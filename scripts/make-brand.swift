// swift scripts/make-brand.swift: the brand assets, generated from the design tokens and the creature grid
// (read from Packages/BrainmergeUI/Sources/BrainmergeUI/Design/CreatureView.swift: a single source of truth).
// Produces: App/Assets.xcassets/AppIcon.appiconset (app icon), docs/brand/icon-1024.png, github-avatar-512.png,
// banner-1280x640.png (GitHub social preview), readme-header.png, logo.svg, logo-mark.svg.
import AppKit

// MARK: Tokens (docs/brand/DESIGN.md)
func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0; Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}
let background = color("#1A1918"), backgroundTop = color("#2B2633"), cream = color("#F4EFE6"), accent = color("#A06BE0"), eye = color("#1E1430")

// MARK: The creature, read from CreatureView.swift
let source = try String(contentsOfFile: "Packages/BrainmergeUI/Sources/BrainmergeUI/Design/CreatureView.swift", encoding: .utf8)
let body: [String] = source.split(separator: "\n").compactMap { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("\"") else { return nil }
    let content = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\",")).replacingOccurrences(of: "\",", with: "")
    return content.count == 16 && content.allSatisfy({ $0 == "X" || $0 == "." }) ? content : nil
}
precondition(body.count == 11, "creature grid not found in CreatureView.swift (\(body.count) lines)")
let eyes = [(4, 1), (11, 1)]

func drawCreature(in rect: NSRect) {
    let unit = rect.width / 16
    let path = NSBezierPath()
    for (y, row) in body.enumerated() { for (x, ch) in row.enumerated() where ch == "X" {
        path.appendRect(NSRect(x: rect.minX + CGFloat(x) * unit, y: rect.maxY - CGFloat(y + 1) * unit, width: unit, height: unit)) } }
    accent.setFill(); path.fill()
    for (x, y) in eyes { eye.setFill(); NSRect(x: rect.minX + CGFloat(x) * unit, y: rect.maxY - CGFloat(y + 1) * unit, width: unit, height: unit).fill() }
}

func bitmap(_ w: Int, _ h: Int, draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
func save(_ rep: NSBitmapImageRep, _ path: String) throws {
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
func serif(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size) ?? base
}
func text(_ s: String, font: NSFont, color: NSColor, at point: NSPoint) {
    (s as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
}
func textWidth(_ s: String, font: NSFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }

/// The icon's rounded square: dark background, purple halo, creature. `inset` = macOS margin (10%) or 0 for a full-bleed avatar.
func drawIconSquare(_ r: NSRect, inset: CGFloat) {
    let square = r.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: square, xRadius: square.width * 0.225, yRadius: square.width * 0.225)
    background.setFill(); path.fill()
    NSGraphicsContext.current?.saveGraphicsState(); path.addClip()
    NSGradient(colors: [accent.withAlphaComponent(0.32), .clear])!.draw(fromCenter: NSPoint(x: square.midX, y: square.midY + square.height * 0.05), radius: 0,
                                                                        toCenter: NSPoint(x: square.midX, y: square.midY + square.height * 0.05), radius: square.width * 0.6, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()
    let w = square.width * 0.62, h = w * 11 / 16
    drawCreature(in: NSRect(x: square.midX - w / 2, y: square.midY - h / 2, width: w, height: h))
}

// MARK: App icon (full set) and avatar
let sizes: [(String, Int, Int)] = [("16x16", 16, 1), ("16x16", 16, 2), ("32x32", 32, 1), ("32x32", 32, 2), ("128x128", 128, 1), ("128x128", 128, 2), ("256x256", 256, 1), ("256x256", 256, 2), ("512x512", 512, 1), ("512x512", 512, 2)]
let iconDir = "App/Assets.xcassets/AppIcon.appiconset"
var images: [[String: String]] = []
for (name, pts, scale) in sizes {
    let px = pts * scale
    let rep = bitmap(px, px) { r in drawIconSquare(r, inset: r.width * 0.1) }
    let file = "icon_\(name)\(scale == 2 ? "@2x" : "").png"
    try save(rep, "\(iconDir)/\(file)")
    images.append(["size": name, "idiom": "mac", "filename": file, "scale": "\(scale)x"])
}
try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(iconDir)/Contents.json"))
try save(bitmap(1024, 1024) { r in drawIconSquare(r, inset: r.width * 0.1) }, "docs/brand/icon-1024.png")
try save(bitmap(512, 512) { r in drawIconSquare(r, inset: 0) }, "docs/brand/github-avatar-512.png")

// MARK: Banner (GitHub social preview, 1280 x 640) and README header (1600 x 480)
func drawBanner(_ r: NSRect, creatureSize: CGFloat, title: CGFloat, tagline: CGFloat) {
    background.setFill(); r.fill()
    NSGradient(colors: [backgroundTop, background])!.draw(in: r, angle: -60)
    NSGradient(colors: [accent.withAlphaComponent(0.22), .clear])!.draw(fromCenter: NSPoint(x: r.width * 0.22, y: r.midY), radius: 0, toCenter: NSPoint(x: r.width * 0.22, y: r.midY), radius: r.height * 0.7, options: [])
    let cw = creatureSize, ch = cw * 11 / 16
    drawCreature(in: NSRect(x: r.width * 0.22 - cw / 2, y: r.midY - ch / 2 + r.height * 0.02, width: cw, height: ch))
    let x = r.width * 0.42
    let titleFont = serif(title)
    text("Brainmerge", font: titleFont, color: cream, at: NSPoint(x: x, y: r.midY + r.height * 0.02))
    text("Every Claude account you own,", font: NSFont.systemFont(ofSize: tagline), color: cream.withAlphaComponent(0.72), at: NSPoint(x: x + 4, y: r.midY - tagline * 1.5))
    text("one shared brain.", font: NSFont.systemFont(ofSize: tagline), color: cream.withAlphaComponent(0.72), at: NSPoint(x: x + 4, y: r.midY - tagline * 2.8))
    let small = NSFont.systemFont(ofSize: tagline * 0.55)
    let note = "Free and open source · macOS · Works with Claude. Not made by Anthropic."
    text(note, font: small, color: cream.withAlphaComponent(0.4), at: NSPoint(x: r.width - textWidth(note, font: small) - r.height * 0.06, y: r.height * 0.06))
}
try save(bitmap(1280, 640) { r in drawBanner(r, creatureSize: 300, title: 92, tagline: 30) }, "docs/brand/banner-1280x640.png")
try save(bitmap(1600, 480) { r in drawBanner(r, creatureSize: 240, title: 84, tagline: 27) }, "docs/brand/readme-header.png")

// MARK: SVG logos (the creature in rectangles, the wordmark in serif)
func svgCreature(unit: Int, x0: Int, y0: Int) -> String {
    var s = ""
    for (y, row) in body.enumerated() { for (x, ch) in row.enumerated() where ch == "X" {
        s += "<rect x=\"\(x0 + x * unit)\" y=\"\(y0 + y * unit)\" width=\"\(unit)\" height=\"\(unit)\" fill=\"#A06BE0\"/>" } }
    for (x, y) in eyes { s += "<rect x=\"\(x0 + x * unit)\" y=\"\(y0 + y * unit)\" width=\"\(unit)\" height=\"\(unit)\" fill=\"#1E1430\"/>" }
    return s
}
let mark = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 160 110\" width=\"160\" height=\"110\">\(svgCreature(unit: 10, x0: 0, y0: 0))</svg>\n"
try mark.write(toFile: "docs/brand/logo-mark.svg", atomically: true, encoding: .utf8)
let logo = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 560 120\" width=\"560\" height=\"120\"><rect width=\"560\" height=\"120\" rx=\"24\" fill=\"#1A1918\"/>\(svgCreature(unit: 6, x0: 32, y0: 27))<text x=\"156\" y=\"78\" font-family=\"New York, Georgia, serif\" font-size=\"58\" font-weight=\"500\" fill=\"#F4EFE6\">Brainmerge</text></svg>\n"
try logo.write(toFile: "docs/brand/logo.svg", atomically: true, encoding: .utf8)
print("brand: icon (\(images.count) images), icon-1024, avatar 512, banner 1280x640, README header, logo.svg, logo-mark.svg")
