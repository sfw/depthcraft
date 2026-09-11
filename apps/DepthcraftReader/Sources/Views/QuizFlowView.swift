import SwiftUI

struct QuizFlowView: View {
    @EnvironmentObject private var store: CourseStore
    @Environment(\.dismiss) private var dismiss

    let unitId: String
    let lessonId: String
    let quiz: QuizDocument
    let navigationPath: Binding<[NavigationDestination]>
    let onDismissQuiz: () -> Void

    @State private var mcSelections: [String: String] = [:]
    @State private var clozeAnswers: [String: String] = [:]
    @State private var graded = false
    @State private var itemResults: [String: Bool] = [:]

    private var nextLesson: (unitId: String, lessonId: String, title: String)? {
        guard let course = store.course else { return nil }
        guard let currentUnit = course.curriculum.units.first(where: { $0.id == unitId }) else { return nil }
        let lessons = store.lessons(for: currentUnit)
        if let currentIndex = lessons.firstIndex(where: { $0.id == lessonId }),
           currentIndex + 1 < lessons.count {
            let next = lessons[currentIndex + 1]
            return (unitId, next.id, next.title)
        }
        let orderedUnits = store.orderedUnits()
        if let unitIndex = orderedUnits.firstIndex(where: { $0.id == unitId }),
           unitIndex + 1 < orderedUnits.count {
            let nextUnit = orderedUnits[unitIndex + 1]
            if let firstLesson = store.lessons(for: nextUnit).first {
                return (nextUnit.id, firstLesson.id, firstLesson.title)
            }
        }
        return nil
    }

    private var isUnitComplete: Bool {
        guard let unit = store.course?.curriculum.units.first(where: { $0.id == unitId }) else { return false }
        return store.progress?.units[unitId]?.completed == true
    }

    var body: some View {
        List {
            Section {
                Text("Check your understanding")
                    .font(.title2.weight(.bold))
                Text("Answers stay on this device. Spelling isn't picky.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(quiz.items.enumerated()), id: \.element.id) { index, item in
                Section("Question \(index + 1)") {
                    switch item {
                    case .mc(let mc):
                        mcBlock(mc)
                    case .cloze(let cloze):
                        clozeBlock(cloze)
                    }
                }
            }

            Section {
                if !graded {
                    Button {
                        gradeAll()
                    } label: {
                        Label("Submit answers", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                } else {
                    let passed = itemResults.values.allSatisfy { $0 }
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            passed ? "Quiz passed" : "Not quite — review explains and retry",
                            systemImage: passed ? "checkmark.seal.fill" : "arrow.counterclockwise"
                        )
                        .foregroundStyle(passed ? Color.teal : Color.orange)
                        .font(.headline)

                        if passed {
                            if isUnitComplete {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.teal)
                                    Text("Unit complete")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.teal)
                                }
                                .padding(.vertical, 4)
                            }
                            if let next = nextLesson {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Ready for more?")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Button {
                                        navigateToNextLesson(nextUnitId: next.unitId, nextLessonId: next.lessonId)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Next lesson")
                                                    .font(.headline)
                                                Text(next.title)
                                                    .font(.subheadline)
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.forward.circle.fill")
                                                .font(.title2)
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.teal)
                                }
                            } else {
                                Button("Back to course") { dismiss() }
                                    .buttonStyle(.bordered)
                            }
                        } else {
                            Button("Try again") {
                                graded = false
                                itemResults = [:]
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                        }
                    }
                }
            }
        }
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(false)
    }

    @ViewBuilder
    private func mcBlock(_ item: MCItem) -> some View {
        Text(item.prompt)
            .font(.body.weight(.medium))
        ForEach(item.choices) { choice in
            let isSelected = mcSelections[item.id] == choice.id
            Button {
                guard !graded else { return }
                mcSelections[item.id] = choice.id
            } label: {
                HStack {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? Color.teal : Color.secondary)
                    Text(choice.text)
                        .foregroundStyle(isSelected ? Color.teal : Color(uiColor: .label))
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            .disabled(graded)
        }
        if graded {
            resultRow(correct: itemResults[item.id] == true, explain: item.explain)
        }
    }

    @ViewBuilder
    private func clozeBlock(_ item: ClozeItem) -> some View {
        Text(item.prompt)
            .font(.body.weight(.medium))
        TextField("Your answer", text: Binding(
            get: { clozeAnswers[item.id] ?? "" },
            set: { clozeAnswers[item.id] = $0 }
        ))
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(graded)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        if graded {
            resultRow(correct: itemResults[item.id] == true, explain: item.explain)
        }
    }

    @ViewBuilder
    private func resultRow(correct: Bool, explain: String?) -> some View {
        HStack {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? Color.teal : Color.orange)
            Text(correct ? "Correct" : "Incorrect")
                .font(.subheadline.weight(.semibold))
        }
        if let explain, !explain.isEmpty {
            Text(explain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func gradeAll() {
        var results: [String: Bool] = [:]
        for item in quiz.items {
            switch item {
            case .mc(let mc):
                results[mc.id] = QuizGrading.gradeMC(choiceId: mcSelections[mc.id], correctId: mc.correctId)
            case .cloze(let cloze):
                results[cloze.id] = QuizGrading.gradeCloze(answer: clozeAnswers[cloze.id] ?? "", accepted: cloze.answers)
            }
        }
        itemResults = results
        graded = true
        if results.values.allSatisfy({ $0 }) {
            store.markQuizPassed(lessonId: lessonId, unitId: unitId)
        }
    }
    
    private func navigateToNextLesson(nextUnitId: String, nextLessonId: String) {
        // Dismiss the quiz sheet first
        onDismissQuiz()
        
        // Remove the current lesson from the path (last item should be the current lesson)
        // and replace it with the next lesson, so Back goes to the previous lesson, not the completed one
        if !navigationPath.wrappedValue.isEmpty {
            navigationPath.wrappedValue.removeLast()
        }
        navigationPath.wrappedValue.append(.lesson(unitId: nextUnitId, lessonId: nextLessonId))
    }
}
