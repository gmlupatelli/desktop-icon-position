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
        #expect(name == "Auto-56645984")
    }
    @Test func autoProfileNameWithDisplayNames() {
        let name = ProfileManager.autoProfileName(
            fingerprint: "566459849ad08e7084399efd0414acb8",
            displayNames: ["Built-in Retina Display", "DELL U2720Q"]
        )
        #expect(name == "Auto-Built-in+DELL-U2720Q_56645984")
    }

    // MARK: - validateProfileName

    @Test("valid profile names are accepted")
    func validateValidNames() throws {
        try ProfileManager.validateProfileName("my-profile")
        try ProfileManager.validateProfileName("Profile 1")
        try ProfileManager.validateProfileName("Auto-Built-in_56645984")
    }

    @Test("empty name is rejected")
    func validateEmptyName() {
        #expect(throws: ProfileError.self) {
            try ProfileManager.validateProfileName("")
        }
    }

    @Test("name starting with dot is rejected")
    func validateDotPrefix() {
        #expect(throws: ProfileError.self) {
            try ProfileManager.validateProfileName(".hidden")
        }
    }

    @Test("name containing slash is rejected")
    func validateSlash() {
        #expect(throws: ProfileError.self) {
            try ProfileManager.validateProfileName("../../etc/evil")
        }
    }

    @Test("name containing dot-dot is rejected")
    func validateDotDot() {
        #expect(throws: ProfileError.self) {
            try ProfileManager.validateProfileName("foo..bar")
        }
    }

    // MARK: - parsePipeDelimitedContent

    @Test("pipe-delimited icon with pipe in name parsed correctly")
    func parsePipeInName() {
        let content = """
        #FINGERPRINT|abc123
        #SETTINGS|64|12
        file|name.txt|100|200
        normal.txt|300|400
        """
        let profile = ProfileManager.parsePipeDelimitedContent(content)
        #expect(profile.icons.count == 2)
        #expect(profile.icons[0].name == "file|name.txt")
        #expect(profile.icons[0].x == 100)
        #expect(profile.icons[0].y == 200)
        #expect(profile.icons[1].name == "normal.txt")
        #expect(profile.fingerprint == "abc123")
    }

    @Test("pipe-delimited with multiple pipes in name")
    func parseMultiplePipesInName() {
        let content = "a|b|c|50|60\n"
        let profile = ProfileManager.parsePipeDelimitedContent(content)
        #expect(profile.icons.count == 1)
        #expect(profile.icons[0].name == "a|b|c")
        #expect(profile.icons[0].x == 50)
    }
}
