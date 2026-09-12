import Foundation

enum GlossServiceError: LocalizedError {
    case offline
    case noAPIKey
    case llmError(Error)
    
    var errorDescription: String? {
        switch self {
        case .offline:
            return "You're offline. Tap-to-explain requires an internet connection to generate explanations for terms not included in the lesson."
        case .noAPIKey:
            return "No API key configured. Go to Settings → Generate to add an API key."
        case .llmError(let error):
            return "Failed to generate explanation: \(error.localizedDescription)"
        }
    }
}

@MainActor
class GlossService {
    private let configService: LLMConfigService
    
    init(configService: LLMConfigService) {
        self.configService = configService
    }
    
    /// Generate a gloss/explanation for a term or passage in the context of a lesson
    func generateGloss(for text: String, lessonContext: String) async throws -> String {
        // Get API key and create LLM client
        guard let config = try configService.getAvailableConfig() else {
            throw GlossServiceError.noAPIKey
        }
        
        let client = try LLMClientFactory.createClient(config: config)
        
        let systemPrompt = """
        You are a helpful educational assistant. When a student asks about a term or passage from a lesson, provide a clear, concise explanation.
        
        Keep your explanation:
        - Short (2-3 sentences max)
        - Focused on the specific term/passage
        - Relevant to the lesson context
        - At an appropriate level for the student
        
        Use markdown for emphasis (*italic*, **bold**) if helpful, but keep it simple.
        """
        
        let userPrompt = """
        Lesson context: \(lessonContext)
        
        Explain this term/passage: "\(text)"
        """
        
        do {
            let gloss = try await client.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: 0.7,
                maxTokens: 300
            )
            return gloss.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GlossServiceError.llmError(error)
        }
    }
    
    /// Check if we have any API key configured
    func hasAPIKey() -> Bool {
        return configService.hasAPIKey()
    }
}
