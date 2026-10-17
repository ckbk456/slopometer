import Foundation
import SlopometerCore
import Testing

@Suite("Widget sync label")
struct SyncAgeLabelTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        return calendar
    }()
    let locale = Locale(identifier: "en_GB")

    @Test func sameDayShowsClockTimeAndAge() {
        let text = SyncAgeLabel.text(
            synced: date("2026-10-17T14:47:00Z"), now: date("2026-10-17T14:49:30Z"),
            calendar: calendar, locale: locale)
        #expect(text == "Synced 21:47 (00:02 ago)")
    }

    @Test func earlierDayIsNamedAndHoursKeepCounting() {
        let text = SyncAgeLabel.text(
            synced: date("2026-10-16T14:47:00Z"), now: date("2026-10-17T17:00:00Z"),
            calendar: calendar, locale: locale)
        #expect(text.hasPrefix("Synced 16 Oct"))
        #expect(text.hasSuffix("(26:13 ago)"))
    }

    @Test func missingSyncAndClockSkewAreHandled() {
        #expect(SyncAgeLabel.text(synced: nil, now: Date()) == "Not synced yet")
        let now = date("2026-10-17T00:00:00Z")
        #expect(SyncAgeLabel.age(from: now.addingTimeInterval(90), to: now) == "00:00")
    }

    @Test func updatesFallOnMinuteBoundariesFromTheSync() {
        let synced = date("2026-10-17T14:47:20Z")
        let now = date("2026-10-17T14:49:00Z")
        let updates = SyncAgeLabel.updates(synced: synced, from: now, count: 3)
        #expect(
            updates == [
                now, date("2026-10-17T14:49:20Z"), date("2026-10-17T14:50:20Z"),
                date("2026-10-17T14:51:20Z"),
            ])
        #expect(SyncAgeLabel.updates(synced: nil, from: now, count: 3) == [now])
    }
}
