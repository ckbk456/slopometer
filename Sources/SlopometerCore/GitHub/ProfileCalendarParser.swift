import Foundation

/// Parses GitHub's public profile contribution calendar HTML. This page is not a
/// documented API; an empty result means the markup changed and is an error.
public enum ProfileCalendarParser {
    public static func parse(_ html: String) throws -> [CalendarDay: Int] {
        var dayByCellID: [String: CalendarDay] = [:]
        for cell in matches(of: #"<td\b[^>]*>"#, in: html) {
            guard let label = attribute("data-date", in: cell), let day = CalendarDay(label),
                let cellID = attribute("id", in: cell)
            else { continue }
            dayByCellID[cellID] = day
        }

        var counts: [CalendarDay: Int] = [:]
        for tooltip in matches(of: #"<tool-tip\b[^>]*>[^<]*"#, in: html) {
            guard let target = attribute("for", in: tooltip), let day = dayByCellID[target],
                let text = tooltip.split(separator: ">", maxSplits: 1).last
            else { continue }
            counts[day] = try count(in: String(text))
        }
        guard !counts.isEmpty, counts.count == dayByCellID.count else {
            throw GitHubError.malformedResponse
        }
        return counts
    }

    /// "No contributions on …", "1 contribution on …", "1,234 contributions on …".
    static func count(in text: String) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("No contributions") { return 0 }
        let digits = trimmed.prefix { $0.isNumber || $0 == "," }.filter { $0 != "," }
        guard !digits.isEmpty, let value = Int(digits) else { throw GitHubError.malformedResponse }
        return value
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let expression = try! NSRegularExpression(pattern: #"\s\#(name)="([^"]*)""#)
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = expression.firstMatch(in: tag, range: range),
            let value = Range(match.range(at: 1), in: tag)
        else { return nil }
        return String(tag[value])
    }
}
