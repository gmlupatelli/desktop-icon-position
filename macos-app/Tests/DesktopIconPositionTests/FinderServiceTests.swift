import Testing
import Foundation
@testable import DesktopIconPosition

@Suite("FinderService Parsing")
@MainActor
struct FinderServiceParsingTests {

    // MARK: - parseIconPositions

    @Test("simple name parsed correctly")
    func parseSimpleName() {
        let output = "file.txt|100|200\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "file.txt")
        #expect(result[0].x == 100)
        #expect(result[0].y == 200)
    }

    @Test("name containing pipe parsed correctly via right-to-left split")
    func parseNameWithPipe() {
        let output = "file|name.txt|300|400\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "file|name.txt")
        #expect(result[0].x == 300)
        #expect(result[0].y == 400)
    }

    @Test("name with multiple pipes parsed correctly")
    func parseNameWithMultiplePipes() {
        let output = "a|b|c.txt|50|60\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "a|b|c.txt")
        #expect(result[0].x == 50)
        #expect(result[0].y == 60)
    }

    @Test("escaped newline in name is unescaped")
    func parseEscapedNewline() {
        // AppleScript escaping emits \\n for a linefeed in the name
        let output = "part1\\npart2|10|20\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "part1\npart2")
        #expect(result[0].x == 10)
        #expect(result[0].y == 20)
    }

    @Test("escaped backslash in name is unescaped")
    func parseEscapedBackslash() {
        let output = "file\\\\name|5|6\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "file\\name")
    }

    @Test("multiple lines parsed")
    func parseMultipleLines() {
        let output = "alpha|10|20\nbeta|30|40\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 2)
        #expect(result[0].name == "alpha")
        #expect(result[1].name == "beta")
    }

    @Test("malformed line with only one pipe is skipped")
    func parseMalformedLine() {
        let output = "no-y-value|100\ngood|10|20\n"
        let result = FinderService.parseIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "good")
    }

    @Test("empty output produces empty array")
    func parseEmptyOutput() {
        let result = FinderService.parseIconPositions("")
        #expect(result.isEmpty)
    }

    // MARK: - unescapeIconName

    @Test("unescape plain name is identity")
    func unescapePlain() {
        #expect(FinderService.unescapeIconName("hello") == "hello")
    }

    @Test("unescape backslash-n to newline")
    func unescapeNewline() {
        #expect(FinderService.unescapeIconName("a\\nb") == "a\nb")
    }

    @Test("unescape backslash-r to carriage return")
    func unescapeCarriageReturn() {
        #expect(FinderService.unescapeIconName("a\\rb") == "a\rb")
    }

    @Test("unescape double backslash to single")
    func unescapeBackslash() {
        #expect(FinderService.unescapeIconName("a\\\\b") == "a\\b")
    }

    @Test("unescape unknown escape passes through")
    func unescapeUnknown() {
        #expect(FinderService.unescapeIconName("a\\xb") == "a\\xb")
    }

    @Test("trailing backslash passes through")
    func unescapeTrailingBackslash() {
        #expect(FinderService.unescapeIconName("abc\\") == "abc\\")
    }
}
