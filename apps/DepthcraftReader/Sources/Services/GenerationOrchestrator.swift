import Foundation

@MainActor
class GenerationOrchestrator: ObservableObject {
    @Published var progress = GenerationProgress.idle
    @Published var draftCurriculum: Curriculum?
    @Published var output: GenerationOutput?
    
    // Retain partial progress for retry resume
    private var partialLessons: [String: (markdown: String, meta: LessonMeta)] = [:]
    private var partialQuizzes: [String: QuizDocument] = [:]
    
    private let keyStore: APIKeyStore
    
    init(keyStore: APIKeyStore) {
        self.keyStore = keyStore
    }
    
    func startGeneration(request: GenerationRequest) async {
        progress = GenerationProgress(
            phase: .planning,
            currentItem: "Planning curriculum",
            completedItems: 0,
            totalItems: 1,
            error: nil
        )
        
        do {
            let plannerClient = try LLMClientFactory.createClient(config: request.plannerConfig)
            let planner = PlannerService(client: plannerClient, temperature: request.plannerConfig.temperature)
            
            let curriculum = try await planner.plan(
                topic: request.topic,
                locale: request.locale,
                knowledgeLevel: request.knowledgeLevel,
                depthLevel: request.depthLevel
            )
            
            draftCurriculum = curriculum
            
            progress = GenerationProgress(
                phase: .awaitingApproval,
                currentItem: nil,
                completedItems: 1,
                totalItems: 1,
                error: nil
            )
        } catch {
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
        if progress.phase == .writingLessons || progress.phase == .writingQuizzes || progress.phase == .packaging {
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
        
        do {
            let lessonClient = try LLMClientFactory.createClient(config: request.lessonWriterConfig)
            let lessonWriter = LessonWriterService(client: lessonClient, temperature: request.lessonWriterConfig.temperature)
            
            // Skip lessons that are already generated (retry resume)
            let remainingLessons = lessonsToGenerate.filter { lessons[$0.id] == nil }
            let alreadyCompleted = lessonsToGenerate.count - remainingLessons.count
            
            for (index, lesson) in remainingLessons.enumerated() {
                guard let unit = curriculum.units.first(where: { $0.id == lesson.unitId }) else {
                    throw GenerationError.validationFailed("Unit not found for lesson \(lesson.id)")
                }
                
                progress.currentItem = "Writing: \(lesson.title)"
                progress.completedItems = alreadyCompleted + index
                
                let (markdown, meta) = try await lessonWriter.writeLesson(
                    lesson: lesson,
                    unit: unit,
                    curriculum: curriculum
                )
                
                lessons[lesson.id] = (markdown, meta)
                partialLessons = lessons // Save progress for retry
            }
            
            progress.phase = .writingQuizzes
            progress.currentItem = "Writing quizzes"
            progress.completedItems = 0
            
            let quizClient = try LLMClientFactory.createClient(config: request.quizWriterConfig)
            let quizWriter = QuizWriterService(client: quizClient, temperature: request.quizWriterConfig.temperature)
            
            // Skip quizzes that are already generated (retry resume)
            let remainingQuizzes = lessonsToGenerate.filter { quizzes[$0.id] == nil }
            let alreadyCompletedQuizzes = lessonsToGenerate.count - remainingQuizzes.count
            
            for (index, lesson) in remainingQuizzes.enumerated() {
                guard let (markdown, _) = lessons[lesson.id] else {
                    throw GenerationError.validationFailed("Lesson content not found for \(lesson.id)")
                }
                
                progress.currentItem = "Quiz for: \(lesson.title)"
                progress.completedItems = alreadyCompletedQuizzes + index
                
                let quiz = try await quizWriter.writeQuiz(
                    lessonMarkdown: markdown,
                    lesson: lesson
                )
                
                quizzes[lesson.id] = quiz
                partialQuizzes = quizzes // Save progress for retry
            }
            
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
            let packagerRun = RoleRun(
                provider: "anthropic",
                model: "packager-v1",
                ranAt: ISO8601DateFormatter().string(from: Date())
            )
            
            let metadata = GeneratorMetadata(
                planner: plannerRun,
                lessonWriter: lessonRun,
                quizWriter: quizRun,
                packager: packagerRun
            )
            
            let packageURL = try await packager.packageCourse(
                topic: request.topic,
                locale: request.locale,
                curriculum: slicedCurriculum,
                lessons: lessons,
                quizzes: quizzes,
                roleRuns: metadata
            )
            
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
            
            progress = GenerationProgress(
                phase: .completed,
                currentItem: nil,
                completedItems: totalLessons,
                totalItems: totalLessons,
                error: nil
            )
        } catch {
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
    
    func reset() {
        progress = .idle
        draftCurriculum = nil
        output = nil
        partialLessons = [:]
        partialQuizzes = [:]
    }
}
