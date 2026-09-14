import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: CourseStore
    @EnvironmentObject private var orchestrator: GenerationOrchestrator
    @State private var navigationPath: [NavigationDestination] = []
    @State private var showGenerationView = false

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack(path: $navigationPath) {
                Group {
                    if store.isLoading && store.course == nil {
                        ProgressView("Opening course…")
                    } else if shouldShowLibrary {
                        LibraryView()
                    } else {
                        CourseHomeView()
                    }
                }
                .navigationTitle(shouldShowLibrary ? "" : "Depthcraft")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .unit(let unitId):
                        UnitView(unitId: unitId)
                    case .lesson(let unitId, let lessonId):
                        LessonPlayerView(unitId: unitId, lessonId: lessonId, navigationPath: $navigationPath)
                    }
                }
            }
            .environment(\.navigationPath, $navigationPath)
            
            // Background generation status banner
            if isGenerationActive {
                GenerationStatusBanner(orchestrator: orchestrator, showGenerationView: $showGenerationView)
                    .padding(.top, 50)
            }
        }
        .sheet(isPresented: $showGenerationView) {
            NavigationStack {
                GenerationView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showGenerationView = false
                            }
                        }
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
    
    private var shouldShowLibrary: Bool {
        store.availablePackages.count >= 2
    }
}

/// Banner shown at top of screen when generation is active
struct GenerationStatusBanner: View {
    @ObservedObject var orchestrator: GenerationOrchestrator
    @Binding var showGenerationView: Bool
    
    var body: some View {
        Button {
            showGenerationView = true
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
