import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnline = true // Start optimistic to avoid flash
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.depthcraft.network.monitor")
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
