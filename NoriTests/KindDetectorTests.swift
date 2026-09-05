import Foundation
import Testing
@testable import Nori

@Suite("KindDetector")
struct KindDetectorTests {
    @Test("links", arguments: [
        "https://example.com/path?q=1",
        "http://localhost:3000",
        "mailto:someone@example.com",
        "  https://zenn.dev/articles/abc  ",
    ])
    func detectsLinks(_ text: String) {
        #expect(KindDetector.link(in: text.trimmingCharacters(in: .whitespaces)) != nil)
    }

    @Test("not links", arguments: [
        "hello world",
        "https://example.com and more",
        "example.com",
        "http://",
        "mailto:nobody",
        "file:///Users/me/a.txt",
        "just: text",
    ])
    func rejectsNonLinks(_ text: String) {
        #expect(KindDetector.link(in: text) == nil)
    }

    @Test("colors", arguments: [
        ("#fff", "#FFFFFF"),
        ("#1a2B3c", "#1A2B3C"),
        ("#1a2B3c80", "#1A2B3C80"),
        ("#abcd", "#AABBCCDD"),
        ("rgb(255, 0, 128)", "#FF0080"),
        ("rgba(255, 0, 128, 0.5)", "#FF008080"),
        ("rgb(255 0 128 / 50%)", "#FF008080"),
        ("hsl(0, 100%, 50%)", "#FF0000"),
        ("hsl(120, 100%, 25%)", "#008000"),
        ("hsla(240, 100%, 50%, 1)", "#0000FF"),
    ])
    func detectsColors(_ pair: (String, String)) {
        #expect(KindDetector.color(in: pair.0) == pair.1)
    }

    @Test("not colors", arguments: ["#12", "#12345", "rgb(300,0,0)", "#ggg", "hsl(0,200%,50%)", "color: #fff;", "12345678"])
    func rejectsNonColors(_ text: String) {
        #expect(KindDetector.color(in: text) == nil)
    }

    @Test func detectsSwiftCode() {
        let code = """
        import Foundation

        struct Point {
            var x: Double
            var y: Double
        }
        """
        #expect(KindDetector.looksLikeCode(code))
    }

    @Test func detectsJavaScriptCode() {
        let code = """
        const items = list.filter((item) => item.active);
        items.forEach((item) => {
          console.log(item.name);
        });
        """
        #expect(KindDetector.looksLikeCode(code))
    }

    @Test func detectsShellCommand() {
        #expect(KindDetector.looksLikeCode("brew install --cask maccy"))
        #expect(KindDetector.looksLikeCode("git commit -m \"fix\""))
    }

    @Test func proseIsNotCode() {
        let prose = """
        Nori keeps the history of what you copy and lets you find it again quickly.
        It works with text, links, images and files; nothing ever leaves your Mac.
        Press the shortcut, type a few letters, hit return.
        """
        #expect(!KindDetector.looksLikeCode(prose))
        #expect(!KindDetector.looksLikeCode("Meet me at 5; bring the docs."))
        #expect(!KindDetector.looksLikeCode("Hello"))
    }
}
