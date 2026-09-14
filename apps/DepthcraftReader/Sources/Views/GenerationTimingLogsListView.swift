import SwiftUI

struct GenerationTimingLogsListView: View {
    @StateObject private var logger = GenerationTimingLogger()
    @State private var logs: [GenerationTimingLog] = []
    @State private var showingDeleteAlert = false
    @State private var logToDelete: GenerationTimingLog?
    
    var body: some View {
        List {
            if logs.isEmpty {
                ContentUnavailableView(
                    "No Timing Logs",
                    systemImage: "clock",
                    description: Text("Timing logs from generation runs will appear here")
                )
            } else {
                ForEach(logs) { log in
                    NavigationLink {
                        GenerationTimingLogDetailView(log: log)
                    } label: {
                        LogRowView(log: log)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            logToDelete = log
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Timing Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !logs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        loadLogs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            loadLogs()
        }
        .alert("Delete Log", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                logToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let log = logToDelete {
                    deleteLog(log)
                }
            }
        } message: {
            Text("Are you sure you want to delete this timing log?")
        }
    }
    
    private func loadLogs() {
        logs = logger.listAllLogs()
    }
    
    private func deleteLog(_ log: GenerationTimingLog) {
        logger.deleteLog(runId: log.runId)
        loadLogs()
        logToDelete = nil
    }
}

struct LogRowView: View {
    let log: GenerationTimingLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(log.topic)
                .font(.headline)
                .lineLimit(2)
            
            HStack {
                Text(formatDate(log.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if log.isComplete {
                    Text(log.totalDurationFormatted)
                        .font(.caption)
                        .foregroundStyle(.teal)
                } else {
                    Text("In progress")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            HStack {
                Text("\(log.entries.count) stages")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                let okCount = log.entries.filter { $0.status == .ok }.count
                let failCount = log.entries.filter { $0.status == .fail }.count
                
                if okCount > 0 {
                    Label("\(okCount)", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                
                if failCount > 0 {
                    Label("\(failCount)", systemImage: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
