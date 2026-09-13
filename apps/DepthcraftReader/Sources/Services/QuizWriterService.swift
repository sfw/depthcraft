import Foundation

class QuizWriterService: QuizWriterRole {
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
    
    func writeQuiz(lessonMarkdown: String, lesson: CurriculumLesson, unit: CurriculumUnit) async throws -> QuizDocument {
        let itemCount: String
        switch depthLevel {
        case .brief:
            itemCount = "2"
        case .standard:
            itemCount = "2-3"
        case .deep:
            itemCount = "3-4"
        case .thorough:
            itemCount = "4-5"
        case .exhaustive:
            itemCount = "5-7"
        }
        
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
        
        let depthGuidance: String
        switch depthLevel {
        case .brief:
            depthGuidance = "Brief (essentials only)"
        case .standard:
            depthGuidance = "Standard (balanced coverage)"
        case .deep:
            depthGuidance = "Deep (comprehensive with examples)"
        case .thorough:
            depthGuidance = "Thorough (detailed exploration)"
        case .exhaustive:
            depthGuidance = "Exhaustive (deep dive, all angles)"
        }
        
        let systemPrompt = """
        You are a quiz writer for the Depthcraft learning platform. Create engaging, fair quiz questions based on the lesson content.
        
        Output ONLY valid JSON. Do not include markdown code fences, explanatory text, or commentary.
        
        CRITICAL: Use these EXACT field names (case-sensitive):
        - "schemaVersion" (string, must be "0.1.0")
        - "lessonId" (string)
        - "items" (array)
        - For MC items: "id", "type", "prompt", "choices", "correctId", "explain"
        - For choices: "id", "text"
        - For cloze items: "id", "type", "prompt", "answers", "explain"
        
        JSON schema:
        {
          "schemaVersion": "0.1.0",
          "lessonId": "lesson-id-here",
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
        - Create \(itemCount) questions total
        - Mix of mc (multiple choice) and cloze (fill-in-blank)
        - MC: 3-4 choices, one correct (use "choices" field, not "options")
        - Cloze: single word or short phrase answers (2-3 words max, use "answers" field)
        - All cloze answers will be graded with Unicode casefold + trim
        - Include helpful "explain" for each question (optional but recommended)
        - Questions should test understanding, not just recall
        - Calibrate difficulty to learner's knowledge level
        
        Output ONLY the raw JSON object. No markdown, no fences, no explanatory text before or after.
        """
        
        let userPrompt = """
        Course topic: \(topic)
        Unit: \(unit.title)
        Lesson: \(lesson.title)
        
        Learner knowledge level: \(knowledgeGuidance)
        Depth level: \(depthGuidance)
        
        Lesson content:
        \(lessonMarkdown)
        
        Use lessonId: \(lesson.id)
        
        Create \(itemCount) questions calibrated to the learner's knowledge level.
        
        Remember: Output ONLY the JSON object with no additional text or formatting.
        """
        
        // Use full model max - no artificial caps
        let maxTokens = ModelCapabilities.maxOutputTokens(provider: provider, model: model)
        
        let response = try await client.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        // Try to extract and decode JSON with robust handling
        return try decodeQuizResponse(response, expectedLessonId: lesson.id)
    }
    
    /// Decode quiz JSON with robust extraction and validation
    private func decodeQuizResponse(_ response: String, expectedLessonId: String) throws -> QuizDocument {
        // Attempt 1: Try to extract JSON using robust extractor
        guard let extracted = JSONExtractor.extractJSON(from: response) else {
            throw GenerationError.invalidResponse("Quiz Writer returned invalid JSON: Could not extract valid JSON from response. Response snippet: \(response.prefix(200))...")
        }
        
        // Validate JSON structure before decoding
        let structureValidation = JSONExtractor.validateJSONStructure(extracted, expectedTopLevelType: .object)
        guard structureValidation.isValid else {
            throw GenerationError.invalidResponse("Quiz Writer returned invalid JSON structure: \(structureValidation.errorMessage ?? "unknown"). Extracted: \(extracted.prefix(200))...")
        }
        
        // Pre-decode validation: check for required fields
        if let validationError = validateQuizJSONFields(extracted) {
            throw GenerationError.invalidResponse("Quiz Writer JSON missing required fields: \(validationError). JSON: \(extracted.prefix(300))...")
        }
        
        // Attempt to decode
        guard let data = extracted.data(using: .utf8) else {
            throw GenerationError.invalidResponse("Quiz Writer JSON encoding failed: Could not encode extracted JSON as UTF-8")
        }
        
        do {
            let quiz = try JSONDecoder().decode(QuizDocument.self, from: data)
            
            // Post-decode validation
            guard quiz.schemaVersion == "0.1.0" else {
                throw GenerationError.validationFailed("Quiz schemaVersion must be '0.1.0', got '\(quiz.schemaVersion)'")
            }
            
            guard quiz.lessonId == expectedLessonId else {
                throw GenerationError.validationFailed("Quiz lessonId mismatch: expected '\(expectedLessonId)', got '\(quiz.lessonId)'")
            }
            
            guard !quiz.items.isEmpty else {
                throw GenerationError.validationFailed("Quiz has no items")
            }
            
            // Validate each item
            for item in quiz.items {
                try validateQuizItem(item)
            }
            
            return quiz
        } catch let error as GenerationError {
            throw error
        } catch let decodingError as DecodingError {
            let message = decodingErrorMessage(decodingError)
            throw GenerationError.invalidResponse("Quiz JSON decode failed: \(message). JSON snippet: \(extracted.prefix(300))...")
        } catch {
            throw GenerationError.invalidResponse("Quiz JSON decode failed: \(error.localizedDescription)")
        }
    }
    
    /// Pre-decode validation: check for required top-level fields in raw JSON
    private func validateQuizJSONFields(_ jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Not a valid JSON object"
        }
        
        // Check required top-level fields
        guard json["schemaVersion"] != nil else {
            return "Missing 'schemaVersion' field"
        }
        
        guard json["lessonId"] is String else {
            return "Missing or invalid 'lessonId' field (must be string)"
        }
        
        guard let items = json["items"] as? [[String: Any]], !items.isEmpty else {
            return "Missing or empty 'items' array"
        }
        
        // Check each item has required fields
        for (index, item) in items.enumerated() {
            guard let type = item["type"] as? String else {
                return "Item \(index): missing 'type' field"
            }
            
            guard item["id"] is String else {
                return "Item \(index): missing 'id' field"
            }
            
            guard item["prompt"] is String else {
                return "Item \(index): missing 'prompt' field"
            }
            
            switch type {
            case "mc":
                guard let choices = item["choices"] as? [[String: Any]], !choices.isEmpty else {
                    return "Item \(index): MC question missing or empty 'choices' array (not 'options')"
                }
                
                guard item["correctId"] is String else {
                    return "Item \(index): MC question missing 'correctId' field"
                }
                
                // Validate choices structure
                for (choiceIndex, choice) in choices.enumerated() {
                    guard choice["id"] is String else {
                        return "Item \(index), choice \(choiceIndex): missing 'id' field"
                    }
                    guard choice["text"] is String else {
                        return "Item \(index), choice \(choiceIndex): missing 'text' field"
                    }
                }
                
            case "cloze":
                guard let answers = item["answers"] as? [String], !answers.isEmpty else {
                    return "Item \(index): Cloze question missing or empty 'answers' array"
                }
                
            default:
                return "Item \(index): unknown question type '\(type)' (must be 'mc' or 'cloze')"
            }
        }
        
        return nil
    }
    
    /// Validate a decoded quiz item
    private func validateQuizItem(_ item: QuizItem) throws {
        switch item {
        case .mc(let mcItem):
            guard !mcItem.id.isEmpty else {
                throw GenerationError.validationFailed("MC item has empty id")
            }
            guard !mcItem.prompt.isEmpty else {
                throw GenerationError.validationFailed("MC item '\(mcItem.id)' has empty prompt")
            }
            guard mcItem.choices.count >= 2 else {
                throw GenerationError.validationFailed("MC item '\(mcItem.id)' has fewer than 2 choices")
            }
            guard mcItem.choices.contains(where: { $0.id == mcItem.correctId }) else {
                throw GenerationError.validationFailed("MC item '\(mcItem.id)' correctId '\(mcItem.correctId)' not found in choices")
            }
            for choice in mcItem.choices {
                guard !choice.id.isEmpty && !choice.text.isEmpty else {
                    throw GenerationError.validationFailed("MC item '\(mcItem.id)' has choice with empty id or text")
                }
            }
            
        case .cloze(let clozeItem):
            guard !clozeItem.id.isEmpty else {
                throw GenerationError.validationFailed("Cloze item has empty id")
            }
            guard !clozeItem.prompt.isEmpty else {
                throw GenerationError.validationFailed("Cloze item '\(clozeItem.id)' has empty prompt")
            }
            guard !clozeItem.answers.isEmpty else {
                throw GenerationError.validationFailed("Cloze item '\(clozeItem.id)' has empty answers array")
            }
            for answer in clozeItem.answers {
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GenerationError.validationFailed("Cloze item '\(clozeItem.id)' has empty or whitespace-only answer")
                }
            }
        }
    }
    
    /// Generate a helpful error message from DecodingError
    private func decodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value: expected \(type) at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")). \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")). \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Data corrupted at \(context.codingPath.map { $0.stringValue }.joined(separator: ".")). \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
