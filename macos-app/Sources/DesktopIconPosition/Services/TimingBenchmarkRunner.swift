import Foundation

/// CLI benchmark that exercises a full save → restore cycle and prints timing.
/// Run with: swift run DesktopIconPosition --timing-benchmark
@MainActor
enum TimingBenchmarkRunner {
    static let flag = "--timing-benchmark"

    static func isEnabled(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(flag)
    }

    static func run() async -> Int32 {
        print("=== Timing Benchmark ===")
        print()

        guard FinderService.checkPermission() else {
            fputs("Benchmark requires Finder Automation permission.\n", stderr)
            return 2
        }

        let profileName = "__timing_benchmark__"

        // --- SAVE ---
        print("--- SAVE ---")
        let saveStart = CFAbsoluteTimeGetCurrent()
        do {
            let frames = TimingLog.measure("save: currentFrames") { DisplayService.currentFrames() }
            let fingerprint = TimingLog.measure("save: fingerprint") { DisplayService.fingerprint() }
            let settings = try TimingLog.measure("save: readSettings") { try FinderService.readSettings() }
            let icons = try TimingLog.measure("save: readIconPositions") { try FinderService.readIconPositions() }

            let profile = Profile(
                fingerprint: fingerprint,
                displays: frames,
                settings: settings,
                icons: icons
            )
            try TimingLog.measure("save: writeProfile") {
                try ProfileManager.saveProfile(profile, name: profileName, allowReservedAutoName: false)
            }
            TimingLog.summary("SAVE TOTAL", startTime: saveStart)
            print("  → \(icons.count) icons saved")
        } catch {
            fputs("Save failed: \(error.localizedDescription)\n", stderr)
            cleanup(profileName)
            return 1
        }

        print()

        // --- RESTORE ---
        print("--- RESTORE ---")
        let restoreStart = CFAbsoluteTimeGetCurrent()
        do {
            let profile = try TimingLog.measure("restore: loadProfile") {
                try ProfileManager.loadProfile(name: profileName)
            }
            let currentDisplays = TimingLog.measure("restore: currentFrames") {
                DisplayService.currentFrames()
            }

            var icons = profile.icons
            if profile.displays != currentDisplays && !profile.displays.isEmpty {
                icons = TimingLog.measure("restore: remap") {
                    CoordinateConverter.remap(icons: icons, from: profile.displays, to: currentDisplays)
                }
            }

            try TimingLog.measure("restore: prepareForRestore") {
                try FinderService.prepareForRestore(profile.settings)
            }
            try TimingLog.measure("restore: batchSetPositions") {
                try FinderService.batchSetPositions(icons)
            }
            TimingLog.summary("RESTORE (before verify)", startTime: restoreStart)

            // Verify pass (simulates the 3s wait)
            print()
            print("--- VERIFY (after 3s wait) ---")
            try await Task.sleep(for: .seconds(3))
            let corrected = try TimingLog.measure("restore: verifyAndReapply") {
                try FinderService.verifyAndReapply(expected: icons)
            }
            TimingLog.summary("RESTORE TOTAL (with verify)", startTime: restoreStart)
            print("  → \(icons.count) icons restored, \(corrected) corrected")
        } catch {
            fputs("Restore failed: \(error.localizedDescription)\n", stderr)
            cleanup(profileName)
            return 1
        }

        print()
        print("=== Benchmark Complete ===")

        cleanup(profileName)
        return 0
    }

    private static func cleanup(_ name: String) {
        try? ProfileManager.deleteProfile(name: name)
    }
}
