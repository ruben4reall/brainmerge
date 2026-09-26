import Foundation
import Testing

/// Tests that draw into a hosted window and read its pixels frame by frame, as the screen shows them. CI runners have no
/// display: vibrant text and glass draw nothing there and frames are not paced, so these films prove nothing on CI.
/// They run on every Mac with a screen, and the pure frame functions they film are tested everywhere.
extension Trait where Self == ConditionTrait {
    static var needsARealDisplay: Self {
        .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "CI runners have no display to draw and pace frames")
    }
}
