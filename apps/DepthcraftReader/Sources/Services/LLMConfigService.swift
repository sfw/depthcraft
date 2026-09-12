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
    /// Uses user's configured models from Generate settings
    func getAvailableConfig() throws -> LLMConfiguration? {
        // Try Anthropic first
        if apiKeyStore.hasAnthropicKey, let key = try apiKeyStore.getKey(for: .anthropic) {
            guard let model = apiKeyStore.getModel(for: .anthropic), !model.isEmpty else {
                throw GlossServiceError.noModelConfigured(provider: "Anthropic")
            }
            return LLMConfiguration(
                provider: .anthropic,
                model: model,
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try OpenAI
        if apiKeyStore.hasOpenAIKey, let key = try apiKeyStore.getKey(for: .openai) {
            guard let model = apiKeyStore.getModel(for: .openai), !model.isEmpty else {
                throw GlossServiceError.noModelConfigured(provider: "OpenAI")
            }
            return LLMConfiguration(
                provider: .openai,
                model: model,
                apiKey: key,
                customBaseURL: nil
            )
        }
        
        // Try OpenRouter
        if apiKeyStore.hasOpenRouterKey, let key = try apiKeyStore.getKey(for: .openrouter) {
            guard let model = apiKeyStore.getModel(for: .openrouter), !model.isEmpty else {
                throw GlossServiceError.noModelConfigured(provider: "OpenRouter")
            }
            return LLMConfiguration(
                provider: .openrouter,
                model: model,
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
