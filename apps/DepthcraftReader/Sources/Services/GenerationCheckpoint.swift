import Foundation

/// Checkpoint state that persists across app lifecycle events and process death
/// Saved to disk incrementally during generation for crash recovery
struct GenerationCheckpoint: Codable {
    let schemaVersion: String = "1.0"
    
    // Request metadata
    let topic: String
    let locale: String
    let knowledgeLevel: Int
    let depthLevel: Int
    let generateUnitIds: [String]?
    let extendFromPackageURL: URL?
    
    // Model configurations
    let plannerProvider: String
    let plannerModel: String
    let plannerCustomEndpointId: String?  // UUID string for custom endpoint
    let plannerCustomBaseURL: String?     // Base URL for custom endpoint
    
    let lessonWriterProvider: String
    let lessonWriterModel: String
    let lessonWriterCustomEndpointId: String?
    let lessonWriterCustomBaseURL: String?
    
    let quizWriterProvider: String
    let quizWriterModel: String
    let quizWriterCustomEndpointId: String?
    let quizWriterCustomBaseURL: String?
    
    let demoWriterProvider: String
    let demoWriterModel: String
    let demoWriterCustomEndpointId: String?
    let demoWriterCustomBaseURL: String?
    
    // Generation state
    let phase: String
    let curriculum: Curriculum?
    let completedItems: Int
    let totalItems: Int
    
    // Partial progress
    let partialLessons: [String: PartialLessonData]
    let partialQuizzes: [String: QuizDocument]
    let partialDemos: [String: DemoWriterOutput]
    
    // Timing
    let startedAt: Date
    let lastUpdatedAt: Date
    
    struct PartialLessonData: Codable {
        let markdown: String
        let meta: LessonMeta
    }
}

/// Manages checkpoint persistence and restoration for generation
/// Survives process death, app backgrounding, and crashes
@MainActor
class CheckpointManager {
    private let checkpointURL: URL
    private let fileManager = FileManager.default
    
    init() {
        // Store checkpoint in Application Support (survives app updates)
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let checkpointDir = appSupport.appendingPathComponent("Checkpoints")
        
        // Ensure directory exists
        try? fileManager.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
        
        checkpointURL = checkpointDir.appendingPathComponent("generation-checkpoint.json")
    }
    
    /// Save checkpoint to disk (non-throwing for incremental saves during generation)
    func saveCheckpoint(_ checkpoint: GenerationCheckpoint) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(checkpoint)
            try data.write(to: checkpointURL, options: .atomic)
            print("✓ Checkpoint saved: \(checkpoint.phase), \(checkpoint.completedItems)/\(checkpoint.totalItems)")
        } catch {
            print("⚠️ Failed to save checkpoint: \(error)")
        }
    }
    
    /// Load checkpoint from disk, returns nil if none exists or invalid
    func loadCheckpoint() -> GenerationCheckpoint? {
        guard fileManager.fileExists(atPath: checkpointURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: checkpointURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let checkpoint = try decoder.decode(GenerationCheckpoint.self, from: data)
            
            // Validate checkpoint isn't too old (older than 7 days = stale)
            let age = Date().timeIntervalSince(checkpoint.lastUpdatedAt)
            if age > 7 * 24 * 60 * 60 {
                print("⚠️ Checkpoint too old (age: \(Int(age/3600))h), ignoring")
                clearCheckpoint()
                return nil
            }
            
            print("✓ Checkpoint loaded: \(checkpoint.phase), \(checkpoint.completedItems)/\(checkpoint.totalItems)")
            return checkpoint
        } catch {
            print("⚠️ Failed to load checkpoint: \(error)")
            clearCheckpoint() // Corrupted checkpoint, clear it
            return nil
        }
    }
    
    /// Clear checkpoint from disk (call on successful completion or user reset)
    func clearCheckpoint() {
        try? fileManager.removeItem(at: checkpointURL)
        print("✓ Checkpoint cleared")
    }
    
    /// Check if a checkpoint exists
    func hasCheckpoint() -> Bool {
        fileManager.fileExists(atPath: checkpointURL.path)
    }
}
