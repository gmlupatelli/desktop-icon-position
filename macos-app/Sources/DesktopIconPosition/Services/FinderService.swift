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
        let source = """
        tell application "Finder"
            set allItems to every item of desktop
            set posData to ""
            repeat with anItem in allItems
                try
                    set itemName to name of anItem as text
                    set itemPos to desktop position of anItem
                    set posX to item 1 of itemPos as integer
                    set posY to item 2 of itemPos as integer
                    set posData to posData & itemName & "|" & posX & "|" & posY & linefeed
                end try
            end repeat
        end tell
        return posData
        """
        let output = try executeAppleScript(source)
        return parseIconPositions(output)
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
        guard !icons.isEmpty else { return }
        var setStatements = ""
        for icon in icons {
            let escaped = icon.name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            setStatements += """
                        try
                            set desktop position of item "\(escaped)" of desktop to {\(icon.x), \(icon.y)}
                        end try
            
            """
        }
        let source = """
        tell application "Finder"
            ignoring application responses
        \(setStatements)    end ignoring
        end tell
        return "done"
        """
        try executeAppleScript(source)
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

    private static func parseIconPositions(_ output: String) -> [IconPosition] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3,
                  let x = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  let y = Int(parts[2].trimmingCharacters(in: .whitespaces)) else {
                return nil
            }
            return IconPosition(name: String(parts[0]), x: x, y: y)
        }
    }
}
