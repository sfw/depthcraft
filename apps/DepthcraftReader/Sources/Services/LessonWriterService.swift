import Foundation

class LessonWriterService: LessonWriterRole {
    private let client: LLMClient
    private let temperature: Double
    private let depthLevel: DepthLevel
    
    init(client: LLMClient, temperature: Double = 0.7, depthLevel: DepthLevel = .standard) {
        self.client = client
        self.temperature = temperature
        self.depthLevel = depthLevel
    }
    
    func writeLesson(lesson: CurriculumLesson, unit: CurriculumUnit, curriculum: Curriculum) async throws -> (markdown: String, meta: LessonMeta) {
        let systemPrompt = """
        You are a lesson writer for the Depthcraft learning platform. Write clear, focused educational content in markdown.
        
        Requirements:
        - Use ## for main section headings (NOT #)
        - Keep it concise (aim for \(lesson.estimatedMinutes ?? 12) minute read)
        - Use clear, accessible language
        - Focus on understanding, not just facts
        - Include 2-4 main sections
        
        Output ONLY markdown, no JSON or metadata.
        """
        
        let userPrompt = """
        Write a lesson on: \(lesson.title)
        
        Context:
        - Unit: \(unit.title)
        - Lesson \(lesson.order) of \(unit.lessonIds.count) in this unit
        
        Output ONLY the markdown content.
        """
        
        let markdown = try await client.complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            maxTokens: 4096
        )
        
        var meta = extractMeta(from: markdown, lessonId: lesson.id)
        
        let complexityAnalyzer = ComplexityAnalyzerService(
            client: client,
            temperature: 0.5,
            depthLevel: depthLevel
        )
        
        let explainAnchors = try await complexityAnalyzer.analyzeComplexity(
            markdown: markdown,
            lessonTitle: lesson.title,
            lessonId: lesson.id
        )
        
        meta = LessonMeta(
            schemaVersion: meta.schemaVersion,
            lessonId: meta.lessonId,
            anchors: meta.anchors + explainAnchors
        )
        
        return (markdown, meta)
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
                
                anchors.append(LessonMeta.Anchor(id: anchorId, heading: heading, kind: kind))
            }
        }
        
        return LessonMeta(schemaVersion: "0.1.0", lessonId: lessonId, anchors: anchors)
    }
}
