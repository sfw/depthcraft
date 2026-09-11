import SwiftUI

// MARK: - Demo Placement Note
// Demos are currently rendered AFTER lesson content (below-content stacking).
// True inline placement at :::demo::: directive positions would require:
// 1. Splitting lesson HTML at placeholder markers
// 2. Alternating between WKWebView sections and DemoHostView instances
// 3. Managing multiple WebView heights dynamically
// This is feasible but adds complexity. Current approach approved pending Product Designer review.
// If PD requires true inline: see DEMO_SPIKE_NOTES.md "Demo positioning" section.

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
            // TODO: True inline placement requires PD signoff (see file header note)
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
