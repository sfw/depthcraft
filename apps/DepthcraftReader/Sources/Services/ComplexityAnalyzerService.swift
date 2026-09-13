import Foundation

class ComplexityAnalyzerService {
    private let client: LLMClient
    private let temperature: Double?
    private let depthLevel: DepthLevel
    private let provider: LLMProvider
    private let model: String
    
    init(client: LLMClient, temperature: Double? = nil, depthLevel: DepthLevel, provider: LLMProvider, model: String) {
        self.client = client
        self.temperature = temperature
        self.depthLevel = depthLevel
        self.provider = provider
        self.model = model
    }
    
    func analyzeComplexity(markdown: String, lessonTitle: String, lessonId: String) async throws -> [LessonMeta.Anchor] {
        let maxAnchors = maxAnchorsForDepth()
        
        guard maxAnchors > 0 else {
            return []
        }
        
        let systemPrompt = """
        You are a complexity analyzer for educational content. Identify technical terms or concepts that would benefit from brief, accessible explanations.
        
        Focus on:
        - Technical jargon or domain-specific terms
        - Complex concepts that require prerequisite knowledge
        - Terms that might be unfamiliar to learners
        
        Guidelines:
        - Be selective: only \(maxAnchors) most impactful terms
        - Choose terms that appear in the lesson text verbatim (for exact matching)
        - Write concise glosses (2-3 sentences, plain language)
        - Warm, editorial tone (not Wikipedia-dry)
        
        Return ONLY valid JSON matching this structure:
        {
          "anchors": [
            {
              "term": "exact text from lesson",
              "kind": "concept",
              "gloss": "Brief explanation in 2-3 sentences."
            }
          ]
        }
        
        Use kind values: "concept" for technical terms, "prerequisite" for background knowledge needed.
        """
        
        let userPrompt = """
        Lesson: \(lessonTitle)
        
        Content:
        \(markdown)
        
        Identify up to \(maxAnchors) terms that need explanation. Return JSON with anchors array.
        """
        
        let maxTokens = ModelCapabilities.maxOutputTokens(provider: provider, model: model)
        
        let response: String
        do {
            response = try await client.complete(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maxTokens: maxTokens
            )
        } catch let error as LLMClientError {
            // Wrap LLM client errors with stage name for UI
            throw GenerationError.invalidResponse("Complexity: \(error.localizedDescription)")
        }
        
        let anchors = try parseComplexityResponse(response, lessonId: lessonId)
        return Array(anchors.prefix(maxAnchors))
    }
    
    private func maxAnchorsForDepth() -> Int {
        switch depthLevel {
        case .brief: return 1
        case .standard: return 2
        case .deep: return 3
        case .thorough: return 4
        case .exhaustive: return 5
        }
    }
    
    private func parseComplexityResponse(_ response: String, lessonId: String) throws -> [LessonMeta.Anchor] {
        // Check for truncated JSON first
        if let truncationDiagnostic = JSONExtractor.detectTruncation(response) {
            throw GenerationError.invalidResponse("Complexity: \(truncationDiagnostic). The response was likely cut off due to output length limits. Try again or use a model with higher output capacity. Response start: \(response.prefix(150))...")
        }
        
        // Extract JSON with robust extraction
        guard let jsonString = JSONExtractor.extractJSON(from: response) else {
            throw GenerationError.invalidResponse("Complexity: Could not extract valid JSON from response. Response snippet: \(response.prefix(200))...")
        }
        
        // Validate JSON structure before decoding
        let structureValidation = JSONExtractor.validateJSONStructure(jsonString, expectedTopLevelType: .object)
        guard structureValidation.isValid else {
            throw GenerationError.invalidResponse("Complexity: Invalid JSON structure - \(structureValidation.errorMessage ?? "unknown error"). Extracted JSON start: \(jsonString.prefix(200))...")
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GenerationError.invalidResponse("Complexity: JSON encoding failed - Could not encode extracted JSON as UTF-8")
        }
        
        // Decode with detailed error
        let parsed: ComplexityResponse
        do {
            parsed = try JSONDecoder().decode(ComplexityResponse.self, from: jsonData)
        } catch {
            throw GenerationError.invalidResponse("Complexity: JSON decode failed - \(error.localizedDescription). JSON snippet: \(jsonString.prefix(300))...")
        }
        
        return parsed.anchors.enumerated().map { index, item in
            let anchorId = "\(lessonId)-explain-\(index + 1)"
            
            // Validate kind against allowed enum values
            let validKind: String
            if ["concept", "prerequisite"].contains(item.kind) {
                validKind = item.kind
            } else {
                validKind = "concept" // Default to concept if LLM returns invalid kind
            }
            
            return LessonMeta.Anchor(
                id: anchorId,
                heading: item.term,
                kind: validKind,
                term: item.term,
                gloss: item.gloss
            )
        }
    }
}

private struct ComplexityResponse: Codable {
    let anchors: [ComplexityAnchor]
    
    struct ComplexityAnchor: Codable {
        let term: String
        let kind: String
        let gloss: String
    }
}
