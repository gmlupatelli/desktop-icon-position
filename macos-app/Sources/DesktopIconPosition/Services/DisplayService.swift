import AppKit
import CryptoKit
import Foundation

/// Reads display geometry from NSScreen and observes display configuration changes.
@MainActor
final class DisplayService {

    /// Returns display frames in Quartz/CG coordinates (matching Finder's coordinate system).
    /// Converts from NSScreen's Cocoa coordinates (bottom-left origin) to CG (top-left origin).
    static func currentFrames() -> [DisplayFrame] {
        let screens = NSScreen.screens
        guard let mainScreen = screens.first else { return [] }
        let mainHeight = Int(mainScreen.frame.size.height)

        return screens.map { screen in
            let f = screen.frame
            let cgX = Int(f.origin.x.rounded())
            let cgY = mainHeight - Int(f.origin.y.rounded()) - Int(f.size.height.rounded())
            let w = Int(f.size.width.rounded())
            let h = Int(f.size.height.rounded())
            return DisplayFrame(x: cgX, y: cgY, width: w, height: h)
        }
    }

    /// Number of currently connected displays.
    static func displayCount() -> Int {
        NSScreen.screens.count
    }

    /// MD5 fingerprint of the current display configuration.
    /// Matches the shell script algorithm: sort pipe-delimited frames, then MD5.
    static func fingerprint() -> String {
        let frames = currentFrames()
        let sorted = frames.map(\.pipeString).sorted()
        let input = sorted.joined(separator: "\n") + "\n"
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns localized display names (e.g. "Built-in Retina Display", "DELL U2720Q").
    static func displayNames() -> [String] {
        NSScreen.screens.map { $0.localizedName }
    }

    /// Observe display configuration changes via NSApplication notification.
    /// Calls the handler on the main actor after the specified delay (seconds).
    static func observeDisplayChanges(
        delay: TimeInterval = 5.0,
        handler: @escaping @Sendable () -> Void
    ) -> NSObjectProtocol {
        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                handler()
            }
        }
        return observer
    }
}
