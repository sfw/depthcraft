import Foundation

class DemoWriterService: DemoWriterRole {
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
    
    func writeDemos(lessonMarkdown: String, lesson: CurriculumLesson, unit: CurriculumUnit) async throws -> DemoWriterOutput? {
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
        You are a demo writer for the Depthcraft learning platform. You create OPTIONAL interactive demos ONLY when they meaningfully aid understanding through active manipulation.
        
        CRITICAL QUALITY BAR:
        - BIAS HARD TO NO DEMO. Empty demos array is STRONGLY PREFERRED over weak/decorative demos
        - Demos are expensive (time/tokens). The bar is VERY HIGH
        - ONLY emit a demo if the learner must ACT in a way prose cannot substitute
        - Must enable: manipulate a spatial idea, run a procedure, test a hypothesis with feedback
        - NEVER emit filler demos just because a lesson seems "complex" — zero demos > weak demo
        
        EXPLICIT REJECT LIST (NEVER emit these):
        - Decorative orbiting/spinning scenes with no learner agency
        - Title splash screens or visual embellishment
        - "Visualize the concept" demos where learner input doesn't change meaningful state
        - Demos where interaction is cosmetic (click to change color but no learning feedback)
        - Kit-fake / missing-API workarounds (if three-v0 can't support it → NO DEMO)
        
        REQUIRED FIELDS PER DEMO:
        - learningGoal: one-line string stating what the learner gains by interacting (not what the demo shows)
        - fallback.md: MUST teach the SAME learningGoal if WebView fails. Not a summary; a standalone lesson snippet
        
        THREE-V0 CAPABILITY GATE:
        - Kit allowlist: ONLY "three-v0" (bundled Three.js r170). NO ui-v0, NO other libraries
        - If the interaction requires APIs not in core Three.js r170 → return {"demos":[]} — do not fake it
        - NO external URLs (http/https) anywhere in demo files
        - NO mid-flight fetch/XHR in JavaScript
        
        PRODUCT RULES (preserve existing):
        - Earn-it density (not scarcity): emit 0–N demos per lesson with soft safety cap of 8
        - Prefer playable interactive loops (learner acts; try/fail/retry) over passive vignettes
        - Platform: iPadOS/iOS touch-first (no hover-only interactions; large hit targets)
        - Entry HTML must use ES modules from kit only
        - Demos shown inline at :::demo::: directive position
        
        WHEN TO EMIT (rare):
        - Spatial/visual manipulation required (3D transforms, coordinate system exploration)
        - Interactive feedback loop teaches through action (NOT passive observation)
        - Kit primitives suffice (simple Three.js core API only)
        
        WHEN NOT TO EMIT (vast majority):
        - Lesson is conceptual/text-based
        - Demo would be decorative only
        - Requires external libraries not in kit
        - Static diagram or animated GIF suffices
        - Interaction is shallow (no meaningful state change or learning feedback)
        
        THREE-V0 KIT CARD (AUTHORITATIVE):
        - Three.js version: r170
        - Available import: 'kit:three-v0/three.module.min.js' (exports entire THREE namespace)
        - What Reader injects: Full Three.js r170 module with core objects (Scene, Camera, WebGLRenderer, geometries, materials, lights, loaders)
        - What is NOT available: No CDN access, no fetch calls, no external addons, no OrbitControls or other helpers not in core Three.js
        - If needed API is missing from core Three.js r170: return no demo (empty array)
        
        OUTPUT FORMAT (JSON only, no markdown fences):
        {
          "demos": [
            {
              "demoId": "kebab-case-id",
              "title": "Brief title",
              "learningGoal": "What learner gains by interacting (one line)",
              "kit": "three-v0",
              "entry": "index.html",
              "fallback": "fallback.md",
              "entryHTML": "<!DOCTYPE html>\\n<html>\\n<head><title>Demo</title></head>\\n<body>\\n<script type=\\"module\\">\\nimport * as THREE from 'kit:three-v0/three.module.min.js';\\n// Kit import succeeded - now safe to create canvas\\nconst canvas = document.createElement('canvas');\\ncanvas.id = 'c';\\ndocument.body.appendChild(canvas);\\n// Demo code that renders to canvas\\n</script>\\n</body>\\n</html>",
              "fallbackMarkdown": "# Learning Goal\\n\\n[Teach the same learningGoal in prose]\\n\\n...",
              "insertAfterHeading": "## Section Name",
              "assets": {
                "scene.js": "// JavaScript content..."
              }
            }
          ]
        }
        
        - demos: array (EMPTY if no demo warranted; 0–N demos with soft cap 8)
        - demoId: unique kebab-case within lesson
        - title: concise demo purpose
        - learningGoal: REQUIRED one-line string (what learner gains through interaction)
        - kit: MUST be "three-v0"
        - entry: MUST be "index.html"
        - fallback: MUST be "fallback.md"
        - entryHTML: complete HTML file (ES modules, kit-only imports)
        - fallbackMarkdown: complete fallback content teaching SAME learningGoal (always required)
        - insertAfterHeading: heading text to insert demo after (must exist in lesson.md)
        - assets: optional dict of filename->content for additional JS/JSON files
        
        ENTRY HTML REQUIREMENTS:
        - Use stable kit import placeholder: import * as THREE from 'kit:three-v0/three.module.min.js'
        - This is a placeholder convention; live Three.js requires Reader kit injection (not yet implemented)
        - NO static canvas in HTML body - create canvas in JS ONLY AFTER successful kit import
        - NO decorative chrome (#info divs, loading text, or painted UI elements) before kit success
        - If kit import fails, body must remain blank so Reader fallback triggers automatically
        - NO CDN URLs, NO external fetch calls
        - Self-contained scene in HTML or split into assets
        - Touch-first: large hit targets, no hover-only
        
        FALLBACK REQUIREMENTS:
        - Brief markdown teaching the SAME learningGoal if demo unavailable
        - NOT just "demo unavailable" — must be a standalone lesson snippet
        - Key concepts in text form with same learning outcome
        - Always include even for simple demos
        
        DEPTH LEVEL GUIDANCE:
        - Exhaustive depth does NOT mean "more demos" — it means higher quality bar for necessary demos only
        - Brief/Standard depth → extremely rare demos (only if critical spatial manipulation required)
        - Deep/Thorough/Exhaustive → slightly more likely, but ONLY if interaction aids understanding
        
        Output ONLY raw JSON object. No markdown fences, no explanatory text.
        """
        
        let userPrompt = """
        Course topic: \(topic)
        Unit: \(unit.title)
        Lesson: \(lesson.title)
        
        Learner knowledge level: \(knowledgeGuidance)
        Depth level: \(depthGuidance)
        
        Content:
        \(lessonMarkdown)
        
        Review this lesson and decide if interactive demos are TRULY warranted. BIAS HARD to NO DEMO unless interaction is essential.
        
        Emit 0–N demos (up to 8 per lesson). Prefer zero demos unless learner must ACT to understand. Prefer playable interactive loops if you emit any.
        
        Remember: Depth level does NOT mean "more demos" — it only raises the quality bar. Exhaustive depth with zero demos is excellent if prose suffices.
        
        Output ONLY the JSON object.
        """
        
        // Use full model max - no artificial caps
        let maxTokens = ModelCapabilities.maxOutputTokens(provider: provider, model: model)
        
        let response = try await client.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        return try decodeDemoResponse(response, lessonId: lesson.id)
    }
    
    private func decodeDemoResponse(_ response: String, lessonId: String) throws -> DemoWriterOutput? {
        guard let extracted = JSONExtractor.extractJSON(from: response) else {
            throw GenerationError.invalidResponse("Demo Writer returned invalid JSON: Could not extract valid JSON from response. Response snippet: \(response.prefix(200))...")
        }
        
        let structureValidation = JSONExtractor.validateJSONStructure(extracted, expectedTopLevelType: .object)
        guard structureValidation.isValid else {
            throw GenerationError.invalidResponse("Demo Writer returned invalid JSON structure: \(structureValidation.errorMessage ?? "unknown"). Extracted: \(extracted.prefix(200))...")
        }
        
        guard let data = extracted.data(using: .utf8) else {
            throw GenerationError.invalidResponse("Demo Writer JSON encoding failed: Could not encode extracted JSON as UTF-8")
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
        
        guard demo.learningGoal != nil && !demo.learningGoal!.isEmpty else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' missing required learningGoal field")
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
    let learningGoal: String?
    let assets: [String: String]?
}
