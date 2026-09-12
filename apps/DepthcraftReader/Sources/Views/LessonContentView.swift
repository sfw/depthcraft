import SwiftUI
import WebKit

struct LessonContentView: View {
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let renderResult: LessonRenderResult
    let onScrolledToEnd: () -> Void
    
    @State private var explainSheet: ExplainSheet?
    
    var body: some View {
        Group {
            if renderResult.demos.isEmpty {
                // No demos - use simple web view
                LessonWebView(
                    html: renderResult.html,
                    explainAnchors: renderResult.explainAnchors,
                    onScrolledToEnd: onScrolledToEnd,
                    explainSheet: $explainSheet
                )
            } else {
                // Has demos - embed them inline at :::demo::: directive positions
                inlineLayout
            }
        }
        .sheet(item: $explainSheet) { sheet in
            ExplanationSheetView(term: sheet.term, gloss: sheet.gloss)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    private var inlineLayout: some View {
        let sections = splitHTMLAtDemoPlaceholders(html: renderResult.html, demos: renderResult.demos)
        
        return InlineContentScrollView(
            sections: sections,
            course: course,
            unitId: unitId,
            lessonId: lessonId,
            explainAnchors: renderResult.explainAnchors,
            explainSheet: $explainSheet,
            onScrolledToEnd: onScrolledToEnd
        )
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
    let explainAnchors: [LessonMeta.Anchor]
    @Binding var explainSheet: ExplainSheet?
    let onScrolledToEnd: () -> Void
    
    func makeUIViewController(context: Context) -> InlineContentViewController {
        InlineContentViewController(
            sections: sections,
            course: course,
            unitId: unitId,
            lessonId: lessonId,
            explainAnchors: explainAnchors,
            explainSheet: $explainSheet,
            onScrolledToEnd: onScrolledToEnd
        )
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
    let explainAnchors: [LessonMeta.Anchor]
    var explainSheet: Binding<ExplainSheet?>
    let onScrolledToEnd: () -> Void
    private var hasNotifiedEnd = false
    private var scrollView: UIScrollView!
    private var stackView: UIStackView!
    
    init(sections: [ContentSection], course: LoadedCourse, unitId: String, lessonId: String, explainAnchors: [LessonMeta.Anchor], explainSheet: Binding<ExplainSheet?>, onScrolledToEnd: @escaping () -> Void) {
        self.sections = sections
        self.course = course
        self.unitId = unitId
        self.lessonId = lessonId
        self.explainAnchors = explainAnchors
        self.explainSheet = explainSheet
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
        // Enable JS for height measurement and tap-to-explain (navigation still locked down)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Add message handler for explain taps
        let contentController = config.userContentController
        let tapHandler = ExplainTapHandler(explainSheet: explainSheet, explainAnchors: explainAnchors)
        contentController.add(tapHandler, name: "explainTap")
        
        // Inject tap handler script
        let tapScript = WKUserScript(
            source: """
            document.addEventListener('click', function(e) {
                const target = e.target.closest('.explain-term');
                if (target) {
                    e.preventDefault();
                    const anchorId = target.getAttribute('data-anchor-id');
                    const term = target.textContent;
                    window.webkit.messageHandlers.explainTap.postMessage({
                        anchorId: anchorId,
                        term: term
                    });
                }
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(tapScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set provisional height so layout isn't 0 until measure returns
        let provisionalHeight: CGFloat = 200
        webView.heightAnchor.constraint(equalToConstant: provisionalHeight).isActive = true
        
        // Load HTML and measure height
        let delegate = HTMLWebViewDelegate()
        webView.navigationDelegate = delegate
        // Keep delegate alive by storing in associated object
        objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(webView, "tapHandler", tapHandler, .OBJC_ASSOCIATION_RETAIN)
        
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    private class ExplainTapHandler: NSObject, WKScriptMessageHandler {
        var explainSheet: Binding<ExplainSheet?>
        var explainAnchors: [LessonMeta.Anchor]
        
        init(explainSheet: Binding<ExplainSheet?>, explainAnchors: [LessonMeta.Anchor]) {
            self.explainSheet = explainSheet
            self.explainAnchors = explainAnchors
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "explainTap",
                  let body = message.body as? [String: String],
                  let anchorId = body["anchorId"],
                  let term = body["term"] else {
                return
            }
            
            // Look up gloss by anchor ID
            guard let anchor = explainAnchors.first(where: { $0.id == anchorId }),
                  let gloss = anchor.gloss else {
                return
            }
            
            DispatchQueue.main.async {
                self.explainSheet.wrappedValue = ExplainSheet(term: term, gloss: gloss)
            }
        }
    }
    
    private class HTMLWebViewDelegate: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure content height and update constraint
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                var height: CGFloat = 0
                
                // Robust casting for JS return value (may be Double, NSNumber, Int, etc.)
                if let doubleValue = result as? Double {
                    height = CGFloat(doubleValue)
                } else if let numberValue = result as? NSNumber {
                    height = CGFloat(truncating: numberValue)
                } else if let intValue = result as? Int {
                    height = CGFloat(intValue)
                } else if let cgfloatValue = result as? CGFloat {
                    height = cgfloatValue
                }
                
                if height > 0 {
                    DispatchQueue.main.async {
                        // Update height constraint
                        if let heightConstraint = webView.constraints.first(where: { $0.firstAttribute == .height }) {
                            heightConstraint.constant = height
                        } else {
                            webView.heightAnchor.constraint(equalToConstant: height).isActive = true
                        }
                        webView.layoutIfNeeded()
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // After layout settles, check if content fits
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.checkIfAtEnd(self.scrollView)
        }
    }
    
    private func checkIfAtEnd(_ scrollView: UIScrollView) {
        guard !hasNotifiedEnd else { return }
        let contentHeight = scrollView.contentSize.height
        let scrollViewHeight = scrollView.bounds.height
        let offset = scrollView.contentOffset.y
        let bottomThreshold: CGFloat = 80
        
        // Only fire if:
        // 1. Content fits without scrolling (after layout settles), OR
        // 2. User has scrolled near end
        // Match LessonWebView: content must be measured (contentHeight > 0) and either fit or scrolled
        if contentHeight > 0 {
            if contentHeight <= scrollViewHeight {
                // Content fits - only mark read after layout settles (viewDidLayoutSubviews)
                // Don't fire on first scrollViewDidScroll before content is laid out
                if scrollView.contentSize != .zero {
                    hasNotifiedEnd = true
                    onScrolledToEnd()
                }
            } else if offset + scrollViewHeight >= contentHeight - bottomThreshold {
                // User scrolled near bottom
                hasNotifiedEnd = true
                onScrolledToEnd()
            }
        }
    }
}

struct ExplanationSheetView: View {
    let term: String
    let gloss: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(parseMarkdown(gloss))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}
