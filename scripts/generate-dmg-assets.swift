#!/usr/bin/env swift
// generate-dmg-assets.swift — Generate polished DMG background images and volume icon
// Uses only built-in AppKit (no third-party dependencies)
// Usage: swift scripts/generate-dmg-assets.swift
//
// Outputs:
//   build/dmg-background.png      (660×400 @1x)
//   build/dmg-background@2x.png   (1320×800 @2x)
//   build/VolumeIcon.icns         (app icon on disk shape)

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // scripts/
    .deletingLastPathComponent()   // repo root

let buildDir = repoRoot.appendingPathComponent("build")
let icnsPath = repoRoot.appendingPathComponent("macos-app/Resources/AppIcon.icns")

let fm = FileManager.default
try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)

// MARK: - DMG Background Generation

/// Renders the DMG background — white with a dark chevron ">"
func renderBackground(width: Int, height: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let w = CGFloat(width)
    let h = CGFloat(height)

    // White background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Dark chevron ">" centered between icon positions
    let scale = w / 660.0
    let chevronX = w * 0.5
    let chevronY = h * 0.58
    let chevronSize = 22.0 * scale
    let lineWidth = 4.5 * scale

    ctx.setStrokeColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 0.7))
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.move(to: CGPoint(x: chevronX - chevronSize * 0.5, y: chevronY + chevronSize))
    ctx.addLine(to: CGPoint(x: chevronX + chevronSize * 0.5, y: chevronY))
    ctx.addLine(to: CGPoint(x: chevronX - chevronSize * 0.5, y: chevronY - chevronSize))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Generate 1x and 2x backgrounds
for (suffix, width, height) in [("", 660, 400), ("@2x", 1320, 800)] {
    let rep = renderBackground(width: width, height: height)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Error: Failed to create background PNG \(suffix)\n", stderr)
        exit(1)
    }
    let path = buildDir.appendingPathComponent("dmg-background\(suffix).png")
    try pngData.write(to: path)
    print("Generated \(path.path)")
}

// MARK: - Volume Icon Generation

/// Creates a volume icon by compositing the app icon onto a rounded disk shape
func generateVolumeIcon() {
    // Load app icon
    guard fm.fileExists(atPath: icnsPath.path),
          let appIcon = NSImage(contentsOf: icnsPath) else {
        print("Skipping VolumeIcon.icns — AppIcon.icns not found")
        return
    }

    let iconsetPath = buildDir.appendingPathComponent("VolumeIcon.iconset")
    try? fm.removeItem(at: iconsetPath)
    try! fm.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

    let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16",        16),
        ("icon_16x16@2x",     32),
        ("icon_32x32",        32),
        ("icon_32x32@2x",     64),
        ("icon_128x128",     128),
        ("icon_128x128@2x",  256),
        ("icon_256x256",     256),
        ("icon_256x256@2x",  512),
        ("icon_512x512",     512),
        ("icon_512x512@2x", 1024),
    ]

    for entry in sizes {
        let px = entry.pixels
        let size = NSSize(width: px, height: px)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        let s = CGFloat(px)

        // Disk shape background (rounded rectangle)
        let inset = s * 0.05
        let diskRect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let cornerRadius = s * 0.18
        let diskPath = CGPath(roundedRect: diskRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Gradient fill for disk shape
        ctx.saveGState()
        ctx.addPath(diskPath)
        ctx.clip()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let diskGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0),
                CGColor(red: 0.82, green: 0.83, blue: 0.87, alpha: 1.0)
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(diskGradient,
            start: CGPoint(x: s/2, y: s),
            end: CGPoint(x: s/2, y: 0),
            options: [])
        ctx.restoreGState()

        // Disk border
        ctx.setStrokeColor(CGColor(red: 0.7, green: 0.71, blue: 0.75, alpha: 1.0))
        ctx.setLineWidth(max(1.0, s * 0.01))
        ctx.addPath(diskPath)
        ctx.strokePath()

        // Draw app icon centered, scaled to 65% of the disk
        let iconSize = s * 0.65
        let iconRect = NSRect(
            x: (s - iconSize) / 2,
            y: (s - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        appIcon.draw(in: iconRect,
                     from: NSRect(origin: .zero, size: appIcon.size),
                     operation: .sourceOver,
                     fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            fputs("Error: Failed to create volume icon PNG for \(entry.name)\n", stderr)
            exit(1)
        }
        let pngPath = iconsetPath.appendingPathComponent("\(entry.name).png")
        try! pngData.write(to: pngPath)
    }

    // Convert to .icns
    let volumeIcnsPath = buildDir.appendingPathComponent("VolumeIcon.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["--convert", "icns", "--output", volumeIcnsPath.path, iconsetPath.path]
    let pipe = Pipe()
    process.standardError = pipe
    try! process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        fputs("Error: iconutil failed for VolumeIcon: \(errorMsg)\n", stderr)
        exit(1)
    }

    try? fm.removeItem(at: iconsetPath)
    print("Generated \(volumeIcnsPath.path)")
}

generateVolumeIcon()
