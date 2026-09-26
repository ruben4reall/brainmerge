import Darwin
import Foundation

/// The disk space a folder takes, and whether every entry was counted.
public struct DiskSize: Equatable, Sendable {
    public var bytes: Int64
    /// False when the walk stopped early (limits, or the screen went away): `bytes` is then a lower bound.
    public var complete: Bool
    /// A private-size walk only: the blocks its files share with clones elsewhere (a tinted copy with Claude).
    public var sharedBytes: Int64
    public init(bytes: Int64, complete: Bool, sharedBytes: Int64 = 0) {
        self.bytes = bytes; self.complete = complete; self.sharedBytes = sharedBytes
    }
}

/// Adds up the blocks a folder takes, from the sizes the file system reports while listing it: no file is opened, no
/// name is turned into text, no link is followed, no other disk is entered, nothing is written.
public struct DiskUsage: Sendable {
    public var entryLimit: Int
    public var timeLimit: Duration

    public init(entryLimit: Int = 2_000_000, timeLimit: Duration = .seconds(20)) {
        self.entryLimit = entryLimit; self.timeLimit = timeLimit
    }

    private struct FileID: Hashable { let device: dev_t; let inode: ino_t }

    /// Nil when the folder does not exist. `privateOnly` counts, per file, only the blocks no clone shares (25 times
    /// slower, so for app bundles only). `skipping`: folders inside `root` counted elsewhere, given as real paths.
    /// The limits and `isCancelled` are checked on the first entry and every 4,096 after it.
    public func size(of root: URL, privateOnly: Bool = false, skipping: [URL] = [], isCancelled: () -> Bool = { false }) -> DiskSize? {
        guard let start = strdup(root.path) else { return nil }
        defer { free(start) }
        let skipped = skipping.compactMap { strdup($0.path) }
        defer { skipped.forEach { free($0) } }
        var roots: [UnsafeMutablePointer<CChar>?] = [start, nil]
        // Physical: a link is reported as a link and never followed. XDEV: a mounted disk inside is never entered.
        guard let stream = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
        defer { fts_close(stream) }
        let clock = ContinuousClock()
        let began = clock.now
        var total: Int64 = 0, shared: Int64 = 0, entries = 0
        var complete = true
        // Only regular files with several links: a folder's link count is its number of entries on APFS.
        var linked: Set<FileID> = []
        while let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            if entry.pointee.fts_level == FTS_ROOTLEVEL, info == FTS_NS || info == FTS_ERR { return nil }
            if info == FTS_DP { continue }   // a folder on the way back up, counted on the way down
            if entries & 4095 == 0, isCancelled() || clock.now - began > timeLimit { complete = false; break }
            entries += 1
            if entries > entryLimit { complete = false; break }
            if info == FTS_D, !skipped.isEmpty, let path = entry.pointee.fts_path, skipped.contains(where: { strcmp($0, path) == 0 }) {
                fts_set(stream, entry, FTS_SKIP)
                continue
            }
            guard info != FTS_NS, info != FTS_ERR, info != FTS_DC, let stat = entry.pointee.fts_statp?.pointee else { continue }
            let allocated = Int64(stat.st_blocks) * 512
            guard info == FTS_F else { total += allocated; continue }
            if stat.st_nlink > 1, !linked.insert(FileID(device: stat.st_dev, inode: stat.st_ino)).inserted { continue }
            if privateOnly, let path = entry.pointee.fts_accpath, let own = Self.privateSize(path) {
                total += min(own, allocated)
                shared += max(0, allocated - own)
            } else {
                total += allocated
            }
        }
        return DiskSize(bytes: total, complete: complete, sharedBytes: shared)
    }

    /// The bytes of a file no clone shares (ATTR_CMNEXT_PRIVATESIZE), without following a link. The reply is packed:
    /// its length (4 bytes), then the size (8 bytes) right after it, not at the next 8-byte boundary.
    static func privateSize(_ path: UnsafePointer<CChar>) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var reply = [UInt8](repeating: 0, count: 16)
        let result = reply.withUnsafeMutableBytes { buffer in
            getattrlist(path, &request, buffer.baseAddress, buffer.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard result == 0 else { return nil }
        return reply.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
}
