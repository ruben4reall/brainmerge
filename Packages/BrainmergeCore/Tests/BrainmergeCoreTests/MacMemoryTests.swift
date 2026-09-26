import Foundation
import Testing
@testable import BrainmergeCore

@Suite struct MacMemoryTests {
    static let gib: Int64 = 1 << 30

    /// Activity Monitor's "Memory Used": apps (anonymous pages minus purgeable) plus wired plus compressed.
    /// Cached files and free pages are not "used".
    @Test func usedIsAppsPlusWiredPlusCompressed() {
        let pages = MacMemory.Pages(internalPages: 500_000, purgeable: 20_000, external: 300_000, wired: 150_000, compressor: 50_000, free: 10_000)
        let mac = MacMemory(physical: 18 * Self.gib, pageSize: 16_384, pages: pages, swapUsed: 0, pressure: .normal)
        #expect(mac.appMemory == 480_000 * 16_384)
        #expect(mac.wired == 150_000 * 16_384)
        #expect(mac.compressed == 50_000 * 16_384)
        #expect(mac.used == 680_000 * 16_384)
        #expect(mac.cachedFiles == 320_000 * 16_384)
        // 680,000 pages of 16 KB is 10.4 GB of 18 GB.
        #expect(abs(mac.usedFraction - 0.5764) < 0.001)
    }

    @Test func oddCountsNeverGiveANegativeOrImpossibleFigure() {
        // Purgeable above internal (the counters are read one after another): apps clamp at zero.
        let skewed = MacMemory(physical: 8 * Self.gib, pageSize: 4096,
                               pages: .init(internalPages: 10, purgeable: 30, external: 0, wired: 100, compressor: 0, free: 0), swapUsed: 0, pressure: .normal)
        #expect(skewed.appMemory == 0)
        #expect(skewed.used == 100 * 4096)
        // More pages than the Mac has: used never exceeds physical.
        let over = MacMemory(physical: 1 * Self.gib, pageSize: 16_384,
                             pages: .init(internalPages: 200_000, purgeable: 0, external: 0, wired: 0, compressor: 0, free: 0), swapUsed: 0, pressure: .normal)
        #expect(over.used == 1 * Self.gib)
        #expect(over.usedFraction == 1)
        let empty = MacMemory(physical: 0, pageSize: 16_384, pages: .init(internalPages: 1, purgeable: 0, external: 0, wired: 0, compressor: 0, free: 0), swapUsed: 0, pressure: .normal)
        #expect(empty.usedFraction == 0)
    }

    /// Read from the kernel with no subprocess: the real Mac gives a sane figure.
    @Test func readsTheRealMacWithoutASubprocess() throws {
        let mac = try #require(MacMemory.read(pressure: .warning))
        #expect(mac.physical == Int64(ProcessInfo.processInfo.physicalMemory))
        #expect([4096, 16_384].contains(mac.pageSize))
        #expect(mac.used > 0 && mac.used <= mac.physical)
        #expect(mac.swapUsed >= 0)
        #expect(mac.pressure == .warning)
    }
}
