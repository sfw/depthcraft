import SwiftUI
import WebKit

struct LessonContentView: View {
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let renderResult: LessonRenderResult
    let onScrolledToEnd: () -> Void
    
    @State private var explainSheet: ExplainSheet?
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @StateObject private var apiKeyStore = APIKeyStore()
    
    private var lessonContext: ExplainSheet.LessonContext {
        ExplainSheet.LessonContext(
            courseTitle: course.manifest.title,
            lessonTitle: course.curriculum.lessons[lessonId]?.title ?? "Lesson",
            unitId: unitId,
            lessonId: lessonId
        )
    }
    
    private var configService: LLMConfigService {
        LLMConfigService(apiKeyStore: apiKeyStore)
    }
    
    private var glossService: GlossService {
        GlossService(configService: configService)
    }
    
    var body: some View {
        Group {
            if renderResult.demos.isEmpty {
                // No demos - use simple web view
                LessonWebView(
                    html: renderResult.html,
                    explainAnchors: renderResult.explainAnchors,
                    lessonContext: lessonContext,
                    isOnline: networkMonitor.isOnline,
                    glossService: glossService,
                    onScrolledToEnd: onScrolledToEnd,
                    explainSheet: $explainSheet
                )
            } else {
                // Has demos - embed them inline at :::demo::: directive positions
                inlineLayout
            }
        }
        .sheet(item: $explainSheet) { sheet in
            ExplanationSheetView(
                term: sheet.term,
                gloss: sheet.gloss,
                lessonContext: sheet.lessonContext
            )
            .presentationDetents([.medium, .large])
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
            lessonContext: lessonContext,
            isOnline: networkMonitor.isOnline,
            glossService: glossService,
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
    let lessonContext: ExplainSheet.LessonContext
    let isOnline: Bool
    let glossService: GlossService
    @Binding var explainSheet: ExplainSheet?
    let onScrolledToEnd: () -> Void
    
    func makeUIViewController(context: Context) -> InlineContentViewController {
        InlineContentViewController(
            sections: sections,
            course: course,
            unitId: unitId,
            lessonId: lessonId,
            explainAnchors: explainAnchors,
            lessonContext: lessonContext,
            isOnline: isOnline,
            glossService: glossService,
            explainSheet: $explainSheet,
            onScrolledToEnd: onScrolledToEnd
        )
    }
    
    func updateUIViewController(_ viewController: InlineContentViewController, context: Context) {
        viewController.isOnline = isOnline
        viewController.updateDelegatesOnlineState()
    }
}

class InlineContentViewController: UIViewController, UIScrollViewDelegate {
    let sections: [ContentSection]
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let explainAnchors: [LessonMeta.Anchor]
    let lessonContext: ExplainSheet.LessonContext
    var isOnline: Bool
    let glossService: GlossService
    var explainSheet: Binding<ExplainSheet?>
    let onScrolledToEnd: () -> Void
    private var hasNotifiedEnd = false
    private var scrollView: UIScrollView!
    private var stackView: UIStackView!
    
    init(sections: [ContentSection], course: LoadedCourse, unitId: String, lessonId: String, explainAnchors: [LessonMeta.Anchor], lessonContext: ExplainSheet.LessonContext, isOnline: Bool, glossService: GlossService, explainSheet: Binding<ExplainSheet?>, onScrolledToEnd: @escaping () -> Void) {
        self.sections = sections
        self.course = course
        self.unitId = unitId
        self.lessonId = lessonId
        self.explainAnchors = explainAnchors
        self.lessonContext = lessonContext
        self.isOnline = isOnline
        self.glossService = glossService
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
    
    func updateDelegatesOnlineState() {
        // Update isOnline in all WebView delegates
        for view in stackView.arrangedSubviews {
            if let webView = view as? WKWebView {
                // Update delegate
                if let delegate = objc_getAssociatedObject(webView, "delegate") as? HTMLWebViewDelegate {
                    delegate.isOnline = isOnline
                }
                // Update tap handler
                if let tapHandler = objc_getAssociatedObject(webView, "tapHandler") as? ExplainTapHandler {
                    tapHandler.isOnline = isOnline
                }
            }
        }
    }
    
    private func createHTMLWebView(html: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Enable JS for height measurement and tap-to-explain (navigation still locked down)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Disable system text interaction (we own selection via paint/double-tap/baked)
        if #available(iOS 14.5, *) {
            config.preferences.isTextInteractionEnabled = false
        }
        
        // Add message handlers
        let contentController = config.userContentController
        let tapHandler = ExplainTapHandler(
            explainSheet: explainSheet,
            explainAnchors: explainAnchors,
            lessonContext: lessonContext,
            isOnline: isOnline,
            glossService: glossService
        )
        contentController.add(tapHandler, name: "explainTap")
        contentController.add(tapHandler, name: "paintSelection")
        contentController.add(tapHandler, name: "clearPaint")
        
        // Inject paint selection script (same as LessonWebView)
        let paintScript = WKUserScript(
            source: """
            (function() {
                // Teal ink paint selection system
                let paintStartAnchor = null;  // Stable start position (no DOM mutation during gesture)
                let currentPaintRange = null; // Current range being painted
                let paintHighlight = null;    // CSS Highlight API highlight
                let isSelecting = false;
                
                // Create floating capsule
                const capsule = document.createElement('div');
                capsule.id = 'explain-capsule';
                capsule.textContent = 'Release to explain';
                capsule.style.cssText = `
                    position: fixed;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    background: rgba(20, 184, 166, 0.95);
                    color: white;
                    padding: 8px 16px;
                    border-radius: 20px;
                    font-size: 14px;
                    font-weight: 500;
                    pointer-events: none;
                    z-index: 10000;
                    display: none;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.2);
                `;
                document.body.appendChild(capsule);
                
                // Suppress system text selection during paint gesture
                function suppressSystemSelection() {
                    // Clear any existing selection
                    const selection = window.getSelection();
                    if (selection) {
                        selection.removeAllRanges();
                    }
                    // Add user-select: none to body
                    document.body.style.webkitUserSelect = 'none';
                    document.body.style.userSelect = 'none';
                }
                
                function restoreSystemSelection() {
                    document.body.style.webkitUserSelect = '';
                    document.body.style.userSelect = '';
                }
                
                // Add CSS for highlight API
                const style = document.createElement('style');
                style.textContent = `
                    ::highlight(teal-ink-paint) {
                        background-color: rgba(20, 184, 166, 0.3);
                        border-radius: 2px;
                    }
                `;
                document.head.appendChild(style);
                
                // Apply teal ink highlight using CSS Highlight API (no DOM mutation)
                function applyPaintHighlight(range) {
                    if (!range) return;
                    
                    currentPaintRange = range.cloneRange();
                    
                    // Use CSS Highlight API (no DOM mutation during gesture)
                    if (CSS.highlights) {
                        paintHighlight = new Highlight(currentPaintRange);
                        CSS.highlights.set('teal-ink-paint', paintHighlight);
                    } else {
                        // Fallback for older browsers: use inline span (only during gesture)
                        clearSpanHighlights();
                        const span = document.createElement('span');
                        span.className = 'teal-ink-paint-fallback';
                        span.style.cssText = `
                            background-color: rgba(20, 184, 166, 0.3);
                            border-radius: 2px;
                            padding: 2px 0;
                        `;
                        try {
                            const fallbackRange = range.cloneRange();
                            fallbackRange.surroundContents(span);
                        } catch(e) {
                            // Ignore fallback errors
                        }
                    }
                }
                
                function clearSpanHighlights() {
                    // Only clear span fallback highlights (not final wrapped span)
                    const painted = document.querySelectorAll('.teal-ink-paint-fallback');
                    painted.forEach(span => {
                        const parent = span.parentNode;
                        if (parent) {
                            while (span.firstChild) {
                                parent.insertBefore(span.firstChild, span);
                            }
                            parent.removeChild(span);
                        }
                    });
                }
                
                function clearPaint() {
                    // Clear CSS Highlight API
                    if (CSS.highlights) {
                        CSS.highlights.clear();
                    }
                    // Clear fallback spans
                    clearSpanHighlights();
                    // Clear any final wrapped spans from previous gestures
                    const finalSpans = document.querySelectorAll('.teal-ink-paint');
                    finalSpans.forEach(span => {
                        const parent = span.parentNode;
                        if (parent) {
                            while (span.firstChild) {
                                parent.insertBefore(span.firstChild, span);
                            }
                            parent.removeChild(span);
                            parent.normalize();
                        }
                    });
                    currentPaintRange = null;
                    paintStartAnchor = null;
                    paintHighlight = null;
                }
                
                function getWordBoundaryRange(node, offset) {
                    if (node.nodeType !== Node.TEXT_NODE) return null;
                    
                    const text = node.textContent;
                    const wordPattern = /\\b[\\w']+\\b/g;
                    let match;
                    
                    while ((match = wordPattern.exec(text)) !== null) {
                        if (offset >= match.index && offset <= match.index + match[0].length) {
                            const range = document.createRange();
                            range.setStart(node, match.index);
                            range.setEnd(node, match.index + match[0].length);
                            return range;
                        }
                    }
                    return null;
                }
                
                function expandToWordBoundaries(startNode, startOffset, endNode, endOffset) {
                    const range = document.createRange();
                    
                    // Find word boundaries
                    let startRange = getWordBoundaryRange(startNode, startOffset);
                    let endRange = getWordBoundaryRange(endNode, endOffset);
                    
                    if (startRange && endRange) {
                        range.setStart(startRange.startContainer, startRange.startOffset);
                        range.setEnd(endRange.endContainer, endRange.endOffset);
                    } else {
                        range.setStart(startNode, startOffset);
                        range.setEnd(endNode, endOffset);
                    }
                    
                    return range;
                }
                
                // Handle baked explain terms
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
                    } else {
                        // Tap outside - clear paint
                        window.webkit.messageHandlers.clearPaint.postMessage({});
                    }
                });
                
                // Expose functions for native gesture handling
                window.startPaintSelection = function(x, y) {
                    const point = document.elementFromPoint(x, y);
                    if (!point) return;
                    
                    const range = document.caretRangeFromPoint(x, y);
                    if (!range) return;
                    
                    isSelecting = true;
                    
                    // Suppress system blue selection immediately
                    suppressSystemSelection();
                    
                    // Show capsule
                    capsule.style.display = 'block';
                    
                    const wordRange = getWordBoundaryRange(range.startContainer, range.startOffset);
                    if (wordRange) {
                        // Store stable start position (no DOM mutation yet, so node stays valid)
                        paintStartAnchor = {
                            node: wordRange.startContainer,
                            offset: wordRange.startOffset
                        };
                        applyPaintHighlight(wordRange);
                    }
                };
                
                window.updatePaintSelection = function(x, y) {
                    if (!isSelecting || !paintStartAnchor) return;
                    
                    // Keep suppressing system selection during drag
                    suppressSystemSelection();
                    
                    const currentRange = document.caretRangeFromPoint(x, y);
                    if (!currentRange) return;
                    
                    // No DOM mutation during gesture, so nodes stay valid
                    try {
                        // Create fresh range from stable start to current end (word boundaries)
                        const expandedRange = expandToWordBoundaries(
                            paintStartAnchor.node,
                            paintStartAnchor.offset,
                            currentRange.startContainer,
                            currentRange.startOffset
                        );
                        
                        // Update highlight (no DOM mutation via CSS Highlight API)
                        applyPaintHighlight(expandedRange);
                    } catch(e) {
                        console.warn('Paint update failed:', e);
                    }
                };
                
                window.endPaintSelection = function() {
                    isSelecting = false;
                    capsule.style.display = 'none';
                    
                    // Restore system selection after gesture
                    restoreSystemSelection();
                    
                    if (currentPaintRange) {
                        const text = currentPaintRange.toString().trim();
                        if (text.length > 0 && text.length <= 200) {
                            window.webkit.messageHandlers.paintSelection.postMessage({ text: text });
                        }
                    }
                };
                
                window.clearPaintSelection = function() {
                    isSelecting = false;
                    capsule.style.display = 'none';
                    
                    // Restore system selection
                    restoreSystemSelection();
                    
                    clearPaint();
                };
                
                // Double-tap detection
                let lastTapTime = 0;
                let lastTapX = 0;
                let lastTapY = 0;
                
                document.addEventListener('touchstart', function(e) {
                    const now = Date.now();
                    const touch = e.touches[0];
                    
                    if (now - lastTapTime < 300 && 
                        Math.abs(touch.clientX - lastTapX) < 20 &&
                        Math.abs(touch.clientY - lastTapY) < 20) {
                        
                        // Double-tap detected
                        e.preventDefault();
                        
                        const range = document.caretRangeFromPoint(touch.clientX, touch.clientY);
                        if (range) {
                            const wordRange = getWordBoundaryRange(range.startContainer, range.startOffset);
                            if (wordRange) {
                                applyPaintHighlight(wordRange);
                                const text = wordRange.toString().trim();
                                if (text.length > 0 && text.length <= 200) {
                                    window.webkit.messageHandlers.paintSelection.postMessage({ text: text });
                                }
                            }
                        }
                        
                        lastTapTime = 0;
                    } else {
                        lastTapTime = now;
                        lastTapX = touch.clientX;
                        lastTapY = touch.clientY;
                    }
                }, { passive: false });
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(paintScript)
        
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
        let delegate = HTMLWebViewDelegate(
            isOnline: isOnline,
            glossService: glossService,
            explainSheet: explainSheet,
            lessonContext: lessonContext
        )
        webView.navigationDelegate = delegate
        
        // Wire up webView and delegate references (fix #1: enable clearPaint)
        tapHandler.webView = webView
        tapHandler.delegate = delegate
        
        // Keep delegate alive by storing in associated object
        objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(webView, "tapHandler", tapHandler, .OBJC_ASSOCIATION_RETAIN)
        
        // Add long-press gesture
        let longPress = UILongPressGestureRecognizer(target: delegate, action: #selector(delegate.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = delegate
        webView.addGestureRecognizer(longPress)
        delegate.webView = webView
        
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    private class ExplainTapHandler: NSObject, WKScriptMessageHandler {
        var explainSheet: Binding<ExplainSheet?>
        var explainAnchors: [LessonMeta.Anchor]
        var lessonContext: ExplainSheet.LessonContext
        var isOnline: Bool
        var glossService: GlossService
        weak var webView: WKWebView?
        weak var delegate: HTMLWebViewDelegate?
        
        init(explainSheet: Binding<ExplainSheet?>, explainAnchors: [LessonMeta.Anchor], lessonContext: ExplainSheet.LessonContext, isOnline: Bool, glossService: GlossService) {
            self.explainSheet = explainSheet
            self.explainAnchors = explainAnchors
            self.lessonContext = lessonContext
            self.isOnline = isOnline
            self.glossService = glossService
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "explainTap" {
                // Baked anchor tap (Slice A)
                guard let body = message.body as? [String: String],
                      let anchorId = body["anchorId"],
                      let term = body["term"] else {
                    return
                }
                
                guard let anchor = explainAnchors.first(where: { $0.id == anchorId }),
                      let gloss = anchor.gloss else {
                    return
                }
                
                DispatchQueue.main.async {
                    self.explainSheet.wrappedValue = ExplainSheet(
                        term: term,
                        gloss: gloss,
                        lessonContext: self.lessonContext
                    )
                    self.clearPaint()
                }
            } else if message.name == "paintSelection" {
                // Paint selection completed (long-press or double-tap)
                guard let body = message.body as? [String: String],
                      let text = body["text"] else {
                    return
                }
                
                DispatchQueue.main.async {
                    self.explainText(text)
                }
            } else if message.name == "clearPaint" {
                // Clear paint (tap outside / Done)
                clearPaint()
            }
        }
        
        private func explainText(_ text: String) {
            // Check online + BYOK
            guard isOnline, glossService.hasAPIKey() else {
                // Offline - show toast (fix #2: offline double-tap)
                delegate?.showOfflineToast()
                clearPaint()
                return
            }
            
            Task { @MainActor in
                do {
                    let contextString = "\(lessonContext.courseTitle) — \(lessonContext.lessonTitle)"
                    let gloss = try await glossService.generateGloss(for: text, lessonContext: contextString)
                    
                    self.explainSheet.wrappedValue = ExplainSheet(
                        term: text,
                        gloss: gloss,
                        lessonContext: self.lessonContext
                    )
                    // Fix #3: Clear paint after successful explain
                    self.clearPaint()
                } catch {
                    self.explainSheet.wrappedValue = ExplainSheet(
                        term: text,
                        gloss: "**Error generating explanation:** \(error.localizedDescription)",
                        lessonContext: self.lessonContext
                    )
                    self.clearPaint()
                }
            }
        }
        
        private func clearPaint() {
            // Fix #1: Actually clear paint in inline path
            webView?.evaluateJavaScript("window.clearPaintSelection()") { _, _ in }
        }
    }
    
    private class HTMLWebViewDelegate: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var isOnline: Bool
        var glossService: GlossService
        var explainSheet: Binding<ExplainSheet?>
        var lessonContext: ExplainSheet.LessonContext
        weak var webView: WKWebView?
        private var offlineToastWorkItem: DispatchWorkItem?
        
        init(isOnline: Bool, glossService: GlossService, explainSheet: Binding<ExplainSheet?>, lessonContext: ExplainSheet.LessonContext) {
            self.isOnline = isOnline
            self.glossService = glossService
            self.explainSheet = explainSheet
            self.lessonContext = lessonContext
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            
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
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let webView = webView else { return }
            
            let location = gesture.location(in: webView)
            
            switch gesture.state {
            case .began:
                // Haptic feedback
                let feedback = UIImpactFeedbackGenerator(style: .medium)
                feedback.impactOccurred()
                
                // Start paint selection
                webView.evaluateJavaScript("window.startPaintSelection(\(location.x), \(location.y))") { _, _ in }
                
            case .changed:
                // Update paint selection as user drags
                webView.evaluateJavaScript("window.updatePaintSelection(\(location.x), \(location.y))") { _, _ in }
                
            case .ended:
                // End paint selection and trigger explain
                webView.evaluateJavaScript("window.endPaintSelection()") { _, _ in }
                
                // Check if we need to show offline toast
                if !isOnline || !glossService.hasAPIKey() {
                    showOfflineToast()
                    clearPaint()
                }
                
            case .cancelled, .failed:
                // Clear paint
                clearPaint()
                
            default:
                break
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
        
        private func clearPaint() {
            webView?.evaluateJavaScript("window.clearPaintSelection()") { _, _ in }
        }
        
        func showOfflineToast() {
            guard let webView = webView else { return }
            
            // Cancel any existing toast
            offlineToastWorkItem?.cancel()
            
            // Create toast view
            let toast = UILabel()
            toast.text = "Explain needs a connection"
            toast.textColor = .white
            toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            toast.textAlignment = .center
            toast.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            toast.layer.cornerRadius = 8
            toast.clipsToBounds = true
            toast.translatesAutoresizingMaskIntoConstraints = false
            toast.alpha = 0
            
            // Find the scroll view to add toast to
            var targetView: UIView = webView
            if let scrollView = webView.superview?.superview as? UIScrollView {
                targetView = scrollView
            }
            
            targetView.addSubview(toast)
            
            NSLayoutConstraint.activate([
                toast.centerXAnchor.constraint(equalTo: targetView.centerXAnchor),
                toast.bottomAnchor.constraint(equalTo: targetView.safeAreaLayoutGuide.bottomAnchor, constant: -40),
                toast.heightAnchor.constraint(equalToConstant: 36),
                toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
            ])
            
            // Animate in
            UIView.animate(withDuration: 0.3) {
                toast.alpha = 1.0
            }
            
            // Dismiss after 2 seconds
            let workItem = DispatchWorkItem {
                UIView.animate(withDuration: 0.3, animations: {
                    toast.alpha = 0
                }) { _ in
                    toast.removeFromSuperview()
                }
            }
            
            offlineToastWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
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
    let lessonContext: ExplainSheet.LessonContext?
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var store: CourseStore
    @State private var showDiscuss = false
    
    private var canDiscuss: Bool {
        networkMonitor.isOnline && lessonContext != nil
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(parseMarkdown(gloss))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                    
                    if canDiscuss {
                        Button {
                            showDiscuss = true
                        } label: {
                            Label("Discuss", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .padding(.top, 8)
                    } else if !networkMonitor.isOnline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .foregroundStyle(.secondary)
                            Text("Discuss requires an internet connection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
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
            .sheet(isPresented: $showDiscuss) {
                if let context = lessonContext {
                    DiscussView(
                        term: term,
                        initialGloss: gloss,
                        lessonContext: context
                    )
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
