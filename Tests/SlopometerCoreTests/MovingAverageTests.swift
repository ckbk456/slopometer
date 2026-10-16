import SlopometerCore
import Testing

@Suite("Trailing calendar-day averages")
struct MovingAverageTests {
    @Test func zeroDaysParticipateInTheDenominator() throws {
        #expect(try MovingAverage.trailing([0, 3, 0, 3], window: 3) == [nil, nil, 1, 2])
    }

    @Test func unknownDaysMakeTheWindowUnknown() throws {
        #expect(
            try MovingAverage.trailing([2, nil, 4, 6, 8], window: 3)
                == [nil, nil, nil, nil, 6]
        )
    }

    @Test func insufficientHistoryDoesNotInventAnAverage() throws {
        #expect(try MovingAverage.trailing([4, 2], window: 7) == [nil, nil])
        #expect(try MovingAverage.trailing([], window: 7).isEmpty)
    }

    @Test func invalidInputsAreRejected() {
        #expect(throws: MeasurementError.invalidWindow) {
            try MovingAverage.trailing([1, 2], window: 0)
        }
        #expect(throws: MeasurementError.negativeCount) {
            try MovingAverage.trailing([1, -1], window: 2)
        }
    }
}
