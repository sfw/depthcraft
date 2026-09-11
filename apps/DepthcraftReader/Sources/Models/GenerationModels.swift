import Foundation

// MARK: - Provider configuration

enum LLMProvider: String, Codable, CaseIterable {
    case anthropic
    case openai
    case openrouter
    case custom
    
    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }
}

struct LLMConfiguration {
    let provider: LLMProvider
    let model: String
    let apiKey: String
    let temperature: Double
    let customBaseURL: String?
    
    init(provider: LLMProvider, model: String, apiKey: String, temperature: Double = 0.7, customBaseURL: String? = nil) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.customBaseURL = customBaseURL
    }
}

// MARK: - Role run metadata

struct RoleRun: Codable, Hashable {
    let provider: String
    let model: String
    let ranAt: String
}

// MARK: - Generation request

struct GenerationRequest {
    let topic: String
    let locale: String
    let plannerConfig: LLMConfiguration
    let lessonWriterConfig: LLMConfiguration
    let quizWriterConfig: LLMConfiguration
    let generateUnitIds: [String]?
}

// MARK: - Generation state

enum GenerationPhase: String, CaseIterable {
    case idle
    case planning
    case awaitingApproval
    case writingLessons
    case writingQuizzes
    case packaging
    case completed
    case failed
    
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .planning: return "Planning curriculum..."
        case .awaitingApproval: return "Awaiting approval"
        case .writingLessons: return "Writing lessons..."
        case .writingQuizzes: return "Writing quizzes..."
        case .packaging: return "Packaging course..."
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

struct GenerationProgress {
    var phase: GenerationPhase
    var currentItem: String?
    var completedItems: Int
    var totalItems: Int
    var error: String?
    
    var progressPercent: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }
    
    static var idle: GenerationProgress {
        GenerationProgress(phase: .idle, currentItem: nil, completedItems: 0, totalItems: 0, error: nil)
    }
}

// MARK: - Generation output

struct GenerationOutput {
    let packageURL: URL
    let manifest: PackageManifest
    let curriculum: Curriculum
}

// MARK: - Role interfaces

protocol PlannerRole {
    func plan(topic: String, locale: String) async throws -> Curriculum
}

protocol LessonWriterRole {
    func writeLesson(lesson: CurriculumLesson, unit: CurriculumUnit, curriculum: Curriculum) async throws -> (markdown: String, meta: LessonMeta)
}

protocol QuizWriterRole {
    func writeQuiz(lessonMarkdown: String, lesson: CurriculumLesson) async throws -> QuizDocument
}

protocol PackagerRole {
    func packageCourse(
        topic: String,
        locale: String,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument],
        roleRuns: GeneratorMetadata
    ) async throws -> URL
}

// MARK: - Supporting types

struct LessonMeta: Codable, Hashable {
    let schemaVersion: String
    let lessonId: String
    let anchors: [Anchor]
    
    struct Anchor: Codable, Hashable {
        let id: String
        let heading: String
        let kind: String
    }
}

struct GeneratorMetadata: Codable, Hashable {
    let planner: RoleRun?
    let lessonWriter: RoleRun?
    let quizWriter: RoleRun?
    let packager: RoleRun?
}

// MARK: - Error types

enum GenerationError: LocalizedError {
    case missingAPIKey(LLMProvider)
    case invalidResponse(String)
    case lessonFailed(String, Error)
    case quizFailed(String, Error)
    case validationFailed(String)
    case packagingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider.displayName)"
        case .invalidResponse(let message):
            return "Invalid LLM response: \(message)"
        case .lessonFailed(let lessonId, let error):
            return "Failed to generate lesson \(lessonId): \(error.localizedDescription)"
        case .quizFailed(let lessonId, let error):
            return "Failed to generate quiz for \(lessonId): \(error.localizedDescription)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .packagingFailed(let error):
            return "Packaging failed: \(error.localizedDescription)"
        }
    }
}
