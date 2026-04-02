import Foundation

/// Error types for profile operations.
enum ProfileError: LocalizedError {
    case profileNotFound(String)
    case profileAlreadyExists(String)
    case parseError(String)
    case directoryError(String)
    case invalidProfileName(String)
    case cannotRenameAutoProfile

    var errorDescription: String? {
        switch self {
        case .profileNotFound(let name): return "Profile \"\(name)\" not found"
        case .profileAlreadyExists(let name): return "Profile \"\(name)\" already exists"
        case .parseError(let msg): return "Profile parse error: \(msg)"
        case .directoryError(let msg): return "Profile directory error: \(msg)"
        case .invalidProfileName(let msg): return "Invalid profile name: \(msg)"
        case .cannotRenameAutoProfile: return "Auto-profiles cannot be renamed"
        }
    }
}

/// Manages profile storage in ~/.desktop_icon_profiles/.
/// Reads both pipe-delimited (.txt) and JSON (.json) formats.
/// Always writes JSON (.json).
final class ProfileManager {

    /// Shared profile directory (same as shell script).
    static let profileDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".desktop_icon_profiles", isDirectory: true)
    }()

    /// Ensure profile directory exists.
    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: profileDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Validate that a profile name is safe for use as a filename.
    static func validateProfileName(_ name: String) throws {
        guard !name.isEmpty else {
            throw ProfileError.invalidProfileName("must not be empty")
        }
        guard !name.hasPrefix(".") else {
            throw ProfileError.invalidProfileName("must not start with '.'")
        }
        guard !name.contains("/"), !name.contains("\0") else {
            throw ProfileError.invalidProfileName("contains invalid characters")
        }
        guard !name.contains("..") else {
            throw ProfileError.invalidProfileName("must not contain '..'")
        }
    }

    // MARK: - List

    /// Summary info for displaying in menus.
    struct ProfileSummary: Identifiable {
        let id: String  // profile name
        let name: String
        let iconCount: Int
        let displayCount: Int
        let fingerprint: String
        let format: String  // "json" or "txt"
    }

    /// List all saved profiles (both .json and .txt).
    static func listProfiles() throws -> [ProfileSummary] {
        try ensureDirectory()
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: profileDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )

        var summaries: [ProfileSummary] = []
        var seen: Set<String> = []

        // JSON profiles take precedence
        for url in contents where url.pathExtension == "json" {
            let name = url.deletingPathExtension().lastPathComponent
            seen.insert(name)
            if let profile = try? loadJSON(from: url) {
                summaries.append(ProfileSummary(
                    id: name, name: name,
                    iconCount: profile.iconCount,
                    displayCount: profile.displayCount,
                    fingerprint: profile.fingerprint,
                    format: "json"
                ))
            }
        }

        // Then pipe-delimited profiles (skip if JSON version exists)
        for url in contents where url.pathExtension == "txt" {
            let name = url.deletingPathExtension().lastPathComponent
            guard !seen.contains(name) else { continue }
            if let profile = try? parsePipeDelimited(from: url) {
                summaries.append(ProfileSummary(
                    id: name, name: name,
                    iconCount: profile.iconCount,
                    displayCount: profile.displayCount,
                    fingerprint: profile.fingerprint,
                    format: "txt"
                ))
            }
        }

        return summaries.sorted { $0.name < $1.name }
    }

    // MARK: - Load

    /// Load a profile by name. Tries .json first, then .txt.
    static func loadProfile(name: String) throws -> Profile {
        try validateProfileName(name)
        let jsonURL = profileDirectory.appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return try loadJSON(from: jsonURL)
        }

        let txtURL = profileDirectory.appendingPathComponent("\(name).txt")
        if FileManager.default.fileExists(atPath: txtURL.path) {
            return try parsePipeDelimited(from: txtURL)
        }

        throw ProfileError.profileNotFound(name)
    }

    // MARK: - Save (always JSON)

    /// Save a profile as JSON.
    static func saveProfile(_ profile: Profile, name: String, allowReservedAutoName: Bool = false) throws {
        try validateProfileName(name)
        guard allowReservedAutoName || !name.hasPrefix("Auto-") else {
            throw ProfileError.invalidProfileName("names starting with 'Auto-' are reserved for automatic profiles")
        }
        try ensureDirectory()
        let url = profileDirectory.appendingPathComponent("\(name).json")
        let data = try JSONEncoder.prettyEncoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Search

    /// Find the first profile matching the given fingerprint.
    static func findProfile(forFingerprint fingerprint: String) throws -> (name: String, profile: Profile)? {
        let summaries = try listProfiles()
        for summary in summaries where summary.fingerprint == fingerprint {
            let profile = try loadProfile(name: summary.name)
            return (summary.name, profile)
        }
        return nil
    }

    /// Find the best auto-profile matching the given fingerprint.
    /// Prefers Auto-prefixed profiles; falls back to any match if none exist.
    static func findAutoProfile(forFingerprint fingerprint: String) throws -> (name: String, profile: Profile)? {
        let summaries = try listProfiles()
        let matching = summaries.filter { $0.fingerprint == fingerprint }

        if let auto = matching.first(where: { $0.name.hasPrefix("Auto-") }) {
            let profile = try loadProfile(name: auto.name)
            return (auto.name, profile)
        }

        if let first = matching.first {
            let profile = try loadProfile(name: first.name)
            return (first.name, profile)
        }

        return nil
    }

    /// Generate a human-friendly auto-profile name from display names and fingerprint.
    /// e.g. "Auto-Built-in+DELL-U2720Q_a1b2c3d4"
    static func autoProfileName(fingerprint: String, displayNames: [String] = []) -> String {
        let hash = String(fingerprint.prefix(8))
        guard !displayNames.isEmpty else {
            return "Auto-\(hash)"
        }
        let sanitized = displayNames.map { name in
            // Shorten common prefixes, replace spaces/special chars with hyphens
            name.replacingOccurrences(of: "Built-in Retina Display", with: "Built-in")
                .replacingOccurrences(of: "Built-in Display", with: "Built-in")
                .replacingOccurrences(of: " ", with: "-")
                .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
                .joined()
        }
        let joined = sanitized.joined(separator: "+")
        // Truncate to keep filename reasonable (max ~60 chars for the name part)
        let truncated = String(joined.prefix(50))
        return "Auto-\(truncated)_\(hash)"
    }

    // MARK: - Delete

    /// Delete a profile by name. Removes both .json and .txt versions if they exist.
    static func deleteProfile(name: String) throws {
        try validateProfileName(name)
        let fm = FileManager.default
        let jsonURL = profileDirectory.appendingPathComponent("\(name).json")
        let txtURL = profileDirectory.appendingPathComponent("\(name).txt")
        var deleted = false
        if fm.fileExists(atPath: jsonURL.path) {
            try fm.removeItem(at: jsonURL)
            deleted = true
        }
        if fm.fileExists(atPath: txtURL.path) {
            try fm.removeItem(at: txtURL)
            deleted = true
        }
        if !deleted {
            throw ProfileError.profileNotFound(name)
        }
    }

    // MARK: - Rename

    /// Rename a profile. Loads from old name, saves as new name (JSON), deletes old.
    /// Throws if the new name already exists to prevent accidental data loss.
    static func renameProfile(from oldName: String, to newName: String) throws {
        guard !oldName.hasPrefix("Auto-") else {
            throw ProfileError.cannotRenameAutoProfile
        }
        try validateProfileName(newName)
        let fm = FileManager.default
        let jsonURL = profileDirectory.appendingPathComponent("\(newName).json")
        let txtURL = profileDirectory.appendingPathComponent("\(newName).txt")
        if fm.fileExists(atPath: jsonURL.path) || fm.fileExists(atPath: txtURL.path) {
            throw ProfileError.profileAlreadyExists(newName)
        }
        let profile = try loadProfile(name: oldName)
        try saveProfile(profile, name: newName)
        try deleteProfile(name: oldName)
    }

    // MARK: - Parse Pipe-Delimited (.txt)

    /// Parse a shell-script-format profile from a URL.
    private static func parsePipeDelimited(from url: URL) throws -> Profile {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parsePipeDelimitedContent(content)
    }

    /// Parse pipe-delimited profile content. Internal for testing.
    static func parsePipeDelimitedContent(_ content: String) -> Profile {
        let lines = content.components(separatedBy: .newlines)

        var fingerprint = ""
        var displays: [DisplayFrame] = []
        var settings = DesktopSettings(iconSize: 64, textSize: 12)
        var icons: [IconPosition] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#FINGERPRINT|") {
                fingerprint = String(trimmed.dropFirst("#FINGERPRINT|".count))
            } else if trimmed.hasPrefix("#DISPLAY|") {
                let parts = String(trimmed.dropFirst("#DISPLAY|".count)).split(separator: "|")
                if parts.count == 4,
                   let x = Int(parts[0]), let y = Int(parts[1]),
                   let w = Int(parts[2]), let h = Int(parts[3]) {
                    displays.append(DisplayFrame(x: x, y: y, width: w, height: h))
                }
            } else if trimmed.hasPrefix("#SETTINGS|") {
                let parts = String(trimmed.dropFirst("#SETTINGS|".count)).split(separator: "|")
                if parts.count == 2, let iSize = Int(parts[0]), let tSize = Int(parts[1]) {
                    settings = DesktopSettings(iconSize: iSize, textSize: tSize)
                }
            } else if trimmed.hasPrefix("#") {
                continue  // skip unknown metadata
            } else {
                // Icon line: name|x|y — parse from right to handle | in names
                guard let lastPipe = trimmed.lastIndex(of: "|") else { continue }
                let beforeLast = trimmed[trimmed.startIndex..<lastPipe]
                guard let secondPipe = beforeLast.lastIndex(of: "|") else { continue }

                let name = String(trimmed[trimmed.startIndex..<secondPipe])
                let xStr = trimmed[trimmed.index(after: secondPipe)..<lastPipe]
                let yStr = trimmed[trimmed.index(after: lastPipe)...]

                if let x = Int(xStr.trimmingCharacters(in: .whitespaces)),
                   let y = Int(yStr.trimmingCharacters(in: .whitespaces)),
                   !name.isEmpty {
                    icons.append(IconPosition(name: name, x: x, y: y))
                }
            }
        }

        return Profile(fingerprint: fingerprint, displays: displays, settings: settings, icons: icons)
    }

    // MARK: - Load JSON

    private static func loadJSON(from url: URL) throws -> Profile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Profile.self, from: data)
    }
}

// MARK: - JSONEncoder extension

private extension JSONEncoder {
    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
