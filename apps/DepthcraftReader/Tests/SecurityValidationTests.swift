import XCTest
@testable import DepthcraftReader

/// Tests for P1 security hardening: schema validation and path traversal protection
final class SecurityValidationTests: XCTestCase {
    
    // MARK: - Path Traversal Tests
    
    func testRejectPathTraversalDotDot() throws {
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("../etc/passwd", name: "test")) { error in
            XCTAssertTrue(error.localizedDescription.contains(".."))
        }
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("foo/../bar", name: "test"))
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("../../secrets", name: "test"))
    }
    
    func testRejectAbsolutePaths() throws {
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("/etc/passwd", name: "test")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Absolute"))
        }
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("/var/log/system", name: "test"))
    }
    
    func testRejectSchemePaths() throws {
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("http://evil.com", name: "test")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Scheme-based"))
        }
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("file:///etc/passwd", name: "test"))
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("javascript://alert(1)", name: "test"))
    }
    
    func testRejectEmptyPath() throws {
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("", name: "test")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Empty"))
        }
    }
    
    func testRejectWhitespacePadding() throws {
        XCTAssertThrowsError(try SchemaValidator.validateSafePath(" foo", name: "test"))
        XCTAssertThrowsError(try SchemaValidator.validateSafePath("foo ", name: "test"))
        XCTAssertThrowsError(try SchemaValidator.validateSafePath(" foo ", name: "test"))
    }
    
    func testAcceptSafePaths() throws {
        XCTAssertNoThrow(try SchemaValidator.validateSafePath("units/u01/lesson.md", name: "test"))
        XCTAssertNoThrow(try SchemaValidator.validateSafePath("three-v0", name: "test"))
        XCTAssertNoThrow(try SchemaValidator.validateSafePath("fallback.md", name: "test"))
    }
    
    // MARK: - ID Pattern Tests
    
    func testRejectInvalidIDs() throws {
        // Uppercase not allowed
        XCTAssertThrowsError(try SchemaValidator.validateId("Unit01", name: "test"))
        // Must start with alphanumeric
        XCTAssertThrowsError(try SchemaValidator.validateId("-invalid", name: "test"))
        // No spaces
        XCTAssertThrowsError(try SchemaValidator.validateId("foo bar", name: "test"))
        // No special chars
        XCTAssertThrowsError(try SchemaValidator.validateId("foo_bar", name: "test"))
        XCTAssertThrowsError(try SchemaValidator.validateId("foo.bar", name: "test"))
        XCTAssertThrowsError(try SchemaValidator.validateId("foo/bar", name: "test"))
    }
    
    func testAcceptValidIDs() throws {
        XCTAssertNoThrow(try SchemaValidator.validateId("u01", name: "test"))
        XCTAssertNoThrow(try SchemaValidator.validateId("l01-what-is-a-harness", name: "test"))
        XCTAssertNoThrow(try SchemaValidator.validateId("three-v0", name: "test"))
        XCTAssertNoThrow(try SchemaValidator.validateId("demo-rotate-cube-001", name: "test"))
    }
    
    // MARK: - Manifest Validation Tests
    
    func testRejectInvalidSchemaVersion() throws {
        var manifest = createValidManifest()
        manifest = PackageManifest(
            schemaVersion: "99.0.0",
            packageId: manifest.packageId,
            contentVersion: manifest.contentVersion,
            title: manifest.title,
            topic: manifest.topic,
            createdAt: manifest.createdAt,
            locale: manifest.locale,
            generator: manifest.generator,
            extendedFrom: manifest.extendedFrom
        )
        XCTAssertThrowsError(try SchemaValidator.validateManifest(manifest)) { error in
            XCTAssertTrue(error.localizedDescription.contains("schema version"))
        }
    }
    
    func testRejectEmptyManifestFields() throws {
        var manifest = createValidManifest()
        
        // Empty packageId
        manifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "",
            contentVersion: 1,
            title: "Title",
            topic: "Topic",
            createdAt: "2026-09-12T00:00:00Z",
            locale: "en",
            generator: nil,
            extendedFrom: nil
        )
        XCTAssertThrowsError(try SchemaValidator.validateManifest(manifest))
    }
    
    func testRejectInvalidContentVersion() throws {
        var manifest = createValidManifest()
        manifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-pkg",
            contentVersion: 0,
            title: "Title",
            topic: "Topic",
            createdAt: "2026-09-12T00:00:00Z",
            locale: "en",
            generator: nil,
            extendedFrom: nil
        )
        XCTAssertThrowsError(try SchemaValidator.validateManifest(manifest)) { error in
            XCTAssertTrue(error.localizedDescription.contains("contentVersion"))
        }
    }
    
    func testAcceptValidManifest() throws {
        let manifest = createValidManifest()
        XCTAssertNoThrow(try SchemaValidator.validateManifest(manifest))
    }
    
    // MARK: - Curriculum Validation Tests
    
    func testRejectEmptyUnits() throws {
        var curriculum = createValidCurriculum()
        curriculum.units = []
        XCTAssertThrowsError(try SchemaValidator.validateCurriculum(curriculum)) { error in
            XCTAssertTrue(error.localizedDescription.contains("units"))
        }
    }
    
    func testRejectEmptyLessons() throws {
        var curriculum = createValidCurriculum()
        curriculum.lessons = [:]
        XCTAssertThrowsError(try SchemaValidator.validateCurriculum(curriculum)) { error in
            XCTAssertTrue(error.localizedDescription.contains("lessons"))
        }
    }
    
    func testRejectDuplicateUnitIDs() throws {
        var curriculum = createValidCurriculum()
        curriculum.units.append(curriculum.units[0]) // Duplicate first unit
        XCTAssertThrowsError(try SchemaValidator.validateCurriculum(curriculum)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Duplicate"))
        }
    }
    
    func testRejectInvalidUnitID() throws {
        var curriculum = createValidCurriculum()
        curriculum.units[0] = CurriculumUnit(
            id: "../etc/passwd",
            title: "Evil Unit",
            order: 1,
            lessonIds: ["l01"]
        )
        XCTAssertThrowsError(try SchemaValidator.validateCurriculum(curriculum))
    }
    
    func testRejectNonexistentLessonReference() throws {
        var curriculum = createValidCurriculum()
        curriculum.units[0].lessonIds.append("nonexistent-lesson")
        XCTAssertThrowsError(try SchemaValidator.validateCurriculum(curriculum)) { error in
            XCTAssertTrue(error.localizedDescription.contains("non-existent"))
        }
    }
    
    func testAcceptValidCurriculum() throws {
        let curriculum = createValidCurriculum()
        XCTAssertNoThrow(try SchemaValidator.validateCurriculum(curriculum))
    }
    
    // MARK: - Quiz Validation Tests
    
    func testRejectEmptyQuizItems() throws {
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01",
            items: []
        )
        XCTAssertThrowsError(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l01")) { error in
            XCTAssertTrue(error.localizedDescription.contains("no items"))
        }
    }
    
    func testRejectMismatchedLessonID() throws {
        let quiz = createValidQuiz(lessonId: "l01")
        XCTAssertThrowsError(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l02")) { error in
            XCTAssertTrue(error.localizedDescription.contains("does not match"))
        }
    }
    
    func testRejectDuplicateQuizItemIDs() throws {
        let item1 = MCItem(
            id: "q1",
            type: "mc",
            prompt: "Question?",
            choices: [
                MCChoice(id: "a", text: "Answer A"),
                MCChoice(id: "b", text: "Answer B")
            ],
            correctId: "a",
            explain: nil
        )
        let item2 = MCItem(
            id: "q1", // Duplicate
            type: "mc",
            prompt: "Another?",
            choices: [
                MCChoice(id: "a", text: "Answer A"),
                MCChoice(id: "b", text: "Answer B")
            ],
            correctId: "a",
            explain: nil
        )
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01",
            items: [.mc(item1), .mc(item2)]
        )
        XCTAssertThrowsError(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l01")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Duplicate"))
        }
    }
    
    func testRejectMCItemWithoutEnoughChoices() throws {
        let item = MCItem(
            id: "q1",
            type: "mc",
            prompt: "Question?",
            choices: [MCChoice(id: "a", text: "Only one")],
            correctId: "a",
            explain: nil
        )
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01",
            items: [.mc(item)]
        )
        XCTAssertThrowsError(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l01")) { error in
            XCTAssertTrue(error.localizedDescription.contains("at least 2 choices"))
        }
    }
    
    func testRejectMCItemWithInvalidCorrectId() throws {
        let item = MCItem(
            id: "q1",
            type: "mc",
            prompt: "Question?",
            choices: [
                MCChoice(id: "a", text: "Answer A"),
                MCChoice(id: "b", text: "Answer B")
            ],
            correctId: "c", // Not in choices
            explain: nil
        )
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01",
            items: [.mc(item)]
        )
        XCTAssertThrowsError(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l01")) { error in
            XCTAssertTrue(error.localizedDescription.contains("not found in choices"))
        }
    }
    
    func testRejectClozeItemWithoutAnswers() throws {
        let item = ClozeItem(
            id: "q1",
            type: "cloze",
            prompt: "Fill in blank",
            answers: [],
            explain: nil
        )
        let quiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01",
            items: [.cloze(item)]
        )
        XCTAssertThrowsError(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l01")) { error in
            XCTAssertTrue(error.localizedDescription.contains("no answers"))
        }
    }
    
    func testAcceptValidQuiz() throws {
        let quiz = createValidQuiz(lessonId: "l01")
        XCTAssertNoThrow(try SchemaValidator.validateQuiz(quiz, expectedLessonId: "l01"))
    }
    
    // MARK: - Demo Manifest Validation Tests
    
    func testRejectDemoWithPathTraversal() throws {
        let manifest = DemoManifest(
            schemaVersion: "0.1.0",
            demoId: "demo1",
            title: "Evil Demo",
            kit: "../../../secrets",
            entry: "index.html",
            fallback: "fallback.md"
        )
        XCTAssertThrowsError(try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: "demo1"))
    }
    
    func testRejectDemoWithAbsoluteEntry() throws {
        let manifest = DemoManifest(
            schemaVersion: "0.1.0",
            demoId: "demo1",
            title: "Evil Demo",
            kit: "three-v0",
            entry: "/etc/passwd",
            fallback: "fallback.md"
        )
        XCTAssertThrowsError(try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: "demo1")) { error in
            XCTAssertTrue(error.localizedDescription.contains("relative"))
        }
    }
    
    func testRejectDemoWithMismatchedID() throws {
        let manifest = DemoManifest(
            schemaVersion: "0.1.0",
            demoId: "wrong-id",
            title: "Demo",
            kit: "three-v0",
            entry: "index.html",
            fallback: "fallback.md"
        )
        XCTAssertThrowsError(try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: "demo1")) { error in
            XCTAssertTrue(error.localizedDescription.contains("does not match"))
        }
    }
    
    func testAcceptValidDemoManifest() throws {
        let manifest = DemoManifest(
            schemaVersion: "0.1.0",
            demoId: "demo1",
            title: "Rotate Cube",
            kit: "three-v0",
            entry: "index.html",
            fallback: "fallback.md"
        )
        XCTAssertNoThrow(try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: "demo1"))
    }
    
    // MARK: - Helper Functions
    
    private func createValidManifest() -> PackageManifest {
        PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-pkg",
            contentVersion: 1,
            title: "Test Package",
            topic: "Testing",
            createdAt: "2026-09-12T00:00:00Z",
            locale: "en",
            generator: nil,
            extendedFrom: nil
        )
    }
    
    private func createValidCurriculum() -> Curriculum {
        Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: "2026-09-12T00:00:00Z",
            units: [
                CurriculumUnit(
                    id: "u01",
                    title: "Unit 1",
                    order: 1,
                    lessonIds: ["l01", "l02"]
                )
            ],
            lessons: [
                "l01": CurriculumLesson(
                    id: "l01",
                    unitId: "u01",
                    title: "Lesson 1",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                ),
                "l02": CurriculumLesson(
                    id: "l02",
                    unitId: "u01",
                    title: "Lesson 2",
                    order: 2,
                    status: "built",
                    estimatedMinutes: 15
                )
            ]
        )
    }
    
    private func createValidQuiz(lessonId: String) -> QuizDocument {
        QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: lessonId,
            items: [
                .mc(MCItem(
                    id: "q1",
                    type: "mc",
                    prompt: "What is 2+2?",
                    choices: [
                        MCChoice(id: "a", text: "3"),
                        MCChoice(id: "b", text: "4"),
                        MCChoice(id: "c", text: "5")
                    ],
                    correctId: "b",
                    explain: "Basic math"
                )),
                .cloze(ClozeItem(
                    id: "q2",
                    type: "cloze",
                    prompt: "Fill in: The sky is ___",
                    answers: ["blue"],
                    explain: "Common knowledge"
                ))
            ]
        )
    }
}
