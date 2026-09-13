import Foundation

/// Robust JSON extraction from LLM responses that may contain markdown fences,
/// trailing commentary, or other formatting artifacts.
struct JSONExtractor {
    
    /// Extract JSON from a response that may contain markdown fences, commentary, or other text.
    /// Tries multiple strategies to find valid JSON:
    /// 1. Clean obvious markdown fences and try the whole content
    /// 2. Find JSON boundaries (first '{' or '[' to last '}' or ']')
    /// 3. Try multiple JSON candidates if response contains several objects
    /// 4. Try the original trimmed content as-is
    static func extractJSON(from response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { return nil }
        
        // Strategy 1: Clean markdown fences and try the whole content
        if let cleaned = cleanMarkdownFences(trimmed) {
            if isLikelyValidJSON(cleaned) && validatesParseable(cleaned) {
                return cleaned
            }
        }
        
        // Strategy 2: Find JSON boundaries (first open to last close bracket)
        if let extracted = extractByBoundaries(trimmed) {
            if isLikelyValidJSON(extracted) && validatesParseable(extracted) {
                return extracted
            }
        }
        
        // Strategy 3: Try the original trimmed content as-is
        if isLikelyValidJSON(trimmed) && validatesParseable(trimmed) {
            return trimmed
        }
        
        // Strategy 4: Extract multiple JSON candidates and try each
        if let candidates = extractMultipleCandidates(trimmed) {
            for candidate in candidates {
                if isLikelyValidJSON(candidate) && validatesParseable(candidate) {
                    return candidate
                }
            }
        }
        
        return nil
    }
    
    /// Clean markdown code fences (```json, ```, etc.)
    private static func cleanMarkdownFences(_ text: String) -> String? {
        var cleaned = text
        
        // Remove opening fence with optional language tag
        // Matches: ```json, ```JSON, ``` json, ```
        let openingPattern = "^```\\s*[a-zA-Z]*\\s*\n?"
        if let regex = try? NSRegularExpression(pattern: openingPattern, options: [.anchorsMatchLines]) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        
        // Remove closing fence
        let closingPattern = "\n?\\s*```\\s*$"
        if let regex = try? NSRegularExpression(pattern: closingPattern, options: []) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: ""
            )
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned.isEmpty ? nil : cleaned
    }
    
    /// Extract JSON by finding first opening bracket to last closing bracket
    private static func extractByBoundaries(_ text: String) -> String? {
        // Find first occurrence of { or [
        guard let firstOpen = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }
        
        // Find last occurrence of } or ]
        guard let lastClose = text.lastIndex(where: { $0 == "}" || $0 == "]" }) else {
            return nil
        }
        
        // Ensure the closing bracket comes after the opening
        guard firstOpen < lastClose else {
            return nil
        }
        
        let extracted = String(text[firstOpen...lastClose])
        return extracted.isEmpty ? nil : extracted
    }
    
    /// Quick heuristic check if a string is likely valid JSON
    /// Checks for basic structure without full parsing
    private static func isLikelyValidJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Must start with { or [
        guard trimmed.first == "{" || trimmed.first == "[" else {
            return false
        }
        
        // Must end with } or ]
        guard trimmed.last == "}" || trimmed.last == "]" else {
            return false
        }
        
        // Must have matching brackets (rough check)
        let openBraces = trimmed.filter { $0 == "{" }.count
        let closeBraces = trimmed.filter { $0 == "}" }.count
        let openBrackets = trimmed.filter { $0 == "[" }.count
        let closeBrackets = trimmed.filter { $0 == "]" }.count
        
        return openBraces == closeBraces && openBrackets == closeBrackets
    }
    
    /// Validate that a candidate string actually parses as JSON
    private static func validatesParseable(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else {
            return false
        }
        
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
    
    /// Extract multiple JSON candidates from text that may contain several JSON objects
    /// Returns candidates in order of likelihood (largest/outermost first)
    private static func extractMultipleCandidates(_ text: String) -> [String]? {
        var candidates: [String] = []
        
        // Find all potential JSON object/array boundaries
        var depth = 0
        var startIndex: String.Index?
        var inString = false
        var escapeNext = false
        
        for (index, char) in text.enumerated() {
            let stringIndex = text.index(text.startIndex, offsetBy: index)
            
            // Reset string state on newline (JSON strings can't contain unescaped newlines)
            // If we're in a string at a newline, the JSON is malformed — abandon it
            if char == "\n" || char == "\r" {
                if inString && !escapeNext {
                    // Malformed JSON with unclosed string - abandon this candidate
                    inString = false
                    depth = 0
                    startIndex = nil
                }
                escapeNext = false
            }
            
            // Track string boundaries to avoid counting brackets inside strings
            if char == "\"" && !escapeNext {
                inString.toggle()
            }
            
            if char == "\\" && !escapeNext {
                escapeNext = true
                continue
            } else {
                escapeNext = false
            }
            
            if inString {
                continue
            }
            
            // Track bracket depth
            if char == "{" || char == "[" {
                if depth == 0 {
                    startIndex = stringIndex
                }
                depth += 1
            } else if char == "}" || char == "]" {
                depth -= 1
                if depth == 0, let start = startIndex {
                    let candidate = String(text[start...stringIndex])
                    candidates.append(candidate)
                    startIndex = nil
                }
            }
        }
        
        return candidates.isEmpty ? nil : candidates
    }
    
    /// Try to decode and validate JSON structure, returning a diagnostic message if invalid
    static func validateJSONStructure(_ jsonString: String, expectedTopLevelType: ExpectedJSONType = .object) -> ValidationResult {
        guard let data = jsonString.data(using: .utf8) else {
            return .invalid("Could not encode JSON string as UTF-8")
        }
        
        do {
            let parsed = try JSONSerialization.jsonObject(with: data, options: [])
            
            switch expectedTopLevelType {
            case .object:
                guard parsed is [String: Any] else {
                    return .invalid("Expected JSON object ({}), got \(type(of: parsed))")
                }
            case .array:
                guard parsed is [Any] else {
                    return .invalid("Expected JSON array ([]), got \(type(of: parsed))")
                }
            case .any:
                break
            }
            
            return .valid
        } catch {
            return .invalid("JSON parse error: \(error.localizedDescription)")
        }
    }
    
    enum ExpectedJSONType {
        case object
        case array
        case any
    }
    
    enum ValidationResult {
        case valid
        case invalid(String)
        
        var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
        
        var errorMessage: String? {
            if case .invalid(let message) = self { return message }
            return nil
        }
    }
}
