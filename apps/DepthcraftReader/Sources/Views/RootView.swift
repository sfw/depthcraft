import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: CourseStore

    var body: some View {
        NavigationStack {
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
        }
    }
}
