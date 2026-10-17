import Foundation

/// The widget's sync line: the clock time of the last sync and its age as hours and
/// minutes, e.g. "Synced 21:47 (00:02 ago)". The day is named when it was not today,
/// so a widget left over from an earlier day cannot pass for current data.
public enum SyncAgeLabel {
    public static func text(
        synced: Date?, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        guard let synced else { return "Not synced yet" }
        var format = Date.FormatStyle(
            locale: locale, calendar: calendar, timeZone: calendar.timeZone
        )
        .hour().minute()
        if !calendar.isDate(synced, inSameDayAs: now) { format = format.month(.abbreviated).day() }
        return "Synced \(synced.formatted(format)) (\(age(from: synced, to: now)) ago)"
    }

    /// Whole hours and minutes elapsed, zero-padded; never negative.
    public static func age(from synced: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(synced) / 60))
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// When the label next changes: the minute boundaries counted from the sync.
    public static func updates(synced: Date?, from now: Date, count: Int) -> [Date] {
        guard let synced, count > 0 else { return [now] }
        let elapsed = max(0, now.timeIntervalSince(synced))
        let next = synced.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
        return [now] + (0..<count).map { next.addingTimeInterval(Double($0) * 60) }
    }
}
