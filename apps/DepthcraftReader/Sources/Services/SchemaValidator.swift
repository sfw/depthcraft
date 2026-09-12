import Foundation

enum SchemaValidatorError: LocalizedError {
    case invalidSchema(String)
    case pathTraversal(String)
    case invalidId(String)
    case schemaViolation(String, details: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidSchema(let name):
            return "Schema validation failed for \(name)"
        case .pathTraversal(let path):
            return "Path traversal detected: \(path)"
        case .invalidId(let id):
            return "Invalid ID format: \(id)"
        case .schemaViolation(let name, let details):
            return "Schema violation in \(name): \(details)"
        }
    }
}

/// Validates package files against schemas and security constraints
enum SchemaValidator {
    
    // MARK: - Schema Version
    
    /// Supported schema version for v0.1 field trial.
    /// Note: Hardcoded to "0.1.0" for initial release. Future additive changes
    /// (e.g. tap-to-explain in Slice A, optional demo video fields) may require
    /// schema evolution to 0.1.x with backward compatibility checks.
    private static let supportedSchemaVersion = "0.1.0"
    
    // MARK: - ID Pattern
    
    /// Safe ID pattern: lowercase alphanumeric and hyphens, must start with alphanumeric
    /// Matches schema pattern: ^[a-z0-9][a-z0-9-]*$
    private static let idPattern = "^[a-z0-9][a-z0-9-]*$"
    
    // MARK: - Path Safety
    
    /// Validates that a path component is safe (no traversal, no absolute paths)
    static func validateSafePath(_ path: String, name: String) throws {
        // Reject empty paths
        guard !path.isEmpty else {
            throw SchemaValidatorError.pathTraversal("Empty path for \(name)")
        }
        
        // Reject path traversal attempts
        if path.contains("..") {
            throw SchemaValidatorError.pathTraversal("Path contains '..' in \(name): \(path)")
        }
        
        // Reject absolute paths
        if path.hasPrefix("/") {
            throw SchemaValidatorError.pathTraversal("Absolute path not allowed in \(name): \(path)")
        }
        
        // Reject scheme-based paths (http://, file://, etc.)
        if path.contains("://") {
            throw SchemaValidatorError.pathTraversal("Scheme-based path not allowed in \(name): \(path)")
        }
        
        // Reject leading/trailing whitespace
        if path != path.trimmingCharacters(in: .whitespaces) {
            throw SchemaValidatorError.pathTraversal("Path has leading/trailing whitespace in \(name): \(path)")
        }
    }
    
    /// Validates that an ID matches the safe pattern
    static func validateId(_ id: String, name: String) throws {
        try validateSafePath(id, name: name)
        
        guard let regex = try? NSRegularExpression(pattern: idPattern),
              regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil else {
            throw SchemaValidatorError.invalidId("\(name) ID '\(id)' must match pattern [a-z0-9][a-z0-9-]*")
        }
    }
    
    // MARK: - Manifest Validation
    
    static func validateManifest(_ manifest: PackageManifest) throws {
        // Check schema version
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw SchemaValidatorError.schemaViolation(
                "manifest.json",
                details: "Unsupported schema version '\(manifest.schemaVersion)', expected '\(supportedSchemaVersion)'"
            )
        }
        
        // Validate required string fields are non-empty
        guard !manifest.packageId.isEmpty else {
            throw SchemaValidatorError.schemaViolation("manifest.json", details: "packageId cannot be empty")
        }
        guard !manifest.title.isEmpty else {
            throw SchemaValidatorError.schemaViolation("manifest.json", details: "title cannot be empty")
        }
        guard !manifest.topic.isEmpty else {
            throw SchemaValidatorError.schemaViolation("manifest.json", details: "topic cannot be empty")
        }
        guard manifest.locale.count >= 2 else {
            throw SchemaValidatorError.schemaViolation("manifest.json", details: "locale must be at least 2 characters")
        }
        
        // Validate contentVersion is positive
        guard manifest.contentVersion >= 1 else {
            throw SchemaValidatorError.schemaViolation("manifest.json", details: "contentVersion must be >= 1")
        }
        
        // Validate package ID is safe (no path traversal)
        try validateSafePath(manifest.packageId, name: "manifest.packageId")
        
        // Validate extended metadata if present
        if let extended = manifest.extendedFrom {
            guard extended.priorVersion >= 1 else {
                throw SchemaValidatorError.schemaViolation("manifest.json", details: "extendedFrom.priorVersion must be >= 1")
            }
        }
    }
    
    // MARK: - Curriculum Validation
    
    static func validateCurriculum(_ curriculum: Curriculum) throws {
        // Check schema version
        guard curriculum.schemaVersion == supportedSchemaVersion else {
            throw SchemaValidatorError.schemaViolation(
                "curriculum.json",
                details: "Unsupported schema version '\(curriculum.schemaVersion)', expected '\(supportedSchemaVersion)'"
            )
        }
        
        // Validate status is one of allowed values
        let allowedStatuses = ["draft", "approved", "built"]
        guard allowedStatuses.contains(curriculum.status) else {
            throw SchemaValidatorError.schemaViolation(
                "curriculum.json",
                details: "Invalid status '\(curriculum.status)', must be one of: \(allowedStatuses.joined(separator: ", "))"
            )
        }
        
        // Validate units array is non-empty
        guard !curriculum.units.isEmpty else {
            throw SchemaValidatorError.schemaViolation("curriculum.json", details: "units array cannot be empty")
        }
        
        // Validate lessons map is non-empty
        guard !curriculum.lessons.isEmpty else {
            throw SchemaValidatorError.schemaViolation("curriculum.json", details: "lessons map cannot be empty")
        }
        
        // Validate each unit
        var seenUnitIds = Set<String>()
        for unit in curriculum.units {
            // Validate unit ID format
            try validateId(unit.id, name: "unit")
            
            // Check for duplicate unit IDs
            guard !seenUnitIds.contains(unit.id) else {
                throw SchemaValidatorError.schemaViolation("curriculum.json", details: "Duplicate unit ID: \(unit.id)")
            }
            seenUnitIds.insert(unit.id)
            
            // Validate unit has non-empty title
            guard !unit.title.isEmpty else {
                throw SchemaValidatorError.schemaViolation("curriculum.json", details: "Unit '\(unit.id)' has empty title")
            }
            
            // Validate unit order is positive
            guard unit.order >= 1 else {
                throw SchemaValidatorError.schemaViolation("curriculum.json", details: "Unit '\(unit.id)' order must be >= 1")
            }
            
            // Validate unit has at least one lesson
            guard !unit.lessonIds.isEmpty else {
                throw SchemaValidatorError.schemaViolation("curriculum.json", details: "Unit '\(unit.id)' has no lessons")
            }
            
            // Validate each lesson ID in unit
            for lessonId in unit.lessonIds {
                try validateId(lessonId, name: "lesson")
            }
        }
        
        // Validate each lesson
        for (lessonKey, lesson) in curriculum.lessons {
            // Validate lesson key matches lesson.id
            guard lessonKey == lesson.id else {
                throw SchemaValidatorError.schemaViolation(
                    "curriculum.json",
                    details: "Lesson key '\(lessonKey)' does not match lesson.id '\(lesson.id)'"
                )
            }
            
            // Validate lesson ID format
            try validateId(lesson.id, name: "lesson")
            
            // Validate lesson has non-empty title
            guard !lesson.title.isEmpty else {
                throw SchemaValidatorError.schemaViolation("curriculum.json", details: "Lesson '\(lesson.id)' has empty title")
            }
            
            // Validate lesson status
            guard allowedStatuses.contains(lesson.status) else {
                throw SchemaValidatorError.schemaViolation(
                    "curriculum.json",
                    details: "Lesson '\(lesson.id)' has invalid status '\(lesson.status)'"
                )
            }
            
            // Validate lesson order is positive
            guard lesson.order >= 1 else {
                throw SchemaValidatorError.schemaViolation("curriculum.json", details: "Lesson '\(lesson.id)' order must be >= 1")
            }
            
            // Validate unitId is safe
            try validateSafePath(lesson.unitId, name: "lesson.unitId")
            
            // Validate estimatedMinutes if present
            if let minutes = lesson.estimatedMinutes {
                guard minutes >= 1 else {
                    throw SchemaValidatorError.schemaViolation(
                        "curriculum.json",
                        details: "Lesson '\(lesson.id)' estimatedMinutes must be >= 1"
                    )
                }
            }
        }
        
        // Cross-validate: all lesson IDs referenced in units must exist in lessons map
        for unit in curriculum.units {
            for lessonId in unit.lessonIds {
                guard curriculum.lessons[lessonId] != nil else {
                    throw SchemaValidatorError.schemaViolation(
                        "curriculum.json",
                        details: "Unit '\(unit.id)' references non-existent lesson '\(lessonId)'"
                    )
                }
            }
        }
    }
    
    // MARK: - Quiz Validation
    
    static func validateQuiz(_ quiz: QuizDocument, expectedLessonId: String) throws {
        // Check schema version
        guard quiz.schemaVersion == supportedSchemaVersion else {
            throw SchemaValidatorError.schemaViolation(
                "quiz.json",
                details: "Unsupported schema version '\(quiz.schemaVersion)', expected '\(supportedSchemaVersion)'"
            )
        }
        
        // Validate lesson ID matches expected
        guard quiz.lessonId == expectedLessonId else {
            throw SchemaValidatorError.schemaViolation(
                "quiz.json",
                details: "Quiz lessonId '\(quiz.lessonId)' does not match expected '\(expectedLessonId)'"
            )
        }
        
        // Validate quiz has at least one item
        guard !quiz.items.isEmpty else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "Quiz has no items")
        }
        
        // Validate each quiz item
        var seenItemIds = Set<String>()
        for item in quiz.items {
            let itemId = item.id
            
            // Check for duplicate item IDs
            guard !seenItemIds.contains(itemId) else {
                throw SchemaValidatorError.schemaViolation("quiz.json", details: "Duplicate quiz item ID: \(itemId)")
            }
            seenItemIds.insert(itemId)
            
            switch item {
            case .mc(let mc):
                try validateMCItem(mc)
            case .cloze(let cloze):
                try validateClozeItem(cloze)
            }
        }
    }
    
    private static func validateMCItem(_ item: MCItem) throws {
        // Validate ID is non-empty
        guard !item.id.isEmpty else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item has empty ID")
        }
        
        // Validate type
        guard item.type == "mc" else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item '\(item.id)' has wrong type '\(item.type)'")
        }
        
        // Validate prompt is non-empty
        guard !item.prompt.isEmpty else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item '\(item.id)' has empty prompt")
        }
        
        // Validate has at least 2 choices
        guard item.choices.count >= 2 else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item '\(item.id)' must have at least 2 choices")
        }
        
        // Validate each choice
        var seenChoiceIds = Set<String>()
        for choice in item.choices {
            guard !choice.id.isEmpty else {
                throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item '\(item.id)' has choice with empty ID")
            }
            guard !choice.text.isEmpty else {
                throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item '\(item.id)' choice '\(choice.id)' has empty text")
            }
            guard !seenChoiceIds.contains(choice.id) else {
                throw SchemaValidatorError.schemaViolation("quiz.json", details: "MC item '\(item.id)' has duplicate choice ID: \(choice.id)")
            }
            seenChoiceIds.insert(choice.id)
        }
        
        // Validate correctId exists in choices
        guard item.choices.contains(where: { $0.id == item.correctId }) else {
            throw SchemaValidatorError.schemaViolation(
                "quiz.json",
                details: "MC item '\(item.id)' correctId '\(item.correctId)' not found in choices"
            )
        }
    }
    
    private static func validateClozeItem(_ item: ClozeItem) throws {
        // Validate ID is non-empty
        guard !item.id.isEmpty else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "Cloze item has empty ID")
        }
        
        // Validate type
        guard item.type == "cloze" else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "Cloze item '\(item.id)' has wrong type '\(item.type)'")
        }
        
        // Validate prompt is non-empty
        guard !item.prompt.isEmpty else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "Cloze item '\(item.id)' has empty prompt")
        }
        
        // Validate has at least one answer
        guard !item.answers.isEmpty else {
            throw SchemaValidatorError.schemaViolation("quiz.json", details: "Cloze item '\(item.id)' has no answers")
        }
        
        // Validate each answer is non-empty
        for (index, answer) in item.answers.enumerated() {
            guard !answer.isEmpty else {
                throw SchemaValidatorError.schemaViolation(
                    "quiz.json",
                    details: "Cloze item '\(item.id)' answer at index \(index) is empty"
                )
            }
        }
    }
    
    // MARK: - Demo Manifest Validation
    
    static func validateDemoManifest(_ manifest: DemoManifest, expectedDemoId: String) throws {
        // Check schema version
        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw SchemaValidatorError.schemaViolation(
                "demo.json",
                details: "Unsupported schema version '\(manifest.schemaVersion)', expected '\(supportedSchemaVersion)'"
            )
        }
        
        // Validate demo ID matches expected and is safe
        guard manifest.demoId == expectedDemoId else {
            throw SchemaValidatorError.schemaViolation(
                "demo.json",
                details: "Demo demoId '\(manifest.demoId)' does not match expected '\(expectedDemoId)'"
            )
        }
        try validateId(manifest.demoId, name: "demo")
        
        // Validate title is non-empty
        guard !manifest.title.isEmpty else {
            throw SchemaValidatorError.schemaViolation("demo.json", details: "Demo '\(manifest.demoId)' has empty title")
        }
        
        // Validate kit is non-empty and safe
        guard !manifest.kit.isEmpty else {
            throw SchemaValidatorError.schemaViolation("demo.json", details: "Demo '\(manifest.demoId)' has empty kit")
        }
        try validateSafePath(manifest.kit, name: "demo.kit")
        
        // Validate entry path is safe
        guard !manifest.entry.isEmpty else {
            throw SchemaValidatorError.schemaViolation("demo.json", details: "Demo '\(manifest.demoId)' has empty entry")
        }
        try validateSafePath(manifest.entry, name: "demo.entry")
        
        // Validate fallback path is safe
        guard !manifest.fallback.isEmpty else {
            throw SchemaValidatorError.schemaViolation("demo.json", details: "Demo '\(manifest.demoId)' has empty fallback")
        }
        try validateSafePath(manifest.fallback, name: "demo.fallback")
        
        // Entry and fallback should be relative file paths only
        guard !manifest.entry.hasPrefix("/") && !manifest.fallback.hasPrefix("/") else {
            throw SchemaValidatorError.schemaViolation("demo.json", details: "Demo '\(manifest.demoId)' entry/fallback must be relative paths")
        }
    }
}
