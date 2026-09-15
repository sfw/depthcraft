import SwiftUI

// MARK: - Lesson Player
/// P2 PRIVACY: Lesson rendering is 100% offline. No network calls during study path.
/// - Lesson markdown/HTML: Loaded from local package files (PackageLoader)
/// - Progress tracking: Device-local only (ProgressStore → UserDefaults)
/// - Online features (Explain/Discuss) are explicitly gated by isOnline + hasAPIKey checks

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
    
    private var activeNavigationPath: Binding<[NavigationDestination]> {
        navigationPath ?? environmentNavigationPath
    }

    private var lesson: CurriculumLesson? {
        store.course?.curriculum.lessons[lessonId]
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

                // Lesson completion control band
                VStack(spacing: 0) {
                    Divider()
                    
                    HStack(spacing: 12) {
                        if store.progress?.lessons[lessonId]?.completed == true {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.teal)
                                Text("Complete")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.teal)
                            }
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
                }
                .background(.bar)
            }
        }
        .navigationTitle(lesson?.title ?? "Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    activeNavigationPath.wrappedValue.removeAll()
                } label: {
                    Image("HomeMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 28)
                }
            }
        }
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
            
            let meta = try? PackageLoader.lessonMeta(course: course, unitId: unitId, lessonId: lessonId)
            let anchors = meta?.anchors ?? []
            
            renderResult = MarkdownHTML.render(md, title: lesson?.title ?? "", estimatedMinutes: lesson?.estimatedMinutes, anchors: anchors)
            quiz = try PackageLoader.quiz(course: course, unitId: unitId, lessonId: lessonId)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
