@testable import DesktopIconPosition
import Foundation
import Testing

@MainActor
struct FinderServiceParsingTests {
    // MARK: - Script generation

    @Test("batch read script uses DIM-style direct item property access")
    func batchReadScriptUsesDIMStyle() {
        let source = FinderService.readIconPositionsBatchSource()
        #expect(source.contains("name of items of desktop"))
        #expect(source.contains("desktop position of items of desktop"))
        #expect(source.contains("ASCII character 30"))
        #expect(source.contains("ASCII character 29"))
    }

    @Test("loop read script uses per-item access with try/catch")
    func loopReadScriptUsesPerItemAccess() {
        let source = FinderService.readIconPositionsLoopSource()
        #expect(source.contains("name of item i of allItems"))
        #expect(source.contains("desktop position of item i of allItems"))
        #expect(source.contains("ASCII character 31"))
    }

    @Test("batch script is omitted for empty icon list")
    func batchScriptForEmptyList() {
        #expect(FinderService.batchSetPositionsSource([]) == nil)
    }

    @Test("AppleScript string literal escapes quotes and backslashes")
    func appleScriptLiteralEscapesQuotesAndBackslashes() {
        let literal = FinderService.appleScriptStringLiteral("quote\"slash\\name")
        #expect(literal == "\"quote\\\"slash\\\\name\"")
    }

    @Test("AppleScript string literal uses ASCII character for newline")
    func appleScriptLiteralUsesAsciiForNewline() {
        let literal = FinderService.appleScriptStringLiteral("line1\nline2")
        #expect(literal == "\"line1\" & (ASCII character 10) & \"line2\"")
    }

    @Test("batch script embeds newline-safe AppleScript expression")
    func batchScriptUsesGeneratedLiteral() {
        let source = FinderService.batchSetPositionsSource([
            IconPosition(name: "line1\nline2", x: 10, y: 20),
        ])
        #expect(source?
            .contains(
                "set desktop position of item (\"line1\" & (ASCII character 10) & \"line2\") of desktop to {10, 20}"
            ) ==
            true)
    }

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

    // MARK: - parseBatchOutput (GS/RS delimiter format)

    @Test("batch output with two icons parsed correctly")
    func parseBatchOutputNormal() {
        // names separated by RS (\u{1E}), positions separated by RS, sections split by GS (\u{1D})
        let output = "alpha\u{1E}beta\u{1D}100,200\u{1E}300,400"
        let result = FinderService.parseBatchOutput(output)
        #expect(result.count == 2)
        #expect(result[0].name == "alpha")
        #expect(result[0].x == 100)
        #expect(result[0].y == 200)
        #expect(result[1].name == "beta")
        #expect(result[1].x == 300)
        #expect(result[1].y == 400)
    }

    @Test("batch output empty string returns empty array")
    func parseBatchOutputEmpty() {
        #expect(FinderService.parseBatchOutput("").isEmpty)
        #expect(FinderService.parseBatchOutput("   \n").isEmpty)
    }

    @Test("batch output with mismatched name/position count returns empty")
    func parseBatchOutputMismatch() {
        let output = "alpha\u{1E}beta\u{1D}100,200"
        #expect(FinderService.parseBatchOutput(output).isEmpty)
    }

    @Test("batch output missing group separator returns empty")
    func parseBatchOutputNoGS() {
        let output = "alpha\u{1E}100,200"
        #expect(FinderService.parseBatchOutput(output).isEmpty)
    }

    @Test("batch output skips entries with malformed coordinates")
    func parseBatchOutputBadCoords() {
        let output = "alpha\u{1E}beta\u{1D}100,200\u{1E}bad"
        let result = FinderService.parseBatchOutput(output)
        // mismatched count means entire batch is rejected
        #expect(result.count == 1)
        #expect(result[0].name == "alpha")
    }

    @Test("batch output single icon")
    func parseBatchOutputSingle() {
        let output = "file.txt\u{1D}42,99"
        let result = FinderService.parseBatchOutput(output)
        #expect(result.count == 1)
        #expect(result[0].name == "file.txt")
        #expect(result[0].x == 42)
        #expect(result[0].y == 99)
    }

    // MARK: - parseRawIconPositions (unit separator format)

    @Test("raw icon positions with unit separator parsed correctly")
    func parseRawPositionsNormal() {
        let output = "alpha\u{1F}100\u{1F}200\nbeta\u{1F}300\u{1F}400\n"
        let result = FinderService.parseRawIconPositions(output)
        #expect(result.count == 2)
        #expect(result[0].name == "alpha")
        #expect(result[0].x == 100)
        #expect(result[1].name == "beta")
        #expect(result[1].y == 400)
    }

    @Test("raw icon positions empty returns empty")
    func parseRawPositionsEmpty() {
        #expect(FinderService.parseRawIconPositions("").isEmpty)
    }

    @Test("raw icon positions skips malformed lines")
    func parseRawPositionsMalformed() {
        let output = "only-name\u{1F}100\ngood\u{1F}10\u{1F}20\n"
        let result = FinderService.parseRawIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "good")
    }

    @Test("raw icon positions skips empty names")
    func parseRawPositionsEmptyName() {
        let output = "\u{1F}100\u{1F}200\ngood\u{1F}10\u{1F}20\n"
        let result = FinderService.parseRawIconPositions(output)
        #expect(result.count == 1)
        #expect(result[0].name == "good")
    }
}
