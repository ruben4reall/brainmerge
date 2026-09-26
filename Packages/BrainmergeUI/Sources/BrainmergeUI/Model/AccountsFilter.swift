import Foundation

public enum AccountsFilter {
    /// `saved`: the accounts' own order, the sidebar's. Accounts never move or swap places when one opens or closes.
    public enum Sort { case saved, name }

    public static func apply(_ accounts: [Account], query: String, sort: Sort = .saved) -> [Account] {
        let needle = fold(query)
        let hits = needle.isEmpty ? accounts : accounts.filter {
            fold($0.identity.name).contains(needle) || $0.identity.slug.contains(needle) || ($0.codeAccount.map { fold($0.email).contains(needle) } ?? false)
        }
        switch sort {
        case .name:
            return hits.sorted { $0.identity.name.localizedCaseInsensitiveCompare($1.identity.name) == .orderedAscending }
        case .saved:
            return hits
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespaces)
    }
}
