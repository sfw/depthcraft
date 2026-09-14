import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: CourseStore
    @EnvironmentObject private var orchestrator: GenerationOrchestrator
    @State private var navigationPath: [NavigationDestination] = []
    @State private var showingLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            // Background generation status banner
            // Pushes content down when visible (no overlay)
            // Hide banner when on Generate page itself (no duplicate chrome)
            if isGenerationActive && !isOnGeneratePage {
                GenerationStatusBanner(orchestrator: orchestrator, navigationPath: $navigationPath)
            }
            
            NavigationStack(path: $navigationPath) {
                Group {
                    if store.isLoading && store.course == nil {
                        ProgressView("Opening course…")
                    } else if showingLibrary && store.availablePackages.count >= 2 {
                        LibraryView(onSelectCourse: {
                            showingLibrary = false
                        })
                    } else {
                        CourseHomeView()
                            .toolbar {
                                if store.availablePackages.count >= 2 {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Library") {
                                            showingLibrary = true
                                        }
                                    }
                                }
                            }
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .unit(let unitId):
                        UnitView(unitId: unitId)
                    case .lesson(let unitId, let lessonId):
                        LessonPlayerView(unitId: unitId, lessonId: lessonId, navigationPath: $navigationPath)
                    case .generation:
                        GenerationView()
                    }
                }
            }
            .environment(\.navigationPath, $navigationPath)
            .onAppear {
                if store.availablePackages.count >= 2 && store.course == nil {
                    showingLibrary = true
                }
            }
            .onChange(of: store.availablePackages.count) { oldCount, newCount in
                if newCount >= 2 && store.course == nil {
                    showingLibrary = true
                } else if newCount < 2 {
                    showingLibrary = false
                }
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
}

/// Banner shown at top of screen when generation is active
struct GenerationStatusBanner: View {
    @ObservedObject var orchestrator: GenerationOrchestrator
    @Binding var navigationPath: [NavigationDestination]
    
    var body: some View {
        Button {
            navigationPath.append(.generation)
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
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}
