import SwiftUI
import WebKit

// MARK: - Kit URL Scheme Handler

/// Handles `kit:` URL scheme to serve app-bundled demo kits (e.g. Three.js)
/// Example: `kit:three-v0/three.module.min.js` → `Resources/demo-kits/three-v0/three.module.min.js`
final class KitSchemeHandler: NSObject, WKURLSchemeHandler {
    private let allowedKits: Set<String>
    
    init(allowedKits: Set<String>) {
        self.allowedKits = allowedKits
        super.init()
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -1, userInfo: nil))
            return
        }
        
        // Parse kit:three-v0/three.module.min.js → kitId=three-v0, path=three.module.min.js
        let components = url.absoluteString.dropFirst("kit:".count).split(separator: "/", maxSplits: 1)
        guard components.count == 2 else {
            #if DEBUG
            print("🚫 Invalid kit URL format: \(url.absoluteString)")
            #endif
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid kit URL format"]))
            return
        }
        
        let kitId = String(components[0])
        let resourcePath = String(components[1])
        
        // Reject path escape attempts (.. or absolute paths)
        guard !resourcePath.contains(".."),
              !resourcePath.hasPrefix("/"),
              !resourcePath.contains("://") else {
            #if DEBUG
            print("🚫 Path escape attempt blocked: \(resourcePath)")
            #endif
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -8, userInfo: [NSLocalizedDescriptionKey: "Invalid resource path"]))
            return
        }
        
        // Verify kit is in allowlist
        guard allowedKits.contains(kitId) else {
            #if DEBUG
            print("🚫 Kit not in allowlist: \(kitId)")
            #endif
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -3, userInfo: [NSLocalizedDescriptionKey: "Kit '\(kitId)' not allowed"]))
            return
        }
        
        // Resolve kit file in bundle with multiple fallback paths
        guard let kitFileURL = resolveKitFile(kitId: kitId, resourcePath: resourcePath) else {
            #if DEBUG
            print("🚫 Kit file not found after trying all bundle paths")
            #endif
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -5, userInfo: [NSLocalizedDescriptionKey: "Kit file not found"]))
            return
        }
        
        #if DEBUG
        print("📦 Kit request: \(url.absoluteString) → \(kitFileURL.path)")
        #endif
        
        // Load file data
        guard let data = try? Data(contentsOf: kitFileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -6, userInfo: nil))
            return
        }
        
        // Determine MIME type based on extension
        let mimeType: String
        switch kitFileURL.pathExtension.lowercased() {
        case "js":
            mimeType = "application/javascript"
        case "json":
            mimeType = "application/json"
        case "css":
            mimeType = "text/css"
        case "html":
            mimeType = "text/html"
        default:
            mimeType = "application/octet-stream"
        }
        
        // Create HTTPURLResponse with CORS headers for ES module imports
        // Plain URLResponse is insufficient for cross-scheme module loading
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=31536000"
            ]
        ) else {
            urlSchemeTask.didFailWithError(NSError(domain: "KitSchemeHandler", code: -7, userInfo: nil))
            return
        }
        
        urlSchemeTask.didReceive(httpResponse)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    /// Resolve kit file in bundle with multiple fallback paths
    /// XcodeGen's `type: folder` may nest under Resources/ or copy contents to root
    private func resolveKitFile(kitId: String, resourcePath: String) -> URL? {
        let fm = FileManager.default
        
        // Try 1: resourceURL/demo-kits/{kitId}/{path} (flat copy)
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL
                .appendingPathComponent("demo-kits", isDirectory: true)
                .appendingPathComponent(kitId, isDirectory: true)
                .appendingPathComponent(resourcePath)
            if fm.fileExists(atPath: candidate.path) {
                #if DEBUG
                print("✅ Kit found at resourceURL/demo-kits: \(candidate.path)")
                #endif
                return candidate
            }
        }
        
        // Try 2: resourceURL/Resources/demo-kits/{kitId}/{path} (nested under Resources)
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("demo-kits", isDirectory: true)
                .appendingPathComponent(kitId, isDirectory: true)
                .appendingPathComponent(resourcePath)
            if fm.fileExists(atPath: candidate.path) {
                #if DEBUG
                print("✅ Kit found at resourceURL/Resources/demo-kits: \(candidate.path)")
                #endif
                return candidate
            }
        }
        
        // Try 3: bundleURL/demo-kits/{kitId}/{path}
        let bundleURL = Bundle.main.bundleURL
        let candidate3 = bundleURL
            .appendingPathComponent("demo-kits", isDirectory: true)
            .appendingPathComponent(kitId, isDirectory: true)
            .appendingPathComponent(resourcePath)
        if fm.fileExists(atPath: candidate3.path) {
            #if DEBUG
            print("✅ Kit found at bundleURL/demo-kits: \(candidate3.path)")
            #endif
            return candidate3
        }
        
        // Try 4: path(forResource:ofType:inDirectory:)
        let pathComponents = resourcePath.split(separator: "/")
        if let fileName = pathComponents.last {
            let fileNameStr = String(fileName)
            let directory = "demo-kits/\(kitId)"
            
            // Split filename and extension
            let parts = fileNameStr.split(separator: ".")
            if parts.count >= 2 {
                let name = parts.dropLast().joined(separator: ".")
                let ext = String(parts.last!)
                
                if let candidate = Bundle.main.path(forResource: name, ofType: ext, inDirectory: directory) {
                    #if DEBUG
                    print("✅ Kit found via path(forResource:): \(candidate)")
                    #endif
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        
        #if DEBUG
        print("❌ Kit file not found in any bundle location")
        if let resourceURL = Bundle.main.resourceURL {
            print("   Tried: \(resourceURL.path)/demo-kits/\(kitId)/\(resourcePath)")
            print("   Tried: \(resourceURL.path)/Resources/demo-kits/\(kitId)/\(resourcePath)")
        }
        print("   Tried: \(bundleURL.path)/demo-kits/\(kitId)/\(resourcePath)")
        #endif
        
        return nil
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Task cancelled, nothing to clean up
    }
}

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
        
        // Register kit: URL scheme handler for app-bundled demo kits
        do {
            let manifest = try PackageLoader.demoManifest(course: course, unitId: unitId, lessonId: lessonId, demoId: demoId)
            let kitHandler = KitSchemeHandler(allowedKits: [manifest.kit])
            config.setURLSchemeHandler(kitHandler, forURLScheme: "kit")
            context.coordinator.allowedKitId = manifest.kit
            context.coordinator.kitHandler = kitHandler  // Retain handler
            #if DEBUG
            print("✅ Registered kit: scheme handler for kit '\(manifest.kit)'")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to load demo manifest for kit registration: \(error)")
            #endif
            // Continue without kit handler - will soft-fail if demo tries to use kit:
        }
        
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
        
        // Inject global error handler to catch uncaught exceptions
        let errorHandlerScript = WKUserScript(
            source: """
            window.addEventListener('error', function(e) {
                window.webkit.messageHandlers.demoError.postMessage(e.message || 'Unknown error');
            });
            window.addEventListener('unhandledrejection', function(e) {
                window.webkit.messageHandlers.demoError.postMessage(e.reason?.toString() || 'Promise rejection');
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
        var allowedKitId: String?
        var kitHandler: KitSchemeHandler?  // Retain scheme handler
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
            
            // Allow kit: URLs (handled by custom scheme handler)
            if url.scheme == "kit" {
                decisionHandler(.allow)
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
            // (detects blank WebGL / JS init failures that don't throw to didFail)
            contentCheckTimer?.invalidate()
            contentCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self, weak webView] _ in
                guard let self = self, let webView = webView else { return }
                
                // Check if body has any visible child elements (canvas, divs with content, etc.)
                webView.evaluateJavaScript("""
                    (function() {
                        const body = document.body;
                        if (!body) return false;
                        
                        // Check for canvas (WebGL demos)
                        if (body.querySelector('canvas')) return true;
                        
                        // Check for non-empty text content
                        const text = body.innerText?.trim();
                        if (text && text.length > 0) return true;
                        
                        // Check for visible elements
                        const visibleElements = Array.from(body.querySelectorAll('*')).filter(el => {
                            const style = window.getComputedStyle(el);
                            return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
                        });
                        return visibleElements.length > 0;
                    })();
                    """) { result, error in
                    if let hasContent = result as? Bool, !hasContent {
                        #if DEBUG
                        print("⚠️ Demo appears blank after load, triggering fallback")
                        #endif
                        self.onError("Demo failed to render")
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
