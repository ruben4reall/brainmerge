import SwiftUI
import BrainmergeCore

/// "Log in to …": the three steps, then the live status. One purple button at a time: Start, then the reopen.
struct LoginSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        if let flow = model.login {
            VStack(alignment: .leading, spacing: 14) {
                Text(flow.title).font(Theme.Fonts.sheetTitle)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(flow.steps.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1).").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                            Text(line).font(Theme.Fonts.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let status = flow.status {
                    Text(status).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                HStack(spacing: 10) {
                    Spacer()
                    if flow.closeLabel == "Done" {
                        // Alone: nothing was closed, so nothing to reopen. The one purple button ends the sheet.
                        Button(flow.closeLabel) { model.cancelLogin() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button(flow.closeLabel) { model.cancelLogin() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                    }
                    if flow.step == .ready {
                        Button("Start") { model.startLogin() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                            .keyboardShortcut(.defaultAction)
                    } else if flow.canConfirm {
                        Button("I'm logged in") { model.confirmLoggedIn() }.buttonStyle(.glass)
                    }
                    if flow.step != .ready, !flow.others.isEmpty {
                        Button(flow.reopenLabel) { model.reopenAfterLogin() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                            .disabled(!flow.canReopen)
                    }
                }
            }
            .padding(22)
            .frame(width: 440)
        }
    }
}
