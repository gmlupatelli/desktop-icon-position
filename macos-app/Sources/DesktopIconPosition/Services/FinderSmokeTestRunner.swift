import Foundation

/// Opt-in manual smoke test for the real Finder read/write code paths.
/// Creates temporary desktop items with edge-case names, waits for Finder
/// to surface them, exercises read + write, then removes the fixtures.
@MainActor
enum FinderSmokeTestRunner {
    static let flag = "--finder-smoke-test"

    static func isEnabled(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(flag)
    }

    static func run() async -> Int32 {
        let fixtureURLs = makeFixtureURLs()
        defer { cleanupFixtures(at: fixtureURLs) }

        do {
            print("Finder smoke test: checking Finder Automation permission")
            guard FinderService.checkPermission() else {
                fputs("Finder smoke test requires Finder Automation permission.\n", stderr)
                return 2
            }

            print("Finder smoke test: creating temporary desktop files")
            try createFixtures(at: fixtureURLs)

            let names = fixtureURLs.map(\.lastPathComponent)
            print("Finder smoke test: waiting for Finder to index temporary items")
            let currentIcons = try await waitForIcons(named: names)

            print("Finder smoke test: exercising batch write with edge-case names")
            let iconsToRewrite = names.compactMap { currentIcons[$0] }
            guard iconsToRewrite.count == names.count else {
                let missing = names.filter { currentIcons[$0] == nil }
                throw SmokeTestError.missingIcons(missing)
            }
            try FinderService.batchSetPositions(iconsToRewrite)

            print("Finder smoke test passed")
            return 0
        } catch {
            fputs("Finder smoke test failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private static func makeFixtureURLs() -> [URL] {
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let prefix = "DesktopIconPosition Smoke \(pid)"
        let names = [
            "\(prefix) plain.txt",
            "\(prefix) pipe|name.txt",
            "\(prefix) quote\"name.txt",
            "\(prefix) backslash\\name.txt",
            "\(prefix) line1\nline2.txt",
        ]
        return names.map { desktopURL.appendingPathComponent($0) }
    }

    private static func createFixtures(at urls: [URL]) throws {
        for url in urls {
            let created = FileManager.default.createFile(atPath: url.path, contents: Data())
            if !created {
                throw SmokeTestError.fixtureCreateFailed(url.lastPathComponent)
            }
        }
    }

    private static func cleanupFixtures(at urls: [URL]) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func waitForIcons(named names: [String], attempts: Int = 15) async throws -> [String: IconPosition] {
        var lastMap: [String: IconPosition] = [:]

        for _ in 0..<attempts {
            let icons = try FinderService.readIconPositions()
            lastMap = Dictionary(icons.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

            if names.allSatisfy({ lastMap[$0] != nil }) {
                return lastMap
            }

            try await Task.sleep(for: .seconds(1))
        }

        let missing = names.filter { lastMap[$0] == nil }
        throw SmokeTestError.missingIcons(missing)
    }
}

private enum SmokeTestError: LocalizedError {
    case fixtureCreateFailed(String)
    case missingIcons([String])

    var errorDescription: String? {
        switch self {
        case .fixtureCreateFailed(let name):
            return "Unable to create smoke-test fixture \"\(name)\""
        case .missingIcons(let names):
            let formatted = names.map(\.debugDescription).joined(separator: ", ")
            return "Finder did not surface expected desktop items: \(formatted)"
        }
    }
}
