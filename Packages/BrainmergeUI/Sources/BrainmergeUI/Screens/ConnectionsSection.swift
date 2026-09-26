import SwiftUI
import BrainmergeCore

/// The edit sheet's Connections: which browser profile goes with the account (saved with the sheet), a way to open it and
/// the account's connectors page, and its MCP servers by name. Names only: no value of any file is shown or kept.
struct ConnectionsSection: View {
    @Bindable var model: AppModel
    let account: Account
    /// The sheet's pick, not saved yet: the buttons act on the profile shown.
    @Binding var choice: BrowserChoice?
    /// Brings a line that opened below the fold into view (the sheet's scroll view, by id).
    var reveal: (String) -> Void = { _ in }
    /// Long lists of servers stay folded until asked for.
    @State private var showsServers = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What opens under a line (the profile's buttons, the list of servers): it waits for its room, then fades in, so it
    /// never prints over the lines it pushes down; it goes at once.
    static func opens(_ reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .fade(true) }
        return .asymmetric(insertion: AnyTransition.opacity.animation(Theme.Motion.out(0.16).delay(0.1 * Theme.Motion.slow)),
                           removal: AnyTransition.opacity.animation(Theme.Motion.out(0.1)))
    }
    static let profileID = "connections.profile", serversEndID = "connections.servers.end"

    /// Past this many servers the list folds.
    nonisolated static func folds(serverCount: Int) -> Bool { serverCount > 6 }

    /// What is read after the sheet opens (the browsers, the servers) drops in as it comes, and picking a profile opens
    /// its line: the sheet eases to each new height instead of jumping. With Reduce Motion the sheet takes its height at
    /// once and what comes fades in where it lands.
    var body: some View {
        let options = model.browserOptions(keeping: choice)
        let serversRead = model.mcpServers(account.id) != nil
        VStack(alignment: .leading, spacing: 8) {
            if !options.isEmpty {
                Picker("Browser", selection: $choice) {
                    ForEach(options, id: \.self) { option in Text(option.label).tag(option.choice) }
                }
                .pickerStyle(.menu).fixedSize()
                .transition(.fade(reduceMotion))
            }
            if let label = model.openBrowserLabel(choice), let choice {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Button(label) { model.openBrowser(choice) }.buttonStyle(.glass).controlSize(.small)
                        Spacer(minLength: 0)
                    }
                    faint(AppModel.browserGuide(account: account.identity.name))
                }
                .id(Self.profileID)
                .transition(Self.opens(reduceMotion))
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
        .animation(Theme.Motion.layout(Theme.Motion.out(0.2), reduceMotion), value: options.isEmpty)
        .animation(Theme.Motion.layout(Theme.Motion.out(0.2), reduceMotion), value: choice)
        .animation(Theme.Motion.layout(Theme.Motion.out(Arrival.line.duration), reduceMotion), value: serversRead)
        .task { await model.loadConnections() }
        // What opens below the fold is brought into view once it has its room.
        .onChange(of: choice) { _, choice in
            guard model.openBrowserLabel(choice) != nil else { return }
            Task { try? await Task.sleep(for: .seconds(0.22 * Theme.Motion.slow)); reveal(Self.profileID) }
        }
        .onChange(of: showsServers) { _, shows in
            guard shows else { return }
            Task { try? await Task.sleep(for: .seconds(0.22 * Theme.Motion.slow)); reveal(Self.serversEndID) }
        }
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
                Color.clear.frame(height: 1).id(Self.serversEndID)
            }
            // Its groups and names start at the left edge, under the title, never centered in the sheet.
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if Self.folds(serverCount: count) {
                    DisclosureGroup(isExpanded: $showsServers) { list.padding(.top, 4).transition(Self.opens(reduceMotion)) } label: { title }
                        .animation(Theme.Motion.layout(Theme.Motion.out(0.2), reduceMotion), value: showsServers)
                } else {
                    title
                    list
                }
                faint("Names only. Brainmerge does not copy servers between accounts.")
            }
            .transition(.line(reduceMotion))
        }
    }

    func faint(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).fixedSize(horizontal: false, vertical: true)
    }
}
