import Foundation

enum ImportValidatorError: LocalizedError {
    case invalidPackageStructure(String)
    case securityViolation(String)
    case schemaValidationFailed(String)
    case zipSlipDetected(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPackageStructure(let details):
            return "Invalid package structure: \(details)"
        case .securityViolation(let details):
            return "Security violation detected: \(details)"
        case .schemaValidationFailed(let details):
            return "Package validation failed: \(details)"
        case .zipSlipDetected(let path):
            return "Zip slip attack detected: \(path)"
        }
    }
    
    var userFriendlyDescription: String {
        switch self {
        case .invalidPackageStructure:
            return "This package file is damaged or incomplete. Please regenerate the course or obtain a valid package."
        case .securityViolation:
            return "This package contains unsafe content and cannot be imported. Please ensure the package is from a trusted source."
        case .schemaValidationFailed:
            return "This package format is invalid or incompatible. Please regenerate the course with the latest version."
        case .zipSlipDetected:
            return "This package contains invalid file paths and cannot be imported for security reasons."
        }
    }
}

enum ImportValidator {
    
    /// Validates an imported package before it's loaded
    static func validateImportedPackage(at packageURL: URL) throws {
        let fileManager = FileManager.default
        
        // 1. Check if it's a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ImportValidatorError.invalidPackageStructure("Package must be a directory")
        }
        
        // 2. Validate all paths in package to prevent zip-slip
        try validatePackagePaths(at: packageURL)
        
        // 3. Load and validate manifest
        let manifest: PackageManifest = try decode("manifest.json", from: packageURL)
        do {
            try SchemaValidator.validateManifest(manifest)
        } catch {
            throw ImportValidatorError.schemaValidationFailed(error.localizedDescription)
        }
        
        // 4. Load and validate curriculum
        let curriculum: Curriculum = try decode("curriculum.json", from: packageURL)
        do {
            try SchemaValidator.validateCurriculum(curriculum)
        } catch {
            throw ImportValidatorError.schemaValidationFailed(error.localizedDescription)
        }
        
        // 5. Validate package structure
        try validateRequiredFiles(at: packageURL, curriculum: curriculum)
        
        // 6. Scan lessons for unsafe content
        try validateLessonContent(at: packageURL, curriculum: curriculum)
        
        // 7. Validate demos for security issues
        try validateDemos(at: packageURL, curriculum: curriculum)
    }
    
    private static func validatePackagePaths(at packageURL: URL) throws {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: packageURL.path)
        
        while let relativePath = enumerator?.nextObject() as? String {
            // Check for path traversal attempts
            if relativePath.contains("..") {
                throw ImportValidatorError.zipSlipDetected(relativePath)
            }
            
            // Check for absolute paths
            if relativePath.hasPrefix("/") {
                throw ImportValidatorError.zipSlipDetected(relativePath)
            }
            
            // Construct full path and verify it's within package directory
            let fullPath = packageURL.appendingPathComponent(relativePath).standardizedFileURL.path
            let packagePath = packageURL.standardizedFileURL.path
            
            if !fullPath.hasPrefix(packagePath) {
                throw ImportValidatorError.zipSlipDetected(relativePath)
            }
        }
    }
    
    private static func validateRequiredFiles(at packageURL: URL, curriculum: Curriculum) throws {
        let fileManager = FileManager.default
        
        // Check for required files
        let requiredFiles = ["manifest.json", "curriculum.json", "progress.json"]
        for file in requiredFiles {
            let fileURL = packageURL.appendingPathComponent(file)
            if !fileManager.fileExists(atPath: fileURL.path) {
                throw ImportValidatorError.invalidPackageStructure("Missing required file: \(file)")
            }
        }
        
        // Check content directory exists
        let contentURL = packageURL.appendingPathComponent("content")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: contentURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ImportValidatorError.invalidPackageStructure("Missing content directory")
        }
        
        // Validate each unit and lesson exists
        for unit in curriculum.units {
            let unitURL = contentURL.appendingPathComponent("units/\(unit.id)")
            guard fileManager.fileExists(atPath: unitURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ImportValidatorError.invalidPackageStructure("Missing unit directory: \(unit.id)")
            }
            
            for lessonId in unit.lessonIds {
                let lessonURL = unitURL.appendingPathComponent("lessons/\(lessonId)")
                guard fileManager.fileExists(atPath: lessonURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw ImportValidatorError.invalidPackageStructure("Missing lesson directory: \(lessonId)")
                }
                
                // Check required lesson files
                let lessonFiles = ["lesson.md", "meta.json", "quiz.json"]
                for file in lessonFiles {
                    let fileURL = lessonURL.appendingPathComponent(file)
                    if !fileManager.fileExists(atPath: fileURL.path) {
                        throw ImportValidatorError.invalidPackageStructure("Missing lesson file: \(lessonId)/\(file)")
                    }
                }
            }
        }
    }
    
    private static func validateLessonContent(at packageURL: URL, curriculum: Curriculum) throws {
        // Validate lesson markdown and meta.json for each lesson
        for unit in curriculum.units {
            for lessonId in unit.lessonIds {
                // Validate IDs to prevent path traversal
                try SchemaValidator.validateId(unit.id, name: "unitId")
                try SchemaValidator.validateId(lessonId, name: "lessonId")
                
                let lessonURL = packageURL
                    .appendingPathComponent("content/units/\(unit.id)/lessons/\(lessonId)")
                
                // Load and validate meta.json
                let metaURL = lessonURL.appendingPathComponent("meta.json")
                let _ : LessonMeta = try decode("meta.json", from: lessonURL)
                
                // Load and scan lesson.md for dangerous content
                let markdownURL = lessonURL.appendingPathComponent("lesson.md")
                let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
                try validateMarkdownContent(markdown, lessonId: lessonId)
                
                // Load and validate quiz.json
                let quizURL = lessonURL.appendingPathComponent("quiz.json")
                let quizData = try Data(contentsOf: quizURL)
                let quiz = try JSONDecoder().decode(QuizDocument.self, from: quizData)
                try SchemaValidator.validateQuiz(quiz, expectedLessonId: lessonId)
            }
        }
    }
    
    private static func validateMarkdownContent(_ markdown: String, lessonId: String) throws {
        // Check for common XSS patterns (note: MarkdownHTML.render already escapes these,
        // but we want to reject packages that contain them in the first place)
        let dangerousPatterns = [
            "<script",
            "javascript:",
            "onerror=",
            "onload=",
            "<iframe",
            "data:text/html"
        ]
        
        let lowercased = markdown.lowercased()
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern) {
                throw ImportValidatorError.securityViolation("Lesson \(lessonId) contains potentially unsafe content: \(pattern)")
            }
        }
    }
    
    private static func validateDemos(at packageURL: URL, curriculum: Curriculum) throws {
        let fileManager = FileManager.default
        
        for unit in curriculum.units {
            for lessonId in unit.lessonIds {
                let demosURL = packageURL
                    .appendingPathComponent("content/units/\(unit.id)/lessons/\(lessonId)/demos")
                
                // Check if demos directory exists
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: demosURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue // No demos for this lesson
                }
                
                // Enumerate demo directories
                let demoContents = try fileManager.contentsOfDirectory(atPath: demosURL.path)
                for demoId in demoContents {
                    let demoURL = demosURL.appendingPathComponent(demoId)
                    
                    // Validate demo ID
                    try SchemaValidator.validateId(demoId, name: "demoId")
                    
                    // Load and validate demo.json
                    let manifestURL = demoURL.appendingPathComponent("demo.json")
                    guard fileManager.fileExists(atPath: manifestURL.path) else {
                        continue
                    }
                    
                    let manifestData = try Data(contentsOf: manifestURL)
                    let manifest = try JSONDecoder().decode(DemoManifest.self, from: manifestData)
                    try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: demoId)
                    
                    // Validate entry HTML for external URLs and fetch
                    let entryURL = demoURL.appendingPathComponent(manifest.entry)
                    if fileManager.fileExists(atPath: entryURL.path) {
                        let entryContent = try String(contentsOf: entryURL, encoding: .utf8)
                        try validateDemoContent(entryContent, demoId: demoId, file: manifest.entry)
                    }
                    
                    // Validate fallback markdown
                    let fallbackURL = demoURL.appendingPathComponent(manifest.fallback)
                    if fileManager.fileExists(atPath: fallbackURL.path) {
                        let fallbackContent = try String(contentsOf: fallbackURL, encoding: .utf8)
                        try validateMarkdownContent(fallbackContent, lessonId: "\(lessonId)/demo/\(demoId)")
                    }
                }
            }
        }
    }
    
    private static func validateDemoContent(_ content: String, demoId: String, file: String) throws {
        // Check for external URLs
        let urlPatterns = [
            "http://",
            "https://",
            "//cdn",
            "//unpkg",
            "//jsdelivr"
        ]
        
        for pattern in urlPatterns {
            if content.contains(pattern) {
                throw ImportValidatorError.securityViolation("Demo \(demoId) file \(file) contains external URL: \(pattern)")
            }
        }
        
        // Check for mid-flight fetch patterns
        let fetchPatterns = [
            "fetch(",
            "XMLHttpRequest",
            ".ajax("
        ]
        
        for pattern in fetchPatterns {
            if content.contains(pattern) {
                throw ImportValidatorError.securityViolation("Demo \(demoId) file \(file) contains network fetch pattern: \(pattern)")
            }
        }
    }
    
    private static func decode<T: Decodable>(_ name: String, from root: URL) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportValidatorError.invalidPackageStructure("Missing file: \(name)")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ImportValidatorError.schemaValidationFailed("Could not decode \(name): \(error.localizedDescription)")
        }
    }
}
