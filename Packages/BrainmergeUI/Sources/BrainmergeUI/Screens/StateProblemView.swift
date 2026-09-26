import SwiftUI
import BrainmergeCore

/// Shown instead of the setup when state.json exists but cannot be read: the accounts are still on disk.
struct StateProblemView: View {
    @Bindable var model: AppModel
    let problem: StateProblem
    @State private var restoring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WarmBackground()
            VStack(spacing: 18) {
                Text(StateProblem.title).font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center)
                Text(problem.detail(canRestore: model.canRestorePreviousState)).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted)
                    .multilineTextAlignment(.center).frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                HStack(spacing: 10) {
                    Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.glass)
                    Button("Show in Finder") { model.showStateFileInFinder() }.buttonStyle(.glass)
                    // The one purple button: only when there is a copy this version can read.
                    if model.canRestorePreviousState {
                        Button("Restore the previous copy") {
                            restoring = true
                            Task { await model.restorePreviousState(); restoring = false }
                        }
                        .buttonStyle(.glassProminent).tint(Theme.Colors.button).disabled(restoring)
                        .transition(.opacity)
                    }
                }
                // The restore waits for the lock while the command line changes the list: say it is working.
                WorkingLine(text: restoring ? "Restoring the previous copy…" : nil)
            }
            .padding(40)
            .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: model.canRestorePreviousState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
