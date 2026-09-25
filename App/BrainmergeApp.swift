import SwiftUI
import BrainmergeUI

@main
struct BrainmergeApp: App {
    /// The model lives with the delegate: it outlives the window, and AppKit asks the delegate before quitting.
    @NSApplicationDelegateAdaptor(BrainmergeAppDelegate.self) private var delegate
    var body: some Scene { BrainmergeScenes(model: delegate.model) }
}
