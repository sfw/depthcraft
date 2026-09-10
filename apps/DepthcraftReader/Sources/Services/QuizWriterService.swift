import Foundation

class QuizWriterService: QuizWriterRole {
    private let client: LLMClient
    
    init(client: LLMClient) {
        self.client = client
    }
    
    func writeQuiz(lessonMarkdown: String, lesson: CurriculumLesson) async throws -> QuizDocument {
        let systemPrompt = """
        You are a quiz writer for the Depthcraft learning platform. Create engaging, fair quiz questions based on the lesson content.
        
        Output ONLY valid JSON matching this schema:
        {
          "schemaVersion": "0.1.0",
          "lessonId": "lesson-id",
          "items": [
            {
              "id": "q1",
              "type": "mc",
              "prompt": "Question text?",
              "choices": [
                {"id": "a", "text": "Choice A"},
                {"id": "b", "text": "Choice B"},
                {"id": "c", "text": "Choice C"}
              ],
              "correctId": "b",
              "explain": "Why this is correct"
            },
            {
              "id": "q2",
              "type": "cloze",
              "prompt": "The model proposes; the _____ validates.",
              "answers": ["harness"],
              "explain": "Brief explanation"
            }
          ]
        }
        
        Requirements:
        - Create 2-3 questions total
        - Mix of mc (multiple choice) and cloze (fill-in-blank)
        - MC: 3-4 choices, one correct
        - Cloze: single word or short phrase answers (2-3 words max)
        - All cloze answers will be graded with Unicode casefold + trim
        - Include helpful "explain" for each question
        - Questions should test understanding, not just recall
        """
        
        let userPrompt = """
        Create a quiz for this lesson:
        
        \(lessonMarkdown)
        
        Lesson ID: \(lesson.id)
        
        Output ONLY the JSON quiz, no markdown fences or explanatory text.
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
            let quiz = try JSONDecoder().decode(QuizDocument.self, from: data)
            
            guard quiz.lessonId == lesson.id else {
                throw GenerationError.validationFailed("Quiz lessonId mismatch")
            }
            
            guard !quiz.items.isEmpty else {
                throw GenerationError.validationFailed("Quiz has no items")
            }
            
            return quiz
        } catch let error as GenerationError {
            throw error
        } catch {
            throw GenerationError.invalidResponse("Invalid quiz JSON: \(error.localizedDescription)")
        }
    }
}
