import SwiftUI

struct UnitView: View {
    @EnvironmentObject private var store: CourseStore
    let unitId: String

    private var unit: CurriculumUnit? {
        store.orderedUnits().first { $0.id == unitId }
    }

    var body: some View {
        List {
            if let unit {
                if let rawBlurb = store.course.flatMap({ PackageLoader.unitMarkdown(course: $0, unitId: unitId) }),
                   let cleanedBlurb = cleanMarkdownText(rawBlurb),
                   !cleanedBlurb.isEmpty {
                    Section {
                        Text(cleanedBlurb)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Lessons") {
                    ForEach(store.lessons(for: unit)) { lesson in
                        NavigationLink(value: NavigationDestination.lesson(unitId: unitId, lessonId: lesson.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                // Current lesson marker (teal accent)
                                if store.progress?.lastLessonId == lesson.id {
                                    Rectangle()
                                        .fill(Color.teal)
                                        .frame(width: 2, height: 16)
                                }
                                
                                // Read indicator (subtle dot)
                                Circle()
                                    .fill(store.progress?.lessons[lesson.id]?.completed == true ? Color.secondary : Color.clear)
                                    .frame(width: 6, height: 6)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    let isCurrent = store.progress?.lastLessonId == lesson.id
                                    let isCompleted = store.progress?.lessons[lesson.id]?.completed == true
                                    
                                    Text(lesson.title)
                                        .font(.body)
                                        .foregroundStyle(isCurrent ? .primary : (isCompleted ? .tertiary : .secondary))
                                    
                                    if let minutes = lesson.estimatedMinutes {
                                        Text("\(minutes) min")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle(unit?.title ?? "Unit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cleanMarkdownText(_ text: String) -> String? {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        
        // Strip leading # from first line if present
        if let first = lines.first, first.hasPrefix("#") {
            let cleaned = first.drop(while: { $0 == "#" || $0 == " " })
            if !cleaned.isEmpty {
                lines[0] = String(cleaned)
            } else {
                lines.removeFirst()
            }
        }
        
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
