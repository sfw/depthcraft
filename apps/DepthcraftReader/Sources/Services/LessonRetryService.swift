import Foundation

/// Service for retrying individual failed lessons from course home / Contents view
/// Regenerates a single lesson and merges it into an existing package
@MainActor
class LessonRetryService {
    private let keyStore = APIKeyStore()
    private let customEndpointsStore = CustomEndpointsStore()
    private let fileManager = FileManager.default
    
    func retryLesson(
        lesson: CurriculumLesson,
        packageURL: URL,
        manifest: PackageManifest
    ) async throws {
        // Get planned curriculum from manifest
        guard let plannedCurriculum = manifest.plannedCurriculum else {
            throw GenerationError.validationFailed("No planned curriculum found in package manifest")
        }
        
        // Find the lesson and unit in planned curriculum
        guard let plannedLesson = plannedCurriculum.lessons[lesson.id] else {
            throw GenerationError.validationFailed("Lesson \(lesson.id) not found in planned curriculum")
        }
        
        guard let unit = plannedCurriculum.units.first(where: { $0.lessonIds.contains(lesson.id) }) else {
            throw GenerationError.validationFailed("Unit for lesson \(lesson.id) not found in planned curriculum")
        }
        
        // Get LLM configurations from current settings
        let roleConfig = LLMRoleConfigService(apiKeyStore: keyStore, customEndpointsStore: customEndpointsStore)
        
        let lessonConfig = try roleConfig.getLLMConfig(for: .lessons)
        let quizConfig = try roleConfig.getLLMConfig(for: .quizzes)
        let demoConfig = try roleConfig.getLLMConfig(for: .demos)
        
        // Get knowledge/depth levels from manifest (original generation params)
        let knowledgeLevel = KnowledgeLevel(rawValue: manifest.knowledgeLevel ?? KnowledgeLevel.some.rawValue) ?? .some
        let depthLevel = DepthLevel(rawValue: manifest.depthLevel ?? DepthLevel.standard.rawValue) ?? .standard
        
        // Create generation services
        let lessonClient = try LLMClientFactory.createClient(config: lessonConfig)
        let lessonWriter = LessonWriterService(
            client: lessonClient,
            temperature: lessonConfig.temperature,
            topic: manifest.topic,
            locale: manifest.locale,
            knowledgeLevel: knowledgeLevel,
            depthLevel: depthLevel,
            provider: lessonConfig.provider,
            model: lessonConfig.model,
            timingLogger: nil  // No timing for retry
        )
        
        let quizClient = try LLMClientFactory.createClient(config: quizConfig)
        let quizWriter = QuizWriterService(
            client: quizClient,
            temperature: quizConfig.temperature,
            topic: manifest.topic,
            knowledgeLevel: knowledgeLevel,
            depthLevel: depthLevel,
            provider: quizConfig.provider,
            model: quizConfig.model
        )
        
        let demoClient = try LLMClientFactory.createClient(config: demoConfig)
        let demoWriter = DemoWriterService(
            client: demoClient,
            temperature: demoConfig.temperature,
            topic: manifest.topic,
            knowledgeLevel: knowledgeLevel,
            depthLevel: depthLevel,
            provider: demoConfig.provider,
            model: demoConfig.model
        )
        
        // Generate lesson content
        let (markdown, meta, _) = try await lessonWriter.writeLesson(
            lesson: plannedLesson,
            unit: unit,
            curriculum: plannedCurriculum
        )
        
        // Generate quiz
        let quiz = try await quizWriter.writeQuiz(
            lessonMarkdown: markdown,
            lesson: plannedLesson,
            unit: unit
        )
        
        // Generate demo (optional)
        let demoOutput = try await demoWriter.writeDemos(
            lessonMarkdown: markdown,
            lesson: plannedLesson,
            unit: unit
        )
        
        // Write content to package
        try await writeContentToPackage(
            packageURL: packageURL,
            unit: unit,
            lesson: plannedLesson,
            markdown: markdown,
            meta: meta,
            quiz: quiz,
            demoOutput: demoOutput
        )
        
        // Update curriculum.json to include the new lesson
        try await updateCurriculum(
            packageURL: packageURL,
            plannedCurriculum: plannedCurriculum,
            unit: unit,
            lesson: plannedLesson
        )
        
        // Update manifest contentVersion
        try await updateManifest(packageURL: packageURL, manifest: manifest)
    }
    
    private func writeContentToPackage(
        packageURL: URL,
        unit: CurriculumUnit,
        lesson: CurriculumLesson,
        markdown: String,
        meta: LessonMeta,
        quiz: QuizDocument,
        demoOutput: DemoWriterOutput?
    ) async throws {
        let contentURL = packageURL.appendingPathComponent("content")
        let unitsURL = contentURL.appendingPathComponent("units")
        let unitURL = unitsURL.appendingPathComponent(unit.id)
        let lessonsURL = unitURL.appendingPathComponent("lessons")
        let lessonURL = lessonsURL.appendingPathComponent(lesson.id)
        
        // Create lesson directory if it doesn't exist
        try fileManager.createDirectory(at: lessonURL, withIntermediateDirectories: true)
        
        // Write lesson markdown
        var finalMarkdown = markdown
        
        // Insert demo directives if demos exist
        if let demoOutput = demoOutput, !demoOutput.demos.isEmpty {
            finalMarkdown = try insertDemoDirectives(
                markdown: markdown,
                demos: demoOutput.demos,
                lessonId: lesson.id
            )
            
            // Write demo content
            let demosURL = lessonURL.appendingPathComponent("demos")
            try fileManager.createDirectory(at: demosURL, withIntermediateDirectories: true)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            for demo in demoOutput.demos {
                let demoURL = demosURL.appendingPathComponent(demo.demoId)
                try fileManager.createDirectory(at: demoURL, withIntermediateDirectories: true)
                
                let demoManifest = DemoManifest(
                    schemaVersion: "0.1.0",
                    demoId: demo.demoId,
                    title: demo.title,
                    kit: demo.kit,
                    entry: demo.entry,
                    fallback: demo.fallback,
                    learningGoal: demo.learningGoal
                )
                let demoManifestData = try encoder.encode(demoManifest)
                try demoManifestData.write(to: demoURL.appendingPathComponent("demo.json"))
                
                try demo.entryHTML.write(
                    to: demoURL.appendingPathComponent(demo.entry),
                    atomically: true,
                    encoding: .utf8
                )
                
                try demo.fallbackMarkdown.write(
                    to: demoURL.appendingPathComponent(demo.fallback),
                    atomically: true,
                    encoding: .utf8
                )
                
                if let assets = demo.assets {
                    for (filename, content) in assets {
                        try content.write(
                            to: demoURL.appendingPathComponent(filename),
                            atomically: true,
                            encoding: .utf8
                        )
                    }
                }
            }
        }
        
        try finalMarkdown.write(to: lessonURL.appendingPathComponent("lesson.md"), atomically: true, encoding: .utf8)
        
        // Write meta.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(meta)
        try metaData.write(to: lessonURL.appendingPathComponent("meta.json"))
        
        // Write quiz.json
        let quizData = try encoder.encode(quiz)
        try quizData.write(to: lessonURL.appendingPathComponent("quiz.json"))
    }
    
    private func insertDemoDirectives(markdown: String, demos: [DemoSpec], lessonId: String) throws -> String {
        var result = markdown
        
        for demo in demos {
            let targetHeading = demo.insertAfterHeading
            let directive = "\n\n:::demo id=\"\(demo.demoId)\":::\n"
            
            guard let headingRange = result.range(of: targetHeading) else {
                throw GenerationError.validationFailed("Demo '\(demo.demoId)' in lesson '\(lessonId)' insertAfterHeading '\(targetHeading)' not found in lesson markdown")
            }
            
            let insertPosition = result.index(after: headingRange.upperBound)
            result.insert(contentsOf: directive, at: insertPosition)
        }
        
        return result
    }
    
    private func updateCurriculum(
        packageURL: URL,
        plannedCurriculum: Curriculum,
        unit: CurriculumUnit,
        lesson: CurriculumLesson
    ) async throws {
        let curriculumURL = packageURL.appendingPathComponent("curriculum.json")
        
        // Read existing curriculum
        let data = try Data(contentsOf: curriculumURL)
        var curriculum = try JSONDecoder().decode(Curriculum.self, from: data)
        
        // Add the lesson with "built" status
        let builtLesson = CurriculumLesson(
            id: lesson.id,
            unitId: lesson.unitId,
            title: lesson.title,
            order: lesson.order,
            status: "built",
            estimatedMinutes: lesson.estimatedMinutes
        )
        curriculum.lessons[lesson.id] = builtLesson
        
        // Add unit if it doesn't exist (in case the lesson was part of a new unit)
        if !curriculum.units.contains(where: { $0.id == unit.id }) {
            // Filter unit.lessonIds to only built lessons (previously built + just retried)
            let builtLessonIds = unit.lessonIds.filter { curriculum.lessons[$0] != nil }
            
            // Only add unit if it has at least one built lesson
            if !builtLessonIds.isEmpty {
                let filteredUnit = CurriculumUnit(
                    id: unit.id,
                    title: unit.title,
                    order: unit.order,
                    lessonIds: builtLessonIds
                )
                curriculum.units.append(filteredUnit)
                curriculum.units.sort { $0.order < $1.order }
            }
        } else {
            // Update existing unit to include the lesson if not already present
            if let unitIndex = curriculum.units.firstIndex(where: { $0.id == unit.id }) {
                var updatedUnit = curriculum.units[unitIndex]
                if !updatedUnit.lessonIds.contains(lesson.id) {
                    updatedUnit.lessonIds.append(lesson.id)
                    updatedUnit.lessonIds.sort { id1, id2 in
                        let order1 = curriculum.lessons[id1]?.order ?? 0
                        let order2 = curriculum.lessons[id2]?.order ?? 0
                        return order1 < order2
                    }
                    curriculum.units[unitIndex] = updatedUnit
                }
            }
        }
        
        // Write updated curriculum
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let updatedData = try encoder.encode(curriculum)
        try updatedData.write(to: curriculumURL)
    }
    
    private func updateManifest(packageURL: URL, manifest: PackageManifest) async throws {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        
        // Increment content version, preserve knowledge/depth levels
        let updatedManifest = PackageManifest(
            schemaVersion: manifest.schemaVersion,
            packageId: manifest.packageId,
            contentVersion: manifest.contentVersion + 1,
            title: manifest.title,
            topic: manifest.topic,
            createdAt: manifest.createdAt,
            locale: manifest.locale,
            generator: manifest.generator,
            extendedFrom: manifest.extendedFrom,
            plannedCurriculum: manifest.plannedCurriculum,
            knowledgeLevel: manifest.knowledgeLevel,
            depthLevel: manifest.depthLevel
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updatedManifest)
        try data.write(to: manifestURL)
    }
}
