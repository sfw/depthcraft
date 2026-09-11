import Foundation

struct PackageManifest: Codable, Hashable {
    let schemaVersion: String
    let packageId: String
    let title: String
    let topic: String
    let createdAt: String
    let locale: String
    let generator: GeneratorMetadata?
}

struct Curriculum: Codable, Hashable {
    let schemaVersion: String
    var status: String
    var approvedAt: String?
    var units: [CurriculumUnit]
    var lessons: [String: CurriculumLesson]
}

struct CurriculumUnit: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var order: Int
    var lessonIds: [String]
}

struct CurriculumLesson: Codable, Hashable, Identifiable {
    let id: String
    let unitId: String
    var title: String
    var order: Int
    var status: String
    var estimatedMinutes: Int?
}

struct DemoManifest: Codable, Hashable {
    let schemaVersion: String
    let demoId: String
    let title: String
    let kit: String
    let entry: String
    let fallback: String
}

struct QuizDocument: Codable, Hashable {
    let schemaVersion: String
    let lessonId: String
    let items: [QuizItem]
}

enum QuizItem: Codable, Hashable, Identifiable {
    case mc(MCItem)
    case cloze(ClozeItem)

    var id: String {
        switch self {
        case .mc(let item): return item.id
        case .cloze(let item): return item.id
        }
    }

    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: CodingKeys.self)
        let type = try probe.decode(String.self, forKey: .type)
        switch type {
        case "mc":
            self = .mc(try MCItem(from: decoder))
        case "cloze":
            self = .cloze(try ClozeItem(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: probe,
                debugDescription: "Unknown quiz item type \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .mc(let item): try item.encode(to: encoder)
        case .cloze(let item): try item.encode(to: encoder)
        }
    }
}

struct MCItem: Codable, Hashable, Identifiable {
    let id: String
    let type: String
    let prompt: String
    let choices: [MCChoice]
    let correctId: String
    let explain: String?
}

struct MCChoice: Codable, Hashable, Identifiable {
    let id: String
    let text: String
}

struct ClozeItem: Codable, Hashable, Identifiable {
    let id: String
    let type: String
    let prompt: String
    let answers: [String]
    let explain: String?
}

struct LessonProgress: Codable, Hashable {
    var completed: Bool
    var quizPassed: Bool
    var completedAt: String?
    var markedRead: Bool

    static var empty: LessonProgress {
        LessonProgress(completed: false, quizPassed: false, completedAt: nil, markedRead: false)
    }
}

struct UnitProgress: Codable, Hashable {
    var completed: Bool
    var completedAt: String?
}

struct DeviceProgress: Codable, Hashable {
    var schemaVersion: String
    var packageId: String
    var lessons: [String: LessonProgress]
    var units: [String: UnitProgress]
    var lastLessonId: String?
    var lastUnitId: String?

    static func blank(packageId: String, lessonIds: [String], unitIds: [String]) -> DeviceProgress {
        DeviceProgress(
            schemaVersion: "0.1.0",
            packageId: packageId,
            lessons: Dictionary(uniqueKeysWithValues: lessonIds.map { ($0, .empty) }),
            units: Dictionary(uniqueKeysWithValues: unitIds.map { ($0, UnitProgress(completed: false, completedAt: nil)) }),
            lastLessonId: nil,
            lastUnitId: nil
        )
    }
}

struct LoadedCourse: Hashable {
    let rootURL: URL
    let manifest: PackageManifest
    let curriculum: Curriculum
}
