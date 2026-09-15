import Foundation

class LessonWriterService: LessonWriterRole {
    private let client: LLMClient
    private let temperature: Double?
    private let topic: String
    private let locale: String
    private let knowledgeLevel: KnowledgeLevel
    private let depthLevel: DepthLevel
    private let provider: LLMProvider
    private let model: String
    private let timingLogger: GenerationTimingLogger?
    
    init(client: LLMClient, temperature: Double? = nil, topic: String, locale: String, knowledgeLevel: KnowledgeLevel, depthLevel: DepthLevel, provider: LLMProvider, model: String, timingLogger: GenerationTimingLogger? = nil) {
        self.client = client
        self.temperature = temperature
        self.topic = topic
        self.locale = locale
        self.knowledgeLevel = knowledgeLevel
        self.depthLevel = depthLevel
        self.provider = provider
        self.model = model
        self.timingLogger = timingLogger
    }
    
    func writeLesson(lesson: CurriculumLesson, unit: CurriculumUnit, curriculum: Curriculum) async throws -> (markdown: String, meta: LessonMeta, llmMetadata: LLMResponse?) {
        let sectionRange: String
        switch depthLevel {
        case .brief:
            sectionRange = "2–3"
        case .standard:
            sectionRange = "2–4"
        case .deep:
            sectionRange = "3–5"
        case .thorough:
            sectionRange = "4–6"
        case .exhaustive:
            sectionRange = "5–8"
        }
        
        let depthGuidance: String
        switch depthLevel {
        case .brief:
            depthGuidance = "Tight; essentials only."
        case .standard:
            depthGuidance = "Balanced; concrete examples when useful."
        case .deep:
            depthGuidance = "Fuller explanations; worked examples; teaching edge cases."
        case .thorough:
            depthGuidance = "Comprehensive within lesson scope; comparisons, pitfalls."
        case .exhaustive:
            depthGuidance = "Deep dive; multiple angles/nuance/failure modes; density over fluff (never pad)."
        }
        
        let systemPrompt = """
        You are a lesson writer for the Depthcraft learning platform. Write clear, focused educational content in markdown.
        
        PROSE-FIRST PEDAGOGY (CRITICAL):
        - Every lesson MUST contain substantive explanatory prose — concepts, why it matters, worked explanation
        - NEVER write a stub that only launches a demo or defers to an interactive without teaching in prose
        - Structure lessons with real pedagogical sections: hook/motivation, core explanation, examples/edge cases, pitfalls/gotchas, summary
        - Demos are optional add-ons decided separately by DemoWriter — do NOT mention, assume, or depend on demos in your prose
        - Your prose must stand alone as a complete learning resource even if no demo is ever added
        
        Requirements:
        - Use ## for main section headings (NOT #)
        - Target ~\(lesson.estimatedMinutes ?? 12) minute reading time
        - Language matched to knowledge level
        - Focus on understanding, not just facts
        - Include \(sectionRange) main ## sections with substantive content in each
        - Depth writing guidance: \(depthGuidance)
        
        Tables (GFM):
        - If emitting a table: header row, separator |---|---|, then data rows with NO blank lines between any table rows
        - No line breaks mid-cell or split pipes across lines
        - Prefer a short bullet list when a table isn't worth it
        
        Output ONLY markdown, no JSON or metadata.
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
        
        let curriculumOutline = curriculum.units.map { u in
            let lessons = u.lessonIds.compactMap { curriculum.lessons[$0] }
            let lessonList = lessons.prefix(3).map { "\($0.id) \($0.title)" }.joined(separator: "; ")
            let more = lessons.count > 3 ? "; [\(lessons.count - 3) more]" : ""
            return "\(u.id) \(u.title):\n  \(lessonList)\(more)"
        }.joined(separator: "\n\n")
        
        let siblingLessons = unit.lessonIds.compactMap { curriculum.lessons[$0] }
        let siblingList = siblingLessons.map { "  \($0.id) \($0.title)" }.joined(separator: "\n")
        
        let userPrompt = """
        Course topic: \(topic)
        Locale: \(locale)
        
        Knowledge level: \(knowledgeGuidance)
        
        Depth level: \(depthGuidance)
        
        Curriculum outline:
        \(curriculumOutline)
        
        This lesson:
        Unit: \(unit.id) \(unit.title)
        Lesson: \(lesson.id) \(lesson.title) (lesson \(lesson.order) of \(unit.lessonIds.count) in unit)
        
        Siblings in this unit:
        \(siblingList)
        
        Honor curriculum scope; don't swallow sibling lessons.
        
        Output ONLY the markdown content.
        """
        
        // Use full model max - no artificial caps
        let maxTokens = ModelCapabilities.maxOutputTokens(provider: provider, model: model)
        
        let markdown: String
        let lessonLLMMetadata: LLMResponse
        do {
            lessonLLMMetadata = try await client.completeWithMetadata(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                temperature: temperature,
                maxTokens: maxTokens
            )
            markdown = lessonLLMMetadata.text
        } catch let error as LLMClientError {
            throw GenerationError.invalidResponse("Lessons: \(error.localizedDescription)")
        }
        
        var meta = extractMeta(from: markdown, lessonId: lesson.id)
        
        let complexityAnalyzer = ComplexityAnalyzerService(
            client: client,
            temperature: temperature,
            topic: topic,
            knowledgeLevel: knowledgeLevel,
            depthLevel: depthLevel,
            provider: provider,
            model: model
        )
        
        let complexityMaxTokens = ModelCapabilities.maxOutputTokens(provider: provider, model: model)
        
        let explainAnchors: [LessonMeta.Anchor]
        if let logger = timingLogger {
            let timingId = await logger.startStage(
                .complexity,
                lessonId: lesson.id,
                provider: provider.rawValue,
                model: model,
                maxTokens: complexityMaxTokens
            )
            
            do {
                let complexityResult = try await complexityAnalyzer.analyzeComplexity(
                    markdown: markdown,
                    lessonTitle: lesson.title,
                    lessonId: lesson.id
                )
                explainAnchors = complexityResult.anchors
                
                // Complete timing with returned metadata
                let metadata = complexityResult.llmMetadata
                await logger.completeStage(
                    timingId,
                    tokensUsed: metadata.tokensUsed,
                    finishReason: metadata.finishReason,
                    requestCharCount: metadata.requestCharCount,
                    responseCharCount: metadata.responseCharCount
                )
            } catch {
                await logger.failStage(timingId, error: error.localizedDescription)
                throw error
            }
        } else {
            let complexityResult = try await complexityAnalyzer.analyzeComplexity(
                markdown: markdown,
                lessonTitle: lesson.title,
                lessonId: lesson.id
            )
            explainAnchors = complexityResult.anchors
        }
        
        meta = LessonMeta(
            schemaVersion: meta.schemaVersion,
            lessonId: meta.lessonId,
            anchors: meta.anchors + explainAnchors
        )
        
        return (markdown, meta, lessonLLMMetadata)
    }
    
    private func extractMeta(from markdown: String, lessonId: String) -> LessonMeta {
        var anchors: [LessonMeta.Anchor] = []
        
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let anchorId = "a-" + heading
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                    .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
                
                let kind: String
                if heading.lowercased().contains("warning") || heading.lowercased().contains("caution") {
                    kind = "warning"
                } else if heading.lowercased().contains("concept") || heading.lowercased().contains("key") {
                    kind = "concept"
                } else {
                    kind = "section"
                }
                
                anchors.append(LessonMeta.Anchor(id: anchorId, heading: heading, kind: kind, term: nil, gloss: nil))
            }
        }
        
        return LessonMeta(schemaVersion: "0.1.0", lessonId: lessonId, anchors: anchors)
    }
}
