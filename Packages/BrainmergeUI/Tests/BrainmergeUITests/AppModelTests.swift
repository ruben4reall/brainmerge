import Foundation
import Observation
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct AppModelTests {
    /// Hermetic: no process of the real Mac and no real RAM figure, which move between two reloads.
    func model(_ e: ManagerEnv, monitor: ProcessMonitor? = nil) -> AppModel {
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false, monitor: monitor ?? ProcessMonitor(psOutput: { "" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        return model
    }

    @Test func aDamagedStateShowsItsOwnScreenNeverTheSetup() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        try Data("{ broken".utf8).write(to: e.home.paths.stateFile)
        let m = model(e)
        m.reload()
        #expect(m.stateProblem == .damaged)
        #expect(!m.needsOnboarding)
        #expect(StateProblem.damaged.detail == "The file is damaged. A copy from before your last change is available.")
        #expect(m.canRestorePreviousState)
        m.restorePreviousState()
        #expect(m.stateProblem == nil)
        #expect(m.accounts.map(\.identity.slug) == ["ruben"])
    }

    @Test func aStateFromANewerVersionSaysSo() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        try Data(#"{"schemaVersion": 3, "machineID": "m", "identities": [], "autoRebuild": true, "brainLanguage": "en"}"#.utf8)
            .write(to: e.home.paths.stateFile)
        let m = model(e)
        m.reload()
        #expect(m.stateProblem == .tooNew(3))
        #expect(!m.needsOnboarding)
        #expect(StateProblem.tooNew(3).detail == "It was written by a newer Brainmerge (version 3 of the file). Your accounts, memories and logins are untouched.")
        #expect(StateProblem.title == "Brainmerge can't read its list of accounts")
    }

    @Test func settingsAreSavedUnderTheStateLock() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.reload()
        let held = try e.store.lock()
        let task = m.setAutoRebuild(false)
        try await Task.sleep(for: .milliseconds(200))
        #expect(try e.store.load().autoRebuild == true)
        held.release()
        await task.value
        #expect(try e.store.load().autoRebuild == false)
    }

    @Test func choosingAnUnsignedClaudeIsRefusedAndNothingIsSaved() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.claudeLocator = ClaudeLocator(paths: e.home.paths, folders: [], launchServices: { [] }, isSigned: { _ in false })
        let refusal = await m.chooseClaude(e.claude.url)
        #expect(refusal?.detail == "This copy of Claude is not signed by Anthropic. Brainmerge only opens the official app.")
        #expect(try e.store.load().claudeAppPath == nil)
    }

    @Test func choosingASignedClaudeIsSavedForTheNextLaunch() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.claudeLocator = ClaudeLocator(paths: e.home.paths, folders: [], launchServices: { [] }, isSigned: { _ in true })
        #expect(await m.chooseClaude(e.claude.url) == nil)
        #expect(try e.store.load().claudeAppPath == e.claude.url.path)
    }

    @Test func withoutGitTheMemorySaysHistoryNeedsIt() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.git = GitAvailability(shell: Shell { _, _, _, _ in ShellResult(status: 2, stdout: "", stderr: "") }, isExecutable: { _ in false })
        #expect(!m.gitAvailable)
        #expect(AppModel.historyNeedsGit == "History needs git. Install Apple's tools")
    }

    @Test func listsAccountsWithRunningFlags() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let data = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        m.reload()
        #expect(m.accounts.map(\.identity.slug) == ["ruben", "client"])
        #expect(m.accounts.map(\.isRunning) == [false, true])
        #expect(m.claude?.version == "2.7032.0")
        #expect(m.brain?.root == e.brain.root)
        #expect(!m.needsOnboarding)
    }

    @Test func needsOnboardingWithoutBrainOrPrimary() throws {
        let e = try ManagerEnv.make(withBrain: false); defer { e.home.remove() }
        let m = model(e)
        m.reload()
        #expect(m.needsOnboarding)
    }

    @Test func removingARunningAccountShowsASentenceAndKeepsIt() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let data = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        m.reload()
        await m.remove("client", deleteData: true)
        #expect(m.message?.title == "Client is open")
        #expect(m.message?.action == .quit(slug: "client"))
        #expect(m.message?.actionLabel == "Quit Client")
        #expect(try e.store.load().identity(slug: "client") != nil)
    }

    @Test func accountsCarryTheirSessionState() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        // Client logged in: its data folder holds Claude's own storage. Ruben's folder has nothing yet.
        let data = client.desktopData(in: e.home.paths)
        try Data("x".utf8).write(to: data.appending(path: "Cookies"))
        try FileManager.default.createDirectory(at: data.appending(path: "IndexedDB/https_claude.ai_0.indexeddb.leveldb"), withIntermediateDirectories: true)
        let m = model(e)
        m.reload()
        #expect(m.accounts.first { $0.id == "client" }?.hasSession == true)
        #expect(m.accounts.first { $0.id == "client" }?.needsLogin == false)
        #expect(m.accounts.first { $0.id == "ruben" }?.hasSession == false)
        #expect(m.accounts.first { $0.id == "ruben" }?.needsLogin == true)
    }

    // MARK: Several memories

    @Test func memoriesAreListedAndSelectable() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let work = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        let m = model(e)
        m.reload()
        #expect(m.brains.map(\.id) == ["shared", "work"])
        #expect(m.brain?.root == e.brain.root)
        #expect(m.selectedBrain?.root == e.brain.root)
        #expect(m.selectedBrainID == "shared")
        m.selectBrain("work")
        #expect(m.selectedBrain?.root.path == work.path)
        #expect(m.memoryEvents.isEmpty && m.projectCount == 0)
        #expect(m.brainName(of: try e.store.load().identities[0]) == "Shared")
        // A memory that disappears from the list: the selection falls back to the default one.
        try e.manager.forgetBrain(id: "work")
        m.reload()
        #expect(m.selectedBrainID == "shared")
    }

    @Test func anAccountMovesToAnotherMemory() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        let work = await m.addBrain(name: "Work", path: nil)
        #expect(work?.id == "work")
        #expect(m.brains.count == 2)
        await m.setBrain(of: "client", to: "work")
        #expect(try e.store.load().identity(slug: "client")?.brain == "work")
        #expect(m.brainName(of: try e.store.load().identity(slug: "client")!) == "Work")
        await m.forgetBrain("work")
        #expect(m.message?.title == "This memory is still in use")
        #expect(m.brains.count == 2)
        m.message = nil
        await m.setBrain(of: "client", to: "shared")
        await m.forgetBrain("work")
        #expect(m.message == nil && m.brains.count == 1)
        #expect(FileManager.default.fileExists(atPath: work!.url.appending(path: "BRAIN.md").path))
    }

    @Test func uninstallPlansThenRemovesEverythingOfItsOwn() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        let plan = m.uninstallPlan()
        #expect(plan?.kept.contains { $0.contains(e.brain.root.path) } == true)
        #expect(await m.uninstall() != nil)
        #expect(!FileManager.default.fileExists(atPath: e.home.paths.stateFile.path))
        #expect(FileManager.default.fileExists(atPath: e.brain.brainMD.path))
    }

    // MARK: A real app per account, live updates

    @Test func anOutdatedTintedCopyIsFlaggedAndUpdatedOnDemand() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Client"); request.iconMode = .tintedClone
        _ = try e.manager.add(request)
        let m = model(e)
        m.reload()
        #expect(m.accounts.first { $0.id == "client" }?.claudeVersion == .current)
        #expect(m.outdatedAccounts.isEmpty)
        // Claude updates itself: the copy still carries the old version.
        _ = try FakeClaudeApp.make(in: e.home.url, version: "2.8000.0")
        m.reload()
        #expect(m.accounts.first { $0.id == "client" }?.claudeVersion == .outdated(installed: "2.8000.0", built: "2.7032.0"))
        #expect(m.outdatedAccounts.map(\.id) == ["client"])
        #expect(m.updateBanner?.contains("2.8000.0") == true)
        await m.updateAccount("client")
        #expect(try e.store.load().identity(slug: "client")?.builtForClaudeVersion == "2.8000.0")
        #expect(m.accounts.first { $0.id == "client" }?.claudeVersion == .current)
        #expect(m.updateBanner == nil)
    }

    @Test func launcherAccountsAreNeverOutdated() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        _ = try FakeClaudeApp.make(in: e.home.url, version: "2.8000.0")
        let m = model(e)
        m.reload()
        #expect(m.accounts.first { $0.id == "client" }?.claudeVersion == .notApplicable)
        #expect(m.accounts.first { $0.id == "ruben" }?.claudeVersion == .notApplicable)
        #expect(m.outdatedAccounts.isEmpty && m.updateBanner == nil)
    }

    @Test func editingAnAccountChangesEverythingAtOnce() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        let work = await m.addBrain(name: "Work", path: nil)
        var edit = AccountEdit(account: m.accounts.first { $0.id == "client" }!, memory: "shared")
        edit.name = "Studio"; edit.tint = .green; edit.note = "Design"; edit.distinctIcon = true; edit.memory = work!.id
        await m.apply(edit, to: "client")
        let identity = try e.store.load().identity(slug: "client")
        #expect(identity?.name == "Studio" && identity?.tint == .green && identity?.note == "Design")
        #expect(identity?.iconMode == .tintedClone && identity?.brain == "work")
        #expect(FileManager.default.fileExists(atPath: e.home.paths.tintedClone(name: "Studio").path))
        #expect(m.appURL(of: "client") == e.home.paths.tintedClone(name: "Studio"))
        // A photo, then a color again: the photo goes.
        let photo = try FakeIcon.orangePNG(in: e.home.url)
        var withPhoto = AccountEdit(account: m.accounts.first { $0.id == "client" }!, memory: "work"); withPhoto.logo = photo
        await m.apply(withPhoto, to: "client")
        #expect(try e.store.load().identity(slug: "client")?.logoPath == photo.path)
        var withColor = AccountEdit(account: m.accounts.first { $0.id == "client" }!, memory: "work"); withColor.logo = nil
        await m.apply(withColor, to: "client")
        #expect(try e.store.load().identity(slug: "client")?.logoPath == nil)
    }

    @Test func aCopyBeingUpdatedIsNotRebuiltTwice() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Client"); request.iconMode = .tintedClone
        _ = try e.manager.add(request)
        _ = try FakeClaudeApp.make(in: e.home.url, version: "2.8000.0")
        let m = model(e)
        m.reload()
        m.rebuilding.insert("client")   // an update of Client is under way
        await m.checkClaudeUpdate()
        #expect(try e.store.load().identity(slug: "client")?.builtForClaudeVersion == "2.7032.0")
        m.rebuilding.remove("client")
        await m.checkClaudeUpdate()
        #expect(try e.store.load().identity(slug: "client")?.builtForClaudeVersion == "2.8000.0")
    }

    @Test func memoryNamesComeFromTheLoadedState() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        try e.manager.setBrain(of: "ruben", to: "work")
        let m = model(e)
        m.reload()
        #expect(m.brainName(of: m.accounts[0].identity) == "Work")
        #expect(m.accounts(using: "work").map(\.id) == ["ruben"])
        // The state file is not consulted again: a change on disk shows only after the next reload.
        try e.manager.setBrain(of: "ruben", to: "shared")
        #expect(m.brainName(of: m.accounts[0].identity) == "Work")
        m.reload()
        #expect(m.brainName(of: m.accounts[0].identity) == "Shared")
    }


    @Test func errorsBecomeSentences() {
        #expect(AppModel.sentence(for: BrainmergeError.claudeAppNotFound("/Applications/Claude.app")).title == "Claude isn't installed")
        #expect(AppModel.sentence(for: BrainmergeError.claudeAppNotFound("/Applications/Claude.app")).action == .getClaude)
        #expect(AppModel.sentence(for: BrainmergeError.identityRunning("client")).action == .quit(slug: "client"))
        #expect(AppModel.sentence(for: BrainmergeError.brainNotConfigured).action == .openSettings)
        #expect(AppModel.sentence(for: BrainmergeError.identityNameTaken("Client")).detail == "There is already an account called Client. Pick another name.")
        #expect(AppModel.sentence(for: BrainmergeError.brainNotConfigured).title == "Choose where the memory lives first")
        #expect(AppModel.sentence(for: BrainmergeError.lockTimeout).title == "The memory is busy")
        #expect(AppModel.sentence(for: NSError(domain: "x", code: 1)).title == "Something went wrong")
    }

    @Test func openOnARunningAccountShowsItInsteadOfLaunchingAgain() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let data = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        m.reload()
        m.open("client")
        // No second launch on the same data folder: no opening aura, no message.
        #expect(m.opening.isEmpty)
        #expect(m.message == nil)
        #expect(m.lastShownProcess == 900)
    }

    @Test func addingAnAccountWhileAnotherIsOpenAsksToQuitFirst() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let exe = e.claude.executable.path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  800 1 90000 \(exe)\n" }))
        m.reload()
        var form = AddAccountForm(); form.name = "Work"
        #expect(await m.add(form))
        #expect(m.accounts.map(\.identity.slug).contains("work"))
        // The login link would open in the window that's already running: no launch, a sentence and a button.
        #expect(m.opening.isEmpty)
        #expect(m.message?.title == "Close your other Claude windows first")
        #expect(m.message?.action == .quitOthersThenOpen(slug: "work"))
        #expect(m.working == nil)
    }

    @Test func addingWithoutOpeningJustAdds() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        var form = AddAccountForm(); form.name = "Work"
        #expect(await m.add(form, open: false))
        #expect(m.accounts.map(\.identity.slug) == ["ruben", "work"])
        #expect(m.opening.isEmpty && m.message == nil)
    }

    @Test func reloadReportsWhetherSomethingChanged() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        #expect(m.reload())
        #expect(!m.reload())
    }

    @Test func logoImagesAreCachedAndDownscaled() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let png = try FakeIcon.orangePNG(in: e.home.url)
        let m = model(e)
        let identity = Identity(slug: "x", name: "X", logoPath: png.path)
        let first = try #require(m.logo(for: identity))
        let second = try #require(m.logo(for: identity))
        #expect(first === second)
        #expect(first.size.width <= 160 && first.size.height <= 160)
    }

    @Test func renamingToAnEmptyNameIsRefused() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        await m.rename("client", to: "   ")
        #expect(m.message?.title == "Check the form")
        #expect(try e.store.load().identity(slug: "client")?.name == "Client")
    }

    nonisolated static let mb: Int64 = 1024 * 1024
    /// 16 GB, 9 GB used (pages of 16 KB, 65,536 per GB).
    nonisolated static func mac(_ level: MemoryPressure.Level) -> MacMemory {
        MacMemory(physical: 16 << 30, pageSize: 16_384, pages: .init(internalPages: 5 * 65_536, purgeable: 0, external: 65_536,
                                                                     wired: 3 * 65_536, compressor: 65_536, free: 1000), swapUsed: 0, pressure: level)
    }

    /// The cards, the subtitle and the warning use one number per account: Activity Monitor's (the footprint of each
    /// process of its tree), the resident size where the kernel gave none.
    @Test func memoryPerAccountAndAWarningUnderPressure() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let data = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let helper = exe.replacingOccurrences(of: "MacOS/Claude", with: "Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper")
        let ps = "  800 1 50000 \(exe)\n  900 1 100000 \(exe) --user-data-dir=\(data)\n  901 900 400000 \(helper) --type=renderer\n"
            + "  950 1 3000 -zsh\n  951 950 70000 claude --resume\n"
        let footprints: [Int32: Int64] = [900: 300 * Self.mb, 901: 150 * Self.mb, 951: 90 * Self.mb]
        let m = model(e, monitor: ProcessMonitor(psOutput: { ps }, footprint: { footprints[$0] }))
        m.memoryPressure = { .warning }
        m.readMacMemory = { Self.mac($0) }
        m.reload()
        #expect(m.ramBytes(of: "client") == 450 * Self.mb)
        #expect(m.ramBytes(of: "ruben") == 50_000 * 1024)          // no footprint: its resident size
        #expect(m.totalRAMBytes == 450 * Self.mb + 50_000 * 1024)
        #expect(m.terminalUse == ProcessMonitor.TerminalUse(sessions: 1, bytes: 90 * Self.mb))
        #expect(m.macMemory == Self.mac(.warning))
        #expect(m.memoryWarning == "Your Mac is running low on RAM. 2 open accounts use 499 MB. Close the ones you don't use.")
        m.memoryPressure = { .normal }
        m.reload()
        #expect(m.memoryWarning == nil)
        #expect(m.macMemory?.pressure == .normal)
    }

    /// The first load, off the main thread, measures too: the first screen never shows resident sizes first.
    @Test func theFirstLoadMeasuresToo() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let exe = e.claude.executable.path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  800 1 50000 \(exe)\n" }, footprint: { $0 == 800 ? 70 * Self.mb : nil }))
        await m.launch(minimum: .zero)
        #expect(m.ramBytes(of: "ruben") == 70 * Self.mb)
    }

    /// Disk sizes are walked when the screen asks, at most every few minutes unless asked again; any change to the
    /// accounts makes the next ask walk again.
    @Test func refreshDiskIsThrottledAndForced() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        let walks = PSCounter()
        m.diskMeasure = { root, _ in walks.bump(); return root.part == .claudeCode ? DiskSize(bytes: 5_000_000, complete: true) : nil }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await m.refreshDisk(now: start)
        let perPass = walks.value
        #expect(perPass >= 2)
        #expect(m.disk["ruben"]?.bytes(.claudeCode) == 5_000_000)
        #expect(m.diskMeasuredAt == start)
        #expect(!m.diskMeasuring)
        await m.refreshDisk(now: start.addingTimeInterval(60))
        #expect(walks.value == perPass)
        await m.refreshDisk(force: true, now: start.addingTimeInterval(61))
        #expect(walks.value == 2 * perPass)
        await m.refreshDisk(now: start.addingTimeInterval(61 + 301))
        #expect(walks.value == 3 * perPass)
        var form = AddAccountForm(); form.name = "Work"
        #expect(await m.add(form, open: false))
        #expect(m.diskMeasuredAt == nil)
        await m.refreshDisk(now: start.addingTimeInterval(400))
        #expect(m.disk["work"] != nil)
    }

    /// An account added or removed outside the app (`brainmerge add` in a terminal) arrives through a reload: the next
    /// pass of the Usage screen, a few seconds later, walks again and measures it.
    @Test func anAccountAddedFromTheCommandLineIsMeasuredAtTheNextPass() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        m.diskMeasure = { _, _ in DiskSize(bytes: 1_000, complete: true) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await m.refreshDisk(now: start)
        #expect(m.diskMeasuredAt == start && m.disk["work"] == nil)
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        m.reload()
        #expect(m.diskMeasuredAt == nil)
        await m.refreshDisk(now: start.addingTimeInterval(5))
        #expect(m.disk["work"] != nil)
        // A reload that changes nothing keeps the measure.
        m.reload()
        #expect(m.diskMeasuredAt == start.addingTimeInterval(5))
    }

    /// Leaving the screen stops the walk: nothing half counted is kept, and the next visit walks again. Bounded: a walk
    /// that is never told to stop gives up after two minutes and fails the test instead of hanging it (wide bounds: the
    /// main actor is shared by the whole suite, so a step of this test can wait its turn for a long time).
    @Test(.timeLimit(.minutes(5))) func leavingTheScreenCancelsTheWalk() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        let started = PSCounter(), stopped = PSCounter()
        m.diskMeasure = { _, cancelled in
            started.bump()
            let deadline = Date().addingTimeInterval(120)
            while !cancelled(), Date() < deadline { usleep(1000) }
            if cancelled() { stopped.bump() }
            return DiskSize(bytes: 1, complete: false)
        }
        let visit = Task { await m.refreshDisk() }
        let deadline = Date().addingTimeInterval(120)
        while started.value == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(started.value > 0, "the walk never started")
        #expect(m.diskMeasuring)
        visit.cancel()
        await visit.value
        #expect(stopped.value > 0, "the walk was not told to stop")
        #expect(!m.diskMeasuring)
        #expect(m.disk.isEmpty)
        #expect(m.diskMeasuredAt == nil)
    }

    @Test func aFailedAutomaticRebuildIsReportedOncePerClaudeVersion() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Client"); request.iconMode = .tintedClone
        _ = try e.manager.add(request)
        // Stale tinted copy, and a rebuild doomed to fail: Claude's icon has disappeared.
        var state = try e.store.load()
        state.identities = state.identities.map { var i = $0; if i.slug == "client" { i.builtForClaudeVersion = "1.0.0" }; return i }
        try e.store.save(state)
        try FileManager.default.removeItem(at: e.claude.icon)
        let m = model(e)
        m.reload()
        await m.checkClaudeUpdate()
        #expect(m.message != nil)
        m.message = nil
        await m.checkClaudeUpdate()
        #expect(m.message == nil)
    }

    @Test func memoryJitterDoesNotCountAsAChange() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let exe = e.claude.executable.path
        let counter = PSCounter()
        let m = model(e, monitor: ProcessMonitor(psOutput: { counter.bump(); return "  800 1 \(600_000 + counter.value * 37) \(exe)\n" }))
        #expect(m.reload())
        #expect(!m.reload())       // a few more KB on every ps: not a change for the interface
    }

    @Test func openMarksTheCardAsOpening() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        m.markOpening("ruben")
        #expect(m.opening == ["ruben"])
    }

    // MARK: The sidebar's labels

    @Test func severalAccountsCanBeOpeningAtOnceAndEachClearsWhenItsWindowRuns() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let data = client.desktopData(in: e.home.paths).path
        let exe = e.claude.executable.path
        let ps = PSOutput()
        let m = model(e, monitor: ProcessMonitor(psOutput: { ps.text }))
        m.reload()
        // Opening Ruben then Client: Ruben does not turn back to "Open" while its window is still on its way.
        m.markOpening("ruben")
        m.markOpening("client")
        #expect(m.opening == ["ruben", "client"])
        // Client's window appears: it is no longer "opening", without waiting for the timer.
        ps.text = "  900 1 120000 \(exe) --user-data-dir=\(data)\n"
        m.reload()
        #expect(m.opening == ["ruben"])
        ps.text = "  800 1 90000 \(exe)\n  900 1 120000 \(exe) --user-data-dir=\(data)\n"
        m.reload()
        #expect(m.opening.isEmpty)
    }

    @Test func openingAClaudeCodeOnlyAccountExplainsInsteadOfFailing() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        var request = IdentityManager.AddRequest(name: "Terminal"); request.surfaces = Surfaces(desktop: false)
        _ = try e.manager.add(request)
        // Claude is removed, so that nothing here could ever reach /usr/bin/open: without the check,
        // the click would end in "Claude isn't installed" instead of saying what this account is.
        try FileManager.default.removeItem(at: e.claude.url)
        let m = model(e)
        m.reload()
        m.open("terminal")
        #expect(m.message?.title == "Terminal is Claude Code only")
        #expect(m.message?.detail == "This account has no Claude window. Use it with Claude Code in the terminal.")
        #expect(m.message?.action == nil)
        #expect(m.opening.isEmpty)
    }

    @Test func aRebuildMarksOnlyItsAccountBusyAndLeavesNoneBusy() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        let task = Task { _ = await m.rebuild("client") }
        for _ in 0..<1000 where m.working == nil { await Task.yield() }
        #expect(m.working != nil)
        #expect(m.busy == ["client"])
        #expect(m.accountsBusy == ["client"])
        await task.value
        #expect(m.busy.isEmpty && m.accountsBusy.isEmpty)
        #expect(m.message == nil)
    }

    @Test func attachingAnotherMemoryDoesNotMarkTheAccountBusy() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        m.reload()
        _ = await m.addBrain(name: "Work", path: nil)
        // The app bundle is not touched: opening it stays possible.
        let task = Task { _ = await m.setBrain(of: "client", to: "work") }
        for _ in 0..<1000 where m.working == nil { await Task.yield() }
        #expect(m.working != nil)
        #expect(m.busy.isEmpty)
        await task.value
        #expect(try e.store.load().identity(slug: "client")?.brain == "work")
    }

    @Test func editingThePrimaryNeverMarksItBusy() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        // Opening the primary opens Claude itself, which no edit touches: its row keeps saying "Open".
        let task = Task { await m.changeNote("ruben", to: "Personal") }
        for _ in 0..<1000 where m.working == nil { await Task.yield() }
        #expect(m.working != nil)
        #expect(m.busy.isEmpty)
        await task.value
        #expect(try e.store.load().identity(slug: "ruben")?.note == "Personal")
    }

    // MARK: The primary while Claude runs

    /// The real Claude's command line, with no --user-data-dir: the primary account is open.
    func withClaudeOpen(_ e: ManagerEnv) -> AppModel {
        let exe = e.claude.executable.path
        return model(e, monitor: ProcessMonitor(psOutput: { "  800 1 90000 \(exe)\n" }))
    }

    @Test func editingThePrimaryWhileOpenSavesWithoutAskingToQuit() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = withClaudeOpen(e)
        m.reload()
        let ruben = try #require(m.accounts.first { $0.id == "ruben" })
        #expect(ruben.isRunning)
        var edit = AccountEdit(account: ruben, memory: "shared")
        #expect(!edit.ownApp)
        edit.name = "Ruben C"; edit.tint = .green; edit.note = "Personal"; edit.ownApp = true
        await m.apply(edit, to: "ruben")
        #expect(m.message == nil)
        let saved = try #require(try e.store.load().primary)
        #expect(saved.name == "Ruben C" && saved.tint == .green && saved.note == "Personal" && saved.ownApp == true)
        #expect(m.appURL(of: "ruben") == e.home.paths.launcherApp(name: "Ruben C"))
        #expect(m.accounts.first { $0.id == "ruben" }?.isRunning == true)
        #expect(m.busy.isEmpty)
        // Its own app can be rebuilt with Claude open too, and switched off again.
        try FileManager.default.removeItem(at: e.home.paths.launcherApp(name: "Ruben C"))
        await m.rebuild("ruben")
        #expect(m.message == nil && m.appURL(of: "ruben") != nil)
        var off = AccountEdit(account: try #require(m.accounts.first { $0.id == "ruben" }), memory: "shared")
        #expect(off.ownApp)
        off.ownApp = false
        await m.apply(off, to: "ruben")
        #expect(m.message == nil && m.appURL(of: "ruben") == nil)
    }

    /// Moving the memory links is not atomic: that one change still waits for Claude to quit, and it is said before
    /// anything is saved, so an edit is never half applied.
    @Test func thePrimarysMemoryStillWaitsForClaudeToQuit() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        let m = withClaudeOpen(e)
        m.reload()
        var edit = AccountEdit(account: try #require(m.accounts.first { $0.id == "ruben" }), memory: "work")
        edit.note = "Personal"; edit.name = "Ruben C"
        let failure = await m.apply(edit, to: "ruben")
        #expect(failure?.title == "Ruben is open")
        #expect(m.message == failure)
        #expect(try e.store.load().primary?.note == nil)
        #expect(try e.store.load().primary?.name == "Ruben")
        #expect(try e.store.load().primary?.brain == nil)
    }

    /// A secondary's app is rebuilt when it is saved: it still has to be closed first.
    @Test func editingAnOpenSecondaryStillAsksToQuitIt() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let client = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let exe = e.claude.executable.path, data = client.desktopData(in: e.home.paths).path
        let m = model(e, monitor: ProcessMonitor(psOutput: { "  900 1 120000 \(exe) --user-data-dir=\(data)\n" }))
        m.reload()
        var edit = AccountEdit(account: try #require(m.accounts.first { $0.id == "client" }), memory: "shared")
        edit.note = "Work"
        edit.ownApp = true   // the primary's switch: ignored for a secondary
        await m.apply(edit, to: "client")
        #expect(m.message?.title == "Client is open")
        #expect(try e.store.load().identity(slug: "client")?.note == nil)
        #expect(try e.store.load().identity(slug: "client")?.ownApp == nil)
    }

    @Test func theSidebarSeesAnUpdateUnderWayAsBusy() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        m.reload()
        m.rebuilding.insert("client")   // updateAccount or the automatic check at work
        #expect(m.accountsBusy == ["client"])
        #expect(m.busy.isEmpty)          // two sets: the update's marker is never cleared by a nested change
    }

    // MARK: Apps the person made

    /// The owner's "Claude Second" copies open Agency's adopted folders: the edit sheet of Agency lists
    /// both, the primary's lists none, and the copies are left exactly as they were.
    @Test func appsMadeByHandAreFoundForTheAccountTheyOpen() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let data = e.home.url.appending(path: "Library/Application Support/Claude-Second")
        let profile = e.home.url.appending(path: ".claude-second")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        _ = try CLIProfile.create(at: profile, inheritingFrom: nil)
        var request = IdentityManager.AddRequest(name: "Agency")
        request.adoptDesktopData = data; request.adoptCLIProfile = profile
        _ = try e.manager.add(request)
        let apps = e.home.url.appending(path: "Applications")
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let copy = try HandMadeApp.make("Claude Second", in: apps, script: HandMadeApp.ownersScript, version: "2.2553.13")
        try HandMadeApp.make("Claude Second (ancienne 1.49585)", in: apps, script: HandMadeApp.ownersScript, version: "1.49585.0")
        let m = model(e)
        m.reload()

        let found = await m.otherApps(opening: "agency")
        #expect(found.map(\.name) == ["Claude Second", "Claude Second (ancienne 1.49585)"])
        #expect(found.first?.url.path == copy.path)
        #expect(await m.otherApps(opening: "ruben").isEmpty)
        #expect(await m.otherApps(opening: "nobody").isEmpty)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(m.message == nil)
    }

    // MARK: The launch splash

    @Test func capturesAndDemosSkipTheSplash() {
        for key in ["BRAINMERGE_CAPTURE", "BRAINMERGE_SCREEN", "BRAINMERGE_ONBOARDING_STEP"] {
            #expect(AppModel.skipsSplash(environment: [key: "1"]), "\(key)")
        }
        #expect(!AppModel.skipsSplash(environment: [:]))
        #expect(!AppModel.skipsSplash(environment: ["BRAINMERGE_HOME": "/tmp/demo"]))
        #expect(!AppModel.skipsSplash(environment: ["BRAINMERGE_MEMORY_PRESSURE": "warning"]))
    }

    @Test func theSplashHoldsOnlyWhatRemainsOfTheMinimum() {
        let minimum = Duration.milliseconds(480)
        #expect(AppModel.splashHold(loaded: .milliseconds(70), minimum: minimum) == .milliseconds(410))
        #expect(AppModel.splashHold(loaded: .milliseconds(480), minimum: minimum) == .zero)
        #expect(AppModel.splashHold(loaded: .seconds(2), minimum: minimum) == .zero)
        #expect(AppModel.splashHold(loaded: .zero, minimum: .zero) == .zero)
    }

    @Test func theFirstLoadRunsBehindTheSplashThenTheWindowIsReady() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let m = model(e)
        #expect(m.launchPhase == .loading)
        #expect(m.accounts.isEmpty)
        var seenBeforeReady: (LaunchPhase, [String])?
        await m.launch(minimum: .zero) { seenBeforeReady = (m.launchPhase, m.accounts.map(\.id)) }
        #expect(m.launchPhase == .ready)
        #expect(m.accounts.map(\.identity.slug) == ["ruben", "client"])
        // The work before the first screen sees the loaded accounts, while the splash is still up.
        #expect(seenBeforeReady?.0 == .loading)
        #expect(seenBeforeReady?.1 == ["ruben", "client"])
        // Loaded like any reload: the memory's history too.
        let reference = model(e)
        reference.reload()
        #expect(m.brain?.root == reference.brain?.root)
        #expect(m.lastMemorySave == reference.lastMemorySave && m.memoryCounts == reference.memoryCounts)
    }

    @Test func theSplashStaysAtLeastTheMinimum() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = model(e)
        let clock = ContinuousClock()
        let start = clock.now
        await m.launch(minimum: .milliseconds(300))
        #expect(start.duration(to: clock.now) >= .milliseconds(300))
        #expect(m.launchPhase == .ready)
    }

    @Test func theFirstLoadListsProcessesOffTheMainThread() async throws {
        // The splash keeps walking while `ps` runs: only the main thread draws it.
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let threads = MainThreadLog()
        let m = model(e, monitor: ProcessMonitor(psOutput: { threads.record(); return "" }))
        await m.launch(minimum: .zero)
        #expect(threads.onMain == [false])
    }

    @Test func theLaunchRunsOnceEvenWhenTwoWindowsAsk() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let ps = PSCounter()
        let m = model(e, monitor: ProcessMonitor(psOutput: { ps.bump(); return "" }))
        let first = Tally(), second = Tally(), late = Tally()
        async let a: Void = m.launch(minimum: .milliseconds(50)) { first.count += 1 }
        async let b: Void = m.launch(minimum: .milliseconds(50)) { second.count += 1 }
        _ = await (a, b)
        // One load for both windows, and each window's work before the first screen ran once.
        #expect(ps.value == 1)
        #expect(first.count == 1 && second.count == 1)
        // Once ready, asking again changes nothing.
        await m.launch(minimum: .zero) { late.count += 1 }
        #expect(late.count == 0)
        #expect(ps.value == 1)
        #expect(m.launchPhase == .ready)
    }

    @Test func watchingStartsOnceWhoeverAsks() async throws {
        // The launch and the onboarding switch can both ask right after the splash: one Claude check, not two.
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let ps = PSCounter()
        let m = model(e, monitor: ProcessMonitor(psOutput: { ps.bump(); return "" }))
        m.startWatching()
        m.startWatching()
        #expect(m.isWatching)
        m.stopWatching()   // no clock ticks from here: only the Claude checks the starts queued are left to run
        #expect(!m.isWatching)
        var waited = 0
        while ps.value == 0, waited < 500 { try await Task.sleep(for: .milliseconds(20)); waited += 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(ps.value == 1)
    }

    // MARK: The menu bar

    /// A model past the splash, with no capture or demo variable: the icon's own rules decide.
    func readyModel(_ e: ManagerEnv, monitor: ProcessMonitor? = nil) async -> AppModel {
        let m = model(e, monitor: monitor)
        m.environment = [:]
        await m.launch(minimum: .zero)
        return m
    }

    /// The graph shows a vault picked from Obsidian's list, remembers it, and goes back to the memory when asked or
    /// when the vault's folder is gone. A folder Obsidian never opened is not offered as a vault.
    @Test func theGraphShowsAChosenVaultAndRemembersIt() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.reload()
        #expect(m.graphTarget == GraphTarget(root: e.brain.root, style: .memory))
        #expect(m.graphSource == .memory("shared"))
        let vault = e.home.url.appending(path: "Notes Vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault.appending(path: ".obsidian"), withIntermediateDirectories: true)
        let list = e.home.paths.obsidianVaultList
        try FileManager.default.createDirectory(at: list.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"vaults": {"a": {"path": "\#(vault.path)"}}}"#.utf8).write(to: list)
        await m.refreshVaults()
        #expect(m.obsidianVaults.map(\.path) == [vault.standardizedFileURL.path])
        await m.selectGraphSource(.vault(vault.path)).value
        #expect(m.graphTarget == GraphTarget(root: URL(fileURLWithPath: vault.path, isDirectory: true), style: .vault))
        #expect(m.graphSource == .vault(vault.path))
        #expect(try e.store.load().graphVault == vault.path)
        let fresh = model(e)
        fresh.reload()
        #expect(fresh.graphTarget.style == .vault)
        // Back to the memory.
        await m.selectGraphSource(.memory("shared")).value
        #expect(m.graphTarget.style == .memory && m.graphVault == nil)
        #expect(try e.store.load().graphVault == nil)
        // A folder picked by hand must be a vault; a plain one is explained, not shown.
        let plain = e.home.url.appending(path: "Plain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        await m.chooseVault(plain).value
        #expect(m.message?.title == "Not an Obsidian vault")
        #expect(m.graphTarget.style == .memory && m.graphVault == nil)
        await m.chooseVault(vault).value
        #expect(m.graphTarget.style == .vault)
        // The vault's folder goes away. The disk is not looked at on every redraw: the next time the screen opens, the
        // memory shows, and the choice waits for the folder to come back.
        try FileManager.default.removeItem(at: vault)
        #expect(m.graphTarget.style == .vault)
        await m.refreshVaults()
        #expect(m.graphTarget == GraphTarget(root: e.brain.root, style: .memory))
        #expect(m.graphVault == vault.path)
        try FileManager.default.createDirectory(at: vault.appending(path: ".obsidian"), withIntermediateDirectories: true)
        await m.refreshVaults()
        #expect(m.graphTarget.style == .vault)
    }

    /// Looking at a vault's folder can make macOS ask for consent and wait for the answer: it never runs on the main
    /// thread, whether the graph shows, a listed vault is picked or a folder is chosen.
    @Test func vaultFoldersAreLookedAtOffTheMainThread() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.reload()
        let vault = e.home.url.appending(path: "Notes Vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault.appending(path: ".obsidian"), withIntermediateDirectories: true)
        let log = MainThreadLog()
        m.isVaultGone = { log.record(); return ObsidianVaults.isGone($0) }
        m.isVaultFolder = { log.record(); return ObsidianVaults.isVault($0) }
        await m.chooseVault(vault).value
        await m.selectGraphSource(.vault(vault.path)).value
        await m.refreshVaults()
        #expect(m.graphTarget.style == .vault)
        #expect(log.onMain.count == 3)
        #expect(!log.onMain.contains(true))
    }

    /// A vault picked, then a memory picked before the vault's folder was looked at: the later choice wins.
    @Test func theLastPickWinsWhileAVaultIsLookedAt() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.reload()
        let vault = e.home.url.appending(path: "Notes Vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault.appending(path: ".obsidian"), withIntermediateDirectories: true)
        m.isVaultGone = { Thread.sleep(forTimeInterval: 0.2); return ObsidianVaults.isGone($0) }
        let slow = m.selectGraphSource(.vault(vault.path))
        await m.selectGraphSource(.memory("shared")).value
        await slow.value
        #expect(m.graphVault == nil && m.graphTarget.style == .memory)
        #expect(try e.store.load().graphVault == nil)
    }

    /// The memory picked in the graph's source menu is remembered like a vault: the next launch shows it again. A memory
    /// forgotten since gives way to the default one.
    @Test func theMemoryPickedForTheGraphIsRemembered() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.addBrain(name: "Work", path: nil, language: .en)
        let m = model(e)
        m.reload()
        #expect(m.graphSource == .memory("shared"))
        await m.selectGraphSource(.memory("work")).value
        #expect(m.graphSource == .memory("work"))
        #expect(try e.store.load().graphMemory == "work")
        let fresh = model(e)
        fresh.reload()
        #expect(fresh.selectedBrainID == "work" && fresh.graphSource == .memory("work"))
        try e.manager.forgetBrain(id: "work")
        let later = model(e)
        later.reload()
        #expect(later.selectedBrainID == "shared" && later.graphSource == .memory("shared"))
    }

    /// Obsidian may list a vault whose folder is gone (it is listed unlooked at when macOS guards its place): picking it
    /// says so and keeps the graph as it was.
    @Test func pickingAVaultThatIsGoneSaysSo() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.reload()
        let gone = e.home.url.appending(path: "Documents/Old Vault", directoryHint: .isDirectory).path
        await m.selectGraphSource(.vault(gone)).value
        #expect(m.message?.title == "Vault not found")
        #expect(m.graphVault == nil && m.graphTarget.style == .memory)
        #expect(try e.store.load().graphVault == nil)
    }

    @Test func menuBarSettingPersists() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        #expect(m.menuBarIcon && m.showsMenuBarIcon)
        await m.setMenuBarIcon(false).value
        #expect(!m.menuBarIcon && !m.showsMenuBarIcon)
        #expect(try e.store.load().menuBarIcon == false)
        let fresh = model(e)
        fresh.reload()
        #expect(!fresh.menuBarIcon)
        // The guided setup on screen, a capture, or no memory yet: no icon, whatever the setting.
        await m.setMenuBarIcon(true).value
        #expect(m.showsMenuBarIcon)
        m.setupGuideShown = true
        #expect(!m.showsMenuBarIcon)
        m.setupGuideShown = false
        m.environment = ["BRAINMERGE_CAPTURE": "1"]
        #expect(!m.showsMenuBarIcon)
        let bare = try ManagerEnv.make(withBrain: false); defer { bare.home.remove() }
        let b = await readyModel(bare)
        #expect(b.menuBarIcon && !b.showsMenuBarIcon)
    }

    /// The switch is saved after any work already on the core queue (a rebuild saves the state too), and a reload in
    /// between does not flip it back.
    @Test func theSwitchHoldsWhileItsSaveWaitsForTheCoreQueue() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        let slow = Task { _ = await m.outcome("Rebuilding Work…") { Thread.sleep(forTimeInterval: 0.3) } }
        while m.working == nil { await Task.yield() }
        let save = m.setMenuBarIcon(false)
        m.reload()
        #expect(!m.menuBarIcon)
        #expect(try e.store.load().menuBarIcon == true)
        await save.value
        await slow.value
        m.reload()
        #expect(!m.menuBarIcon)
        #expect(try e.store.load().menuBarIcon == false)
    }

    /// The scenes read whether the icon shows: an account opening or closing must not draw them again (that would
    /// rebuild the window's root view on every clock tick), only a change of the answer.
    @Test func theIconAnswerChangesOnlyWithItself() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let exe = e.claude.url.appending(path: "Contents/MacOS/Claude").path
        let ps = PSOutput()
        let m = await readyModel(e, monitor: ProcessMonitor(psOutput: { ps.text }))
        let touched = Tally()
        func watch() {
            withObservationTracking { _ = m.showsMenuBarIcon; _ = m.setupDone } onChange: { MainActor.assumeIsolated { touched.count += 1 } }
        }
        watch()
        ps.text = "  800 1 90000 \(exe)\n"
        m.reload()
        #expect(m.openAccounts.count == 1)
        #expect(touched.count == 0)
        m.setupGuideShown = true
        #expect(touched.count == 1)
        #expect(!m.showsMenuBarIcon && !m.setupDone)
    }

    /// With the icon, closing the window keeps the clocks the menu needs; without it, nothing runs.
    @Test func closingTheWindowKeepsTheClocksWithTheIcon() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        defer { m.stopWatching() }
        m.windowAppeared()
        #expect(m.watchedClocks == Set(Watchers.Clock.allCases))
        m.windowDisappeared()
        #expect(m.watchedClocks == [.instances, .projects, .claude])
        await m.setMenuBarIcon(false).value
        #expect(!m.isWatching)
        m.windowAppeared()
        #expect(m.watchedClocks == Set(Watchers.Clock.allCases))
        m.windowDisappeared()
        #expect(!m.isWatching)
        // The guide on screen stops the background clocks too, and a state that needs the setup again stops them all.
        await m.setMenuBarIcon(true).value
        #expect(m.isWatching)
        m.setupGuideShown = true
        #expect(!m.isWatching)
        m.setupGuideShown = false
        #expect(m.isWatching)
        var state = try e.store.load()
        state.identities = []
        try e.store.save(state)
        m.reload()
        #expect(m.needsOnboarding && !m.isWatching)
    }

    /// With the window closed and the icon shown, the minute clock keeps new projects and emails current but reads no
    /// transcripts: the usage is only on screen. It reads them again once the window is back.
    @Test func theMinuteClockReadsNoUsageWithTheWindowClosed() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        defer { m.stopWatching() }
        m.windowAppeared()
        m.windowDisappeared()
        #expect(m.watchedClocks.contains(.projects))
        await m.onProjectsTick()?.value
        #expect(m.usageUpdatedAt == nil)
        m.windowAppeared()
        await m.onProjectsTick()?.value
        #expect(m.usageUpdatedAt != nil)
    }

    /// Dragging the icon out of the menu bar turns the switch off. With the window closed, Brainmerge would be left
    /// running with no window and no icon: the window opens again. SwiftUI echoing a removal after the app hid the icon
    /// itself (the guide, a capture) changes nothing.
    @Test func draggingTheIconOutWithNoWindowReopensIt() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        defer { m.stopWatching() }
        m.windowAppeared()
        #expect(m.menuBarIconRemoved() == false)
        #expect(!m.menuBarIcon && !m.showsMenuBarIcon)
        await m.setMenuBarIcon(true).value
        m.windowDisappeared()
        #expect(m.menuBarIconRemoved() == true)
        #expect(!m.menuBarIcon && !m.showsMenuBarIcon)
        await m.setMenuBarIcon(true).value
        #expect(try e.store.load().menuBarIcon == true)
        m.setupGuideShown = true
        #expect(m.menuBarIconRemoved() == false)
        #expect(m.menuBarIcon)
    }

    /// A setting changed while core work runs is saved after it on the core queue: the work saving the state it read
    /// before (a rebuild records its Claude version) never undoes it, and a reload meanwhile does not flip it back.
    @Test func settingsChangedDuringCoreWorkAreKept() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        let store = e.store
        let slow = Task {
            _ = await m.outcome("Rebuilding Work…") {
                let state = try store.load()
                Thread.sleep(forTimeInterval: 0.3)
                try store.save(state)
            }
        }
        while m.working == nil { await Task.yield() }
        m.setAutoRebuild(false)
        m.setNotesApp("md.obsidian")
        m.setLanguage(.fr)
        m.reload()
        #expect(!m.autoRebuild && m.notesApp == "md.obsidian" && m.language == .fr)
        await slow.value
        _ = await m.outcome("Checking…") {}   // after every save already queued
        let state = try e.store.load()
        #expect(!state.autoRebuild && state.notesApp == "md.obsidian" && state.brainLanguage == .fr)
        m.reload()
        #expect(!m.autoRebuild && m.notesApp == "md.obsidian" && m.language == .fr)
    }

    /// Before any window appeared (tests, the first load), nothing starts the clocks on its own.
    @Test func noClockStartsBeforeTheWindowIsTracked() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        m.updateWatching()
        await m.setMenuBarIcon(false).value
        await m.setMenuBarIcon(true).value
        m.reload()
        #expect(!m.isWatching)
        // During the splash, the window appearing starts nothing either: the launch asks once it is done.
        let splash = model(e)
        splash.environment = [:]
        splash.windowAppeared()
        #expect(!splash.isWatching)
    }

    /// An uninstall keeps every clock stopped, whatever the window does meanwhile: a Claude check would rebuild a copy.
    @Test func anUninstallKeepsTheClocksStopped() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        let m = await readyModel(e)
        defer { m.stopWatching() }
        m.windowAppeared()
        #expect(m.isWatching)
        let uninstall = Task { await m.uninstall() }
        while m.working == nil { await Task.yield() }
        // The window closes and opens again while the removal runs: nothing starts.
        m.windowDisappeared()
        m.windowAppeared()
        #expect(!m.isWatching)
        #expect(await uninstall.value != nil)
        m.windowAppeared()
        #expect(!m.isWatching)
    }

    /// Quit waits for the work on an account's app, for a bounded time.
    @Test func quitWaitsForWorkInProgress() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        #expect(await m.waitForWork(limit: .seconds(1)))
        let work = Task { _ = await m.outcome("Rebuilding Work…") { Thread.sleep(forTimeInterval: 0.3) } }
        while m.working == nil { await Task.yield() }
        #expect(await m.waitForWork(limit: .milliseconds(20)) == false)
        #expect(await m.waitForWork(limit: .seconds(5)))
        #expect(m.working == nil)
        await work.value
    }

    /// The menu's accounts use every account whose app is being worked on: the automatic update marks only `rebuilding`.
    @Test func menuEntriesUseEveryBusyAccount() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Work"))
        let m = model(e)
        m.reload()
        #expect(m.menuEntries.map(\.title) == ["Open Ruben", "Open Work"])
        m.rebuilding.insert("work")
        #expect(m.menuEntries.map(\.title) == ["Open Ruben", "Updating Work…"])
        #expect(m.menuEntries.map(\.isEnabled) == [true, false])
    }

    /// Closing and reopening the window is routine with the icon: the move to Applications is offered once per process.
    @Test func theMoveIsOfferedOncePerProcess() throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        let m = model(e)
        m.offersMove = { true }
        m.offerMoveIfNeeded()
        #expect(m.message?.action == .moveToApplications)
        m.message = nil
        m.offerMoveIfNeeded()
        #expect(m.message == nil)
        let declined = model(e)
        declined.offersMove = { false }
        declined.offerMoveIfNeeded()
        #expect(declined.message == nil)
    }
}

/// Whether each `ps` ran on the main thread.
final class MainThreadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    func record() { let main = Thread.isMainThread; lock.lock(); calls.append(main); lock.unlock() }
    var onMain: [Bool] { lock.lock(); defer { lock.unlock() }; return calls }
}

@MainActor final class Tally { var count = 0 }

/// A `ps` output a test can change between two reloads.
final class PSOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    var text: String {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}
