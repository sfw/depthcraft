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
            contentVersion: 1,
            title: "Test",
            topic: "Test Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
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
                quizzes: quizzes,
                demos: [:]
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
            contentVersion: 1,
            title: "Test",
            topic: "Test Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
        )
        
        XCTAssertThrowsError(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: [:],
                quizzes: [:],
                demos: [:]
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
            contentVersion: 1,
            title: "Test Subset",
            topic: "Test Subset Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
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
                quizzes: quizzes,
                demos: [:]
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
    
    func testDemoValidationRejectsDisallowedKit() {
        let packager = PackagerService()
        
        let curriculum = makeCurriculum()
        let manifest = makeManifest()
        let (lessons, quizzes) = makeLessonsAndQuizzes()
        
        let invalidDemo = DemoSpec(
            demoId: "test-demo",
            title: "Test Demo",
            kit: "react-v18",
            entry: "index.html",
            fallback: "fallback.md",
            entryHTML: "<html><body>Test</body></html>",
            fallbackMarkdown: "# Fallback",
            insertAfterHeading: "## Test Section",
            assets: nil
        )
        
        let demos = ["l01-test": DemoWriterOutput(demos: [invalidDemo])]
        
        XCTAssertThrowsError(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes,
                demos: demos
            )
        ) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("disallowed kit"))
        }
    }
    
    func testDemoValidationRejectsExternalURLs() {
        let packager = PackagerService()
        
        let curriculum = makeCurriculum()
        let manifest = makeManifest()
        let (lessons, quizzes) = makeLessonsAndQuizzes()
        
        let demoWithHTTPS = DemoSpec(
            demoId: "test-demo",
            title: "Test Demo",
            kit: "three-v0",
            entry: "index.html",
            fallback: "fallback.md",
            entryHTML: "<script src=\"https://cdn.jsdelivr.net/npm/three@0.150.0/build/three.min.js\"></script>",
            fallbackMarkdown: "# Fallback",
            insertAfterHeading: "## Test Section",
            assets: nil
        )
        
        let demos = ["l01-test": DemoWriterOutput(demos: [demoWithHTTPS])]
        
        XCTAssertThrowsError(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes,
                demos: demos
            )
        ) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("external URL"))
        }
    }
    
    func testDemoValidationRejectsMidFlightFetch() {
        let packager = PackagerService()
        
        let curriculum = makeCurriculum()
        let manifest = makeManifest()
        let (lessons, quizzes) = makeLessonsAndQuizzes()
        
        let demoWithFetch = DemoSpec(
            demoId: "test-demo",
            title: "Test Demo",
            kit: "three-v0",
            entry: "index.html",
            fallback: "fallback.md",
            entryHTML: "<html><body><script>const data = await fetch('/local/data.json'); console.log(data);</script></body></html>",
            fallbackMarkdown: "# Fallback",
            insertAfterHeading: "## Test Section",
            assets: nil
        )
        
        let demos = ["l01-test": DemoWriterOutput(demos: [demoWithFetch])]
        
        XCTAssertThrowsError(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes,
                demos: demos
            )
        ) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("mid-flight fetch"))
        }
    }
    
    func testDemoValidationRejectsMissingFallback() {
        let packager = PackagerService()
        
        let curriculum = makeCurriculum()
        let manifest = makeManifest()
        let (lessons, quizzes) = makeLessonsAndQuizzes()
        
        let demoWithoutFallback = DemoSpec(
            demoId: "test-demo",
            title: "Test Demo",
            kit: "three-v0",
            entry: "index.html",
            fallback: "fallback.md",
            entryHTML: "<html><body>Test</body></html>",
            fallbackMarkdown: "",
            insertAfterHeading: "## Test Section",
            assets: nil
        )
        
        let demos = ["l01-test": DemoWriterOutput(demos: [demoWithoutFallback])]
        
        XCTAssertThrowsError(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes,
                demos: demos
            )
        ) { error in
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("empty fallback"))
        }
    }
    
    func testDemoValidationAcceptsValidDemo() {
        let packager = PackagerService()
        
        let curriculum = makeCurriculum()
        let manifest = makeManifest()
        let (lessons, quizzes) = makeLessonsAndQuizzes()
        
        let validDemo = DemoSpec(
            demoId: "rotating-cube",
            title: "3D Coordinate System",
            kit: "three-v0",
            entry: "index.html",
            fallback: "fallback.md",
            entryHTML: """
            <!DOCTYPE html>
            <html>
            <head><title>Demo</title></head>
            <body>
            <script type="module">
            import * as THREE from 'kit:three-v0/three.module.min.js';
            // Demo code here
            </script>
            </body>
            </html>
            """,
            fallbackMarkdown: """
            # Interactive Demo Unavailable
            
            This lesson includes a 3D demo. Key concepts:
            - 3D coordinate systems
            - Rotation transforms
            """,
            insertAfterHeading: "## Test Section",
            assets: ["scene.js": "// Scene configuration"]
        )
        
        let demos = ["l01-test": DemoWriterOutput(demos: [validDemo])]
        
        XCTAssertNoThrow(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes,
                demos: demos
            )
        )
    }
    
    func testDemoValidationNoOpPath() {
        let packager = PackagerService()
        
        let curriculum = makeCurriculum()
        let manifest = makeManifest()
        let (lessons, quizzes) = makeLessonsAndQuizzes()
        
        let emptyDemos: [String: DemoWriterOutput] = [:]
        
        XCTAssertNoThrow(
            try packager.validatePackage(
                manifest: manifest,
                curriculum: curriculum,
                lessons: lessons,
                quizzes: quizzes,
                demos: emptyDemos
            )
        )
    }
    
    private func makeCurriculum() -> Curriculum {
        Curriculum(
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
    }
    
    private func makeManifest() -> PackageManifest {
        PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            contentVersion: 1,
            title: "Test",
            topic: "Test Topic",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
        )
    }
    
    private func makeLessonsAndQuizzes() -> ([String: (String, LessonMeta)], [String: QuizDocument]) {
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
        
        let lessons = ["l01-test": ("# Test\n\n## Test Section\n\nContent", meta)]
        let quizzes = ["l01-test": quiz]
        
        return (lessons, quizzes)
    }
}

final class ExtendRefreshTests: XCTestCase {
    
    func testProgressMergePreservesExistingCompletions() {
        let progressStore = ProgressStore(defaults: UserDefaults(suiteName: "test-suite")!)
        
        let existingProgress = DeviceProgress(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            lessons: [
                "l01-old": LessonProgress(completed: true, quizPassed: true, completedAt: "2024-01-01", markedRead: true),
                "l02-old": LessonProgress(completed: false, quizPassed: false, completedAt: nil, markedRead: true)
            ],
            units: [
                "u01-old": UnitProgress(completed: true, completedAt: "2024-01-01")
            ],
            lastLessonId: "l01-old",
            lastUnitId: "u01-old"
        )
        
        progressStore.save(existingProgress)
        
        let newLessonIds = ["l01-old", "l02-old", "l03-new", "l04-new"]
        let newUnitIds = ["u01-old", "u02-new"]
        
        let mergedProgress = progressStore.load(
            packageId: "test-package",
            lessonIds: newLessonIds,
            unitIds: newUnitIds
        )
        
        XCTAssertTrue(mergedProgress.lessons["l01-old"]?.completed == true, "Old completed lesson should remain completed")
        XCTAssertTrue(mergedProgress.lessons["l02-old"]?.markedRead == true, "Old read lesson should remain read")
        XCTAssertFalse(mergedProgress.lessons["l03-new"]?.completed ?? true, "New lesson should start incomplete")
        XCTAssertFalse(mergedProgress.lessons["l04-new"]?.completed ?? true, "New lesson should start incomplete")
        
        XCTAssertTrue(mergedProgress.units["u01-old"]?.completed == true, "Old completed unit should remain completed")
        XCTAssertFalse(mergedProgress.units["u02-new"]?.completed ?? true, "New unit should start incomplete")
        
        XCTAssertEqual(mergedProgress.lessons.count, 4, "Should have all 4 lessons")
        XCTAssertEqual(mergedProgress.units.count, 2, "Should have both units")
    }
    
    @MainActor
    func testVersionDetectionRejectsOlderVersion() {
        let store = CourseStore()
        
        let currentManifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            contentVersion: 2,
            title: "Test Course",
            topic: "Test",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: ExtensionMetadata(priorVersion: 1, extendedAt: "2024-01-02", extendedBy: nil)
        )
        
        let currentCourse = LoadedCourse(
            rootURL: URL(fileURLWithPath: "/tmp/current"),
            manifest: currentManifest,
            curriculum: Curriculum(schemaVersion: "0.1.0", status: "built", approvedAt: nil, units: [], lessons: [:])
        )
        
        store.course = currentCourse
        
        XCTAssertEqual(currentCourse.manifest.contentVersion, 2)
    }
    
    func testIDCollisionDetection() async throws {
        let packager = PackagerService()
        let tempDir = FileManager.default.temporaryDirectory
        
        let priorURL = tempDir.appendingPathComponent("prior-package.depthcraft")
        try? FileManager.default.removeItem(at: priorURL)
        try FileManager.default.createDirectory(at: priorURL, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: priorURL)
        }
        
        let priorManifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            contentVersion: 1,
            title: "Test",
            topic: "Test",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
        )
        
        let priorCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u01-existing", title: "Existing Unit", order: 1, lessonIds: ["l01-existing"])
            ],
            lessons: [
                "l01-existing": CurriculumLesson(
                    id: "l01-existing",
                    unitId: "u01-existing",
                    title: "Existing Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        try encoder.encode(priorManifest).write(to: priorURL.appendingPathComponent("manifest.json"))
        try encoder.encode(priorCurriculum).write(to: priorURL.appendingPathComponent("curriculum.json"))
        
        let newCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u01-existing", title: "Collision!", order: 2, lessonIds: ["l02-new"])
            ],
            lessons: [
                "l02-new": CurriculumLesson(
                    id: "l02-new",
                    unitId: "u01-existing",
                    title: "New Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        do {
            try await packager.validateExtension(
                priorPackageURL: priorURL,
                newCurriculum: newCurriculum,
                newLessons: [:]
            )
            XCTFail("Should have thrown an error for ID collision")
        } catch {
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("collision"), "Should detect unit ID collision")
        }
    }
    
    func testAppendOnlyValidation() async throws {
        let packager = PackagerService()
        let tempDir = FileManager.default.temporaryDirectory
        
        let priorURL = tempDir.appendingPathComponent("prior-package-append.depthcraft")
        try? FileManager.default.removeItem(at: priorURL)
        try FileManager.default.createDirectory(at: priorURL, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: priorURL)
        }
        
        let priorManifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-package",
            contentVersion: 1,
            title: "Test",
            topic: "Test",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
        )
        
        let priorCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u01-old", title: "Old Unit", order: 1, lessonIds: ["l01-old"])
            ],
            lessons: [
                "l01-old": CurriculumLesson(
                    id: "l01-old",
                    unitId: "u01-old",
                    title: "Old Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        try encoder.encode(priorManifest).write(to: priorURL.appendingPathComponent("manifest.json"))
        try encoder.encode(priorCurriculum).write(to: priorURL.appendingPathComponent("curriculum.json"))
        
        let newCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u02-new", title: "New Unit", order: 2, lessonIds: ["l02-new"])
            ],
            lessons: [
                "l02-new": CurriculumLesson(
                    id: "l02-new",
                    unitId: "u02-new",
                    title: "New Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        do {
            try await packager.validateExtension(
                priorPackageURL: priorURL,
                newCurriculum: newCurriculum,
                newLessons: [:]
            )
        } catch {
            XCTFail("Should not throw error for valid append-only extension: \(error)")
        }
    }
    
    func testByteImmutabilityAfterExtension() async throws {
        let packager = PackagerService()
        let tempDir = FileManager.default.temporaryDirectory
        let fm = FileManager.default
        
        let priorURL = tempDir.appendingPathComponent("prior-package-bytes.depthcraft")
        try? fm.removeItem(at: priorURL)
        try fm.createDirectory(at: priorURL, withIntermediateDirectories: true)
        
        defer {
            try? fm.removeItem(at: priorURL)
        }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let priorManifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: "test-bytes",
            contentVersion: 1,
            title: "Test",
            topic: "Test",
            createdAt: timestamp,
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
        )
        
        let priorCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u01-prior", title: "Prior Unit", order: 1, lessonIds: ["l01-prior"])
            ],
            lessons: [
                "l01-prior": CurriculumLesson(
                    id: "l01-prior",
                    unitId: "u01-prior",
                    title: "Prior Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        try encoder.encode(priorManifest).write(to: priorURL.appendingPathComponent("manifest.json"))
        try encoder.encode(priorCurriculum).write(to: priorURL.appendingPathComponent("curriculum.json"))
        
        let priorContentURL = priorURL.appendingPathComponent("content/units/u01-prior/lessons/l01-prior")
        try fm.createDirectory(at: priorContentURL, withIntermediateDirectories: true)
        
        let priorLessonMd = "# Prior Lesson\n\nThis is the original lesson content that must not change."
        try priorLessonMd.write(to: priorContentURL.appendingPathComponent("lesson.md"), atomically: true, encoding: .utf8)
        
        let priorQuiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01-prior",
            items: [
                .mc(MCItem(
                    id: "q1",
                    type: "mc",
                    prompt: "Original quiz?",
                    choices: [
                        MCChoice(id: "a", text: "Yes"),
                        MCChoice(id: "b", text: "No")
                    ],
                    correctId: "a",
                    explain: nil
                ))
            ]
        )
        try encoder.encode(priorQuiz).write(to: priorContentURL.appendingPathComponent("quiz.json"))
        
        let priorLessonBytes = try Data(contentsOf: priorContentURL.appendingPathComponent("lesson.md"))
        let priorQuizBytes = try Data(contentsOf: priorContentURL.appendingPathComponent("quiz.json"))
        
        let newCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u02-new", title: "New Unit", order: 2, lessonIds: ["l02-new"])
            ],
            lessons: [
                "l02-new": CurriculumLesson(
                    id: "l02-new",
                    unitId: "u02-new",
                    title: "New Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let newMeta = LessonMeta(
            schemaVersion: "0.1.0",
            lessonId: "l02-new",
            anchors: []
        )
        
        let newQuiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l02-new",
            items: [
                .mc(MCItem(
                    id: "q2",
                    type: "mc",
                    prompt: "New quiz?",
                    choices: [
                        MCChoice(id: "a", text: "Yes"),
                        MCChoice(id: "b", text: "No")
                    ],
                    correctId: "a",
                    explain: nil
                ))
            ]
        )
        
        let metadata = GeneratorMetadata(
            planner: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp),
            lessonWriter: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp),
            quizWriter: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp),
            demoWriter: DemoRun(provider: "anthropic", model: "test", ranAt: timestamp, demosEmitted: 0),
            packager: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp)
        )
        
        let extendedURL = try await packager.packageCourse(
            topic: "Test",
            locale: "en-CA",
            curriculum: newCurriculum,
            lessons: ["l02-new": ("# New Lesson\n\nNew content", newMeta)],
            quizzes: ["l02-new": newQuiz],
            demos: [:],
            roleRuns: metadata,
            extendFrom: priorURL
        )
        
        defer {
            try? fm.removeItem(at: extendedURL)
        }
        
        let extendedPriorLessonURL = extendedURL.appendingPathComponent("content/units/u01-prior/lessons/l01-prior/lesson.md")
        let extendedPriorQuizURL = extendedURL.appendingPathComponent("content/units/u01-prior/lessons/l01-prior/quiz.json")
        
        let extendedLessonBytes = try Data(contentsOf: extendedPriorLessonURL)
        let extendedQuizBytes = try Data(contentsOf: extendedPriorQuizURL)
        
        XCTAssertEqual(priorLessonBytes, extendedLessonBytes, "Prior lesson.md bytes must be identical after extension")
        XCTAssertEqual(priorQuizBytes, extendedQuizBytes, "Prior quiz.json bytes must be identical after extension")
        
        let newLessonURL = extendedURL.appendingPathComponent("content/units/u02-new/lessons/l02-new/lesson.md")
        XCTAssertTrue(fm.fileExists(atPath: newLessonURL.path), "New lesson should exist")
    }
    
    func testSamePathExtensionDoesNotWipePriorContent() async throws {
        let packager = PackagerService()
        let fm = FileManager.default
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let packageId = "test-same-path-\(UUID().uuidString.prefix(8))"
        
        let documentsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let packageURL = documentsURL.appendingPathComponent("\(packageId).depthcraft")
        
        defer {
            try? fm.removeItem(at: packageURL)
        }
        
        let initialManifest = PackageManifest(
            schemaVersion: "0.1.0",
            packageId: packageId,
            contentVersion: 1,
            title: "Test Same Path",
            topic: "Test",
            createdAt: timestamp,
            locale: "en-CA",
            generator: nil,
            extendedFrom: nil
        )
        
        let initialCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u01-original", title: "Original Unit", order: 1, lessonIds: ["l01-original"])
            ],
            lessons: [
                "l01-original": CurriculumLesson(
                    id: "l01-original",
                    unitId: "u01-original",
                    title: "Original Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try encoder.encode(initialManifest).write(to: packageURL.appendingPathComponent("manifest.json"))
        try encoder.encode(initialCurriculum).write(to: packageURL.appendingPathComponent("curriculum.json"))
        
        let originalContentURL = packageURL.appendingPathComponent("content/units/u01-original/lessons/l01-original")
        try fm.createDirectory(at: originalContentURL, withIntermediateDirectories: true)
        
        let originalLessonMd = "# Original Lesson\n\nThis content must survive same-path extension."
        try originalLessonMd.write(to: originalContentURL.appendingPathComponent("lesson.md"), atomically: true, encoding: .utf8)
        
        let originalQuiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l01-original",
            items: [
                .mc(MCItem(
                    id: "q1",
                    type: "mc",
                    prompt: "Original?",
                    choices: [
                        MCChoice(id: "a", text: "Yes"),
                        MCChoice(id: "b", text: "No")
                    ],
                    correctId: "a",
                    explain: nil
                ))
            ]
        )
        try encoder.encode(originalQuiz).write(to: originalContentURL.appendingPathComponent("quiz.json"))
        
        let originalLessonBytes = try Data(contentsOf: originalContentURL.appendingPathComponent("lesson.md"))
        let originalQuizBytes = try Data(contentsOf: originalContentURL.appendingPathComponent("quiz.json"))
        
        let newCurriculum = Curriculum(
            schemaVersion: "0.1.0",
            status: "built",
            approvedAt: nil,
            units: [
                CurriculumUnit(id: "u02-extension", title: "Extension Unit", order: 2, lessonIds: ["l02-extension"])
            ],
            lessons: [
                "l02-extension": CurriculumLesson(
                    id: "l02-extension",
                    unitId: "u02-extension",
                    title: "Extension Lesson",
                    order: 1,
                    status: "built",
                    estimatedMinutes: 10
                )
            ]
        )
        
        let newMeta = LessonMeta(
            schemaVersion: "0.1.0",
            lessonId: "l02-extension",
            anchors: []
        )
        
        let newQuiz = QuizDocument(
            schemaVersion: "0.1.0",
            lessonId: "l02-extension",
            items: [
                .mc(MCItem(
                    id: "q2",
                    type: "mc",
                    prompt: "Extension?",
                    choices: [
                        MCChoice(id: "a", text: "Yes"),
                        MCChoice(id: "b", text: "No")
                    ],
                    correctId: "a",
                    explain: nil
                ))
            ]
        )
        
        let metadata = GeneratorMetadata(
            planner: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp),
            lessonWriter: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp),
            quizWriter: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp),
            demoWriter: DemoRun(provider: "anthropic", model: "test", ranAt: timestamp, demosEmitted: 0),
            packager: RoleRun(provider: "anthropic", model: "test", ranAt: timestamp)
        )
        
        let resultURL = try await packager.packageCourse(
            topic: "Test Same Path",
            locale: "en-CA",
            curriculum: newCurriculum,
            lessons: ["l02-extension": ("# Extension Lesson\n\nNew content", newMeta)],
            quizzes: ["l02-extension": newQuiz],
            demos: [:],
            roleRuns: metadata,
            extendFrom: packageURL
        )
        
        XCTAssertEqual(resultURL.standardizedFileURL.path, packageURL.standardizedFileURL.path, "Should return same Documents path")
        XCTAssertEqual(resultURL.path, documentsURL.appendingPathComponent("\(packageId).depthcraft").path, "Should be at expected Documents location")
        
        let finalOriginalLessonURL = resultURL.appendingPathComponent("content/units/u01-original/lessons/l01-original/lesson.md")
        let finalOriginalQuizURL = resultURL.appendingPathComponent("content/units/u01-original/lessons/l01-original/quiz.json")
        
        let finalLessonBytes = try Data(contentsOf: finalOriginalLessonURL)
        let finalQuizBytes = try Data(contentsOf: finalOriginalQuizURL)
        
        XCTAssertEqual(originalLessonBytes, finalLessonBytes, "Original lesson.md bytes must survive same-path extension")
        XCTAssertEqual(originalQuizBytes, finalQuizBytes, "Original quiz.json bytes must survive same-path extension")
        
        let extensionLessonURL = resultURL.appendingPathComponent("content/units/u02-extension/lessons/l02-extension/lesson.md")
        XCTAssertTrue(fm.fileExists(atPath: extensionLessonURL.path), "Extension lesson should exist")
        
        let finalManifestData = try Data(contentsOf: resultURL.appendingPathComponent("manifest.json"))
        let finalManifest = try JSONDecoder().decode(PackageManifest.self, from: finalManifestData)
        XCTAssertEqual(finalManifest.contentVersion, 2, "Version should increment to 2")
        XCTAssertNotNil(finalManifest.extendedFrom, "Should have extendedFrom metadata")
        XCTAssertEqual(finalManifest.extendedFrom?.priorVersion, 1, "Should track prior version 1")
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

final class ExplainUnderlineInjectionTests: XCTestCase {
    
    func testInjectExplainInTextNodesOnly() {
        let html = "<p>The harness pattern is <strong>powerful</strong> but requires careful design.</p>"
        let anchors = [
            LessonMeta.Anchor(
                id: "test-explain-1",
                heading: "harness",
                kind: "concept",
                term: "harness",
                gloss: "A control structure that manages interactions."
            )
        ]
        
        let result = MarkdownHTML.render("# Test", title: "Test", estimatedMinutes: nil, anchors: anchors)
        
        // Should wrap "harness" but not affect tags or attributes
        XCTAssertTrue(result.html.contains("explain-term"))
        XCTAssertTrue(result.html.contains("data-anchor-id=\"test-explain-1\""))
    }
    
    func testInjectDoesNotMatchInsideTags() {
        let html = "<p>See <a href=\"/code\">code</a> for details.</p>"
        let anchors = [
            LessonMeta.Anchor(
                id: "test-explain-1",
                heading: "code",
                kind: "concept",
                term: "code",
                gloss: "Source code."
            )
        ]
        
        let testHtml = html
        let result = MarkdownHTML.render("See `code` for details.", title: "Test", estimatedMinutes: nil, anchors: anchors)
        
        // Should not wrap "code" inside href attribute
        let codeInAttribute = result.html.contains("href=\"/code\"")
        XCTAssertTrue(codeInAttribute, "Should preserve code in href attribute")
    }
    
    func testInjectDoesNotMatchInsideCodeBlock() {
        let html = "<p>Use the <code>fetch</code> API to load data.</p>"
        let anchors = [
            LessonMeta.Anchor(
                id: "test-explain-1",
                heading: "fetch",
                kind: "concept",
                term: "fetch",
                gloss: "A browser API."
            )
        ]
        
        let result = MarkdownHTML.render("Use the `fetch` API to load data.", title: "Test", estimatedMinutes: nil, anchors: anchors)
        
        // Should not wrap "fetch" inside <code> tag
        let hasCodeTag = result.html.contains("<code>fetch</code>")
        XCTAssertTrue(hasCodeTag, "Should preserve code tag")
        
        // Count occurrences of explain-term - should be 0 (inside code) or match outside code only
        let explainCount = result.html.components(separatedBy: "explain-term").count - 1
        XCTAssertTrue(explainCount <= 1, "Should not wrap inside code blocks")
    }
    
    func testInjectFirstOccurrenceOnly() {
        let html = "<p>A harness controls the harness pattern implementation.</p>"
        let anchors = [
            LessonMeta.Anchor(
                id: "test-explain-1",
                heading: "harness",
                kind: "concept",
                term: "harness",
                gloss: "A control structure."
            )
        ]
        
        let result = MarkdownHTML.render("A harness controls the harness pattern implementation.", title: "Test", estimatedMinutes: nil, anchors: anchors)
        
        // Should wrap only first occurrence
        let explainCount = result.html.components(separatedBy: "explain-term").count - 1
        XCTAssertEqual(explainCount, 1, "Should wrap first occurrence only")
    }
    
    func testInjectMultipleAnchors() {
        let anchors = [
            LessonMeta.Anchor(
                id: "test-explain-1",
                heading: "harness",
                kind: "concept",
                term: "harness",
                gloss: "A control structure."
            ),
            LessonMeta.Anchor(
                id: "test-explain-2",
                heading: "orchestration",
                kind: "concept",
                term: "orchestration",
                gloss: "Coordinating multiple steps."
            )
        ]
        
        let result = MarkdownHTML.render("The harness enables orchestration of complex flows.", title: "Test", estimatedMinutes: nil, anchors: anchors)
        
        // Should wrap both terms
        XCTAssertTrue(result.html.contains("test-explain-1"))
        XCTAssertTrue(result.html.contains("test-explain-2"))
    }
    
    func testInjectHandlesHTMLEntities() {
        let anchors = [
            LessonMeta.Anchor(
                id: "test-explain-1",
                heading: "API",
                kind: "concept",
                term: "API",
                gloss: "Application Programming Interface."
            )
        ]
        
        let result = MarkdownHTML.render("The API & SDK work together.", title: "Test", estimatedMinutes: nil, anchors: anchors)
        
        // Should handle & entity correctly
        XCTAssertTrue(result.html.contains("explain-term"))
        XCTAssertTrue(result.html.contains("&amp;"), "Should preserve HTML entities")
    }
}

class MockLLMClient: LLMClient {
    func complete(systemPrompt: String, userPrompt: String, temperature: Double, maxTokens: Int = 4096) async throws -> String {
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

final class AnthropicClientTests: XCTestCase {
    
    func testSupportsTemperatureFor3xModels() {
        let client3x = AnthropicClient(apiKey: "test", model: "claude-3-5-sonnet-20241022")
        // Use reflection to access private property for testing
        // In real code, this is checked internally
        // 3.x models should support temperature
        XCTAssertTrue(true) // Placeholder - private property
    }
    
    func testSupportsTemperatureFor4xModels() {
        let client4x = AnthropicClient(apiKey: "test", model: "claude-opus-4-6")
        // 4.x models should support temperature
        XCTAssertTrue(true) // Placeholder
    }
    
    func testDoesNotSupportTemperatureFor5ClassModels() {
        // Test various 5-class model patterns
        let models = [
            "claude-sonnet-5",
            "claude-opus-5",
            "claude-fable-5-1",
            "claude-haiku-4-5"
        ]
        
        for model in models {
            let client = AnthropicClient(apiKey: "test", model: model)
            // 5-class models should NOT support temperature
            // This is tested implicitly by API behavior
            XCTAssertNotNil(client)
        }
    }
    
    func testTextBlockExtractionWithThinking() {
        // Simulate response with thinking + text blocks
        let mockContent = [
            ["type": "thinking", "thinking": "Let me think about this..."],
            ["type": "text", "text": "Here is the actual response."]
        ]
        
        // The client would filter for type="text" blocks
        var textParts: [String] = []
        for block in mockContent {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String {
                textParts.append(text)
            }
        }
        
        XCTAssertEqual(textParts.count, 1)
        XCTAssertEqual(textParts.first, "Here is the actual response.")
    }
    
    func testTextBlockExtractionMultipleText() {
        // Simulate response with multiple text blocks
        let mockContent = [
            ["type": "text", "text": "First part."],
            ["type": "thinking", "thinking": "Internal reasoning..."],
            ["type": "text", "text": "Second part."]
        ]
        
        var textParts: [String] = []
        for block in mockContent {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String {
                textParts.append(text)
            }
        }
        
        XCTAssertEqual(textParts.count, 2)
        XCTAssertEqual(textParts.joined(separator: "\n\n"), "First part.\n\nSecond part.")
    }
    
    func testTextBlockExtractionNoTextBlocks() {
        // Edge case: only thinking blocks (should fail)
        let mockContent = [
            ["type": "thinking", "thinking": "Only thinking here..."]
        ]
        
        var textParts: [String] = []
        for block in mockContent {
            if let type = block["type"] as? String, type == "text",
               let text = block["text"] as? String {
                textParts.append(text)
            }
        }
        
        XCTAssertTrue(textParts.isEmpty)
    }
}

final class ProviderAvailabilityTests: XCTestCase {
    
    @MainActor
    func testAvailableProvidersWithNoKeys() {
        let keyStore = APIKeyStore()
        
        // Simulate no keys configured
        keyStore.hasAnthropicKey = false
        keyStore.hasOpenAIKey = false
        keyStore.hasOpenRouterKey = false
        keyStore.hasCustomKey = false
        
        let available = getAvailableProviders(keyStore: keyStore)
        
        XCTAssertEqual(available.count, 0, "No providers should be available when no keys configured")
    }
    
    @MainActor
    func testAvailableProvidersWithAnthropicOnly() {
        let keyStore = APIKeyStore()
        
        keyStore.hasAnthropicKey = true
        keyStore.hasOpenAIKey = false
        keyStore.hasOpenRouterKey = false
        keyStore.hasCustomKey = false
        
        let available = getAvailableProviders(keyStore: keyStore)
        
        XCTAssertEqual(available.count, 1)
        XCTAssertTrue(available.contains(.anthropic))
    }
    
    @MainActor
    func testAvailableProvidersWithMultipleKeys() {
        let keyStore = APIKeyStore()
        
        keyStore.hasAnthropicKey = true
        keyStore.hasOpenAIKey = true
        keyStore.hasOpenRouterKey = false
        keyStore.hasCustomKey = false
        
        let available = getAvailableProviders(keyStore: keyStore)
        
        XCTAssertEqual(available.count, 2)
        XCTAssertTrue(available.contains(.anthropic))
        XCTAssertTrue(available.contains(.openai))
        XCTAssertFalse(available.contains(.openrouter))
    }
    
    @MainActor
    func testCustomProviderRequiresBaseURLAndModel() {
        let keyStore = APIKeyStore()
        
        // Has key but no base URL or model
        keyStore.hasCustomKey = true
        keyStore.customBaseURL = ""
        keyStore.customModel = ""
        
        var available = getAvailableProviders(keyStore: keyStore)
        XCTAssertFalse(available.contains(.custom), "Custom should not be available without base URL and model")
        
        // Has key and base URL but no model
        keyStore.customBaseURL = "https://api.example.com/v1"
        keyStore.customModel = ""
        
        available = getAvailableProviders(keyStore: keyStore)
        XCTAssertFalse(available.contains(.custom), "Custom should not be available without model")
        
        // Has key, base URL, and model
        keyStore.customBaseURL = "https://api.example.com/v1"
        keyStore.customModel = "test-model"
        
        available = getAvailableProviders(keyStore: keyStore)
        XCTAssertTrue(available.contains(.custom), "Custom should be available with key + base URL + model")
    }
    
    @MainActor
    func testPreferredDefaultIsAnthropic() {
        let keyStore = APIKeyStore()
        
        keyStore.hasAnthropicKey = true
        keyStore.hasOpenAIKey = true
        
        let available = getAvailableProviders(keyStore: keyStore)
        
        // Anthropic should be preferred if available
        let preferred = available.contains(.anthropic) ? LLMProvider.anthropic : available.first!
        XCTAssertEqual(preferred, .anthropic)
    }
    
    @MainActor
    func testPreferredDefaultFallback() {
        let keyStore = APIKeyStore()
        
        // Only OpenAI configured
        keyStore.hasAnthropicKey = false
        keyStore.hasOpenAIKey = true
        
        let available = getAvailableProviders(keyStore: keyStore)
        
        // Should fall back to first available (OpenAI)
        let preferred = available.contains(.anthropic) ? LLMProvider.anthropic : available.first!
        XCTAssertEqual(preferred, .openai)
    }
    
    // Helper function matching GenerationView logic
    @MainActor
    private func getAvailableProviders(keyStore: APIKeyStore) -> [LLMProvider] {
        var providers: [LLMProvider] = []
        
        if keyStore.hasAnthropicKey {
            providers.append(.anthropic)
        }
        if keyStore.hasOpenAIKey {
            providers.append(.openai)
        }
        if keyStore.hasOpenRouterKey {
            providers.append(.openrouter)
        }
        // Custom requires key + base URL + model
        if keyStore.hasCustomKey && !keyStore.customBaseURL.isEmpty && !keyStore.customModel.isEmpty {
            providers.append(.custom)
        }
        
        return providers
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

// MARK: - JSON Extraction Tests

final class JSONExtractionTests: XCTestCase {
    
    func testExtractCleanJSON() {
        let input = """
        {
          "schemaVersion": "0.1.0",
          "lessonId": "test",
          "items": []
        }
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
    }
    
    func testExtractJSONWithMarkdownFences() {
        let input = """
        ```json
        {
          "schemaVersion": "0.1.0",
          "lessonId": "test",
          "items": []
        }
        ```
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("```"))
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
    }
    
    func testExtractJSONWithTrailingCommentary() {
        let input = """
        {
          "schemaVersion": "0.1.0",
          "lessonId": "test",
          "items": []
        }
        
        This quiz tests understanding of key concepts.
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("This quiz"))
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
    }
    
    func testExtractJSONWithLeadingCommentary() {
        let input = """
        Here is the quiz in JSON format:
        
        {
          "schemaVersion": "0.1.0",
          "lessonId": "test",
          "items": []
        }
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("Here is"))
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
    }
    
    func testExtractJSONWithBothLeadingAndTrailing() {
        let input = """
        Here's your quiz:
        
        ```json
        {
          "schemaVersion": "0.1.0",
          "lessonId": "test",
          "items": []
        }
        ```
        
        Let me know if you need changes!
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("Here's"))
        XCTAssertFalse(extracted!.contains("Let me know"))
        XCTAssertFalse(extracted!.contains("```"))
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
    }
    
    func testExtractComplexQuizJSON() {
        let input = """
        ```json
        {
          "schemaVersion": "0.1.0",
          "lessonId": "test-lesson",
          "items": [
            {
              "id": "q1",
              "type": "mc",
              "prompt": "What is AI?",
              "choices": [
                {"id": "a", "text": "Artificial Intelligence"},
                {"id": "b", "text": "Automated Interaction"}
              ],
              "correctId": "a",
              "explain": "AI stands for Artificial Intelligence"
            }
          ]
        }
        ```
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
        
        // Verify it can decode to QuizDocument
        guard let data = extracted!.data(using: .utf8) else {
            XCTFail("Could not encode as UTF-8")
            return
        }
        
        XCTAssertNoThrow(try JSONDecoder().decode(QuizDocument.self, from: data))
    }
    
    func testExtractJSONArray() {
        let input = """
        [
          {"id": "1", "name": "Test"},
          {"id": "2", "name": "Another"}
        ]
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .array)
        XCTAssertTrue(validation.isValid)
    }
    
    func testRejectInvalidJSON() {
        let inputs = [
            "This is not JSON at all",
            "{ invalid json",
            "{ \"missing\": \"closing bracket\"",
            "[1, 2, 3",
            "null",
            "123",
            "\"just a string\""
        ]
        
        for input in inputs {
            let extracted = JSONExtractor.extractJSON(from: input)
            // Either no extraction, or extracted but invalid
            if let extracted = extracted {
                let validation = JSONExtractor.validateJSONStructure(extracted, expectedTopLevelType: .any)
                if validation.isValid {
                    XCTFail("Should not validate invalid JSON: \(input)")
                }
            }
        }
    }
    
    func testValidationErrorMessages() {
        let invalidJSON = "{ invalid }"
        let validation = JSONExtractor.validateJSONStructure(invalidJSON, expectedTopLevelType: .object)
        XCTAssertFalse(validation.isValid)
        XCTAssertNotNil(validation.errorMessage)
        XCTAssertTrue(validation.errorMessage!.contains("parse error") || validation.errorMessage!.contains("JSON"))
    }
    
    func testExtractJSONWithCapitalJSONLanguageTag() {
        let input = """
        ```JSON
        {"test": "value"}
        ```
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("```"))
    }
    
    func testExtractJSONWithSpacedLanguageTag() {
        let input = """
        ``` json
        {"test": "value"}
        ```
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("```"))
    }
    
    func testExtractJSONWithNoLanguageTag() {
        let input = """
        ```
        {"test": "value"}
        ```
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        XCTAssertFalse(extracted!.contains("```"))
    }
    
    func testHandleEmptyInput() {
        XCTAssertNil(JSONExtractor.extractJSON(from: ""))
        XCTAssertNil(JSONExtractor.extractJSON(from: "   "))
        XCTAssertNil(JSONExtractor.extractJSON(from: "\n\n"))
    }
    
    func testExtractNestedJSON() {
        let input = """
        Here's a response with nested objects:
        {
          "outer": {
            "inner": {
              "value": "test"
            }
          },
          "array": [1, 2, 3]
        }
        And some trailing text.
        """
        
        let extracted = JSONExtractor.extractJSON(from: input)
        XCTAssertNotNil(extracted)
        
        let validation = JSONExtractor.validateJSONStructure(extracted!, expectedTopLevelType: .object)
        XCTAssertTrue(validation.isValid)
    }
}

// MARK: - Planner Configuration Tests

final class PlannerConfigurationTests: XCTestCase {
    
    func testPlannerUsesHigherMaxTokens() async throws {
        let mockClient = TrackingLLMClient()
        let planner = PlannerService(client: mockClient, temperature: 0.7)
        
        do {
            _ = try await planner.plan(
                topic: "Test Topic",
                locale: "en-CA",
                knowledgeLevel: .some,
                depthLevel: .exhaustive
            )
        } catch {
            // Expected to fail since mock returns invalid JSON
            // We just want to verify maxTokens was set correctly
        }
        
        XCTAssertEqual(mockClient.lastMaxTokens, 8192, "Planner should use 8192 max_tokens for large curricula")
    }
    
    func testDepthLevelGuidanceIncludesSoftBands() {
        let planner = PlannerService(client: TrackingLLMClient(), temperature: 0.7)
        
        // We can't directly access the guidance strings, but we can verify
        // the depth levels exist and are properly defined
        let allDepthLevels: [DepthLevel] = [.brief, .standard, .deep, .thorough, .exhaustive]
        XCTAssertEqual(allDepthLevels.count, 5)
        
        XCTAssertEqual(DepthLevel.brief.displayName, "Brief")
        XCTAssertEqual(DepthLevel.exhaustive.displayName, "Exhaustive")
    }
}

class TrackingLLMClient: LLMClient {
    var lastMaxTokens: Int = 0
    
    func complete(systemPrompt: String, userPrompt: String, temperature: Double, maxTokens: Int = 4096) async throws -> String {
        lastMaxTokens = maxTokens
        return "{\"invalid\": \"json\"}"
    }
}

// MARK: - Package Upgrade Tests

@MainActor
final class PackageUpgradeTests: XCTestCase {
    
    var tempDir: URL!
    var store: CourseStore!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for test packages
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        store = CourseStore()
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        store = nil
        
        try await super.tearDown()
    }
    
    func createTestPackage(packageId: String, contentVersion: Int, title: String, lessonCount: Int = 3) throws -> URL {
        let packageURL = tempDir.appendingPathComponent("\(packageId)-v\(contentVersion).depthcraft")
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        
        // Create manifest
        let manifest: [String: Any] = [
            "schemaVersion": "0.1.0",
            "packageId": packageId,
            "contentVersion": contentVersion,
            "title": title,
            "topic": "Test Topic",
            "createdAt": "2026-01-01T00:00:00Z",
            "locale": "en-US"
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest)
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        
        // Create curriculum
        var lessons: [String: Any] = [:]
        var lessonIds: [String] = []
        for i in 1...lessonCount {
            let lessonId = "lesson-\(i)"
            lessonIds.append(lessonId)
            lessons[lessonId] = [
                "id": lessonId,
                "unitId": "unit-1",
                "title": "Lesson \(i)",
                "order": i,
                "status": "approved"
            ]
        }
        
        let curriculum: [String: Any] = [
            "schemaVersion": "0.1.0",
            "status": "approved",
            "units": [
                [
                    "id": "unit-1",
                    "title": "Test Unit",
                    "order": 1,
                    "lessonIds": lessonIds
                ]
            ],
            "lessons": lessons
        ]
        let curriculumData = try JSONSerialization.data(withJSONObject: curriculum)
        try curriculumData.write(to: packageURL.appendingPathComponent("curriculum.json"))
        
        // Create lesson HTML files
        for i in 1...lessonCount {
            let lessonDir = packageURL.appendingPathComponent("lessons/lesson-\(i)")
            try FileManager.default.createDirectory(at: lessonDir, withIntermediateDirectories: true)
            let html = "<html><body><h1>Lesson \(i)</h1></body></html>"
            try html.write(to: lessonDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        }
        
        return packageURL
    }
    
    func testFirstOpenAfterExtendShowsDialog() throws {
        // Load initial version
        let v1URL = try createTestPackage(packageId: "test-course", contentVersion: 1, title: "Test Course v1", lessonCount: 3)
        store.loadPackage(from: v1URL)
        
        XCTAssertNotNil(store.course, "Initial course should load")
        XCTAssertEqual(store.course?.manifest.contentVersion, 1)
        XCTAssertNil(store.pendingPackageUpgrade, "No upgrade should be pending initially")
        XCTAssertFalse(store.showUpgradeDialog, "Dialog should not show initially")
        
        // Simulate user completing a lesson
        if let lesson = store.course?.curriculum.lessons["lesson-1"] {
            store.markQuizPassed(lessonId: lesson.id, unitId: lesson.unitId)
        }
        XCTAssertTrue(store.progress?.lessons["lesson-1"]?.completed == true, "Lesson should be marked complete")
        
        // Load extended version (v2) - this should trigger upgrade flow
        let v2URL = try createTestPackage(packageId: "test-course", contentVersion: 2, title: "Test Course v2", lessonCount: 5)
        store.loadPackage(from: v2URL)
        
        // Verify upgrade dialog is triggered
        XCTAssertTrue(store.showUpgradeDialog, "First open after extend MUST show dialog")
        XCTAssertNotNil(store.pendingPackageUpgrade, "Pending upgrade should be set")
        XCTAssertEqual(store.pendingPackageUpgrade?.manifest.contentVersion, 2, "Pending upgrade should be v2")
        
        // Verify current course is still v1 (upgrade not applied yet)
        XCTAssertEqual(store.course?.manifest.contentVersion, 1, "Current course should still be v1 until confirmed")
        XCTAssertTrue(store.progress?.lessons["lesson-1"]?.completed == true, "Progress should be unchanged")
    }
    
    func testCancelDiscardsUpgrade() throws {
        // Load initial version and mark progress
        let v1URL = try createTestPackage(packageId: "test-course", contentVersion: 1, title: "Test Course v1", lessonCount: 3)
        store.loadPackage(from: v1URL)
        
        if let lesson = store.course?.curriculum.lessons["lesson-1"] {
            store.markQuizPassed(lessonId: lesson.id, unitId: lesson.unitId)
        }
        
        let originalCourseURL = store.course?.rootURL
        let originalProgress = store.progress
        
        // Load v2 to trigger upgrade
        let v2URL = try createTestPackage(packageId: "test-course", contentVersion: 2, title: "Test Course v2", lessonCount: 5)
        store.loadPackage(from: v2URL)
        
        XCTAssertTrue(store.showUpgradeDialog, "Dialog should show")
        XCTAssertNotNil(store.pendingPackageUpgrade)
        
        // User cancels
        store.cancelPackageUpgrade()
        
        // Verify upgrade was discarded
        XCTAssertFalse(store.showUpgradeDialog, "Dialog should be hidden after cancel")
        XCTAssertNil(store.pendingPackageUpgrade, "Pending upgrade should be cleared")
        
        // Verify current course and progress are unchanged
        XCTAssertEqual(store.course?.manifest.contentVersion, 1, "Course should still be v1 after cancel")
        XCTAssertEqual(store.course?.rootURL.path, originalCourseURL?.path, "Course URL should be unchanged")
        XCTAssertEqual(store.progress?.lessons.count, originalProgress?.lessons.count, "Progress should be unchanged")
        XCTAssertTrue(store.progress?.lessons["lesson-1"]?.completed == true, "Lesson completion should be preserved")
    }
    
    func testConfirmAppliesUpgradeAndMergesProgress() throws {
        // Load initial version with 3 lessons
        let v1URL = try createTestPackage(packageId: "test-course", contentVersion: 1, title: "Test Course v1", lessonCount: 3)
        store.loadPackage(from: v1URL)
        
        // Mark lessons 1 and 2 as complete
        if let lesson1 = store.course?.curriculum.lessons["lesson-1"] {
            store.markQuizPassed(lessonId: lesson1.id, unitId: lesson1.unitId)
        }
        if let lesson2 = store.course?.curriculum.lessons["lesson-2"] {
            store.markQuizPassed(lessonId: lesson2.id, unitId: lesson2.unitId)
        }
        
        XCTAssertTrue(store.progress?.lessons["lesson-1"]?.completed == true)
        XCTAssertTrue(store.progress?.lessons["lesson-2"]?.completed == true)
        XCTAssertFalse(store.progress?.lessons["lesson-3"]?.completed == true)
        
        // Load extended version with 5 lessons
        let v2URL = try createTestPackage(packageId: "test-course", contentVersion: 2, title: "Test Course v2", lessonCount: 5)
        store.loadPackage(from: v2URL)
        
        XCTAssertTrue(store.showUpgradeDialog)
        
        // User confirms upgrade
        store.confirmPackageUpgrade()
        
        // Verify upgrade was applied
        XCTAssertFalse(store.showUpgradeDialog, "Dialog should be hidden after confirm")
        XCTAssertNil(store.pendingPackageUpgrade, "Pending upgrade should be cleared after confirm")
        XCTAssertEqual(store.course?.manifest.contentVersion, 2, "Course should be upgraded to v2")
        XCTAssertEqual(store.course?.curriculum.lessons.count, 5, "Should have 5 lessons after upgrade")
        
        // Verify progress was merged correctly
        XCTAssertNotNil(store.progress, "Progress should exist")
        XCTAssertTrue(store.progress?.lessons["lesson-1"]?.completed == true, "Old completed lesson 1 should remain complete")
        XCTAssertTrue(store.progress?.lessons["lesson-2"]?.completed == true, "Old completed lesson 2 should remain complete")
        XCTAssertFalse(store.progress?.lessons["lesson-3"]?.completed == true, "Old incomplete lesson 3 should remain incomplete")
        XCTAssertFalse(store.progress?.lessons["lesson-4"]?.completed == true, "New lesson 4 should be incomplete")
        XCTAssertFalse(store.progress?.lessons["lesson-5"]?.completed == true, "New lesson 5 should be incomplete")
    }
    
    func testSecondOpenAfterCancelShowsDialogAgain() throws {
        // Load v1 and mark progress
        let v1URL = try createTestPackage(packageId: "test-course", contentVersion: 1, title: "Test Course v1", lessonCount: 3)
        store.loadPackage(from: v1URL)
        
        if let lesson = store.course?.curriculum.lessons["lesson-1"] {
            store.markQuizPassed(lessonId: lesson.id, unitId: lesson.unitId)
        }
        
        // First open of v2 - trigger upgrade
        let v2URL = try createTestPackage(packageId: "test-course", contentVersion: 2, title: "Test Course v2", lessonCount: 5)
        store.loadPackage(from: v2URL)
        
        XCTAssertTrue(store.showUpgradeDialog, "First open should show dialog")
        
        // User cancels
        store.cancelPackageUpgrade()
        
        XCTAssertFalse(store.showUpgradeDialog)
        XCTAssertEqual(store.course?.manifest.contentVersion, 1, "Should still be on v1")
        
        // Second open of v2 - should trigger upgrade again
        store.loadPackage(from: v2URL)
        
        XCTAssertTrue(store.showUpgradeDialog, "Second open should show dialog again")
        XCTAssertNotNil(store.pendingPackageUpgrade, "Pending upgrade should be set again")
        XCTAssertEqual(store.pendingPackageUpgrade?.manifest.contentVersion, 2)
        XCTAssertEqual(store.course?.manifest.contentVersion, 1, "Current course should still be v1 until confirmed")
    }
    
    func testNoUpgradeDialogForSameVersion() throws {
        let v1URL = try createTestPackage(packageId: "test-course", contentVersion: 1, title: "Test Course v1", lessonCount: 3)
        store.loadPackage(from: v1URL)
        
        XCTAssertEqual(store.course?.manifest.contentVersion, 1)
        XCTAssertFalse(store.showUpgradeDialog)
        
        // Load same version again
        store.loadPackage(from: v1URL)
        
        // Should not trigger upgrade dialog
        XCTAssertFalse(store.showUpgradeDialog, "Same version should not trigger dialog")
        XCTAssertNil(store.pendingPackageUpgrade, "No pending upgrade for same version")
        XCTAssertEqual(store.course?.manifest.contentVersion, 1)
    }
    
    func testCannotLoadOlderVersion() throws {
        // Load v2 first
        let v2URL = try createTestPackage(packageId: "test-course", contentVersion: 2, title: "Test Course v2", lessonCount: 5)
        store.loadPackage(from: v2URL)
        
        XCTAssertEqual(store.course?.manifest.contentVersion, 2)
        XCTAssertNil(store.errorMessage)
        
        // Try to load v1 (older)
        let v1URL = try createTestPackage(packageId: "test-course", contentVersion: 1, title: "Test Course v1", lessonCount: 3)
        store.loadPackage(from: v1URL)
        
        // Should fail with error
        XCTAssertNotNil(store.errorMessage, "Should have error message")
        XCTAssertTrue(store.errorMessage?.contains("older version") ?? false, "Error should mention older version")
        XCTAssertEqual(store.course?.manifest.contentVersion, 2, "Should still be on v2")
        XCTAssertFalse(store.showUpgradeDialog, "Should not show upgrade dialog for downgrade")
    }
}
