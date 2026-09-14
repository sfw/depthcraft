import XCTest
@testable import DepthcraftReader

/// Tests for GFM table rendering and blank-line normalization
final class MarkdownTableTests: XCTestCase {
    
    func testBasicTable() {
        let markdown = """
        # Lesson
        
        | Column A | Column B | Column C |
        |----------|----------|----------|
        | Cell 1   | Cell 2   | Cell 3   |
        | Cell 4   | Cell 5   | Cell 6   |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("<thead>"))
        XCTAssertTrue(result.html.contains("<tbody>"))
        XCTAssertTrue(result.html.contains("<th>Column A</th>"))
        XCTAssertTrue(result.html.contains("<th>Column B</th>"))
        XCTAssertTrue(result.html.contains("<th>Column C</th>"))
        XCTAssertTrue(result.html.contains("<td>Cell 1</td>"))
        XCTAssertTrue(result.html.contains("<td>Cell 2</td>"))
        XCTAssertTrue(result.html.contains("</table>"))
    }
    
    func testTableWithBlankLines() {
        let markdown = """
        # Responsibility Boundary
        
        | Role | Responsibility |
        |------|----------------|
        | Planner | Create curriculum |
        
        | Writer | Write lessons |
        
        | Packager | Bundle everything |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // All rows should render despite blank lines
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("<th>Role</th>"))
        XCTAssertTrue(result.html.contains("<th>Responsibility</th>"))
        XCTAssertTrue(result.html.contains("<td>Planner</td>"))
        XCTAssertTrue(result.html.contains("<td>Create curriculum</td>"))
        XCTAssertTrue(result.html.contains("<td>Writer</td>"))
        XCTAssertTrue(result.html.contains("<td>Write lessons</td>"))
        XCTAssertTrue(result.html.contains("<td>Packager</td>"))
        XCTAssertTrue(result.html.contains("<td>Bundle everything</td>"))
        XCTAssertTrue(result.html.contains("</table>"))
    }
    
    func testTableWithAlignment() {
        let markdown = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | A    | B      | C     |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("<th>Left</th>"))
        XCTAssertTrue(result.html.contains("<th>Center</th>"))
        XCTAssertTrue(result.html.contains("<th>Right</th>"))
    }
    
    func testTableWithInlineFormatting() {
        let markdown = """
        | Feature | Status |
        |---------|--------|
        | **Bold** | *Italic* |
        | `Code` | Normal |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("<strong>Bold</strong>"))
        XCTAssertTrue(result.html.contains("<em>Italic</em>"))
        XCTAssertTrue(result.html.contains("<code>Code</code>"))
    }
    
    func testTableFollowedByParagraph() {
        let markdown = """
        | Column 1 | Column 2 |
        |----------|----------|
        | Data     | More     |
        
        This is a paragraph after the table.
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        XCTAssertTrue(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("</table>"))
        XCTAssertTrue(result.html.contains("<p>This is a paragraph after the table.</p>"))
    }
    
    func testMultipleTables() {
        let markdown = """
        First table:
        
        | A | B |
        |---|---|
        | 1 | 2 |
        
        Second table:
        
        | C | D |
        |---|---|
        | 3 | 4 |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Should contain two separate tables
        let tableCount = result.html.components(separatedBy: "<table>").count - 1
        XCTAssertEqual(tableCount, 2)
    }
    
    func testTableWithSpecialCharacters() {
        let markdown = """
        | Name | Symbol |
        |------|--------|
        | And  | &      |
        | Less | <      |
        | Greater | >   |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Special characters should be escaped
        XCTAssertTrue(result.html.contains("&amp;"))
        XCTAssertTrue(result.html.contains("&lt;"))
        XCTAssertTrue(result.html.contains("&gt;"))
    }
    
    func testNonTablePipesDontCreateTable() {
        let markdown = """
        This is a paragraph with a | pipe character.
        
        No separator follows, so no table.
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // Should not create a table
        XCTAssertFalse(result.html.contains("<table>"))
        XCTAssertTrue(result.html.contains("pipe character"))
    }
    
    func testTableNormalization() {
        let markdown = """
        | Header 1 | Header 2 |
        |----------|----------|
        | Row 1    | Data 1   |
        
        | Row 2    | Data 2   |
        
        
        | Row 3    | Data 3   |
        """
        let result = MarkdownHTML.render(markdown, title: "Test", estimatedMinutes: nil)
        
        // All rows should be in one table
        XCTAssertTrue(result.html.contains("<td>Row 1</td>"))
        XCTAssertTrue(result.html.contains("<td>Row 2</td>"))
        XCTAssertTrue(result.html.contains("<td>Row 3</td>"))
        
        // Only one table should exist
        let tableCount = result.html.components(separatedBy: "<table>").count - 1
        XCTAssertEqual(tableCount, 1)
    }
}
