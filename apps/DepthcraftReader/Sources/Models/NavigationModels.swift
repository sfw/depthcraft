import Foundation

enum NavigationDestination: Hashable, Codable {
    case unit(unitId: String)
    case lesson(unitId: String, lessonId: String)
}
