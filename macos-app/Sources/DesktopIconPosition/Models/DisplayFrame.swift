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

    /// Pipe-delimited representation matching the shell script format.
    var pipeString: String {
        "\(x)|\(y)|\(width)|\(height)"
    }
}
