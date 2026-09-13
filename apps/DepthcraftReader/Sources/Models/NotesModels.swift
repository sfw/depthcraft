import Foundation

/// A saved highlight/note in a lesson
struct HighlightNote: Codable, Hashable, Identifiable {
    let id: String
    let lessonId: String
    let unitId: String
    let text: String
    let createdAt: String
    var gloss: String?
    var discussHistory: [DiscussMessage]?
    
    init(id: String = UUID().uuidString, lessonId: String, unitId: String, text: String, createdAt: String = ISO8601DateFormatter().string(from: Date()), gloss: String? = nil, discussHistory: [DiscussMessage]? = nil) {
        self.id = id
        self.lessonId = lessonId
        self.unitId = unitId
        self.text = text
        self.createdAt = createdAt
        self.gloss = gloss
        self.discussHistory = discussHistory
    }
}

struct DiscussMessage: Codable, Hashable, Identifiable {
    let id: String
    let role: String
    let content: String
    let timestamp: String
    
    init(id: String = UUID().uuidString, role: String, content: String, timestamp: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// Device-local notes keyed by packageId
struct CourseNotes: Codable, Hashable {
    var schemaVersion: String
    var packageId: String
    var highlights: [String: HighlightNote]
    
    static func blank(packageId: String) -> CourseNotes {
        CourseNotes(
            schemaVersion: "0.1.0",
            packageId: packageId,
            highlights: [:]
        )
    }
}
