import Foundation
import Testing

@testable import NtfyAppLogic

@Suite struct MessageBodyRendererTests {
  private func text(_ rendered: AttributedString) -> String { String(rendered.characters) }

  @Test func listMarkersBecomeBullets() {
    let body = "- one\n* two\n+ three\n  - nested\nplain - dash\n---\n**bold**"
    #expect(
      MessageBodyRenderer.normaliseListMarkers(body)
        == "• one\n• two\n• three\n  • nested\nplain - dash\n---\n**bold**")
  }

  @Test func openableLinksSurvive() {
    let rendered = MessageBodyRenderer.render("[a](https://example.com) [b](mailto:x@example.com)")
    let links = rendered.runs.compactMap(\.link)
    #expect(links.map(\.absoluteString) == ["https://example.com", "mailto:x@example.com"])
  }

  @Test func otherSchemesLoseTheirLinkButKeepTheirText() {
    let rendered = MessageBodyRenderer.render(
      "[x](javascript:alert(1)) [y](file:///etc/passwd) [z](relative) [ok](http://example.com)")
    let links = rendered.runs.compactMap(\.link)
    #expect(links.map(\.absoluteString) == ["http://example.com"])
    #expect(text(rendered).contains("x"))
    #expect(text(rendered).contains("y"))
  }

  @Test func inlineStyleIsKeptAndWhitespacePreserved() {
    let rendered = MessageBodyRenderer.render("**bold**\n\n- item")
    #expect(text(rendered) == "bold\n\n• item")
    #expect(
      rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
  }

  @Test func plainTextPassesThrough() {
    #expect(text(MessageBodyRenderer.render("just text")) == "just text")
  }
}
