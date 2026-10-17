import Foundation

/// A repository a person can tick in the PR repository filter.
public struct RepositoryChoice: Equatable, Identifiable, Sendable {
    /// `owner/name`, spelled as GitHub reports it.
    public let name: String
    /// Synced PRs authored in this repository; 0 for a selection with no synced PRs.
    public let pullRequests: Int
    public var id: String { name.lowercased() }

    public init(name: String, pullRequests: Int) {
        self.name = name
        self.pullRequests = pullRequests
    }
}

/// Checklist rules for the repository filter. An empty selection means every
/// readable repository, so the filter can never select nothing.
public enum RepositoryFilter {
    /// Repositories with synced PRs, plus selected ones that have none, busiest first.
    public static func choices(records: [PullRequestRecord], selected: [String])
        -> [RepositoryChoice]
    {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for record in records {
            let key = record.repository.lowercased()
            names[key] = names[key] ?? record.repository
            counts[key, default: 0] += 1
        }
        for name in selected where names[name.lowercased()] == nil {
            names[name.lowercased()] = name
        }
        return names.map { key, name in
            RepositoryChoice(name: name, pullRequests: counts[key] ?? 0)
        }
        .sorted {
            ($0.pullRequests, $1.id) > ($1.pullRequests, $0.id)
        }
    }

    public static func isIncluded(_ name: String, in selected: [String]) -> Bool {
        selected.isEmpty || selected.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Whether unticking `name` would leave nothing ticked.
    public static func isLastIncluded(
        _ name: String, in selected: [String], choices: [RepositoryChoice]
    ) -> Bool {
        let included = selected.isEmpty ? choices.map(\.name) : selected
        return included.count == 1 && isIncluded(name, in: [included[0]])
    }

    /// Ticks or unticks `name`. Unticking from "all" keeps every other choice; ticking
    /// every choice collapses back to "all"; the last ticked repository stays ticked.
    public static func toggling(
        _ name: String, in selected: [String], choices: [RepositoryChoice]
    ) -> [String] {
        guard !isLastIncluded(name, in: selected, choices: choices) else { return selected }
        let included = selected.isEmpty ? choices.map(\.name) : selected
        let updated =
            isIncluded(name, in: selected)
            ? included.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            : included + [name]
        let coversAll = choices.allSatisfy { isIncluded($0.name, in: updated) }
        return coversAll ? [] : updated
    }
}
