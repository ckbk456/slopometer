import Foundation

/// Identifies the running build: semantic version, build number, and source commit.
enum BuildInfo {
    static let version = value("CFBundleShortVersionString")
    static let build = value("CFBundleVersion")
    static let commit = value("SlopometerCommit")

    /// For example "0.2.0 (31, 16667c3)".
    private static func value(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "unknown"
    }

    static var summary: String { "\(version) (\(build), \(commit))" }
}
