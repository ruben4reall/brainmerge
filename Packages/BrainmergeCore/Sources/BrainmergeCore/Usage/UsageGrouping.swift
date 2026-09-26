import Foundation

/// Groups identities by real `projects` folder: two accounts with shared history read the same folder.
public enum UsageGrouping {
    public static func groups(of identities: [Identity], paths: Paths) -> [[Identity]] {
        var order: [String] = []
        var byRoot: [String: [Identity]] = [:]
        for identity in identities {
            let projects = CLIProfile(directory: identity.cliProfile(in: paths)).projectsDir
            let key = projects.resolvingSymlinksInPath().path
            if byRoot[key] == nil { order.append(key) }
            byRoot[key, default: []].append(identity)
        }
        return order.compactMap { byRoot[$0] }
    }
}
