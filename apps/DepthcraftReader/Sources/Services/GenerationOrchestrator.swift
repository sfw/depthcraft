import Foundation

@MainActor
class GenerationOrchestrator: ObservableObject {
    @Published var progress = GenerationProgress.idle
    @Published var draftCurriculum: Curriculum?
    @Published var output: GenerationOutput?
    
    // Retain partial progress for retry resume
    private var partialLessons: [String: (markdown: String, meta: LessonMeta)] = [:]
    private var partialQuizzes: [String: QuizDocument] = [:]
    private var partialDemos: [String: DemoWriterOutput] = [:]
    
    private let keyStore: APIKeyStore
    let timingLogger = GenerationTimingLogger()
    
    /// Maximum number of lessons to generate concurrently (Perf Slice 2)
    /// Default: 3 lessons in parallel
    /// Each lesson's work (lesson → quiz → demo) runs sequentially to respect dependencies,
    /// but multiple lessons can be in flight concurrently up to this limit.
    /// Product can tune this value to balance speed vs. API rate limits.
    private let maxConcurrentLessons = 3
    
    init(keyStore: APIKeyStore) {
        self.keyStore = keyStore
    }
    
    func startGeneration(request: GenerationRequest) async {
        timingLogger.startRun(topic: request.topic)
        
        progress = GenerationProgress(
            phase: .planning,
            currentItem: "Planning curriculum",
            completedItems: 0,
            totalItems: 1,
            error: nil
        )
        
        do {
            let plannerClient = try LLMClientFactory.createClient(config: request.plannerConfig)
            let planner = PlannerService(
                client: plannerClient,
                temperature: request.plannerConfig.temperature,
                provider: request.plannerConfig.provider,
                model: request.plannerConfig.model
            )
            
            let priorCurriculum: Curriculum?
            if let priorURL = request.extendFromPackageURL {
                let priorCurriculumURL = priorURL.appendingPathComponent("curriculum.json")
                let priorData = try Data(contentsOf: priorCurriculumURL)
                priorCurriculum = try JSONDecoder().decode(Curriculum.self, from: priorData)
            } else {
                priorCurriculum = nil
            }
            
            let maxTokens = ModelCapabilities.maxOutputTokens(
                provider: request.plannerConfig.provider,
                model: request.plannerConfig.model
            )
            
            let curriculum = try await timingLogger.timeStage(
                .planner,
                provider: request.plannerConfig.provider.rawValue,
                model: request.plannerConfig.model,
                maxTokens: maxTokens
            ) {
                try await planner.plan(
                    topic: request.topic,
                    locale: request.locale,
                    knowledgeLevel: request.knowledgeLevel,
                    depthLevel: request.depthLevel,
                    extendingCurriculum: priorCurriculum
                )
            }
            
            if let prior = priorCurriculum {
                let priorUnitIds = Set(prior.units.map(\.id))
                let priorLessonIds = Set(prior.lessons.keys)
                let newUnitIds = Set(curriculum.units.map(\.id))
                let newLessonIds = Set(curriculum.lessons.keys)
                
                let unitCollisions = priorUnitIds.intersection(newUnitIds)
                if !unitCollisions.isEmpty {
                    throw GenerationError.validationFailed(
                        "Planner returned existing unit IDs: \(Array(unitCollisions).sorted().joined(separator: ", ")). Extension must generate only new IDs."
                    )
                }
                
                let lessonCollisions = priorLessonIds.intersection(newLessonIds)
                if !lessonCollisions.isEmpty {
                    throw GenerationError.validationFailed(
                        "Planner returned existing lesson IDs: \(Array(lessonCollisions).sorted().joined(separator: ", ")). Extension must generate only new IDs."
                    )
                }
            }
            
            draftCurriculum = curriculum
            
            progress = GenerationProgress(
                phase: .awaitingApproval,
                currentItem: nil,
                completedItems: 1,
                totalItems: 1,
                error: nil
            )
        } catch {
            timingLogger.failRun()
            progress = GenerationProgress(
                phase: .failed,
                currentItem: nil,
                completedItems: 0,
                totalItems: 1,
                error: error.localizedDescription
            )
        }
    }
    
    func continueGeneration(request: GenerationRequest) async {
        // Re-entrancy guard: if already generating, ignore
        if progress.phase == .writingLessons || progress.phase == .writingQuizzes || progress.phase == .writingDemos || progress.phase == .packaging {
            return
        }
        
        guard var curriculum = draftCurriculum else {
            progress.error = "No draft curriculum to continue from"
            progress.phase = .failed
            return
        }
        
        // Set phase immediately so UI updates even before any await
        let totalLessons = curriculum.units.flatMap { $0.lessonIds }.count
        progress = GenerationProgress(
            phase: .writingLessons,
            currentItem: "Starting generation...",
            completedItems: 0,
            totalItems: totalLessons,
            error: nil
        )
        
        // Stamp approval
        curriculum.status = "approved"
        curriculum.approvedAt = ISO8601DateFormatter().string(from: Date())
        draftCurriculum = curriculum
        
        let unitsToGenerate: [CurriculumUnit]
        let selectedUnitIds: Set<String>
        if let generateUnitIds = request.generateUnitIds {
            unitsToGenerate = curriculum.units.filter { generateUnitIds.contains($0.id) }
            selectedUnitIds = Set(generateUnitIds)
        } else {
            unitsToGenerate = curriculum.units
            selectedUnitIds = Set(curriculum.units.map { $0.id })
        }
        
        let lessonsToGenerate = unitsToGenerate.flatMap { unit in
            unit.lessonIds.compactMap { lessonId in
                curriculum.lessons[lessonId]
            }
        }
        
        let actualTotalLessons = lessonsToGenerate.count
        
        progress = GenerationProgress(
            phase: .writingLessons,
            currentItem: "Writing lessons",
            completedItems: 0,
            totalItems: actualTotalLessons,
            error: nil
        )
        
        // Resume from partial progress if available
        var lessons = partialLessons
        var quizzes = partialQuizzes
        var demos = partialDemos
        
        do {
            let lessonClient = try LLMClientFactory.createClient(config: request.lessonWriterConfig)
            let lessonWriter = LessonWriterService(
                client: lessonClient,
                temperature: request.lessonWriterConfig.temperature,
                topic: request.topic,
                locale: request.locale,
                knowledgeLevel: request.knowledgeLevel,
                depthLevel: request.depthLevel,
                provider: request.lessonWriterConfig.provider,
                model: request.lessonWriterConfig.model,
                timingLogger: timingLogger
            )
            
            // Prepare all generation services upfront
            let lessonMaxTokens = ModelCapabilities.maxOutputTokens(
                provider: request.lessonWriterConfig.provider,
                model: request.lessonWriterConfig.model
            )
            
            let quizClient = try LLMClientFactory.createClient(config: request.quizWriterConfig)
            let quizWriter = QuizWriterService(
                client: quizClient,
                temperature: request.quizWriterConfig.temperature,
                topic: request.topic,
                knowledgeLevel: request.knowledgeLevel,
                depthLevel: request.depthLevel,
                provider: request.quizWriterConfig.provider,
                model: request.quizWriterConfig.model
            )
            
            let quizMaxTokens = ModelCapabilities.maxOutputTokens(
                provider: request.quizWriterConfig.provider,
                model: request.quizWriterConfig.model
            )
            
            let demoClient = try LLMClientFactory.createClient(config: request.demoWriterConfig)
            let demoWriter = DemoWriterService(
                client: demoClient,
                temperature: request.demoWriterConfig.temperature,
                topic: request.topic,
                knowledgeLevel: request.knowledgeLevel,
                depthLevel: request.depthLevel,
                provider: request.demoWriterConfig.provider,
                model: request.demoWriterConfig.model
            )
            
            let demoMaxTokens = ModelCapabilities.maxOutputTokens(
                provider: request.demoWriterConfig.provider,
                model: request.demoWriterConfig.model
            )
            
            // Generate lessons, quizzes, and demos in parallel with bounded concurrency
            // Retry-friendly: each lesson checks partial state and skips completed stages
            try await self.generateLessonsInParallel(
                lessonsToGenerate: lessonsToGenerate,
                curriculum: curriculum,
                request: request,
                lessonWriter: lessonWriter,
                lessonMaxTokens: lessonMaxTokens,
                quizWriter: quizWriter,
                quizMaxTokens: quizMaxTokens,
                demoWriter: demoWriter,
                demoMaxTokens: demoMaxTokens,
                lessons: &lessons,
                quizzes: &quizzes,
                demos: &demos
            )
            
            progress.phase = .packaging
            progress.currentItem = "Packaging course"
            progress.completedItems = totalLessons
            
            // Slice curriculum to only selected units before packaging
            // Product lock: built package = only what learner can study (no draft stubs)
            // If generateUnitIds is subset, unselected units are NOT in the package at all
            let selectedUnits = curriculum.units.filter { selectedUnitIds.contains($0.id) }
            let selectedLessonIds = Set(selectedUnits.flatMap { $0.lessonIds })
            let selectedLessons = curriculum.lessons.filter { selectedLessonIds.contains($0.key) }
            
            let slicedCurriculum = Curriculum(
                schemaVersion: curriculum.schemaVersion,
                status: curriculum.status,
                approvedAt: curriculum.approvedAt,
                units: selectedUnits,
                lessons: selectedLessons
            )
            
            let packager = PackagerService()
            let plannerRun = RoleRun(
                provider: request.plannerConfig.provider.rawValue,
                model: request.plannerConfig.model,
                ranAt: ISO8601DateFormatter().string(from: Date())
            )
            let lessonRun = RoleRun(
                provider: request.lessonWriterConfig.provider.rawValue,
                model: request.lessonWriterConfig.model,
                ranAt: ISO8601DateFormatter().string(from: Date())
            )
            let quizRun = RoleRun(
                provider: request.quizWriterConfig.provider.rawValue,
                model: request.quizWriterConfig.model,
                ranAt: ISO8601DateFormatter().string(from: Date())
            )
            let totalDemosEmitted = demos.values.reduce(0) { $0 + $1.demos.count }
            let demoRun = DemoRun(
                provider: request.demoWriterConfig.provider.rawValue,
                model: request.demoWriterConfig.model,
                ranAt: ISO8601DateFormatter().string(from: Date()),
                demosEmitted: totalDemosEmitted
            )
            let packagerRun = RoleRun(
                provider: "anthropic",
                model: "packager-v1",
                ranAt: ISO8601DateFormatter().string(from: Date())
            )
            
            let metadata = GeneratorMetadata(
                planner: plannerRun,
                lessonWriter: lessonRun,
                quizWriter: quizRun,
                demoWriter: demoRun,
                packager: packagerRun
            )
            
            let packageURL = try await timingLogger.timeStage(
                .packager,
                provider: "anthropic",
                model: "packager-v1"
            ) {
                try await packager.packageCourse(
                    topic: request.topic,
                    locale: request.locale,
                    curriculum: slicedCurriculum,
                    lessons: lessons,
                    quizzes: quizzes,
                    demos: demos,
                    roleRuns: metadata,
                    extendFrom: request.extendFromPackageURL
                )
            }
            
            let manifestURL = packageURL.appendingPathComponent("manifest.json")
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PackageManifest.self, from: manifestData)
            
            let curriculumURL = packageURL.appendingPathComponent("curriculum.json")
            let curriculumData = try Data(contentsOf: curriculumURL)
            let finalCurriculum = try JSONDecoder().decode(Curriculum.self, from: curriculumData)
            
            output = GenerationOutput(
                packageURL: packageURL,
                manifest: manifest,
                curriculum: finalCurriculum
            )
            
            timingLogger.completeRun()
            
            progress = GenerationProgress(
                phase: .completed,
                currentItem: nil,
                completedItems: totalLessons,
                totalItems: totalLessons,
                error: nil
            )
        } catch {
            timingLogger.failRun()
            
            progress = GenerationProgress(
                phase: .failed,
                currentItem: nil,
                completedItems: progress.completedItems,
                totalItems: totalLessons,
                error: error.localizedDescription
            )
            
            // Keep partial progress for retry (don't clear)
        }
    }
    
    /// Generate lessons, quizzes, and demos in parallel with bounded concurrency
    /// Each lesson's work (lesson → quiz → demo) runs sequentially, but multiple lessons run in parallel
    /// Retry-friendly: checks partial state and only generates missing stages per lesson
    private func generateLessonsInParallel(
        lessonsToGenerate: [CurriculumLesson],
        curriculum: Curriculum,
        request: GenerationRequest,
        lessonWriter: LessonWriterService,
        lessonMaxTokens: Int,
        quizWriter: QuizWriterService,
        quizMaxTokens: Int,
        demoWriter: DemoWriterService,
        demoMaxTokens: Int,
        lessons: inout [String: (markdown: String, meta: LessonMeta)],
        quizzes: inout [String: QuizDocument],
        demos: inout [String: DemoWriterOutput]
    ) async throws {
        // Count completed lessons (all 3 stages done)
        let initialCompleted = lessonsToGenerate.filter { lesson in
            lessons[lesson.id] != nil && quizzes[lesson.id] != nil && demos[lesson.id] != nil
        }.count
        let completedCount = ThreadSafeCounter(initialValue: initialCompleted)
        
        // Use a semaphore to limit concurrency
        let semaphore = AsyncSemaphore(maxCount: maxConcurrentLessons)
        
        // Use non-throwing TaskGroup - results always carry partial stages + optional error
        var firstError: Error?
        
        await withTaskGroup(of: LessonGenerationResult.self) { group in
            // Spawn tasks for all lessons (they check partial state internally)
            for lesson in lessonsToGenerate {
                // Snapshot existing state BEFORE addTask to avoid reading inout from child task
                let existingLesson = lessons[lesson.id]
                let existingQuiz = quizzes[lesson.id]
                let existingDemo = demos[lesson.id]
                
                // Check if this lesson is fully complete (all stages done)
                let isFullyComplete = existingLesson != nil && existingQuiz != nil && existingDemo != nil
                
                if isFullyComplete {
                    // All stages complete, nothing to do - skip task entirely
                    continue
                }
                
                group.addTask {
                    // Wait for semaphore slot
                    await semaphore.wait()
                    defer { await semaphore.signal() }
                    
                    // Generate missing stages for this lesson
                    // Returns partial result with completed stages even if mid-lesson failure occurs
                    return await self.generateSingleLesson(
                        lesson: lesson,
                        curriculum: curriculum,
                        request: request,
                        lessonWriter: lessonWriter,
                        lessonMaxTokens: lessonMaxTokens,
                        quizWriter: quizWriter,
                        quizMaxTokens: quizMaxTokens,
                        demoWriter: demoWriter,
                        demoMaxTokens: demoMaxTokens,
                        existingLesson: existingLesson,
                        existingQuiz: existingQuiz,
                        existingDemo: existingDemo,
                        completedCount: completedCount
                    )
                }
            }
            
            // Collect all results and merge partial stages (even from failed tasks)
            for await lessonResult in group {
                // Merge any newly generated stages (partial or complete)
                if let (markdown, meta) = lessonResult.lesson {
                    lessons[lessonResult.lessonId] = (markdown, meta)
                }
                if let quiz = lessonResult.quiz {
                    quizzes[lessonResult.lessonId] = quiz
                }
                if let demo = lessonResult.demo {
                    demos[lessonResult.lessonId] = demo
                }
                
                // Persist partials incrementally (critical for retry)
                partialLessons = lessons
                partialQuizzes = quizzes
                partialDemos = demos
                
                // Capture first error (but continue merging all partial work)
                if let error = lessonResult.error, firstError == nil {
                    firstError = error
                }
            }
        }
        
        // After collecting all results, save final partial state and throw if any failed
        partialLessons = lessons
        partialQuizzes = quizzes
        partialDemos = demos
        
        if let error = firstError {
            throw error
        }
    }
    
    /// Generate a single lesson's complete content (lesson write → quiz → demo)
    /// Retry-friendly: skips stages that already exist in partial state
    /// Returns partial result with completed stages even on mid-lesson failure
    /// Respects dependencies: lesson before quiz/demo
    /// Never throws - always returns result with optional error
    private func generateSingleLesson(
        lesson: CurriculumLesson,
        curriculum: Curriculum,
        request: GenerationRequest,
        lessonWriter: LessonWriterService,
        lessonMaxTokens: Int,
        quizWriter: QuizWriterService,
        quizMaxTokens: Int,
        demoWriter: DemoWriterService,
        demoMaxTokens: Int,
        existingLesson: (markdown: String, meta: LessonMeta)?,
        existingQuiz: QuizDocument?,
        existingDemo: DemoWriterOutput?,
        completedCount: ThreadSafeCounter
    ) async -> LessonGenerationResult {
        guard let unit = curriculum.units.first(where: { $0.id == lesson.unitId }) else {
            return LessonGenerationResult(
                lessonId: lesson.id,
                lesson: nil,
                quiz: nil,
                demo: nil,
                error: GenerationError.validationFailed("Unit not found for lesson \(lesson.id)")
            )
        }
        
        var newLesson: (markdown: String, meta: LessonMeta)? = nil
        var newQuiz: QuizDocument? = nil
        var newDemo: DemoWriterOutput? = nil
        var capturedError: Error? = nil
        
        // 1. Write lesson (or reuse existing)
        let markdown: String
        let meta: LessonMeta
        if let existing = existingLesson {
            markdown = existing.markdown
            meta = existing.meta
        } else {
            await updateProgress(phase: .writingLessons, item: "Writing: \(lesson.title)", completed: completedCount.value)
            
            do {
                let generated = try await timingLogger.timeStage(
                    .lessonWrite,
                    lessonId: lesson.id,
                    provider: request.lessonWriterConfig.provider.rawValue,
                    model: request.lessonWriterConfig.model,
                    maxTokens: lessonMaxTokens
                ) {
                    try await lessonWriter.writeLesson(
                        lesson: lesson,
                        unit: unit,
                        curriculum: curriculum
                    )
                }
                
                markdown = generated.0
                meta = generated.1
                newLesson = (markdown, meta)
            } catch {
                // Lesson write failed - return immediately with error, no stages completed
                return LessonGenerationResult(
                    lessonId: lesson.id,
                    lesson: nil,
                    quiz: nil,
                    demo: nil,
                    error: error
                )
            }
        }
        
        // 2. Write quiz (or reuse existing) - needs lesson markdown
        if let existing = existingQuiz {
            newQuiz = nil // Reused, not newly generated
        } else {
            await updateProgress(phase: .writingQuizzes, item: "Quiz for: \(lesson.title)", completed: completedCount.value)
            
            do {
                let generated = try await timingLogger.timeStage(
                    .quiz,
                    lessonId: lesson.id,
                    provider: request.quizWriterConfig.provider.rawValue,
                    model: request.quizWriterConfig.model,
                    maxTokens: quizMaxTokens
                ) {
                    try await quizWriter.writeQuiz(
                        lessonMarkdown: markdown,
                        lesson: lesson,
                        unit: unit
                    )
                }
                
                newQuiz = generated
            } catch {
                // Quiz failed but lesson succeeded - return partial with error
                capturedError = error
                // Don't attempt demo if quiz failed
                return LessonGenerationResult(
                    lessonId: lesson.id,
                    lesson: newLesson,
                    quiz: nil,
                    demo: nil,
                    error: error
                )
            }
        }
        
        // 3. Write demo (or reuse existing) - needs lesson markdown
        if let existing = existingDemo {
            newDemo = nil // Reused, not newly generated
        } else {
            await updateProgress(phase: .writingDemos, item: "Checking: \(lesson.title)", completed: completedCount.value)
            
            do {
                let demoOutput = try await timingLogger.timeStage(
                    .demo,
                    lessonId: lesson.id,
                    provider: request.demoWriterConfig.provider.rawValue,
                    model: request.demoWriterConfig.model,
                    maxTokens: demoMaxTokens
                ) {
                    try await demoWriter.writeDemos(
                        lessonMarkdown: markdown,
                        lesson: lesson,
                        unit: unit
                    )
                }
                
                newDemo = demoOutput ?? DemoWriterOutput(demos: [])
            } catch {
                // Demo failed but lesson + quiz succeeded - return partial with error
                return LessonGenerationResult(
                    lessonId: lesson.id,
                    lesson: newLesson,
                    quiz: newQuiz,
                    demo: nil,
                    error: error
                )
            }
        }
        
        // Increment completed count only if we did actual work
        if newLesson != nil || newQuiz != nil || newDemo != nil {
            await completedCount.increment()
        }
        
        // Success - return all newly generated stages (collector merges into main dictionaries)
        return LessonGenerationResult(
            lessonId: lesson.id,
            lesson: newLesson,
            quiz: newQuiz,
            demo: newDemo,
            error: nil
        )
    }
    
    /// Update progress UI safely from background tasks
    private func updateProgress(phase: GenerationPhase, item: String, completed: Int) {
        Task { @MainActor in
            // Only update if we're still in a generation phase (not failed/cancelled)
            if progress.phase == .writingLessons || progress.phase == .writingQuizzes || progress.phase == .writingDemos {
                progress.phase = phase
                progress.currentItem = item
                progress.completedItems = completed
            }
        }
    }
    
    func reset() {
        progress = .idle
        draftCurriculum = nil
        output = nil
        partialLessons = [:]
        partialQuizzes = [:]
        partialDemos = [:]
        timingLogger.reset()
    }
}

// MARK: - Helper Types for Parallel Generation

/// Result of generating a single lesson's content (may be partial if mid-lesson failure)
/// Only newly generated stages are non-nil; existing stages remain nil in result
/// If error is present, partial stages were completed before failure
private struct LessonGenerationResult {
    let lessonId: String
    let lesson: (markdown: String, meta: LessonMeta)?
    let quiz: QuizDocument?
    let demo: DemoWriterOutput?
    let error: Error?
}

/// Thread-safe counter for tracking completion across parallel tasks
private actor ThreadSafeCounter {
    private var count: Int
    
    init(initialValue: Int = 0) {
        self.count = initialValue
    }
    
    var value: Int {
        count
    }
    
    func increment() {
        count += 1
    }
}

/// Simple async semaphore for limiting concurrency
private actor AsyncSemaphore {
    private let maxCount: Int
    private var currentCount: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    
    init(maxCount: Int) {
        self.maxCount = maxCount
        self.currentCount = 0
    }
    
    func wait() async {
        if currentCount < maxCount {
            currentCount += 1
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }
    
    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            currentCount = max(0, currentCount - 1)
        }
    }
}
