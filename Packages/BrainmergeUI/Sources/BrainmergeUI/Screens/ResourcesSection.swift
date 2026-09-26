import SwiftUI
import BrainmergeCore

/// The top of the Usage screen: the Mac's RAM, then what each account uses of it and of the disk, then Claude Code in a
/// terminal and the other apps. Every text comes from ResourceSummary; this view only lays it out.
struct ResourcesSection: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// "Measure again": kept so that leaving the screen stops it like the regular walk.
    @State private var forcedWalk: Task<Void, Never>?

    static let ramColumn: CGFloat = 116
    static let barColumn: CGFloat = 120
    static let diskColumn: CGFloat = 128

    var summary: ResourceSummary {
        ResourceSummary.make(accounts: model.accounts, ram: model.ramBySlug, disk: model.disk, mac: model.macMemory, terminal: model.terminalUse)
    }

    var body: some View {
        let summary = self.summary
        VStack(alignment: .leading, spacing: 12) {
            macCard(summary.mac)
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    // The per-row bars go first when the window is narrow.
                    ViewThatFits(in: .horizontal) {
                        table(summary.rows, bars: true)
                        table(summary.rows, bars: false)
                    }
                    Divider().overlay(Theme.Colors.surfaceLine)
                    footer(summary.footer)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
        .onDisappear { forcedWalk?.cancel() }
    }

    func macCard(_ mac: ResourceSummary.Mac?) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("This Mac").font(Theme.Fonts.cardName)
                if let mac {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(mac.used).font(Theme.Fonts.figure).monospacedDigit()
                        Text(mac.detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).monospacedDigit()
                        Spacer(minLength: 12)
                        if let pressure = mac.pressure {
                            Label(pressure, systemImage: "exclamationmark.triangle.fill").font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.Colors.text)
                        }
                    }
                    .help("Counted like Activity Monitor: apps, wired and compressed.")
                    bar(mac.fraction, color: Theme.Colors.meter, height: 10)
                    Text(mac.breakdown).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint)
                } else {
                    Text("RAM figures are not available right now.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(mac?.accessibilityLabel ?? "RAM figures are not available right now.")
        }
    }

    func table(_ rows: [ResourceSummary.Row], bars: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                columnLabel("RAM").frame(width: Self.ramColumn, alignment: .trailing)
                if bars { Color.clear.frame(width: Self.barColumn, height: 1) }
                columnLabel("Disk").frame(width: Self.diskColumn, alignment: .trailing)
            }
            .accessibilityHidden(true)
            ForEach(rows) { row in self.row(row, bars: bars) }
        }
    }

    func columnLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
    }

    func row(_ row: ResourceSummary.Row, bars: Bool) -> some View {
        let color = row.tint.map(Theme.color(for:)) ?? Theme.Colors.meter
        return HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(Theme.Fonts.cardName).lineLimit(1)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                // Nothing running: the state takes the figure's place, fainter.
                Text(row.ram ?? row.ramDetail).font(Theme.Fonts.body).monospacedDigit()
                    .foregroundStyle(row.ram == nil ? Theme.Colors.textFaint : Theme.Colors.text)
                if row.ram != nil {
                    Text(row.ramDetail).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint).monospacedDigit()
                }
            }
            .lineLimit(1)
            .frame(width: Self.ramColumn, alignment: .trailing)
            .help(row.ramHelp ?? "")
            if bars { bar(row.fraction, color: color, height: 6).frame(width: Self.barColumn) }
            // "Measuring…" gives way to the size in a crossfade. The RAM figures, redrawn every few seconds, never animate.
            Text(row.disk ?? "").font(Theme.Fonts.body).monospacedDigit().lineLimit(1)
                .foregroundStyle(row.diskIsFigure ? Theme.Colors.text : Theme.Colors.textFaint)
                .contentTransition(.opacity)
                .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: row.disk)
                .frame(width: Self.diskColumn, alignment: .trailing)
                .help(row.diskHelp ?? "")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.accessibilityLabel)
    }

    func footer(_ text: String) -> some View {
        let when = model.diskMeasuring ? " Measuring the disk…"
            : model.diskMeasuredAt.map { " Disk measured at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            // While the disk is walked, a small spinner before the sentence.
            HStack(alignment: .center, spacing: 6) {
                if model.diskMeasuring { ProgressView().controlSize(.mini).transition(.opacity) }
                Text(text + when).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: model.diskMeasuring)
            Spacer(minLength: 12)
            Button("Measure again") {
                forcedWalk?.cancel()
                forcedWalk = Task { await model.refreshDisk(force: true) }
            }
            .buttonStyle(.glass).controlSize(.small)
            .disabled(model.diskMeasuring)
        }
    }

    /// A share of the Mac's RAM on a faint track; a share that is not nothing always shows (2 pt at least).
    func bar(_ fraction: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Layout.meterRadius, style: .continuous).fill(Theme.Colors.field)
                RoundedRectangle(cornerRadius: Theme.Layout.meterRadius, style: .continuous).fill(color)
                    .frame(width: fraction > 0 ? max(2, geometry.size.width * fraction) : 0)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Theme.Motion.out(0.25), value: fraction)
        .accessibilityHidden(true)
    }
}
