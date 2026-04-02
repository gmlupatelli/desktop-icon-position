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

    // MARK: - findAutoProfile

    @Test("findAutoProfile prefers Auto-prefixed profile over alphabetically earlier manual profile")
    func findAutoProfilePrefersAutoPrefix() throws {
        let fp = "test-fingerprint-\(UUID().uuidString)"
        let profile = Profile(
            fingerprint: fp,
            displays: [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)],
            settings: DesktopSettings(iconSize: 64, textSize: 12),
            icons: [IconPosition(name: "file.txt", x: 100, y: 200)]
        )

        // "AAA-manual" sorts before "Auto-..."
        try ProfileManager.saveProfile(profile, name: "AAA-manual-\(fp)")
        try ProfileManager.saveProfile(profile, name: "Auto-test_\(fp)", allowReservedAutoName: true)
        defer {
            try? ProfileManager.deleteProfile(name: "AAA-manual-\(fp)")
            try? ProfileManager.deleteProfile(name: "Auto-test_\(fp)")
        }

        let result = try ProfileManager.findAutoProfile(forFingerprint: fp)
        #expect(result != nil)
        #expect(result?.name.hasPrefix("Auto-") == true)
    }

    @Test("findAutoProfile falls back to manual profile when no Auto-profile exists")
    func findAutoProfileFallsBackToManual() throws {
        let fp = "fallback-fingerprint-\(UUID().uuidString)"
        let profile = Profile(
            fingerprint: fp,
            displays: [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)],
            settings: DesktopSettings(iconSize: 64, textSize: 12),
            icons: [IconPosition(name: "file.txt", x: 100, y: 200)]
        )

        try ProfileManager.saveProfile(profile, name: "Manual-only-\(fp)")
        defer {
            try? ProfileManager.deleteProfile(name: "Manual-only-\(fp)")
        }

        let result = try ProfileManager.findAutoProfile(forFingerprint: fp)
        #expect(result != nil)
        #expect(result?.name == "Manual-only-\(fp)")
    }

    // MARK: - renameProfile blocks Auto-profiles

    @Test("renaming an Auto-profile throws cannotRenameAutoProfile")
    func renameAutoProfileBlocked() throws {
        let fp = "rename-block-\(UUID().uuidString)"
        let profile = Profile(
            fingerprint: fp,
            displays: [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)],
            settings: DesktopSettings(iconSize: 64, textSize: 12),
            icons: [IconPosition(name: "file.txt", x: 100, y: 200)]
        )

        let autoName = "Auto-test_\(fp)"
        try ProfileManager.saveProfile(profile, name: autoName, allowReservedAutoName: true)
        defer {
            try? ProfileManager.deleteProfile(name: autoName)
            try? ProfileManager.deleteProfile(name: "New-name")
        }

        #expect(throws: ProfileError.self) {
            try ProfileManager.renameProfile(from: autoName, to: "New-name")
        }

        // Verify the auto-profile still exists
        let loaded = try ProfileManager.loadProfile(name: autoName)
        #expect(loaded.fingerprint == fp)
    }

    @Test("manual save rejects Auto-prefixed names")
    func manualSaveRejectsAutoPrefix() {
        let fp = "reserved-auto-save-\(UUID().uuidString)"
        let profile = Profile(
            fingerprint: fp,
            displays: [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)],
            settings: DesktopSettings(iconSize: 64, textSize: 12),
            icons: [IconPosition(name: "file.txt", x: 100, y: 200)]
        )

        #expect(throws: ProfileError.self) {
            try ProfileManager.saveProfile(profile, name: "Auto-manual-\(fp)")
        }
    }

    @Test("renaming a manual profile to an Auto-prefixed name is rejected")
    func renameManualProfileToAutoPrefixBlocked() throws {
        let fp = "rename-to-auto-\(UUID().uuidString)"
        let manualName = "Manual-\(fp)"
        let autoName = "Auto-test_\(fp)"
        let profile = Profile(
            fingerprint: fp,
            displays: [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)],
            settings: DesktopSettings(iconSize: 64, textSize: 12),
            icons: [IconPosition(name: "file.txt", x: 100, y: 200)]
        )

        try ProfileManager.saveProfile(profile, name: manualName)
        defer {
            try? ProfileManager.deleteProfile(name: manualName)
            try? ProfileManager.deleteProfile(name: autoName)
        }

        #expect(throws: ProfileError.self) {
            try ProfileManager.renameProfile(from: manualName, to: autoName)
        }

        let loaded = try ProfileManager.loadProfile(name: manualName)
        #expect(loaded.fingerprint == fp)
        #expect(throws: ProfileError.self) {
            try ProfileManager.loadProfile(name: autoName)
        }
    }
}
