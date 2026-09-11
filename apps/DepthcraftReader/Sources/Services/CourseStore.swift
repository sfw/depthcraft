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
    private let lastOpenedPackageKey = "lastOpenedPackageURL"

    func loadBundledCourseIfNeeded() {
        guard course == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let url = try determineStartupPackageURL()
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
            
            // Persist last opened package URL if it's from Documents (not bundled fixture)
            let bundledURL = try? PackageLoader.bundledPackageURL()
            if bundledURL == nil || url.path != bundledURL?.path {
                UserDefaults.standard.set(url.path, forKey: lastOpenedPackageKey)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func determineStartupPackageURL() throws -> URL {
        // 1. Try last-opened package if it still exists
        if let lastOpenedPath = UserDefaults.standard.string(forKey: lastOpenedPackageKey) {
            let lastOpenedURL = URL(fileURLWithPath: lastOpenedPath)
            if fileManager.fileExists(atPath: lastOpenedURL.path) {
                return lastOpenedURL
            }
        }
        
        // 2. Try newest .depthcraft in Documents
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let contents = try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let packages = contents.filter { url in
                url.pathExtension == "depthcraft" || url.lastPathComponent.hasSuffix(".depthcraft")
            }
            
            if let newestPackage = packages.sorted(by: { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }).first {
                return newestPackage
            }
        }
        
        // 3. Fall back to bundled fixture
        return try PackageLoader.bundledPackageURL()
    }
    
    func loadPackage(from url: URL) {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try PackageLoader.load(from: url)
            
            #if DEBUG
            print("📦 Loading package from: \(url.path)")
            print("   Manifest: \(loaded.manifest.packageId)")
            print("   Units: \(loaded.curriculum.units.count)")
            print("   Lessons: \(loaded.curriculum.lessons.count)")
            for unit in loaded.curriculum.units.sorted(by: { $0.order < $1.order }) {
                print("   - Unit \(unit.order): \(unit.title) (\(unit.lessonIds.count) lessons)")
            }
            #endif
            
            // Force-clear old course before setting new one to ensure SwiftUI detects the change
            course = nil
            
            // Set new course
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
            
            // Persist last opened package URL
            UserDefaults.standard.set(url.path, forKey: lastOpenedPackageKey)
        } catch {
            #if DEBUG
            print("❌ Failed to load package: \(error)")
            #endif
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

    func updateLastVisited(lessonId: String, unitId: String) {
        guard var progress else { return }
        progressStore.updateLastVisited(&progress, lessonId: lessonId, unitId: unitId)
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
