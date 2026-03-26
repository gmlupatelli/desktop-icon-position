import Foundation

/// Desktop icon/text size settings from Finder.
struct DesktopSettings: Codable, Hashable, Sendable {
    let iconSize: Int
    let textSize: Int
}

/// A saved profile containing display geometry, settings, and icon positions.
struct Profile: Codable, Sendable {
    let fingerprint: String
    let displays: [DisplayFrame]
    let settings: DesktopSettings
    let icons: [IconPosition]

    var displayCount: Int { displays.count }
    var iconCount: Int { icons.count }
}
