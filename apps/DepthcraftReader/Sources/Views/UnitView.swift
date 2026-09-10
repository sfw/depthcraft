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
                Section {
                    if let blurb = store.course.flatMap({ PackageLoader.unitMarkdown(course: $0, unitId: unitId) }) {
                        Text(blurb.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: store.unitProgressFraction(unit))
                        .tint(.teal)
                }

                Section("Lessons") {
                    ForEach(store.lessons(for: unit)) { lesson in
                        NavigationLink {
                            LessonPlayerView(unitId: unitId, lessonId: lesson.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: statusIcon(for: lesson.id))
                                    .foregroundStyle(statusColor(for: lesson.id))
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lesson.title)
                                        .font(.headline)
                                    HStack(spacing: 8) {
                                        if let minutes = lesson.estimatedMinutes {
                                            Label("\(minutes) min", systemImage: "clock")
                                        }
                                        Text(statusLabel(for: lesson.id))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(unit?.title ?? "Unit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusIcon(for lessonId: String) -> String {
        let p = store.progress?.lessons[lessonId]
        if p?.completed == true { return "checkmark.circle.fill" }
        if p?.markedRead == true || p?.quizPassed == true { return "circle.lefthalf.filled" }
        return "circle"
    }

    private func statusColor(for lessonId: String) -> Color {
        store.progress?.lessons[lessonId]?.completed == true ? .teal : .secondary
    }

    private func statusLabel(for lessonId: String) -> String {
        let p = store.progress?.lessons[lessonId]
        if p?.completed == true { return "Complete" }
        if p?.quizPassed == true { return "Quiz passed" }
        if p?.markedRead == true { return "In progress" }
        return "Not started"
    }
}
