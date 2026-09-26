import Darwin
import Foundation

/// The Mac's RAM as Activity Monitor counts it, read from the kernel with no subprocess.
/// "Used" is apps + wired + compressed; cached files and free pages are not used, the system takes them back at once.
public struct MacMemory: Equatable, Sendable {
    /// Page counts from host_statistics64 (HOST_VM_INFO64).
    public struct Pages: Equatable, Sendable {
        public var internalPages: UInt64
        public var purgeable: UInt64
        public var external: UInt64
        public var wired: UInt64
        public var compressor: UInt64
        public var free: UInt64
        public init(internalPages: UInt64, purgeable: UInt64, external: UInt64, wired: UInt64, compressor: UInt64, free: UInt64) {
            self.internalPages = internalPages; self.purgeable = purgeable; self.external = external
            self.wired = wired; self.compressor = compressor; self.free = free
        }
    }

    public let physical: Int64
    /// 16 KB on Apple silicon, 4 KB on Intel: always asked of the kernel.
    public let pageSize: Int64
    public let pages: Pages
    public let swapUsed: Int64
    public let pressure: MemoryPressure.Level

    public init(physical: Int64, pageSize: Int64, pages: Pages, swapUsed: Int64, pressure: MemoryPressure.Level) {
        self.physical = physical; self.pageSize = pageSize; self.pages = pages; self.swapUsed = swapUsed; self.pressure = pressure
    }

    /// Anonymous pages apps own, minus the purgeable ones the system may drop at will. The counters are read one after
    /// another, so purgeable can briefly exceed internal: clamped rather than negative.
    public var appMemory: Int64 { Int64(pages.internalPages - min(pages.purgeable, pages.internalPages)) * pageSize }
    public var wired: Int64 { Int64(pages.wired) * pageSize }
    /// The physical pages the compressor occupies, not the uncompressed size of what it holds.
    public var compressed: Int64 { Int64(pages.compressor) * pageSize }
    public var cachedFiles: Int64 { Int64(pages.external + pages.purgeable) * pageSize }
    public var used: Int64 { min(physical, appMemory + wired + compressed) }
    public var usedFraction: Double { physical > 0 ? Double(used) / Double(physical) : 0 }

    /// Every mach_host_self() call adds a user reference to the send right: one, kept for the process.
    private static let host = mach_host_self()

    /// Nil when the kernel refuses the statistics.
    public static func read(pressure: MemoryPressure.Level) -> MacMemory? {
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        var stats = vm_statistics64()
        // HOST_VM_INFO64_COUNT is a macro Swift does not import.
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = Pages(internalPages: UInt64(stats.internal_page_count), purgeable: UInt64(stats.purgeable_count),
                          external: UInt64(stats.external_page_count), wired: UInt64(stats.wire_count),
                          compressor: UInt64(stats.compressor_page_count), free: UInt64(stats.free_count))
        return MacMemory(physical: MemoryPressure.physicalMemory, pageSize: Int64(pageSize), pages: pages,
                         swapUsed: swapUsed(), pressure: pressure)
    }

    /// Swap in use (vm.swapusage), zero when the kernel does not say.
    static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }
}
