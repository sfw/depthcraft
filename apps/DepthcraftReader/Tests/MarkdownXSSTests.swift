import XCTest
@testable import DepthcraftReader

/// Tests for XSS protection in markdown rendering
final class MarkdownXSSTests: XCTestCase {
    
    func testEscapeScriptTags() {
        let markdown = """
        # Test
        
        <script>alert('XSS')</script>
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Script tags should be escaped
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
        XCTAssertTrue(result.html.contains("&lt;/script&gt;"))
        XCTAssertFalse(result.html.contains("<script>alert"))
    }
    
    func testEscapeImgOnerror() {
        let markdown = """
        Look at this: <img src=x onerror=alert(1)>
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Should be escaped
        XCTAssertTrue(result.html.contains("&lt;img"))
        XCTAssertFalse(result.html.contains("<img src=x"))
    }
    
    func testEscapeIframe() {
        let markdown = """
        Evil iframe: <iframe src="http://evil.com"></iframe>
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("&lt;iframe"))
        XCTAssertFalse(result.html.contains("<iframe src"))
    }
    
    func testEscapeInCodeBlock() {
        let markdown = """
        ```javascript
        <script>alert('This should be escaped')</script>
        ```
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // In code blocks, also escaped
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
        XCTAssertFalse(result.html.contains("<script>alert"))
    }
    
    func testEscapeInInlineCode() {
        let markdown = """
        Use this code: `<script>alert(1)</script>`
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("&lt;script&gt;"))
        XCTAssertFalse(result.html.contains("<script>alert"))
    }
    
    func testEscapeInBold() {
        let markdown = """
        **<script>alert(1)</script>**
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Bold formatting should wrap escaped content
        XCTAssertTrue(result.html.contains("<strong>&lt;script&gt;"))
        XCTAssertFalse(result.html.contains("<strong><script>"))
    }
    
    func testEscapeInLinks() {
        let markdown = """
        Click [here](javascript:alert(1))
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Note: current implementation doesn't support markdown links,
        // so this will be rendered as plain text with escaping
        XCTAssertFalse(result.html.contains("javascript:alert"))
    }
    
    func testEscapeAmpersands() {
        let markdown = """
        AT&T is a company
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("AT&amp;T"))
        // Should not have unescaped ampersand in body (except in entity itself)
    }
    
    func testDemoIdEscaping() {
        let markdown = """
        :::demo id="<script>alert(1)</script>":::
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Demo ID should be extracted but then escaped when inserted into HTML
        XCTAssertTrue(result.html.contains("&lt;script&gt;") || !result.html.contains("<script>alert"))
    }
    
    func testDemoFallbackEscaping() {
        let markdown = """
        # Fallback
        
        <script>alert('XSS')</script>
        """
        let html = MarkdownHTML.renderDemoFallback(markdown)
        
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>alert"))
    }
    
    func testSafeMarkdownRendersCorrectly() {
        let markdown = """
        # Introduction
        
        This is **bold** and *italic* text.
        
        Here's some `code` inline.
        
        ## Lists
        
        - Item 1
        - Item 2
        
        ```
        code block
        ```
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: 10)
        
        // Verify safe markdown is not broken
        XCTAssertTrue(result.html.contains("<strong>bold</strong>"))
        XCTAssertTrue(result.html.contains("<em>italic</em>"))
        XCTAssertTrue(result.html.contains("<code>code</code>"))
        XCTAssertTrue(result.html.contains("<ul>"))
        XCTAssertTrue(result.html.contains("<li>Item 1</li>"))
        XCTAssertTrue(result.html.contains("<pre><code>"))
    }
}
