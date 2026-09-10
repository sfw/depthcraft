import Foundation

class PlannerService: PlannerRole {
    private let client: LLMClient
    
    init(client: LLMClient) {
        self.client = client
    }
    
    func plan(topic: String, locale: String) async throws -> Curriculum {
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
        - Estimate 10-15 minutes per lesson
        - Create 2-3 units with 2-3 lessons each
        - All lesson IDs in unit.lessonIds must exist in lessons dict
        """
        
        let userPrompt = """
        Create a curriculum for: \(topic)
        Locale: \(locale)
        
        Output ONLY the JSON curriculum, no markdown fences or explanatory text.
        """
        
        let response = try await client.complete(systemPrompt: systemPrompt, userPrompt: userPrompt)
        
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
