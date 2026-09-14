import Foundation

@MainActor
class GenerationOrchestrator: ObservableObject {
    @Published var progress = GenerationProgress.idle
    @Published var draftCurriculum: Curriculum?
    @Published var output: GenerationOutput?
    @Published var hasCheckpointAvailable = false
    
    // Retain partial progress for retry resume
    private var partialLessons: [String: (markdown: String, meta: LessonMeta)] = [:]
    private var partialQuizzes: [String: QuizDocument] = [:]
    private var partialDemos: [String: DemoWriterOutput] = [:]
    
    private let keyStore: APIKeyStore
    private let customEndpointsStore: CustomEndpointsStore
    let timingLogger = GenerationTimingLogger()
    
    /// Maximum number of lessons to generate concurrently (Perf Slice 2)
    /// Default: 3 lessons in parallel
    /// Each lesson's work (lesson → quiz → demo) runs sequentially to respect dependencies,
    /// but multiple lessons can be in flight concurrently up to this limit.
    /// Product can tune this value to balance speed vs. API rate limits.
    private let maxConcurrentLessons = 3
    
    /// Background generation support with checkpointing
    let backgroundManager = BackgroundGenerationManager()
    private let checkpointManager = CheckpointManager()
    
    /// Store the last request for notifications
    private var activeRequest: GenerationRequest?
    
    /// Track when generation started (for checkpoint persistence)
    private var generationStartedAt: Date?
    
    init(keyStore: APIKeyStore, customEndpointsStore: CustomEndpointsStore) {
        self.keyStore = keyStore
        self.customEndpointsStore = customEndpointsStore
        
        // Check for existing checkpoint on init and peek completed/total for resume UI
        if let checkpoint = checkpointManager.loadCheckpoint() {
            hasCheckpointAvailable = true
            // Peek completed/total so resume banner can show N/M before user taps
            progress = GenerationProgress(
                phase: .idle,
                currentItem: nil,
                completedItems: checkpoint.completedItems,
                totalItems: checkpoint.totalItems,
                error: nil,
                lessonProgress: [:]
            )
            print("✓ Checkpoint detected on init - ready to resume (\(checkpoint.completedItems)/\(checkpoint.totalItems) lessons)")
        }
    }
    
    /// Restore generation state from checkpoint (call to resume from process death or app restart)
    func restoreFromCheckpoint() -> GenerationRequest? {
        guard let checkpoint = checkpointManager.loadCheckpoint() else {
            hasCheckpointAvailable = false
            return nil
        }
        
        // Restore curriculum
        draftCurriculum = checkpoint.curriculum
        
        // Restore partial progress
        partialLessons = checkpoint.partialLessons.mapValues { ($0.markdown, $0.meta) }
        partialQuizzes = checkpoint.partialQuizzes
        partialDemos = checkpoint.partialDemos
        
        // Restore generation start time
        generationStartedAt = checkpoint.startedAt
        
        // Restore progress state - branch on checkpoint phase
        let checkpointPhase = GenerationPhase(rawValue: checkpoint.phase) ?? .idle
        
        if checkpointPhase == .awaitingApproval {
            // Checkpoint was awaiting approval - restore to that state (show editor, don't auto-continue)
            progress = GenerationProgress(
                phase: .awaitingApproval,
                currentItem: nil,
                completedItems: checkpoint.completedItems,
                totalItems: checkpoint.totalItems,
                error: nil,
                lessonProgress: [:]
            )
        } else {
            // Checkpoint was mid-generation or post-approval - restore to .idle so continueGeneration can proceed
            // DO NOT restore checkpoint's phase (could be .writingLessons etc) which would trigger re-entrancy guard
            progress = GenerationProgress(
                phase: .idle,
                currentItem: nil,
                completedItems: checkpoint.completedItems,
                totalItems: checkpoint.totalItems,
                error: nil,
                lessonProgress: [:]  // Will be re-initialized in continueGeneration
            )
        }
        
        // Reconstruct request (API keys from keyStore, temperatures from global settings)
        guard let curriculum = checkpoint.curriculum else {
            print("⚠️ Checkpoint has no curriculum")
            return nil
        }
        
        // Helper to reconstruct LLMConfiguration from checkpoint
        func buildConfig(
            provider: LLMProvider,
            model: String,
            customEndpointId: String?,
            customBaseURL: String?
        ) throws -> LLMConfiguration {
            if provider == .custom {
                // Custom endpoint - need to get key and baseURL
                var apiKey: String?
                var baseURL: String?
                
                // Try to find endpoint by ID first
                if let endpointIdString = customEndpointId,
                   let endpointId = UUID(uuidString: endpointIdString),
                   let endpoint = customEndpointsStore.getEndpoint(id: endpointId) {
                    apiKey = try? customEndpointsStore.getKey(for: endpoint)
                    baseURL = endpoint.baseURL
                }
                
                // Fallback to baseURL lookup or legacy storage
                if apiKey == nil, let customBaseURL = customBaseURL {
                    // Try to find endpoint by baseURL
                    if let endpoint = customEndpointsStore.endpoints.first(where: { $0.baseURL == customBaseURL }) {
                        apiKey = try? customEndpointsStore.getKey(for: endpoint)
                        baseURL = endpoint.baseURL
                    } else {
                        // Legacy: try old .custom keychain location (for in-flight checkpoints from pre-#59)
                        apiKey = try? keyStore.getKey(for: .custom)
                        baseURL = customBaseURL
                    }
                }
                
                guard let apiKey = apiKey, !apiKey.isEmpty else {
                    throw NSError(domain: "GenerationOrchestrator", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Missing API key for custom endpoint"
                    ])
                }
                guard let baseURL = baseURL, !baseURL.isEmpty else {
                    throw NSError(domain: "GenerationOrchestrator", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Missing base URL for custom endpoint"
                    ])
                }
                
                return LLMConfiguration(
                    provider: .custom,
                    model: model,
                    apiKey: apiKey,
                    temperature: keyStore.getGlobalTemperature(),
                    customBaseURL: baseURL
                )
            } else {
                // Fixed provider
                guard let apiKey = try? keyStore.getKey(for: provider), !apiKey.isEmpty else {
                    throw NSError(domain: "GenerationOrchestrator", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Missing API key for provider: \(provider.rawValue)"
                    ])
                }
                
                return LLMConfiguration(
                    provider: provider,
                    model: model,
                    apiKey: apiKey,
                    temperature: keyStore.getGlobalTemperature()
                )
            }
        }
        
        let plannerProvider = LLMProvider(rawValue: checkpoint.plannerProvider) ?? .anthropic
        let lessonWriterProvider = LLMProvider(rawValue: checkpoint.lessonWriterProvider) ?? .anthropic
        let quizWriterProvider = LLMProvider(rawValue: checkpoint.quizWriterProvider) ?? .anthropic
        let demoWriterProvider = LLMProvider(rawValue: checkpoint.demoWriterProvider) ?? .anthropic
        
        // Build configurations with custom endpoint support
        let plannerConfig: LLMConfiguration
        let lessonWriterConfig: LLMConfiguration
        let quizWriterConfig: LLMConfiguration
        let demoWriterConfig: LLMConfiguration
        
        do {
            plannerConfig = try buildConfig(
                provider: plannerProvider,
                model: checkpoint.plannerModel,
                customEndpointId: checkpoint.plannerCustomEndpointId,
                customBaseURL: checkpoint.plannerCustomBaseURL
            )
            
            lessonWriterConfig = try buildConfig(
                provider: lessonWriterProvider,
                model: checkpoint.lessonWriterModel,
                customEndpointId: checkpoint.lessonWriterCustomEndpointId,
                customBaseURL: checkpoint.lessonWriterCustomBaseURL
            )
            
            quizWriterConfig = try buildConfig(
                provider: quizWriterProvider,
                model: checkpoint.quizWriterModel,
                customEndpointId: checkpoint.quizWriterCustomEndpointId,
                customBaseURL: checkpoint.quizWriterCustomBaseURL
            )
            
            demoWriterConfig = try buildConfig(
                provider: demoWriterProvider,
                model: checkpoint.demoWriterModel,
                customEndpointId: checkpoint.demoWriterCustomEndpointId,
                customBaseURL: checkpoint.demoWriterCustomBaseURL
            )
        } catch {
            print("⚠️ Failed to build configurations from checkpoint: \(error.localizedDescription)")
            checkpointManager.clearCheckpoint()
            hasCheckpointAvailable = false
            return nil
        }
        
        let request = GenerationRequest(
            topic: checkpoint.topic,
            locale: checkpoint.locale,
            plannerConfig: plannerConfig,
            lessonWriterConfig: lessonWriterConfig,
            quizWriterConfig: quizWriterConfig,
            demoWriterConfig: demoWriterConfig,
            generateUnitIds: checkpoint.generateUnitIds,
            knowledgeLevel: KnowledgeLevel(rawValue: checkpoint.knowledgeLevel) ?? .some,
            depthLevel: DepthLevel(rawValue: checkpoint.depthLevel) ?? .standard,
            extendFromPackageURL: checkpoint.extendFromPackageURL
        )
        
        hasCheckpointAvailable = true
        print("✓ Restored from checkpoint: \(checkpoint.completedItems)/\(checkpoint.totalItems) lessons")
        
        return request
    }
    
    /// Save current state to checkpoint
    private func saveCheckpoint() {
        guard let request = activeRequest,
              let curriculum = draftCurriculum else {
            return
        }
        
        // Helper to extract custom endpoint info from LLMConfiguration
        func getCustomEndpointInfo(_ config: LLMConfiguration) -> (id: String?, baseURL: String?) {
            if config.provider == .custom, let baseURL = config.customBaseURL {
                // Try to find matching endpoint by baseURL
                if let endpoint = customEndpointsStore.endpoints.first(where: { $0.baseURL == baseURL }) {
                    return (endpoint.id.uuidString, baseURL)
                }
                // Fallback: just store the baseURL for legacy compatibility
                return (nil, baseURL)
            }
            return (nil, nil)
        }
        
        let plannerEndpoint = getCustomEndpointInfo(request.plannerConfig)
        let lessonWriterEndpoint = getCustomEndpointInfo(request.lessonWriterConfig)
        let quizWriterEndpoint = getCustomEndpointInfo(request.quizWriterConfig)
        let demoWriterEndpoint = getCustomEndpointInfo(request.demoWriterConfig)
        
        let checkpoint = GenerationCheckpoint(
            topic: request.topic,
            locale: request.locale,
            knowledgeLevel: request.knowledgeLevel.rawValue,
            depthLevel: request.depthLevel.rawValue,
            generateUnitIds: request.generateUnitIds,
            extendFromPackageURL: request.extendFromPackageURL,
            plannerProvider: request.plannerConfig.provider.rawValue,
            plannerModel: request.plannerConfig.model,
            plannerCustomEndpointId: plannerEndpoint.id,
            plannerCustomBaseURL: plannerEndpoint.baseURL,
            lessonWriterProvider: request.lessonWriterConfig.provider.rawValue,
            lessonWriterModel: request.lessonWriterConfig.model,
            lessonWriterCustomEndpointId: lessonWriterEndpoint.id,
            lessonWriterCustomBaseURL: lessonWriterEndpoint.baseURL,
            quizWriterProvider: request.quizWriterConfig.provider.rawValue,
            quizWriterModel: request.quizWriterConfig.model,
            quizWriterCustomEndpointId: quizWriterEndpoint.id,
            quizWriterCustomBaseURL: quizWriterEndpoint.baseURL,
            demoWriterProvider: request.demoWriterConfig.provider.rawValue,
            demoWriterModel: request.demoWriterConfig.model,
            demoWriterCustomEndpointId: demoWriterEndpoint.id,
            demoWriterCustomBaseURL: demoWriterEndpoint.baseURL,
            phase: progress.phase.rawValue,
            curriculum: curriculum,
            completedItems: progress.completedItems,
            totalItems: progress.totalItems,
            partialLessons: partialLessons.mapValues { 
                GenerationCheckpoint.PartialLessonData(markdown: $0.markdown, meta: $0.meta)
            },
            partialQuizzes: partialQuizzes,
            partialDemos: partialDemos,
            startedAt: generationStartedAt ?? Date(),
            lastUpdatedAt: Date()
        )
        
        checkpointManager.saveCheckpoint(checkpoint)
        hasCheckpointAvailable = true
    }
    
    func startGeneration(request: GenerationRequest) async {
        activeRequest = request
        generationStartedAt = Date()
        timingLogger.startRun(topic: request.topic)
        
        // Request notification permission and begin background task
        await backgroundManager.requestNotificationPermission()
        backgroundManager.beginBackgroundTask(name: "course-generation")
        
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
            
            // Save checkpoint after planning
            saveCheckpoint()
        } catch {
            timingLogger.failRun()
            backgroundManager.endBackgroundTask()
            
            // Save checkpoint on planning failure
            saveCheckpoint()
            
            // Post failure notification
            if let request = activeRequest {
                backgroundManager.postFailureNotification(topic: request.topic, error: error.localizedDescription)
            }
            
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
        
        activeRequest = request
        
        // Ensure background task is active (may have been stopped if user returned to foreground)
        backgroundManager.beginBackgroundTask(name: "course-generation")
        
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
        
        // Initialize per-lesson progress tracking
        var lessonProgressDict: [String: LessonGenerationProgress] = [:]
        var initialCompletedCount = 0
        
        for lesson in lessonsToGenerate {
            let existingLesson = partialLessons[lesson.id]
            let existingQuiz = partialQuizzes[lesson.id]
            let existingDemo = partialDemos[lesson.id]
            
            // Only fully complete lessons (all 3 stages done) are marked .done
            // Incomplete lessons start as .queued until a worker claims them
            let stage: LessonStage
            if existingLesson != nil && existingQuiz != nil && existingDemo != nil {
                stage = .done
                initialCompletedCount += 1
            } else {
                stage = .queued
            }
            
            lessonProgressDict[lesson.id] = LessonGenerationProgress(
                lessonId: lesson.id,
                lessonTitle: lesson.title,
                stage: stage,
                error: nil
            )
        }
        
        progress = GenerationProgress(
            phase: .writingLessons,
            currentItem: "Writing lessons",
            completedItems: initialCompletedCount,
            totalItems: actualTotalLessons,
            error: nil,
            lessonProgress: lessonProgressDict
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
            
            // Check if we have mixed Done/Failed lessons after generation
            let completedLessonIds = Set(lessonsToGenerate.compactMap { lesson in
                let hasAll = lessons[lesson.id] != nil && quizzes[lesson.id] != nil && demos[lesson.id] != nil
                return hasAll ? lesson.id : nil
            })
            let completedCount = completedLessonIds.count
            let failedCount = actualTotalLessons - completedCount
            
            // Explicit branch for mixed Done/Failed (happy-path with some failures)
            if failedCount > 0 {
                // Package partial success - filter to only completed lessons
                progress.phase = .packaging
                progress.currentItem = "Packaging \(completedCount) successful lessons"
                progress.completedItems = completedCount
                
                let selectedUnits = curriculum.units.filter { selectedUnitIds.contains($0.id) }
                
                // Filter units to only include completed lesson IDs and remove empty units
                let filteredUnits = selectedUnits.compactMap { unit -> CurriculumUnit? in
                    let completedLessonIdsInUnit = unit.lessonIds.filter { completedLessonIds.contains($0) }
                    guard !completedLessonIdsInUnit.isEmpty else { return nil }
                    return CurriculumUnit(
                        id: unit.id,
                        title: unit.title,
                        order: unit.order,
                        lessonIds: completedLessonIdsInUnit
                    )
                }
                
                let completedLessons = curriculum.lessons.filter { completedLessonIds.contains($0.key) }
                
                let slicedCurriculum = Curriculum(
                    schemaVersion: curriculum.schemaVersion,
                    status: curriculum.status,
                    approvedAt: curriculum.approvedAt,
                    units: filteredUnits,
                    lessons: completedLessons
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
                    provider: nil,
                    model: nil
                ) {
                    try await packager.packageCourse(
                        topic: request.topic,
                        locale: request.locale,
                        curriculum: slicedCurriculum,
                        lessons: lessons,
                        quizzes: quizzes,
                        demos: demos,
                        roleRuns: metadata,
                        extendFrom: request.extendFromPackageURL,
                        plannedCurriculum: curriculum,
                        knowledgeLevel: request.knowledgeLevel,
                        depthLevel: request.depthLevel
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
                
                // Mark as completed with failures - keep lessonProgress to show failed lessons
                progress = GenerationProgress(
                    phase: .completed,
                    currentItem: nil,
                    completedItems: completedCount,
                    totalItems: actualTotalLessons,
                    error: "\(failedCount) lesson(s) failed",
                    lessonProgress: progress.lessonProgress
                )
                
                // Don't clear checkpoint - user can still retry failed lessons
                saveCheckpoint()
                
                // End background task
                backgroundManager.endBackgroundTask()
            } else {
                // All lessons succeeded - normal happy path
                progress.phase = .packaging
                progress.currentItem = "Packaging course"
                progress.completedItems = actualTotalLessons
                
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
                    provider: nil,
                    model: nil
                ) {
                    try await packager.packageCourse(
                        topic: request.topic,
                        locale: request.locale,
                        curriculum: slicedCurriculum,
                        lessons: lessons,
                        quizzes: quizzes,
                        demos: demos,
                        roleRuns: metadata,
                        extendFrom: request.extendFromPackageURL,
                        plannedCurriculum: nil,
                        knowledgeLevel: request.knowledgeLevel,
                        depthLevel: request.depthLevel
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
                backgroundManager.endBackgroundTask()
                
                // Clear checkpoint on successful completion
                checkpointManager.clearCheckpoint()
                hasCheckpointAvailable = false
                
                // Post completion notification
                if let request = activeRequest {
                    let durationMs = timingLogger.currentLog?.effectiveTotalDurationMs
                    backgroundManager.postCompletionNotification(
                        topic: request.topic,
                        totalLessons: actualTotalLessons,
                        durationMs: durationMs
                    )
                }
                
                progress = GenerationProgress(
                    phase: .completed,
                    currentItem: nil,
                    completedItems: actualTotalLessons,
                    totalItems: actualTotalLessons,
                    error: nil
                )
            }
        } catch {
            // Complete failure - no lessons succeeded (generateLessonsInParallel threw)
            timingLogger.failRun()
            backgroundManager.endBackgroundTask()
            saveCheckpoint()
            
            if let request = activeRequest {
                backgroundManager.postFailureNotification(topic: request.topic, error: error.localizedDescription)
            }
            
            progress = GenerationProgress(
                phase: .failed,
                currentItem: nil,
                completedItems: progress.completedItems,
                totalItems: actualTotalLessons,
                error: error.localizedDescription,
                lessonProgress: progress.lessonProgress
            )
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
                    
                    // Generate missing stages for this lesson
                    // Returns partial result with completed stages even if mid-lesson failure occurs
                    let result = await self.generateSingleLesson(
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
                    
                    // Release semaphore slot (structured same-task release)
                    await semaphore.signal()
                    return result
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
                
                // Persist partials incrementally (critical for retry and process death survival)
                partialLessons = lessons
                partialQuizzes = quizzes
                partialDemos = demos
                
                // Save checkpoint after each lesson completes (survives process death)
                saveCheckpoint()
                
                // Capture first error (but continue merging all partial work)
                if let error = lessonResult.error, firstError == nil {
                    firstError = error
                }
            }
        }
        
        // After collecting all results, save final partial state
        partialLessons = lessons
        partialQuizzes = quizzes
        partialDemos = demos
        
        // Only throw if NO lessons succeeded (complete failure)
        // If some succeeded, we'll package partial success
        let successfulLessonsCount = lessonsToGenerate.filter { lesson in
            lessons[lesson.id] != nil && quizzes[lesson.id] != nil && demos[lesson.id] != nil
        }.count
        
        if successfulLessonsCount == 0 && firstError != nil {
            throw firstError!
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
        
        // 1. Write lesson (or reuse existing)
        let markdown: String
        let meta: LessonMeta
        if let existing = existingLesson {
            markdown = existing.markdown
            meta = existing.meta
        } else {
            await updateLessonStage(lessonId: lesson.id, stage: .writing)
            await updateProgress(phase: .writingLessons, item: "Writing: \(lesson.title)", completed: completedCount.value)
            
            let timingId = await timingLogger.startStage(
                .lessonWrite,
                lessonId: lesson.id,
                provider: request.lessonWriterConfig.provider.rawValue,
                model: request.lessonWriterConfig.model,
                maxTokens: lessonMaxTokens
            )
            
            do {
                let generated = try await lessonWriter.writeLesson(
                    lesson: lesson,
                    unit: unit,
                    curriculum: curriculum
                )
                
                markdown = generated.markdown
                meta = generated.meta
                
                // Complete timing with returned metadata
                if let metadata = generated.llmMetadata {
                    await timingLogger.completeStage(
                        timingId,
                        tokensUsed: metadata.tokensUsed,
                        finishReason: metadata.finishReason,
                        requestCharCount: metadata.requestCharCount,
                        responseCharCount: metadata.responseCharCount
                    )
                } else {
                    await timingLogger.completeStage(timingId)
                }
                
                newLesson = (markdown, meta)
            } catch {
                // Lesson write failed - mark timing and stage as failed
                await timingLogger.failStage(timingId, error: error.localizedDescription)
                await updateLessonStage(lessonId: lesson.id, stage: .failed, error: error.localizedDescription)
                
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
            await updateLessonStage(lessonId: lesson.id, stage: .quiz)
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
                // Quiz failed but lesson succeeded - mark as failed and return partial
                await updateLessonStage(lessonId: lesson.id, stage: .failed, error: error.localizedDescription)
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
            await updateLessonStage(lessonId: lesson.id, stage: .demo)
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
                // Demo failed but lesson + quiz succeeded - mark as failed and return partial
                await updateLessonStage(lessonId: lesson.id, stage: .failed, error: error.localizedDescription)
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
        
        // Mark as done on success
        await updateLessonStage(lessonId: lesson.id, stage: .done)
        
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
    
    /// Update per-lesson stage in progress dictionary
    private func updateLessonStage(lessonId: String, stage: LessonStage, error: String? = nil) async {
        await MainActor.run {
            // Only update if we're in an active phase where lessonProgress is valid
            // Allow updates during generation (.writingLessons/Quizzes/Demos) and after partial completion (.completed with failures)
            let allowedPhases: Set<GenerationPhase> = [.writingLessons, .writingQuizzes, .writingDemos, .completed]
            if allowedPhases.contains(progress.phase) {
                if var lessonProgress = progress.lessonProgress[lessonId] {
                    lessonProgress.stage = stage
                    lessonProgress.error = error
                    progress.lessonProgress[lessonId] = lessonProgress
                }
            }
        }
    }
    
    func reset() {
        backgroundManager.endBackgroundTask()
        checkpointManager.clearCheckpoint()
        hasCheckpointAvailable = false
        progress = .idle
        draftCurriculum = nil
        output = nil
        partialLessons = [:]
        partialQuizzes = [:]
        partialDemos = [:]
        timingLogger.reset()
        activeRequest = nil
        generationStartedAt = nil
    }
    
    /// Repackage current completed lessons (called after retry completes)
    private func repackageCompletedLessons() async throws {
        guard let request = activeRequest,
              let curriculum = draftCurriculum else {
            return
        }
        
        let selectedUnitIds: Set<String>
        if let generateUnitIds = request.generateUnitIds {
            selectedUnitIds = Set(generateUnitIds)
        } else {
            selectedUnitIds = Set(curriculum.units.map { $0.id })
        }
        
        let unitsToGenerate = curriculum.units.filter { selectedUnitIds.contains($0.id) }
        let lessonsToGenerate = unitsToGenerate.flatMap { unit in
            unit.lessonIds.compactMap { lessonId in
                curriculum.lessons[lessonId]
            }
        }
        
        // Determine completed lessons
        let completedLessonIds = Set(lessonsToGenerate.compactMap { lesson in
            let hasAll = partialLessons[lesson.id] != nil && partialQuizzes[lesson.id] != nil && partialDemos[lesson.id] != nil
            return hasAll ? lesson.id : nil
        })
        
        let completedCount = completedLessonIds.count
        let totalCount = lessonsToGenerate.count
        let failedCount = totalCount - completedCount
        
        // Filter to only completed lessons
        let selectedUnits = curriculum.units.filter { selectedUnitIds.contains($0.id) }
        let filteredUnits = selectedUnits.compactMap { unit -> CurriculumUnit? in
            let completedLessonIdsInUnit = unit.lessonIds.filter { completedLessonIds.contains($0) }
            guard !completedLessonIdsInUnit.isEmpty else { return nil }
            return CurriculumUnit(
                id: unit.id,
                title: unit.title,
                order: unit.order,
                lessonIds: completedLessonIdsInUnit
            )
        }
        
        let completedLessons = curriculum.lessons.filter { completedLessonIds.contains($0.key) }
        
        let slicedCurriculum = Curriculum(
            schemaVersion: curriculum.schemaVersion,
            status: curriculum.status,
            approvedAt: curriculum.approvedAt,
            units: filteredUnits,
            lessons: completedLessons
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
        let totalDemosEmitted = partialDemos.values.reduce(0) { $0 + $1.demos.count }
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
            provider: nil,
            model: nil
        ) {
            try await packager.packageCourse(
                topic: request.topic,
                locale: request.locale,
                curriculum: slicedCurriculum,
                lessons: partialLessons,
                quizzes: partialQuizzes,
                demos: partialDemos,
                roleRuns: metadata,
                extendFrom: request.extendFromPackageURL,
                plannedCurriculum: curriculum,
                knowledgeLevel: request.knowledgeLevel,
                depthLevel: request.depthLevel
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
        
        // Update progress to reflect current state
        await MainActor.run {
            progress.completedItems = completedCount
            progress.totalItems = totalCount
            if failedCount > 0 {
                progress.error = "\(failedCount) lesson(s) failed"
            } else {
                progress.error = nil
            }
        }
    }
    
    /// Get list of failed lesson IDs
    var failedLessonIds: [String] {
        progress.lessonProgress.values
            .filter { $0.isFailed }
            .map { $0.lessonId }
    }
    
    /// Retry a specific failed lesson
    func retryFailedLesson(lessonId: String) async {
        guard let request = activeRequest,
              let curriculum = draftCurriculum,
              let lessonProgress = progress.lessonProgress[lessonId],
              lessonProgress.isFailed,
              let lesson = curriculum.lessons[lessonId] else {
            return
        }
        
        // Reset lesson stage to queued
        await updateLessonStage(lessonId: lessonId, stage: .queued, error: nil)
        
        // Ensure background task is active
        backgroundManager.beginBackgroundTask(name: "lesson-retry")
        
        // Remove failed lesson's partial data (force regeneration)
        partialLessons.removeValue(forKey: lessonId)
        partialQuizzes.removeValue(forKey: lessonId)
        partialDemos.removeValue(forKey: lessonId)
        
        // Regenerate the lesson
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
            
            let completedCount = ThreadSafeCounter(initialValue: progress.completedItems)
            
            let result = await generateSingleLesson(
                lesson: lesson,
                curriculum: curriculum,
                request: request,
                lessonWriter: lessonWriter,
                lessonMaxTokens: lessonMaxTokens,
                quizWriter: quizWriter,
                quizMaxTokens: quizMaxTokens,
                demoWriter: demoWriter,
                demoMaxTokens: demoMaxTokens,
                existingLesson: nil,
                existingQuiz: nil,
                existingDemo: nil,
                completedCount: completedCount
            )
            
            // Merge result
            if let (markdown, meta) = result.lesson {
                partialLessons[lessonId] = (markdown, meta)
            }
            if let quiz = result.quiz {
                partialQuizzes[lessonId] = quiz
            }
            if let demo = result.demo {
                partialDemos[lessonId] = demo
            }
            
            // Update progress
            progress.completedItems = await completedCount.value
            
            // Save checkpoint
            saveCheckpoint()
            
            if result.error != nil {
                // Still failed after retry
                await updateLessonStage(lessonId: lessonId, stage: .failed, error: result.error?.localizedDescription)
            } else {
                // Success! Mark as done and repackage to include newly completed lesson
                await updateLessonStage(lessonId: lessonId, stage: .done)
                
                // Repackage to include newly completed lesson
                do {
                    try await repackageCompletedLessons()
                } catch {
                    // Repackaging failed - lesson succeeded but package not updated
                    print("⚠️ Repackaging failed after retry: \(error.localizedDescription)")
                }
            }
        } catch {
            await updateLessonStage(lessonId: lessonId, stage: .failed, error: error.localizedDescription)
        }
        
        backgroundManager.endBackgroundTask()
    }
    
    /// Retry all failed lessons in parallel (respects concurrency cap)
    func retryAllFailedLessons() async {
        let failedIds = failedLessonIds
        guard !failedIds.isEmpty else { return }
        
        guard let request = activeRequest,
              let curriculum = draftCurriculum else {
            return
        }
        
        // Ensure background task is active
        backgroundManager.beginBackgroundTask(name: "lesson-retry-all")
        
        // Prepare services once
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
            
            let completedCount = ThreadSafeCounter(initialValue: progress.completedItems)
            
            // Use semaphore to limit concurrency (same as main generation)
            let semaphore = AsyncSemaphore(maxCount: maxConcurrentLessons)
            
            await withTaskGroup(of: (String, LessonGenerationResult).self) { group in
                for lessonId in failedIds {
                    guard let lesson = curriculum.lessons[lessonId] else { continue }
                    
                    // Reset to queued
                    await updateLessonStage(lessonId: lessonId, stage: .queued, error: nil)
                    
                    // Remove partial data
                    partialLessons.removeValue(forKey: lessonId)
                    partialQuizzes.removeValue(forKey: lessonId)
                    partialDemos.removeValue(forKey: lessonId)
                    
                    group.addTask {
                        await semaphore.wait()
                        
                        let result = await self.generateSingleLesson(
                            lesson: lesson,
                            curriculum: curriculum,
                            request: request,
                            lessonWriter: lessonWriter,
                            lessonMaxTokens: lessonMaxTokens,
                            quizWriter: quizWriter,
                            quizMaxTokens: quizMaxTokens,
                            demoWriter: demoWriter,
                            demoMaxTokens: demoMaxTokens,
                            existingLesson: nil,
                            existingQuiz: nil,
                            existingDemo: nil,
                            completedCount: completedCount
                        )
                        
                        await semaphore.signal()
                        return (lessonId, result)
                    }
                }
                
                // Collect results
                for await (lessonId, result) in group {
                    if let (markdown, meta) = result.lesson {
                        partialLessons[lessonId] = (markdown, meta)
                    }
                    if let quiz = result.quiz {
                        partialQuizzes[lessonId] = quiz
                    }
                    if let demo = result.demo {
                        partialDemos[lessonId] = demo
                    }
                    
                    // Update progress and save checkpoint
                    progress.completedItems = await completedCount.value
                    saveCheckpoint()
                    
                    if result.error != nil {
                        await updateLessonStage(lessonId: lessonId, stage: .failed, error: result.error?.localizedDescription)
                    } else {
                        await updateLessonStage(lessonId: lessonId, stage: .done)
                    }
                }
            }
            
            // Repackage after all retries complete
            if progress.phase == .completed {
                do {
                    try await repackageCompletedLessons()
                } catch {
                    print("⚠️ Repackaging failed after retry-all: \(error.localizedDescription)")
                }
            }
        } catch {
            print("⚠️ Failed to initialize retry-all: \(error.localizedDescription)")
        }
        
        backgroundManager.endBackgroundTask()
    }
    
    /// Handle app entering background (called from app lifecycle)
    func handleAppDidEnterBackground() {
        // Background task already running - iOS will give us best-effort time
        // Partial state is already being persisted incrementally
    }
    
    /// Handle app returning to foreground (called from app lifecycle)
    func handleAppWillEnterForeground() {
        // If generation is still in progress, ensure background task continues
        // (in case it was ended while we were backgrounded)
        if progress.phase == .writingLessons || 
           progress.phase == .writingQuizzes || 
           progress.phase == .writingDemos || 
           progress.phase == .packaging {
            backgroundManager.beginBackgroundTask(name: "course-generation")
        }
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
