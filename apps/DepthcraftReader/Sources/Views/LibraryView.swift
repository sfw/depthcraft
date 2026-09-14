import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CourseStore
    @State private var packages: [LibraryPackageMetadata] = []
    @State private var showingImporter = false
    @State private var importError: ImportValidatorError?
    @State private var showingImportError = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let onSelectCourse: () -> Void
    
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Library")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        
                        if let mostRecent = packages.first {
                            Button {
                                store.loadPackage(from: mostRecent.url)
                                onSelectCourse()
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Continue")
                                        .font(.subheadline.weight(.medium))
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(mostRecent.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Vertical shelf with LazyVGrid
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 18)
                        ],
                        spacing: 18
                    ) {
                        ForEach(packages) { package in
                            CourseShelfCover(
                                package: package,
                                isMostRecent: package.id == packages.first?.id
                            )
                            .onTapGesture {
                                store.loadPackage(from: package.url)
                                onSelectCourse()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Create")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            NavigationLink {
                                GenerationView()
                            } label: {
                                Label("Generate", systemImage: "sparkles")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            Button {
                                showingImporter = true
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                }
                .padding(.vertical, 16)
            }
            .background(Color(hex: "#EDE6D9"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .alert("Import Failed", isPresented: $showingImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = importError {
                    Text(error.userFriendlyDescription)
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
        .onAppear {
            refreshPackages()
        }
        .onChange(of: store.availablePackages) { _ in
            refreshPackages()
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
            
            do {
                let fileManager = FileManager.default
                var isDirectory: ObjCBool = false
                fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                
                let packageURL: URL
                
                if isDirectory.boolValue {
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
                onSelectCourse()
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
    
    private func refreshPackages() {
        packages = store.libraryPackages()
    }
}

struct CourseShelfCover: View {
    let package: LibraryPackageMetadata
    let isMostRecent: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width / 0.75
            
            HStack(spacing: 0) {
                if isMostRecent {
                    Rectangle()
                        .fill(Color(hex: "#0D9488"))
                        .frame(width: 3)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        WordBoundaryText(
                            text: package.title,
                            font: .custom("NewYorkMedium-Medium", size: 19),
                            fallbackFont: .system(size: 19, weight: .medium, design: .default),
                            color: Color(hex: "#1C1917").opacity(0.92),
                            lineSpacing: 4,
                            tracking: 0.3,
                            maxLines: 3,
                            maxWidth: width - (isMostRecent ? 3 : 0) - 36
                        )
                        
                        Text(packageMeta)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#1C1917").opacity(0.57))
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    
                    Spacer(minLength: 0)
                }
            }
            .frame(width: width, height: height)
            .background(Color(hex: "#F5F0E6"))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(hex: "#E8E0D2"), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .aspectRatio(0.75, contentMode: .fit)
    }
    
    private var packageMeta: String {
        let lessonStr = "\(package.lessonCount) lesson\(package.lessonCount == 1 ? "" : "s")"
        let lastOpenedStr = package.lastOpenedAt.map(formatLastOpened) ?? "Never opened"
        return "\(lessonStr) · \(lastOpenedStr)"
    }
    
    private func formatLastOpened(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
    }
}

struct WordBoundaryText: View {
    let text: String
    let font: Font
    let fallbackFont: Font?
    let color: Color
    let lineSpacing: CGFloat
    let tracking: CGFloat
    let maxLines: Int
    let maxWidth: CGFloat
    
    init(
        text: String,
        font: Font,
        fallbackFont: Font? = nil,
        color: Color,
        lineSpacing: CGFloat = 0,
        tracking: CGFloat = 0,
        maxLines: Int,
        maxWidth: CGFloat
    ) {
        self.text = text
        self.font = font
        self.fallbackFont = fallbackFont
        self.color = color
        self.lineSpacing = lineSpacing
        self.tracking = tracking
        self.maxLines = maxLines
        self.maxWidth = maxWidth
    }
    
    var body: some View {
        Text(truncatedText)
            .font(fontWithFallback)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .tracking(tracking)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var fontWithFallback: Font {
        // Try the primary font first, fall back if needed
        if let customName = extractCustomFontName(from: font),
           UIFont(name: customName, size: 19) != nil {
            return font
        }
        return fallbackFont ?? font
    }
    
    private func extractCustomFontName(from font: Font) -> String? {
        // Extract "NewYorkMedium-Medium" from custom font
        let mirror = Mirror(reflecting: font)
        for child in mirror.children {
            if let provider = child.value as? Any {
                let providerMirror = Mirror(reflecting: provider)
                for providerChild in providerMirror.children {
                    if let name = providerChild.value as? String {
                        return name
                    }
                }
            }
        }
        return nil
    }
    
    private var truncatedText: String {
        // Use New York Medium if available, otherwise SF Pro Display Medium
        let uiFont: UIFont
        if let nyFont = UIFont(name: "NewYorkMedium-Medium", size: 19) {
            uiFont = nyFont
        } else {
            uiFont = UIFont.systemFont(ofSize: 19, weight: .medium)
        }
        
        // Account for tracking in width calculation
        let trackingAdjustment = tracking * CGFloat(text.count) * 0.5
        let effectiveMaxWidth = maxWidth - trackingAdjustment
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .kern: tracking
        ]
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        
        var lines: [String] = []
        var currentLine = ""
        
        for word in words {
            let testLine = currentLine.isEmpty ? word : "\(currentLine) \(word)"
            let size = (testLine as NSString).size(withAttributes: attributes)
            
            if size.width > effectiveMaxWidth {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = word
                    
                    if lines.count >= maxLines {
                        break
                    }
                } else {
                    lines.append(word)
                    currentLine = ""
                    
                    if lines.count >= maxLines {
                        break
                    }
                }
            } else {
                currentLine = testLine
            }
        }
        
        if !currentLine.isEmpty && lines.count < maxLines {
            lines.append(currentLine)
        }
        
        if lines.count == maxLines && words.joined(separator: " ") != lines.joined(separator: " ") {
            if var lastLine = lines.last {
                let ellipsis = "…"
                let testString = "\(lastLine)\(ellipsis)"
                let size = (testString as NSString).size(withAttributes: attributes)
                
                while size.width > effectiveMaxWidth && !lastLine.isEmpty {
                    let lastWords = lastLine.split(separator: " ")
                    if lastWords.count > 1 {
                        lastLine = lastWords.dropLast().joined(separator: " ")
                    } else {
                        break
                    }
                }
                
                lines[lines.count - 1] = "\(lastLine)\(ellipsis)"
            }
        }
        
        return lines.joined(separator: "\n")
    }
}


