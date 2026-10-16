public enum MeasurementError: Error, Equatable, Sendable {
    case invalidWindow
    case negativeCount
    case emptySeries
}

/// Inputs are consecutive calendar-day buckets prepared by the caller.
/// Nil represents unknown data, not a zero-activity day.
public enum MovingAverage {
    public static func trailing(_ counts: [Int?], window: Int) throws -> [Double?] {
        guard window > 0 else { throw MeasurementError.invalidWindow }
        guard counts.allSatisfy({ value in value.map { $0 >= 0 } ?? true }) else {
            throw MeasurementError.negativeCount
        }

        return counts.indices.map { index in
            guard index + 1 >= window else { return nil }
            let values = counts[(index + 1 - window)...index].compactMap { $0 }
            guard values.count == window else { return nil }
            return values.reduce(0.0) { $0 + Double($1) } / Double(window)
        }
    }
}
