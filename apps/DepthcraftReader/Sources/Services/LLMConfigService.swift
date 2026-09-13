import Foundation

/// Centralized LLM configuration service for BYOK
@MainActor
class LLMConfigService {
    private let apiKeyStore: APIKeyStore
    private let roleConfigService: LLMRoleConfigService
    
    init(apiKeyStore: APIKeyStore) {
        self.apiKeyStore = apiKeyStore
        self.roleConfigService = LLMRoleConfigService(apiKeyStore: apiKeyStore)
    }
    
    /// Check if we have any API key configured
    func hasAPIKey() -> Bool {
        return apiKeyStore.hasAnthropicKey ||
               apiKeyStore.hasOpenAIKey ||
               apiKeyStore.hasOpenRouterKey ||
               apiKeyStore.hasCustomKey
    }
    
    /// Get the first available LLM configuration for Explain role
    /// Uses the global/role configuration from Generate settings
    func getAvailableConfig() throws -> LLMConfiguration? {
        // Use Explain role config (which may follow global or be overridden)
        return try? roleConfigService.getLLMConfig(for: .explain, temperature: 0.7)
    }
    
    /// Get configuration for Discuss role
    func getDiscussConfig() throws -> LLMConfiguration? {
        return try? roleConfigService.getLLMConfig(for: .discuss, temperature: 0.7)
    }
}
