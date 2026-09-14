import Foundation

/// Generation roles that can be configured
/// Note: Packager is not included as it's local-only (no LLM)
enum GenerationRole: String, CaseIterable, Identifiable {
    case planner
    case lessons
    case quizzes
    case demos
    case explain
    case discuss
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .planner: return "Planner"
        case .lessons: return "Lessons"
        case .quizzes: return "Quizzes"
        case .demos: return "Demos"
        case .explain: return "Explain"
        case .discuss: return "Discuss"
        }
    }
}

/// Service managing global LLM config + per-role overrides
@MainActor
class LLMRoleConfigService: ObservableObject {
    private let apiKeyStore: APIKeyStore
    private let customEndpointsStore: CustomEndpointsStore
    
    // Global configuration
    @Published var globalSelection: ProviderSelection
    @Published var globalModel: String
    
    // Per-role overrides (nil = follow global)
    @Published private var roleOverrides: [GenerationRole: RoleOverride] = [:]
    
    struct RoleOverride {
        let selection: ProviderSelection
        let model: String
    }
    
    // Legacy computed properties for compatibility
    var globalProvider: LLMProvider {
        switch globalSelection {
        case .fixed(let provider):
            return provider
        case .customEndpoint:
            return .custom
        }
    }
    
    init(apiKeyStore: APIKeyStore, customEndpointsStore: CustomEndpointsStore) {
        self.apiKeyStore = apiKeyStore
        self.customEndpointsStore = customEndpointsStore
        
        // Load global config (with migration from old per-provider settings)
        let (selection, model) = Self.loadGlobalConfig(from: apiKeyStore, customEndpoints: customEndpointsStore)
        self.globalSelection = selection
        self.globalModel = model
        
        // Load role overrides
        self.roleOverrides = Self.loadRoleOverrides(customEndpoints: customEndpointsStore)
    }
    
    // MARK: - Global configuration
    
    private static func loadGlobalConfig(from store: APIKeyStore, customEndpoints: CustomEndpointsStore) -> (ProviderSelection, String) {
        // Check if we have a saved global config with custom endpoint
        if let savedCustomEndpointString = UserDefaults.standard.string(forKey: "llm.global.customEndpointId"),
           let endpointId = UUID(uuidString: savedCustomEndpointString),
           let endpoint = customEndpoints.getEndpoint(id: endpointId),
           let model = UserDefaults.standard.string(forKey: "llm.global.model"),
           !model.isEmpty {
            return (.customEndpoint(endpointId), model)
        }
        
        // Check if we have a saved global config with fixed provider
        if let savedProvider = UserDefaults.standard.string(forKey: "llm.global.provider"),
           let provider = LLMProvider(rawValue: savedProvider),
           provider != .custom, // Ignore legacy .custom
           let model = UserDefaults.standard.string(forKey: "llm.global.model"),
           !model.isEmpty {
            return (.fixed(provider), model)
        }
        
        // Migration: use first available provider's model as global
        // Priority: Anthropic → OpenAI → OpenRouter → Custom endpoints
        if store.hasAnthropicKey, let model = store.getModel(for: .anthropic), !model.isEmpty {
            return (.fixed(.anthropic), model)
        }
        if store.hasOpenAIKey, let model = store.getModel(for: .openai), !model.isEmpty {
            return (.fixed(.openai), model)
        }
        if store.hasOpenRouterKey, let model = store.getModel(for: .openrouter), !model.isEmpty {
            return (.fixed(.openrouter), model)
        }
        
        // Check for configured custom endpoints
        if let firstEndpoint = customEndpoints.endpoints.first,
           customEndpoints.hasKey(for: firstEndpoint) {
            let model = firstEndpoint.defaultModel ?? ""
            return (.customEndpoint(firstEndpoint.id), model)
        }
        
        // Fallback defaults
        if store.hasAnthropicKey {
            return (.fixed(.anthropic), "claude-sonnet-5")
        }
        if store.hasOpenAIKey {
            return (.fixed(.openai), "gpt-4o")
        }
        if store.hasOpenRouterKey {
            return (.fixed(.openrouter), "anthropic/claude-sonnet-5")
        }
        
        // No keys configured, return Anthropic default
        return (.fixed(.anthropic), "claude-sonnet-5")
    }
    
    func setGlobalConfig(selection: ProviderSelection, model: String) {
        self.globalSelection = selection
        self.globalModel = model
        
        // Persist
        switch selection {
        case .fixed(let provider):
            UserDefaults.standard.set(provider.rawValue, forKey: "llm.global.provider")
            UserDefaults.standard.removeObject(forKey: "llm.global.customEndpointId")
            // Also update the legacy per-provider model for compatibility
            apiKeyStore.setModel(model, for: provider)
        case .customEndpoint(let endpointId):
            UserDefaults.standard.set(endpointId.uuidString, forKey: "llm.global.customEndpointId")
            UserDefaults.standard.removeObject(forKey: "llm.global.provider")
        }
        UserDefaults.standard.set(model, forKey: "llm.global.model")
    }
    
    // Legacy compatibility method
    func setGlobalConfig(provider: LLMProvider, model: String) {
        setGlobalConfig(selection: .fixed(provider), model: model)
    }
    
    // MARK: - Role configuration
    
    private static func loadRoleOverrides(customEndpoints: CustomEndpointsStore) -> [GenerationRole: RoleOverride] {
        var overrides: [GenerationRole: RoleOverride] = [:]
        
        for role in GenerationRole.allCases {
            let model = UserDefaults.standard.string(forKey: "llm.role.\(role.rawValue).model")
            
            // Check for custom endpoint override
            if let endpointIdString = UserDefaults.standard.string(forKey: "llm.role.\(role.rawValue).customEndpointId"),
               let endpointId = UUID(uuidString: endpointIdString),
               customEndpoints.getEndpoint(id: endpointId) != nil,
               let model = model, !model.isEmpty {
                overrides[role] = RoleOverride(selection: .customEndpoint(endpointId), model: model)
            }
            // Check for fixed provider override
            else if let providerString = UserDefaults.standard.string(forKey: "llm.role.\(role.rawValue).provider"),
                    let provider = LLMProvider(rawValue: providerString),
                    provider != .custom, // Ignore legacy .custom
                    let model = model, !model.isEmpty {
                overrides[role] = RoleOverride(selection: .fixed(provider), model: model)
            }
        }
        
        return overrides
    }
    
    func getRoleOverride(for role: GenerationRole) -> RoleOverride? {
        return roleOverrides[role]
    }
    
    func isFollowingGlobal(role: GenerationRole) -> Bool {
        return roleOverrides[role] == nil
    }
    
    func setRoleOverride(for role: GenerationRole, selection: ProviderSelection, model: String) {
        roleOverrides[role] = RoleOverride(selection: selection, model: model)
        
        // Persist
        switch selection {
        case .fixed(let provider):
            UserDefaults.standard.set(provider.rawValue, forKey: "llm.role.\(role.rawValue).provider")
            UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).customEndpointId")
        case .customEndpoint(let endpointId):
            UserDefaults.standard.set(endpointId.uuidString, forKey: "llm.role.\(role.rawValue).customEndpointId")
            UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).provider")
        }
        UserDefaults.standard.set(model, forKey: "llm.role.\(role.rawValue).model")
    }
    
    // Legacy compatibility method
    func setRoleOverride(for role: GenerationRole, provider: LLMProvider, model: String) {
        setRoleOverride(for: role, selection: .fixed(provider), model: model)
    }
    
    func resetToGlobal(role: GenerationRole) {
        roleOverrides[role] = nil
        
        // Remove from persistence
        UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).provider")
        UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).customEndpointId")
        UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).model")
    }
    
    // MARK: - Effective configuration
    
    /// Get the effective provider selection and model for a role
    func getEffectiveConfig(for role: GenerationRole) -> (selection: ProviderSelection, model: String) {
        if let override = roleOverrides[role] {
            return (override.selection, override.model)
        }
        return (globalSelection, globalModel)
    }
    
    /// Get LLM configuration for a role (ready for client creation)
    /// Temperature: uses global setting if set, otherwise nil (omit/provider default)
    func getLLMConfig(for role: GenerationRole) throws -> LLMConfiguration {
        let (selection, model) = getEffectiveConfig(for: role)
        
        let provider: LLMProvider
        let apiKey: String
        let customBaseURL: String?
        
        switch selection {
        case .fixed(let fixedProvider):
            provider = fixedProvider
            guard let key = try apiKeyStore.getKey(for: provider) else {
                throw GenerationError.missingAPIKey(provider)
            }
            apiKey = key
            customBaseURL = nil
            
        case .customEndpoint(let endpointId):
            provider = .custom
            guard let endpoint = customEndpointsStore.getEndpoint(id: endpointId) else {
                throw GenerationError.validationFailed("Custom endpoint not found")
            }
            guard let key = try customEndpointsStore.getKey(for: endpoint) else {
                throw GenerationError.missingAPIKey(.custom)
            }
            apiKey = key
            customBaseURL = endpoint.baseURL
        }
        
        // Get global temperature (nil = omit/provider default)
        let temperature = apiKeyStore.getGlobalTemperature()
        
        return LLMConfiguration(
            provider: provider,
            model: model,
            apiKey: apiKey,
            temperature: temperature,
            customBaseURL: customBaseURL
        )
    }
}
