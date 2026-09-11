import SwiftUI

struct LessonPlayerView: View {
    @EnvironmentObject private var store: CourseStore
    @Environment(\.navigationPath) private var environmentNavigationPath
    let unitId: String
    let lessonId: String
    var navigationPath: Binding<[NavigationDestination]>?

    @State private var renderResult: LessonRenderResult?
    @State private var quiz: QuizDocument?
    @State private var showQuiz = false
    @State private var loadError: String?

    private var lesson: CurriculumLesson? {
        store.course?.curriculum.lessons[lessonId]
    }
    
    private var activeNavigationPath: Binding<[NavigationDestination]> {
        navigationPath ?? environmentNavigationPath
    }

    var body: some View {
        VStack(spacing: 0) {
            if let loadError {
                ContentUnavailableView("Lesson unavailable", systemImage: "doc.questionmark", description: Text(loadError))
            } else if let renderResult, let course = store.course {
                LessonContentView(
                    course: course,
                    unitId: unitId,
                    lessonId: lessonId,
                    renderResult: renderResult,
                    onScrolledToEnd: {
                        store.markLessonRead(lessonId: lessonId, unitId: unitId)
                    }
                )

                Divider()

                HStack(spacing: 12) {
                    if store.progress?.lessons[lessonId]?.completed == true {
                        Label("Complete", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.teal)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Study, then continue to quiz")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.markLessonRead(lessonId: lessonId, unitId: unitId)
                        showQuiz = true
                    } label: {
                        Label(quiz == nil ? "Quiz unavailable" : "Continue to quiz", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(quiz == nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .navigationTitle(lesson?.title ?? "Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showQuiz) {
            if let quiz {
                QuizFlowView(
                    unitId: unitId,
                    lessonId: lessonId,
                    quiz: quiz,
                    navigationPath: activeNavigationPath,
                    onDismissQuiz: { showQuiz = false }
                )
            }
        }
        .task {
            await load()
            store.updateLastVisited(lessonId: lessonId, unitId: unitId)
        }
    }

    @MainActor
    private func load() async {
        guard let course = store.course else { return }
        do {
            let md = try PackageLoader.lessonMarkdown(course: course, unitId: unitId, lessonId: lessonId)
            renderResult = MarkdownHTML.render(md, title: lesson?.title ?? "", estimatedMinutes: lesson?.estimatedMinutes)
            quiz = try PackageLoader.quiz(course: course, unitId: unitId, lessonId: lessonId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
