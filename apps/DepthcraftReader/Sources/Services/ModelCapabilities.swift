import Foundation

/// Resolves maximum output token limits for LLM providers and models
struct ModelCapabilities {
    
    /// Get the maximum output tokens for a given provider and model
    /// Returns the known model max, or a high fallback for unknown models
    /// NEVER returns more than the model's known capacity
    static func maxOutputTokens(provider: LLMProvider, model: String) -> Int {
        switch provider {
        case .anthropic:
            return anthropicMaxOutput(model: model)
        case .openai:
            return openaiMaxOutput(model: model)
        case .openrouter:
            return openrouterMaxOutput(model: model)
        case .custom:
            return customMaxOutput(model: model)
        }
    }
    
    // MARK: - Anthropic
    
    private static func anthropicMaxOutput(model: String) -> Int {
        let normalized = model.lowercased()
        
        // Claude 3.5 and newer (Sonnet, Opus, Haiku variants)
        // Anthropic max_tokens is 8192 for most Claude 3+ models (not total context, just output)
        if normalized.contains("claude-3") || 
           normalized.contains("claude-4") ||
           normalized.contains("claude-5") {
            return 8192
        }
        
        // Legacy Claude 2 models
        if normalized.contains("claude-2") {
            return 4096
        }
        
        // Fallback for unknown Anthropic models
        return 8192
    }
    
    // MARK: - OpenAI
    
    private static func openaiMaxOutput(model: String) -> Int {
        let normalized = model.lowercased()
        
        // GPT-4 and GPT-4 Turbo variants
        // GPT-4o, GPT-4o-mini, and similar have high output caps
        if normalized.contains("gpt-4o") {
            return 16384  // GPT-4o models support up to 16K output
        }
        
        if normalized.contains("gpt-4-turbo") || normalized.contains("gpt-4-1106") || normalized.contains("gpt-4-0125") {
            return 4096  // GPT-4 Turbo models support 4K output
        }
        
        if normalized.contains("gpt-4") {
            return 4096  // Standard GPT-4 supports 4K-8K output, use 4K safe
        }
        
        // o1 reasoning models (o1-preview, o1-mini)
        if normalized.contains("o1-preview") {
            return 32768  // o1-preview supports up to 32K output
        }
        
        if normalized.contains("o1-mini") {
            return 65536  // o1-mini supports up to 65K output
        }
        
        if normalized.contains("o1") {
            return 100000  // o1 (newer) supports up to 100K output
        }
        
        // GPT-3.5 Turbo
        if normalized.contains("gpt-3.5") {
            return 4096
        }
        
        // Fallback for unknown OpenAI models
        return 16384
    }
    
    // MARK: - OpenRouter
    
    private static func openrouterMaxOutput(model: String) -> Int {
        let normalized = model.lowercased()
        
        // OpenRouter routes to many providers - check for known model patterns
        
        // Anthropic models via OpenRouter
        if normalized.contains("claude") {
            return anthropicMaxOutput(model: model)
        }
        
        // OpenAI models via OpenRouter
        if normalized.contains("gpt") || normalized.contains("o1") {
            return openaiMaxOutput(model: model)
        }
        
        // Meta Llama models
        if normalized.contains("llama") {
            if normalized.contains("llama-3.3") || normalized.contains("llama-3.1") {
                return 32768  // Llama 3.3 and 3.1 support large outputs
            }
            return 8192  // Other Llama variants
        }
        
        // Google Gemini models
        if normalized.contains("gemini") {
            return 8192  // Gemini models typically support 8K output
        }
        
        // Mistral models
        if normalized.contains("mistral") {
            return 8192
        }
        
        // DeepSeek models
        if normalized.contains("deepseek") {
            if normalized.contains("r1") {
                return 65536  // DeepSeek R1 supports large outputs
            }
            return 8192
        }
        
        // Qwen models
        if normalized.contains("qwen") {
            return 32768  // Qwen models typically support large outputs
        }
        
        // High fallback for unknown OpenRouter models
        // OpenRouter handles many models with varying caps
        return 32768
    }
    
    // MARK: - Custom
    
    private static func customMaxOutput(model: String) -> Int {
        // Custom endpoints are OpenAI-compatible but unknown capacity
        // Use high fallback to avoid artificial truncation
        return 32768
    }
}
