// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopIconPosition",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DesktopIconPosition",
            path: "Sources/DesktopIconPosition"
        ),
        .testTarget(
            name: "DesktopIconPositionTests",
            dependencies: ["DesktopIconPosition"],
            path: "Tests/DesktopIconPositionTests"
        ),
    ]
)
