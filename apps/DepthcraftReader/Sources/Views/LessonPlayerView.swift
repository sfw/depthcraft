import SwiftUI

struct LessonPlayerView: View {
    @EnvironmentObject private var store: CourseStore
    let unitId: String
    let lessonId: String

    @State private var html: String = ""
    @State private var quiz: QuizDocument?
    @State private var showQuiz = false
    @State private var loadError: String?
    @State private var markedRead = false

    private var lesson: CurriculumLesson? {
        store.course?.curriculum.lessons[lessonId]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let loadError {
                ContentUnavailableView("Lesson unavailable", systemImage: "doc.questionmark", description: Text(loadError))
            } else {
                LessonWebView(html: html)
                    .ignoresSafeArea(edges: .bottom)

                Divider()

                HStack(spacing: 12) {
                    if store.progress?.lessons[lessonId]?.completed == true {
                        Label("Complete", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.teal)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("Study, then check understanding")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        markReadOnce()
                        showQuiz = true
                    } label: {
                        Label(quiz == nil ? "Quiz unavailable" : "Take quiz", systemImage: "checkmark.circle")
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
                QuizFlowView(unitId: unitId, lessonId: lessonId, quiz: quiz)
            }
        }
        .task {
            await load()
        }
        .onDisappear {
            markReadOnce()
        }
    }

    private func markReadOnce() {
        guard !markedRead else { return }
        markedRead = true
        store.markLessonRead(lessonId: lessonId, unitId: unitId)
    }

    @MainActor
    private func load() async {
        guard let course = store.course else { return }
        do {
            let md = try PackageLoader.lessonMarkdown(course: course, unitId: unitId, lessonId: lessonId)
            html = MarkdownHTML.render(md, title: lesson?.title ?? "")
            quiz = try PackageLoader.quiz(course: course, unitId: unitId, lessonId: lessonId)
            loadError = nil
            // Mark read shortly after open so resume works even if they don't finish.
            try? await Task.sleep(nanoseconds: 800_000_000)
            markReadOnce()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
