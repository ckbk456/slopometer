import Foundation

/// A saved GitHub token. Several can be saved, for example one per resource owner,
/// because a fine-grained token reads only the repositories of a single owner.
public struct AccessToken: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Can be limited to read-only Pull requests access.
        case fineGrained
        /// Classic or other token formats; scopes such as `repo` also grant write access.
        case classic

        public init(of value: String) {
            self = value.hasPrefix("github_pat_") ? .fineGrained : .classic
        }
    }

    /// Stable local identifier, also the Keychain account. Never the secret itself.
    public let id: String
    public let value: String

    public init(id: String, value: String) {
        self.id = id
        self.value = value
    }

    public var kind: Kind { Kind(of: value) }
}
