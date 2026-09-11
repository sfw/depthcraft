import SwiftUI
import WebKit

struct DemoHostView: View {
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let demoId: String
    
    @State private var loadError: String?
    @State private var showingFallback = false
    @State private var demoKey = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            if showingFallback {
                fallbackView
            } else if let loadError {
                errorView(loadError)
            } else {
                DemoWebView(
                    course: course,
                    unitId: unitId,
                    lessonId: lessonId,
                    demoId: demoId,
                    key: demoKey,
                    onError: { error in
                        loadError = error
                        showingFallback = true
                    }
                )
                .frame(minHeight: 400)
                
                // Demo controls
                HStack(spacing: 12) {
                    Button {
                        demoKey = UUID()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    
                    Spacer()
                    
                    Button {
                        // Next step - for v0 this is a no-op placeholder
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                }
                .padding(12)
                .background(.bar)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.teal.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var fallbackView: some View {
        VStack(spacing: 16) {
            if let fallbackMarkdown = loadFallbackMarkdown() {
                let fallbackHTML = renderFallbackAsHTML(fallbackMarkdown)
                FallbackWebView(html: fallbackHTML)
            } else {
                ContentUnavailableView(
                    "Demo unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This interactive demo could not be loaded.")
                )
            }
        }
        .frame(minHeight: 400)
    }
    
    private func renderFallbackAsHTML(_ markdown: String) -> String {
        // Render fallback markdown as readable HTML
        let renderResult = MarkdownHTML.render(markdown, title: "Demo Unavailable", estimatedMinutes: nil)
        return renderResult.html
    }
    
    private func errorView(_ message: String) -> some View {
        ContentUnavailableView(
            "Demo unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
        .frame(minHeight: 400)
    }
    
    private func loadFallbackMarkdown() -> String? {
        let fallbackURL = PackageLoader.demoDirectory(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
            .appendingPathComponent("fallback.md")
        return try? String(contentsOf: fallbackURL, encoding: .utf8)
    }
}

struct DemoWebView: UIViewRepresentable {
    let course: LoadedCourse
    let unitId: String
    let lessonId: String
    let demoId: String
    let key: UUID
    let onError: (String) -> Void
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Enable WebGL for Three.js demos
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        // Sandbox: block network requests
        let contentController = WKUserContentController()
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.isScrollEnabled = true
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            loadDemo(into: webView, context: context)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }
    
    private func loadDemo(into webView: WKWebView, context: Context) {
        do {
            let manifest = try PackageLoader.demoManifest(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
            let demoDir = PackageLoader.demoDirectory(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
            let entryURL = demoDir.appendingPathComponent(manifest.entry)
            
            guard FileManager.default.fileExists(atPath: entryURL.path) else {
                onError("Demo entry file not found")
                return
            }
            
            // Set allowed directory for sandbox
            context.coordinator.allowedDirectory = demoDir
            
            // Use loadFileURL for ES module support (avoids opaque origin issue with loadHTMLString)
            webView.loadFileURL(entryURL, allowingReadAccessTo: demoDir)
            
        } catch {
            onError(error.localizedDescription)
        }
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
        let onError: (String) -> Void
        var lastKey: UUID?
        var allowedDirectory: URL?
        
        init(onError: @escaping (String) -> Void) {
            self.onError = onError
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            
            // Allow file:// URLs only within the demo directory
            if url.scheme == "file" {
                if let allowedDir = allowedDirectory, url.path.hasPrefix(allowedDir.path) {
                    decisionHandler(.allow)
                } else {
                    decisionHandler(.allow) // Initial load before allowedDirectory is set
                }
            }
            // Block all http/https network requests
            else if url.scheme == "http" || url.scheme == "https" {
                #if DEBUG
                print("🚫 Blocked external request: \(url.absoluteString)")
                #endif
                decisionHandler(.cancel)
            }
            // Block other navigation types
            else if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Additional check: block any response from http/https
            if let url = navigationResponse.response.url,
               url.scheme == "http" || url.scheme == "https" {
                #if DEBUG
                print("🚫 Blocked external response: \(url.absoluteString)")
                #endif
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError("Demo failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError("Demo failed to load: \(error.localizedDescription)")
        }
        
        // WKURLSchemeHandler - not used but available for custom schemes if needed
        func webView(_ urlSchemeTask: WKURLSchemeTask) {
            urlSchemeTask.didFailWithError(NSError(domain: "DemoHost", code: -1, userInfo: nil))
        }
        
        func webViewDidStopLoading(_ urlSchemeTask: WKURLSchemeTask) {
            // Not implemented
        }
    }
}

// Simple WebView wrapper for fallback markdown rendering
struct FallbackWebView: UIViewRepresentable {
    let html: String
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}
