import Foundation

/// Centralized LLM configuration service for BYOK
@MainActor
class LLMConfigService {
    private let apiKeyStore: APIKeyStore
    
    init(apiKeyStore: APIKeyStore) {
        self.apiKeyStore = apiKeyStore
    }
    
    /// Check if we have any API key configured
    func hasAPIKey() -> Bool {
        return apiKeyStore.hasAnthropicKey ||
               apiKeyStore.hasOpenAIKey ||
               apiKeyStore.hasOpenRouterKey ||
               apiKeyStore.hasCustomKey
    }
    
    /// Get the first available LLM configuration
    /// Priority: Anthropic → OpenAI → OpenRouter → Custom
    /// Uses same model defaults as Generate UI
    func getAvailableConfig() throws -> LLMConfiguration? {
        // Try Anthropic first
        if apiKeyStore.hasAnthropicKey, let key = try apiKeyStore.getKey(for: .anthropic) {
            return LLMConfiguration(
                provider: .anthropic,
                model: "claude-sonnet-5",
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try OpenAI
        if apiKeyStore.hasOpenAIKey, let key = try apiKeyStore.getKey(for: .openai) {
            return LLMConfiguration(
                provider: .openai,
                model: "gpt-4o",
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try OpenRouter
        if apiKeyStore.hasOpenRouterKey, let key = try apiKeyStore.getKey(for: .openrouter) {
            return LLMConfiguration(
                provider: .openrouter,
                model: "anthropic/claude-sonnet-5",
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try Custom
        if apiKeyStore.hasCustomKey,
           let key = try apiKeyStore.getKey(for: .custom),
           let baseURL = apiKeyStore.getCustomBaseURL(),
           let model = apiKeyStore.getCustomModel() {
            return LLMConfiguration(
                provider: .custom,
                model: model,
                apiKey: key,
                customBaseURL: baseURL
            )
        }
        
        return nil
    }
}
