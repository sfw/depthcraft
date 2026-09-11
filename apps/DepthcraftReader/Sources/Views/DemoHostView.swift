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
                ScrollView {
                    Text(fallbackMarkdown)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding()
                }
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
        
        // Sandbox: block network requests
        let contentController = WKUserContentController()
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
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
            
            // Read the entry HTML
            var html = try String(contentsOf: entryURL, encoding: .utf8)
            
            // For now, kit injection is a placeholder - the demo should bundle its own Three.js
            // In a production version, we'd inject the kit script here
            // For v0, demos are self-contained with local three.js
            
            webView.loadHTMLString(html, baseURL: demoDir)
            
        } catch {
            onError(error.localizedDescription)
        }
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onError: (String) -> Void
        var lastKey: UUID?
        
        init(onError: @escaping (String) -> Void) {
            self.onError = onError
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Block all external navigation (airplane mode)
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError("Demo failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError("Demo failed to load: \(error.localizedDescription)")
        }
    }
}
