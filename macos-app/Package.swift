// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesktopIconPosition",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.2"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.6"),
    ],
    targets: [
        .executableTarget(
            name: "DesktopIconPosition",
            path: "Sources/DesktopIconPosition",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "DesktopIconPositionTests",
            dependencies: ["DesktopIconPosition"],
            path: "Tests/DesktopIconPositionTests",
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
    ]
)
