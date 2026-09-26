import Foundation
import BrainmergeCore

/// Sizes for people, with a point for decimals whatever the Mac's language: every number is written through
/// en_US_POSIX, never through the Mac's locale or C's (ByteCountFormatter printed "1,3 GB" in the English interface of
/// a French Mac).
public enum ByteFormat {
    static let mib = 1024.0 * 1024
    static let gib = mib * 1024
    /// The one locale sizes are written in: the interface is English on every Mac.
    static let locale = Locale(identifier: "en_US_POSIX")

    /// RAM in binary units, like Activity Monitor and About This Mac: whole MB under 1 GB, then one decimal.
    public static func ram(_ bytes: Int64) -> String { ram(bytes, locale: locale) }

    /// Disk space in decimal units, like Finder: whole MB under 1 GB, one decimal in GB, then TB.
    public static func disk(_ bytes: Int64) -> String { disk(bytes, locale: locale) }

    /// The same, written through `locale` (tests show the pin is what keeps the point).
    static func ram(_ bytes: Int64, locale: Locale) -> String {
        size(bytes, mega: mib, giga: gib, tera: nil, locale: locale)
    }
    static func disk(_ bytes: Int64, locale: Locale) -> String {
        size(bytes, mega: 1e6, giga: 1e9, tera: 1e12, locale: locale)
    }

    /// The Mac's RAM as Apple says it: "18 GB".
    public static func capacity(_ bytes: Int64) -> String {
        "\(Int((Double(bytes) / gib).rounded())) GB"
    }

    /// A whole percent; "< 1%" for a small share that is not nothing.
    public static func percent(_ part: Int64, of whole: Int64) -> String {
        guard part > 0, whole > 0 else { return "0%" }
        let value = (Double(part) / Double(whole) * 100).rounded()
        return value == 0 ? "< 1%" : "\(Int(value))%"
    }

    private static func size(_ bytes: Int64, mega: Double, giga: Double, tera: Double?, locale: Locale) -> String {
        guard bytes > 0 else { return "0 GB" }
        let value = Double(bytes)
        if value < mega { return "< 1 MB" }
        // Decided on the rounded figure, so 999.7 MB reads "1.0 GB", never "1000 MB".
        let megas = (value / mega).rounded()
        if megas < giga / mega { return "\(Int(megas)) MB" }
        let gigas = (value / giga * 10).rounded() / 10
        if let tera, gigas >= tera / giga { return String(format: "%.1f TB", locale: locale, value / tera) }
        return String(format: "%.1f GB", locale: locale, gigas)
    }
}

/// Every text of the Usage screen's RAM and disk section, from the numbers alone: what the Mac uses, then one row per
/// account, Claude Code in a terminal and the other apps. Percents are of the Mac's RAM, for every bar alike.
public struct ResourceSummary: Equatable, Sendable {
    public struct Mac: Equatable, Sendable {
        public var used: String
        public var detail: String
        /// Only when the kernel says the Mac is short of RAM.
        public var pressure: String?
        public var fraction: Double
        public var breakdown: String
        public var accessibilityLabel: String
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case account(String), terminal, otherApps }
        public var kind: Kind
        public var name: String
        public var tint: Tint?
        public var subtitle: String?
        /// Nil when there is nothing running to measure (closed, Claude Code only).
        public var ram: String?
        public var ramDetail: String
        public var ramHelp: String?
        public var fraction: Double
        /// Nil for rows without folders of their own.
        public var disk: String?
        /// A size, rather than a state ("Measuring…", "Not measured").
        public var diskIsFigure: Bool
        public var diskHelp: String?
        public var accessibilityLabel: String
        public var id: String {
            switch kind {
            case .account(let slug): return "account-" + slug
            case .terminal: return "terminal"
            case .otherApps: return "other-apps"
            }
        }
    }

    public var mac: Mac?
    public var rows: [Row]
    public var footer: String

    public static func make(accounts: [Account], ram: [String: Int64], disk: [String: AccountDisk], mac: MacMemory?,
                            terminal: ProcessMonitor.TerminalUse, physical: Int64 = MemoryPressure.physicalMemory) -> ResourceSummary {
        let physical = mac?.physical ?? physical
        let names = Dictionary(accounts.map { ($0.id, $0.identity.name) }, uniquingKeysWith: { first, _ in first })
        func share(_ bytes: Int64) -> String { "\(ByteFormat.percent(bytes, of: physical)) of this Mac" }
        func fraction(_ bytes: Int64) -> Double { physical > 0 ? min(1, max(0, Double(bytes) / Double(physical))) : 0 }

        var rows: [Row] = []
        var accountsRAM: Int64 = 0
        for account in accounts {
            let identity = account.identity
            let bytes = account.isRunning ? ram[account.id] ?? 0 : 0
            accountsRAM += bytes
            let disk = diskTexts(disk[account.id], names: names)
            let ramText: String?, detail: String, help: String?
            if !identity.surfaces.desktop {
                (ramText, detail, help) = (nil, "Claude Code only", "It has no Claude window: its sessions count in Claude Code in a terminal.")
            } else if !account.isRunning {
                (ramText, detail, help) = (nil, "Closed", nil)
            } else {
                (ramText, detail, help) = (ByteFormat.ram(bytes), share(bytes), "Claude and everything it runs: its windows, its Code tab and the tools it starts.")
            }
            let ramSpoken = ramText.map { "\($0) of RAM, \(detail)" } ?? (detail == "Closed" ? "closed" : detail)
            rows.append(Row(kind: .account(account.id), name: identity.name, tint: identity.tint, subtitle: nil, ram: ramText, ramDetail: detail,
                            ramHelp: help, fraction: fraction(bytes), disk: disk.text, diskIsFigure: disk.isFigure, diskHelp: disk.help,
                            accessibilityLabel: "\(identity.name), \(ramSpoken), \(disk.spoken)"))
        }
        if terminal.sessions > 0 {
            let sessions = terminal.sessions == 1 ? "1 session" : "\(terminal.sessions) sessions"
            let subtitle = "\(sessions), all accounts together"
            let name = "Claude Code in a terminal"
            rows.append(Row(kind: .terminal, name: name, tint: nil, subtitle: subtitle, ram: ByteFormat.ram(terminal.bytes),
                            ramDetail: share(terminal.bytes),
                            ramHelp: "Brainmerge can't tell which account a terminal session uses: that is only in its environment, which Brainmerge never reads.",
                            fraction: fraction(terminal.bytes), disk: nil, diskIsFigure: false, diskHelp: nil,
                            accessibilityLabel: "\(name), \(subtitle), \(ByteFormat.ram(terminal.bytes)) of RAM, \(share(terminal.bytes))"))
        }
        if let mac {
            // Footprints can add up to more than "used" (they count compressed pages at full size): never below zero.
            // Everything in use that is not Claude's, macOS's own wired and compressed memory included: named for what it
            // holds, so it never reads as more than the "Apps" of the Mac's line above it.
            let others = max(0, mac.used - accountsRAM - terminal.bytes)
            let name = "macOS and other apps"
            rows.append(Row(kind: .otherApps, name: name, tint: nil, subtitle: nil, ram: ByteFormat.ram(others), ramDetail: share(others),
                            ramHelp: "Everything else in use on this Mac: macOS itself (its wired and compressed memory) and the other apps, Brainmerge included. Claude's virtual machine, when it runs, counts here too.",
                            fraction: fraction(others), disk: nil, diskIsFigure: false, diskHelp: nil,
                            accessibilityLabel: "\(name), \(ByteFormat.ram(others)) of RAM, \(share(others))"))
        }

        let claudeRAM = accountsRAM + terminal.bytes
        var footer = claudeRAM > 0
            ? "Claude uses \(ByteFormat.ram(claudeRAM)) of RAM, \(share(claudeRAM))."
            : "No Claude window or terminal session is open, so Claude uses no RAM right now."
        let measured = accounts.compactMap { disk[$0.id] }.filter(\.isMeasured)
        if !measured.isEmpty {
            let total = measured.reduce(Int64(0)) { $0 + $1.total.bytes }
            let cut = measured.contains { !$0.total.complete }
            footer += " Your accounts take \(cut ? "more than " : "")\(ByteFormat.disk(total)) on disk."
        }
        return ResourceSummary(mac: mac.map(macLine), rows: rows, footer: footer)
    }

    static func macLine(_ mac: MacMemory) -> Mac {
        let percent = ByteFormat.percent(mac.used, of: mac.physical)
        let pressure: String? = switch mac.pressure {
        case .normal: nil
        case .warning: "Pressure: warning"
        case .critical: "Pressure: critical"
        }
        var breakdown = "Apps \(ByteFormat.ram(mac.appMemory)), wired \(ByteFormat.ram(mac.wired)), compressed \(ByteFormat.ram(mac.compressed))."
        if mac.swapUsed > 0 { breakdown += " Swap \(ByteFormat.ram(mac.swapUsed))." }
        let used = ByteFormat.ram(mac.used), capacity = ByteFormat.capacity(mac.physical)
        return Mac(used: used, detail: "of \(capacity) used · \(percent)", pressure: pressure, fraction: mac.usedFraction, breakdown: breakdown,
                   accessibilityLabel: "This Mac, \(used) of \(capacity) of RAM used, \(percent)" + (pressure.map { ", \($0.lowercased())" } ?? ""))
    }

    static let partNames: [AccountDisk.Part: String] = [.claude: "Claude", .claudeCode: "Claude Code", .app: "App"]

    /// The disk figure of one account, its parts for the tooltip, and the same figure as a spoken clause.
    static func diskTexts(_ disk: AccountDisk?, names: [String: String]) -> (text: String, isFigure: Bool, help: String?, spoken: String) {
        guard let disk else { return ("Measuring…", false, nil, "disk space being measured") }
        var parts: [String] = []
        for part in AccountDisk.Part.allCases {
            let name = partNames[part] ?? part.rawValue
            switch disk.parts[part] {
            case .measured(let size):
                var text = "\(name) \(size.complete ? "" : "more than ")\(ByteFormat.disk(size.bytes))"
                // A tinted copy: only its own blocks count, the rest is Claude's own, shared by the clone.
                if part == .app, size.sharedBytes > 0 { text += ", plus \(ByteFormat.disk(size.sharedBytes)) shared with Claude" }
                parts.append(text)
            case .countedWith(let owner): parts.append("\(name) counted with \(names[owner] ?? owner)")
            case .notMeasured: parts.append("\(name) not measured: it is in a folder macOS protects, like Documents.")
            case nil: break
            }
        }
        var notes: [String] = []
        let shared = AccountDisk.Folder.allCases.filter { disk.sharedWith[$0] != nil }
        if let owner = shared.first.flatMap({ disk.sharedWith[$0] }) {
            let folders = shared.map { $0 == .history ? "history" : "skills" }.joined(separator: " and ")
            notes.append("\(folders.prefix(1).uppercased() + folders.dropFirst()) counted with \(names[owner] ?? owner).")
        }
        let total = disk.total
        if !total.complete { notes.append("Brainmerge stopped counting early to stay fast.") }
        let help = ([parts.joined(separator: " · ")] + notes).filter { !$0.isEmpty }.joined(separator: "\n")
        let protectedOnly = !disk.isMeasured && disk.parts.values.contains(.notMeasured)
        if protectedOnly { return ("Not measured", false, help, "disk space not measured") }
        let figure = ByteFormat.disk(total.bytes)
        return total.complete ? (figure, true, help, "\(figure) on disk") : ("More than \(figure)", true, help, "more than \(figure) on disk")
    }
}
