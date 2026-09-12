import Foundation

struct DemoReference: Hashable {
    let demoId: String
    let placeholder: String // Unique marker in HTML where demo should be embedded
}

struct LessonRenderResult {
    let html: String
    let demos: [DemoReference]
    let explainAnchors: [LessonMeta.Anchor]
}

enum MarkdownHTML {
    /// Minimal markdown→HTML for lesson study typography (headings, paragraphs, bold/italic, code, lists, hr).
    /// Also extracts :::demo id="...":::  directives.
    /// Injects warm ink underlines for tap-to-explain terms when anchors are provided.
    static func render(_ markdown: String, title: String, estimatedMinutes: Int?, anchors: [LessonMeta.Anchor] = []) -> LessonRenderResult {
        let (body, demos) = convert(markdown)
        let minutesLabel = estimatedMinutes.map { " · \($0) min" } ?? ""
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
        <style>
          :root {
            color-scheme: light dark;
            --bg: #f7f4ef;
            --fg: #1c1917;
            --muted: #57534e;
            --accent: #0f766e;
            --rule: #d6d3d1;
            --code-bg: #ebe7e0;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #1c1917;
              --fg: #e7e5e4;
              --muted: #a8a29e;
              --accent: #5d9b94;
              --rule: #44403c;
              --code-bg: #292524;
            }
          }
          html, body {
            margin: 0;
            padding: 0;
            background: var(--bg);
            color: var(--fg);
            font-family: ui-serif, Georgia, "Times New Roman", serif;
            font-size: 20px;
            line-height: 1.7;
            -webkit-text-size-adjust: 100%;
          }
          .page {
            max-width: 38rem;
            margin: 0 auto;
            padding: 2rem 2rem 4rem;
          }
          .eyebrow {
            font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
            font-size: 0.8rem;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            color: var(--accent);
            margin: 0 0 0.75rem;
            font-weight: 600;
          }
          h1 {
            font-size: 2rem;
            line-height: 1.2;
            margin: 0 0 1.5rem;
            font-weight: 700;
          }
          h2 {
            font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
            font-size: 1.25rem;
            margin: 2.5rem 0 0.9rem;
            font-weight: 650;
            color: var(--fg);
          }
          h3 {
            font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
            font-size: 1.1rem;
            margin: 1.75rem 0 0.6rem;
          }
          p { margin: 0 0 1.25rem; }
          strong { font-weight: 700; }
          em { font-style: italic; }
          code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.88em;
            background: var(--code-bg);
            padding: 0.15em 0.4em;
            border-radius: 0.3em;
          }
          pre {
            background: var(--code-bg);
            padding: 1rem 1.1rem;
            border-radius: 0.6rem;
            overflow-x: auto;
            font-size: 0.9rem;
            line-height: 1.5;
            margin: 1.5rem 0;
          }
          pre code { background: transparent; padding: 0; }
          ul, ol { margin: 0 0 1.25rem; padding-left: 1.5rem; }
          li { margin: 0.35rem 0; }
          hr {
            border: none;
            border-top: 1px solid var(--rule);
            margin: 2.5rem 0;
          }
          a { color: var(--accent); }
          blockquote {
            margin: 0 0 1.25rem;
            padding: 0.3rem 0 0.3rem 1.2rem;
            border-left: 3px solid var(--accent);
            color: var(--muted);
          }
          .explain-term {
            text-decoration: underline;
            text-decoration-color: rgba(120, 113, 108, 0.4);
            text-decoration-thickness: 1.5px;
            text-underline-offset: 3px;
            cursor: pointer;
            -webkit-tap-highlight-color: rgba(120, 113, 108, 0.1);
          }
          .explain-term:hover {
            text-decoration-color: rgba(120, 113, 108, 0.7);
          }
          @media (prefers-color-scheme: dark) {
            .explain-term {
              text-decoration-color: rgba(168, 162, 158, 0.4);
            }
            .explain-term:hover {
              text-decoration-color: rgba(168, 162, 158, 0.7);
            }
          }
          .demo-placeholder {
            margin: 2rem 0;
            min-height: 400px;
            background: var(--code-bg);
            border-radius: 0.6rem;
            display: flex;
            align-items: center;
            justify-content: center;
            color: var(--muted);
          }
        </style>
        </head>
        <body>
          <article class="page">
            <p class="eyebrow">Lesson\(minutesLabel)</p>
            \(body)
          </article>
        </body>
        </html>
        """
        
        let explainAnchors = anchors.filter { $0.isExplainAnchor }
        let htmlWithUnderlines = injectExplainUnderlines(html: html, anchors: explainAnchors)
        
        return LessonRenderResult(html: htmlWithUnderlines, demos: demos, explainAnchors: explainAnchors)
    }
    
    /// Render markdown for demo fallback without lesson chrome or eyebrow.
    /// Keeps the leading H1 (unlike lesson render which drops it) for fallback context.
    static func renderDemoFallback(_ markdown: String) -> String {
        let (body, _) = convertSimple(markdown)
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
        <style>
          :root {
            color-scheme: light dark;
            --bg: #f7f4ef;
            --fg: #1c1917;
            --muted: #57534e;
            --accent: #0f766e;
            --code-bg: #ebe7e0;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #1c1917;
              --fg: #e7e5e4;
              --muted: #a8a29e;
              --accent: #5d9b94;
              --code-bg: #292524;
            }
          }
          html, body {
            margin: 0;
            padding: 0;
            background: var(--bg);
            color: var(--fg);
            font-family: ui-serif, Georgia, "Times New Roman", serif;
            font-size: 20px;
            line-height: 1.7;
            -webkit-text-size-adjust: 100%;
          }
          .page {
            max-width: 38rem;
            margin: 0 auto;
            padding: 2rem 2rem 4rem;
          }
          h1 {
            font-size: 1.5rem;
            line-height: 1.3;
            margin: 0 0 1rem;
            font-weight: 700;
          }
          h2 {
            font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
            font-size: 1.15rem;
            margin: 2rem 0 0.8rem;
            font-weight: 650;
          }
          p { margin: 0 0 1rem; }
          strong { font-weight: 700; }
          em { font-style: italic; }
          code {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 0.88em;
            background: var(--code-bg);
            padding: 0.15em 0.4em;
            border-radius: 0.3em;
          }
          ul, ol { margin: 0 0 1rem; padding-left: 1.5rem; }
          li { margin: 0.3rem 0; }
        </style>
        </head>
        <body>
          <article class="page">
            \(body)
          </article>
        </body>
        </html>
        """
        return html
    }

    /// Simple markdown conversion for demo fallback (no demo extraction, keeps leading H1)
    private static func convertSimple(_ markdown: String) -> (String, [DemoReference]) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var html: [String] = []
        var inList = false
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if inList {
                    html.append("</ul>")
                    inList = false
                }
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<h3>\(inline(String(trimmed.dropFirst(4))))</h3>")
            } else if trimmed.hasPrefix("## ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<h2>\(inline(String(trimmed.dropFirst(3))))</h2>")
            } else if trimmed.hasPrefix("# ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<h1>\(inline(String(trimmed.dropFirst(2))))</h1>")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    html.append("<ul>")
                    inList = true
                }
                html.append("<li>\(inline(String(trimmed.dropFirst(2))))</li>")
            } else {
                if inList { html.append("</ul>"); inList = false }
                html.append("<p>\(inline(trimmed))</p>")
            }
            i += 1
        }
        if inList { html.append("</ul>") }
        return (html.joined(separator: "\n"), [])
    }
    
    private static func convert(_ markdown: String) -> (String, [DemoReference]) {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var demos: [DemoReference] = []
        
        // Drop a leading H1 if present — page chrome already frames the lesson.
        if let first = lines.first, first.hasPrefix("# ") {
            lines.removeFirst()
            while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                lines.removeFirst()
            }
        }

        var html: [String] = []
        var inList = false
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if inList {
                    html.append("</ul>")
                    inList = false
                }
                i += 1
                continue
            }

            // Handle :::demo id="...":::
            if trimmed.hasPrefix(":::demo") && trimmed.hasSuffix(":::") {
                if inList { html.append("</ul>"); inList = false }
                if let demoId = extractDemoId(from: trimmed) {
                    let placeholder = "DEMO_PLACEHOLDER_\(demoId)"
                    demos.append(DemoReference(demoId: demoId, placeholder: placeholder))
                    html.append("<div class=\"demo-placeholder\" id=\"\(placeholder)\">Interactive demo</div>")
                }
                i += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                if inList { html.append("</ul>"); inList = false }
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(escape(lines[i]))
                    i += 1
                }
                html.append("<pre><code>\(code.joined(separator: "\n"))</code></pre>")
                i += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" {
                if inList { html.append("</ul>"); inList = false }
                html.append("<hr />")
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<h3>\(inline(String(trimmed.dropFirst(4))))</h3>")
            } else if trimmed.hasPrefix("## ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<h2>\(inline(String(trimmed.dropFirst(3))))</h2>")
            } else if trimmed.hasPrefix("# ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<h1>\(inline(String(trimmed.dropFirst(2))))</h1>")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList {
                    html.append("<ul>")
                    inList = true
                }
                html.append("<li>\(inline(String(trimmed.dropFirst(2))))</li>")
            } else if trimmed.hasPrefix("> ") {
                if inList { html.append("</ul>"); inList = false }
                html.append("<blockquote><p>\(inline(String(trimmed.dropFirst(2))))</p></blockquote>")
            } else {
                if inList { html.append("</ul>"); inList = false }
                html.append("<p>\(inline(trimmed))</p>")
            }
            i += 1
        }
        if inList { html.append("</ul>") }
        return (html.joined(separator: "\n"), demos)
    }

    private static func extractDemoId(from directive: String) -> String? {
        // Parse :::demo id="some-id":::
        let pattern = #"id="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: directive, range: NSRange(directive.startIndex..., in: directive)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: directive) else {
            return nil
        }
        return String(directive[range])
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        // bold **x**
        s = replaceDelimited(s, delimiter: "**", open: "<strong>", close: "</strong>")
        // italic *x* (simple)
        s = replaceDelimited(s, delimiter: "*", open: "<em>", close: "</em>")
        // `code`
        s = replaceDelimited(s, delimiter: "`", open: "<code>", close: "</code>")
        return s
    }

    private static func replaceDelimited(_ input: String, delimiter: String, open: String, close: String) -> String {
        let parts = input.components(separatedBy: delimiter)
        guard parts.count > 1 else { return input }
        var out = ""
        for (idx, part) in parts.enumerated() {
            if idx % 2 == 0 {
                out += part
            } else {
                out += open + part + close
            }
        }
        // Odd trailing delimiter — leave as-is visually by not wrapping last
        if parts.count % 2 == 0 {
            // ended with delimiter; last part was wrapped incorrectly empty — acceptable for v0.1
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
    
    private static func injectExplainUnderlines(html: String, anchors: [LessonMeta.Anchor]) -> String {
        guard !anchors.isEmpty else { return html }
        
        var result = html
        
        // Sort anchors by term length (longest first) to handle overlapping terms
        let sortedAnchors = anchors.sorted { ($0.term?.count ?? 0) > ($1.term?.count ?? 0) }
        
        for anchor in sortedAnchors {
            guard let term = anchor.term else { continue }
            
            // Escape HTML entities in term for matching (terms should already be plain text)
            let escapedTerm = escape(term)
            
            // Only wrap first occurrence in text nodes (not inside tags, code, or existing spans)
            result = wrapTermInTextNodes(html: result, term: escapedTerm, anchorId: anchor.id)
        }
        
        return result
    }
    
    private static func wrapTermInTextNodes(html: String, term: String, anchorId: String) -> String {
        var output = ""
        var i = html.startIndex
        var insideTag = false
        var insideCode = false
        var insideExplainSpan = false
        var codeTagStack: [String] = []
        var spanDepth = 0
        var wrapped = false
        
        while i < html.endIndex {
            let char = html[i]
            
            // Track tag boundaries
            if char == "<" {
                insideTag = true
                let tagStart = i
                
                // Look ahead to identify tag
                var j = html.index(after: i)
                var tagName = ""
                var isClosing = false
                
                if j < html.endIndex && html[j] == "/" {
                    isClosing = true
                    j = html.index(after: j)
                }
                
                while j < html.endIndex && html[j] != " " && html[j] != ">" {
                    tagName.append(html[j])
                    j = html.index(after: j)
                }
                
                let lowerTag = tagName.lowercased()
                
                // Track code/pre blocks
                if lowerTag == "code" || lowerTag == "pre" {
                    if isClosing {
                        if !codeTagStack.isEmpty && codeTagStack.last == lowerTag {
                            codeTagStack.removeLast()
                            insideCode = !codeTagStack.isEmpty
                        }
                    } else {
                        codeTagStack.append(lowerTag)
                        insideCode = true
                    }
                }
                
                // Track explain-term spans
                if lowerTag == "span" && !isClosing {
                    // Check if this is an explain-term span
                    if let tagEnd = html[i...].firstIndex(of: ">") {
                        let tagContent = String(html[i...tagEnd])
                        if tagContent.contains("class=\"explain-term\"") || tagContent.contains("class='explain-term'") {
                            insideExplainSpan = true
                            spanDepth += 1
                        }
                    }
                } else if lowerTag == "span" && isClosing && insideExplainSpan {
                    spanDepth -= 1
                    if spanDepth <= 0 {
                        insideExplainSpan = false
                        spanDepth = 0
                    }
                }
            } else if char == ">" && insideTag {
                insideTag = false
                output.append(char)
                i = html.index(after: i)
                continue
            }
            
            // If we're inside a tag, code block, or existing explain span, just copy
            if insideTag || insideCode || insideExplainSpan {
                output.append(char)
                i = html.index(after: i)
                continue
            }
            
            // We're in text content - check if term matches here
            if !wrapped && html[i...].starts(with: term) {
                // Found first occurrence in text node - wrap it
                output.append("<span class=\"explain-term\" data-anchor-id=\"\(anchorId)\">")
                output.append(term)
                output.append("</span>")
                i = html.index(i, offsetBy: term.count)
                wrapped = true
                continue
            }
            
            // Regular text content
            output.append(char)
            i = html.index(after: i)
        }
        
        return output
    }
}
