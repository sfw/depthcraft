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
        
        let id2 = packager.generatePackageId(from: "AI Harness Design")
        XCTAssertTrue(id2.hasPrefix("ai-harness-design"))
        
        let id3 = packager.generatePackageId(from: "Course With Special!@# Characters")
        XCTAssertTrue(id3.hasPrefix("course-with-special-characters"))
    }
    
    func testValidateCurriculumStructure() async throws {
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
    func complete(systemPrompt: String, userPrompt: String) async throws -> String {
        return "Mock response"
    }
}

extension PackagerService {
    func generatePackageId(from topic: String) -> String {
        let cleaned = topic
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
        return String(cleaned.prefix(40))
    }
    
    func validatePackage(
        manifest: PackageManifest,
        curriculum: Curriculum,
        lessons: [String: (markdown: String, meta: LessonMeta)],
        quizzes: [String: QuizDocument]
    ) throws {
        guard curriculum.schemaVersion == "0.1.0" else {
            throw GenerationError.validationFailed("Invalid curriculum schema version")
        }
        
        guard !curriculum.units.isEmpty else {
            throw GenerationError.validationFailed("Curriculum has no units")
        }
        
        for unit in curriculum.units {
            guard !unit.lessonIds.isEmpty else {
                throw GenerationError.validationFailed("Unit \(unit.id) has no lessons")
            }
            
            for lessonId in unit.lessonIds {
                guard curriculum.lessons[lessonId] != nil else {
                    throw GenerationError.validationFailed("Lesson \(lessonId) referenced in unit \(unit.id) not found in curriculum")
                }
                
                guard lessons[lessonId] != nil else {
                    throw GenerationError.validationFailed("Lesson content for \(lessonId) not provided")
                }
                
                guard quizzes[lessonId] != nil else {
                    throw GenerationError.validationFailed("Quiz for \(lessonId) not provided")
                }
            }
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
