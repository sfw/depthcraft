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
            // Has demos - embed them inline at :::demo::: directive positions
            inlineLayout
        }
    }
    
    private var inlineLayout: some View {
        let sections = splitHTMLAtDemoPlaceholders(html: renderResult.html, demos: renderResult.demos)
        
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    switch section {
                    case .html(let html):
                        if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            InlineHTMLSection(
                                html: html,
                                onScrolledToEnd: index == sections.count - 1 ? onScrolledToEnd : {}
                            )
                        }
                    case .demo(let demoId):
                        DemoHostView(
                            course: course,
                            unitId: unitId,
                            lessonId: lessonId,
                            demoId: demoId
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                }
            }
        }
    }
    
    private func splitHTMLAtDemoPlaceholders(html: String, demos: [DemoReference]) -> [ContentSection] {
        var sections: [ContentSection] = []
        var remainingHTML = html
        
        for demo in demos {
            let placeholderDiv = "<div class=\"demo-placeholder\" id=\"\(demo.placeholder)\">Interactive demo</div>"
            
            if let range = remainingHTML.range(of: placeholderDiv) {
                // Add HTML section before the demo
                let beforeHTML = String(remainingHTML[..<range.lowerBound])
                if !beforeHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(.html(beforeHTML))
                }
                
                // Add demo section
                sections.append(.demo(demo.demoId))
                
                // Continue with remaining HTML
                remainingHTML = String(remainingHTML[range.upperBound...])
            }
        }
        
        // Add final HTML section after last demo
        if !remainingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(.html(remainingHTML))
        }
        
        return sections
    }
}

enum ContentSection {
    case html(String)
    case demo(String)
}

struct InlineHTMLSection: View {
    let html: String
    let onScrolledToEnd: () -> Void
    @State private var contentHeight: CGFloat = 200
    
    var body: some View {
        InlineWebViewWrapper(html: html, contentHeight: $contentHeight, onScrolledToEnd: onScrolledToEnd)
            .frame(height: contentHeight)
    }
}

struct InlineWebViewWrapper: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    let onScrolledToEnd: () -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight, onScrolledToEnd: onScrolledToEnd)
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        @Binding var contentHeight: CGFloat
        let onScrolledToEnd: () -> Void
        
        init(contentHeight: Binding<CGFloat>, onScrolledToEnd: @escaping () -> Void) {
            self._contentHeight = contentHeight
            self.onScrolledToEnd = onScrolledToEnd
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure actual content height
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self?.contentHeight = height
                    }
                }
            }
            onScrolledToEnd()
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
