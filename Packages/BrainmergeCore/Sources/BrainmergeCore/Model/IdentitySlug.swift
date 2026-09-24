import Foundation

public enum IdentitySlug {
    /// ASCII lowercase letters and dashes, 32 characters max, unique among `taken`.
    public static func make(from name: String, taken: Set<String> = []) -> String {
        let folded = name.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en")).lowercased()
        var out = ""
        var lastWasDash = true
        for ch in folded {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                out.append(ch); lastWasDash = false
            } else if !lastWasDash {
                out.append("-"); lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        if out.isEmpty { out = "identity" }
        if out.count > 32 {
            out = String(out.prefix(32))
            while out.hasSuffix("-") { out.removeLast() }
        }
        guard taken.contains(out) else { return out }
        var n = 2
        while taken.contains("\(out)-\(n)") { n += 1 }
        return "\(out)-\(n)"
    }
}
