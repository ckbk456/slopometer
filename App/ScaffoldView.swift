import Charts
import SlopometerCore
import SwiftUI

private enum ChartStyle: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case columns = "Columns"
    case line = "Line"

    var id: String { rawValue }
}

private struct SampleDay: Identifiable {
    let id: Int
    let count: Int
    let average: Double?
}

struct ScaffoldView: View {
    @State private var style: ChartStyle = .grid

    private static let counts = [
        0, 1, 3, 0, 2, 5, 1, 0, 2, 4, 3, 0, 1, 2, 6, 3, 1, 0, 4, 2, 3,
        1, 0, 2, 5, 4, 2, 1, 3, 6, 2, 0, 4, 3, 1, 2, 3, 5, 0, 1, 4, 2,
    ]

    private let days: [SampleDay] = {
        let counts = ScaffoldView.counts
        let averages =
            (try? MovingAverage.trailing(counts.map(Optional.some), window: 7))
            ?? Array(repeating: nil, count: counts.count)
        return counts.indices.map {
            SampleDay(id: $0, count: counts[$0], average: averages[$0])
        }
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Slopometer")
                        .font(.largeTitle.weight(.semibold))
                    Text("Your daily slop, quantified.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Sample data", systemImage: "testtube.2")
                    .font(.caption)
                    .padding(8)
                    .background(.quaternary, in: Capsule())
            }

            Picker("Chart", selection: $style) {
                ForEach(ChartStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if style == .grid {
                    LazyHGrid(
                        rows: Array(repeating: GridItem(.fixed(18), spacing: 5), count: 7),
                        alignment: .top,
                        spacing: 5
                    ) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    Color.green.opacity(
                                        day.count == 0 ? 0.1 : Double(day.count) / 6)
                                )
                                .frame(width: 22, height: 18)
                                .help("Sample day \(day.id + 1): \(day.count) contributions")
                                .accessibilityLabel("Sample day \(day.id + 1)")
                                .accessibilityValue("\(day.count) contributions")
                        }
                    }
                } else {
                    Chart(days) { day in
                        if style == .columns {
                            BarMark(
                                x: .value("Sample day", day.id + 1), y: .value("Count", day.count)
                            )
                            .foregroundStyle(.green)
                        } else {
                            LineMark(
                                x: .value("Sample day", day.id + 1),
                                y: .value("Count", day.count),
                                series: .value("Series", "Daily")
                            )
                            .foregroundStyle(.green)
                        }
                        if let average = day.average {
                            LineMark(
                                x: .value("Sample day", day.id + 1),
                                y: .value("Count", average),
                                series: .value("Series", "7-day average")
                            )
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                    }
                    .chartYScale(domain: 0...7)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity, alignment: .leading)

            if style != .grid {
                Label("7-day sample average", systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text("Development preview · GitHub connection and PR goals are planned.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(minWidth: 540, minHeight: 380)
    }
}
