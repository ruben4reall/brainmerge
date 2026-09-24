// swift scripts/make-dmg-background.swift: the installer window background (660 x 400 points, rendered at 2x).
// The app icon sits on the left, the Applications folder on the right; an arrow and a sentence in between.
import AppKit

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}
let w = 660, h = 400, scale = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * scale, pixelsHigh: h * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let r = NSRect(x: 0, y: 0, width: w, height: h)
color("#1A1918").setFill(); r.fill()
NSGradient(colors: [color("#2B2633"), color("#1A1918")])!.draw(in: r, angle: -70)
NSGradient(colors: [color("#A06BE0", alpha: 0.18), .clear])!.draw(fromCenter: NSPoint(x: 165, y: 185), radius: 0, toCenter: NSPoint(x: 165, y: 185), radius: 190, options: [])
// The wordmark in serif, at the top.
let base = NSFont.systemFont(ofSize: 26, weight: .medium)
let serif = NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: 26) ?? base
("Brainmerge" as NSString).draw(at: NSPoint(x: 40, y: h - 62), withAttributes: [.font: serif, .foregroundColor: color("#F4EFE6")])
// The arrow between the icon (x = 165) and Applications (x = 495): the Finder places icons 215 pt from the top, so y = 185 here.
let arrow = NSBezierPath(); arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: 185)); arrow.line(to: NSPoint(x: 392, y: 185))
arrow.move(to: NSPoint(x: 372, y: 203)); arrow.line(to: NSPoint(x: 392, y: 185)); arrow.line(to: NSPoint(x: 372, y: 167))
color("#F4EFE6", alpha: 0.55).setStroke(); arrow.stroke()
// The sentence, below the icons.
let sentence = "Drag Brainmerge to your Applications folder, then open it from there."
let font = NSFont.systemFont(ofSize: 13)
let width = (sentence as NSString).size(withAttributes: [.font: font]).width
(sentence as NSString).draw(at: NSPoint(x: (CGFloat(w) - width) / 2, y: 78), withAttributes: [.font: font, .foregroundColor: color("#F4EFE6", alpha: 0.6)])
let note = "Works with Claude. Not made by Anthropic."
let small = NSFont.systemFont(ofSize: 10.5)
let nw = (note as NSString).size(withAttributes: [.font: small]).width
(note as NSString).draw(at: NSPoint(x: (CGFloat(w) - nw) / 2, y: 26), withAttributes: [.font: small, .foregroundColor: color("#F4EFE6", alpha: 0.35)])
NSGraphicsContext.restoreGraphicsState()
try FileManager.default.createDirectory(atPath: "docs/brand", withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/brand/dmg-background.png"))
print("DMG background: docs/brand/dmg-background.png")
