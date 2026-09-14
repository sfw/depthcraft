import Foundation

/// Centralized LLM configuration service for BYOK
@MainActor
class LLMConfigService {
    private let apiKeyStore: APIKeyStore
    private let customEndpointsStore: CustomEndpointsStore
    private let roleConfigService: LLMRoleConfigService
    
    init(apiKeyStore: APIKeyStore, customEndpointsStore: CustomEndpointsStore) {
        self.apiKeyStore = apiKeyStore
        self.customEndpointsStore = customEndpointsStore
        self.roleConfigService = LLMRoleConfigService(apiKeyStore: apiKeyStore, customEndpointsStore: customEndpointsStore)
        
        // Migrate legacy custom endpoint on init
        customEndpointsStore.migrateLegacyCustomEndpoint(from: apiKeyStore)
    }
    
    /// Check if we have any API key configured
    func hasAPIKey() -> Bool {
        let hasFixedProvider = apiKeyStore.hasAnthropicKey ||
                              apiKeyStore.hasOpenAIKey ||
                              apiKeyStore.hasOpenRouterKey
        let hasCustomEndpoint = customEndpointsStore.endpoints.contains { customEndpointsStore.hasKey(for: $0) }
        return hasFixedProvider || hasCustomEndpoint
    }
    
    /// Get the first available LLM configuration for Explain role
    /// Uses the global/role configuration from Generate settings
    func getAvailableConfig() throws -> LLMConfiguration? {
        // Use Explain role config (which may follow global or be overridden)
        return try? roleConfigService.getLLMConfig(for: .explain)
    }
    
    /// Get configuration for Discuss role
    func getDiscussConfig() throws -> LLMConfiguration? {
        return try? roleConfigService.getLLMConfig(for: .discuss)
    }
}
