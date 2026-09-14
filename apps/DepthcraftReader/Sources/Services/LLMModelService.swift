import Foundation

/// Service for fetching available models from LLM providers
@MainActor
class LLMModelService: ObservableObject {
    private let apiKeyStore: APIKeyStore
    private var customEndpointsStore: CustomEndpointsStore?
    
    // Cache models for 1 hour
    private var cachedModels: [String: CachedModels] = [:]
    private let cacheTimeout: TimeInterval = 3600
    
    init(apiKeyStore: APIKeyStore, customEndpointsStore: CustomEndpointsStore? = nil) {
        self.apiKeyStore = apiKeyStore
        self.customEndpointsStore = customEndpointsStore
    }
    
    struct ModelInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let providerType: String  // "anthropic", "openai", etc. or endpoint ID
        
        var displayName: String {
            // For OpenRouter, strip provider prefix for display
            if providerType == "openrouter" && name.contains("/") {
                return name.split(separator: "/").last.map(String.init) ?? name
            }
            return name
        }
    }
    
    enum FetchError: LocalizedError {
        case noAPIKey
        case networkError(Error)
        case invalidResponse
        case apiError(String)
        
        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid response from API"
            case .apiError(let message):
                return message
            }
        }
    }
    
    private struct CachedModels {
        let models: [ModelInfo]
        let fetchedAt: Date
        
        var isExpired: Bool {
            Date().timeIntervalSince(fetchedAt) > 3600
        }
    }
    
    /// Fetch available models for a provider selection
    func fetchModels(for selection: ProviderSelection) async throws -> [ModelInfo] {
        switch selection {
        case .fixed(let provider):
            return try await fetchModels(for: provider)
        case .customEndpoint(let endpointId):
            return try await fetchModelsForCustomEndpoint(endpointId: endpointId)
        }
    }
    
    /// Fetch available models for a fixed provider
    func fetchModels(for provider: LLMProvider) async throws -> [ModelInfo] {
        let cacheKey = provider.rawValue
        
        // Check cache first
        if let cached = cachedModels[cacheKey], !cached.isExpired {
            return cached.models
        }
        
        // Get API key
        guard let apiKey = try apiKeyStore.getKey(for: provider) else {
            throw FetchError.noAPIKey
        }
        
        let models: [ModelInfo]
        
        switch provider {
        case .anthropic:
            models = try await fetchAnthropicModels(apiKey: apiKey)
        case .openai:
            models = try await fetchOpenAIModels(apiKey: apiKey)
        case .openrouter:
            models = try await fetchOpenRouterModels(apiKey: apiKey)
        case .custom:
            // Legacy custom endpoint - should not be used anymore
            guard let baseURL = apiKeyStore.getCustomBaseURL() else {
                throw FetchError.apiError("Custom endpoint requires base URL")
            }
            models = try await fetchCustomModels(apiKey: apiKey, baseURL: baseURL, providerType: "custom")
        }
        
        // Cache results
        cachedModels[cacheKey] = CachedModels(models: models, fetchedAt: Date())
        
        return models
    }
    
    /// Fetch available models for a custom endpoint
    func fetchModelsForCustomEndpoint(endpointId: UUID) async throws -> [ModelInfo] {
        guard let customEndpointsStore = customEndpointsStore else {
            throw FetchError.apiError("Custom endpoints not available")
        }
        
        guard let endpoint = customEndpointsStore.getEndpoint(id: endpointId) else {
            throw FetchError.apiError("Custom endpoint not found")
        }
        
        let cacheKey = endpointId.uuidString
        
        // Check cache first
        if let cached = cachedModels[cacheKey], !cached.isExpired {
            return cached.models
        }
        
        // Get API key
        guard let apiKey = try customEndpointsStore.getKey(for: endpoint) else {
            throw FetchError.noAPIKey
        }
        
        let models = try await fetchCustomModels(apiKey: apiKey, baseURL: endpoint.baseURL, providerType: endpointId.uuidString)
        
        // Cache results
        cachedModels[cacheKey] = CachedModels(models: models, fetchedAt: Date())
        
        return models
    }
    
    /// Clear cached models for a provider or endpoint
    func clearCache(for selection: ProviderSelection? = nil) {
        if let selection = selection {
            let cacheKey: String
            switch selection {
            case .fixed(let provider):
                cacheKey = provider.rawValue
            case .customEndpoint(let endpointId):
                cacheKey = endpointId.uuidString
            }
            cachedModels[cacheKey] = nil
        } else {
            cachedModels.removeAll()
        }
    }
    
    /// Legacy method for compatibility
    func clearCache(for provider: LLMProvider? = nil) {
        if let provider = provider {
            clearCache(for: .fixed(provider))
        } else {
            cachedModels.removeAll()
        }
    }
    
    // MARK: - Provider-specific fetchers
    
    private func fetchAnthropicModels(apiKey: String) async throws -> [ModelInfo] {
        let url = URL(string: "https://api.anthropic.com/v1/models")!
        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FetchError.apiError(message)
            }
            throw FetchError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw FetchError.invalidResponse
        }
        
        return dataArray.compactMap { modelData in
            guard let id = modelData["id"] as? String else { return nil }
            return ModelInfo(id: id, name: id, providerType: "anthropic")
        }.sorted { $0.name < $1.name }
    }
    
    private func fetchOpenAIModels(apiKey: String) async throws -> [ModelInfo] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FetchError.apiError(message)
            }
            throw FetchError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw FetchError.invalidResponse
        }
        
        // Filter to only chat models
        return dataArray.compactMap { modelData in
            guard let id = modelData["id"] as? String,
                  id.contains("gpt") || id.contains("o1") || id.contains("o3") else { return nil }
            return ModelInfo(id: id, name: id, providerType: "openai")
        }.sorted { $0.name < $1.name }
    }
    
    private func fetchOpenRouterModels(apiKey: String) async throws -> [ModelInfo] {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FetchError.apiError(message)
            }
            throw FetchError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw FetchError.invalidResponse
        }
        
        return dataArray.compactMap { modelData in
            guard let id = modelData["id"] as? String else { return nil }
            return ModelInfo(id: id, name: id, providerType: "openrouter")
        }.sorted { $0.name < $1.name }
    }
    
    private func fetchCustomModels(apiKey: String, baseURL: String, providerType: String) async throws -> [ModelInfo] {
        let normalizedURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let urlString = "\(normalizedURL)/models"
        guard let url = URL(string: urlString) else {
            throw FetchError.apiError("Invalid base URL")
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FetchError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw FetchError.apiError(message)
            }
            throw FetchError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw FetchError.invalidResponse
        }
        
        return dataArray.compactMap { modelData in
            guard let id = modelData["id"] as? String else { return nil }
            return ModelInfo(id: id, name: id, providerType: providerType)
        }.sorted { $0.name < $1.name }
    }
}
