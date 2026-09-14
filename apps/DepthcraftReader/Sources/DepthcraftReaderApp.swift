import SwiftUI

@main
struct DepthcraftReaderApp: App {
    @StateObject private var store = CourseStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var orchestrator = GenerationOrchestrator(keyStore: APIKeyStore())
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register background tasks on app launch
        let manager = BackgroundGenerationManager()
        Task { @MainActor in
            manager.registerBackgroundTasks()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(networkMonitor)
                .environmentObject(orchestrator)
                .onAppear {
                    store.loadBundledCourseIfNeeded()
                    orchestrator.backgroundManager.clearNotificationBadge()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            orchestrator.handleAppDidEnterBackground()
        case .active:
            orchestrator.handleAppWillEnterForeground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
