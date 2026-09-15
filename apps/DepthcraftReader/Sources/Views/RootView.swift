import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: CourseStore
    @EnvironmentObject private var orchestrator: GenerationOrchestrator
    @State private var navigationPath: [NavigationDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            if store.isLoading && store.course == nil {
                ProgressView("Opening course…")
            } else {
                LibraryView()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .courseHome:
                    CourseHomeView()
                case .unit(let unitId):
                    UnitView(unitId: unitId)
                case .lesson(let unitId, let lessonId):
                    LessonPlayerView(unitId: unitId, lessonId: lessonId, navigationPath: $navigationPath)
                case .generation(let extendFromPackageURL):
                    if let packageURL = extendFromPackageURL,
                       let course = loadCourseForExtend(from: packageURL) {
                        GenerationView(extendFromCourse: course)
                    } else {
                        GenerationView()
                    }
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // Banner pushes content down when visible (no overlay)
                // Hide banner when on Generate page itself (no duplicate chrome)
                if isGenerationActive && !isOnGeneratePage {
                    GenerationStatusBanner(orchestrator: orchestrator, navigationPath: $navigationPath)
                }
            }
        }
        .environment(\.navigationPath, $navigationPath)
        .onAppear {
            // Navigate to course home if only one package and it's loaded
            if store.availablePackages.count == 1 && store.course != nil {
                navigationPath.append(.courseHome)
            }
        }
        .onChange(of: store.availablePackages.count) { oldCount, newCount in
            // Navigate to course home if we just loaded a single course
            if newCount == 1 && store.course != nil && navigationPath.isEmpty {
                navigationPath.append(.courseHome)
            }
        }
        .alert("Course Updated", isPresented: $store.showUpgradeDialog) {
            Button("Apply Update") {
                store.confirmPackageUpgrade()
            }
            Button("Cancel", role: .cancel) {
                store.cancelPackageUpgrade()
            }
        } message: {
            if let pending = store.pendingPackageUpgrade,
               let current = store.course {
                Text("A newer version (v\(pending.manifest.contentVersion)) of \"\(pending.manifest.title)\" is available. Your progress for existing lessons will be preserved, and new content will be added.\n\nCurrent: v\(current.manifest.contentVersion)")
            }
        }
    }
    
    private var isGenerationActive: Bool {
        switch orchestrator.progress.phase {
        case .planning, .writingLessons, .writingQuizzes, .writingDemos, .packaging:
            return true
        default:
            return false
        }
    }
    
    private var isOnGeneratePage: Bool {
        navigationPath.contains(where: { destination in
            if case .generation = destination {
                return true
            }
            return false
        })
    }
    
    private func loadCourseForExtend(from packageURL: URL) -> LoadedCourse? {
        // Load the course synchronously for extend
        // This is the same course already loaded in store, just need to pass it
        if let currentCourse = store.course, currentCourse.rootURL == packageURL {
            return currentCourse
        }
        return nil
    }
}

/// Banner shown at top of screen when generation is active
struct GenerationStatusBanner: View {
    @ObservedObject var orchestrator: GenerationOrchestrator
    @Binding var navigationPath: [NavigationDestination]
    
    var body: some View {
        Button {
            // Don't append if already on Generate page
            let alreadyOnGeneratePage = navigationPath.contains(where: { destination in
                if case .generation = destination {
                    return true
                }
                return false
            })
            
            if !alreadyOnGeneratePage {
                navigationPath.append(.generation(extendFromPackageURL: nil))
            }
        } label: {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generating Course")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 4) {
                        Text("\(orchestrator.progress.completedItems)/\(orchestrator.progress.totalItems)")
                            .font(.caption2)
                        
                        if orchestrator.progress.inProgressCount > 0 {
                            Text("·")
                            Text("\(orchestrator.progress.inProgressCount) running")
                                .font(.caption2)
                        }
                    }
                    .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.teal.opacity(0.15))
            .overlay(
                Rectangle()
                    .fill(.teal)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
    }
}
