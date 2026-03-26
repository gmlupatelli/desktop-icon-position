import Testing
@testable import DesktopIconPosition

@Suite("CoordinateConverter")
struct CoordinateConverterTests {

    // MARK: - findDisplay

    @Test("finds correct display for point inside bounds")
    func findDisplayInside() {
        let displays = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 912, y: -1080, width: 1920, height: 1080),
        ]
        let found = CoordinateConverter.findDisplay(forPoint: 1000, -500, in: displays)
        #expect(found == displays[1])
    }

    @Test("falls back to first display when point is outside all displays")
    func findDisplayFallback() {
        let displays = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
        ]
        let found = CoordinateConverter.findDisplay(forPoint: 5000, 5000, in: displays)
        #expect(found == displays[0])
    }

    // MARK: - remap: identity

    @Test("same display layout returns identical positions")
    func remapIdentity() {
        let displays = [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)]
        let icons = [IconPosition(name: "test.txt", x: 100, y: 200)]
        let result = CoordinateConverter.remap(icons: icons, from: displays, to: displays)
        #expect(result == icons)
    }

    // MARK: - remap: two displays to one

    @Test("icon on secondary display maps to primary when secondary removed")
    func remapTwoToOne() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
        ]
        let icons = [IconPosition(name: "file.txt", x: 1900, y: 50)]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)
        #expect(result[0].x == 108)
        #expect(result[0].y == 50)
    }

    // MARK: - remap: boundary clamping

    @Test("icon at extreme position is clamped with 20px padding")
    func remapClamping() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 3840, height: 2160),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let icons = [IconPosition(name: "far.txt", x: 3800, y: 2100)]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)
        #expect(result[0].x == 1900)
        #expect(result[0].y == 1060)
    }

    @Test("icon near origin is clamped to minimum padding")
    func remapClampingMin() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 100, y: 100, width: 1920, height: 1080),
        ]
        let icons = [IconPosition(name: "corner.txt", x: 5, y: 5)]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)
        #expect(result[0].x == 120)
        #expect(result[0].y == 120)
    }
}
