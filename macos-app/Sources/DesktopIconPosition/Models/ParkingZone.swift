import Foundation

/// Screen corner where displaced and unmapped icons are parked during restore.
enum ParkingZone: String, CaseIterable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }
}
