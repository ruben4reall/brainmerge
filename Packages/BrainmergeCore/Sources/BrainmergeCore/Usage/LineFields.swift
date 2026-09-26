import Foundation

/// The few fields Brainmerge needs from one transcript line, read by walking the JSON bytes once, with no
/// allocation per key: the type, the timestamp, the working folder, and the message's id, model and usage.
/// Strings are parsed properly, so a key mentioned inside a text block is never mistaken for a real one.
struct LineFields {
    var type: String?
    var timestamp: String?
    var cwd: String?
    var messageID: String?
    var model: String?
    var hasUsage = false
    var input = 0, cacheCreation = 0, cacheRead = 0, output = 0

    static func parse(_ line: Data) -> LineFields {
        line.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> LineFields in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return LineFields() }
            return parse(bytes: UnsafeBufferPointer(start: base, count: raw.count))
        }
    }

    static func parse(bytes: UnsafeBufferPointer<UInt8>) -> LineFields {
        do {
            var walker = Walker(bytes: bytes)
            var fields = LineFields()
            walker.walkObject { key, walker in
                switch key {
                case "type": fields.type = walker.string()
                case "timestamp": fields.timestamp = walker.string()
                case "cwd": fields.cwd = walker.string()
                case "message":
                    walker.walkObject { key, walker in
                        switch key {
                        case "id": fields.messageID = walker.string()
                        case "model": fields.model = walker.string()
                        case "usage":
                            walker.skipWhitespace()
                            fields.hasUsage = walker.peek() == UInt8(ascii: "{")
                            walker.walkObject { key, walker in
                                switch key {
                                case "input_tokens": fields.input = walker.int() ?? 0
                                case "cache_creation_input_tokens": fields.cacheCreation = walker.int() ?? 0
                                case "cache_read_input_tokens": fields.cacheRead = walker.int() ?? 0
                                case "output_tokens": fields.output = walker.int() ?? 0
                                default: walker.skipValue()
                                }
                            }
                        default: walker.skipValue()
                        }
                    }
                default: walker.skipValue()
                }
            }
            return fields
        }
    }

    /// A cursor over the bytes of one JSON value. Every method leaves the cursor after the value it consumed.
    struct Walker {
        let bytes: UnsafeBufferPointer<UInt8>
        var i = 0

        init(bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        var atEnd: Bool { i >= bytes.count }
        func peek() -> UInt8? { i < bytes.count ? bytes[i] : nil }
        mutating func skipWhitespace() { while let c = peek(), c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { i += 1 } }

        /// Walks the object at the cursor: `body` is called for each key with the cursor on its value and must consume it.
        mutating func walkObject(_ body: (String, inout Walker) -> Void) {
            skipWhitespace()
            guard peek() == UInt8(ascii: "{") else { skipValue(); return }
            i += 1
            // Every turn of the loop must move the cursor: a broken line ends the walk, it never spins.
            while true {
                skipWhitespace()
                guard let c = peek() else { return }
                if c == UInt8(ascii: "}") { i += 1; return }
                if c == UInt8(ascii: ",") { i += 1; continue }
                let start = i
                guard c == UInt8(ascii: "\""), let key = string() else {
                    skipValue()
                    if i == start { return }
                    continue
                }
                skipWhitespace()
                guard peek() == UInt8(ascii: ":") else { return }
                i += 1
                skipWhitespace()
                let before = i
                body(key, &self)
                if i == before { skipValue() }   // the body did not consume the value
                if i == before { return }        // nothing to consume: a truncated or broken line
            }
        }

        /// The string at the cursor, unescaped (the few escapes paths and ids can hold).
        mutating func string() -> String? {
            skipWhitespace()
            guard peek() == UInt8(ascii: "\"") else { return nil }
            i += 1
            let start = i
            var needsUnescape = false
            while let c = peek() {
                if c == UInt8(ascii: "\\") { needsUnescape = true; i += 2; continue }
                if c == UInt8(ascii: "\"") { break }
                i += 1
            }
            let end = min(i, bytes.count)
            i = end + 1
            let slice = UnsafeBufferPointer(rebasing: bytes[start..<end])
            guard needsUnescape else { return String(decoding: slice, as: UTF8.self) }
            return Self.unescape(slice)
        }

        /// Steps over the string at the cursor without reading it: a skipped value is never copied or decoded.
        mutating func skipString() {
            guard peek() == UInt8(ascii: "\"") else { return }
            i += 1
            while let c = peek() {
                if c == UInt8(ascii: "\\") { i += 2; continue }
                i += 1
                if c == UInt8(ascii: "\"") { return }
            }
        }

        /// JSON's escapes, `\uXXXX` and its surrogate pairs included. A broken escape is kept as it is written.
        static func unescape(_ raw: UnsafeBufferPointer<UInt8>) -> String {
            var out: [UInt8] = []
            out.reserveCapacity(raw.count)
            var k = 0
            func hex(_ at: Int) -> UInt32? {
                guard at + 4 <= raw.count else { return nil }
                var v: UInt32 = 0
                for b in raw[at..<(at + 4)] {
                    guard let d = Int(String(UnicodeScalar(b)), radix: 16) else { return nil }
                    v = v << 4 | UInt32(d)
                }
                return v
            }
            while k < raw.count {
                let c = raw[k]
                guard c == UInt8(ascii: "\\"), k + 1 < raw.count else { out.append(c); k += 1; continue }
                let e = raw[k + 1]
                k += 2
                switch e {
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "u"):
                    guard var scalar = hex(k) else { out += [UInt8(ascii: "\\"), e]; continue }
                    k += 4
                    if (0xD800...0xDBFF).contains(scalar), k + 1 < raw.count, raw[k] == UInt8(ascii: "\\"), raw[k + 1] == UInt8(ascii: "u"),
                       let low = hex(k + 2), (0xDC00...0xDFFF).contains(low) {
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        k += 6
                    }
                    out += Array(String(UnicodeScalar(scalar).map(Character.init) ?? "\u{FFFD}").utf8)
                default: out.append(e)   // \" \\ \/ and anything else: the character itself
                }
            }
            return String(decoding: out, as: UTF8.self)
        }

        /// The integer at the cursor (a JSON number without fraction), or nil.
        mutating func int() -> Int? {
            skipWhitespace()
            var value = 0, digits = 0
            while let c = peek(), c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") {
                value = value &* 10 &+ Int(c - UInt8(ascii: "0")); digits += 1; i += 1
            }
            if digits == 0 { skipValue(); return nil }
            // A fraction or an exponent: not a token count, skip the rest of the number.
            while let c = peek(), c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") || c == UInt8(ascii: "+") || c == UInt8(ascii: "-") || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) { i += 1 }
            return value
        }

        /// Skips any value: a string, a number, a literal, an object or an array (strings inside are respected).
        mutating func skipValue() {
            skipWhitespace()
            guard let c = peek() else { return }
            switch c {
            case UInt8(ascii: "\""): skipString()
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                var depth = 0
                while let c = peek() {
                    if c == UInt8(ascii: "\"") { skipString(); continue }
                    if c == UInt8(ascii: "{") || c == UInt8(ascii: "[") { depth += 1 }
                    if c == UInt8(ascii: "}") || c == UInt8(ascii: "]") { depth -= 1; if depth == 0 { i += 1; return } }
                    i += 1
                }
            case UInt8(ascii: "}"), UInt8(ascii: "]"), UInt8(ascii: ","):
                i += 1   // a stray closing character or separator: stepping over it keeps the walk moving
            default:
                while let c = peek(), c != UInt8(ascii: ","), c != UInt8(ascii: "}"), c != UInt8(ascii: "]"), c != 0x20, c != 0x0A { i += 1 }
            }
        }
    }
}
