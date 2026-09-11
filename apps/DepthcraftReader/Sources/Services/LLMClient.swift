import Foundation

protocol LLMClient {
    func complete(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String
}

enum LLMClientError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case rateLimitError(provider: String, status: Int, message: String?)
    case invalidJSON
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimitError(let provider, let status, let message):
            if let message = message {
                return "\(provider) rate limit or quota exceeded (HTTP \(status)): \(message)\n\nPlease check your API quota and try again later, or switch providers."
            } else {
                return "\(provider) rate limit or quota exceeded (HTTP \(status)). Please check your API quota and try again later, or switch providers."
            }
        case .invalidJSON:
            return "Invalid JSON response"
        }
    }
}

class AnthropicClient: LLMClient {
    let apiKey: String
    let model: String
    
    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }
    
    func complete(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "temperature": temperature,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Parse error details
            var errorMessage: String? = nil
            var errorType: String? = nil
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any] {
                errorMessage = error["message"] as? String
                errorType = error["type"] as? String
            }
            
            // Check for rate limit / quota errors
            if httpResponse.statusCode == 429 ||
               errorType == "rate_limit_error" ||
               errorType == "overloaded_error" ||
               errorMessage?.lowercased().contains("rate limit") == true ||
               errorMessage?.lowercased().contains("quota") == true {
                throw LLMClientError.rateLimitError(
                    provider: "Anthropic",
                    status: httpResponse.statusCode,
                    message: errorMessage
                )
            }
            
            // Generic error
            if let errorMessage = errorMessage {
                throw LLMClientError.apiError(errorMessage)
            }
            throw LLMClientError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMClientError.invalidJSON
        }
        
        return text
    }
}

class OpenAIClient: LLMClient {
    let apiKey: String
    let model: String
    
    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }
    
    func complete(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Parse error details
            var errorMessage: String? = nil
            var errorType: String? = nil
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any] {
                errorMessage = error["message"] as? String
                errorType = error["type"] as? String
            }
            
            // Check for rate limit / quota errors
            if httpResponse.statusCode == 429 ||
               errorType == "insufficient_quota" ||
               errorType == "rate_limit_exceeded" ||
               errorMessage?.lowercased().contains("rate limit") == true ||
               errorMessage?.lowercased().contains("quota") == true {
                throw LLMClientError.rateLimitError(
                    provider: "OpenAI",
                    status: httpResponse.statusCode,
                    message: errorMessage
                )
            }
            
            // Generic error
            if let errorMessage = errorMessage {
                throw LLMClientError.apiError(errorMessage)
            }
            throw LLMClientError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMClientError.invalidJSON
        }
        
        return content
    }
}

class OpenRouterClient: LLMClient {
    let apiKey: String
    let model: String
    
    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }
    
    func complete(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Parse error details
            var errorMessage: String? = nil
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any] {
                errorMessage = error["message"] as? String
            }
            
            // Check for rate limit / quota errors
            if httpResponse.statusCode == 429 ||
               errorMessage?.lowercased().contains("rate limit") == true ||
               errorMessage?.lowercased().contains("quota") == true {
                throw LLMClientError.rateLimitError(
                    provider: "OpenRouter",
                    status: httpResponse.statusCode,
                    message: errorMessage
                )
            }
            
            // Generic error
            if let errorMessage = errorMessage {
                throw LLMClientError.apiError(errorMessage)
            }
            throw LLMClientError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMClientError.invalidJSON
        }
        
        return content
    }
}

class CustomOpenAIClient: LLMClient {
    let apiKey: String
    let model: String
    let baseURL: String
    
    init(apiKey: String, model: String, baseURL: String) {
        self.apiKey = apiKey
        self.model = model
        // Normalize trailing slash
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
    }
    
    func complete(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        let urlString = "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else {
            throw LLMClientError.apiError("Invalid custom base URL: \(baseURL)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "content-type")
        
        let body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Parse error details
            var errorMessage: String? = nil
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any] {
                errorMessage = error["message"] as? String
            }
            
            // Check for rate limit / quota errors
            if httpResponse.statusCode == 429 ||
               errorMessage?.lowercased().contains("rate limit") == true ||
               errorMessage?.lowercased().contains("quota") == true {
                throw LLMClientError.rateLimitError(
                    provider: "Custom endpoint",
                    status: httpResponse.statusCode,
                    message: errorMessage
                )
            }
            
            // Generic error
            if let errorMessage = errorMessage {
                throw LLMClientError.apiError(errorMessage)
            }
            throw LLMClientError.apiError("HTTP \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMClientError.invalidJSON
        }
        
        return content
    }
}

class LLMClientFactory {
    static func createClient(config: LLMConfiguration) throws -> LLMClient {
        switch config.provider {
        case .anthropic:
            return AnthropicClient(apiKey: config.apiKey, model: config.model)
        case .openai:
            return OpenAIClient(apiKey: config.apiKey, model: config.model)
        case .openrouter:
            return OpenRouterClient(apiKey: config.apiKey, model: config.model)
        case .custom:
            guard let baseURL = config.customBaseURL, !baseURL.isEmpty else {
                throw GenerationError.invalidResponse("Custom provider requires a base URL")
            }
            return CustomOpenAIClient(apiKey: config.apiKey, model: config.model, baseURL: baseURL)
        }
    }
}
