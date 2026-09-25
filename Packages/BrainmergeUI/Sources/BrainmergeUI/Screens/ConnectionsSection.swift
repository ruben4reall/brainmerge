import SwiftUI
import BrainmergeCore

/// The edit sheet's Connections: which browser profile goes with the account (saved with the sheet), a way to open it and
/// the account's connectors page, and its MCP servers by name. Names only: no value of any file is shown or kept.
struct ConnectionsSection: View {
    @Bindable var model: AppModel
    let account: Account
    /// The sheet's pick, not saved yet: the buttons act on the profile shown.
    @Binding var choice: BrowserChoice?
    /// Long lists of servers stay folded until asked for.
    @State private var showsServers = false

    /// Past this many servers the list folds.
    nonisolated static func folds(serverCount: Int) -> Bool { serverCount > 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let options = model.browserOptions(keeping: choice)
            if !options.isEmpty {
                Picker("Browser", selection: $choice) {
                    ForEach(options, id: \.self) { option in Text(option.label).tag(option.choice) }
                }
                .pickerStyle(.menu).fixedSize()
            }
            if let label = model.openBrowserLabel(choice), let choice {
                HStack(spacing: 10) {
                    Button(label) { model.openBrowser(choice) }.buttonStyle(.glass).controlSize(.small)
                    Spacer(minLength: 0)
                }
                faint(AppModel.browserGuide(account: account.identity.name))
            }
            HStack(spacing: 10) {
                Button("Manage connectors") { model.manageConnectors(choice) }.buttonStyle(.glass).controlSize(.small)
                    // A picked profile is only known once the browsers are read: until then it could open the wrong one.
                    .disabled(choice != nil && model.installedBrowsers == nil)
                Spacer(minLength: 0)
            }
            faint(AppModel.connectorsGuide)
            servers
        }
        .task { await model.loadConnections() }
    }

    @ViewBuilder var servers: some View {
        if let inventory = model.mcpServers(account.id), !inventory.isEmpty {
            let groups = [("Claude Code, all projects", inventory.codeUser), ("Claude Code, one project", inventory.codeLocal),
                          ("Claude app", inventory.desktop), ("Claude app extensions", inventory.extensions)].filter { !$0.1.isEmpty }
            let onlyHere = model.onlyHere(account.id)
            let count = groups.reduce(0) { $0 + $1.1.count }
            let title = Text(count == 1 ? "1 MCP server" : "\(count) MCP servers").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.text)
            let list = VStack(alignment: .leading, spacing: 4) {
                ForEach(groups, id: \.0) { group, names in
                    Text(group).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    ForEach(names, id: \.self) { name in
                        HStack(spacing: 6) {
                            Text(name).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.text)
                            if onlyHere.contains(name) {
                                Text("Only here").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.accentLight)
                            }
                        }
                    }
                }
            }
            if Self.folds(serverCount: count) {
                DisclosureGroup(isExpanded: $showsServers) { list.padding(.top, 4) } label: { title }
            } else {
                title
                list
            }
            faint("Names only. Brainmerge does not copy servers between accounts.")
        }
    }

    func faint(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).fixedSize(horizontal: false, vertical: true)
    }
}
