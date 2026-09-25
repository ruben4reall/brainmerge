import SwiftUI
import BrainmergeCore

/// The edit sheet's Connections: which browser profile goes with the account, a way to open it and the account's
/// connectors page, and its MCP servers by name. Names only: no value of any file is shown or kept.
struct ConnectionsSection: View {
    @Bindable var model: AppModel
    let account: Account
    /// Long lists of servers stay folded until asked for.
    @State private var showsServers = false

    var choice: Binding<BrowserChoice?> {
        Binding(get: { account.identity.browser }, set: { model.setBrowser(account.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.installedBrowsers.isEmpty {
                Picker("Browser", selection: choice) {
                    Text("None").tag(BrowserChoice?.none)
                    ForEach(model.installedBrowsers, id: \.browser) { browser in
                        ForEach(browser.profiles, id: \.self) { profile in
                            Text("\(browser.browser.displayName) · \(profile.name)")
                                .tag(BrowserChoice?.some(BrowserChoice(browser: browser.browser, directory: profile.directory)))
                        }
                    }
                }
                .pickerStyle(.menu).fixedSize()
            }
            if let label = model.openBrowserLabel(account.id) {
                HStack(spacing: 10) {
                    Button(label) { model.openBrowser(account.id) }.buttonStyle(.glass).controlSize(.small)
                    Spacer(minLength: 0)
                }
                faint(AppModel.browserGuide(account: account.identity.name))
            }
            HStack(spacing: 10) {
                Button("Manage connectors") { model.manageConnectors(account.id) }.buttonStyle(.glass).controlSize(.small)
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
            DisclosureGroup(isExpanded: count > 6 ? $showsServers : .constant(true)) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(groups, id: \.0) { title, names in
                        Text(title).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
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
                .padding(.top, 4)
            } label: {
                Text(count == 1 ? "1 MCP server" : "\(count) MCP servers").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.text)
            }
            faint("Names only. Brainmerge does not copy servers between accounts.")
        }
    }

    func faint(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).fixedSize(horizontal: false, vertical: true)
    }
}
