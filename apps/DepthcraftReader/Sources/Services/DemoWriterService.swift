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
        
        PROSE-FIRST PEDAGOGY (CRITICAL):
        - The lesson prose you receive is the PRIMARY teaching resource and is COMPLETE on its own
        - Demos are optional ENHANCEMENTS that come AFTER prose explanation, never replacements
        - A demo must SUPPORT and CLARIFY a high-complexity idea that prose has already explained
        - NEVER assume a demo is needed just because the lesson covers a complex topic — prose comes first
        - If you emit a demo, it appears AFTER the prose section that introduces the concept (via insertAfterHeading)
        
        CRITICAL QUALITY BAR:
        - BIAS HARD TO NO DEMO. Empty demos array is STRONGLY PREFERRED over weak/decorative demos
        - Demos are expensive (time/tokens). The bar is VERY HIGH
        - ONLY emit a demo if the learner must ACT in a way prose cannot substitute
        - Must enable: manipulate a spatial idea, run a procedure, test a hypothesis with feedback
        - NEVER emit filler demos just because a lesson seems "complex" — zero demos > weak demo
        - The prose already teaches the concept; demo only adds if interaction clarifies what words struggle with
        
        EXPLICIT REJECT LIST (NEVER emit these):
        - Decorative orbiting/spinning scenes with no learner agency
        - Title splash screens or visual embellishment
        - "Visualize the concept" demos where learner input doesn't change meaningful state
        - Demos where interaction is cosmetic (click to change color but no learning feedback)
        - Kit-fake / missing-API workarounds (if three-v0 can't support it → NO DEMO)
        
        REQUIRED FIELDS PER DEMO:
        - learningGoal: one-line string stating what the learner gains by interacting (not what the demo shows)
        - fallback.md: MUST teach the SAME learningGoal if WebView fails. Not a summary; a standalone lesson snippet
        
        KIT SELECTION GUIDANCE:
        - Two kits available: "three-v0" (3D/spatial) and "ui-v0" (non-3D interactive)
        - Choose "three-v0" ONLY for spatial/3D manipulation (transforms, coordinate systems, WebGL)
        - Choose "ui-v0" for non-3D interactive patterns (tap-reveal, drag-match, param exploration)
        - If neither kit fits the interaction → return {"demos":[]} — do not fake it
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
        
        UI-V0 KIT CARD (AUTHORITATIVE):
        - Touch-first interactive primitives for non-3D learn-by-doing
        - Available import: 'kit:ui-v0/kit.js' (exports window.DepthcraftUIKit namespace)
        - Platform: iPadOS/iOS touch-first (44pt minimum touch targets, no hover-only interactions)
        - Offline: No CDN, no fetch, no external fonts — fully self-contained
        - What Reader injects: 8 primitives + thin DOM escape
        - CRITICAL: DO NOT use HTML5 Drag and Drop API (draggable, ondragstart, ondrop). iOS touch interaction is tap-based, not drag-based
        - Interaction pattern: tap to select → tap to place (not drag). All ui-v0 primitives follow this model
        
        UI-V0 PRIMITIVES (all available):
        1. TapReveal: Tap to progressively reveal hidden content
           - Use: Multi-step explanations, layered concepts
           - Example: createTapReveal({ containerId: 'demo', items: [{title: '...', content: '...'}] })
        
        2. StepSequence: Navigate through sequential steps with prev/next controls
           - Use: Procedures, algorithms, walkthroughs
           - Example: createStepSequence({ containerId: 'demo', steps: [{title: '...', content: '...'}] })
        
        3. OrderList: Reorder items by tapping (touch-compatible)
           - Use: Sequence ordering, ranking, priority
           - Example: createOrderList({ containerId: 'demo', items: [...], correctOrder: [...] })
        
        4. DragMatch: Tap items to match with targets (touch-first, not HTML5 drag-drop)
           - Use: Vocabulary matching, concept pairing, classification
           - Example: createDragMatch({ containerId: 'demo', items: [...], targets: [...], matches: {...} })
        
        5. HotspotDiagram: Tap hotspots on image/SVG to reveal info
           - Use: Annotated diagrams, anatomy, architecture
           - Example: createHotspotDiagram({ containerId: 'demo', svgContent: '...', hotspots: [{x: 50, y: 30, info: '...'}] })
        
        6. ParamExplorer: Sliders/toggles with live visual feedback
           - Use: Parameter exploration, formula visualization, config tuning
           - Example: createParamExplorer({ containerId: 'demo', params: [...], renderFn: (output, vals) => {...} })
        
        7. ClassifyBins: Sort items into categorical bins (tap chip → tap bin pattern)
           - Use: Classification, categorization, sorting
           - Touch pattern: tap chip to select (shows selection), tap bin to place, tap chip-in-bin to remove
           - CRITICAL: Each item MUST have a 'text' property (the human-readable label shown on the chip). Never omit item.text
           - Example: createClassifyBins({ containerId: 'demo', items: [...], bins: [...], correctBins: {...} })
        
        8. ChallengeLoop: Try → feedback → retry pattern (local validation only)
           - Use: Practice problems, code exercises, format practice
           - Example: createChallengeLoop({ containerId: 'demo', question: '...', checkFn: (ans) => ({correct: bool, message: '...'}), hintFn: (attempts) => '...' })
        
        UI-V0 THIN DOM ESCAPE:
        - When NO primitive fits, use injectCustom() for minimal custom HTML/JS
        - Still offline, touch-first, no network, same injection rules
        - Example: DepthcraftUIKit.injectCustom('demo', '<div>...</div>', (container) => { /* setup */ })
        - Prefer primitives over DOM escape; escape is for edge cases only
        
        OUTPUT FORMAT (JSON only, no markdown fences):
        {
          "demos": [
            {
              "demoId": "kebab-case-id",
              "title": "Brief title",
              "learningGoal": "What learner gains by interacting (one line)",
              "kit": "three-v0",  // or "ui-v0"
              "entry": "index.html",
              "fallback": "fallback.md",
              "entryHTML": "<!DOCTYPE html>\\n<html>\\n<head><title>Demo</title></head>\\n<body>\\n<div id=\\"demo\\"></div>\\n<script type=\\"module\\">\\nimport 'kit:ui-v0/kit.js';\\nconst demo = DepthcraftUIKit.createTapReveal({containerId: 'demo', items: [...]});\\n</script>\\n</body>\\n</html>",
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
        - kit: MUST be "three-v0" or "ui-v0"
        - entry: MUST be "index.html"
        - fallback: MUST be "fallback.md"
        - entryHTML: complete HTML file (ES modules, kit-only imports)
        - fallbackMarkdown: complete fallback content teaching SAME learningGoal (always required)
        - insertAfterHeading: heading text to insert demo after (must exist in lesson.md)
        - assets: optional dict of filename->content for additional JS/JSON files
        
        ENTRY HTML REQUIREMENTS:
        - For three-v0: import * as THREE from 'kit:three-v0/three.module.min.js'
        - For ui-v0: import 'kit:ui-v0/kit.js' then use window.DepthcraftUIKit
        - NO static canvas in HTML body for three-v0 demos - create in JS AFTER kit import
        - For ui-v0: include container div with unique id, then call primitives
        - NO decorative chrome before kit success
        - If kit import fails, body must remain blank so Reader fallback triggers automatically
        - NO CDN URLs, NO external fetch calls
        - Self-contained scene in HTML or split into assets
        - Touch-first: large hit targets (44pt min), no hover-only
        
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
        
        Lesson prose (complete teaching resource):
        \(lessonMarkdown)
        
        The prose above is a complete, standalone teaching resource. Review it and decide if interactive demos would ADD VALUE through hands-on manipulation.
        
        BIAS HARD to NO DEMO unless interaction is essential. The prose already teaches the concepts — only add a demo if:
        - The concept is high-complexity AND
        - Active manipulation clarifies what prose struggles to convey AND
        - A kit primitive truly enables learning through action
        
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
        
        guard demo.kit == "three-v0" || demo.kit == "ui-v0" else {
            throw GenerationError.validationFailed("Demo '\(demo.demoId)' uses unsupported kit '\(demo.kit)'. Only 'three-v0' and 'ui-v0' are allowed")
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
