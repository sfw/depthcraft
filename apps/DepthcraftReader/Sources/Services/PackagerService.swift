import Foundation

class PackagerService: PackagerRole {
    private let fileManager = FileManager.default
    
    func packageCourse(
        topic: String,
        locale: String,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument],
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
            locale: locale
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
            quizzes: quizzes
        )
        
        let packageURL = try await assemblePackage(
            packageId: packageId,
            manifest: manifest,
            curriculum: updatedCurriculum,
            lessons: lessons,
            quizzes: quizzes,
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
        quizzes: [String: QuizDocument]
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
    }
    
    func assemblePackage(
        packageId: String,
        manifest: PackageManifest,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument],
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
                
                try markdown.write(to: lessonURL.appendingPathComponent("lesson.md"), atomically: true, encoding: .utf8)
                
                let metaData = try encoder.encode(meta)
                try metaData.write(to: lessonURL.appendingPathComponent("meta.json"))
                
                let quizData = try encoder.encode(quiz)
                try quizData.write(to: lessonURL.appendingPathComponent("quiz.json"))
            }
        }
        
        return packageURL
    }
}
