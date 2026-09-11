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
        
        return InlineContentScrollView(sections: sections, course: course, unitId: unitId, lessonId: lessonId, onScrolledToEnd: onScrolledToEnd)
    }
    
    private func splitHTMLAtDemoPlaceholders(html: String, demos: [DemoReference]) -> [ContentSection] {
        var sections: [ContentSection] = []
        var remainingHTML = html
        
        // Extract stylesheet from the full document to re-wrap sections
        let (styleSheet, bodyContent) = extractStyleAndBody(from: html)
        remainingHTML = bodyContent
        
        for demo in demos {
            // Match by placeholder id attribute, not the exact text
            let placeholderPattern = "<div[^>]+id=\"\(demo.placeholder)\"[^>]*>.*?</div>"
            if let regex = try? NSRegularExpression(pattern: placeholderPattern, options: []),
               let match = regex.firstMatch(in: remainingHTML, range: NSRange(remainingHTML.startIndex..., in: remainingHTML)),
               let range = Range(match.range, in: remainingHTML) {
                
                // Add HTML section before the demo (re-wrapped with style)
                let beforeHTML = String(remainingHTML[..<range.lowerBound])
                if !beforeHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    sections.append(.html(wrapWithStyle(beforeHTML, styleSheet: styleSheet)))
                }
                
                // Add demo section
                sections.append(.demo(demo.demoId))
                
                // Continue with remaining HTML
                remainingHTML = String(remainingHTML[range.upperBound...])
            }
        }
        
        // Add final HTML section after last demo (re-wrapped with style)
        if !remainingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(.html(wrapWithStyle(remainingHTML, styleSheet: styleSheet)))
        }
        
        return sections
    }
    
    private func extractStyleAndBody(from html: String) -> (styleSheet: String, body: String) {
        // Extract <style>...</style> from <head>
        let stylePattern = "<style>.*?</style>"
        var styleSheet = ""
        if let regex = try? NSRegularExpression(pattern: stylePattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range, in: html) {
            styleSheet = String(html[range])
        }
        
        // Extract content between <body> and </body>
        let bodyPattern = "<body>(.*?)</body>"
        var body = html
        if let regex = try? NSRegularExpression(pattern: bodyPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: html) {
            body = String(html[range])
        }
        
        return (styleSheet, body)
    }
    
    private func wrapWithStyle(_ bodyContent: String, styleSheet: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
        \(styleSheet)
        </head>
        <body>
        \(bodyContent)
        </body>
        </html>
        """
    }
}

enum ContentSection {
    case html(String)
    case demo(String)
}

struct InlineContentScrollView: UIViewControllerRepresentable {
    let sections: [ContentSection]
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let onScrolledToEnd: () -> Void
    
    func makeUIViewController(context: Context) -> InlineContentViewController {
        InlineContentViewController(sections: sections, course: course, unitId: unitId, lessonId: lessonId, onScrolledToEnd: onScrolledToEnd)
    }
    
    func updateUIViewController(_ viewController: InlineContentViewController, context: Context) {
        // Update if needed
    }
}

class InlineContentViewController: UIViewController, UIScrollViewDelegate {
    let sections: [ContentSection]
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let onScrolledToEnd: () -> Void
    private var hasNotifiedEnd = false
    private var scrollView: UIScrollView!
    private var stackView: UIStackView!
    
    init(sections: [ContentSection], course: LoadedCourse, unitId: String, lessonId: String, onScrolledToEnd: @escaping () -> Void) {
        self.sections = sections
        self.course = course
        self.unitId = unitId
        self.lessonId = lessonId
        self.onScrolledToEnd = onScrolledToEnd
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        // Add sections to stack view
        for section in sections {
            switch section {
            case .html(let html):
                if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let webView = createHTMLWebView(html: html)
                    stackView.addArrangedSubview(webView)
                }
            case .demo(let demoId):
                let demoHost = createDemoHostController(demoId: demoId)
                addChild(demoHost)
                let container = UIView()
                container.translatesAutoresizingMaskIntoConstraints = false
                demoHost.view.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(demoHost.view)
                NSLayoutConstraint.activate([
                    demoHost.view.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
                    demoHost.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                    demoHost.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                    demoHost.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
                    demoHost.view.heightAnchor.constraint(equalToConstant: 400)
                ])
                stackView.addArrangedSubview(container)
                demoHost.didMove(toParent: self)
            }
        }
    }
    
    private func createHTMLWebView(html: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        // Load HTML and measure height
        let delegate = HTMLWebViewDelegate()
        webView.navigationDelegate = delegate
        // Keep delegate alive by storing in associated object
        objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    private class HTMLWebViewDelegate: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure content height and update constraint
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        // Update height constraint
                        if let heightConstraint = webView.constraints.first(where: { $0.firstAttribute == .height }) {
                            heightConstraint.constant = height
                        } else {
                            webView.heightAnchor.constraint(equalToConstant: height).isActive = true
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
    
    private func createDemoHostController(demoId: String) -> UIHostingController<DemoHostView> {
        let demoView = DemoHostView(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
        return UIHostingController(rootView: demoView)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        checkIfAtEnd(scrollView)
    }
    
    private func checkIfAtEnd(_ scrollView: UIScrollView) {
        guard !hasNotifiedEnd else { return }
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.bounds.height
        let offset = scrollView.contentOffset.y
        let bottomThreshold: CGFloat = 80
        
        // If content fits without scrolling, or user has scrolled near end
        if contentHeight > 0 && (contentHeight <= scrollViewHeight || offset + scrollViewHeight >= contentHeight - bottomThreshold) {
            hasNotifiedEnd = true
            onScrolledToEnd()
        }
    }
}
