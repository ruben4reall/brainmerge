// swift scripts/click.swift X Y [APP]: a real left click at screen coordinates (points), for capturing sheets and menus.
// Refuses to click if the frontmost app is not APP (Brainmerge by default): never a blind click into another app.
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: swift scripts/click.swift X Y [APP]\n".utf8)); exit(1)
}
let expected = args.count > 3 ? args[3] : "Brainmerge"
let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
guard front == expected else {
    FileHandle.standardError.write(Data("click refused: \"\(front)\" is in front, not \"\(expected)\"\n".utf8)); exit(2)
}
let point = CGPoint(x: x, y: y)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(80_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(60_000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
