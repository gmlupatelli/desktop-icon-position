#!/usr/bin/env swift
// generate-icns.swift — Convert AppIcon.svg to AppIcon.icns
// Uses only built-in AppKit (no third-party dependencies)
// Usage: swift scripts/generate-icns.swift

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // scripts/
    .deletingLastPathComponent()   // repo root

let svgPath = repoRoot
    .appendingPathComponent("macos-app/Resources/AppIcon.svg")
let outputDir = repoRoot
    .appendingPathComponent("macos-app/Resources")
let icnsPath = outputDir.appendingPathComponent("AppIcon.icns")

// Icon sizes required for macOS .iconset (point sizes with 1x and 2x)
let iconSizes: [(name: String, pixels: Int)] = [
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

// Load SVG
guard let svgData = try? Data(contentsOf: svgPath) else {
    fputs("Error: Cannot read \(svgPath.path)\n", stderr)
    exit(1)
}
guard let svgImage = NSImage(data: svgData) else {
    fputs("Error: Cannot parse SVG as NSImage\n", stderr)
    exit(1)
}

// Create temporary .iconset directory
let iconsetPath = outputDir.appendingPathComponent("AppIcon.iconset")
let fm = FileManager.default
try? fm.removeItem(at: iconsetPath)
try fm.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

// Render each size as PNG
for entry in iconSizes {
    let size = NSSize(width: entry.pixels, height: entry.pixels)
    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: entry.pixels,
        pixelsHigh: entry.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmapRep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
    svgImage.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: svgImage.size),
                  operation: .copy,
                  fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        fputs("Error: Failed to create PNG for \(entry.name)\n", stderr)
        exit(1)
    }

    let pngPath = iconsetPath.appendingPathComponent("\(entry.name).png")
    try pngData.write(to: pngPath)
}

// Convert .iconset to .icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", icnsPath.path, iconsetPath.path]

let pipe = Pipe()
process.standardError = pipe
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
    fputs("Error: iconutil failed: \(errorMsg)\n", stderr)
    exit(1)
}

// Clean up .iconset directory
try? fm.removeItem(at: iconsetPath)

print("Generated \(icnsPath.path)")
