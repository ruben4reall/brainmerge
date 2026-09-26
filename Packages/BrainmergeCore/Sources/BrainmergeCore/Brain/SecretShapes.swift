import Foundation

/// What a line that looks like it holds a key looks like. Only the kind is ever kept or shown, never the line.
public enum SecretShape: String, Codable, CaseIterable, Sendable {
    case privateKey, anthropic, openAI, gitHub, gitLab, slack, aws, google, stripe, npm, assignment

    /// "looks like <label>".
    public var label: String {
        switch self {
        case .privateKey: "a private key"
        case .anthropic: "an Anthropic API key"
        case .openAI: "an OpenAI API key"
        case .gitHub: "a GitHub token"
        case .gitLab: "a GitLab token"
        case .slack: "a Slack token"
        case .aws: "an AWS access key"
        case .google: "a Google API key"
        case .stripe: "a Stripe live key"
        case .npm: "an npm token"
        case .assignment: "a password or key"
        }
    }
}

/// The shapes the secret guard looks for, all in this one file: a private key's header, providers' key prefixes, and a
/// key, secret, password or token set to a long value that looks random. A shape matches one line.
public enum SecretShapes {
    /// Checked in this order: Anthropic's keys start like OpenAI's.
    static let patterns: [(SecretShape, NSRegularExpression)] = ([
        (.privateKey, #"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"#),
        (.anthropic, #"(?<![A-Za-z0-9_-])sk-ant-[A-Za-z0-9_-]{20,}"#),
        (.openAI, #"(?<![A-Za-z0-9_-])sk-(?:proj-|svcacct-|admin-)?(?=[A-Za-z0-9_-]*[0-9])[A-Za-z0-9_-]{32,}"#),
        (.gitHub, #"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})"#),
        (.gitLab, #"(?<![A-Za-z0-9_])glpat-[A-Za-z0-9_-]{20,}"#),
        (.slack, #"(?<![A-Za-z0-9_])xox[abposr]-[A-Za-z0-9-]{10,}"#),
        (.aws, #"(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])"#),
        (.google, #"(?<![A-Za-z0-9_])AIza[A-Za-z0-9_-]{35}"#),
        (.stripe, #"(?<![A-Za-z0-9_])[rs]k_live_[A-Za-z0-9]{24,}"#),
        (.npm, #"(?<![A-Za-z0-9_])npm_[A-Za-z0-9]{36}"#),
    ] as [(SecretShape, String)]).map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    /// A word that names a key, then `:` or `=`, then the value (quoted or not).
    static let assignment = try! NSRegularExpression(
        pattern: #"(?i)(?:api[_-]?key|secret|password|passwd|token|private[_-]?key)[A-Za-z0-9_-]*["']?\s*[:=]\s*["']?([^\s"'`,;]{20,})"#)

    /// Values that name where a key comes from rather than holding one.
    static let references = ["$", "<", "{", "%", "process.env", "os.environ", "ENV["]

    /// The first shape the line has, nil when it has none.
    public static func match(_ line: String) -> SecretShape? {
        let range = NSRange(line.startIndex..., in: line)
        for (shape, pattern) in patterns where pattern.firstMatch(in: line, range: range) != nil { return shape }
        for found in assignment.matches(in: line, range: range) {
            guard let value = Range(found.range(at: 1), in: line).map({ String(line[$0]) }) else { continue }
            if references.contains(where: { value.hasPrefix($0) }) { continue }
            if (value.hasPrefix("http://") || value.hasPrefix("https://")) && !value.contains("@") { continue }
            if entropy(value) > 3.5 { return .assignment }
        }
        return nil
    }

    /// Shannon entropy, in bits per character: a random key is above 4, a word or a repeated letter far below.
    static func entropy(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for ch in text { counts[ch, default: 0] += 1 }
        let total = Double(text.count)
        return counts.values.reduce(0) { sum, count in
            let p = Double(count) / total
            return sum - p * log2(p)
        }
    }
}
