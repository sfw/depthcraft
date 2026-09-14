import SwiftUI
import UniformTypeIdentifiers

struct GenerationTimingLogDetailView: View {
    let log: GenerationTimingLog
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    
    var body: some View {
        List {
            summarySection
            stageTimingsSection
        }
        .navigationTitle("Timing Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        exportAsJSON()
                    } label: {
                        Label("Export as JSON", systemImage: "doc.text")
                    }
                    
                    Button {
                        exportAsMarkdown()
                    } label: {
                        Label("Export as Markdown", systemImage: "doc.richtext")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if !shareItems.isEmpty {
                ShareSheet(items: shareItems)
            }
        }
    }
    
    private var summarySection: some View {
        Section("Summary") {
            LabeledContent("Run ID", value: log.runId)
            LabeledContent("Topic", value: log.topic)
            LabeledContent("Started", value: formatDate(log.startedAt))
            
            if let completedAt = log.completedAt {
                LabeledContent("Completed", value: formatDate(completedAt))
                LabeledContent("Total Duration", value: log.totalDurationFormatted)
            } else {
                LabeledContent("Status", value: "In progress")
            }
            
            LabeledContent("Stages", value: "\(log.entries.count)")
        }
    }
    
    private var stageTimingsSection: some View {
        Section("Stage Timings") {
            if log.entries.isEmpty {
                Text("No timing entries recorded")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.entries) { entry in
                    NavigationLink {
                        TimingEntryDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.stage.displayName)
                                    .font(.headline)
                                
                                Spacer()
                                
                                if let duration = entry.durationMs {
                                    Text(formatDuration(duration))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            HStack {
                                if let lessonId = entry.lessonId {
                                    Text(lessonId)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                statusBadge(entry.status)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private func statusBadge(_ status: TimingStatus) -> some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .cornerRadius(4)
    }
    
    private func statusColor(_ status: TimingStatus) -> Color {
        switch status {
        case .running: return .blue
        case .ok: return .green
        case .fail: return .red
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func exportAsJSON() {
        guard let jsonString = log.exportAsJSON() else { return }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-log-\(log.runId).json")
        
        do {
            try jsonString.write(to: tempURL, atomically: true, encoding: .utf8)
            shareItems = [tempURL]
            showingShareSheet = true
        } catch {
            print("Failed to export JSON: \(error)")
        }
    }
    
    private func exportAsMarkdown() {
        let markdown = log.exportAsMarkdown()
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-log-\(log.runId).md")
        
        do {
            try markdown.write(to: tempURL, atomically: true, encoding: .utf8)
            shareItems = [tempURL]
            showingShareSheet = true
        } catch {
            print("Failed to export Markdown: \(error)")
        }
    }
}

struct TimingEntryDetailView: View {
    let entry: GenerationTimingEntry
    
    var body: some View {
        List {
            Section("Stage") {
                LabeledContent("Stage", value: entry.stage.displayName)
                
                if let lessonId = entry.lessonId {
                    LabeledContent("Lesson ID", value: lessonId)
                }
                
                LabeledContent("Status", value: entry.status.displayName)
            }
            
            Section("Timing") {
                LabeledContent("Started", value: formatDate(entry.startedAt))
                
                if let endedAt = entry.endedAt {
                    LabeledContent("Ended", value: formatDate(endedAt))
                }
                
                if let duration = entry.durationMs {
                    LabeledContent("Duration", value: formatDuration(duration))
                }
            }
            
            if entry.provider != nil || entry.model != nil {
                Section("Model") {
                    if let provider = entry.provider {
                        LabeledContent("Provider", value: provider)
                    }
                    
                    if let model = entry.model {
                        LabeledContent("Model", value: model)
                    }
                    
                    if let maxTokens = entry.maxTokens {
                        LabeledContent("Max Tokens", value: "\(maxTokens)")
                    }
                    
                    if let tokensUsed = entry.tokensUsed {
                        LabeledContent("Tokens Used", value: "\(tokensUsed)")
                    }
                }
            }
            
            if let error = entry.error {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Entry Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
