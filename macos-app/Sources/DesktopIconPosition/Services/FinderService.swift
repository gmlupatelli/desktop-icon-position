import AppKit
import Foundation

/// Error types for Finder AppleScript operations.
enum FinderError: LocalizedError {
    case scriptError(String)

    var errorDescription: String? {
        switch self {
        case .scriptError(let msg): return "Finder AppleScript error: \(msg)"
        }
    }
}

/// Executes AppleScript commands to interact with Finder for icon position management.
/// All scripts match the shell script's AppleScript blocks exactly.
@MainActor
final class FinderService {

    // MARK: - Read Operations

    /// Read all desktop icon positions. Returns name + Quartz coordinates.
    static func readIconPositions() throws -> [IconPosition] {
        let output = try executeAppleScript(readIconPositionsSource())
        return parseIconPositions(output)
    }

    /// AppleScript source for reading desktop icon positions.
    static func readIconPositionsSource() -> String {
        // Escape backslash, linefeed, and return in icon names so the
        // pipe-delimited output stays one-line-per-icon.
        """
        tell application "Finder"
            set allItems to every item of desktop
            set posData to ""
            set saveTID to AppleScript's text item delimiters
            repeat with anItem in allItems
                try
                    set itemName to name of anItem as text
                    -- Escape \\ -> \\\\
                    set AppleScript's text item delimiters to (ASCII character 92)
                    set tList to text items of itemName
                    set AppleScript's text item delimiters to (ASCII character 92) & (ASCII character 92)
                    set itemName to tList as text
                    -- Escape LF -> \\n
                    set AppleScript's text item delimiters to (ASCII character 10)
                    set tList to text items of itemName
                    set AppleScript's text item delimiters to (ASCII character 92) & "n"
                    set itemName to tList as text
                    -- Escape CR -> \\r
                    set AppleScript's text item delimiters to (ASCII character 13)
                    set tList to text items of itemName
                    set AppleScript's text item delimiters to (ASCII character 92) & "r"
                    set itemName to tList as text
                    set AppleScript's text item delimiters to saveTID
                    set itemPos to desktop position of anItem
                    set posX to item 1 of itemPos as integer
                    set posY to item 2 of itemPos as integer
                    set posData to posData & itemName & "|" & posX & "|" & posY & linefeed
                end try
            end repeat
        end tell
        return posData
        """
    }

    /// Read current Finder icon size and text size.
    static func readSettings() throws -> DesktopSettings {
        let source = """
        tell application "Finder"
            set iSize to icon size of (icon view options of desktop's window)
            set tSize to text size of (icon view options of desktop's window)
            return (iSize as text) & "|" & (tSize as text)
        end tell
        """
        let output = try executeAppleScript(source)
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        guard parts.count == 2,
              let iconSize = Int(parts[0]),
              let textSize = Int(parts[1]) else {
            throw FinderError.scriptError("Unexpected settings format: \(output)")
        }
        return DesktopSettings(iconSize: iconSize, textSize: textSize)
    }

    // MARK: - Write Operations

    /// Restore Finder icon size and text size. Must be called before position restore
    /// to prevent Finder layout recalculation.
    static func restoreSettings(_ settings: DesktopSettings) throws {
        let source = """
        tell application "Finder"
            set icon size of (icon view options of desktop's window) to \(settings.iconSize)
            set text size of (icon view options of desktop's window) to \(settings.textSize)
        end tell
        """
        try executeAppleScript(source)
    }

    /// Disable Finder's auto-arrange / Snap to Grid to prevent icon drift after restore.
    static func disableArrangement() throws {
        let source = """
        tell application "Finder"
            if arrangement of (icon view options of desktop's window) is not not arranged then
                set arrangement of (icon view options of desktop's window) to not arranged
            end if
        end tell
        """
        try executeAppleScript(source)
    }

    /// Set all icon positions in a single batch, wrapped in `ignoring application responses`
    /// to prevent Finder from rearranging icons mid-restore.
    static func batchSetPositions(_ icons: [IconPosition]) throws {
        guard let source = batchSetPositionsSource(icons) else { return }
        try executeAppleScript(source)
    }

    /// AppleScript source for restoring a batch of icon positions.
    static func batchSetPositionsSource(_ icons: [IconPosition]) -> String? {
        guard !icons.isEmpty else { return nil }
        var setStatements = ""
        for icon in icons {
            let nameExpr = appleScriptStringLiteral(icon.name)
            setStatements += """
                        try
                            set desktop position of item (\(nameExpr)) of desktop to {\(icon.x), \(icon.y)}
                        end try
            
            """
        }
        return """
        tell application "Finder"
            ignoring application responses
        \(setStatements)    end ignoring
        end tell
        return "done"
        """
    }

    /// Verify positions after restore and re-apply any that drifted more than `tolerance` pixels.
    /// Returns the number of corrected icons.
    static func verifyAndReapply(expected: [IconPosition], tolerance: Int = 2) throws -> Int {
        let current = try readIconPositions()
        let currentMap = Dictionary(current.map { ($0.name, $0) }, uniquingKeysWith: { $1 })

        var drifted: [IconPosition] = []
        for icon in expected {
            guard let cur = currentMap[icon.name] else { continue }
            let dX = abs(cur.x - icon.x)
            let dY = abs(cur.y - icon.y)
            if dX > tolerance || dY > tolerance {
                drifted.append(icon)
            }
        }

        if !drifted.isEmpty {
            try batchSetPositions(drifted)
        }
        return drifted.count
    }

    // MARK: - Permission Check

    /// Test whether the app has Automation permission to control Finder.
    /// On first call, this may trigger the macOS consent prompt.
    static func checkPermission() -> Bool {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Finder\" to name of startup disk")!
        script.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    /// Whether an error indicates a missing Automation permission.
    static func isPermissionError(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("not authorised") || msg.contains("not authorized")
    }

    // MARK: - Private Helpers

    @discardableResult
    private static func executeAppleScript(_ source: String) throws -> String {
        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)!
        let result = script.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw FinderError.scriptError(msg)
        }
        return result.stringValue ?? ""
    }

    /// Parse `name|x|y` lines using right-to-left splitting so `|` in
    /// filenames does not corrupt the result.
    static func parseIconPositions(_ output: String) -> [IconPosition] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let str = String(line)
            guard let lastPipe = str.lastIndex(of: "|") else { return nil }
            let beforeLast = str[str.startIndex..<lastPipe]
            guard let secondPipe = beforeLast.lastIndex(of: "|") else { return nil }

            let rawName = String(str[str.startIndex..<secondPipe])
            let xStr = str[str.index(after: secondPipe)..<lastPipe]
            let yStr = str[str.index(after: lastPipe)...]

            guard let x = Int(xStr.trimmingCharacters(in: .whitespaces)),
                  let y = Int(yStr.trimmingCharacters(in: .whitespaces)),
                  !rawName.isEmpty else {
                return nil
            }
            return IconPosition(name: unescapeIconName(rawName), x: x, y: y)
        }
    }

    /// Reverse the backslash escaping applied by the read AppleScript.
    static func unescapeIconName(_ name: String) -> String {
        var result = ""
        var i = name.startIndex
        while i < name.endIndex {
            if name[i] == "\\" {
                let next = name.index(after: i)
                if next < name.endIndex {
                    switch name[next] {
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    default:
                        result.append("\\")
                        result.append(name[next])
                    }
                    i = name.index(i, offsetBy: 2)
                } else {
                    result.append("\\")
                    i = name.index(after: i)
                }
            } else {
                result.append(name[i])
                i = name.index(after: i)
            }
        }
        return result
    }

    /// Build an AppleScript string expression, handling backslashes, quotes,
    /// and newlines (which cannot appear inside an AppleScript string literal).
    static func appleScriptStringLiteral(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        if !escaped.contains("\n") && !escaped.contains("\r") {
            return "\"\(escaped)\""
        }

        // Names with newlines must use concatenation with ASCII character refs.
        var parts: [String] = []
        var current = ""
        for char in escaped {
            switch char {
            case "\n":
                if !current.isEmpty { parts.append("\"\(current)\"") }
                parts.append("(ASCII character 10)")
                current = ""
            case "\r":
                if !current.isEmpty { parts.append("\"\(current)\"") }
                parts.append("(ASCII character 13)")
                current = ""
            default:
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append("\"\(current)\"") }
        return parts.joined(separator: " & ")
    }
}
