import AppKit
import SwiftUI
import BrainmergeCore

/// Settings' first section: what the doctor found, in plain sentences, each with the one button that mends it. Glass
/// buttons only: a screen's one purple button is never here.
struct HealthSection: View {
    @Bindable var model: AppModel

    static let allGood = "Everything is in place."
    static let checking = "Checking…"
    static let tooSlow = "The check took more than 10 seconds and was left."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = model.healthNote {
                Text(note).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            }
            if model.health == nil {
                if model.healthTimedOut {
                    HStack(spacing: 10) {
                        Text(Self.tooSlow).foregroundStyle(Theme.Colors.textMuted)
                        Button("Check again") { Task { await model.checkHealth() } }.buttonStyle(.glass).disabled(model.healthChecking)
                    }
                } else {
                    Text(Self.checking).foregroundStyle(Theme.Colors.textMuted)
                }
            } else if model.healthProblems.isEmpty {
                HStack(spacing: 10) {
                    Circle().fill(Theme.Colors.sage).frame(width: 8, height: 8)
                    Text(Self.allGood).foregroundStyle(Theme.Colors.textMuted)
                }
            } else {
                ForEach(Array(model.healthProblems.enumerated()), id: \.offset) { _, finding in row(finding) }
            }
        }
    }

    func row(_ finding: Doctor.Finding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(finding.level == .error ? Theme.Colors.accentLight : Theme.Colors.textFaint).frame(width: 8, height: 8)
            Text(finding.plain).foregroundStyle(Theme.Colors.textMuted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let fix = finding.fix {
                Button(HealthText.button(fix)) { run(fix) }.buttonStyle(.glass).controlSize(.small).disabled(model.healthChecking)
            }
        }
    }

    func run(_ fix: Doctor.Fix) {
        if case .chooseMemory(let id) = fix {
            chooseFolder(for: id)
        } else {
            Task { await model.applyFix(fix) }
        }
    }

    /// The folder where the memory lives now, or an empty one to start it again.
    func chooseFolder(for id: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let name = model.brains.first { $0.id == id }?.name ?? "the memory"
        panel.message = "Choose where \(name) lives now, or an empty folder to start it again. No note is moved."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.chooseMemoryFolder(id, at: url) }
    }
}
