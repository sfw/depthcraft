import Foundation

/// Service for tracking and persisting generation timing data
@MainActor
class GenerationTimingLogger: ObservableObject {
    @Published private(set) var currentLog: GenerationTimingLog?
    private var activeEntries: [UUID: GenerationTimingEntry] = [:]
    
    private let fileManager = FileManager.default
    
    // MARK: - Run Management
    
    func startRun(topic: String) {
        let runId = UUID().uuidString
        currentLog = GenerationTimingLog(
            runId: runId,
            topic: topic,
            startedAt: Date()
        )
    }
    
    func completeRun() {
        guard var log = currentLog else { return }
        log.completedAt = Date()
        currentLog = log
        persistLog(log)
    }
    
    func failRun() {
        guard var log = currentLog else { return }
        log.completedAt = Date()
        currentLog = log
        persistLog(log)
    }
    
    func reset() {
        currentLog = nil
        activeEntries = [:]
    }
    
    // MARK: - Stage Timing
    
    @discardableResult
    func startStage(
        _ stage: GenerationStage,
        lessonId: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        maxTokens: Int? = nil
    ) -> UUID {
        guard var log = currentLog else {
            return UUID()
        }
        
        let entry = GenerationTimingEntry(
            stage: stage,
            lessonId: lessonId,
            startedAt: Date(),
            status: .running,
            provider: provider,
            model: model,
            maxTokens: maxTokens
        )
        
        activeEntries[entry.id] = entry
        log.entries.append(entry)
        currentLog = log
        
        return entry.id
    }
    
    func completeStage(
        _ entryId: UUID,
        tokensUsed: Int? = nil
    ) {
        guard var log = currentLog,
              let entryIndex = log.entries.firstIndex(where: { $0.id == entryId }),
              var entry = activeEntries[entryId] else {
            return
        }
        
        entry.endedAt = Date()
        entry.status = .ok
        entry.tokensUsed = tokensUsed
        
        log.entries[entryIndex] = entry
        activeEntries.removeValue(forKey: entryId)
        currentLog = log
        
        persistLog(log)
    }
    
    func failStage(
        _ entryId: UUID,
        error: String
    ) {
        guard var log = currentLog,
              let entryIndex = log.entries.firstIndex(where: { $0.id == entryId }),
              var entry = activeEntries[entryId] else {
            return
        }
        
        entry.endedAt = Date()
        entry.status = .fail
        entry.error = error
        
        log.entries[entryIndex] = entry
        activeEntries.removeValue(forKey: entryId)
        currentLog = log
        
        persistLog(log)
    }
    
    // MARK: - Convenience Wrappers
    
    func timeStage<T>(
        _ stage: GenerationStage,
        lessonId: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        maxTokens: Int? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        let entryId = startStage(
            stage,
            lessonId: lessonId,
            provider: provider,
            model: model,
            maxTokens: maxTokens
        )
        
        do {
            let result = try await operation()
            completeStage(entryId)
            return result
        } catch {
            failStage(entryId, error: error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Persistence
    
    private func getTimingLogsDirectory() -> URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let timingLogsDir = documentsURL.appendingPathComponent("TimingLogs")
        
        if !fileManager.fileExists(atPath: timingLogsDir.path) {
            try? fileManager.createDirectory(at: timingLogsDir, withIntermediateDirectories: true)
        }
        
        return timingLogsDir
    }
    
    private func persistLog(_ log: GenerationTimingLog) {
        guard let logsDir = getTimingLogsDirectory() else { return }
        
        let filename = "\(log.runId).json"
        let fileURL = logsDir.appendingPathComponent(filename)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(log) else { return }
        try? data.write(to: fileURL)
    }
    
    func loadLog(runId: String) -> GenerationTimingLog? {
        guard let logsDir = getTimingLogsDirectory() else { return nil }
        
        let filename = "\(runId).json"
        let fileURL = logsDir.appendingPathComponent(filename)
        
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(GenerationTimingLog.self, from: data)
    }
    
    func listAllLogs() -> [GenerationTimingLog] {
        guard let logsDir = getTimingLogsDirectory(),
              let files = try? fileManager.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> GenerationTimingLog? in
                guard let data = try? Data(contentsOf: url),
                      let log = try? decoder.decode(GenerationTimingLog.self, from: data) else {
                    return nil
                }
                return log
            }
            .sorted { $0.startedAt > $1.startedAt }
    }
    
    func deleteLog(runId: String) {
        guard let logsDir = getTimingLogsDirectory() else { return }
        
        let filename = "\(runId).json"
        let fileURL = logsDir.appendingPathComponent(filename)
        
        try? fileManager.removeItem(at: fileURL)
    }
}
