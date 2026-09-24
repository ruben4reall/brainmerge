import Foundation

/// Marker class: `Bundle(for:)` finds the test bundle even under Swift Testing.
private final class ProductsMarker {}

public enum Products {
    /// Folder of the built products (contains `launcher` and `brainmerge`): next to the test bundle,
    /// otherwise in the core package's build (for the UI package's tests), otherwise BRAINMERGE_PRODUCTS.
    public static var directory: URL {
        if let p = ProcessInfo.processInfo.environment["BRAINMERGE_PRODUCTS"] { return URL(fileURLWithPath: p) }
        let candidates = [Bundle(for: ProductsMarker.self).bundleURL.deletingLastPathComponent(), corePackageDebugDir]
        for dir in candidates where FileManager.default.fileExists(atPath: dir.appending(path: "launcher").path) { return dir }
        return candidates[0]
    }
    public static var launcher: URL { directory.appending(path: "launcher") }
    public static var brainmerge: URL { directory.appending(path: "brainmerge") }

    static var corePackageDebugDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: ".build/debug", directoryHint: .isDirectory)
    }
}
