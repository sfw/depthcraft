import Foundation

enum NavigationDestination: Hashable, Codable {
    case courseHome
    case unit(unitId: String)
    case lesson(unitId: String, lessonId: String)
    case generation(extendFromPackageURL: URL?)
    case settings
}
