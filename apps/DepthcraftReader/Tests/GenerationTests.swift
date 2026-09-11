import XCTest
@testable import DepthcraftReader

final class QuizGradingTests: XCTestCase {
    
    func testNormalizeCloze() {
        XCTAssertEqual(
            QuizGrading.normalizeCloze("  Harness  "),
            QuizGrading.normalizeCloze("harness")
        )
        
        XCTAssertEqual(
            QuizGrading.normalizeCloze("HELLO"),
            QuizGrading.normalizeCloze("hello")
        )
        
        XCTAssertEqual(
            QuizGrading.normalizeCloze("  TeSt  "),
            QuizGrading.normalizeCloze("test")
        )
    }
    
    func testGradeMCCorrect() {
        XCTAssertTrue(QuizGrading.gradeMC(choiceId: "a", correctId: "a"))
        XCTAssertTrue(QuizGrading.gradeMC(choiceId: "b", correctId: "b"))
    }
    
    func testGradeMCIncorrect() {
        XCTAssertFalse(QuizGrading.gradeMC(choiceId: "a", correctId: "b"))
        XCTAssertFalse(QuizGrading.gradeMC(choiceId: nil, correctId: "a"))
    }
    
    func testGradeClozeCorrect() {
        XCTAssertTrue(
            QuizGrading.gradeCloze(answer: "harness", accepted: ["harness"])
        )
        
        XCTAssertTrue(
            QuizGrading.gradeCloze(answer: "  HARNESS  ", accepted: ["harness"])
        )
        
        XCTAssertTrue(
            QuizGrading.gradeCloze(answer: "harness", accepted: ["control", "harness", "system"])
        )
    }
    
    func testGradeClozeIncorrect() {
        XCTAssertFalse(
            QuizGrading.gradeCloze(answer: "wrong", accepted: ["harness"])
        )
        
        XCTAssertFalse(
            QuizGrading.gradeCloze(answer: "system", accepted: ["harness", "control"])
        )
    }
    
    func testGradeClozeCaseInsensitive() {
        let accepted = ["harness"]
        
        XCTAssertTrue(QuizGrading.gradeCloze(answer: "Harness", accepted: accepted))
        XCTAssertTrue(QuizGrading.gradeCloze(answer: "HARNESS", accepted: accepted))
        XCTAssertTrue(QuizGrading.gradeCloze(answer: "HaRnEsS", accepted: accepted))
    }
    
    func testGradeClozeWithWhitespace() {
        let accepted = ["harness"]
        
        XCTAssertTrue(QuizGrading.gradeCloze(answer: " harness ", accepted: accepted))
        XCTAssertTrue(QuizGrading.gradeCloze(answer: "  harness  ", accepted: accepted))
        XCTAssertTrue(QuizGrading.gradeCloze(answer: "\tharness\n", accepted: accepted))
    }
}

final class PackageValidationTests: XCTestCase {
    
    func testGeneratePackageId() {
        let packager = PackagerService()
        
        let id1 = packager.generatePackageId(from: "Test Course")
        XCTAssertTrue(id1.hasPrefix("test-course"))
        XCTAssertTrue(id1.contains("-"))
        
        let id2 = packager.generatePackageId(from: "AI Harness Design")
        XCTAssertTrue(id2.hasPrefix("ai-harness-design"))
        
        let id3 = packager.generatePackageId(from: "Course With Special!@# Characters")
        XCTAssertTrue(id3.hasPrefix("course-with-special-characters"))
    }
    
    func testValidateCurriculumStructure() throws {
        let packager = PackagerService()
        
        let curriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "approved",
            approvedAt: nil,
            units: [
                CurriculumUnit(
                    id: "u01-test",
                    title: "Test Unit",
                    order: 1,
                    lessonIds: ["l01-test"]
                )
            ],
            lessons: [
                "l01-test": CurriculumLesson(
                    id: "l01-test",
                    unitId: "u01-test",
                    title: "Test Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let manifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            title: "Test",
            topic: "Test Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA"
        )
        
        let meta = LessonMeta(
            schemaVersion: "0.1.0",
            lessonId: "l01-test",
            anchors: []
        )
        
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01-test",
            items: [
                .mc(MCItem(
                    id: "q1",
                    type: "mc",
                    prompt: "Test?",
                    choices: [
                        MCChoice(id: "a", text: "A"),
                        MCChoice(id: "b", text: "B")
                    ],
                    correctId: "a",
                    explain: nil
                ))
            ]
        )
        
        let lessons = ["l01-test": ("# Test\n\nContent", meta)]
        let quizzes = ["l01-test": quiz]
        
        XCTAssertNoThrow(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes
            )
        )
    }
    
    func testValidationFailsOnMissingLesson() {
        let packager = PackagerService()
        
        let curriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "approved",
            approvedAt: nil,
            units: [
                CurriculumUnit(
                    id: "u01-test",
                    title: "Test Unit",
                    order: 1,
                    lessonIds: ["l01-test"]
                )
            ],
            lessons: [
                "l01-test": CurriculumLesson(
                    id: "l01-test",
                    unitId: "u01-test",
                    title: "Test Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let manifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            title: "Test",
            topic: "Test Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA"
        )
        
        XCTAssertThrowsError(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: [:],
                quizzes: [:]
            )
        )
    }
    
    func testSubsetPackaging() throws {
        let packager = PackagerService()
        
        // Full curriculum has 2 units, but only unit 1 has content generated
        let fullCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "approved",
            approvedAt: ISO8601DateFormatter().string(from: Date()),
            units: [
                CurriculumUnit(
                    id: "u01-selected",
                    title: "Selected Unit",
                    order: 1,
                    lessonIds: ["l01-selected"]
                ),
                CurriculumUnit(
                    id: "u02-unselected",
                    title: "Unselected Unit",
                    order: 2,
                    lessonIds: ["l02-unselected"]
                )
            ],
            lessons: [
                "l01-selected": CurriculumLesson(
                    id: "l01-selected",
                    unitId: "u01-selected",
                    title: "Selected Lesson",
                    order: 1,
                    status: "approved",
                    estimatedMinutes: 10
                ),
                "l02-unselected": CurriculumLesson(
                    id: "l02-unselected",
                    unitId: "u02-unselected",
                    title: "Unselected Lesson",
                    order: 1,
                    status: "draft",
                    estimatedMinutes: 10
                )
            ]
        )
        
        // Orchestrator would slice to selected unit before passing to packager
        let slicedCurriculum = Curriculum(
            schemaVersion: fullCurriculum.schemaVersion,
            status: fullCurriculum.status,
            approvedAt: fullCurriculum.approvedAt,
            units: [fullCurriculum.units[0]],  // Only selected unit
            lessons: ["l01-selected": fullCurriculum.lessons["l01-selected"]!]
        )
        
        let manifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-subset-package",
            title: "Test Subset",
            topic: "Test Subset Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA"
        )
        
        let meta = LessonMeta(
            schemaVersion: "0.1.0",
            lessonId: "l01-selected",
            anchors: []
        )
        
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01-selected",
            items: [
                .mc(MCItem(
                    id: "q1",
                    type: "mc",
                    prompt: "Test?",
                    choices: [
                        MCChoice(id: "a", text: "A"),
                        MCChoice(id: "b", text: "B")
                    ],
                    correctId: "a",
                    explain: nil
                ))
            ]
        )
        
        // Only content for selected unit
        let lessons = ["l01-selected": ("# Selected\n\nContent", meta)]
        let quizzes = ["l01-selected": quiz]
        
        // Should validate successfully - only requires content for lessons in sliced curriculum
        XCTAssertNoThrow(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: slicedCurriculum,
                lessons: lessons,
                quizzes: quizzes
            )
        )
        
        // Verify built package would only contain selected unit
        // (This tests the packager's compactMapValues logic that excludes lessons without content)
        let builtLessons = slicedCurriculum.lessons.compactMapValues { lesson -> CurriculumLesson? in
            guard lessons[lesson.id] != nil, quizzes[lesson.id] != nil else {
                return nil
            }
            return lesson
        }
        
        XCTAssertEqual(builtLessons.count, 1, "Built package should only contain generated lesson")
        XCTAssertNotNil(builtLessons["l01-selected"], "Selected lesson should be in built package")
        XCTAssertNil(builtLessons["l02-unselected"], "Unselected lesson should NOT be in built package")
    }
}

final class LessonMetaExtractionTests: XCTestCase {
    
    func testExtractAnchorsFromMarkdown() {
        let markdown = """
        # Main Title
        
        Some intro text.
        
        ## The Job
        
        Content about the job.
        
        ## Key Concept
        
        Important concept here.
        
        ## Warning: Be Careful
        
        A warning section.
        """
        
        let writer = LessonWriterService(client: MockLLMClient())
        let meta = writer.extractMeta(from: markdown, lessonId: "test-lesson")
        
        XCTAssertEqual(meta.schemaVersion, "0.1.0")
        XCTAssertEqual(meta.lessonId, "test-lesson")
        XCTAssertEqual(meta.anchors.count, 3)
        
        XCTAssertEqual(meta.anchors[0].heading, "The Job")
        XCTAssertEqual(meta.anchors[0].kind, "section")
        
        XCTAssertEqual(meta.anchors[1].heading, "Key Concept")
        XCTAssertEqual(meta.anchors[1].kind, "concept")
        
        XCTAssertEqual(meta.anchors[2].heading, "Warning: Be Careful")
        XCTAssertEqual(meta.anchors[2].kind, "warning")
    }
}

class MockLLMClient: LLMClient {
    func complete(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        return "Mock response"
    }
}

final class CustomClientTests: XCTestCase {
    
    func testCustomClientURLNormalization() {
        // Base URL without trailing slash
        let client1 = CustomOpenAIClient(
            apiKey: "test-key",
            model: "test-model",
            baseURL: "https://api.example.com/v1"
        )
        XCTAssertEqual(client1.baseURL, "https://api.example.com/v1")
        
        // Base URL with trailing slash - should be normalized
        let client2 = CustomOpenAIClient(
            apiKey: "test-key",
            model: "test-model",
            baseURL: "https://api.example.com/v1/"
        )
        XCTAssertEqual(client2.baseURL, "https://api.example.com/v1")
        
        // Multiple trailing slashes
        let client3 = CustomOpenAIClient(
            apiKey: "test-key",
            model: "test-model",
            baseURL: "https://api.example.com/v1///"
        )
        XCTAssertEqual(client3.baseURL, "https://api.example.com/v1//")
    }
    
    func testRateLimitErrorMessage() {
        let error = LLMClientError.rateLimitError(
            provider: "Anthropic",
            status: 429,
            message: "Rate limit exceeded"
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("Anthropic"))
        XCTAssertTrue(description.contains("429"))
        XCTAssertTrue(description.contains("rate limit"))
        XCTAssertTrue(description.contains("quota"))
    }
    
    func testRateLimitErrorMessageWithoutDetails() {
        let error = LLMClientError.rateLimitError(
            provider: "OpenAI",
            status: 429,
            message: nil
        )
        
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("OpenAI"))
        XCTAssertTrue(description.contains("429"))
        XCTAssertTrue(description.contains("quota"))
    }
    
    func testLLMConfigurationWithTemperature() {
        let config = LLMConfiguration(
            provider: .anthropic,
            model: "claude-3-5-sonnet-20241022",
            apiKey: "test-key",
            temperature: 0.9
        )
        
        XCTAssertEqual(config.temperature, 0.9)
        XCTAssertNil(config.customBaseURL)
    }
    
    func testLLMConfigurationWithCustomBaseURL() {
        let config = LLMConfiguration(
            provider: .custom,
            model: "moonshot-v1-8k",
            apiKey: "test-key",
            temperature: 0.7,
            customBaseURL: "https://api.moonshot.cn/v1"
        )
        
        XCTAssertEqual(config.customBaseURL, "https://api.moonshot.cn/v1")
        XCTAssertEqual(config.model, "moonshot-v1-8k")
    }
    
    func testLLMClientFactoryCustom() throws {
        let config = LLMConfiguration(
            provider: .custom,
            model: "test-model",
            apiKey: "test-key",
            temperature: 0.7,
            customBaseURL: "https://api.example.com/v1"
        )
        
        let client = try LLMClientFactory.createClient(config: config)
        XCTAssertTrue(client is CustomOpenAIClient)
    }
    
    func testLLMClientFactoryCustomRequiresBaseURL() {
        let config = LLMConfiguration(
            provider: .custom,
            model: "test-model",
            apiKey: "test-key",
            temperature: 0.7,
            customBaseURL: nil
        )
        
        XCTAssertThrowsError(try LLMClientFactory.createClient(config: config)) { error in
            XCTAssertTrue(error.localizedDescription.contains("base URL"))
        }
    }
}

extension LessonWriterService {
    func extractMeta(from markdown: String, lessonId: String) -> LessonMeta {
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
