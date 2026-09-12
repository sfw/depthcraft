import SwiftUI
import WebKit

struct ExplainSheet: Identifiable {
    let id = UUID()
    let term: String
    let gloss: String
    let isBakedAnchor: Bool
    let lessonContext: LessonContext?
    
    struct LessonContext {
        let courseTitle: String
        let lessonTitle: String
        let unitId: String
        let lessonId: String
    }
}

struct LessonWebView: UIViewRepresentable {
    let html: String
    let explainAnchors: [LessonMeta.Anchor]
    let lessonContext: ExplainSheet.LessonContext?
    let onScrolledToEnd: () -> Void
    @Binding var explainSheet: ExplainSheet?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable minimal JS for tap-to-explain (offline, no network)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Add message handler for tap events
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "explainTap")
        
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
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        
        context.coordinator.explainSheet = _explainSheet
        context.coordinator.lessonContext = lessonContext
        
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.onScrolledToEnd = onScrolledToEnd
        context.coordinator.explainSheet = _explainSheet
        context.coordinator.explainAnchors = explainAnchors
        context.coordinator.lessonContext = lessonContext
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var onScrolledToEnd: (() -> Void)?
        var explainSheet: Binding<ExplainSheet?>?
        var explainAnchors: [LessonMeta.Anchor] = []
        var lessonContext: ExplainSheet.LessonContext?
        private var hasNotifiedEnd = false
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "explainTap",
                  let body = message.body as? [String: String],
                  let anchorId = body["anchorId"],
                  let term = body["term"] else {
                return
            }
            
            // Look up gloss by anchor ID (baked anchor from Slice A)
            guard let anchor = explainAnchors.first(where: { $0.id == anchorId }),
                  let gloss = anchor.gloss else {
                return
            }
            
            DispatchQueue.main.async {
                self.explainSheet?.wrappedValue = ExplainSheet(
                    term: term,
                    gloss: gloss,
                    isBakedAnchor: true,
                    lessonContext: self.lessonContext
                )
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Airplane-mode: block any navigation away from the loaded HTML (including taps on explain terms, which are handled by JS)
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkIfAtEnd(webView.scrollView)
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
                onScrolledToEnd?()
            }
        }
    }
}
