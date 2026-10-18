import Foundation

/// Identifies a build: semantic version, build number, and source commit, read from its
/// Info.plist. The app stamps the shared snapshot with its own so the widget can tell when
/// macOS runs it from a different build.
public struct BuildStamp: Codable, Equatable, Sendable {
    public static let unknown = "unknown"

    public let version: String
    public let build: String
    public let commit: String

    public init(version: String, build: String, commit: String) {
        self.version = version
        self.build = build
        self.commit = commit
    }

    /// Reads `CFBundleShortVersionString`, `CFBundleVersion`, and `SlopometerCommit`.
    public init(bundle: Bundle) {
        func value(_ key: String) -> String {
            bundle.object(forInfoDictionaryKey: key) as? String ?? Self.unknown
        }
        self.init(
            version: value("CFBundleShortVersionString"), build: value("CFBundleVersion"),
            commit: value("SlopometerCommit"))
    }

    /// For example "0.2.0 (31, 16667c3)".
    public var summary: String { "\(version) (\(build), \(commit))" }

    /// True only when both builds are known and differ in version or build number. Commits
    /// are not compared: the same commit count with local edits is still the same build.
    public static func differs(writer: BuildStamp?, reader: BuildStamp) -> Bool {
        guard let writer else { return false }
        func known(_ value: String) -> Bool { !value.isEmpty && value != unknown }
        guard known(writer.version), known(writer.build), known(reader.version), known(reader.build)
        else { return false }
        return writer.version != reader.version || writer.build != reader.build
    }
}
