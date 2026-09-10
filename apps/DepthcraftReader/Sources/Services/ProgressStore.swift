import Foundation

/// Device-local progress keyed by packageId. Package progress.json is never authoritative after first open.
final class ProgressStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.outputFormatting = [.sortedKeys]
    }

    private func key(for packageId: String) -> String {
        "depthcraft.progress.\(packageId)"
    }

    func load(packageId: String, lessonIds: [String], unitIds: [String]) -> DeviceProgress {
        if let data = defaults.data(forKey: key(for: packageId)),
           let existing = try? decoder.decode(DeviceProgress.self, from: data),
           existing.packageId == packageId {
            return merge(existing, lessonIds: lessonIds, unitIds: unitIds)
        }
        let blank = DeviceProgress.blank(packageId: packageId, lessonIds: lessonIds, unitIds: unitIds)
        save(blank)
        return blank
    }

    /// Merge new lesson/unit ids without clobbering existing completions.
    private func merge(_ existing: DeviceProgress, lessonIds: [String], unitIds: [String]) -> DeviceProgress {
        var next = existing
        for id in lessonIds where next.lessons[id] == nil {
            next.lessons[id] = .empty
        }
        for id in unitIds where next.units[id] == nil {
            next.units[id] = UnitProgress(completed: false, completedAt: nil)
        }
        return next
    }

    func save(_ progress: DeviceProgress) {
        guard let data = try? encoder.encode(progress) else { return }
        defaults.set(data, forKey: key(for: progress.packageId))
    }

    func markRead(_ progress: inout DeviceProgress, lessonId: String, unitId: String, curriculum: Curriculum) {
        var lesson = progress.lessons[lessonId] ?? .empty
        lesson.markedRead = true
        if lesson.quizPassed {
            lesson.completed = true
            if lesson.completedAt == nil {
                lesson.completedAt = ISO8601DateFormatter().string(from: Date())
            }
        }
        progress.lessons[lessonId] = lesson
        progress.lastLessonId = lessonId
        progress.lastUnitId = unitId
        rollUpUnit(&progress, unitId: unitId, curriculum: curriculum)
        save(progress)
    }

    func updateLastVisited(_ progress: inout DeviceProgress, lessonId: String, unitId: String) {
        progress.lastLessonId = lessonId
        progress.lastUnitId = unitId
        save(progress)
    }

    func markQuizPassed(_ progress: inout DeviceProgress, lessonId: String, unitId: String, curriculum: Curriculum) {
        var lesson = progress.lessons[lessonId] ?? .empty
        lesson.quizPassed = true
        // Completing the quiz also implies the learner engaged with the lesson.
        lesson.markedRead = true
        lesson.completed = true
        lesson.completedAt = ISO8601DateFormatter().string(from: Date())
        progress.lessons[lessonId] = lesson
        progress.lastLessonId = lessonId
        progress.lastUnitId = unitId
        rollUpUnit(&progress, unitId: unitId, curriculum: curriculum)
        save(progress)
    }

    private func rollUpUnit(_ progress: inout DeviceProgress, unitId: String, curriculum: Curriculum) {
        guard let unit = curriculum.units.first(where: { $0.id == unitId }) else { return }
        let allDone = unit.lessonIds.allSatisfy { progress.lessons[$0]?.completed == true }
        var unitProgress = progress.units[unitId] ?? UnitProgress(completed: false, completedAt: nil)
        if allDone {
            unitProgress.completed = true
            if unitProgress.completedAt == nil {
                unitProgress.completedAt = ISO8601DateFormatter().string(from: Date())
            }
        } else {
            unitProgress.completed = false
            unitProgress.completedAt = nil
        }
        progress.units[unitId] = unitProgress
    }
}
