import Foundation

/// A calendar date with no time or timezone. Day buckets are derived by the caller's
/// chosen timezone; the value itself only names the date.
public struct CalendarDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = Self.utcCalendar.date(from: components) else { return nil }
        let check = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a canonical `YYYY-MM-DD` label.
    public init?(_ label: String) {
        let parts = label.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The calendar day containing `date` in `timeZone`, including daylight-saving days.
    public static func containing(_ date: Date, in timeZone: TimeZone) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: parts.year!, month: parts.month!, day: parts.day!)!
    }

    /// The instant at which this day begins in `timeZone`.
    public func start(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(
            for: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!)
    }

    public func adding(days: Int) -> CalendarDay {
        let date = Self.utcCalendar.date(
            from: DateComponents(year: year, month: month, day: day))!
        let moved = Self.utcCalendar.date(byAdding: .day, value: days, to: date)!
        return Self.containing(moved, in: Self.utcCalendar.timeZone)
    }

    /// Consecutive days from `start` through `end`; empty when `end` precedes `start`.
    public static func range(from start: CalendarDay, through end: CalendarDay) -> [CalendarDay] {
        var days: [CalendarDay] = []
        var current = start
        while current <= end {
            days.append(current)
            current = current.adding(days: 1)
        }
        return days
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension CalendarDay: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let label = try container.decode(String.self)
        guard let day = CalendarDay(label) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid calendar day \(label)")
        }
        self = day
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
