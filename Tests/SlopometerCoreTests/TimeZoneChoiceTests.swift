import Foundation
import SlopometerCore
import Testing

@Suite("Timezone choices")
struct TimeZoneChoiceTests {
    let date = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!
    let locale = Locale(identifier: "en_US")

    func choice(_ id: String) throws -> TimeZoneChoice {
        try #require(TimeZoneChoice(identifier: id, at: date, locale: locale))
    }

    @Test func namesAreReadable() throws {
        let saigon = try choice("Asia/Ho_Chi_Minh")
        #expect(saigon.city == "Ho Chi Minh")
        #expect(saigon.region == "Asia")
        #expect(saigon.offset == "GMT+7")
        #expect(saigon.summary == "Ho Chi Minh · GMT+7")
        #expect(try choice("America/Argentina/Buenos_Aires").region == "America · Argentina")
    }

    @Test func offsetsIncludeHalfHoursAndTheMinusSign() throws {
        #expect(try choice("Asia/Kolkata").offset == "GMT+5:30")
        #expect(try choice("America/New_York").offset == "GMT−5")
        #expect(TimeZoneChoice.offsetLabel(0) == "GMT")
        #expect(TimeZoneChoice.offsetLabel(20_700) == "GMT+5:45")
    }

    @Test func daylightSavingFollowsTheDate() throws {
        let july = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!
        let newYork = try #require(TimeZoneChoice(identifier: "America/New_York", at: july))
        #expect(newYork.offset == "GMT−4")
    }

    @Test func searchMatchesCitiesIdentifiersNamesAndOffsets() throws {
        let saigon = try choice("Asia/Ho_Chi_Minh")
        #expect(saigon.matches("ho chi"))
        #expect(saigon.matches("Ho_Chi_Minh"))
        #expect(saigon.matches("asia minh"))
        #expect(saigon.matches("+7"))
        #expect(saigon.matches("UTC+7"))
        #expect(saigon.matches(""))
        #expect(!saigon.matches("tokyo"))
        #expect(try choice("America/New_York").matches("-5"))
        #expect(try choice("America/Sao_Paulo").matches("são"))
    }

    @Test func theListRunsWestToEast() {
        let all = TimeZoneChoice.all(at: date, locale: locale)
        #expect(all.count > 300)
        #expect(zip(all, all.dropFirst()).allSatisfy { $0.offsetSeconds <= $1.offsetSeconds })
        #expect(all.contains { $0.id == "Asia/Ho_Chi_Minh" })
    }
}
