// Renders the app icon into Support/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// Follows the macOS icon grid: an 824 pt rounded square centred on a 1024 pt canvas.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("No bitmap context") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)

    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Drop shadow, as on system icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Deep evening blue at the bottom rising into warm light: "more light" at a glance.
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.11, green: 0.13, blue: 0.32, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.38, blue: 0.18, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.35, alpha: 1),
    ], atLocations: [0, 0.62, 1], colorSpace: .sRGB)
    gradient?.draw(in: shape, angle: 90)

    // Soft glow behind the sun.
    let glowCenter = NSPoint(x: 512, y: 540)
    let glow = NSGradient(colors: [
        NSColor(srgbRed: 1, green: 0.97, blue: 0.85, alpha: 0.75),
        NSColor(srgbRed: 1, green: 0.9, blue: 0.6, alpha: 0),
    ])
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    glow?.draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 360, options: [])
    NSGraphicsContext.restoreGraphicsState()

    let configuration = NSImage.SymbolConfiguration(pointSize: 430, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let sun = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let rect = NSRect(
            x: glowCenter.x - sun.size.width / 2, y: glowCenter.y - sun.size.height / 2,
            width: sun.size.width, height: sun.size.height
        )
        sun.draw(in: rect)
    }

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    return png
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let output = root.appendingPathComponent("Support/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try render(size: 1024).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-preview.png"))
print("Wrote \(output.path)")
