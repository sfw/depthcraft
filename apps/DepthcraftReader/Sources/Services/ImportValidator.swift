import Foundation
import Compression

enum ImportValidatorError: LocalizedError {
    case invalidPackageStructure(String)
    case securityViolation(String)
    case schemaValidationFailed(String)
    case zipSlipDetected(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPackageStructure(let details):
            return "Invalid package structure: \(details)"
        case .securityViolation(let details):
            return "Security violation detected: \(details)"
        case .schemaValidationFailed(let details):
            return "Package validation failed: \(details)"
        case .zipSlipDetected(let path):
            return "Zip slip attack detected: \(path)"
        }
    }
    
    var userFriendlyDescription: String {
        switch self {
        case .invalidPackageStructure:
            return "This package file is damaged or incomplete. Please regenerate the course or obtain a valid package."
        case .securityViolation:
            return "This package contains unsafe content and cannot be imported. Please ensure the package is from a trusted source."
        case .schemaValidationFailed:
            return "This package format is invalid or incompatible. Please regenerate the course with the latest version."
        case .zipSlipDetected:
            return "This package contains invalid file paths and cannot be imported for security reasons."
        }
    }
}

enum ImportValidator {
    
    /// Safely unzips a file with zip-slip protection (iOS-safe, in-process)
    static func unzipSafely(from zipURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        // Create destination directory
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Read the zip file
        let zipData = try Data(contentsOf: zipURL)
        
        // Parse ZIP using Foundation
        guard let archive = try? ZipArchive(data: zipData) else {
            throw ImportValidatorError.invalidPackageStructure("Not a valid ZIP archive")
        }
        
        let basePathWithSlash = destinationURL.standardizedFileURL.path + "/"
        
        // Extract each entry with zip-slip protection BEFORE writing
        for entry in archive.entries {
            let entryPath = entry.path
            
            // SKIP Apple metadata files that may be added during export/sharing
            if shouldSkipAppleMetadata(entryPath) {
                continue
            }
            
            // REFUSE path traversal attempts (../ or /../) or absolute paths BEFORE writing
            if hasPathTraversal(entryPath) {
                throw ImportValidatorError.zipSlipDetected(entryPath)
            }
            
            if entryPath.hasPrefix("/") {
                throw ImportValidatorError.zipSlipDetected(entryPath)
            }
            
            // Build destination path and verify it's within destinationURL
            let destinationPath = destinationURL.appendingPathComponent(entryPath).standardizedFileURL.path
            
            // Use path + "/" boundary check to prevent escapes
            if !destinationPath.hasPrefix(basePathWithSlash) && destinationPath != destinationURL.standardizedFileURL.path {
                throw ImportValidatorError.zipSlipDetected(entryPath)
            }
            
            let destinationFileURL = URL(fileURLWithPath: destinationPath)
            
            // Create parent directory if needed
            let parentDir = destinationFileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }
            
            // Extract the entry
            if entry.type == .directory {
                try fileManager.createDirectory(at: destinationFileURL, withIntermediateDirectories: true)
            } else {
                // Extract file data
                let extractedData = try archive.extract(entry: entry, from: zipData)
                try extractedData.write(to: destinationFileURL)
            }
        }
        
        // Strip progress.json if present (device-local ProgressStore is authoritative)
        let progressURL = destinationURL.appendingPathComponent("progress.json")
        if fileManager.fileExists(atPath: progressURL.path) {
            try? fileManager.removeItem(at: progressURL)
        }
        
        // Look for .depthcraft package in extracted content
        let contents = try fileManager.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil)
        for item in contents where item.lastPathComponent.hasSuffix(".depthcraft") {
            let packageProgressURL = item.appendingPathComponent("progress.json")
            if fileManager.fileExists(atPath: packageProgressURL.path) {
                try? fileManager.removeItem(at: packageProgressURL)
            }
        }
    }
    
    /// Validates an imported package before it's loaded
    static func validateImportedPackage(at packageURL: URL) throws {
        let fileManager = FileManager.default
        
        // 1. Check if it's a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ImportValidatorError.invalidPackageStructure("Package must be a directory")
        }
        
        // 2. Validate all paths in package to prevent zip-slip
        try validatePackagePaths(at: packageURL)
        
        // 3. Load and validate manifest
        let manifest: PackageManifest = try decode("manifest.json", from: packageURL)
        do {
            try SchemaValidator.validateManifest(manifest)
        } catch {
            throw ImportValidatorError.schemaValidationFailed(error.localizedDescription)
        }
        
        // 4. Load and validate curriculum
        let curriculum: Curriculum = try decode("curriculum.json", from: packageURL)
        do {
            try SchemaValidator.validateCurriculum(curriculum)
        } catch {
            throw ImportValidatorError.schemaValidationFailed(error.localizedDescription)
        }
        
        // 5. Validate package structure
        try validateRequiredFiles(at: packageURL, curriculum: curriculum)
        
        // 6. Scan lessons for unsafe content
        try validateLessonContent(at: packageURL, curriculum: curriculum)
        
        // 7. Validate demos for security issues
        try validateDemos(at: packageURL, curriculum: curriculum)
    }
    
    private static func validatePackagePaths(at packageURL: URL) throws {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: packageURL.path)
        
        while let relativePath = enumerator?.nextObject() as? String {
            // Skip Apple metadata files
            if shouldSkipAppleMetadata(relativePath) {
                continue
            }
            
            // Check for path traversal attempts
            if hasPathTraversal(relativePath) {
                throw ImportValidatorError.zipSlipDetected(relativePath)
            }
            
            // Check for absolute paths
            if relativePath.hasPrefix("/") {
                throw ImportValidatorError.zipSlipDetected(relativePath)
            }
            
            // Construct full path and verify it's within package directory
            let fullPath = packageURL.appendingPathComponent(relativePath).standardizedFileURL.path
            let packagePath = packageURL.standardizedFileURL.path
            
            if !fullPath.hasPrefix(packagePath) {
                throw ImportValidatorError.zipSlipDetected(relativePath)
            }
        }
    }
    
    private static func validateRequiredFiles(at packageURL: URL, curriculum: Curriculum) throws {
        let fileManager = FileManager.default
        
        // Check for required files (progress.json is optional - device-local ProgressStore is authoritative)
        let requiredFiles = ["manifest.json", "curriculum.json"]
        for file in requiredFiles {
            let fileURL = packageURL.appendingPathComponent(file)
            if !fileManager.fileExists(atPath: fileURL.path) {
                throw ImportValidatorError.invalidPackageStructure("Missing required file: \(file)")
            }
        }
        
        // Check content directory exists
        let contentURL = packageURL.appendingPathComponent("content")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: contentURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ImportValidatorError.invalidPackageStructure("Missing content directory")
        }
        
        // Validate each unit and lesson exists
        for unit in curriculum.units {
            let unitURL = contentURL.appendingPathComponent("units/\(unit.id)")
            guard fileManager.fileExists(atPath: unitURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ImportValidatorError.invalidPackageStructure("Missing unit directory: \(unit.id)")
            }
            
            for lessonId in unit.lessonIds {
                let lessonURL = unitURL.appendingPathComponent("lessons/\(lessonId)")
                guard fileManager.fileExists(atPath: lessonURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw ImportValidatorError.invalidPackageStructure("Missing lesson directory: \(lessonId)")
                }
                
                // Check required lesson files
                let lessonFiles = ["lesson.md", "meta.json", "quiz.json"]
                for file in lessonFiles {
                    let fileURL = lessonURL.appendingPathComponent(file)
                    if !fileManager.fileExists(atPath: fileURL.path) {
                        throw ImportValidatorError.invalidPackageStructure("Missing lesson file: \(lessonId)/\(file)")
                    }
                }
            }
        }
    }
    
    private static func validateLessonContent(at packageURL: URL, curriculum: Curriculum) throws {
        // Validate lesson markdown and meta.json for each lesson
        for unit in curriculum.units {
            for lessonId in unit.lessonIds {
                // Validate IDs to prevent path traversal
                try SchemaValidator.validateId(unit.id, name: "unitId")
                try SchemaValidator.validateId(lessonId, name: "lessonId")
                
                let lessonURL = packageURL
                    .appendingPathComponent("content/units/\(unit.id)/lessons/\(lessonId)")
                
                // Load and validate meta.json
                let _: LessonMeta = try decode("meta.json", from: lessonURL)
                
                // Load and scan lesson.md for dangerous content
                let markdownURL = lessonURL.appendingPathComponent("lesson.md")
                let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
                try validateMarkdownContent(markdown, lessonId: lessonId)
                
                // Load and validate quiz.json
                let quizURL = lessonURL.appendingPathComponent("quiz.json")
                let quizData = try Data(contentsOf: quizURL)
                let quiz = try JSONDecoder().decode(QuizDocument.self, from: quizData)
                try SchemaValidator.validateQuiz(quiz, expectedLessonId: lessonId)
            }
        }
    }
    
    private static func validateMarkdownContent(_ markdown: String, lessonId: String) throws {
        // Check for common XSS patterns
        let dangerousPatterns = [
            "<script",
            "javascript:",
            "onerror=",
            "onload=",
            "<iframe",
            "data:text/html"
        ]
        
        let lowercased = markdown.lowercased()
        for pattern in dangerousPatterns {
            if lowercased.contains(pattern) {
                throw ImportValidatorError.securityViolation("Lesson \(lessonId) contains potentially unsafe content: \(pattern)")
            }
        }
    }
    
    private static func validateDemos(at packageURL: URL, curriculum: Curriculum) throws {
        let fileManager = FileManager.default
        
        for unit in curriculum.units {
            for lessonId in unit.lessonIds {
                let demosURL = packageURL
                    .appendingPathComponent("content/units/\(unit.id)/lessons/\(lessonId)/demos")
                
                // Check if demos directory exists
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: demosURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue // No demos for this lesson
                }
                
                // Enumerate demo directories
                let demoContents = try fileManager.contentsOfDirectory(atPath: demosURL.path)
                for demoId in demoContents {
                    let demoURL = demosURL.appendingPathComponent(demoId)
                    
                    // Validate demo ID
                    try SchemaValidator.validateId(demoId, name: "demoId")
                    
                    // Load and validate demo.json
                    let manifestURL = demoURL.appendingPathComponent("demo.json")
                    guard fileManager.fileExists(atPath: manifestURL.path) else {
                        continue
                    }
                    
                    let manifestData = try Data(contentsOf: manifestURL)
                    let manifest = try JSONDecoder().decode(DemoManifest.self, from: manifestData)
                    try SchemaValidator.validateDemoManifest(manifest, expectedDemoId: demoId)
                    
                    // Validate entry HTML for external URLs and fetch
                    let entryURL = demoURL.appendingPathComponent(manifest.entry)
                    if fileManager.fileExists(atPath: entryURL.path) {
                        let entryContent = try String(contentsOf: entryURL, encoding: .utf8)
                        try validateDemoContent(entryContent, demoId: demoId, file: manifest.entry)
                    }
                    
                    // Validate fallback markdown
                    let fallbackURL = demoURL.appendingPathComponent(manifest.fallback)
                    if fileManager.fileExists(atPath: fallbackURL.path) {
                        let fallbackContent = try String(contentsOf: fallbackURL, encoding: .utf8)
                        try validateMarkdownContent(fallbackContent, lessonId: "\(lessonId)/demo/\(demoId)")
                    }
                }
            }
        }
    }
    
    private static func validateDemoContent(_ content: String, demoId: String, file: String) throws {
        // Check for external URLs
        let urlPatterns = [
            "http://",
            "https://",
            "//cdn",
            "//unpkg",
            "//jsdelivr"
        ]
        
        for pattern in urlPatterns {
            if content.contains(pattern) {
                throw ImportValidatorError.securityViolation("Demo \(demoId) file \(file) contains external URL: \(pattern)")
            }
        }
        
        // Check for mid-flight fetch patterns
        let fetchPatterns = [
            "fetch(",
            "XMLHttpRequest",
            ".ajax("
        ]
        
        for pattern in fetchPatterns {
            if content.contains(pattern) {
                throw ImportValidatorError.securityViolation("Demo \(demoId) file \(file) contains network fetch pattern: \(pattern)")
            }
        }
    }
    
    private static func decode<T: Decodable>(_ name: String, from root: URL) throws -> T {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportValidatorError.invalidPackageStructure("Missing file: \(name)")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ImportValidatorError.schemaValidationFailed("Could not decode \(name): \(error.localizedDescription)")
        }
    }
    
    /// Skip Apple metadata files that may be added during export/sharing
    private static func shouldSkipAppleMetadata(_ path: String) -> Bool {
        // Skip __MACOSX directory (macOS resource forks)
        if path.hasPrefix("__MACOSX/") || path == "__MACOSX" {
            return true
        }
        
        // Skip .DS_Store files (Finder metadata)
        let components = path.split(separator: "/")
        if components.last == ".DS_Store" {
            return true
        }
        
        // Skip AppleDouble files (._filename)
        if let lastComponent = components.last, lastComponent.hasPrefix("._") {
            return true
        }
        
        return false
    }
    
    /// Check for actual path traversal attempts (../ or /../), not just any ".." substring
    private static func hasPathTraversal(_ path: String) -> Bool {
        // Normalize path separators
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        
        // Check for explicit traversal patterns
        if normalized.hasPrefix("../") || normalized.contains("/../") || normalized.hasSuffix("/..") || normalized == ".." {
            return true
        }
        
        return false
    }
}

// Minimal ZIP archive reader using Foundation
private struct ZipArchive {
    let entries: [ZipEntry]
    
    init(data: Data) throws {
        guard data.count >= 22 else {
            throw ImportValidatorError.invalidPackageStructure("File too small to be a ZIP")
        }
        
        // Find End of Central Directory (EOCD)
        guard let eocdOffset = Self.findEOCD(in: data) else {
            throw ImportValidatorError.invalidPackageStructure("Could not find ZIP central directory")
        }
        
        // Parse EOCD to get central directory location
        let centralDirOffset = Int(data.uint32(at: eocdOffset + 16))
        let entryCount = Int(data.uint16(at: eocdOffset + 10))
        
        // Parse central directory entries
        var parsedEntries: [ZipEntry] = []
        var offset = centralDirOffset
        
        for _ in 0..<entryCount {
            guard let entry = ZipEntry.parse(from: data, at: offset) else {
                break
            }
            parsedEntries.append(entry)
            offset = entry.nextCentralDirOffset
        }
        
        self.entries = parsedEntries
    }
    
    private static func findEOCD(in data: Data) -> Int? {
        // EOCD signature: 0x06054b50
        let signature: UInt32 = 0x06054b50
        
        // Search backwards from end (EOCD is usually at the end)
        let searchStart = data.count - 22
        let searchEnd = Swift.max(0, data.count - 65557)
        
        for i in stride(from: searchStart, through: searchEnd, by: -1) {
            if data.uint32(at: i) == signature {
                return i
            }
        }
        return nil
    }
    
    func extract(entry: ZipEntry, from data: Data) throws -> Data {
        // Read local file header to get actual data offset
        let localHeaderOffset = entry.localHeaderOffset
        let fileNameLength = Int(data.uint16(at: localHeaderOffset + 26))
        let extraFieldLength = Int(data.uint16(at: localHeaderOffset + 28))
        let dataOffset = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        
        guard dataOffset + entry.compressedSize <= data.count else {
            throw ImportValidatorError.invalidPackageStructure("ZIP entry data out of bounds")
        }
        
        let compressedData = data.subdata(in: dataOffset..<(dataOffset + entry.compressedSize))
        
        if entry.compressionMethod == 0 {
            // Stored (no compression)
            return compressedData
        } else if entry.compressionMethod == 8 {
            // Deflate (raw deflate, not zlib)
            return try compressedData.inflateRawDeflate(uncompressedSize: entry.uncompressedSize)
        } else {
            throw ImportValidatorError.invalidPackageStructure("Unsupported compression method: \(entry.compressionMethod)")
        }
    }
}

private struct ZipEntry {
    let path: String
    let type: EntryType
    let compressedSize: Int
    let uncompressedSize: Int
    let compressionMethod: UInt16
    let localHeaderOffset: Int
    let nextCentralDirOffset: Int
    
    enum EntryType {
        case file
        case directory
    }
    
    static func parse(from data: Data, at offset: Int) -> ZipEntry? {
        guard offset + 46 <= data.count else { return nil }
        
        // Verify central directory header signature (0x02014b50)
        let signature = data.uint32(at: offset)
        guard signature == 0x02014b50 else { return nil }
        
        let compressionMethod = data.uint16(at: offset + 10)
        let compressedSize = Int(data.uint32(at: offset + 20))
        let uncompressedSize = Int(data.uint32(at: offset + 24))
        let fileNameLength = Int(data.uint16(at: offset + 28))
        let extraFieldLength = Int(data.uint16(at: offset + 30))
        let commentLength = Int(data.uint16(at: offset + 32))
        let localHeaderOffset = Int(data.uint32(at: offset + 42))
        
        guard offset + 46 + fileNameLength <= data.count else { return nil }
        
        let pathData = data.subdata(in: (offset + 46)..<(offset + 46 + fileNameLength))
        guard let path = String(data: pathData, encoding: .utf8) else { return nil }
        
        let type: EntryType = path.hasSuffix("/") ? .directory : .file
        let nextOffset = offset + 46 + fileNameLength + extraFieldLength + commentLength
        
        return ZipEntry(
            path: path,
            type: type,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            compressionMethod: compressionMethod,
            localHeaderOffset: localHeaderOffset,
            nextCentralDirOffset: nextOffset
        )
    }
}

// Data extensions for ZIP parsing and decompression
private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    
    func uint32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) |
               (UInt32(self[offset + 1]) << 8) |
               (UInt32(self[offset + 2]) << 16) |
               (UInt32(self[offset + 3]) << 24)
    }
    
    func inflateRawDeflate(uncompressedSize: Int) throws -> Data {
        // Use Compression framework with raw deflate
        return try self.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> Data in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                throw ImportValidatorError.invalidPackageStructure("Could not access compressed data")
            }
            
            let sourceBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            let sourceSize = self.count
            
            // Allocate output buffer from uncompressedSize (with small floor for safety)
            let bufferSize = Swift.max(uncompressedSize, 1024)
            var outputData = Data(count: bufferSize)
            var outputSize = outputData.count
            
            let result = outputData.withUnsafeMutableBytes { outputBuffer -> compression_status in
                guard let outputBaseAddress = outputBuffer.baseAddress else {
                    return COMPRESSION_STATUS_ERROR
                }
                
                let decompressedSize = compression_decode_buffer(
                    outputBaseAddress.assumingMemoryBound(to: UInt8.self),
                    outputSize,
                    sourceBuffer,
                    sourceSize,
                    nil,
                    COMPRESSION_ZLIB // Raw deflate in iOS uses COMPRESSION_ZLIB
                )
                
                if decompressedSize == 0 {
                    return COMPRESSION_STATUS_ERROR
                }
                
                outputSize = decompressedSize
                return COMPRESSION_STATUS_OK
            }
            
            if result == COMPRESSION_STATUS_ERROR {
                throw ImportValidatorError.invalidPackageStructure("Failed to decompress ZIP entry")
            }
            
            return outputData.prefix(outputSize)
        }
    }
}
