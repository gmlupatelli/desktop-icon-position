import Testing
import Foundation
@testable import DesktopIconPosition

@Suite("ProfileManager")
struct ProfileManagerTests {

    @Test("profile survives JSON encode-decode round trip")
    func jsonRoundTrip() throws {
        let profile = Profile(
            fingerprint: "abc123def456",
            displays: [
                DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
                DisplayFrame(x: 1920, y: 0, width: 1080, height: 1920),
            ],
            settings: DesktopSettings(iconSize: 64, textSize: 12),
            icons: [
                IconPosition(name: "file.txt", x: 100, y: 200),
                IconPosition(name: "photo.jpg", x: 300, y: 400),
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)

        #expect(decoded.fingerprint == profile.fingerprint)
        #expect(decoded.displays == profile.displays)
        #expect(decoded.settings == profile.settings)
        #expect(decoded.icons == profile.icons)
        #expect(decoded.displayCount == 2)
        #expect(decoded.iconCount == 2)
    }

    @Test("auto profile name uses first 8 chars of fingerprint")
    func autoProfileName() {
        let name = ProfileManager.autoProfileName(fingerprint: "566459849ad08e7084399efd0414acb8")
        #expect(name == "auto_56645984")
    }
}
