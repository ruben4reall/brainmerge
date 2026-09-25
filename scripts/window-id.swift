// swift scripts/window-id.swift [PID | APP]: the ID of the main window of a process (by PID) or of an app (by name,
// Brainmerge by default), for screencapture -l, which captures a window without bringing it to the front.
// With a PID, only that process's windows count: a demo capture can never pick up another copy of the app.
// Windows on another Space count too (screencapture -l can capture them).
import AppKit
import CoreGraphics

let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Brainmerge"
let pid = Int32(argument)
let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
func size(_ window: [String: Any]) -> (Double, Double) {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (bounds["Width"] ?? 0, bounds["Height"] ?? 0)
}
// A real window: layer 0 and taller than a menu bar strip. The largest by area wins.
let windows = list.filter { window in
    guard ((window[kCGWindowLayer as String] as? Int) ?? 0) == 0, size(window).1 > 200 else { return false }
    if let pid { return (window[kCGWindowOwnerPID as String] as? Int32) == pid }
    return (window[kCGWindowOwnerName as String] as? String) == argument
}.sorted { size($0).0 * size($0).1 > size($1).0 * size($1).1 }
if let id = windows.first?[kCGWindowNumber as String] as? Int { print(id) } else { exit(1) }
