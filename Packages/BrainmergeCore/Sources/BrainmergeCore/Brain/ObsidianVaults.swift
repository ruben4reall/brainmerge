import Foundation

/// The Obsidian vaults on this Mac, as Obsidian lists them. Only the folders' paths are decoded from its list; the
/// vaults themselves are only ever read, never written, and never turned into a Brainmerge memory.
public enum ObsidianVaults {
    /// Obsidian's list: `{"vaults": {"<id>": {"path": "...", "ts": ..., "open": true}}}`. Decoded for the paths alone.
    struct List: Decodable {
        struct Vault: Decodable { let path: String? }
        let vaults: [String: LossyVault]
        /// One entry Obsidian wrote differently does not hide the others.
        struct LossyVault: Decodable {
            let path: String?
            init(from decoder: Decoder) throws { path = (try? Vault(from: decoder))?.path }
        }
    }

    /// The vaults Obsidian knows, each once, by name. A vault in a place macOS guards with a consent prompt (Documents,
    /// iCloud Drive, another disk) is listed as Obsidian lists it, unlooked at: a look would ask the person before they
    /// picked anything. Anywhere else, one whose folder is gone is left out.
    public static func known(paths: Paths) -> [URL] {
        guard let handle = try? FileHandle(forReadingFrom: paths.obsidianVaultList) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1 << 20), let list = try? JSONDecoder().decode(List.self, from: data) else { return [] }
        var seen = Set<String>()
        var vaults: [URL] = []
        for path in list.vaults.values.compactMap(\.path) where !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            // resolve() is nil when the path, or a link on the way, reaches a guarded place; it never looks inside one.
            let guarded = DiskPlan.resolve(url, home: paths.home) == nil
            var isFolder: ObjCBool = false
            guard guarded || FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue,
                  seen.insert(url.path).inserted else { continue }
            vaults.append(url)
        }
        return vaults.sorted {
            let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    /// Whether a chosen vault's folder is gone (moved, deleted, its disk unplugged). A folder that macOS or its
    /// permissions refuse to show is not gone: the graph then says it may not read it, instead of quietly switching.
    public static func isGone(_ url: URL) -> Bool {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return errno == ENOENT || errno == ENOTDIR }
        return info.st_mode & S_IFMT != S_IFDIR
    }

    /// A folder is a vault when Obsidian keeps its settings in it, in a `.obsidian` folder.
    public static func isVault(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appending(path: ".obsidian").path, isDirectory: &isFolder) && isFolder.boolValue
    }
}
