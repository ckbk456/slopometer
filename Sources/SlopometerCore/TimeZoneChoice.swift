import Foundation

/// One IANA timezone, named for people: "Ho Chi Minh", "Asia", "GMT+7".
public struct TimeZoneChoice: Identifiable, Equatable, Sendable {
    /// The IANA identifier, for example `Asia/Ho_Chi_Minh`.
    public let id: String
    public let city: String
    /// The area, with nested areas joined: "America · Argentina". Empty for zones like GMT.
    public let region: String
    /// Offset from GMT at the given date, so daylight saving shows as it is now.
    public let offset: String
    public let offsetSeconds: Int
    /// The system's generic name, such as "Indochina Time", when it has one.
    public let name: String?

    public init?(identifier: String, at date: Date = Date(), locale: Locale = .current) {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        id = identifier
        let parts = identifier.split(separator: "/").map {
            $0.replacingOccurrences(of: "_", with: " ")
        }
        city = parts.last ?? identifier
        region = parts.dropLast().joined(separator: " · ")
        offsetSeconds = zone.secondsFromGMT(for: date)
        offset = Self.offsetLabel(offsetSeconds)
        name = zone.localizedName(for: .generic, locale: locale)
    }

    /// Every timezone the system knows, west to east, then by city.
    public static func all(at date: Date = Date(), locale: Locale = .current) -> [TimeZoneChoice] {
        TimeZone.knownTimeZoneIdentifiers
            .compactMap { TimeZoneChoice(identifier: $0, at: date, locale: locale) }
            .sorted { ($0.offsetSeconds, $0.city) < ($1.offsetSeconds, $1.city) }
    }

    /// "Ho Chi Minh · GMT+7", for the Settings row.
    public var summary: String { "\(city) · \(offset)" }

    /// "GMT", "GMT+7", "GMT+5:30", "GMT−3" (with a true minus sign).
    public static func offsetLabel(_ seconds: Int) -> String {
        guard seconds != 0 else { return "GMT" }
        let sign = seconds > 0 ? "+" : "−"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, rest)
    }

    /// Matches city, region, identifier, the system name, or an offset ("+7", "utc+7").
    /// Every word of the query has to match somewhere.
    public func matches(_ query: String) -> Bool {
        let words = Self.normalized(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = Self.normalized(
            [id, city, region, name ?? "", offset].joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "utc", with: "gmt")
            .folding(options: .diacriticInsensitive, locale: nil)
    }
}
