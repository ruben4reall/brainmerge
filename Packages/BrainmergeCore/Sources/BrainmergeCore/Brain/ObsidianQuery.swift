import Foundation

/// The part of Obsidian's search language that a graph's filter and color groups use: `path:` and `file:` terms,
/// quoted values, `-` to negate, juxtaposition for "and", `OR`, parentheses, all case-insensitive.
///
/// Anything else (a word searched in the text, `tag:`, `content:`, a regular expression, a property) is left out of
/// the query: evaluating it would need the notes' text or metadata, and a guess could hide or color a note wrongly.
/// A query that is left with nothing is empty. Parsing never fails.
public struct ObsidianQuery: Equatable, Sendable {
    indirect enum Expr: Equatable, Sendable {
        case path(String)
        case file(String)
        case not(Expr)
        case all([Expr])
        case any([Expr])
    }

    let expr: Expr?
    public let text: String

    public init(_ text: String) {
        self.text = text
        var parser = Parser(tokens: Self.tokens(text))
        expr = parser.parse()
    }

    /// Nothing Brainmerge can evaluate: as a filter it keeps every file, as a color group it colors none.
    public var isEmpty: Bool { expr == nil }

    /// Whether a file, by its path relative to the vault, matches. An empty query matches everything.
    public func matches(path: String) -> Bool { matches(Folded(path)) }

    /// A path folded once, to be tested against several queries.
    struct Folded {
        let path: String, name: String
        init(_ path: String) { self.path = ObsidianQuery.fold(path); name = (self.path as NSString).lastPathComponent }
    }

    func matches(_ folded: Folded) -> Bool {
        guard let expr else { return true }
        return Self.evaluate(expr, path: folded.path, name: folded.name)
    }

    /// Case and Unicode normalization folded away: a folder written with a combining accent on disk still matches a
    /// query typed with a precomposed one.
    static func fold(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.lowercased() }

    static func evaluate(_ expr: Expr, path: String, name: String) -> Bool {
        switch expr {
        case .path(let value): return path.contains(value)
        case .file(let value): return name.contains(value)
        case .not(let inner): return !evaluate(inner, path: path, name: name)
        case .all(let items): return items.allSatisfy { evaluate($0, path: path, name: name) }
        case .any(let items): return items.contains { evaluate($0, path: path, name: name) }
        }
    }

    // MARK: Tokens

    enum Token: Equatable {
        /// A term: its operator (nil for a bare word), its value, and whether a `-` negates it.
        case term(op: String?, value: String, negated: Bool)
        case open(negated: Bool)
        case close
        case or
    }

    static func tokens(_ text: String) -> [Token] {
        let s = Array(text)
        var tokens: [Token] = []
        var i = 0
        /// A quoted value, from after its opening quote to its closing one (or the end, when it never closes).
        func quoted(from start: Int) -> (String, Int) {
            var j = start, value = ""
            while j < s.count, s[j] != "\"" {
                if s[j] == "\\", j + 1 < s.count { value.append(s[j + 1]); j += 2; continue }
                value.append(s[j]); j += 1
            }
            return (value, min(j + 1, s.count))
        }
        func word(from start: Int) -> (String, Int) {
            var j = start
            while j < s.count, !s[j].isWhitespace, s[j] != "(", s[j] != ")" { j += 1 }
            return (String(s[start..<j]), j)
        }
        while i < s.count {
            let c = s[i]
            if c.isWhitespace { i += 1; continue }
            if c == ")" { tokens.append(.close); i += 1; continue }
            var negated = false
            while i < s.count, s[i] == "-" { negated.toggle(); i += 1 }
            guard i < s.count, !s[i].isWhitespace else {
                // A lone "-": nothing to negate.
                continue
            }
            if s[i] == "(" { tokens.append(.open(negated: negated)); i += 1; continue }
            if s[i] == ")" { continue }
            if s[i] == "\"" {
                let (value, next) = quoted(from: i + 1)
                tokens.append(.term(op: nil, value: value, negated: negated)); i = next; continue
            }
            // An operator is letters (and dashes) followed by a colon: path:, file:, tag:, content:...
            var j = i
            while j < s.count, s[j].isLetter || s[j] == "-" { j += 1 }
            if j > i, j < s.count, s[j] == ":" {
                let op = String(s[i..<j]).lowercased()
                i = j + 1
                if i < s.count, s[i] == "\"" {
                    let (value, next) = quoted(from: i + 1)
                    tokens.append(.term(op: op, value: value, negated: negated)); i = next
                } else if i < s.count, s[i] == "(" {
                    // An operator applied to a group, path:(a b): not evaluated. Skip the group whole.
                    var depth = 0
                    while i < s.count {
                        if s[i] == "(" { depth += 1 } else if s[i] == ")" { depth -= 1; if depth == 0 { i += 1; break } }
                        i += 1
                    }
                    tokens.append(.term(op: "unsupported", value: "", negated: negated))
                } else {
                    let (value, next) = word(from: i)
                    tokens.append(.term(op: op, value: value, negated: negated)); i = next
                }
                continue
            }
            let (value, next) = word(from: i)
            i = next
            if value == "OR", !negated { tokens.append(.or) } else { tokens.append(.term(op: nil, value: value, negated: negated)) }
        }
        return tokens
    }

    // MARK: Parser

    /// or := and ("OR" and)*; and := unary+; unary := term | "(" or ")". Terms that cannot be evaluated drop out.
    struct Parser {
        let tokens: [Token]
        var at = 0

        mutating func parse() -> Expr? {
            var result: [Expr] = []
            while at < tokens.count {
                if let e = parseOr() { result.append(e) }
                // A stray ")" at the top level: skip it and read on.
                if at < tokens.count, tokens[at] == .close { at += 1 }
            }
            return Self.combine(result, all: true)
        }

        mutating func parseOr() -> Expr? {
            var items: [Expr] = []
            if let first = parseAnd() { items.append(first) }
            while at < tokens.count, tokens[at] == .or {
                at += 1
                if let next = parseAnd() { items.append(next) }
            }
            return Self.combine(items, all: false)
        }

        mutating func parseAnd() -> Expr? {
            var items: [Expr] = []
            while at < tokens.count {
                switch tokens[at] {
                case .or, .close:
                    return Self.combine(items, all: true)
                case .open(let negated):
                    at += 1
                    let inner = parseOr()
                    if at < tokens.count, tokens[at] == .close { at += 1 }
                    if let inner { items.append(negated ? .not(inner) : inner) }
                case .term(let op, let value, let negated):
                    at += 1
                    if let term = Self.term(op: op, value: value) { items.append(negated ? .not(term) : term) }
                }
            }
            return Self.combine(items, all: true)
        }

        static func term(op: String?, value: String) -> Expr? {
            let folded = ObsidianQuery.fold(value)
            // A regular expression (/.../) needs a matcher Brainmerge does not have: left out like other unknown terms.
            if folded.hasPrefix("/"), folded.hasSuffix("/"), folded.count > 1 { return nil }
            switch op {
            case "path": return .path(folded)
            case "file": return .file(folded)
            default: return nil
            }
        }

        static func combine(_ items: [Expr], all: Bool) -> Expr? {
            if items.count <= 1 { return items.first }
            return all ? .all(items) : .any(items)
        }
    }
}
