import Foundation

public enum AccountsFilter {
    public enum Sort { case lastUsed, name }

    public static func apply(_ accounts: [Account], query: String, sort: Sort = .lastUsed) -> [Account] {
        let needle = fold(query)
        let hits = needle.isEmpty ? accounts : accounts.filter {
            fold($0.identity.name).contains(needle) || $0.identity.slug.contains(needle) || ($0.codeAccount.map { fold($0.email).contains(needle) } ?? false)
        }
        switch sort {
        case .name:
            return hits.sorted { $0.identity.name.localizedCaseInsensitiveCompare($1.identity.name) == .orderedAscending }
        case .lastUsed:
            return hits.sorted {
                if $0.isRunning != $1.isRunning { return $0.isRunning }
                return $0.identity.createdAt > $1.identity.createdAt
            }
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespaces)
    }
}
