import SwiftUI

struct NavigationPathKey: EnvironmentKey {
    static let defaultValue: Binding<[NavigationDestination]> = .constant([])
}

extension EnvironmentValues {
    var navigationPath: Binding<[NavigationDestination]> {
        get { self[NavigationPathKey.self] }
        set { self[NavigationPathKey.self] = newValue }
    }
}
