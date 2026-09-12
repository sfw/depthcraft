import Foundation

enum PackageLoaderError: LocalizedError {
    case missingBundleResource
    case missingFile(String)
    case decode(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource:
            return "Bundled fixture ai-harness-design.depthcraft was not found in the app bundle."
        case .missingFile(let name):
            return "Missing package file: \(name)"
        case .decode(let name, let error):
            return "Could not decode \(name): \(error.localizedDescription)"
        }
    }
}

enum PackageLoader {
    /// Locates the bundled `*.depthcraft` folder. XcodeGen copies the folder into the resource bundle.
    static func bundledPackageURL(named name: String = "ai-harness-design.depthcraft") throws -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return url
        }
        // Folder resource sometimes appears as a directory URL via resourceURL
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            // Nested under Fixtures/
            let nested = resourceURL.appendingPathComponent("Fixtures/\(name)", isDirectory: true)
            if FileManager.default.fileExists(atPath: nested.path) {
                return nested
            }
        }
        throw PackageLoaderError.missingBundleResource
    }

    static func load(from root: URL) throws -> LoadedCourse {
        #if DEBUG
        print("📖 PackageLoader.load from: \(root.path)")
        #endif
        
        // Decode and validate manifest
        let manifest: PackageManifest = try decode("manifest.json", from: root)
        try SchemaValidator.validateManifest(manifest)
        
        // Decode and validate curriculum
        let curriculum: Curriculum = try decode("curriculum.json", from: root)
        try SchemaValidator.validateCurriculum(curriculum)
        
        #if DEBUG
        print("   ✅ Package validated: \(curriculum.units.count) units, \(curriculum.lessons.count) lessons")
        #endif
        
        return LoadedCourse(rootURL: root, manifest: manifest, curriculum: curriculum)
    }

    static func lessonMarkdown(course: LoadedCourse, unitId: String, lessonId: String) throws -> String {
        // Validate IDs to prevent path traversal
        try SchemaValidator.validateId(unitId, name: "unitId")
        try SchemaValidator.validateId(lessonId, name: "lessonId")
        
        let url = course.rootURL
            .appendingPathComponent("content/units/\(unitId)/lessons/\(lessonId)/lesson.md")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PackageLoaderError.missingFile(url.lastPathComponent)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func unitMarkdown(course: LoadedCourse, unitId: String) -> String? {
        // Validate unit ID to prevent path traversal
        guard (try? SchemaValidator.validateId(unitId, name: "unitId")) != nil else {
            return nil
        }
        
        let url = course.rootURL.appendingPathComponent("content/units/\(unitId)/unit.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func quiz(course: LoadedCourse, unitId: String, lessonId: String) throws -> QuizDocument {
        // Validate IDs to prevent path traversal
        try SchemaValidator.validateId(unitId, name: "unitId")
        try SchemaValidator.validateId(lessonId, name: "lessonId")
        
        let url = course.rootURL
            .appendingPathComponent("content/units/\(unitId)/lessons/\(lessonId)/quiz.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PackageLoaderError.missingFile("quiz.json")
        }
        do {
            let data = try Data(contentsOf: url)
            let quiz = try JSONDecoder().decode(QuizDocument.self, from: data)
            // Validate quiz against schema
            try SchemaValidator.validateQuiz(quiz, expectedLessonId: lessonId)
            return quiz
        } catch {
            throw PackageLoaderError.decode("quiz.json", error)
        }
    }

    static func demoManifest(course: LoadedCourse, unitId: String, lessonId: String, demoId: String) throws -> DemoManifest {
        // Validate IDs to prevent path traversal
        try SchemaValidator.validateId(unitId, name: "unitId")
        try SchemaValidator.validateId(lessonId, name: "lessonId")
        try SchemaValidator.validateId(demoId, name: "demoId")
        
        let url = course.rootURL
            .appendingPathComponent("content/units/\(unitId)/lessons/\(lessonId)/demos/\(demoId)/demo.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PackageLoaderError.missingFile("demo.json")
        }
        do {
            let data = try Data(contentsOf: url)
            let manifest = try JSONDecoder().decode(DemoManifest.self, from: data)
            // Validate demo manifest against schema
            try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: demoId)
            return manifest
        } catch {
            throw PackageLoaderError.decode("demo.json", error)
        }
    }

    static func demoDirectory(course: LoadedCourse, unitId: String, lessonId: String, demoId: String) -> URL {
        // Note: Caller should validate IDs before calling this (validateId throws, can't use in non-throwing function)
        // This is validated in demoManifest() which is always called before demoDirectory()
        course.rootURL
            .appendingPathComponent("content/units/\(unitId)/lessons/\(lessonId)/demos/\(demoId)")
    }

    private static func decode<T: Decodable>(_ name: String, from root: URL) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PackageLoaderError.missingFile(name)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PackageLoaderError.decode(name, error)
        }
    }
}
