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
    }
}
