import Foundation

/// A single desktop icon's name and position in Quartz coordinates.
struct IconPosition: Codable, Hashable {
    let name: String
    let x: Int
    let y: Int
}
