import SwiftUI
import BrainmergeCore

/// Shown instead of the setup when state.json exists but cannot be read: the accounts are still on disk.
struct StateProblemView: View {
    @Bindable var model: AppModel
    let problem: StateProblem

    var body: some View {
        VStack(spacing: 18) {
            Text(StateProblem.title).font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center)
            Text(problem.detail).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.glass)
                Button("Show in Finder") { model.showStateFileInFinder() }.buttonStyle(.glass)
                // The one purple button: only when there is a copy to put back.
                if model.canRestorePreviousState {
                    Button("Restore the previous copy") { model.restorePreviousState() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
