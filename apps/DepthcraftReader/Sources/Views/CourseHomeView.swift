import SwiftUI

struct CourseHomeView: View {
    @EnvironmentObject private var store: CourseStore
    @Environment(\.navigationPath) private var navigationPath
    @State private var showingMoreMenu = false
    @State private var showingImporter = false

    var body: some View {
        List {
            if let course = store.course {
                // Cover band: title, subtitle, colophon
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        // Restrained home brand mark
                        Image("HomeMark")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 28)
                            .accessibilityHidden(true)
                            .padding(.top, 16)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(course.manifest.title)
                                .font(.system(.title, design: .serif, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if course.manifest.title.localizedCaseInsensitiveCompare(course.manifest.topic) != .orderedSame {
                                Text(course.manifest.topic)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // Colophon: lesson count · BYOK
                        let totalLessons = course.curriculum.lessons.count
                        Text("\(totalLessons) lessons · BYOK")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        // Continue button (teal accent)
                        if let resume = store.resumeTarget(),
                           let lesson = course.curriculum.lessons[resume.lessonId] {
                            Button {
                                navigationPath.wrappedValue.append(.lesson(unitId: resume.unitId, lessonId: resume.lessonId))
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Continue")
                                        .font(.subheadline.weight(.medium))
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(lesson.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color(.systemGroupedBackground))
                
                // Spine: numbered units (clean TOC)
                Section {
                    ForEach(store.orderedUnits()) { unit in
                        NavigationLink(value: NavigationDestination.unit(unitId: unit.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                // Unit number
                                Text("\(unit.order)")
                                    .font(.system(.callout, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 20, alignment: .trailing)
                                
                                // Current unit marker (teal accent bar)
                                if store.progress?.lastUnitId == unit.id {
                                    Rectangle()
                                        .fill(Color.teal)
                                        .frame(width: 2, height: 16)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.title)
                                        .font(.body)
                                        .foregroundStyle(store.progress?.units[unit.id]?.completed == true ? .secondary : .primary)
                                    
                                    let lessons = store.lessons(for: unit)
                                    let completed = lessons.filter { store.progress?.lessons[$0.id]?.completed == true }.count
                                    Text("\(completed) of \(lessons.count)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                } header: {
                    Text("Contents")
                        .textCase(nil)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                
                // Notes section (highlighted passages)
                let allHighlights = store.allHighlights()
                if !allHighlights.isEmpty {
                    Section {
                        ForEach(allHighlights.prefix(5)) { highlight in
                            if let lesson = course.curriculum.lessons[highlight.lessonId] {
                                NavigationLink(value: NavigationDestination.lesson(unitId: highlight.unitId, lessonId: highlight.lessonId)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(highlight.text)
                                            .font(.body)
                                            .lineLimit(2)
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 8) {
                                            Text(lesson.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            Text("·")
                                                .foregroundStyle(.tertiary)
                                            
                                            Text(timeAgo(from: highlight.createdAt))
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        
                        if allHighlights.count > 5 {
                            Button {
                                // TODO: Navigate to full notes view
                            } label: {
                                Text("See all \(allHighlights.count) notes")
                                    .font(.subheadline)
                                    .foregroundStyle(.teal)
                            }
                        }
                    } header: {
                        Text("Notes")
                            .textCase(nil)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if store.course == nil && !store.isLoading {
                VStack(spacing: 20) {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // Restrained home brand mark + wordmark
                        HStack(spacing: 10) {
                            Image("HomeMark")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 28)
                                .accessibilityHidden(true)
                            
                            Text("Depthcraft")
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundStyle(Color(hex: "#1C1917"))
                        }
                        
                        Text("No Course")
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .padding(.top, 8)
                        
                        Text("Set API keys in Settings, then Generate")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 12) {
                        NavigationLink {
                            GenerationView()
                        } label: {
                            Text("Generate")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .controlSize(.regular)
                        
                        Button {
                            showingImporter = true
                        } label: {
                            Text("Import")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMoreMenu = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingMoreMenu) {
            NavigationStack {
                MoreMenuView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingMoreMenu = false
                            }
                        }
                    }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.init(filenameExtension: "depthcraft")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(sourceURL.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                store.refreshAvailablePackages()
                store.loadPackage(from: destinationURL)
            } catch {
                print("Import error: \(error)")
            }
        case .failure(let error):
            print("File importer error: \(error)")
        }
    }
    
    private func timeAgo(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return "recently" }
        
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            let weeks = Int(interval / 604800)
            return "\(weeks)w ago"
        }
    }
}
