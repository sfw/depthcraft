import Foundation

class PackagerService: PackagerRole {
    private let fileManager = FileManager.default
    
    func packageCourse(
        topic: String,
        locale: String,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument],
        demos: [String: DemoWriterOutput],
        roleRuns: GeneratorMetadata
    ) async throws -> URL {
        let packageId = generatePackageId(from: topic)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        let manifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: packageId,
            title: topic,
            topic: topic,
            createdAt: timestamp,
            locale: locale,
            generator: roleRuns
        )
        
        // Only include lessons that were actually generated (have content + quiz)
        // Ensures built package = only what learner can study
        let builtLessons = curriculum.lessons.compactMapValues { lesson -> CurriculumLesson? in
            guard lessons[lesson.id] != nil, quizzes[lesson.id] != nil else {
                return nil  // Exclude lessons without content
            }
            return CurriculumLesson(
                id: lesson.id,
                unitId: lesson.unitId,
                title: lesson.title,
                order: lesson.order,
                status: "built",
                estimatedMinutes: lesson.estimatedMinutes
            )
        }
        
        // Only include units that have at least one built lesson
        let builtUnits = curriculum.units.filter { unit in
            unit.lessonIds.contains { builtLessons[$0] != nil }
        }
        
        let updatedCurriculum = Curriculum(
            schemaVersion: curriculum.schemaVersion,
            status: "built",
            approvedAt: curriculum.approvedAt,
            units: builtUnits,
            lessons: builtLessons
        )
        
        try validatePackage(
            manifest: manifest,
            curriculum: updatedCurriculum,
            lessons: lessons,
            quizzes: quizzes,
            demos: demos
        )
        
        let packageURL = try await assemblePackage(
            packageId: packageId,
            manifest: manifest,
            curriculum: updatedCurriculum,
            lessons: lessons,
            quizzes: quizzes,
            demos: demos,
            roleRuns: roleRuns
        )
        
        return packageURL
    }
    
    func generatePackageId(from topic: String) -> String {
        let cleaned = topic
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
        let prefix = String(cleaned.prefix(40))
        let timestamp = Date().timeIntervalSince1970
        return "\(prefix)-\(Int(timestamp))"
    }
    
    func validatePackage(
        manifest: PackageManifest,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument],
        demos: [String: DemoWriterOutput]
    ) throws {
        guard curriculum.schemaVersion == "0.1.0" else {
            throw GenerationError.validationFailed("Invalid curriculum schema version")
        }
        
        guard !curriculum.units.isEmpty else {
            throw GenerationError.validationFailed("Curriculum has no units")
        }
        
        for unit in curriculum.units {
            guard !unit.lessonIds.isEmpty else {
                throw GenerationError.validationFailed("Unit \(unit.id) has no lessons")
            }
            
            for lessonId in unit.lessonIds {
                guard curriculum.lessons[lessonId] != nil else {
                    throw GenerationError.validationFailed("Lesson \(lessonId) referenced in unit \(unit.id) not found in curriculum")
                }
                
                guard lessons[lessonId] != nil else {
                    throw GenerationError.validationFailed("Lesson content for \(lessonId) not provided")
                }
                
                guard quizzes[lessonId] != nil else {
                    throw GenerationError.validationFailed("Quiz for \(lessonId) not provided")
                }
            }
        }
        
        for (lessonId, lesson) in curriculum.lessons {
            guard lesson.status == "built" || lesson.status == "approved" else {
                throw GenerationError.validationFailed("Lesson \(lessonId) status is \(lesson.status), expected built or approved")
            }
        }
        
        for (lessonId, demoOutput) in demos {
            guard let (lessonMarkdown, _) = lessons[lessonId] else {
                throw GenerationError.validationFailed("Demo for lesson \(lessonId) but lesson not found")
            }
            
            for demo in demoOutput.demos {
                try validateDemoSpec(demo, lessonId: lessonId, lessonMarkdown: lessonMarkdown)
            }
        }
    }
    
    private func validateDemoSpec(_ demo: DemoSpec, lessonId: String, lessonMarkdown: String) throws {
        let allowedKits = ["three-v0"]
        guard allowedKits.contains(demo.kit) else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' in lesson '\(lessonId)' uses disallowed kit '\(demo.kit)'. Allowed: \(allowedKits.joined(separator: ", "))")
        }
        
        try validateNoExternalURLs(demo.entryHTML, demoId: demo.demoId, file: "index.html", lessonId: lessonId)
        try validateNoExternalURLs(demo.fallbackMarkdown, demoId: demo.demoId, file: "fallback.md", lessonId: lessonId)
        
        for (filename, content) in demo.assets ?? [:] {
            try validateNoExternalURLs(content, demoId: demo.demoId, file: filename, lessonId: lessonId)
        }
        
        try validateNoMidFlightFetch(demo.entryHTML, demoId: demo.demoId, file: "index.html", lessonId: lessonId)
        
        for (filename, content) in demo.assets ?? [:] {
            if filename.hasSuffix(".js") {
                try validateNoMidFlightFetch(content, demoId: demo.demoId, file: filename, lessonId: lessonId)
            }
        }
        
        guard demo.fallback == "fallback.md" else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' in lesson '\(lessonId)' missing or invalid fallback field")
        }
        
        guard !demo.fallbackMarkdown.isEmpty else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' in lesson '\(lessonId)' has empty fallback.md content")
        }
    }
    
    private func validateNoExternalURLs(_ content: String, demoId: String, file: String, lessonId: String) throws {
        let urlPatterns = [
            ("http://", "HTTP URL"),
            ("https://", "HTTPS URL"),
            ("//cdn", "CDN URL"),
            ("//unpkg", "unpkg CDN"),
            ("//jsdelivr", "jsDelivr CDN")
        ]
        
        for (pattern, description) in urlPatterns {
            if content.contains(pattern) {
                throw GenerationError.validationFailed("Demo '\(demoId)' in lesson '\(lessonId)' file '\(file)' contains external URL: \(description)")
            }
        }
    }
    
    private func validateNoMidFlightFetch(_ content: String, demoId: String, file: String, lessonId: String) throws {
        let fetchPatterns = [
            "fetch(",
            "XMLHttpRequest",
            ".ajax("
        ]
        
        for pattern in fetchPatterns {
            if content.contains(pattern) {
                throw GenerationError.validationFailed("Demo '\(demoId)' in lesson '\(lessonId)' file '\(file)' contains mid-flight fetch pattern '\(pattern)'")
            }
        }
    }
    
    func assemblePackage(
        packageId: String,
        manifest: PackageManifest,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument],
        demos: [String: DemoWriterOutput],
        roleRuns: GeneratorMetadata
    ) async throws -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let packageURL = documentsURL.appendingPathComponent("\(packageId).depthcraft")
        
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        
        let curriculumData = try encoder.encode(curriculum)
        try curriculumData.write(to: packageURL.appendingPathComponent("curriculum.json"))
        
        let allLessonIds = curriculum.units.flatMap { $0.lessonIds }
        let allUnitIds = curriculum.units.map { $0.id }
        let progress = DeviceProgress.blank(packageId: packageId, lessonIds: allLessonIds, unitIds: allUnitIds)
        let progressData = try encoder.encode(progress)
        try progressData.write(to: packageURL.appendingPathComponent("progress.json"))
        
        let contentURL = packageURL.appendingPathComponent("content")
        try fileManager.createDirectory(at: contentURL, withIntermediateDirectories: true)
        
        let unitsURL = contentURL.appendingPathComponent("units")
        try fileManager.createDirectory(at: unitsURL, withIntermediateDirectories: true)
        
        for unit in curriculum.units {
            let unitURL = unitsURL.appendingPathComponent(unit.id)
            try fileManager.createDirectory(at: unitURL, withIntermediateDirectories: true)
            
            let unitMd = "# \(unit.title)\n"
            try unitMd.write(to: unitURL.appendingPathComponent("unit.md"), atomically: true, encoding: .utf8)
            
            let lessonsURL = unitURL.appendingPathComponent("lessons")
            try fileManager.createDirectory(at: lessonsURL, withIntermediateDirectories: true)
            
            for lessonId in unit.lessonIds {
                guard let (markdown, meta) = lessons[lessonId],
                      let quiz = quizzes[lessonId] else {
                    throw GenerationError.validationFailed("Missing content for lesson \(lessonId)")
                }
                
                let lessonURL = lessonsURL.appendingPathComponent(lessonId)
                try fileManager.createDirectory(at: lessonURL, withIntermediateDirectories: true)
                
                var finalMarkdown = markdown
                
                if let demoOutput = demos[lessonId], !demoOutput.demos.isEmpty {
                    finalMarkdown = try insertDemoDirectives(
                        markdown: markdown,
                        demos: demoOutput.demos,
                        lessonId: lessonId
                    )
                    
                    let demosURL = lessonURL.appendingPathComponent("demos")
                    try fileManager.createDirectory(at: demosURL, withIntermediateDirectories: true)
                    
                    for demo in demoOutput.demos {
                        let demoURL = demosURL.appendingPathComponent(demo.demoId)
                        try fileManager.createDirectory(at: demoURL, withIntermediateDirectories: true)
                        
                        let demoManifest = DemoManifest(
                            schemaVersion: "0.1.0",
                            demoId: demo.demoId,
                            title: demo.title,
                            kit: demo.kit,
                            entry: demo.entry,
                            fallback: demo.fallback
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
                
                let metaData = try encoder.encode(meta)
                try metaData.write(to: lessonURL.appendingPathComponent("meta.json"))
                
                let quizData = try encoder.encode(quiz)
                try quizData.write(to: lessonURL.appendingPathComponent("quiz.json"))
            }
        }
        
        return packageURL
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
}
