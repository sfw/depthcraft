import Foundation
import SwiftUI

@MainActor
final class CourseStore: ObservableObject {
    @Published var course: LoadedCourse?
    @Published var progress: DeviceProgress?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var availablePackages: [URL] = []
    
    private let progressStore = ProgressStore()
    private let fileManager = FileManager.default

    func loadBundledCourseIfNeeded() {
        guard course == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let url = try PackageLoader.bundledPackageURL()
            let loaded = try PackageLoader.load(from: url)
            course = loaded
            let lessonIds = Array(loaded.curriculum.lessons.keys)
            let unitIds = loaded.curriculum.units.map(\.id)
            progress = progressStore.load(
                packageId: loaded.manifest.packageId,
                lessonIds: lessonIds,
                unitIds: unitIds
            )
            errorMessage = nil
            refreshAvailablePackages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadPackage(from url: URL) {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try PackageLoader.load(from: url)
            course = loaded
            let lessonIds = Array(loaded.curriculum.lessons.keys)
            let unitIds = loaded.curriculum.units.map(\.id)
            progress = progressStore.load(
                packageId: loaded.manifest.packageId,
                lessonIds: lessonIds,
                unitIds: unitIds
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshAvailablePackages() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            availablePackages = contents.filter { url in
                url.pathExtension == "depthcraft" || url.lastPathComponent.hasSuffix(".depthcraft")
            }
        } catch {
            availablePackages = []
        }
    }

    func orderedUnits() -> [CurriculumUnit] {
        (course?.curriculum.units ?? []).sorted { $0.order < $1.order }
    }

    func lessons(for unit: CurriculumUnit) -> [CurriculumLesson] {
        guard let curriculum = course?.curriculum else { return [] }
        return unit.lessonIds.compactMap { curriculum.lessons[$0] }.sorted { $0.order < $1.order }
    }

    func unitProgressFraction(_ unit: CurriculumUnit) -> Double {
        let lessons = lessons(for: unit)
        guard !lessons.isEmpty, let progress else { return 0 }
        let done = lessons.filter { progress.lessons[$0.id]?.completed == true }.count
        return Double(done) / Double(lessons.count)
    }

    func courseProgressFraction() -> Double {
        let units = orderedUnits()
        guard !units.isEmpty else { return 0 }
        let sum = units.map(unitProgressFraction).reduce(0, +)
        return sum / Double(units.count)
    }

    func markLessonRead(lessonId: String, unitId: String) {
        guard var progress, let course else { return }
        progressStore.markRead(&progress, lessonId: lessonId, unitId: unitId, curriculum: course.curriculum)
        self.progress = progress
    }

    func markQuizPassed(lessonId: String, unitId: String) {
        guard var progress, let course else { return }
        progressStore.markQuizPassed(&progress, lessonId: lessonId, unitId: unitId, curriculum: course.curriculum)
        self.progress = progress
    }

    func resumeTarget() -> (unitId: String, lessonId: String)? {
        guard let progress, let course else { return nil }
        if let lessonId = progress.lastLessonId,
           let lesson = course.curriculum.lessons[lessonId] {
            return (lesson.unitId, lessonId)
        }
        // First incomplete lesson in order
        for unit in orderedUnits() {
            for lesson in lessons(for: unit) {
                if progress.lessons[lesson.id]?.completed != true {
                    return (unit.id, lesson.id)
                }
            }
        }
        if let unit = orderedUnits().first, let lesson = lessons(for: unit).first {
            return (unit.id, lesson.id)
        }
        return nil
    }
}
