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
        
        // Enable file:// cross-origin access for package-local fetches
        // (allows demo to fetch('./demo.json') from same file:// origin)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Enable WebGL for Three.js demos
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        // Add error handler for runtime failures from JavaScript
        config.userContentController.add(context.coordinator, name: "demoError")
        
        // Inject global error handler to catch uncaught exceptions + kit import failures
        let errorHandlerScript = WKUserScript(
            source: """
            window.addEventListener('error', function(e) {
                // Check for module import failures (especially kit: imports)
                if (e.message && (e.message.includes('Failed to fetch') || 
                                  e.message.includes('Failed to load') ||
                                  e.message.includes('kit:') ||
                                  e.message.includes('import'))) {
                    window.webkit.messageHandlers.demoError.postMessage('Kit import failed: ' + (e.message || 'Unknown error'));
                } else {
                    window.webkit.messageHandlers.demoError.postMessage(e.message || 'Unknown error');
                }
            });
            window.addEventListener('unhandledrejection', function(e) {
                const msg = e.reason?.toString() || 'Promise rejection';
                if (msg.includes('Failed to fetch') || msg.includes('kit:')) {
                    window.webkit.messageHandlers.demoError.postMessage('Kit import failed: ' + msg);
                } else {
                    window.webkit.messageHandlers.demoError.postMessage(msg);
                }
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(errorHandlerScript)
        
        // Create WebView with base config (rules added to live instance later)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.isScrollEnabled = true
        webView.navigationDelegate = context.coordinator
        
        // Store webView for deferred load
        context.coordinator.pendingWebView = webView
        
        // Sandbox: block ALL http(s) resource loads including fetch/XHR
        // url-filter only matches http(s), so file:// loads are unaffected
        let blockRules = """
        [{
            "trigger": {
                "url-filter": "^https?://.*",
                "resource-type": ["script", "image", "style-sheet", "font", "fetch", "raw"]
            },
            "action": {
                "type": "block"
            }
        }]
        """
        
        let coordinator = context.coordinator
        guard let store = WKContentRuleListStore.default() else {
            // WKContentRuleListStore unavailable, load without content rules
            // (navigation delegates still block http/https)
            coordinator.loadDemo(into: webView)
            return webView
        }
        
        store.compileContentRuleList(
            forIdentifier: "DemoSandboxRules",
            encodedContentRuleList: blockRules
        ) { [weak webView] ruleList, error in
            DispatchQueue.main.async {
                guard let webView else { return }
                
                if let ruleList {
                    // Add to LIVE webView's userContentController (not pre-create config)
                    webView.configuration.userContentController.add(ruleList)
                    #if DEBUG
                    print("✅ Content rules added to live webView")
                    #endif
                } else if let error {
                    #if DEBUG
                    print("⚠️ Failed to compile content rules: \(error)")
                    #endif
                }
                
                // Load demo after rules are active (or failed)
                coordinator.loadDemo(into: webView)
            }
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastKey != key {
            context.coordinator.lastKey = key
            context.coordinator.pendingWebView = webView
            context.coordinator.loadDemo(into: webView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId, onError: onError)
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let course: LoadedCourse
        let unitId: String
        let lessonId: String
        let demoId: String
        let onError: (String) -> Void
        var lastKey: UUID?
        var allowedDirectory: URL?
        weak var pendingWebView: WKWebView?
        var contentCheckTimer: Timer?
        
        init(course: LoadedCourse, unitId: String, lessonId: String, demoId: String, onError: @escaping (String) -> Void) {
            self.course = course
            self.unitId = unitId
            self.lessonId = lessonId
            self.demoId = demoId
            self.onError = onError
        }
        
        // Handle error messages from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "demoError", let errorMsg = message.body as? String {
                #if DEBUG
                print("🚫 Demo runtime error: \(errorMsg)")
                #endif
                onError("Demo failed: \(errorMsg)")
            }
        }
        
        func loadDemo(into webView: WKWebView) {
            do {
                let manifest = try PackageLoader.demoManifest(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
                let demoDir = PackageLoader.demoDirectory(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
                let entryURL = demoDir.appendingPathComponent(manifest.entry)
                
                guard FileManager.default.fileExists(atPath: entryURL.path) else {
                    onError("Demo entry file not found")
                    return
                }
                
                // Set allowed directory for sandbox
                allowedDirectory = demoDir
                
                // Use loadFileURL for ES module support (avoids opaque origin issue with loadHTMLString)
                webView.loadFileURL(entryURL, allowingReadAccessTo: demoDir)
                
            } catch {
                onError(error.localizedDescription)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            
            // Allow file:// URLs only within the demo directory
            if url.scheme == "file" {
                if let allowedDir = allowedDirectory {
                    // Once allowedDirectory is set, only allow files within that directory
                    if url.path.hasPrefix(allowedDir.path) {
                        decisionHandler(.allow)
                    } else {
                        #if DEBUG
                        print("🚫 Blocked file outside demo directory: \(url.path)")
                        #endif
                        decisionHandler(.cancel)
                    }
                } else {
                    // Initial load race: allowedDirectory not yet set
                    decisionHandler(.allow)
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
            contentCheckTimer?.invalidate()
            onError("Demo failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            contentCheckTimer?.invalidate()
            onError("Demo failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check after 2 seconds if demo rendered any visible content
            // (detects blank WebGL / JS init failures, kit import failures that don't throw)
            contentCheckTimer?.invalidate()
            contentCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self, weak webView] _ in
                guard let self = self, let webView = webView else { return }
                
                // Check if demo actually rendered meaningful content
                // (not fooled by empty canvas or minimal chrome like "Drag to rotate...")
                webView.evaluateJavaScript("""
                    (function() {
                        const body = document.body;
                        if (!body) return { hasContent: false, reason: 'no body' };
                        
                        // Check for canvas with actual WebGL context and drawing
                        const canvas = body.querySelector('canvas');
                        if (canvas) {
                            try {
                                const gl = canvas.getContext('webgl') || canvas.getContext('webgl2');
                                if (!gl) {
                                    return { hasContent: false, reason: 'canvas but no WebGL context' };
                                }
                                
                                // Check if something was actually drawn (not just black/empty)
                                const pixels = new Uint8Array(4);
                                gl.readPixels(canvas.width / 2, canvas.height / 2, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
                                const hasDrawn = pixels[0] !== 0 || pixels[1] !== 0 || pixels[2] !== 0 || pixels[3] !== 0;
                                
                                if (!hasDrawn) {
                                    return { hasContent: false, reason: 'canvas but nothing drawn' };
                                }
                                
                                return { hasContent: true, reason: 'WebGL content rendered' };
                            } catch (e) {
                                return { hasContent: false, reason: 'canvas error: ' + e.message };
                            }
                        }
                        
                        // Check for non-trivial text content (more than just chrome text)
                        const text = body.innerText?.trim();
                        if (text && text.length > 50) {
                            return { hasContent: true, reason: 'substantial text content' };
                        }
                        
                        // Check for visible non-canvas elements with content
                        const visibleElements = Array.from(body.querySelectorAll('*:not(canvas):not(script):not(style)')).filter(el => {
                            const style = window.getComputedStyle(el);
                            const hasContent = el.innerText?.trim().length > 0 || el.querySelector('img,video');
                            return hasContent && style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
                        });
                        
                        if (visibleElements.length > 2) {
                            return { hasContent: true, reason: 'visible elements' };
                        }
                        
                        return { hasContent: false, reason: 'no meaningful content detected' };
                    })();
                    """) { result, error in
                    if let resultDict = result as? [String: Any],
                       let hasContent = resultDict["hasContent"] as? Bool,
                       !hasContent {
                        let reason = (resultDict["reason"] as? String) ?? "unknown"
                        #if DEBUG
                        print("⚠️ Demo appears blank/failed after load (\(reason)), triggering fallback")
                        #endif
                        self.onError("Demo failed to render or kit unavailable")
                    }
                }
            }
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
