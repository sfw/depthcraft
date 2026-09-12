import Foundation
import Security

enum KeychainStorage {
    private static let service = "dev.depthcraft.reader"
    
    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case deleteFailed(OSStatus)
        case dataConversionFailed
        
        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to Keychain: \(status)"
            case .loadFailed(let status):
                return "Failed to load from Keychain: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain: \(status)"
            case .dataConversionFailed:
                return "Failed to convert data"
            }
        }
    }
    
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        var status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            
            status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    static func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        
        return value
    }
    
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

@MainActor
class APIKeyStore: ObservableObject {
    @Published var hasAnthropicKey: Bool = false
    @Published var hasOpenAIKey: Bool = false
    @Published var hasOpenRouterKey: Bool = false
    @Published var hasCustomKey: Bool = false
    @Published var customBaseURL: String = ""
    @Published var customModel: String = ""
    
    private let anthropicKey = "llm.anthropic.apikey"
    private let openaiKey = "llm.openai.apikey"
    private let openrouterKey = "llm.openrouter.apikey"
    private let customKey = "llm.custom.apikey"
    
    private let customBaseURLKey = "llm.custom.baseurl"
    private let customModelKey = "llm.custom.model"
    
    // User's configured model per provider (for BYOK tap-to-explain/Discuss)
    private let anthropicModelKey = "llm.anthropic.model"
    private let openaiModelKey = "llm.openai.model"
    private let openrouterModelKey = "llm.openrouter.model"
    
    init() {
        refreshStatus()
    }
    
    func refreshStatus() {
        hasAnthropicKey = (try? KeychainStorage.load(key: anthropicKey)) != nil
        hasOpenAIKey = (try? KeychainStorage.load(key: openaiKey)) != nil
        hasOpenRouterKey = (try? KeychainStorage.load(key: openrouterKey)) != nil
        hasCustomKey = (try? KeychainStorage.load(key: customKey)) != nil
        customBaseURL = UserDefaults.standard.string(forKey: customBaseURLKey) ?? ""
        customModel = UserDefaults.standard.string(forKey: customModelKey) ?? ""
    }
    
    func getKey(for provider: LLMProvider) throws -> String? {
        let key = keyString(for: provider)
        return try KeychainStorage.load(key: key)
    }
    
    func setKey(_ value: String, for provider: LLMProvider) throws {
        let key = keyString(for: provider)
        try KeychainStorage.save(key: key, value: value)
        refreshStatus()
    }
    
    func deleteKey(for provider: LLMProvider) throws {
        let key = keyString(for: provider)
        try KeychainStorage.delete(key: key)
        refreshStatus()
    }
    
    func getCustomBaseURL() -> String? {
        let url = UserDefaults.standard.string(forKey: customBaseURLKey)
        return url?.isEmpty == false ? url : nil
    }
    
    func setCustomBaseURL(_ value: String) {
        UserDefaults.standard.set(value, forKey: customBaseURLKey)
        customBaseURL = value
    }
    
    func getCustomModel() -> String? {
        let model = UserDefaults.standard.string(forKey: customModelKey)
        return model?.isEmpty == false ? model : nil
    }
    
    func setCustomModel(_ value: String) {
        UserDefaults.standard.set(value, forKey: customModelKey)
        customModel = value
    }
    
    /// Get user's configured model for a provider (for tap-to-explain/Discuss)
    func getModel(for provider: LLMProvider) -> String? {
        switch provider {
        case .anthropic:
            return UserDefaults.standard.string(forKey: anthropicModelKey)
        case .openai:
            return UserDefaults.standard.string(forKey: openaiModelKey)
        case .openrouter:
            return UserDefaults.standard.string(forKey: openrouterModelKey)
        case .custom:
            return getCustomModel()
        }
    }
    
    /// Set user's configured model for a provider
    func setModel(_ value: String, for provider: LLMProvider) {
        switch provider {
        case .anthropic:
            UserDefaults.standard.set(value, forKey: anthropicModelKey)
        case .openai:
            UserDefaults.standard.set(value, forKey: openaiModelKey)
        case .openrouter:
            UserDefaults.standard.set(value, forKey: openrouterModelKey)
        case .custom:
            setCustomModel(value)
        }
    }
    
    private func keyString(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic: return anthropicKey
        case .openai: return openaiKey
        case .openrouter: return openrouterKey
        case .custom: return customKey
        }
    }
}
