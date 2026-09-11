import Foundation

class PlannerService: PlannerRole {
    private let client: LLMClient
    private let temperature: Double
    
    init(client: LLMClient, temperature: Double = 0.7) {
        self.client = client
        self.temperature = temperature
    }
    
    func plan(topic: String, locale: String, knowledgeLevel: KnowledgeLevel, depthLevel: DepthLevel) async throws -> Curriculum {
        let systemPrompt = """
        You are a curriculum planner for the Depthcraft learning platform. Your job is to create a structured curriculum map as JSON.
        
        Output ONLY valid JSON matching this schema:
        {
          "schemaVersion": "0.1.0",
          "status": "draft",
          "units": [
            {
              "id": "u01-foundations",
              "title": "Unit Title",
              "order": 1,
              "lessonIds": ["l01-lesson-one", "l02-lesson-two"]
            }
          ],
          "lessons": {
            "l01-lesson-one": {
              "id": "l01-lesson-one",
              "unitId": "u01-foundations",
              "title": "Lesson Title",
              "order": 1,
              "status": "draft",
              "estimatedMinutes": 12
            }
          }
        }
        
        Requirements:
        - Unit IDs: "u01-name", "u02-name" (lowercase, hyphenated)
        - Lesson IDs: "l01-name", "l02-name" (lowercase, hyphenated)
        - Order starts at 1
        - Status is always "draft" for new plans
        - All lesson IDs in unit.lessonIds must exist in lessons dict
        """
        
        let knowledgeGuidance: String
        switch knowledgeLevel {
        case .new:
            knowledgeGuidance = "The learner is NEW to this topic. Include foundational concepts, basic terminology, and clear explanations of fundamentals. Start from first principles."
        case .some:
            knowledgeGuidance = "The learner has SOME knowledge of this topic. Include key foundations but move through basics at a moderate pace. Brief review of fundamentals is helpful."
        case .working:
            knowledgeGuidance = "The learner has WORKING knowledge. Skip basic terminology. Focus on intermediate concepts, practical application, and building on assumed foundations."
        case .strong:
            knowledgeGuidance = "The learner has STRONG knowledge. Compress or skip foundations. Focus on advanced concepts, nuances, and sophisticated applications."
        case .expert:
            knowledgeGuidance = "The learner is an EXPERT. Assume deep familiarity. Focus on cutting-edge topics, subtle distinctions, expert-level patterns, and advanced techniques."
        }
        
        let depthGuidance: String
        switch depthLevel {
        case .brief:
            depthGuidance = "Keep the curriculum BRIEF. Cover only the most essential topics. Estimate 8-12 minutes per lesson."
        case .standard:
            depthGuidance = "Create a STANDARD curriculum. Balance breadth and depth appropriately. Estimate 10-15 minutes per lesson."
        case .deep:
            depthGuidance = "Create a DEEP curriculum. Go deeper into important concepts with more comprehensive coverage. Estimate 12-18 minutes per lesson."
        case .thorough:
            depthGuidance = "Create a THOROUGH curriculum. Cover the topic comprehensively with detailed exploration of key areas. Estimate 15-20 minutes per lesson."
        case .exhaustive:
            depthGuidance = "Create an EXHAUSTIVE curriculum. Provide extensive, comprehensive coverage with deep dives into all major aspects. Estimate 18-25 minutes per lesson."
        }
        
        let userPrompt = """
        Create a curriculum for: \(topic)
        Locale: \(locale)
        
        Learner's current knowledge level: \(knowledgeGuidance)
        
        Desired depth: \(depthGuidance)
        
        Output ONLY the JSON curriculum, no markdown fences or explanatory text.
        """
        
        let response = try await client.complete(systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: temperature)
        
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw GenerationError.invalidResponse("Could not encode response as UTF-8")
        }
        
        do {
            let curriculum = try JSONDecoder().decode(Curriculum.self, from: data)
            return curriculum
        } catch {
            throw GenerationError.invalidResponse("Invalid curriculum JSON: \(error.localizedDescription)")
        }
    }
}
