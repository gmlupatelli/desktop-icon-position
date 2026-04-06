import SwiftUI
import AppKit
import Darwin

/// Generates template images for the menu bar icon
enum MenuBarIcon {
    /// The template image for the menu bar
    static let image: NSImage = createTemplateImage()

    private static func createTemplateImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            let s = rect.size.width // 18
            let cx = s / 2
            let cy = s / 2

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)

            // Crosshair arms
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)

            // Top arm
            ctx.move(to: CGPoint(x: cx, y: 1))
            ctx.addLine(to: CGPoint(x: cx, y: cy - 2.5))
            ctx.strokePath()
            // Bottom arm
            ctx.move(to: CGPoint(x: cx, y: cy + 2.5))
            ctx.addLine(to: CGPoint(x: cx, y: s - 1))
            ctx.strokePath()
            // Left arm
            ctx.move(to: CGPoint(x: 1, y: cy))
            ctx.addLine(to: CGPoint(x: cx - 2.5, y: cy))
            ctx.strokePath()
            // Right arm
            ctx.move(to: CGPoint(x: cx + 2.5, y: cy))
            ctx.addLine(to: CGPoint(x: s - 1, y: cy))
            ctx.strokePath()

            // Center dot
            ctx.fillEllipse(in: CGRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3))

            // 4 small rounded rectangles in quadrants (representing desktop icons)
            let rectSize: CGFloat = 3.0
            let cornerR: CGFloat = 0.6
            let offset: CGFloat = 4.5
            for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                let rx = cx + dx * offset - rectSize / 2
                let ry = cy + dy * offset - rectSize / 2
                let path = CGPath(roundedRect: CGRect(x: rx, y: ry, width: rectSize, height: rectSize),
                                  cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
            }

            return true
        }
        image.isTemplate = true
        return image
    }
}

@main
struct DesktopIconPositionApp: App {
    @State private var viewModel = AppViewModel()
    private let smokeTestEnabled = FinderSmokeTestRunner.isEnabled()
    private let benchmarkEnabled = TimingBenchmarkRunner.isEnabled()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }

    init() {
        // Prevent multiple instances from running simultaneously
        let bundleID = Bundle.main.bundleIdentifier ?? "com.desktop-icon-position"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            running.first(where: { $0 != .current })?.activate()
            exit(0)
        }

        // Register defaults before any UserDefaults reads
        UserDefaults.standard.register(defaults: [
            "autoRestoreEnabled": true,
            "autoRestoreOnLaunch": true,
        ])

        if smokeTestEnabled {
            DispatchQueue.main.async {
                Task { @MainActor in
                    let exitCode = await FinderSmokeTestRunner.run()
                    fflush(stdout)
                    fflush(stderr)
                    exit(exitCode)
                }
            }
        } else if benchmarkEnabled {
            DispatchQueue.main.async {
                Task { @MainActor in
                    let exitCode = await TimingBenchmarkRunner.run()
                    fflush(stdout)
                    fflush(stderr)
                    exit(exitCode)
                }
            }
        } else {
            // Delay start until app is ready
            DispatchQueue.main.async { [self] in
                viewModel.start()
            }
        }
    }
}
