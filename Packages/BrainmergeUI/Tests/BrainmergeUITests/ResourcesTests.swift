import Foundation
import Testing
import BrainmergeCore
@testable import BrainmergeUI

@Suite struct ByteFormatTests {
    static let mib: Int64 = 1 << 20
    static let gib: Int64 = 1 << 30

    /// Each test runs as is, then again with a French locale set explicitly, where C's "%.1f" prints "1,3".
    static let locales: [String?] = [nil, "fr_FR.UTF-8"]

    /// Sets the locale of this thread only (uselocale), so tests running meanwhile keep theirs, and checks it took.
    static func inLocale(_ name: String?, _ body: () -> Void) {
        guard let name else { body(); return }
        let mask = LC_COLLATE_MASK | LC_CTYPE_MASK | LC_MESSAGES_MASK | LC_MONETARY_MASK | LC_NUMERIC_MASK | LC_TIME_MASK
        guard let locale = newlocale(mask, name, nil) else { Issue.record("the \(name) locale is missing"); return }
        let previous = uselocale(locale)
        defer { uselocale(previous); freelocale(locale) }
        #expect(String(cString: localeconv().pointee.decimal_point) == ",", "the French locale must be in effect")
        body()
    }

    /// RAM in binary units, like Activity Monitor and About This Mac; a point for decimals whatever the Mac's language.
    @Test(arguments: locales) func ramReadsLikeActivityMonitor(locale: String?) {
        Self.inLocale(locale) {
            #expect(ByteFormat.ram(1_395_864_371) == "1.3 GB")
            #expect(ByteFormat.ram(0) == "0 GB")
            #expect(ByteFormat.ram(300 * 1024) == "< 1 MB")
            #expect(ByteFormat.ram(48 * Self.mib) == "48 MB")
            #expect(ByteFormat.ram(700 * Self.mib) == "700 MB")
            #expect(ByteFormat.ram(1023 * Self.mib + Self.mib * 9 / 10) == "1.0 GB")
            #expect(ByteFormat.ram(1_610_612_736) == "1.5 GB")
            #expect(ByteFormat.ram(2 * Self.gib) == "2.0 GB")
            #expect(ByteFormat.ram(1_300_000_000) == "1.2 GB")
        }
    }

    /// Disk in decimal units, like Finder.
    @Test(arguments: locales) func diskReadsLikeFinder(locale: String?) {
        Self.inLocale(locale) {
            #expect(ByteFormat.disk(1_300_000_000) == "1.3 GB")
            #expect(ByteFormat.disk(1_300_000_000_000) == "1.3 TB")
            #expect(ByteFormat.disk(0) == "0 GB")
            #expect(ByteFormat.disk(999) == "< 1 MB")
            #expect(ByteFormat.disk(1_300_000) == "1 MB")
            #expect(ByteFormat.disk(350_400_000) == "350 MB")
            #expect(ByteFormat.disk(999_700_000) == "1.0 GB")
            #expect(ByteFormat.disk(15_365_000_000) == "15.4 GB")
            #expect(ByteFormat.disk(999_960_000_000) == "1.0 TB")
            #expect(ByteFormat.disk(1_200_000_000_000) == "1.2 TB")
        }
    }

    @Test(arguments: locales) func capacityAndPercent(locale: String?) {
        Self.inLocale(locale) {
            #expect(ByteFormat.capacity(18 * Self.gib) == "18 GB")
            #expect(ByteFormat.capacity(8 * Self.gib) == "8 GB")
            #expect(ByteFormat.percent(2 * Self.gib, of: 18 * Self.gib) == "11%")
            #expect(ByteFormat.percent(1, of: 18 * Self.gib) == "< 1%")
            #expect(ByteFormat.percent(0, of: 18 * Self.gib) == "0%")
            #expect(ByteFormat.percent(Self.gib, of: 0) == "0%")
            #expect(ByteFormat.percent(18 * Self.gib - 1, of: 18 * Self.gib) == "100%")
        }
    }
}

@Suite struct ResourceSummaryTests {
    static let gib: Int64 = 1 << 30
    static let mib: Int64 = 1 << 20

    static func account(_ slug: String, _ name: String, primary: Bool = false, running: Bool, desktop: Bool = true, tint: Tint = .blue) -> Account {
        var identity = Identity(slug: slug, name: name, tint: tint, isPrimary: primary)
        identity.surfaces = Surfaces(desktop: desktop, cli: true)
        return Account(identity: identity, isRunning: running, hasSession: true)
    }

    /// 18 GB, 10 GB used: apps 6, wired 3, compressed 1 (pages of 16 KB, 65,536 per GB).
    static let mac = MacMemory(physical: 18 * gib, pageSize: 16_384,
                               pages: .init(internalPages: 6 * 65_536, purgeable: 0, external: 2 * 65_536, wired: 3 * 65_536, compressor: 65_536, free: 1000),
                               swapUsed: 3 * gib / 2, pressure: .warning)
    static let accounts = [account("ruben", "Ruben", primary: true, running: true, tint: .orange), account("client", "Client", running: true),
                           account("studio", "Studio", running: false), account("cli", "Terminal", running: false, desktop: false)]
    static func measured(_ bytes: Int64, complete: Bool = true, shared: Int64 = 0) -> AccountDisk.PartSize {
        .measured(DiskSize(bytes: bytes, complete: complete, sharedBytes: shared))
    }
    static let disk: [String: AccountDisk] = [
        "ruben": AccountDisk(slug: "ruben", parts: [.claude: measured(12_100_000_000), .claudeCode: measured(8_900_000_000)]),
        "client": AccountDisk(slug: "client", parts: [.claude: measured(15_000_000_000), .claudeCode: measured(18_000_000)],
                              sharedWith: [.history: "ruben", .skills: "ruben"]),
        "studio": AccountDisk(slug: "studio", parts: [.claude: measured(1_000_000_000, complete: false), .app: measured(350_000_000, shared: 600_000_000)]),
        "cli": AccountDisk(slug: "cli", parts: [.claudeCode: .notMeasured]),
    ]

    static func summary(ram: [String: Int64] = ["ruben": 2 * gib, "client": gib], disk: [String: AccountDisk] = disk, mac: MacMemory? = mac,
                        terminal: ProcessMonitor.TerminalUse = .init(sessions: 2, bytes: gib / 2)) -> ResourceSummary {
        ResourceSummary.make(accounts: accounts, ram: ram, disk: disk, mac: mac, terminal: terminal, physical: 18 * gib)
    }

    @Test func theMacLineCountsLikeActivityMonitor() throws {
        let mac = try #require(Self.summary().mac)
        #expect(mac.used == "10.0 GB")
        #expect(mac.detail == "of 18 GB used · 56%")
        #expect(abs(mac.fraction - 10.0 / 18) < 0.0001)
        #expect(mac.pressure == "Pressure: warning")
        #expect(mac.breakdown == "Apps 6.0 GB, wired 3.0 GB, compressed 1.0 GB. Swap 1.5 GB.")
        var calm = Self.mac
        calm = MacMemory(physical: calm.physical, pageSize: calm.pageSize, pages: calm.pages, swapUsed: 0, pressure: .normal)
        let quiet = try #require(Self.summary(mac: calm).mac)
        #expect(quiet.pressure == nil)
        #expect(quiet.breakdown == "Apps 6.0 GB, wired 3.0 GB, compressed 1.0 GB.")
        #expect(Self.summary(mac: nil).mac == nil)
    }

    /// Accounts in the sidebar's order, then Claude Code in a terminal, then everything else.
    @Test func rowsKeepTheAccountsOrderThenTheTerminalThenOtherApps() {
        let rows = Self.summary().rows
        #expect(rows.map(\.name) == ["Ruben", "Client", "Studio", "Terminal", "Claude Code in a terminal", "Other apps"])
        #expect(rows[0].ram == "2.0 GB" && rows[0].ramDetail == "11% of this Mac")
        #expect(abs(rows[0].fraction - 2.0 / 18) < 0.0001)
        #expect(rows[0].tint == .orange)
        // Closed: no RAM, the disk still shows. Claude Code only: it has no window to measure.
        #expect(rows[2].ram == nil && rows[2].ramDetail == "Closed" && rows[2].fraction == 0)
        #expect(rows[3].ram == nil && rows[3].ramDetail == "Claude Code only")
        let terminal = rows[4]
        #expect(terminal.kind == .terminal)
        #expect(terminal.subtitle == "2 sessions, all accounts together")
        #expect(terminal.ram == "512 MB" && terminal.ramDetail == "3% of this Mac")
        #expect(terminal.disk == nil)
        // 10 GB used minus 3 GB of accounts minus 0.5 GB of terminal.
        #expect(rows[5].ram == "6.5 GB" && rows[5].ramDetail == "36% of this Mac")
        // No session: no terminal row. No figure from the kernel: no "other apps", the accounts still show.
        #expect(!Self.summary(terminal: .init(sessions: 0, bytes: 0)).rows.contains { $0.kind == .terminal })
        let blind = Self.summary(mac: nil).rows
        #expect(!blind.contains { $0.kind == .otherApps })
        #expect(blind[0].ramDetail == "11% of this Mac")
    }

    /// Footprints count what the kernel attributes to each process and can add up to more than "used": other apps stop at zero.
    @Test func otherAppsNeverGoBelowZero() {
        let rows = Self.summary(ram: ["ruben": 9 * Self.gib, "client": 2 * Self.gib]).rows
        #expect(rows.last?.ram == "0 GB")
        #expect(rows.last?.fraction == 0)
    }

    @Test func diskTextsSayWhatWasCountedAndWhere() {
        let rows = Self.summary().rows
        #expect(rows[0].disk == "21.0 GB")
        #expect(rows[0].diskHelp == "Claude 12.1 GB · Claude Code 8.9 GB")
        #expect(rows[1].disk == "15.0 GB")
        #expect(rows[1].diskHelp == "Claude 15.0 GB · Claude Code 18 MB\nHistory and skills counted with Ruben.")
        // A walk cut short says "more than"; a tinted copy counts only its own blocks.
        #expect(rows[2].disk == "More than 1.4 GB")
        #expect(rows[2].diskHelp == "Claude more than 1.0 GB · App 350 MB, plus 600 MB shared with Claude\nBrainmerge stopped counting early to stay fast.")
        #expect(rows[3].disk == "Not measured")
        #expect(rows[3].diskHelp == "Claude Code not measured: it is in a folder macOS protects, like Documents.")
        // Not measured yet. States read fainter than figures.
        #expect(Self.summary(disk: [:]).rows[0].disk == "Measuring…")
        #expect(!Self.summary(disk: [:]).rows[0].diskIsFigure && !rows[3].diskIsFigure)
        #expect(rows[0].diskIsFigure && rows[2].diskIsFigure)
        let adopted = ["ruben": AccountDisk(slug: "ruben", parts: [.claudeCode: .countedWith("client")])]
        #expect(Self.summary(disk: adopted).rows[0].diskHelp == "Claude Code counted with Client")
    }

    @Test func rowsReadAsSentencesAndTheFooterAddsUp() {
        let summary = Self.summary()
        #expect(summary.rows[0].accessibilityLabel == "Ruben, 2.0 GB of RAM, 11% of this Mac, 21.0 GB on disk")
        #expect(summary.rows[2].accessibilityLabel == "Studio, closed, more than 1.4 GB on disk")
        #expect(Self.summary(disk: [:]).rows[1].accessibilityLabel == "Client, 1.0 GB of RAM, 6% of this Mac, disk space being measured")
        #expect(summary.rows[3].accessibilityLabel == "Terminal, Claude Code only, disk space not measured")
        #expect(summary.rows[4].accessibilityLabel == "Claude Code in a terminal, 2 sessions, all accounts together, 512 MB of RAM, 3% of this Mac")
        // 3.5 GB of 18 is 19%; 21.0 + 15.018 + 1.35 GB of disk, one walk cut short.
        #expect(summary.footer == "Claude uses 3.5 GB of RAM, 19% of this Mac. Your accounts take more than 37.4 GB on disk.")
        let idle = ResourceSummary.make(accounts: Self.accounts.map { var a = $0; a.isRunning = false; return a }, ram: [:], disk: [:],
                                        mac: Self.mac, terminal: .init(sessions: 0, bytes: 0), physical: 18 * Self.gib)
        #expect(idle.footer == "No Claude window or terminal session is open, so Claude uses no RAM right now.")
    }
}
