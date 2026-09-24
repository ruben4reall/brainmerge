import AppKit
import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

@Suite struct IconGeneratorTests {
    @Test func buildsICNSFromImage() throws {
        let home = try TempHome(); defer { home.remove() }
        let out = home.url.appending(path: "logo.icns")
        try IconGenerator.icns(fromImage: FakeIcon.orangePNG(in: home.url), output: out)
        #expect(FileManager.default.fileExists(atPath: out.path))
        #expect(NSImage(contentsOf: out) != nil)
    }

    @Test func tintShiftsHueAndOrangeKeepsIt() throws {
        let home = try TempHome(); defer { home.remove() }
        let source = home.url.appending(path: "source.icns")
        try IconGenerator.icns(fromImage: FakeIcon.orangePNG(in: home.url), output: source)

        let blue = home.url.appending(path: "blue.icns")
        try IconGenerator.tintedICNS(from: source, tint: .blue, output: blue)
        let b = try IconGenerator.centerPixel(of: blue)
        #expect(b.blue > b.red)

        let orange = home.url.appending(path: "orange.icns")
        try IconGenerator.tintedICNS(from: source, tint: .orange, output: orange)
        let o = try IconGenerator.centerPixel(of: orange)
        #expect(o.red > o.blue)

        let gray = home.url.appending(path: "gray.icns")
        try IconGenerator.tintedICNS(from: source, tint: .gray, output: gray)
        let g = try IconGenerator.centerPixel(of: gray)
        #expect(abs(g.red - g.blue) < 0.08)
    }

    @Test func unreadableSourceThrows() throws {
        let home = try TempHome(); defer { home.remove() }
        let bad = home.url.appending(path: "bad.png")
        try Data("not an image".utf8).write(to: bad)
        #expect(throws: BrainmergeError.iconFailed(bad.path)) {
            try IconGenerator.icns(fromImage: bad, output: home.url.appending(path: "x.icns"))
        }
    }
}
