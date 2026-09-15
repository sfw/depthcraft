import SwiftUI

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct CourseHomeView: View {
    @EnvironmentObject private var store: CourseStore
    @Environment(\.navigationPath) private var navigationPath
    @State private var shareSheetItem: ShareItem?
    @State private var showingImporter = false
    @State private var exportError: String?
    @State private var showingExportError = false
    @State private var importError: ImportValidatorError?
    @State private var showingImportError = false
    @State private var showingRetryError = false
    @State private var retryError: String?

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
                        
                        // Course actions: twin light grey pills (Extend + Export)
                        HStack(spacing: 12) {
                            Button {
                                if let course = store.course {
                                    navigationPath.wrappedValue.append(.generation(extendFromPackageURL: course.rootURL))
                                }
                            } label: {
                                Label("Extend Course", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            Button {
                                exportCourse()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
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
                    
                    // Failed lessons section (if any)
                    let failedLessonsList = store.failedLessons()
                    if !failedLessonsList.isEmpty {
                        DisclosureGroup {
                            ForEach(failedLessonsList, id: \.lesson.id) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    // Stage icon: spinner if retrying, warning if failed/idle
                                    if let stage = store.retryingLessons[item.lesson.id] {
                                        if stage.isInProgress {
                                            ProgressView()
                                                .controlSize(.mini)
                                                .frame(minWidth: 20)
                                        } else if stage == .failed {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.red)
                                                .font(.caption)
                                                .frame(minWidth: 20, alignment: .trailing)
                                        } else if stage == .done {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                                .frame(minWidth: 20, alignment: .trailing)
                                        }
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                            .frame(minWidth: 20, alignment: .trailing)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.lesson.title)
                                            .font(.body)
                                        Text(item.unit.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    // Show stage chip if retrying, Retry button otherwise
                                    if let stage = store.retryingLessons[item.lesson.id] {
                                        stageChip(for: stage)
                                    } else {
                                        Button {
                                            retryLesson(item.lesson)
                                        } label: {
                                            Text("Retry")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(.teal)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 6)
                                .background(
                                    store.retryingLessons[item.lesson.id]?.isInProgress == true
                                        ? Color.teal.opacity(0.05)
                                        : Color.clear
                                )
                                .cornerRadius(6)
                            }
                        } label: {
                            HStack {
                                Text("Failed Lessons (\(failedLessonsList.count))")
                                    .font(.body)
                                    .foregroundStyle(.orange)
                            }
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
                        Button {
                            navigationPath.wrappedValue.append(.generation(extendFromPackageURL: nil))
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
        .sheet(item: $shareSheetItem) { item in
            PackageShareSheet(activityItems: [item.url])
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = exportError {
                Text(error)
            }
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = importError {
                Text(error.userFriendlyDescription)
            }
        }
        .alert("Retry Failed", isPresented: $showingRetryError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = retryError {
                Text(error)
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                .init(filenameExtension: "depthcraft"),
                .zip
            ].compactMap { $0 },

            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    navigationPath.wrappedValue.removeAll()
                } label: {
                    Image("HomeMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 28)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigationPath.wrappedValue.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
    
    // MARK: - Retry Stage UI Components
    
    private func stageChip(for stage: LessonStage) -> some View {
        Text(stage.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stageChipColor(for: stage))
            .foregroundStyle(stageChipTextColor(for: stage))
            .cornerRadius(4)
    }
    
    private func stageChipColor(for stage: LessonStage) -> Color {
        switch stage {
        case .queued:
            return Color.gray.opacity(0.2)
        case .writing, .quiz, .demo:
            return Color.teal.opacity(0.2)
        case .done:
            return Color.green.opacity(0.2)
        case .failed:
            return Color.red.opacity(0.2)
        }
    }
    
    private func stageChipTextColor(for stage: LessonStage) -> Color {
        switch stage {
        case .queued:
            return .secondary
        case .writing, .quiz, .demo:
            return .teal
        case .done:
            return .green
        case .failed:
            return .red
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
    
    private func exportCourse() {
        guard let course = store.course else { return }
        
        let sourceURL = course.rootURL
        let packageName = sourceURL.deletingPathExtension().lastPathComponent
        let tempDirectory = FileManager.default.temporaryDirectory
        let zipURL = tempDirectory.appendingPathComponent("\(packageName).depthcraft")
        
        do {
            // Remove existing temp file if present
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }
            
            // Create zip archive of the package directory
            try zipDirectory(at: sourceURL, to: zipURL)
            
            // Verify the zip was created successfully
            guard FileManager.default.fileExists(atPath: zipURL.path) else {
                throw NSError(domain: "ExportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "ZIP file was not created"])
            }
            
            // Only present share sheet after confirmed bytes on disk
            self.shareSheetItem = ShareItem(url: zipURL)
        } catch {
            exportError = "Failed to export course: \(error.localizedDescription)"
            showingExportError = true
        }
    }
    
    private func zipDirectory(at sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var zipCreated = false
        var copyError: NSError?
        
        coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordinatorError) { zipURL in
            do {
                // The coordinator creates a zip for us when using .forUploading
                try fileManager.copyItem(at: zipURL, to: destinationURL)
                zipCreated = true
            } catch {
                copyError = error as NSError
            }
        }
        
        // Check for errors from coordinate or copy
        if let error = coordinatorError ?? copyError {
            throw error
        }
        
        if !zipCreated {
            throw NSError(domain: "ExportError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
        }
    }
}

struct PackageShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Extension for import handling
extension CourseHomeView {
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
            
            do {
                let fileManager = FileManager.default
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                
                let packageURL: URL
                
                // BUGFIX: iOS may treat .depthcraft files as packages (directories) on device.
                // Use ZIP magic bytes check to determine actual file type.
                let isActuallyZipFile = isDirectory.boolValue && ImportValidator.isZipFile(at: sourceURL)
                
                if isDirectory.boolValue && !isActuallyZipFile {
                    // Already a directory package - validate and copy
                    try ImportValidator.validateImportedPackage(at: sourceURL)
                    
                    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    packageURL = documentsURL.appendingPathComponent(sourceURL.lastPathComponent)
                    
                    if fileManager.fileExists(atPath: packageURL.path) {
                        try fileManager.removeItem(at: packageURL)
                    }
                    try fileManager.copyItem(at: sourceURL, to: packageURL)
                    
                    // Strip progress.json - device-local ProgressStore is authoritative
                    let progressURL = packageURL.appendingPathComponent("progress.json")
                    if fileManager.fileExists(atPath: progressURL.path) {
                        try? fileManager.removeItem(at: progressURL)
                    }
                } else {
                    // It's a file (zip) - unzip with zip-slip protection, then validate
                    let tempDir = fileManager.temporaryDirectory
                    let tempExtractDir = tempDir.appendingPathComponent(UUID().uuidString)
                    try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
                    
                    // Unzip with zip-slip-safe extraction
                    try ImportValidator.unzipSafely(from: sourceURL, to: tempExtractDir)
                    
                    // Find the .depthcraft package directory in the extracted content
                    let extractedContents = try fileManager.contentsOfDirectory(at: tempExtractDir, includingPropertiesForKeys: nil)
                    let extractedPackage: URL
                    
                    // First try to find a .depthcraft child directory
                    if let depthcraftChild = extractedContents.first(where: { $0.lastPathComponent.hasSuffix(".depthcraft") }) {
                        extractedPackage = depthcraftChild
                    } else {
                        // Fallback: check if extract root itself contains manifest.json + curriculum.json (flattened zip)
                        let manifestURL = tempExtractDir.appendingPathComponent("manifest.json")
                        let curriculumURL = tempExtractDir.appendingPathComponent("curriculum.json")
                        
                        if fileManager.fileExists(atPath: manifestURL.path) && fileManager.fileExists(atPath: curriculumURL.path) {
                            // Extract root is the package - rename to .depthcraft
                            let packageName = sourceURL.deletingPathExtension().lastPathComponent
                            let renamedPackage = tempExtractDir.deletingLastPathComponent().appendingPathComponent("\(packageName).depthcraft")
                            try fileManager.moveItem(at: tempExtractDir, to: renamedPackage)
                            extractedPackage = renamedPackage
                        } else {
                            throw ImportValidatorError.invalidPackageStructure("No .depthcraft package found in zip")
                        }
                    }
                    
                    // Validate the extracted package
                    try ImportValidator.validateImportedPackage(at: extractedPackage)
                    
                    // Move to Documents
                    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    packageURL = documentsURL.appendingPathComponent(extractedPackage.lastPathComponent)
                    
                    if fileManager.fileExists(atPath: packageURL.path) {
                        try fileManager.removeItem(at: packageURL)
                    }
                    try fileManager.moveItem(at: extractedPackage, to: packageURL)
                    
                    // Clean up temp directory
                    try? fileManager.removeItem(at: tempExtractDir)
                }
                
                store.refreshAvailablePackages()
                store.loadPackage(from: packageURL)
            } catch let error as ImportValidatorError {
                importError = error
                showingImportError = true
                print("Import validation error: \(error.localizedDescription)")
            } catch {
                importError = ImportValidatorError.invalidPackageStructure("An unexpected error occurred during import")
                showingImportError = true
                print("Import error: \(error)")
            }
        case .failure(let error):
            importError = ImportValidatorError.invalidPackageStructure("File selection failed")
            showingImportError = true
            print("File importer error: \(error)")
        }
    }
    
    private func retryLesson(_ lesson: CurriculumLesson) {
        guard let course = store.course else { return }
        
        // Mark as retrying with writing stage
        store.updateRetryStage(lessonId: lesson.id, stage: .writing)
        
        Task { @MainActor in
            do {
                #if DEBUG
                print("📝 Starting retry for lesson: \(lesson.id) - \(lesson.title)")
                #endif
                
                let retryService = LessonRetryService()
                
                // Wire up stage callback
                retryService.onStageUpdate = { [weak store] stage in
                    store?.updateRetryStage(lessonId: lesson.id, stage: stage)
                }
                
                try await retryService.retryLesson(
                    lesson: lesson,
                    packageURL: course.rootURL,
                    manifest: course.manifest
                )
                
                #if DEBUG
                print("✅ Retry completed, reloading package")
                #endif
                
                // Mark as done
                store.updateRetryStage(lessonId: lesson.id, stage: .done)
                
                // Reload the package after successful retry
                store.reloadPackageInPlace(from: course.rootURL)
                
                // Clear retry state after a brief delay to show success
                try? await Task.sleep(for: .milliseconds(500))
                store.clearRetryStage(lessonId: lesson.id)
            } catch {
                #if DEBUG
                print("❌ Retry failed: \(error)")
                #endif
                
                // Mark as failed
                store.updateRetryStage(lessonId: lesson.id, stage: .failed)
                
                retryError = error.localizedDescription
                showingRetryError = true
                
                // Clear retry state after showing error
                try? await Task.sleep(for: .milliseconds(2000))
                store.clearRetryStage(lessonId: lesson.id)
            }
        }
    }
}
