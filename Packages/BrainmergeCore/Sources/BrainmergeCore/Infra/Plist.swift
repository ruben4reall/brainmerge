import Foundation

public enum Plist {
    public static func read(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw BrainmergeError.invalidPlist(url.path) }
        return dict
    }

    public static func write(_ dict: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }
}
