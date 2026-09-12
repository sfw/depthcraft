import Foundation

class PlannerService: PlannerRole {
    private let client: LLMClient
    private let temperature: Double
    
    init(client: LLMClient, temperature: Double = 0.7) {
        self.client = client
        self.temperature = temperature
    }
    
    func plan(topic: String, locale: String, knowledgeLevel: KnowledgeLevel, depthLevel: DepthLevel, extendingCurriculum: Curriculum? = nil) async throws -> Curriculum {
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
        - Output ONLY the JSON object, no markdown fences or explanatory text
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
            depthGuidance = "Keep the curriculum BRIEF. Cover only the most essential topics. Aim for approximately 2-3 units with 6-9 lessons total. Estimate 8-12 minutes per lesson."
        case .standard:
            depthGuidance = "Create a STANDARD curriculum. Balance breadth and depth appropriately. Aim for approximately 3-4 units with 9-12 lessons total. Estimate 10-15 minutes per lesson."
        case .deep:
            depthGuidance = "Create a DEEP curriculum. Go deeper into important concepts with more comprehensive coverage. Aim for approximately 4-5 units with 12-18 lessons total. Estimate 12-18 minutes per lesson."
        case .thorough:
            depthGuidance = "Create a THOROUGH curriculum. Cover the topic comprehensively with detailed exploration of key areas. Aim for approximately 5-6 units with 18-24 lessons total. Estimate 15-20 minutes per lesson."
        case .exhaustive:
            depthGuidance = "Create an EXHAUSTIVE curriculum. Provide extensive, comprehensive coverage with deep dives into all major aspects. Aim for approximately 6-8 units with 24-32 lessons total. Estimate 18-25 minutes per lesson."
        }
        
        let extensionConstraint: String
        if let extending = extendingCurriculum {
            let existingUnitIds = extending.units.map { $0.id }.sorted().joined(separator: ", ")
            let existingLessonIds = extending.lessons.keys.sorted().joined(separator: ", ")
            let existingUnits = extending.units.map { "\($0.id): \($0.title)" }.joined(separator: "\n")
            
            extensionConstraint = """
            
            CRITICAL EXTEND MODE:
            This is an EXTENSION of an existing curriculum. You must generate ONLY NEW units and lessons with COMPLETELY NEW IDs.
            
            Existing unit IDs (DO NOT REUSE): \(existingUnitIds)
            Existing lesson IDs (DO NOT REUSE): \(existingLessonIds)
            
            Existing curriculum structure:
            \(existingUnits)
            
            Requirements for extension:
            - Generate ONLY NEW units with NEW unique IDs (e.g., if prior has u01-u03, start at u04)
            - Generate ONLY NEW lessons with NEW unique IDs (use higher numbers than existing)
            - Do NOT re-emit, reshuffle, or reference any existing unit/lesson IDs
            - Build naturally on the existing content
            - Output ONLY the delta (new units/lessons), not the full curriculum
            """
        } else {
            extensionConstraint = ""
        }
        
        let userPrompt = """
        Create a curriculum for: \(topic)
        Locale: \(locale)
        
        Learner's current knowledge level: \(knowledgeGuidance)
        
        Desired depth: \(depthGuidance)\(extensionConstraint)
        
        Output ONLY the JSON curriculum, no markdown fences or explanatory text.
        """
        
        // Use higher max_tokens (8192) for planner to accommodate large Exhaustive curricula
        let response = try await client.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: 8192
        )
        
        // Use robust JSON extraction (same approach as QuizWriter)
        guard let extracted = JSONExtractor.extractJSON(from: response) else {
            throw GenerationError.invalidResponse("Could not extract valid JSON from response. Response: \(response.prefix(200))...")
        }
        
        // Validate JSON structure before decoding
        let structureValidation = JSONExtractor.validateJSONStructure(extracted, expectedTopLevelType: .object)
        guard structureValidation.isValid else {
            throw GenerationError.invalidResponse("Invalid JSON structure: \(structureValidation.errorMessage ?? "unknown"). Extracted: \(extracted.prefix(200))...")
        }
        
        guard let data = extracted.data(using: .utf8) else {
            throw GenerationError.invalidResponse("Could not encode extracted JSON as UTF-8")
        }
        
        do {
            let curriculum = try JSONDecoder().decode(Curriculum.self, from: data)
            return curriculum
        } catch {
            throw GenerationError.invalidResponse("Invalid curriculum JSON: \(error.localizedDescription). JSON snippet: \(extracted.prefix(300))...")
        }
    }
}
