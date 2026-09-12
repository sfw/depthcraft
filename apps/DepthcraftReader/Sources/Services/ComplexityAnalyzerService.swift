import Foundation

class ComplexityAnalyzerService {
    private let client: LLMClient
    private let temperature: Double
    private let depthLevel: DepthLevel
    
    init(client: LLMClient, temperature: Double = 0.5, depthLevel: DepthLevel) {
        self.client = client
        self.temperature = temperature
        self.depthLevel = depthLevel
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
        
        let response = try await client.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: 2048
        )
        
        guard let anchors = try? parseComplexityResponse(response, lessonId: lessonId) else {
            return []
        }
        
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
        let extractor = JSONExtractor()
        guard let jsonString = extractor.extract(from: response),
              let jsonData = jsonString.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ComplexityResponse.self, from: jsonData) else {
            throw GenerationError.invalidResponse("Could not parse complexity analysis JSON")
        }
        
        return parsed.anchors.enumerated().map { index, item in
            let anchorId = "explain-\(index + 1)"
            return LessonMeta.Anchor(
                id: anchorId,
                heading: item.term,
                kind: item.kind,
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
