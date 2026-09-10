import SwiftUI

struct PackageSwitcherView: View {
    @EnvironmentObject private var store: CourseStore
    
    var body: some View {
        List {
            Section {
                Text("Switch between available course packages. Progress is tracked separately per package.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Available Packages")
            }
            
            if let currentCourse = store.course {
                Section("Current") {
                    packageRow(
                        title: currentCourse.manifest.title,
                        packageId: currentCourse.manifest.packageId,
                        url: currentCourse.rootURL,
                        isCurrent: true
                    )
                }
            }
            
            Section("Generated Packages") {
                if store.availablePackages.isEmpty {
                    Text("No generated packages found in Documents.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.availablePackages, id: \.path) { url in
                        if store.course?.rootURL.path != url.path {
                            packageRowFromURL(url: url)
                        }
                    }
                }
            }
        }
        .navigationTitle("Switch Package")
        .onAppear {
            store.refreshAvailablePackages()
        }
    }
    
    private func packageRow(title: String, packageId: String, url: URL, isCurrent: Bool) -> some View {
        Button {
            if !isCurrent {
                store.loadPackage(from: url)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isCurrent ? .primary : .primary)
                    
                    Text(packageId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                }
            }
        }
        .disabled(isCurrent)
    }
    
    private func packageRowFromURL(url: URL) -> some View {
        Button {
            store.loadPackage(from: url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.headline)
                
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
