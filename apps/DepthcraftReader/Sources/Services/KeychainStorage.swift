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
    
    private let anthropicKey = "llm.anthropic.apikey"
    private let openaiKey = "llm.openai.apikey"
    private let openrouterKey = "llm.openrouter.apikey"
    
    init() {
        refreshStatus()
    }
    
    func refreshStatus() {
        hasAnthropicKey = (try? KeychainStorage.load(key: anthropicKey)) != nil
        hasOpenAIKey = (try? KeychainStorage.load(key: openaiKey)) != nil
        hasOpenRouterKey = (try? KeychainStorage.load(key: openrouterKey)) != nil
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
    
    private func keyString(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic: return anthropicKey
        case .openai: return openaiKey
        case .openrouter: return openrouterKey
        }
    }
}
