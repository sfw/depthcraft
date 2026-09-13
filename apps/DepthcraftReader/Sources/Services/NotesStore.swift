import Foundation

/// P2 PRIVACY: Notes are device-local only. Never syncs, exports, or includes API keys.
/// - Storage: UserDefaults with key pattern "depthcraft.notes.{packageId}"
/// - Data: CourseNotes structure (user highlights with optional gloss text)
/// - NO API keys: Notes data contains ONLY user highlights + cached explanations
/// - NO export: No iCloud, no network, no export paths exist in v0.1

/// Device-local notes storage keyed by packageId
final class NotesStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    }
    
    private func key(for packageId: String) -> String {
        "depthcraft.notes.\(packageId)"
    }
    
    func load(packageId: String) -> CourseNotes {
        if let data = defaults.data(forKey: key(for: packageId)),
           let existing = try? decoder.decode(CourseNotes.self, from: data),
           existing.packageId == packageId {
            return existing
        }
        let blank = CourseNotes.blank(packageId: packageId)
        save(blank)
        return blank
    }
    
    func save(_ notes: CourseNotes) {
        guard let data = try? encoder.encode(notes) else { return }
        defaults.set(data, forKey: key(for: notes.packageId))
    }
    
    func addHighlight(_ notes: inout CourseNotes, highlight: HighlightNote) {
        notes.highlights[highlight.id] = highlight
        save(notes)
    }
    
    func removeHighlight(_ notes: inout CourseNotes, highlightId: String) {
        notes.highlights.removeValue(forKey: highlightId)
        save(notes)
    }
    
    func updateHighlight(_ notes: inout CourseNotes, highlight: HighlightNote) {
        notes.highlights[highlight.id] = highlight
        save(notes)
    }
    
    func highlights(for notes: CourseNotes, lessonId: String) -> [HighlightNote] {
        notes.highlights.values
            .filter { $0.lessonId == lessonId }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    func allHighlights(for notes: CourseNotes) -> [HighlightNote] {
        notes.highlights.values
            .sorted { $0.createdAt > $1.createdAt }
    }
}
