import AppKit
import Foundation
import SwiftUI
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// What the edit sheet promises before a save: only a secondary's app is rebuilt, so only a secondary has to be closed.
@Suite struct EditAccountSheetTests {
    func account(_ name: String, primary: Bool = false, running: Bool) -> Account {
        Account(identity: Identity(slug: name.lowercased(), name: name, isPrimary: primary), isRunning: running)
    }

    @Test func theHeaderSaysWhetherTheAccountMustBeClosed() {
        #expect(EditAccountSheet.header(for: account("Ruben", primary: true, running: true)) == "Changes apply when you save. Claude stays open.")
        #expect(EditAccountSheet.header(for: account("Ruben", primary: true, running: false)) == "Changes apply when you save.")
        #expect(EditAccountSheet.header(for: account("Work", running: true)) == "Quit this account first: its app is rebuilt when you save.")
        #expect(EditAccountSheet.header(for: account("Work", running: false)) == "Changes apply when you save.")
    }

    @Test func thePrimarysAppSectionNamesTheAccountAndSaysClaudeIsNeverChanged() {
        let text = EditAccountSheet.ownAppText(name: "Ruben")
        #expect(text == "Ruben is the Claude app itself. Brainmerge never changes Claude, so while it runs the Dock shows Claude's icon. With this switch, Brainmerge adds an app with this color or photo that opens Ruben: keep it in the Dock in place of Claude.")
        #expect(EditAccountSheet.ownAppText(name: "Agency").hasPrefix("Agency is the Claude app itself."))
        #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
    }

    /// The primary's memory waits for Claude to quit: while it runs, the picker is off and says why, so the header's
    /// "Claude stays open" is never followed by a request to quit it.
    @Test func thePrimarysMemoryIsLockedWhileClaudeRuns() {
        let running = account("Ruben", primary: true, running: true)
        #expect(EditAccountSheet.memoryLocked(for: running))
        #expect(EditAccountSheet.memoryHint(for: running) == "Quit Claude to change Ruben's memory.")
        for other in [account("Ruben", primary: true, running: false), account("Work", running: true), account("Work", running: false)] {
            #expect(!EditAccountSheet.memoryLocked(for: other))
            #expect(EditAccountSheet.memoryHint(for: other) == "What this account wrote so far stays where it is; it goes on in the memory you pick.")
        }
    }

    @Test func theSwitchStartsFromTheSavedChoice() {
        var identity = Identity(slug: "ruben", name: "Ruben", isPrimary: true)
        #expect(!AccountEdit(account: Account(identity: identity, isRunning: false), memory: "shared").ownApp)
        identity.ownApp = true
        #expect(AccountEdit(account: Account(identity: identity, isRunning: false), memory: "shared").ownApp)
    }
}

/// The sheet's height with the owner's two hand-made copies: it must fit a laptop screen, its buttons included.
@MainActor @Suite struct EditAccountSheetLayoutTests {
    func model(_ e: ManagerEnv) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false)
        return AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
    }

    func height(_ sheet: EditAccountSheet) -> CGFloat {
        let host = NSHostingView(rootView: sheet)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// The owner's Agency: two hand-made copies of an older Claude open its folders.
    func ownersSetup(_ e: ManagerEnv) async throws -> (AppModel, [ExistingApp]) {
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let data = e.home.url.appending(path: "Library/Application Support/Claude-Second")
        let profile = e.home.url.appending(path: ".claude-second")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        _ = try CLIProfile.create(at: profile, inheritingFrom: nil)
        var request = IdentityManager.AddRequest(name: "Agency")
        request.adoptDesktopData = data; request.adoptCLIProfile = profile
        _ = try e.manager.add(request)
        let apps = e.home.url.appending(path: "Applications")
        try HandMadeApp.make("Claude Second", in: apps, script: HandMadeApp.ownersScript, version: "2.2553.13")
        try HandMadeApp.make("Claude Second (ancienne 1.49585)", in: apps, script: HandMadeApp.ownersScript, version: "1.49585.0")
        _ = try FakeClaudeApp.make(in: e.home.url, version: "2.9939.2")
        let m = model(e)
        m.reload()
        let found = await m.otherApps(opening: "agency")
        try #require(found.count == 2)
        return (m, found)
    }

    /// A 1440 by 900 laptop leaves about 800 points under the menu bar and the window's title bar: the sheet, its Save
    /// button included, stays within `maxHeight` whatever it lists, and the list never repeats the same sentences.
    @Test func theSheetFitsALaptopWithTheOwnersTwoCopies() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let (m, found) = try await ownersSetup(e)
        let agency = try #require(m.accounts.first { $0.id == "agency" })
        let ruben = try #require(m.accounts.first { $0.id == "ruben" })
        let bare = height(EditAccountSheet(model: m, isPresented: .constant(true), account: agency))
        let two = height(EditAccountSheet(model: m, isPresented: .constant(true), account: agency, otherApps: found))
        let primary = height(EditAccountSheet(model: m, isPresented: .constant(true), account: ruben, otherApps: found))
        #expect(two <= EditAccountSheet.maxHeight, "\(two)")
        #expect(primary <= EditAccountSheet.maxHeight, "\(primary)")
        #expect(bare <= two)
        #expect(EditAccountSheet.maxHeight <= 720)
    }
}
