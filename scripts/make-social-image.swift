// Draws the social preview image for GitHub and writes docs/social.png.
// Run with: swift scripts/make-social-image.swift
// Upload it in the settings of the repository, under Social preview.
import AppKit

// GitHub shows the image at 1280 × 640 px and may crop the edges, so the content keeps a margin of 80 px.
let canvas = NSSize(width: 1280, height: 640)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawText(_ text: String, _ font: NSFont, _ textColor: NSColor, x: CGFloat, y: CGFloat) {
    NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: textColor]).draw(at: NSPoint(x: x, y: y))
}

// The same warm paper as the DMG window, so that the project looks the same everywhere.
func drawBackground() {
    let bounds = NSRect(origin: .zero, size: canvas)
    NSGradient(starting: color(0xFBF5EC), ending: color(0xF3E4D2))!.draw(in: bounds, angle: -90)
    for (center, hex) in [(NSPoint(x: 80, y: 600), 0xF2C14E), (NSPoint(x: 1220, y: 40), 0xE38A63)] as [(NSPoint, UInt32)] {
        let glow = NSGradient(starting: color(hex, 0.25), ending: color(hex, 0))!
        glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 460, options: [])
    }
}

func drawTitle() {
    if let icon = NSImage(contentsOfFile: "AppIcon.icns") {
        icon.draw(in: NSRect(x: 72, y: 372, width: 176, height: 176))
    }
    drawText("ClaudeUsageBar", roundedFont(64, .heavy), color(0x6B3A22), x: 80, y: 270)
    drawText("Your Claude plan limits,", roundedFont(32, .semibold), color(0x8A5A40), x: 82, y: 212)
    drawText("right in the macOS menu bar.", roundedFont(32, .semibold), color(0x8A5A40), x: 82, y: 172)
    drawText(
        "5-hour and weekly usage · Rules · English and German",
        roundedFont(20, .medium), color(0xA07A63), x: 82, y: 96
    )
}

// The menu screenshot, with rounded corners and a soft shadow like a window.
func drawScreenshot() {
    guard let screenshot = NSImage(contentsOfFile: "docs/screenshot.png") else { return }
    let frame = NSRect(x: 660, y: 124, width: 560, height: 396)
    let clip = NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x6B3A22, 0.35)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0xFFFFFF).setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    screenshot.draw(in: frame)
    NSGraphicsContext.restoreGraphicsState()
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = canvas
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
drawBackground()
drawTitle()
drawScreenshot()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social.png"))
print("Wrote docs/social.png")
