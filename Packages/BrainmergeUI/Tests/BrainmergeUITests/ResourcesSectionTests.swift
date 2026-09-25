import AppKit
import SwiftUI
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

/// The RAM and disk section lays out in every state, wide and narrow, without the real Mac's figures.
@MainActor @Suite struct ResourcesSectionTests {
    @Test func theSectionLaysOutWideNarrowAndWithoutFigures() async throws {
        let e = try ManagerEnv.make(); defer { e.home.remove() }
        _ = try e.manager.adoptPrimary(name: "Ruben")
        _ = try e.manager.add(IdentityManager.AddRequest(name: "Client"))
        let exe = e.claude.executable.path
        let manager = IdentityManager(paths: e.home.paths, store: e.store, launcherBinary: Products.launcher, cliPath: e.cliPath,
                                      claudeAppURL: e.claude.url, registerLaunchers: false,
                                      monitor: ProcessMonitor(psOutput: { "  800 1 90000 \(exe)\n  950 1 3000 -zsh\n  951 950 70000 claude\n" }))
        let model = AppModel(paths: e.home.paths, store: e.store, manager: manager, claudeAppURL: e.claude.url)
        model.readMacMemory = { _ in nil }
        model.reload()
        func height(width: CGFloat) -> CGFloat {
            let view = NSHostingView(rootView: ResourcesSection(model: model).frame(width: width))
            view.layoutSubtreeIfNeeded()
            return view.fittingSize.height
        }
        #expect(height(width: 880) > 100)
        model.readMacMemory = { MacMemory.read(pressure: $0) }
        model.memoryPressure = { .critical }
        model.reload()
        model.diskMeasure = { _, _ in DiskSize(bytes: 2_000_000_000, complete: false, sharedBytes: 1) }
        await model.refreshDisk()
        #expect(height(width: 880) > 100)
        #expect(height(width: 420) > 100)
    }
}
