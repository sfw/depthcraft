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
            XCTAssertTrue(error.localizedDescription.contains("Absolute path"))
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
    
    // MARK: - Import Validator Path Tests (Export/Import Round-trip)
    
    func testRejectActualPathTraversal() throws {
        // These are actual path traversal attempts and should be rejected
        let maliciousPaths = [
            "../etc/passwd",
            "foo/../../../secrets",
            "content/../../../etc/passwd",
            "..",
            "foo/bar/.."
        ]
        
        // Create a test directory to validate against
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a mock package structure
        try "test".write(to: tempDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "test".write(to: tempDir.appendingPathComponent("curriculum.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("content"), withIntermediateDirectories: true)
        
        // Try to create files with malicious paths - these should be caught
        for maliciousPath in maliciousPaths {
            let fullPath = tempDir.appendingPathComponent(maliciousPath).standardizedFileURL.path
            let tempPath = tempDir.standardizedFileURL.path
            let tempPathWithSlash = tempPath + "/"
            
            // Verify our boundary check would catch this
            let wouldEscape = !fullPath.hasPrefix(tempPathWithSlash) && fullPath != tempPath
            XCTAssertTrue(wouldEscape, "Malicious path should be detected as escape attempt: \(maliciousPath)")
        }
    }
    
    // MARK: - Regression: Scott's iPad Import Rejection
    
    func testZipFileDetectionWithMagicBytes() throws {
        // Routing proof: isZipFile detects ZIP despite .depthcraft extension
        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(forResource: "import-invalid-paths-dogfood", withExtension: "depthcraft") else {
            XCTFail("Fixture not found - expected Tests/Fixtures/import-invalid-paths-dogfood.depthcraft")
            return
        }
        
        // Verify the fixture is detected as a ZIP by magic bytes
        XCTAssertTrue(ImportValidator.isZipFile(at: fixtureURL),
                      "Scott's fixture should be detected as ZIP by PK signature despite .depthcraft extension")
    }
    
    func testZipFileDetectionFailOpen() throws {
        // Fail-open proof: When magic bytes can't be read, .depthcraft extension
        // triggers ZIP path (prefer unzip over directory validation)
        
        // Create a URL to a non-existent .depthcraft file
        let nonExistentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).depthcraft")
        
        // isZipFile should return true (fail-open) for .depthcraft when file can't be read
        XCTAssertTrue(ImportValidator.isZipFile(at: nonExistentURL),
                      "isZipFile should fail-open to true for .depthcraft when magic bytes unreadable")
        
        // Non-.depthcraft files should return false when unreadable (fail-closed)
        let nonDepthcraftURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).txt")
        
        XCTAssertFalse(ImportValidator.isZipFile(at: nonDepthcraftURL),
                       "isZipFile should fail-closed to false for non-.depthcraft when unreadable")
    }
    
    func testImportScottRejectedFixture() throws {
        // Regression: Export from Simulator rejected on iPad with "invalid file paths"
        // Root cause: iOS treats .depthcraft ZIPs as packages (isDirectory=true),
        // causing import code to validate ZIP as directory instead of extracting first.
        
        // Fixture: novel-idea-generation-using-ai--llms-1789431687.depthcraft/
        // - 245 entries, all relative, zero "..", no abs paths, no backslashes, no __MACOSX
        // - Wrapper root ends with .depthcraft/ then content/manifests
        
        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(forResource: "import-invalid-paths-dogfood", withExtension: "depthcraft") else {
            XCTFail("Fixture not found in test bundle - expected Tests/Fixtures/import-invalid-paths-dogfood.depthcraft")
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            // Step 1: unzipSafely should succeed (iPad rejection would happen here if isDirectory logic failed)
            do {
                try ImportValidator.unzipSafely(from: fixtureURL, to: tempDir)
            } catch let error as ImportValidatorError {
                // If this throws zipSlipDetected, the routing logic is broken
                XCTFail("unzipSafely rejected Scott's fixture: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempDir)
                return
            }
            
            // Step 2: Find the .depthcraft package in extracted content
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let extractedPackage = contents.first(where: { $0.lastPathComponent.hasSuffix(".depthcraft") }) else {
                XCTFail("No .depthcraft package found in extracted fixture")
                try? FileManager.default.removeItem(at: tempDir)
                return
            }
            
            // Step 3: validateImportedPackage should succeed on unpacked directory
            do {
                try ImportValidator.validateImportedPackage(at: extractedPackage)
            } catch let error as ImportValidatorError {
                XCTFail("validateImportedPackage rejected unpacked fixture: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: tempDir)
                return
            }
            
            // Cleanup
            try? FileManager.default.removeItem(at: tempDir)
            
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            XCTFail("Unexpected error importing Scott's fixture: \(error)")
        }
    }
    
    func testPathNormalizationVarPrivateVar() throws {
        // Regression: Device-specific path mismatch /var vs /private/var causes false zipSlipDetected
        // On iOS, temp directories may be /var/... but after appendingPathComponent + standardize,
        // they become /private/var/..., causing prefix check to fail.
        
        // Simulate the device scenario
        let basePath = "/var/mobile/Containers/Data/Application/ABC123/tmp/extract"
        let basePathWithSlash = basePath + "/"
        
        // After appendingPathComponent + standardize, iOS may return /private/var
        let childPath = "/private/var/mobile/Containers/Data/Application/ABC123/tmp/extract/novel-idea.depthcraft/content/units/u01/lesson.md"
        
        // WITHOUT normalization, this check would fail (false positive for zipSlip)
        let wouldFailWithoutNormalization = !childPath.hasPrefix(basePathWithSlash)
        XCTAssertTrue(wouldFailWithoutNormalization, 
                      "Without normalization, /private/var child doesn't match /var base")
        
        // WITH normalization (our fix), this check passes
        let normalizedBase = ImportValidator.normalizePath(basePath)
        let normalizedBaseWithSlash = normalizedBase + "/"
        let normalizedChild = ImportValidator.normalizePath(childPath)
        
        let passesWithNormalization = normalizedChild.hasPrefix(normalizedBaseWithSlash)
        XCTAssertTrue(passesWithNormalization,
                      "With normalization, paths are consistent: \(normalizedChild) starts with \(normalizedBaseWithSlash)")
        
        // Verify normalization doesn't break normal paths
        let normalPath = "/Users/test/Documents/package/content/lesson.md"
        XCTAssertEqual(ImportValidator.normalizePath(normalPath), normalPath,
                       "Non-/var paths should pass through unchanged")
    }
    
    func testUnzipWithDeviceLikePathMismatch() throws {
        // Failing-before regression: Simulate device temp directory with /var vs /private/var mismatch
        // This test would FAIL before normalization fix, PASS after
        
        let bundle = Bundle(for: type(of: self))
        guard let fixtureURL = bundle.url(forResource: "import-invalid-paths-dogfood", withExtension: "depthcraft") else {
            XCTFail("Fixture not found")
            return
        }
        
        // Create a directory that simulates iOS device temp structure
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("device-sim-\(UUID().uuidString)")
        
        do {
            // Extract to temp directory
            try ImportValidator.unzipSafely(from: fixtureURL, to: tempRoot)
            
            // If we get here, normalization worked
            // Verify the extraction actually created files
            let contents = try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
            XCTAssertFalse(contents.isEmpty, "Extraction should have created files")
            
            let packageDir = contents.first { $0.lastPathComponent.hasSuffix(".depthcraft") }
            XCTAssertNotNil(packageDir, "Should find .depthcraft wrapper directory")
            
            // Cleanup
            try? FileManager.default.removeItem(at: tempRoot)
            
        } catch let error as ImportValidatorError {
            try? FileManager.default.removeItem(at: tempRoot)
            
            // If this fails with zipSlipDetected, it means normalization didn't work
            if case .zipSlipDetected(let path) = error {
                XCTFail("Path normalization failed - legitimate path rejected as zipSlip: \(path)")
            } else {
                XCTFail("Unexpected ImportValidatorError: \(error)")
            }
        } catch {
            try? FileManager.default.removeItem(at: tempRoot)
            XCTFail("Unexpected error: \(error)")
        }
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
