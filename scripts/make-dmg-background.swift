// Draws the DMG window background and writes DMGBackground.tiff.
// Run with: swift scripts/make-dmg-background.swift
import AppKit

// The window is 640 × 400 pt. build.sh puts the icons on the same coordinates.
let canvas = NSSize(width: 640, height: 400)
let appCenter = NSPoint(x: 160, y: 185)
let applicationsCenter = NSPoint(x: 480, y: 185)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let confettiColors: [UInt32] = [0xE38A63, 0xB5532F, 0xF2C14E, 0x7FB7A4, 0x8E7CC3]

// A fixed seed gives the same confetti at each run.
struct Random {
    var state: UInt64 = 0x00C1_A0DE

    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1)
    }
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawText(_ text: String, _ font: NSFont, _ textColor: NSColor, centerX: CGFloat, y: CGFloat) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor])
    string.draw(at: NSPoint(x: centerX - string.size().width / 2, y: y))
}

func sparkle(_ center: NSPoint, _ radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let tips = [
        NSPoint(x: center.x, y: center.y + radius), NSPoint(x: center.x + radius, y: center.y),
        NSPoint(x: center.x, y: center.y - radius), NSPoint(x: center.x - radius, y: center.y),
    ]
    path.move(to: tips[0])
    for index in 1...4 {
        path.curve(to: tips[index % 4], controlPoint1: center, controlPoint2: center)
    }
    return path
}

// Keeps confetti away from the icons, their labels, the text and the arrow.
func isFree(_ spot: NSPoint) -> Bool {
    let busy = [
        NSRect(x: appCenter.x - 85, y: appCenter.y - 95, width: 170, height: 160),
        NSRect(x: applicationsCenter.x - 85, y: applicationsCenter.y - 95, width: 170, height: 160),
        NSRect(x: 220, y: 175, width: 200, height: 110),
        NSRect(x: 130, y: 300, width: 380, height: 80),
        NSRect(x: 60, y: 26, width: 520, height: 40),
    ]
    return !busy.contains { $0.contains(spot) }
}

func drawConfetti() {
    var random = Random()
    var drawn = 0
    while drawn < 46 {
        let spot = NSPoint(x: 14 + random.next() * (canvas.width - 28), y: 14 + random.next() * (canvas.height - 28))
        let hex = confettiColors[Int(random.next() * CGFloat(confettiColors.count)) % confettiColors.count]
        let size = 3 + random.next() * 5
        let kind = random.next()
        guard isFree(spot) else { continue }
        drawn += 1

        color(hex, 0.75).set()
        if kind < 0.35 {
            sparkle(spot, size * 1.4).fill()
        } else if kind < 0.7 {
            NSBezierPath(ovalIn: NSRect(x: spot.x - size / 2, y: spot.y - size / 2, width: size, height: size)).fill()
        } else {
            // A small squiggle, like a paper streamer.
            let squiggle = NSBezierPath()
            let angle = random.next() * .pi
            let step = NSPoint(x: cos(angle) * size, y: sin(angle) * size)
            squiggle.move(to: NSPoint(x: spot.x - step.x, y: spot.y - step.y))
            squiggle.curve(
                to: NSPoint(x: spot.x + step.x, y: spot.y + step.y),
                controlPoint1: NSPoint(x: spot.x - step.y, y: spot.y + step.x),
                controlPoint2: NSPoint(x: spot.x + step.y, y: spot.y - step.x)
            )
            squiggle.lineWidth = 2
            squiggle.lineCapStyle = .round
            squiggle.stroke()
        }
    }
}

func drawArrow() {
    let start = NSPoint(x: appCenter.x + 78, y: appCenter.y + 22)
    let end = NSPoint(x: applicationsCenter.x - 80, y: applicationsCenter.y + 22)
    let control1 = NSPoint(x: start.x + 50, y: start.y + 75)
    let control2 = NSPoint(x: end.x - 50, y: end.y + 75)

    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end, controlPoint1: control1, controlPoint2: control2)
    arc.lineWidth = 4
    arc.lineCapStyle = .round
    arc.setLineDash([0.1, 11], count: 2, phase: 0)
    color(0xE38A63).setStroke()
    arc.stroke()

    // The arrow head follows the direction of the curve at its end.
    let angle = atan2(end.y - control2.y, end.x - control2.x)
    let head = NSBezierPath()
    for side in [-1.0, 1.0] {
        let wing = angle + .pi + side * 0.55
        head.move(to: end)
        head.line(to: NSPoint(x: end.x + cos(wing) * 16, y: end.y + sin(wing) * 16))
    }
    head.lineWidth = 4
    head.lineCapStyle = .round
    head.stroke()

    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 320, yBy: 218)
    transform.rotate(byDegrees: -4)
    transform.concat()
    drawText("wheee!", roundedFont(14, .semibold), color(0xB5532F), centerX: 0, y: 0)
    NSGraphicsContext.restoreGraphicsState()
}

func drawBackground() {
    let bounds = NSRect(origin: .zero, size: canvas)
    NSGradient(starting: color(0xFBF5EC), ending: color(0xF3E4D2))!.draw(in: bounds, angle: -90)

    // Soft glows in two corners make the paper feel warm.
    for (center, hex) in [(NSPoint(x: 40, y: 380), 0xF2C14E), (NSPoint(x: 610, y: 20), 0xE38A63)] as [(NSPoint, UInt32)] {
        let glow = NSGradient(starting: color(hex, 0.22), ending: color(hex, 0))!
        glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 230, options: [])
    }

    drawConfetti()
    drawArrow()

    drawText("Almost there!", roundedFont(30, .heavy), color(0x6B3A22), centerX: canvas.width / 2, y: 336)
    drawText(
        "Drag the gauge into Applications to keep an eye on your Claude limits.",
        roundedFont(14, .medium), color(0x8A5A40), centerX: canvas.width / 2, y: 312
    )
    drawText(
        "First launch: System Settings → Privacy & Security → Open Anyway",
        roundedFont(11, .regular), color(0xA07A63), centerX: canvas.width / 2, y: 38
    )
}

func png(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Finder shows the sharp version on Retina displays when the TIFF has both sizes.
let folder = URL(fileURLWithPath: NSTemporaryDirectory())
let standard = folder.appendingPathComponent("DMGBackground.png")
let retina = folder.appendingPathComponent("DMGBackground@2x.png")
try png(scale: 1).write(to: standard)
try png(scale: 2).write(to: retina)

let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", standard.path, retina.path, "-out", "DMGBackground.tiff"]
try tiffutil.run()
tiffutil.waitUntilExit()
print(tiffutil.terminationStatus == 0 ? "Wrote DMGBackground.tiff" : "tiffutil failed")
