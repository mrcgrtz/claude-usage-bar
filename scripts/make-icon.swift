// Draws the app icon and writes AppIcon.icns. Run with: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func point(_ center: NSPoint, _ radius: CGFloat, _ degrees: CGFloat) -> NSPoint {
    let radians = degrees * .pi / 180
    return NSPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
}

func drawIcon() {
    // The macOS icon grid puts an 824 pt rounded square in the middle of the 1024 pt canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 20
    shadow.set()
    color(0xC8643F).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0xE38A63), ending: color(0xB5532F))!.draw(in: shape, angle: -90)

    // The gauge runs clockwise from 210° to -30°, and the needle shows 67%.
    let center = NSPoint(x: 512, y: 470)
    let radius: CGFloat = 270
    let start: CGFloat = 210
    let end: CGFloat = -30
    let value = start + (end - start) * 0.67

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    track.lineWidth = 70
    track.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.3).setStroke()
    track.stroke()

    let fill = NSBezierPath()
    fill.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: value, clockwise: true)
    fill.lineWidth = 70
    fill.lineCapStyle = .round
    NSColor.white.setStroke()
    fill.stroke()

    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: point(center, radius - 90, value))
    needle.lineWidth = 44
    needle.lineCapStyle = .round
    needle.stroke()

    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 52, y: center.y - 52, width: 104, height: 104)).fill()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote AppIcon.icns" : "iconutil failed")
