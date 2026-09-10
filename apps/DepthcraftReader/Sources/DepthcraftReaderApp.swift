import SwiftUI

@main
struct DepthcraftReaderApp: App {
    @StateObject private var store = CourseStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { store.loadBundledCourseIfNeeded() }
        }
    }
}
