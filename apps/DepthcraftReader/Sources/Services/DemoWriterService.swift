import Foundation

class DemoWriterService: DemoWriterRole {
    private let client: LLMClient
    private let temperature: Double
    private let depthLevel: DepthLevel
    
    init(client: LLMClient, temperature: Double = 0.7, depthLevel: DepthLevel) {
        self.client = client
        self.temperature = temperature
        self.depthLevel = depthLevel
    }
    
    func writeDemos(lessonMarkdown: String, lesson: CurriculumLesson, unit: CurriculumUnit) async throws -> DemoWriterOutput? {
        let systemPrompt = """
        You are a demo writer for the Depthcraft learning platform. You create OPTIONAL interactive demos that show-not-tell when it meaningfully aids understanding.
        
        CRITICAL RULES:
        - Demos are OPTIONAL. Return empty JSON array if lesson doesn't warrant one
        - NEVER emit filler demos. Zero demos is better than a weak demo
        - Kit allowlist: ONLY "three-v0" (bundled Three.js). NO other libraries
        - ALWAYS emit fallback.md for every demo
        - NO external URLs (http/https) anywhere in demo files
        - NO mid-flight fetch/XHR in JavaScript
        - Entry HTML must use ES modules from kit only
        - Demos are shown inline at :::demo::: directive position
        
        DENSITY RULES:
        - Brief depth: 0-1 demos per COURSE max
        - Standard depth: sparse (most lessons have zero)
        - Deep/Thorough/Exhaustive: selective shown-not-told only
        
        Current depth level: \(depthLevel.displayName)
        
        WHEN TO EMIT A DEMO:
        - Spatial/visual concepts hard to describe in text (3D transforms, coordinate systems)
        - Interactive exploration aids understanding (NOT decoration)
        - Kit primitives suffice (simple Three.js scenes)
        
        WHEN NOT TO EMIT:
        - Lesson is conceptual/text-based
        - Demo would be decorative only
        - Requires external libraries not in kit
        - Static diagram suffices
        
        OUTPUT FORMAT (JSON only, no markdown fences):
        {
          "demos": [
            {
              "demoId": "kebab-case-id",
              "title": "Brief title",
              "kit": "three-v0",
              "entry": "index.html",
              "fallback": "fallback.md",
              "entryHTML": "<!DOCTYPE html>\\n<html>...</html>",
              "fallbackMarkdown": "# Demo Unavailable\\n\\nFallback explanation...",
              "insertAfterHeading": "## Section Name",
              "assets": {
                "scene.js": "// JavaScript content..."
              }
            }
          ]
        }
        
        - demos: array (EMPTY if no demo warranted)
        - demoId: unique kebab-case within lesson
        - title: concise demo purpose
        - kit: MUST be "three-v0"
        - entry: MUST be "index.html"
        - fallback: MUST be "fallback.md"
        - entryHTML: complete HTML file (ES modules, kit-only imports)
        - fallbackMarkdown: complete fallback content (always required)
        - insertAfterHeading: heading text to insert demo after (must exist in lesson.md)
        - assets: optional dict of filename->content for additional JS/JSON files
        
        ENTRY HTML REQUIREMENTS:
        - Import from kit path: <script type="module" src="../../../../../../demo-kits/three-v0/three.module.min.js"></script>
        - NO CDN URLs, NO external fetch calls
        - Self-contained scene in HTML or split into assets
        
        FALLBACK REQUIREMENTS:
        - Brief markdown explaining what demo shows
        - Key concepts in text form
        - Always include even for simple demos
        
        Output ONLY raw JSON object. No markdown fences, no explanatory text.
        """
        
        let userPrompt = """
        Review this lesson and decide if an interactive demo is warranted.
        
        Lesson: \(lesson.title)
        Unit: \(unit.title)
        
        Content:
        \(lessonMarkdown)
        
        If demo warranted: emit ONE demo with complete HTML/JS. If not: return {"demos": []}
        
        Remember: Output ONLY the JSON object.
        """
        
        let response = try await client.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: 8192
        )
        
        return try decodeDemoResponse(response, lessonId: lesson.id)
    }
    
    private func decodeDemoResponse(_ response: String, lessonId: String) throws -> DemoWriterOutput? {
        guard let extracted = JSONExtractor.extractJSON(from: response) else {
            throw GenerationError.invalidResponse("Could not extract valid JSON from demo writer response")
        }
        
        let structureValidation = JSONExtractor.validateJSONStructure(extracted, expectedTopLevelType: .object)
        guard structureValidation.isValid else {
            throw GenerationError.invalidResponse("Invalid JSON structure: \(structureValidation.errorMessage ?? "unknown")")
        }
        
        guard let data = extracted.data(using: .utf8) else {
            throw GenerationError.invalidResponse("Could not encode extracted JSON as UTF-8")
        }
        
        do {
            let output = try JSONDecoder().decode(DemoWriterOutput.self, from: data)
            
            if output.demos.isEmpty {
                return nil
            }
            
            for demo in output.demos {
                try validateDemo(demo, lessonId: lessonId)
            }
            
            return output
        } catch let error as GenerationError {
            throw error
        } catch let decodingError as DecodingError {
            let message = decodingErrorMessage(decodingError)
            throw GenerationError.invalidResponse("Demo JSON decode failed: \(message)")
        } catch {
            throw GenerationError.invalidResponse("Demo JSON decode failed: \(error.localizedDescription)")
        }
    }
    
    private func validateDemo(_ demo: DemoSpec, lessonId: String) throws {
        guard !demo.demoId.isEmpty else {
            throw GenerationError.validationFailed("Demo has empty demoId")
        }
        
        guard !demo.title.isEmpty else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' has empty title")
        }
        
        guard demo.kit == "three-v0" else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' uses unsupported kit '\(demo.kit)'. Only 'three-v0' is allowed")
        }
        
        guard demo.entry == "index.html" else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' entry must be 'index.html', got '\(demo.entry)'")
        }
        
        guard demo.fallback == "fallback.md" else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' fallback must be 'fallback.md', got '\(demo.fallback)'")
        }
        
        guard !demo.entryHTML.isEmpty else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' has empty entryHTML")
        }
        
        guard !demo.fallbackMarkdown.isEmpty else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' has empty fallbackMarkdown")
        }
        
        guard !demo.insertAfterHeading.isEmpty else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' has empty insertAfterHeading")
        }
        
        try validateNoExternalURLs(demo.entryHTML, demoId: demo.demoId, file: "index.html")
        
        for (filename, content) in demo.assets ?? [:] {
            try validateNoExternalURLs(content, demoId: demo.demoId, file: filename)
        }
        
        try validateNoMidFlightFetch(demo.entryHTML, demoId: demo.demoId, file: "index.html")
        
        for (filename, content) in demo.assets ?? [:] {
            if filename.hasSuffix(".js") {
                try validateNoMidFlightFetch(content, demoId: demo.demoId, file: filename)
            }
        }
    }
    
    private func validateNoExternalURLs(_ content: String, demoId: String, file: String) throws {
        let urlPatterns = [
            "http://",
            "https://",
            "//cdn",
            "//unpkg",
            "//jsdelivr"
        ]
        
        for pattern in urlPatterns {
            if content.contains(pattern) {
                throw GenerationError.validationFailed("Demo '\(demoId)' file '\(file)' contains external URL pattern '\(pattern)'")
            }
        }
    }
    
    private func validateNoMidFlightFetch(_ content: String, demoId: String, file: String) throws {
        let fetchPatterns = [
            "fetch(",
            "XMLHttpRequest",
            "new XMLHttpRequest",
            ".ajax("
        ]
        
        for pattern in fetchPatterns {
            if content.contains(pattern) {
                throw GenerationError.validationFailed("Demo '\(demoId)' file '\(file)' contains mid-flight fetch pattern '\(pattern)'")
            }
        }
    }
    
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

struct DemoWriterOutput: Codable {
    let demos: [DemoSpec]
}

struct DemoSpec: Codable {
    let demoId: String
    let title: String
    let kit: String
    let entry: String
    let fallback: String
    let entryHTML: String
    let fallbackMarkdown: String
    let insertAfterHeading: String
    let assets: [String: String]?
}
