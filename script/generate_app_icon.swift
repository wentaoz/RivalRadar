import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("RivalRadar.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let image = drawIcon(size: size)
    let url = iconset.appendingPathComponent(name)
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render icon")
    }
    try png.write(to: url)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("RivalRadar.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed")
}

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let scale = CGFloat(size) / 1024

    let background = NSBezierPath(roundedRect: rect.insetBy(dx: 48 * scale, dy: 48 * scale), xRadius: 210 * scale, yRadius: 210 * scale)
    NSGradient(colors: [
        NSColor(red: 0.04, green: 0.24, blue: 0.28, alpha: 1),
        NSColor(red: 0.02, green: 0.10, blue: 0.18, alpha: 1)
    ])?.draw(in: background, angle: 135)

    let center = NSPoint(x: 512 * scale, y: 560 * scale)
    for (index, radius) in [300, 220, 140].enumerated() {
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - CGFloat(radius) * scale,
            y: center.y - CGFloat(radius) * scale,
            width: CGFloat(radius * 2) * scale,
            height: CGFloat(radius * 2) * scale
        ))
        ring.lineWidth = CGFloat(18 - index * 3) * scale
        NSColor(red: 0.33, green: 0.92, blue: 0.84, alpha: 0.58 - CGFloat(index) * 0.1).setStroke()
        ring.stroke()
    }

    let sweep = NSBezierPath()
    sweep.move(to: center)
    sweep.appendArc(
        withCenter: center,
        radius: 315 * scale,
        startAngle: 18,
        endAngle: 73,
        clockwise: false
    )
    sweep.close()
    NSColor(red: 0.30, green: 0.95, blue: 0.82, alpha: 0.20).setFill()
    sweep.fill()

    let beam = NSBezierPath()
    beam.move(to: center)
    beam.line(to: NSPoint(x: 828 * scale, y: 676 * scale))
    beam.lineWidth = 22 * scale
    beam.lineCapStyle = .round
    NSColor(red: 0.31, green: 0.95, blue: 0.82, alpha: 0.92).setStroke()
    beam.stroke()

    let dot = NSBezierPath(ovalIn: NSRect(x: 792 * scale, y: 640 * scale, width: 72 * scale, height: 72 * scale))
    NSColor(red: 1.00, green: 0.72, blue: 0.25, alpha: 1).setFill()
    dot.fill()

    let card = NSBezierPath(roundedRect: NSRect(x: 240 * scale, y: 190 * scale, width: 500 * scale, height: 250 * scale), xRadius: 42 * scale, yRadius: 42 * scale)
    NSColor(red: 0.94, green: 0.98, blue: 0.98, alpha: 0.96).setFill()
    card.fill()

    for index in 0..<3 {
        let line = NSBezierPath(roundedRect: NSRect(
            x: 310 * scale,
            y: CGFloat(360 - index * 62) * scale,
            width: CGFloat(index == 2 ? 260 : 330) * scale,
            height: 24 * scale
        ), xRadius: 12 * scale, yRadius: 12 * scale)
        NSColor(red: 0.05, green: 0.24, blue: 0.30, alpha: index == 0 ? 0.88 : 0.55).setFill()
        line.fill()
    }

    let badge = NSBezierPath(roundedRect: NSRect(x: 625 * scale, y: 305 * scale, width: 78 * scale, height: 78 * scale), xRadius: 22 * scale, yRadius: 22 * scale)
    NSColor(red: 1.00, green: 0.55, blue: 0.22, alpha: 1).setFill()
    badge.fill()

    image.unlockFocus()
    return image
}
