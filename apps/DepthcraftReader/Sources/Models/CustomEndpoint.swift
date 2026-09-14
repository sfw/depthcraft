import Foundation

/// Named custom OpenAI-compatible endpoint
struct CustomEndpoint: Identifiable, Codable, Hashable {
    let id: UUID
    var label: String
    var baseURL: String
    var defaultModel: String?
    
    init(id: UUID = UUID(), label: String, baseURL: String, defaultModel: String? = nil) {
        self.id = id
        self.label = label
        self.baseURL = baseURL
        self.defaultModel = defaultModel
    }
    
    /// Display name for picker (label)
    var displayName: String {
        label
    }
    
    /// Keychain key for this endpoint's API key
    var keychainKey: String {
        "llm.custom.\(id.uuidString).apikey"
    }
}

/// Provider selection that can be either a fixed provider or a custom endpoint
enum ProviderSelection: Codable, Hashable, Identifiable {
    case fixed(LLMProvider)
    case customEndpoint(UUID)
    
    var id: String {
        switch self {
        case .fixed(let provider):
            return "fixed-\(provider.rawValue)"
        case .customEndpoint(let uuid):
            return "custom-\(uuid.uuidString)"
        }
    }
    
    var displayName: String {
        switch self {
        case .fixed(let provider):
            return provider.displayName
        case .customEndpoint:
            return "Custom Endpoint"
        }
    }
    
    /// Legacy LLMProvider if this is a fixed provider (for compatibility)
    var legacyProvider: LLMProvider? {
        switch self {
        case .fixed(let provider):
            return provider
        case .customEndpoint:
            return nil
        }
    }
}
