@testable import DesktopIconPosition
import Testing

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

    // MARK: - DisplayFrame helpers

    @Test("center computes correctly")
    func displayCenter() {
        let frame = DisplayFrame(x: 100, y: 200, width: 1920, height: 1080)
        #expect(frame.center.x == 1060)
        #expect(frame.center.y == 740)
    }

    @Test("overlapArea with full overlap")
    func overlapFull() {
        let a = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        #expect(a.overlapArea(with: a) == 1920 * 1080)
    }

    @Test("overlapArea with no overlap")
    func overlapNone() {
        let a = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let b = DisplayFrame(x: 2000, y: 0, width: 1920, height: 1080)
        #expect(a.overlapArea(with: b) == 0)
    }

    @Test("overlapArea with partial overlap")
    func overlapPartial() {
        let a = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let b = DisplayFrame(x: 960, y: 540, width: 1920, height: 1080)
        #expect(a.overlapArea(with: b) == 960 * 540)
    }

    // MARK: - matchDisplays

    @Test("identical displays map 1:1")
    func matchIdentical() {
        let displays = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080),
        ]
        let mapping = CoordinateConverter.matchDisplays(saved: displays, current: displays)
        #expect(mapping[0] == 0)
        #expect(mapping[1] == 1)
    }

    @Test("3 saved to 2 current: removed display maps to closest")
    func matchThreeToTwo() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120), // Built-in
            DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080), // DELL left
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080), // DELL right
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120), // Built-in
            DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080), // DELL left
        ]
        let mapping = CoordinateConverter.matchDisplays(saved: saved, current: current)
        #expect(mapping[0] == 0) // Built-in → Built-in
        #expect(mapping[1] == 1) // DELL left → DELL left
        #expect(mapping[2] == 0) // DELL right (removed) → closest = Built-in
    }

    @Test("shifted layout maps 1:1 instead of collapsing")
    func matchShifted() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
            DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 960, y: 0, width: 1920, height: 1080),
            DisplayFrame(x: 2880, y: 0, width: 1920, height: 1080),
        ]
        let mapping = CoordinateConverter.matchDisplays(saved: saved, current: current)
        #expect(mapping[0] == 0) // saved left → current left
        #expect(mapping[1] == 1) // saved right → current right
    }

    @Test("swapped displays map to correct new positions")
    func matchSwapped() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
            DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080),
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let mapping = CoordinateConverter.matchDisplays(saved: saved, current: current)
        #expect(mapping[0] == 1) // saved[0] was at (0,0) → current[1] is now at (0,0)
        #expect(mapping[1] == 0) // saved[1] was at (1920,0) → current[0] is now at (1920,0)
    }

    @Test("3→2 with overlap ambiguity: unique assignment + tiebreaker")
    func matchThreeToTwoAmbiguous() {
        // saved[0] and saved[1] both overlap current[0], but saved[0] overlaps more.
        // saved[2] only overlaps current[1].
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080), // overlaps current[0] fully
            DisplayFrame(
                x: 1440,
                y: 0,
                width: 1920,
                height: 1080
            ), // overlaps current[0] partially, current[1] partially
            DisplayFrame(x: 3840, y: 0, width: 1920, height: 1080), // overlaps current[1] partially
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080), // full match for saved[0]
            DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080), // partial match for saved[1] and saved[2]
        ]
        let mapping = CoordinateConverter.matchDisplays(saved: saved, current: current)
        #expect(mapping[0] == 0) // saved[0] → current[0] (full overlap)
        #expect(mapping[1] == 1) // saved[1] → current[1] (unique assignment forces it off current[0])
        // saved[2] has no remaining unclaimed display → falls back to best match
        #expect(mapping[2] == 1) // saved[2] → current[1] (closest/most overlap)
    }

    // MARK: - remap: identity

    @Test("same display layout returns identical positions")
    func remapIdentity() {
        let displays = [DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)]
        let icons = [IconPosition(name: "test.txt", x: 100, y: 200)]
        let result = CoordinateConverter.remap(icons: icons, from: displays, to: displays)
        #expect(result == icons)
    }

    // MARK: - remap: two displays to one (displaced icons parked at bottom)

    @Test("icon on removed display is parked at bottom of remaining display")
    func remapTwoToOneParking() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
        ]
        let icons = [IconPosition(name: "file.txt", x: 1900, y: 50)]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)
        // Icon from removed display should be parked at bottom of primary
        #expect(result[0].y > 900) // near bottom
        #expect(result[0].x >= 20) // within bounds
        #expect(result[0].x <= 1772)
    }

    @Test("icon on remaining display keeps its position")
    func remapTwoToOneNative() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
        ]
        let icons = [IconPosition(name: "native.txt", x: 100, y: 200)]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)
        #expect(result[0].x == 100)
        #expect(result[0].y == 200)
    }

    // MARK: - remap: three displays to two

    @Test("3→2: icons on remaining displays stay, displaced icons parked at bottom")
    func remapThreeToTwo() throws {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080),
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: -1920, y: 0, width: 1920, height: 1080),
        ]
        let icons = [
            IconPosition(name: "builtin.txt", x: 100, y: 100), // on Built-in
            IconPosition(name: "left.txt", x: -1800, y: 50), // on DELL left
            IconPosition(name: "right.txt", x: 1900, y: 50), // on DELL right (removed)
        ]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)

        // Icons on remaining displays keep positions
        let builtin = try #require(result.first { $0.name == "builtin.txt" })
        #expect(builtin.x == 100)
        #expect(builtin.y == 100)

        let left = try #require(result.first { $0.name == "left.txt" })
        #expect(left.x == -1800)
        #expect(left.y == 50)

        // Icon on removed display is parked at bottom of its target (Built-in)
        let right = try #require(result.first { $0.name == "right.txt" })
        #expect(right.y > 900) // near bottom of Built-in (height 1120)
        #expect(right.x >= 20 && right.x <= 1772)
    }

    // MARK: - remap: displaced icons grid spacing

    @Test("multiple displaced icons are spaced out in a grid at bottom")
    func remapMultipleDisplacedSpacing() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
            DisplayFrame(x: 1920, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let icons = [
            IconPosition(name: "a.txt", x: 2000, y: 50),
            IconPosition(name: "b.txt", x: 2100, y: 50),
            IconPosition(name: "c.txt", x: 2200, y: 50),
        ]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)

        // All should be parked near bottom
        for icon in result {
            #expect(icon.y > 800)
        }

        // All should have distinct x positions (spaced out)
        let xs = Set(result.map(\.x))
        #expect(xs.count == 3)
    }

    // MARK: - remap: boundary clamping

    @Test("icon at extreme position is clamped with 20px padding")
    func remapClamping() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 800, height: 600),
        ]
        let icons = [IconPosition(name: "far.txt", x: 1800, y: 1000)]
        let result = CoordinateConverter.remap(icons: icons, from: saved, to: current)
        // Displaced (no overlap since sizes differ completely, but there IS overlap
        // because both start at 0,0). Actually 800x600 overlaps with 1920x1080 at 0,0.
        // So this is a native icon, clamped to smaller display.
        #expect(result[0].x == 780) // 0 + 800 - 20
        #expect(result[0].y == 580) // 0 + 600 - 20
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
        // These displays don't overlap (saved starts at 0, current at 100, but
        // saved 0..1920 overlaps with current 100..2020), so there IS overlap.
        // relX = 5-0 = 5, newX = 100+5 = 105, clamped to min 120
        #expect(result[0].x == 120)
        #expect(result[0].y == 120)
    }

    // MARK: - parkIcons: zone directions

    @Test("parkIcons bottomRight fills left then up")
    func parkIconsBottomRight() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let icons = [
            IconPosition(name: "a.txt", x: 0, y: 0),
            IconPosition(name: "b.txt", x: 0, y: 0),
        ]
        let result = CoordinateConverter.parkIcons(
            icons, in: .bottomRight, on: display, iconSize: 60, avoiding: []
        )
        // First icon should be rightmost, second to its left
        #expect(result[0].x > result[1].x)
        // Both near the bottom
        #expect(result[0].y > 800)
        #expect(result[1].y > 800)
        // Same row
        #expect(result[0].y == result[1].y)
    }

    @Test("parkIcons topLeft fills right then down")
    func parkIconsTopLeft() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let icons = [
            IconPosition(name: "a.txt", x: 0, y: 0),
            IconPosition(name: "b.txt", x: 0, y: 0),
        ]
        let result = CoordinateConverter.parkIcons(
            icons, in: .topLeft, on: display, iconSize: 60, avoiding: []
        )
        // First icon should be leftmost, second to its right
        #expect(result[0].x < result[1].x)
        // Both near the top
        #expect(result[0].y < 200)
        #expect(result[1].y < 200)
        // Same row
        #expect(result[0].y == result[1].y)
    }

    @Test("parkIcons topRight fills left then down")
    func parkIconsTopRight() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let icons = [
            IconPosition(name: "a.txt", x: 0, y: 0),
            IconPosition(name: "b.txt", x: 0, y: 0),
        ]
        let result = CoordinateConverter.parkIcons(
            icons, in: .topRight, on: display, iconSize: 60, avoiding: []
        )
        // First icon rightmost, second to its left
        #expect(result[0].x > result[1].x)
        // Both near the top
        #expect(result[0].y < 200)
        #expect(result[1].y < 200)
    }

    @Test("parkIcons bottomLeft fills right then up")
    func parkIconsBottomLeft() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let icons = [
            IconPosition(name: "a.txt", x: 0, y: 0),
            IconPosition(name: "b.txt", x: 0, y: 0),
        ]
        let result = CoordinateConverter.parkIcons(
            icons, in: .bottomLeft, on: display, iconSize: 60, avoiding: []
        )
        // First icon leftmost, second to its right
        #expect(result[0].x < result[1].x)
        // Both near the bottom
        #expect(result[0].y > 800)
        #expect(result[1].y > 800)
    }

    // MARK: - parkIcons: slot avoidance

    @Test("parkIcons skips grid slots occupied by profile icons")
    func parkIconsSlotAvoidance() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        // Place a profile icon exactly at the first bottom-right grid slot
        // With iconSize=60, gridSpacing=100, first slot bottomRight:
        // x = 1920 - 20 - 100 + 50 = 1850, y = 1080 - 20 - 100 + 50 = 1010
        let occupier = IconPosition(name: "profile.txt", x: 1850, y: 1010)
        let icons = [IconPosition(name: "new.txt", x: 0, y: 0)]

        let result = CoordinateConverter.parkIcons(
            icons, in: .bottomRight, on: display, iconSize: 60, avoiding: [occupier]
        )
        // The parked icon should NOT be at the occupied slot's position
        #expect(result[0].x != 1850 || result[0].y != 1010)
        // It should still be near the bottom-right area
        #expect(result[0].y > 800)
    }

    // MARK: - parkIcons: dynamic spacing from icon size

    @Test("parkIcons spacing increases with larger icon size")
    func parkIconsDynamicSpacing() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let icons = [
            IconPosition(name: "a.txt", x: 0, y: 0),
            IconPosition(name: "b.txt", x: 0, y: 0),
        ]
        let smallResult = CoordinateConverter.parkIcons(
            icons, in: .bottomRight, on: display, iconSize: 40, avoiding: []
        )
        let largeResult = CoordinateConverter.parkIcons(
            icons, in: .bottomRight, on: display, iconSize: 120, avoiding: []
        )
        // Larger icon size → larger spacing between icons
        let smallGap = abs(smallResult[0].x - smallResult[1].x)
        let largeGap = abs(largeResult[0].x - largeResult[1].x)
        #expect(largeGap > smallGap)
    }

    // MARK: - parkIcons: empty input

    @Test("parkIcons with empty input returns empty")
    func parkIconsEmpty() {
        let display = DisplayFrame(x: 0, y: 0, width: 1920, height: 1080)
        let result = CoordinateConverter.parkIcons(
            [], in: .bottomRight, on: display, iconSize: 60, avoiding: []
        )
        #expect(result.isEmpty)
    }

    // MARK: - remap: parking zone parameter

    @Test("remap uses specified parking zone for displaced icons")
    func remapWithParkingZone() {
        let saved = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
            DisplayFrame(x: 1792, y: 0, width: 1920, height: 1080),
        ]
        let current = [
            DisplayFrame(x: 0, y: 0, width: 1792, height: 1120),
        ]
        let icons = [IconPosition(name: "file.txt", x: 1900, y: 50)]

        let bottomRight = CoordinateConverter.remap(
            icons: icons, from: saved, to: current, parkingZone: .bottomRight, iconSize: 60
        )
        let topLeft = CoordinateConverter.remap(
            icons: icons, from: saved, to: current, parkingZone: .topLeft, iconSize: 60
        )

        // bottomRight parks near bottom, topLeft parks near top
        #expect(bottomRight[0].y > 800)
        #expect(topLeft[0].y < 200)
    }
}
