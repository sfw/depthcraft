import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: CourseStore
    @State private var navigationPath: [NavigationDestination] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if store.isLoading && store.course == nil {
                    ProgressView("Opening course…")
                } else if let message = store.errorMessage, store.course == nil {
                    ContentUnavailableView(
                        "Couldn't open package",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                } else {
                    CourseHomeView()
                }
            }
            .navigationTitle("Depthcraft")
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
}
