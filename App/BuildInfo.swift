import Foundation
import SlopometerCore

/// Identifies the running build: semantic version, build number, and source commit.
enum BuildInfo {
    static let stamp = BuildStamp(bundle: .main)
    static var version: String { stamp.version }
    static var build: String { stamp.build }
    static var commit: String { stamp.commit }

    /// For example "0.2.0 (31, 16667c3)".
    static var summary: String { stamp.summary }
}
