import SwiftUI

struct LessonContentView: View {
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let renderResult: LessonRenderResult
    let onScrolledToEnd: () -> Void
    
    var body: some View {
        if renderResult.demos.isEmpty {
            // No demos - use simple web view
            LessonWebView(html: renderResult.html, onScrolledToEnd: onScrolledToEnd)
        } else {
            // Has demos - show as vertical stack with lesson content and demos
            VStack(spacing: 0) {
                LessonWebView(html: renderResult.html, onScrolledToEnd: onScrolledToEnd)
                
                ForEach(renderResult.demos, id: \.demoId) { demo in
                    DemoHostView(
                        course: course,
                        unitId: unitId,
                        lessonId: lessonId,
                        demoId: demo.demoId
                    )
                    .padding(16)
                }
            }
        }
    }
}
