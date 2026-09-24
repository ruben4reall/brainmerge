import SwiftUI
import BrainmergeUI

@main
struct BrainmergeApp: App {
    @State private var model = AppModel.live()
    var body: some Scene {
        WindowGroup { RootView(model: model) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
    }
}
