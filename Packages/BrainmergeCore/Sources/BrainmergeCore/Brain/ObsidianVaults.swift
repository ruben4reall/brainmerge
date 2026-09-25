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

    /// The vaults Obsidian knows whose folder still exists, each once, by name.
    public static func known(paths: Paths) -> [URL] {
        guard let handle = try? FileHandle(forReadingFrom: paths.obsidianVaultList) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1 << 20), let list = try? JSONDecoder().decode(List.self, from: data) else { return [] }
        var seen = Set<String>()
        var vaults: [URL] = []
        for path in list.vaults.values.compactMap(\.path) where !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue,
                  seen.insert(url.path).inserted else { continue }
            vaults.append(url)
        }
        return vaults.sorted {
            let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    /// A folder is a vault when Obsidian keeps its settings in it, in a `.obsidian` folder.
    public static func isVault(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appending(path: ".obsidian").path, isDirectory: &isFolder) && isFolder.boolValue
    }
}
