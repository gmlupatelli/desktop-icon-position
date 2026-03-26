import Foundation

/// A display rectangle in Quartz/CG coordinates (top-left origin, Y increases downward).
struct DisplayFrame: Codable, Hashable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    /// Whether the given point falls within this display's bounds.
    func contains(px: Int, py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    /// Center point of this display frame.
    var center: (x: Int, y: Int) {
        (x + width / 2, y + height / 2)
    }

    /// Overlap area with another display frame. Returns 0 if no overlap.
    func overlapArea(with other: DisplayFrame) -> Int {
        let overlapX = max(0, min(x + width, other.x + other.width) - max(x, other.x))
        let overlapY = max(0, min(y + height, other.y + other.height) - max(y, other.y))
        return overlapX * overlapY
    }

    /// Pipe-delimited representation matching the shell script format.
    var pipeString: String {
        "\(x)|\(y)|\(width)|\(height)"
    }
}
