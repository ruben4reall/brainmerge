import AppKit
import Foundation
import BrainmergeCore

public enum FakeIcon {
    /// An orange 64x64 square, the color of Claude's icon.
    public static func orangePNG(in dir: URL) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: 0.85, green: 0.45, blue: 0.2, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appending(path: "orange.png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    public static func writeICNS(to output: URL) throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "fake-icon-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try IconGenerator.icns(fromImage: orangePNG(in: work), output: output)
    }
}
