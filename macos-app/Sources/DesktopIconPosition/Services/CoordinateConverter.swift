import Foundation

/// Converts icon positions between different display configurations.
/// Port of the shell script's `remap_coordinates()` and `find_display_for_point()`.
enum CoordinateConverter {

    /// Finds which display contains the given point.
    /// Falls back to the first display if no display contains the point.
    static func findDisplay(forPoint px: Int, _ py: Int, in displays: [DisplayFrame]) -> DisplayFrame {
        for display in displays where display.contains(px: px, py: py) {
            return display
        }
        return displays[0]
    }

    /// Remap icon positions from saved display layout to current display layout.
    ///
    /// Algorithm (matches shell script):
    /// 1. For each icon, find which saved display it was on
    /// 2. Calculate relative position within that display
    /// 3. Map relative position onto the current primary display
    /// 4. Clamp with 20px padding to keep icons on-screen
    static func remap(
        icons: [IconPosition],
        from savedDisplays: [DisplayFrame],
        to currentDisplays: [DisplayFrame]
    ) -> [IconPosition] {
        guard let primary = currentDisplays.first, !savedDisplays.isEmpty else {
            return icons
        }
        let pad = 20

        return icons.map { icon in
            let orig = findDisplay(forPoint: icon.x, icon.y, in: savedDisplays)

            let relX = icon.x - orig.x
            let relY = icon.y - orig.y

            var newX = primary.x + relX
            var newY = primary.y + relY

            newX = max(primary.x + pad, min(newX, primary.x + primary.width - pad))
            newY = max(primary.y + pad, min(newY, primary.y + primary.height - pad))

            return IconPosition(name: icon.name, x: newX, y: newY)
        }
    }
}
