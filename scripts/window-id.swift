// swift scripts/window-id.swift [APP]: the ID of the app's main window (Brainmerge by default), for
// screencapture -l: it captures the window without bringing it to the front, so without stealing the person's keyboard.
import AppKit
import CoreGraphics

let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Brainmerge"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0[kCGWindowOwnerName as String] as? String) == name && (($0[kCGWindowLayer as String] as? Int) ?? 0) == 0 }
    .sorted { (($0[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) > (($1[kCGWindowBounds as String] as? [String: Double])?["Width"] ?? 0) }
if let id = windows.first?[kCGWindowNumber as String] as? Int { print(id) } else { exit(1) }
