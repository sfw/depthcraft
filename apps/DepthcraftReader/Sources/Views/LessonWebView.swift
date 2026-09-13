import SwiftUI
import WebKit

struct ExplainSheet: Identifiable {
    let id = UUID()
    let term: String
    let gloss: String
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
    let lessonContext: ExplainSheet.LessonContext
    let isOnline: Bool
    let glossService: GlossService
    let onScrolledToEnd: () -> Void
    @Binding var explainSheet: ExplainSheet?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable minimal JS for tap-to-explain (offline, no network)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Add message handlers
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "explainTap")
        contentController.add(context.coordinator, name: "paintSelection")
        contentController.add(context.coordinator, name: "clearPaint")
        
        // Inject paint selection script
        let paintScript = WKUserScript(
            source: """
            (function() {
                // Teal ink paint selection system
                let paintStartAnchor = null;  // Stable start position (survives DOM mutations)
                let paintedRange = null;      // Current painted range (for extraction)
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
                
                // Apply teal ink highlight (fix: clear first, then re-apply fresh)
                function applyPaint(range) {
                    if (!range) return;
                    
                    // Clear all existing highlights first
                    const painted = document.querySelectorAll('.teal-ink-paint');
                    painted.forEach(span => {
                        const parent = span.parentNode;
                        if (parent) {
                            while (span.firstChild) {
                                parent.insertBefore(span.firstChild, span);
                            }
                            parent.removeChild(span);
                            parent.normalize();
                        }
                    });
                    
                    // Clone range to avoid mutation issues
                    const freshRange = range.cloneRange();
                    paintedRange = freshRange;
                    
                    // Apply new highlight
                    const span = document.createElement('span');
                    span.className = 'teal-ink-paint';
                    span.style.cssText = `
                        background-color: rgba(20, 184, 166, 0.3);
                        border-radius: 2px;
                        padding: 2px 0;
                    `;
                    
                    try {
                        freshRange.surroundContents(span);
                    } catch(e) {
                        // If surroundContents fails (crosses element boundaries), use extraction
                        try {
                            const contents = freshRange.extractContents();
                            span.appendChild(contents);
                            freshRange.insertNode(span);
                        } catch(err) {
                            // Fallback: just highlight what we can
                            console.warn('Paint highlight failed:', err);
                        }
                    }
                }
                
                function clearPaint() {
                    const painted = document.querySelectorAll('.teal-ink-paint');
                    painted.forEach(span => {
                        const parent = span.parentNode;
                        if (parent) {
                            while (span.firstChild) {
                                parent.insertBefore(span.firstChild, span);
                            }
                            parent.removeChild(span);
                            parent.normalize();
                        }
                    });
                    paintedRange = null;
                    paintStartAnchor = null;
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
                
                // Find original text node under a paint span (if wrapped)
                function findOriginalTextNode(node, offset) {
                    // If we're inside a paint span, drill down to the text node
                    let current = node;
                    while (current && current.nodeType !== Node.TEXT_NODE) {
                        if (current.classList && current.classList.contains('teal-ink-paint')) {
                            // Inside paint span - get first text node
                            const walker = document.createTreeWalker(
                                current,
                                NodeFilter.SHOW_TEXT,
                                null
                            );
                            const textNode = walker.nextNode();
                            if (textNode) return { node: textNode, offset: offset };
                        }
                        current = current.firstChild;
                    }
                    return { node: node, offset: offset };
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
                    capsule.style.display = 'block';
                    
                    const wordRange = getWordBoundaryRange(range.startContainer, range.startOffset);
                    if (wordRange) {
                        // Store stable start position BEFORE any DOM mutation
                        paintStartAnchor = {
                            node: wordRange.startContainer,
                            offset: wordRange.startOffset
                        };
                        applyPaint(wordRange);
                    }
                };
                
                window.updatePaintSelection = function(x, y) {
                    if (!isSelecting || !paintStartAnchor) return;
                    
                    const currentRange = document.caretRangeFromPoint(x, y);
                    if (!currentRange) return;
                    
                    // Find current position, drilling through any paint spans
                    let currentNode = currentRange.startContainer;
                    let currentOffset = currentRange.startOffset;
                    
                    // If we hit a paint span, unwrap to find the original text node
                    if (currentNode.nodeType === Node.ELEMENT_NODE) {
                        const walker = document.createTreeWalker(
                            currentNode,
                            NodeFilter.SHOW_TEXT,
                            null
                        );
                        const textNode = walker.nextNode();
                        if (textNode) {
                            currentNode = textNode;
                            currentOffset = 0;
                        }
                    }
                    
                    // Check if we're inside a paint span and get the underlying text node
                    let checkNode = currentNode;
                    while (checkNode && checkNode !== document.body) {
                        if (checkNode.classList && checkNode.classList.contains('teal-ink-paint')) {
                            // We're inside the paint span - find the actual text position
                            const walker = document.createTreeWalker(
                                checkNode,
                                NodeFilter.SHOW_TEXT,
                                null
                            );
                            let textNode;
                            let accumulatedOffset = 0;
                            while ((textNode = walker.nextNode())) {
                                if (textNode === currentNode) {
                                    currentOffset = accumulatedOffset + currentOffset;
                                    currentNode = checkNode.firstChild;
                                    while (currentNode && currentNode.nodeType !== Node.TEXT_NODE) {
                                        currentNode = currentNode.firstChild;
                                    }
                                    if (!currentNode) currentNode = textNode;
                                    break;
                                }
                                accumulatedOffset += textNode.textContent.length;
                            }
                            break;
                        }
                        checkNode = checkNode.parentNode;
                    }
                    
                    try {
                        // Create fresh range from stable start to current end (word boundaries)
                        const expandedRange = expandToWordBoundaries(
                            paintStartAnchor.node,
                            paintStartAnchor.offset,
                            currentNode,
                            currentOffset
                        );
                        
                        // Clear old paint and apply fresh highlight
                        applyPaint(expandedRange);
                    } catch(e) {
                        console.warn('Paint update failed:', e);
                    }
                };
                
                window.endPaintSelection = function() {
                    isSelecting = false;
                    capsule.style.display = 'none';
                    
                    if (paintedRange) {
                        const text = paintedRange.toString().trim();
                        if (text.length > 0 && text.length <= 200) {
                            window.webkit.messageHandlers.paintSelection.postMessage({ text: text });
                        }
                    }
                };
                
                window.clearPaintSelection = function() {
                    isSelecting = false;
                    capsule.style.display = 'none';
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
                                applyPaint(wordRange);
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
        webView.navigationDelegate = context.coordinator
        webView.scrollView.delegate = context.coordinator
        
        // Add long-press gesture for paint selection
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = context.coordinator
        webView.addGestureRecognizer(longPress)
        
        context.coordinator.webView = webView
        context.coordinator.explainSheet = _explainSheet
        context.coordinator.lessonContext = lessonContext
        context.coordinator.isOnline = isOnline
        context.coordinator.glossService = glossService
        
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
        context.coordinator.isOnline = isOnline
        context.coordinator.glossService = glossService
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        var lastHTML: String?
        var onScrolledToEnd: (() -> Void)?
        var explainSheet: Binding<ExplainSheet?>?
        var explainAnchors: [LessonMeta.Anchor] = []
        var lessonContext: ExplainSheet.LessonContext?
        var isOnline: Bool = false
        var glossService: GlossService?
        private var hasNotifiedEnd = false
        weak var webView: WKWebView?
        private var offlineToastWorkItem: DispatchWorkItem?
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Airplane-mode: block any navigation away from the loaded HTML
            if navigationAction.navigationType == .other || navigationAction.navigationType == .reload {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
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
                
            case .cancelled, .failed:
                // Clear paint
                webView.evaluateJavaScript("window.clearPaintSelection()") { _, _ in }
                
            default:
                break
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
        
        private func explainText(_ text: String) {
            guard let glossService = glossService,
                  let lessonContext = lessonContext else {
                return
            }
            
            // Check online + BYOK
            guard isOnline, glossService.hasAPIKey() else {
                showOfflineToast()
                clearPaint()
                return
            }
            
            Task { @MainActor in
                do {
                    let contextString = "\(lessonContext.courseTitle) — \(lessonContext.lessonTitle)"
                    let gloss = try await glossService.generateGloss(for: text, lessonContext: contextString)
                    
                    self.explainSheet?.wrappedValue = ExplainSheet(
                        term: text,
                        gloss: gloss,
                        lessonContext: lessonContext
                    )
                    self.clearPaint()
                } catch {
                    self.explainSheet?.wrappedValue = ExplainSheet(
                        term: text,
                        gloss: "**Error generating explanation:** \(error.localizedDescription)",
                        lessonContext: lessonContext
                    )
                    self.clearPaint()
                }
            }
        }
        
        private func clearPaint() {
            webView?.evaluateJavaScript("window.clearPaintSelection()") { _, _ in }
        }
        
        private func showOfflineToast() {
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
            
            webView.addSubview(toast)
            
            NSLayoutConstraint.activate([
                toast.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
                toast.bottomAnchor.constraint(equalTo: webView.safeAreaLayoutGuide.bottomAnchor, constant: -40),
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
                    self.explainSheet?.wrappedValue = ExplainSheet(
                        term: term,
                        gloss: gloss,
                        lessonContext: self.lessonContext
                    )
                    // Clear any painted selection after opening sheet
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
                // Clear paint (tap outside)
                clearPaint()
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
