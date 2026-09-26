import AppKit
import SwiftUI
import BrainmergeCore

/// What each account uses on this Mac (RAM and disk) and what it spent in Claude Code, read from its local transcripts,
/// plus its limits when asked: "Check limits" runs that account's own Claude Code on a click, never on its own.
/// Informational: never a switcher, never a comparison between accounts.
public struct UsageView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(model: AppModel) { self.model = model }

    public var body: some View {
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
                        HStack(spacing: 8) {
                            if model.usageRefreshing { ProgressView().controlSize(.small).transition(.fade(reduceMotion)) }
                            Text(model.usageRefreshing ? "Reading the transcripts…" : "Nothing yet. Open an account and work in Claude Code: what it spends shows up here.")
                                .foregroundStyle(Theme.Colors.textMuted).contentTransition(.opacity)
                        }
                        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .animation(Theme.Motion.layout(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: model.usageRefreshing)
                    }
                    .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
                }
                // The first read comes in card by card, 50 ms apart; a later visit finds them in place.
                ForEach(Array(model.usage.enumerated()), id: \.element.id) { index, entry in
                    card(entry, index: index, arrivedAt: model.usageArrivedAt).frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
                }
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

    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            .accessibilityAddTraits(.isHeader)
    }

    /// A card, coming in `index` places after the first when the first read replaced the placeholder at `arrivedAt`.
    func card(_ entry: AccountUsage, index: Int, arrivedAt: Date?) -> some View {
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
                        sparkline(entry.summary.byDay, card: index, arrivedAt: arrivedAt).frame(width: 220, height: 44)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 28) { figures(entry.summary) }
                        sparkline(entry.summary.byDay, card: index, arrivedAt: arrivedAt).frame(maxWidth: 360).frame(height: 36)
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
        .arrives(Arrival.data.delayed(UsageMotion.cardDelay(index)), from: arrivedAt)
    }

    /// "Check limits" and what it found: nothing before the first click, then Claude Code's lines or one sentence. While
    /// it asks, a small spinner says so; the lines then come in one after the other, each bar growing to its share.
    func limits(_ slug: String, name: String, tint: Color, shared: Bool) -> some View {
        let state = model.limits[slug]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(LimitsText.title(name: name, shared: shared).uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                if state == .checking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(LimitsText.checking).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                    }
                    .transition(.fade(reduceMotion))
                } else if case .checked(_, let at) = state {
                    Text(LimitsText.checkedAt(at)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint).transition(.fade(reduceMotion))
                }
                Button("Check limits") { Task { await model.checkLimits(slug) } }
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(state == .checking)
                    .accessibilityLabel(LimitsText.buttonLabel(name: name))
                    .help(LimitsText.buttonHelp)
            }
            switch state {
            case .checked(let lines, let at):
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 28, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        limitRow(line, tint: tint, index: index, arrived: at)
                            .arrives(Arrival.data.delayed(UsageMotion.cardDelay(index)), from: at)
                    }
                }
            case .refused(let sentence):
                Text(sentence).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.line(reduceMotion))
            case .checking, nil:
                EmptyView()
            }
        }
        .animation(Theme.Motion.layout(Theme.Motion.out(Arrival.line.duration), reduceMotion), value: state)
    }

    /// One limit: Claude Code's label, the percent used, a thin bar in the account's color, and the reset time as written.
    /// The bar grows from nothing to its share as the answer comes in, like the chart's bars.
    func limitRow(_ line: LimitLine, tint: Color, index: Int, arrived: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(line.label).font(Theme.Fonts.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Text(LimitsText.percent(line)).font(Theme.Fonts.secondary).monospacedDigit()
            }
            GeometryReader { geometry in
                let delay = UsageMotion.cardDelay(index)
                BeatView(start: arrived, duration: delay + UsageMotion.barGrowth) { elapsed in
                    let grown = reduceMotion ? 1 : elapsed.map { Ease.out(Ease.progress($0, from: delay, over: UsageMotion.barGrowth)) } ?? 1
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Theme.Layout.meterRadius, style: .continuous).fill(Theme.Colors.field)
                        RoundedRectangle(cornerRadius: Theme.Layout.meterRadius, style: .continuous).fill(tint)
                            .frame(width: line.fraction > 0 ? max(2, geometry.size.width * line.fraction) * CGFloat(grown) : 0)
                    }
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

    /// A figure rolls to its new value when a later read changes it (at most once a minute); never on arrival. With Reduce
    /// Motion it changes at once: a new width would slide the figures after it.
    func figure(_ label: String, _ output: Int, _ total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            Text(TokenFormat.short(output)).font(Theme.Fonts.figure)
                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(output)))
                .animation(Theme.Motion.layout(Theme.Motion.out(UsageMotion.update), reduceMotion), value: output)
            Text("written · \(TokenFormat.short(total)) context").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
                .contentTransition(.opacity)
                .animation(Theme.Motion.layout(Theme.Motion.out(UsageMotion.update), reduceMotion), value: total)
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

    /// Fourteen bars, one per day, the most recent on the right. With the first read they grow from a 2 point baseline,
    /// left to right, today's last; a later read moves them to their new height in 0.3 s.
    func sparkline(_ days: [UsageSummary.Bucket], card: Int, arrivedAt: Date?) -> some View {
        let maxValue = max(1, days.map(\.output).max() ?? 1)
        let delay = UsageMotion.cardDelay(card)
        return GeometryReader { geometry in
            let slot = geometry.size.width / CGFloat(max(1, days.count))
            BeatView(start: arrivedAt, duration: delay + UsageMotion.barsDuration) { elapsed in
                ZStack(alignment: .bottomLeading) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        let height = UsageMotion.barHeight(fraction: Double(day.output) / Double(maxValue), height: geometry.size.height,
                                                           index: index, elapsed: elapsed.map { $0 - delay }, reduceMotion: reduceMotion)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(index == days.count - 1 ? Theme.Colors.accent : Theme.Colors.accentSoft)
                            .frame(width: max(0, slot - 4), height: height)
                            .offset(x: CGFloat(index) * slot + 2)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
                .animation(Theme.Motion.layout(Theme.Motion.out(UsageMotion.update), reduceMotion), value: days.map(\.output))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Output tokens per day, last 14 days")
    }
}
