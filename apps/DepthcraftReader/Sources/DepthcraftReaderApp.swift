import SwiftUI

@main
struct DepthcraftReaderApp: App {
    @StateObject private var store = CourseStore()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var apiKeyStore = APIKeyStore()
    @StateObject private var customEndpointsStore = CustomEndpointsStore()
    @StateObject private var orchestrator: GenerationOrchestrator
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let apiStore = APIKeyStore()
        let customStore = CustomEndpointsStore()
        _apiKeyStore = StateObject(wrappedValue: apiStore)
        _customEndpointsStore = StateObject(wrappedValue: customStore)
        _orchestrator = StateObject(wrappedValue: GenerationOrchestrator(keyStore: apiStore, customEndpointsStore: customStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(networkMonitor)
                .environmentObject(orchestrator)
                .onAppear {
                    if store.availablePackages.count < 2 {
                        store.loadBundledCourseIfNeeded()
                    }
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
