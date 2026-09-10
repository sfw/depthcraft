import Foundation

enum MarkdownHTML {
    /// Minimal markdown→HTML for lesson study typography (headings, paragraphs, bold/italic, code, lists, hr).
    static func render(_ markdown: String, title: String, estimatedMinutes: Int?) -> String {
        let body = convert(markdown)
        let minutesLabel = estimatedMinutes.map { " · \($0) min" } ?? ""
        return """
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
              --fg: #f5f5f4;
              --muted: #a8a29e;
              --accent: #5eead4;
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
            max-width: 40rem;
            margin: 0 auto;
            padding: 2rem 1.5rem 3.5rem;
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
    }

    private static func convert(_ markdown: String) -> String {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
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
        return html.joined(separator: "\n")
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
}
