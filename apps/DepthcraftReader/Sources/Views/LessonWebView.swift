import SwiftUI
import WebKit

struct LessonWebView: UIViewRepresentable {
    let html: String
    let onScrolledToEnd: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.onScrolledToEnd = onScrolledToEnd
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var lastHTML: String?
        var onScrolledToEnd: (() -> Void)?
        private var hasNotifiedEnd = false

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Airplane-mode: block any navigation away from the loaded HTML.
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
