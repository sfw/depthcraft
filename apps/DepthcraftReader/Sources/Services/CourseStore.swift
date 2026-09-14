import Foundation
import SwiftUI

@MainActor
final class CourseStore: ObservableObject {
    @Published var course: LoadedCourse?
    @Published var progress: DeviceProgress?
    @Published var notes: CourseNotes?
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var availablePackages: [URL] = []
    @Published var pendingPackageUpgrade: LoadedCourse?
    @Published var showUpgradeDialog = false
    
    private let progressStore = ProgressStore()
    private let notesStore = NotesStore()
    private let fileManager = FileManager.default
    private let lastOpenedPackageKey = "lastOpenedPackageURL"
    
    init() {
        refreshAvailablePackages()
    }

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
            var loadedProgress = progressStore.load(
                packageId: loaded.manifest.packageId,
                lessonIds: lessonIds,
                unitIds: unitIds
            )
            progressStore.markPackageOpened(&loadedProgress)
            progress = loadedProgress
            notes = notesStore.load(packageId: loaded.manifest.packageId)
            errorMessage = nil
            
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
            print("   Version: \(loaded.manifest.contentVersion)")
            print("   Units: \(loaded.curriculum.units.count)")
            print("   Lessons: \(loaded.curriculum.lessons.count)")
            for unit in loaded.curriculum.units.sorted(by: { $0.order < $1.order }) {
                print("   - Unit \(unit.order): \(unit.title) (\(unit.lessonIds.count) lessons)")
            }
            #endif
            
            if let currentCourse = course,
               currentCourse.manifest.packageId == loaded.manifest.packageId {
                if loaded.manifest.contentVersion > currentCourse.manifest.contentVersion {
                    #if DEBUG
                    print("📦 Detected package upgrade: v\(currentCourse.manifest.contentVersion) → v\(loaded.manifest.contentVersion)")
                    #endif
                    pendingPackageUpgrade = loaded
                    showUpgradeDialog = true
                    return
                } else if loaded.manifest.contentVersion < currentCourse.manifest.contentVersion {
                    errorMessage = "Cannot load older version (v\(loaded.manifest.contentVersion)) of package. Current version is v\(currentCourse.manifest.contentVersion)."
                    return
                }
            }
            
            applyPackageLoad(loaded: loaded, url: url)
        } catch {
            #if DEBUG
            print("❌ Failed to load package: \(error)")
            #endif
            // P2 SECURITY: Use user-friendly error messages for package validation failures
            if let validationError = error as? SchemaValidatorError {
                errorMessage = validationError.userFriendlyDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func confirmPackageUpgrade() {
        guard let pending = pendingPackageUpgrade else { return }
        showUpgradeDialog = false
        pendingPackageUpgrade = nil
        
        isLoading = true
        defer { isLoading = false }
        applyPackageLoad(loaded: pending, url: pending.rootURL)
    }
    
    func cancelPackageUpgrade() {
        showUpgradeDialog = false
        pendingPackageUpgrade = nil
    }
    
    private func applyPackageLoad(loaded: LoadedCourse, url: URL) {
        // Force-clear old course before setting new one to ensure SwiftUI detects the change
        course = nil
        
        // Set new course
        course = loaded
        let lessonIds = Array(loaded.curriculum.lessons.keys)
        let unitIds = loaded.curriculum.units.map(\.id)
        var loadedProgress = progressStore.load(
            packageId: loaded.manifest.packageId,
            lessonIds: lessonIds,
            unitIds: unitIds
        )
        progressStore.markPackageOpened(&loadedProgress)
        progress = loadedProgress
        notes = notesStore.load(packageId: loaded.manifest.packageId)
        errorMessage = nil
        refreshAvailablePackages()
        
        // Persist last opened package URL
        UserDefaults.standard.set(url.path, forKey: lastOpenedPackageKey)
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
    
    func addHighlight(_ highlight: HighlightNote) {
        guard var notes else { return }
        notesStore.addHighlight(&notes, highlight: highlight)
        self.notes = notes
    }
    
    func removeHighlight(highlightId: String) {
        guard var notes else { return }
        notesStore.removeHighlight(&notes, highlightId: highlightId)
        self.notes = notes
    }
    
    func updateHighlight(_ highlight: HighlightNote) {
        guard var notes else { return }
        notesStore.updateHighlight(&notes, highlight: highlight)
        self.notes = notes
    }
    
    func highlights(for lessonId: String) -> [HighlightNote] {
        guard let notes else { return [] }
        return notesStore.highlights(for: notes, lessonId: lessonId)
    }
    
    func allHighlights() -> [HighlightNote] {
        guard let notes else { return [] }
        return notesStore.allHighlights(for: notes)
    }
    
    /// Get lessons that were planned but failed to generate (not in built curriculum)
    func failedLessons() -> [(unit: CurriculumUnit, lesson: CurriculumLesson)] {
        guard let course else { return [] }
        guard let plannedCurriculum = course.manifest.plannedCurriculum else { return [] }
        
        let builtLessonIds = Set(course.curriculum.lessons.keys)
        var failed: [(unit: CurriculumUnit, lesson: CurriculumLesson)] = []
        
        for unit in plannedCurriculum.units {
            for lessonId in unit.lessonIds {
                if let lesson = plannedCurriculum.lessons[lessonId],
                   !builtLessonIds.contains(lessonId) {
                    failed.append((unit: unit, lesson: lesson))
                }
            }
        }
        
        return failed
    }
    
    func libraryPackages() -> [LibraryPackageMetadata] {
        var packages: [LibraryPackageMetadata] = []
        
        for url in availablePackages {
            do {
                let loaded = try PackageLoader.load(from: url)
                let packageId = loaded.manifest.packageId
                let lessonIds = Array(loaded.curriculum.lessons.keys)
                let unitIds = loaded.curriculum.units.map(\.id)
                
                let progress = progressStore.load(packageId: packageId, lessonIds: lessonIds, unitIds: unitIds)
                
                var lastOpenedDate: Date? = nil
                if let lastOpenedStr = progress.lastOpenedAt {
                    lastOpenedDate = ISO8601DateFormatter().date(from: lastOpenedStr)
                }
                
                packages.append(LibraryPackageMetadata(
                    id: packageId,
                    packageId: packageId,
                    title: loaded.manifest.title,
                    lessonCount: loaded.curriculum.lessons.count,
                    lastOpenedAt: lastOpenedDate,
                    url: url
                ))
            } catch {
                continue
            }
        }
        
        return packages.sorted { pkg1, pkg2 in
            guard let date1 = pkg1.lastOpenedAt else { return false }
            guard let date2 = pkg2.lastOpenedAt else { return true }
            return date1 > date2
        }
    }
}
