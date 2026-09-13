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
    
    // Global configuration
    @Published var globalProvider: LLMProvider
    @Published var globalModel: String
    
    // Per-role overrides (nil = follow global)
    @Published private var roleOverrides: [GenerationRole: RoleOverride] = [:]
    
    struct RoleOverride {
        let provider: LLMProvider
        let model: String
    }
    
    init(apiKeyStore: APIKeyStore) {
        self.apiKeyStore = apiKeyStore
        
        // Load global config (with migration from old per-provider settings)
        let (provider, model) = Self.loadGlobalConfig(from: apiKeyStore)
        self.globalProvider = provider
        self.globalModel = model
        
        // Load role overrides
        self.roleOverrides = Self.loadRoleOverrides()
    }
    
    // MARK: - Global configuration
    
    private static func loadGlobalConfig(from store: APIKeyStore) -> (LLMProvider, String) {
        // Check if we have a saved global config
        if let savedProvider = UserDefaults.standard.string(forKey: "llm.global.provider"),
           let provider = LLMProvider(rawValue: savedProvider),
           let model = UserDefaults.standard.string(forKey: "llm.global.model"),
           !model.isEmpty {
            return (provider, model)
        }
        
        // Migration: use first available provider's model as global
        // Priority: Anthropic → OpenAI → OpenRouter
        if store.hasAnthropicKey, let model = store.getModel(for: .anthropic), !model.isEmpty {
            return (.anthropic, model)
        }
        if store.hasOpenAIKey, let model = store.getModel(for: .openai), !model.isEmpty {
            return (.openai, model)
        }
        if store.hasOpenRouterKey, let model = store.getModel(for: .openrouter), !model.isEmpty {
            return (.openrouter, model)
        }
        
        // Fallback defaults
        if store.hasAnthropicKey {
            return (.anthropic, "claude-sonnet-5")
        }
        if store.hasOpenAIKey {
            return (.openai, "gpt-4o")
        }
        if store.hasOpenRouterKey {
            return (.openrouter, "anthropic/claude-sonnet-5")
        }
        
        // No keys configured, return Anthropic default
        return (.anthropic, "claude-sonnet-5")
    }
    
    func setGlobalConfig(provider: LLMProvider, model: String) {
        self.globalProvider = provider
        self.globalModel = model
        
        // Persist
        UserDefaults.standard.set(provider.rawValue, forKey: "llm.global.provider")
        UserDefaults.standard.set(model, forKey: "llm.global.model")
        
        // Also update the legacy per-provider model for BYOK compatibility
        apiKeyStore.setModel(model, for: provider)
    }
    
    // MARK: - Role configuration
    
    private static func loadRoleOverrides() -> [GenerationRole: RoleOverride] {
        var overrides: [GenerationRole: RoleOverride] = [:]
        
        for role in GenerationRole.allCases {
            if let providerString = UserDefaults.standard.string(forKey: "llm.role.\(role.rawValue).provider"),
               let provider = LLMProvider(rawValue: providerString),
               let model = UserDefaults.standard.string(forKey: "llm.role.\(role.rawValue).model"),
               !model.isEmpty {
                overrides[role] = RoleOverride(provider: provider, model: model)
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
    
    func setRoleOverride(for role: GenerationRole, provider: LLMProvider, model: String) {
        roleOverrides[role] = RoleOverride(provider: provider, model: model)
        
        // Persist
        UserDefaults.standard.set(provider.rawValue, forKey: "llm.role.\(role.rawValue).provider")
        UserDefaults.standard.set(model, forKey: "llm.role.\(role.rawValue).model")
    }
    
    func resetToGlobal(role: GenerationRole) {
        roleOverrides[role] = nil
        
        // Remove from persistence
        UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).provider")
        UserDefaults.standard.removeObject(forKey: "llm.role.\(role.rawValue).model")
    }
    
    // MARK: - Effective configuration
    
    /// Get the effective provider and model for a role
    func getEffectiveConfig(for role: GenerationRole) -> (provider: LLMProvider, model: String) {
        if let override = roleOverrides[role] {
            return (override.provider, override.model)
        }
        return (globalProvider, globalModel)
    }
    
    /// Get LLM configuration for a role (ready for client creation)
    func getLLMConfig(for role: GenerationRole, temperature: Double = 0.7) throws -> LLMConfiguration {
        let (provider, model) = getEffectiveConfig(for: role)
        
        guard let apiKey = try apiKeyStore.getKey(for: provider) else {
            throw GenerationError.missingAPIKey(provider)
        }
        
        let customBaseURL: String?
        if provider == .custom {
            customBaseURL = apiKeyStore.getCustomBaseURL()
        } else {
            customBaseURL = nil
        }
        
        return LLMConfiguration(
            provider: provider,
            model: model,
            apiKey: apiKey,
            temperature: temperature,
            customBaseURL: customBaseURL
        )
    }
}
