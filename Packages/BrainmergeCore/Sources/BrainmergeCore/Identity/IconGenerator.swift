import AppKit
import CoreImage
import Foundation

/// Builds .icns files: Claude's icon shifted toward the identity's tint, or a supplied logo.
public enum IconGenerator {
    static let sizes: [(name: String, px: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    /// Hue shift from Claude's orange (about 20 degrees), in degrees.
    static func hueShiftDegrees(for tint: Tint) -> CGFloat {
        switch tint {
        case .orange: return 0
        case .yellow: return 30
        case .green: return 110
        case .blue: return 195
        case .purple: return 250
        case .pink: return 310
        case .red: return -20
        case .gray: return 0
        }
    }

    public static func tintedICNS(from source: URL, tint: Tint, output: URL, shell: Shell = Shell()) throws {
        guard let image = NSImage(contentsOf: source) else { throw BrainmergeError.iconFailed(source.path) }
        let result: NSImage
        switch tint {
        case .orange: result = image
        case .gray: result = try filtered(image, name: "CIColorControls", parameters: [kCIInputSaturationKey: 0.0], source: source)
        default:
            let radians = hueShiftDegrees(for: tint) * .pi / 180
            result = try filtered(image, name: "CIHueAdjust", parameters: [kCIInputAngleKey: radians], source: source)
        }
        try writeICNS(result, to: output, shell: shell)
    }

    public static func icns(fromImage source: URL, output: URL, shell: Shell = Shell()) throws {
        guard let image = NSImage(contentsOf: source), image.isValid else { throw BrainmergeError.iconFailed(source.path) }
        try writeICNS(image, to: output, shell: shell)
    }

    /// Color at the center of the icon, rendered at 64 pixels (tests and previews).
    static func centerPixel(of icns: URL) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let image = NSImage(contentsOf: icns) else { throw BrainmergeError.iconFailed(icns.path) }
        let rep = try bitmap(image, pixels: 64, source: icns)
        guard let color = rep.colorAt(x: 32, y: 32)?.usingColorSpace(.deviceRGB) else { throw BrainmergeError.iconFailed(icns.path) }
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    static func filtered(_ image: NSImage, name: String, parameters: [String: Any], source: URL) throws -> NSImage {
        guard let tiff = image.tiffRepresentation, let input = CIImage(data: tiff),
              let filter = CIFilter(name: name) else { throw BrainmergeError.iconFailed(source.path) }
        filter.setValue(input, forKey: kCIInputImageKey)
        for (key, value) in parameters { filter.setValue(value, forKey: key) }
        guard let output = filter.outputImage else { throw BrainmergeError.iconFailed(source.path) }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: rep.size)
        result.addRepresentation(rep)
        return result
    }

    static func writeICNS(_ image: NSImage, to output: URL, shell: Shell) throws {
        let work = FileManager.default.temporaryDirectory
            .appending(path: "brainmerge-icon-\(UUID().uuidString).iconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        for (name, px) in sizes {
            let rep = try bitmap(image, pixels: px, source: output)
            guard let data = rep.representation(using: .png, properties: [:]) else { throw BrainmergeError.iconFailed(output.path) }
            try data.write(to: work.appending(path: "\(name).png"))
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try shell.check("/usr/bin/iconutil", ["-c", "icns", "-o", output.path, work.path])
    }

    static func bitmap(_ image: NSImage, pixels: Int, source: URL) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw BrainmergeError.iconFailed(source.path) }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
