import AppKit
import SwiftUI
import BrainmergeCore

/// "Remove Brainmerge": says what goes and what stays, then does it, moves the app to the Trash and quits.
public struct UninstallSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var problem = InlineProblem()

    public init(model: AppModel, isPresented: Binding<Bool>) { self.model = model; _isPresented = isPresented }

    public var body: some View {
        let plan = model.uninstallPlan()
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Remove Brainmerge").font(Theme.Fonts.sheetTitle)
                Text("Everything Brainmerge set up is undone. Nothing of yours is deleted.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
            }
            if let plan {
                list("Removed", plan.removed, symbol: "minus.circle", tint: Theme.Colors.textMuted)
                list("Kept", plan.kept, symbol: "checkmark.circle", tint: Theme.Colors.sage)
            }
            Text("Every account's Claude keeps working as before Brainmerge: each project gets a copy of its notes next to its sessions.")
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            ProblemLine(problem: problem)
            HStack(spacing: 10) {
                WorkingLine(text: model.working)
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Remove Brainmerge", role: .destructive) { remove() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    .disabled(model.working != nil)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(WarmBackground())
    }

    func list(_ title: String, _ lines: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(tint).font(.system(size: 12))
                    Text(line).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                }
            }
        }
    }

    func remove() {
        Task {
            if await model.uninstall() != nil {
                Installer.trashSelfAndQuit()
            } else {
                problem.show(model.message?.detail); model.message = nil
            }
        }
    }
}
