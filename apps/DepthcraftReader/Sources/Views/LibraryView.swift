import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CourseStore
    @State private var packages: [LibraryPackageMetadata] = []
    @State private var showingImporter = false
    @State private var importError: ImportValidatorError?
    @State private var showingImportError = false
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
                        GridItem(.adaptive(minimum: 160, maximum: 300), spacing: 22)
                    ],
                    spacing: 22
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
        .background(Color(hex: "#F5F0E6"))
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
            allowedContentTypes: [.init(filenameExtension: "depthcraft")].compactMap { $0 },
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
                // Validate the imported package before copying
                try ImportValidator.validateImportedPackage(at: sourceURL)
                
                let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destinationURL = documentsURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                
                store.refreshAvailablePackages()
                store.loadPackage(from: destinationURL)
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
                        .frame(width: 2.5)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(package.title)
                        .font(.system(size: 21, weight: .semibold, design: .default))
                        .foregroundStyle(Color(hex: "#1C1917"))
                        .lineLimit(3)
                        .minimumScaleFactor(1.0)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer()
                    
                    Text(packageMeta)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#1C1917").opacity(0.6))
                }
                .padding(19)
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
