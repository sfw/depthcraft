import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CourseStore
    @State private var packages: [LibraryPackageMetadata] = []
    @State private var showingImporter = false
    let onSelectCourse: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
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
                }
                
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
                .padding(.top, 12)
            }
            .padding(.vertical, 16)
        }
        .background(Color(hex: "#F5F0E6"))
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
            
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(sourceURL.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                store.refreshAvailablePackages()
                store.loadPackage(from: destinationURL)
                onSelectCourse()
            } catch {
                print("Import error: \(error)")
            }
        case .failure(let error):
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
        VStack(alignment: .leading, spacing: 0) {
            if isMostRecent {
                Rectangle()
                    .fill(Color(hex: "#0D9488"))
                    .frame(height: 2.5)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(package.title)
                    .font(.system(size: 19, weight: .semibold, design: .default))
                    .foregroundStyle(Color(hex: "#1C1917"))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                Text(packageMeta)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#1C1917").opacity(0.6))
            }
            .padding(16)
        }
        .frame(width: 200, height: 260)
        .background(Color(hex: "#F5F0E6"))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(hex: "#E8E0D2"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var packageMeta: String {
        let lessonStr = "\(package.lessonCount) lesson\(package.lessonCount == 1 ? "" : "s")"
        if let lastOpened = package.lastOpenedAt {
            return "\(lessonStr) · \(formatLastOpened(lastOpened))"
        }
        return lessonStr
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

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
