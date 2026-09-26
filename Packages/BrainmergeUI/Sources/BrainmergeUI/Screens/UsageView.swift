import AppKit
import SwiftUI
import BrainmergeCore

/// What each account uses on this Mac (RAM and disk) and what it spent in Claude Code, read from its local transcripts,
/// plus its limits when asked: "Check limits" runs that account's own Claude Code on a click, never on its own.
/// Informational: never a switcher, never a comparison between accounts.
public struct UsageView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollViewReader { proxy in content
            .onChange(of: model.requestedUsage, initial: true) { focusRequested(proxy) }
            .onChange(of: model.usage) { focusRequested(proxy) }
            .onChange(of: model.usageRefreshing) { focusRequested(proxy) }
        }
        // A request left over when the screen goes (no card to show) never scrolls a later visit.
        .onDisappear { model.requestedUsage = nil }
    }

    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader("Usage", subtitle: "What your accounts use on this Mac and spent in Claude Code. Brainmerge never reads limits by itself: Check limits asks that account's Claude Code.") {
                    Button("See limits in Claude") { if let url = URL(string: "https://claude.ai/settings/usage") { NSWorkspace.shared.open(url) } }.buttonStyle(.glass)
                }
                sectionLabel("RAM and disk")
                ResourcesSection(model: model)
                sectionLabel("Spent in Claude Code").padding(.top, 8)
                if model.usage.isEmpty {
                    GlassCard {
                        Text(model.usageRefreshing ? "Reading the transcripts…" : "Nothing yet. Open an account and work in Claude Code: what it spends shows up here.")
                            .foregroundStyle(Theme.Colors.textMuted).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
                }
                ForEach(model.usage) { entry in card(entry).frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading).id(entry.id) }
                HStack(spacing: 6) {
                    if let date = model.usageUpdatedAt { Text("Updated \(date.formatted(date: .omitted, time: .shortened)).") }
                    Text("Estimates: output tokens are what Claude wrote, context is what it read (cache included). Brainmerge never switches accounts for you.")
                }
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
                if model.accounts.contains(where: { $0.identity.surfaces.cli }) {
                    Text(LimitsText.caption).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
                }
            }
            .padding(Theme.Layout.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.refreshUsage() }
        // Disk sizes: walked when the screen opens, then again every few minutes at most (refreshDisk decides) or
        // right after a change to the accounts. Leaving the screen cancels this task, and the walk with it.
        .task {
            while !Task.isCancelled {
                await model.refreshDisk()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// The quick opener's Cmd-U: scroll to the card holding the account (a shared history's card too), or let go once
    /// a read is done without one, so no later read scrolls on its own. Nil waits.
    enum Focus: Equatable { case scroll(String), drop }
    static func focus(requested: String?, usage: [AccountUsage], refreshing: Bool, updated: Date?) -> Focus? {
        guard let requested else { return nil }
        if let entry = usage.first(where: { $0.slugs.contains(requested) }) { return .scroll(entry.id) }
        return !refreshing && updated != nil ? .drop : nil
    }

    func focusRequested(_ proxy: ScrollViewProxy) {
        switch Self.focus(requested: model.requestedUsage, usage: model.usage, refreshing: model.usageRefreshing, updated: model.usageUpdatedAt) {
        case .scroll(let id):
            proxy.scrollTo(id, anchor: .top)
            model.requestedUsage = nil
        case .drop: model.requestedUsage = nil
        case nil: break
        }
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            .accessibilityAddTraits(.isHeader)
    }

    func card(_ entry: AccountUsage) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    ForEach(Array(entry.slugs.enumerated()), id: \.offset) { index, _ in
                        OrbView(name: entry.names[index], tint: entry.tints[index], size: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.names.joined(separator: " and ")).font(Theme.Fonts.cardName)
                        if entry.shared { Text("Shared history: these accounts write the same transcripts, so their usage is one number.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
                    }
                    Spacer()
                }
                // Figures on one line and the chart on the right; when the card is narrow, the chart goes under the figures.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 28) {
                        figures(entry.summary)
                        Spacer(minLength: 16)
                        sparkline(entry.summary.byDay).frame(width: 220, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 28) { figures(entry.summary) }
                        sparkline(entry.summary.byDay).frame(maxWidth: 360).frame(height: 36)
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    list("Projects", entry.summary.byProject.prefix(4).map { (ProjectSlug.projectName(forSlug: $0.key, home: model.paths.home), $0.output) })
                    list("Models", entry.summary.byModel.prefix(4).map { ($0.key.replacingOccurrences(of: "claude-", with: ""), $0.output) })
                }
                // Each account with Claude Code has its own limits, even when two share one history.
                let checkable = entry.slugs.indices.filter { model.canCheckLimits(entry.slugs[$0]) }
                if !checkable.isEmpty {
                    Divider().overlay(Theme.Colors.surfaceLine)
                    ForEach(checkable, id: \.self) { index in
                        limits(entry.slugs[index], name: entry.names[index], tint: Theme.color(for: entry.tints[index]), shared: entry.shared)
                    }
                }
            }
            .padding(16)
        }
    }

    /// "Check limits" and what it found: nothing before the first click, then Claude Code's lines or one sentence.
    func limits(_ slug: String, name: String, tint: Color, shared: Bool) -> some View {
        let state = model.limits[slug]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(LimitsText.title(name: name, shared: shared).uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                if state == .checking {
                    Text(LimitsText.checking).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                } else if case .checked(_, let at) = state {
                    Text(LimitsText.checkedAt(at)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint)
                }
                Button("Check limits") { Task { await model.checkLimits(slug) } }
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(state == .checking)
                    .accessibilityLabel(LimitsText.buttonLabel(name: name))
                    .help(LimitsText.buttonHelp)
            }
            switch state {
            case .checked(let lines, _):
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 28, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in limitRow(line, tint: tint) }
                }
            case .refused(let sentence):
                Text(sentence).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            case .checking, nil:
                EmptyView()
            }
        }
    }

    /// One limit: Claude Code's label, the percent used, a thin bar in the account's color, and the reset time as written.
    func limitRow(_ line: LimitLine, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(line.label).font(Theme.Fonts.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Text(LimitsText.percent(line)).font(Theme.Fonts.secondary).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Layout.meterRadius, style: .continuous).fill(Theme.Colors.field)
                    RoundedRectangle(cornerRadius: Theme.Layout.meterRadius, style: .continuous).fill(tint)
                        .frame(width: line.fraction > 0 ? max(2, geometry.size.width * line.fraction) : 0)
                }
            }
            .frame(height: 6)
            if let resets = LimitsText.resets(line) {
                Text(resets).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LimitsText.accessibilityLabel(line))
    }

    @ViewBuilder func figures(_ summary: UsageSummary) -> some View {
        figure("Today", summary.todayOutput, summary.today)
        figure("7 days", summary.weekOutput, summary.week)
        figure("30 days", summary.monthOutput, summary.month)
    }

    func figure(_ label: String, _ output: Int, _ total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            Text(TokenFormat.short(output)).font(Theme.Fonts.figure)
            Text("written · \(TokenFormat.short(total)) context").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
        }
        .fixedSize()
    }

    func list(_ title: String, _ rows: [(String, Int)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            if rows.isEmpty { Text("Nothing in the last 30 days.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack { Text(row.0).font(Theme.Fonts.secondary).lineLimit(1); Spacer(); Text(TokenFormat.short(row.1)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    /// Fourteen bars, one per day, the most recent on the right.
    func sparkline(_ days: [UsageSummary.Bucket]) -> some View {
        Canvas { context, size in
            let maxValue = max(1, days.map(\.output).max() ?? 1)
            let slot = size.width / CGFloat(max(1, days.count))
            for (index, day) in days.enumerated() {
                let height = max(2, size.height * CGFloat(day.output) / CGFloat(maxValue))
                let rect = CGRect(x: CGFloat(index) * slot + 2, y: size.height - height, width: slot - 4, height: height)
                let isToday = index == days.count - 1
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(isToday ? Theme.Colors.accent : Theme.Colors.accentSoft))
            }
        }
        .accessibilityLabel("Output tokens per day, last 14 days")
    }
}
