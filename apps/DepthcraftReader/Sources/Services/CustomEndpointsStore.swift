import Foundation

/// Storage and management for named custom endpoints
@MainActor
class CustomEndpointsStore: ObservableObject {
    @Published private(set) var endpoints: [CustomEndpoint] = []
    
    private let endpointsKey = "llm.customEndpoints"
    
    init() {
        loadEndpoints()
    }
    
    // MARK: - Persistence
    
    private func loadEndpoints() {
        guard let data = UserDefaults.standard.data(forKey: endpointsKey),
              let decoded = try? JSONDecoder().decode([CustomEndpoint].self, from: data) else {
            endpoints = []
            return
        }
        endpoints = decoded
    }
    
    private func saveEndpoints() {
        guard let data = try? JSONEncoder().encode(endpoints) else { return }
        UserDefaults.standard.set(data, forKey: endpointsKey)
    }
    
    // MARK: - CRUD Operations
    
    func add(_ endpoint: CustomEndpoint) {
        endpoints.append(endpoint)
        saveEndpoints()
    }
    
    func update(_ endpoint: CustomEndpoint) {
        if let index = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[index] = endpoint
            saveEndpoints()
        }
    }
    
    func delete(_ endpoint: CustomEndpoint) {
        endpoints.removeAll { $0.id == endpoint.id }
        saveEndpoints()
        
        // Also clean up keychain
        try? KeychainStorage.delete(key: endpoint.keychainKey)
    }
    
    func getEndpoint(id: UUID) -> CustomEndpoint? {
        return endpoints.first { $0.id == id }
    }
    
    // MARK: - Key Management
    
    func hasKey(for endpoint: CustomEndpoint) -> Bool {
        return (try? KeychainStorage.load(key: endpoint.keychainKey)) != nil
    }
    
    func getKey(for endpoint: CustomEndpoint) throws -> String? {
        return try KeychainStorage.load(key: endpoint.keychainKey)
    }
    
    func setKey(_ key: String, for endpoint: CustomEndpoint) throws {
        try KeychainStorage.save(key: endpoint.keychainKey, value: key)
    }
    
    func deleteKey(for endpoint: CustomEndpoint) throws {
        try KeychainStorage.delete(key: endpoint.keychainKey)
    }
    
    // MARK: - Migration
    
    /// Migrate legacy single custom endpoint to named endpoint
    func migrateLegacyCustomEndpoint(from apiKeyStore: APIKeyStore) {
        // Only migrate if there's a legacy custom endpoint configured and no named endpoints yet
        guard endpoints.isEmpty,
              apiKeyStore.hasCustomKey,
              !apiKeyStore.customBaseURL.isEmpty else {
            return
        }
        
        // Extract host from base URL for label
        let baseURL = apiKeyStore.customBaseURL
        let label: String
        if let url = URL(string: baseURL), let host = url.host {
            label = host
        } else {
            label = "Custom"
        }
        
        // Create new named endpoint
        let endpoint = CustomEndpoint(
            label: label,
            baseURL: baseURL,
            defaultModel: apiKeyStore.customModel.isEmpty ? nil : apiKeyStore.customModel
        )
        
        // Copy key from legacy location to new location
        if let legacyKey = try? apiKeyStore.getKey(for: .custom) {
            try? setKey(legacyKey, for: endpoint)
        }
        
        // Add to endpoints
        add(endpoint)
        
        // Clean up legacy storage
        try? apiKeyStore.deleteKey(for: .custom)
        apiKeyStore.setCustomBaseURL("")
        apiKeyStore.setCustomModel("")
    }
}
