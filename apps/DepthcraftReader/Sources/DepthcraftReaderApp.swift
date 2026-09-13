import SwiftUI

@main
struct DepthcraftReaderApp: App {
    @StateObject private var store = CourseStore()
    @StateObject private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(networkMonitor)
                .onAppear { store.loadBundledCourseIfNeeded() }
        }
    }
}
