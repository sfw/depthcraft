import Foundation

class ComplexityAnalyzerService {
    private let client: LLMClient
    private let temperature: Double?
    private let topic: String
    private let knowledgeLevel: KnowledgeLevel
    private let depthLevel: DepthLevel
    private let provider: LLMProvider
    private let model: String
    
    init(client: LLMClient, temperature: Double? = nil, topic: String, knowledgeLevel: KnowledgeLevel, depthLevel: DepthLevel, provider: LLMProvider, model: String) {
        self.client = client
        self.temperature = temperature
        self.topic = topic
        self.knowledgeLevel = knowledgeLevel
        self.depthLevel = depthLevel
        self.provider = provider
        self.model = model
    }
    
    func analyzeComplexity(markdown: String, lessonTitle: String, lessonId: String) async throws -> (anchors: [LessonMeta.Anchor], llmMetadata: LLMResponse) {
        let knowledgeGuidance: String
        switch knowledgeLevel {
        case .new:
            knowledgeGuidance = "NEW to this topic (foundational concepts, basic terminology)"
        case .some:
            knowledgeGuidance = "SOME knowledge (key foundations, moderate pace)"
        case .working:
            knowledgeGuidance = "WORKING knowledge (skip basics, intermediate concepts)"
        case .strong:
            knowledgeGuidance = "STRONG knowledge (compress foundations, advanced concepts)"
        case .expert:
            knowledgeGuidance = "EXPERT (deep familiarity, cutting-edge topics)"
        }
        
        let systemPrompt = """
        You are a complexity analyzer for educational content. Identify technical terms or concepts that would benefit from brief, accessible explanations.
        
        Focus on:
        - Technical jargon or domain-specific terms
        - Complex concepts that require prerequisite knowledge
        - Terms that might be unfamiliar to learners at this knowledge level
        
        Guidelines:
        - Be selective: calibrate to the learner's knowledge level
        - Anchors = verbatim spans from the lesson (term → multi-word phrase → short clause)
        - Use the shortest span that uniquely marks the hard idea
        - Write warm, editorial glosses (2-3 sentences, plain language)
        - Soft safety cap: 24 anchors maximum (but be selective, not exhaustive)
        
        Return ONLY valid JSON matching this structure:
        {
          "anchors": [
            {
              "term": "exact verbatim span from lesson",
              "kind": "concept",
              "gloss": "Warm, editorial explanation in 2-3 sentences."
            }
          ]
        }
        
        Use kind values: "concept" for technical terms, "prerequisite" for background knowledge needed.
        """
        
        let userPrompt = """
        Course topic: \(topic)
        Lesson: \(lessonTitle)
        
        Learner knowledge level: \(knowledgeGuidance)
        
        Content:
        \(markdown)
        
        Identify terms that need explanation, calibrated to the learner's knowledge level. Be selective. Return JSON with anchors array.
        """
        
        // Use full model max - no artificial caps
        let maxTokens = ModelCapabilities.maxOutputTokens(provider: provider, model: model)
        
        let response: String
        let llmResponse: LLMResponse
        do {
            llmResponse = try await client.completeWithMetadata(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maxTokens: maxTokens
            )
            response = llmResponse.text
        } catch let error as LLMClientError {
            // Wrap LLM client errors with stage name for UI
            throw GenerationError.invalidResponse("Complexity: \(error.localizedDescription)")
        }
        
        let anchors = try parseComplexityResponse(response, lessonId: lessonId)
        
        // Soft safety cap: trim to 24 if model overfires
        return (anchors: Array(anchors.prefix(24)), llmMetadata: llmResponse)
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
