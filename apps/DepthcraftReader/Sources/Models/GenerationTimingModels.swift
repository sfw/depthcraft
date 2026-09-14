import Foundation

// MARK: - Generation Timing Models

/// Represents a single stage or operation in the generation pipeline
struct GenerationTimingEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let stage: GenerationStage
    let lessonId: String?
    let startedAt: Date
    var endedAt: Date?
    var status: TimingStatus
    var error: String?
    let provider: String?
    let model: String?
    let maxTokens: Int?
    var tokensUsed: Int?
    var durationMs: Int?
    var finishReason: String?
    var requestCharCount: Int?
    var responseCharCount: Int?
    
    var computedDurationMs: Int? {
        guard let endedAt = endedAt else { return nil }
        return Int((endedAt.timeIntervalSince(startedAt)) * 1000)
    }
    
    var effectiveDurationMs: Int? {
        durationMs ?? computedDurationMs
    }
    
    var isComplete: Bool {
        endedAt != nil
    }
    
    init(
        id: UUID = UUID(),
        stage: GenerationStage,
        lessonId: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: TimingStatus = .running,
        error: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        maxTokens: Int? = nil,
        tokensUsed: Int? = nil,
        durationMs: Int? = nil,
        finishReason: String? = nil,
        requestCharCount: Int? = nil,
        responseCharCount: Int? = nil
    ) {
        self.id = id
        self.stage = stage
        self.lessonId = lessonId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.error = error
        self.provider = provider
        self.model = model
        self.maxTokens = maxTokens
        self.tokensUsed = tokensUsed
        self.durationMs = durationMs
        self.finishReason = finishReason
        self.requestCharCount = requestCharCount
        self.responseCharCount = responseCharCount
    }
}

enum GenerationStage: String, Codable, CaseIterable {
    case planner = "planner"
    case lessonWrite = "lesson-write"
    case complexity = "complexity"
    case quiz = "quiz"
    case demo = "demo"
    case packager = "packager"
    case phaseTransition = "phase-transition"
    case totalRun = "total-run"
    
    var displayName: String {
        switch self {
        case .planner: return "Planner"
        case .lessonWrite: return "Lesson"
        case .complexity: return "Complexity"
        case .quiz: return "Quiz"
        case .demo: return "Demo"
        case .packager: return "Packager"
        case .phaseTransition: return "Phase Transition"
        case .totalRun: return "Total Run"
        }
    }
}

enum TimingStatus: String, Codable {
    case running = "running"
    case ok = "ok"
    case fail = "fail"
    
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .ok: return "OK"
        case .fail: return "Failed"
        }
    }
}

/// Complete timing log for a generation run
struct GenerationTimingLog: Codable, Identifiable {
    let id: UUID
    let runId: String
    let topic: String
    let startedAt: Date
    var completedAt: Date?
    var entries: [GenerationTimingEntry]
    var totalDurationMs: Int?
    
    var isComplete: Bool {
        completedAt != nil
    }
    
    var computedTotalDurationMs: Int? {
        guard let completedAt = completedAt else { return nil }
        return Int((completedAt.timeIntervalSince(startedAt)) * 1000)
    }
    
    var effectiveTotalDurationMs: Int? {
        totalDurationMs ?? computedTotalDurationMs
    }
    
    var totalDurationFormatted: String {
        guard let ms = effectiveTotalDurationMs else { return "In progress" }
        return formatDuration(ms)
    }
    
    init(
        id: UUID = UUID(),
        runId: String,
        topic: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        entries: [GenerationTimingEntry] = [],
        totalDurationMs: Int? = nil
    ) {
        self.id = id
        self.runId = runId
        self.topic = topic
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.entries = entries
        self.totalDurationMs = totalDurationMs
    }
}

// MARK: - Formatting Helpers

func formatDuration(_ milliseconds: Int) -> String {
    let totalSeconds = Double(milliseconds) / 1000.0
    
    if totalSeconds < 60 {
        return String(format: "%.1fs", totalSeconds)
    } else if totalSeconds < 3600 {
        let minutes = Int(totalSeconds / 60)
        let seconds = Int(totalSeconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    } else {
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }
}

func formatISO8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

// MARK: - Export Formats

extension GenerationTimingLog {
    func exportAsJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    func exportAsMarkdown() -> String {
        var md = "# Generation Timing Log\n\n"
        md += "**Topic:** \(topic)\n\n"
        md += "**Run ID:** `\(runId)`\n\n"
        md += "**Started:** \(formatISO8601(startedAt))\n\n"
        
        if let completedAt = completedAt {
            md += "**Completed:** \(formatISO8601(completedAt))\n\n"
            md += "**Total Duration:** \(totalDurationFormatted)\n\n"
        } else {
            md += "**Status:** In progress\n\n"
        }
        
        md += "---\n\n"
        md += "## Stage Timings\n\n"
        
        if entries.isEmpty {
            md += "*No timing entries recorded*\n\n"
        } else {
            md += "| Stage | Lesson ID | Duration | Status | Provider | Model |\n"
            md += "|-------|-----------|----------|--------|----------|-------|\n"
            
            for entry in entries {
                let lessonIdStr = entry.lessonId ?? "–"
                let durationStr = entry.effectiveDurationMs.map { formatDuration($0) } ?? "–"
                let providerStr = entry.provider ?? "–"
                let modelStr = entry.model ?? "–"
                
                md += "| \(entry.stage.displayName) | \(lessonIdStr) | \(durationStr) | \(entry.status.displayName) | \(providerStr) | \(modelStr) |\n"
            }
            
            md += "\n"
        }
        
        md += "## Details\n\n"
        
        for entry in entries {
            md += "### \(entry.stage.displayName)"
            if let lessonId = entry.lessonId {
                md += " - `\(lessonId)`"
            }
            md += "\n\n"
            
            md += "- **Started:** \(formatISO8601(entry.startedAt))\n"
            
            if let endedAt = entry.endedAt {
                md += "- **Ended:** \(formatISO8601(endedAt))\n"
            }
            
            if let duration = entry.effectiveDurationMs {
                md += "- **Duration:** \(formatDuration(duration))\n"
            }
            
            md += "- **Status:** \(entry.status.displayName)\n"
            
            if let provider = entry.provider {
                md += "- **Provider:** \(provider)\n"
            }
            
            if let model = entry.model {
                md += "- **Model:** \(model)\n"
            }
            
            if let maxTokens = entry.maxTokens {
                md += "- **Max Tokens:** \(maxTokens)\n"
            }
            
            if let tokensUsed = entry.tokensUsed {
                md += "- **Tokens Used:** \(tokensUsed)\n"
            }
            
            if let finishReason = entry.finishReason {
                md += "- **Finish Reason:** \(finishReason)\n"
            }
            
            if let requestCharCount = entry.requestCharCount {
                md += "- **Request Char Count:** \(requestCharCount)\n"
            }
            
            if let responseCharCount = entry.responseCharCount {
                md += "- **Response Char Count:** \(responseCharCount)\n"
            }
            
            if let error = entry.error {
                md += "- **Error:** \(error)\n"
            }
            
            md += "\n"
        }
        
        return md
    }
}
