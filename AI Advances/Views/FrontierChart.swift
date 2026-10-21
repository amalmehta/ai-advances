import SwiftUI
import Charts

/// Best score so far on each benchmark in an area, as a step line; optionally every result as dots.
struct FrontierChart: View {
    let area: CapabilityArea
    let since: Date
    var showAllResults = false
    var height: CGFloat = 180

    @State private var hoverDate: Date?
    @State private var hoverResult: String?

    private struct Step: Identifiable {
        var id: String { benchmark + "\(date.timeIntervalSince1970)" }
        let benchmark: String
        let date: Date
        let score: Double
        let model: String
    }

    private let labels: [String]
    private let colors: [Color]
    private let steps: [Step]
    private let dots: [BenchmarkResult]

    /// - Parameters:
    ///   - frontiers: record-setting results per benchmark, precomputed by the store.
    ///   - results: every result, needed only for `showAllResults`.
    /// Everything is worked out here, once per input, so hovering only redraws.
    init(area: CapabilityArea, frontiers: [String: [FrontierPoint]], results: [BenchmarkResult] = [],
         since: Date, showAllResults: Bool = false, height: CGFloat = 180) {
        self.area = area
        self.since = since
        self.showAllResults = showAllResults
        self.height = height
        let names = area.benchmarks.filter { frontiers[$0]?.isEmpty == false }
        labels = names.map(Analysis.shortName)
        colors = names.indices.map(Palette.color)
        let now = Date()
        steps = names.flatMap { b -> [Step] in
            let f = frontiers[b] ?? []
            let label = Analysis.shortName(b)
            var out: [Step] = []
            if let start = f.last(where: { $0.date <= since }) {
                out.append(Step(benchmark: label, date: since, score: start.score, model: start.model))
            }
            out += f.filter { $0.date > since }.map { Step(benchmark: label, date: $0.date, score: $0.score, model: $0.model) }
            if let last = out.last { out.append(Step(benchmark: label, date: now, score: last.score, model: last.model)) }
            return out
        }
        let set = Set(names)
        dots = showAllResults ? results.filter { set.contains($0.benchmark) && $0.releaseDate >= since } : []
    }

    var body: some View {
        Chart {
            ForEach(dots) { r in
                PointMark(x: .value("Released", r.releaseDate), y: .value("Score", r.score))
                    .foregroundStyle(by: .value("Benchmark", Analysis.shortName(r.benchmark)))
                    .symbolSize(hoverResult == r.id ? 90 : 22)
                    .opacity(hoverResult == r.id ? 1 : 0.35)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                        if hoverResult == r.id {
                            Tooltip(title: r.modelGroup, lines: [
                                "\(Analysis.shortName(r.benchmark)): \(Format.percent(r.score, digits: 1))",
                                "\(r.organization) · \(Format.date.string(from: r.releaseDate))"])
                        }
                    }
            }
            ForEach(steps) { s in
                LineMark(x: .value("Date", s.date), y: .value("Best score", s.score))
                    .foregroundStyle(by: .value("Benchmark", s.benchmark))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let d = hoverDate, !showAllResults {
                RuleMark(x: .value("Date", d))
                    .foregroundStyle(Palette.muted.opacity(0.6))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        Tooltip(title: Format.date.string(from: d), lines: tooltipLines(at: d, steps: steps))
                    }
            }
        }
        .chartForegroundStyleScale(domain: labels, range: colors)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { v in
                AxisGridLine().foregroundStyle(Palette.grid)
                AxisValueLabel { Text(Format.percent(v.as(Double.self))) }.foregroundStyle(Palette.muted)
            }
        }
        .quietAxes()
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXSelection(value: showAllResults ? .constant(nil) : $hoverDate)
        .chartOverlay { proxy in
            if showAllResults {
                HoverLayer(proxy: proxy, points: dots.map { ($0.id, $0.releaseDate, $0.score) }, selection: $hoverResult, radius: 14)
            }
        }
        .frame(height: height)
        .chartSummary(summary)
        .accessibilityChartDescriptor(chartData)
    }

    private var summary: String {
        "Line chart of the best score so far on \(labels.joined(separator: ", ")) since \(Format.monthYear(since)). Current bests: " + labels.compactMap { l in steps.last { $0.benchmark == l }.map { "\(l) \(Format.percent($0.score)) (\($0.model))" } }.joined(separator: "; ") + "."
    }

    /// Each benchmark's record line, plus every result when they're shown, for VoiceOver and Audio Graphs.
    private var chartData: ChartData {
        let percent: (Double) -> String = { Format.percent($0, digits: 1) }
        var series = labels.map { l in
            ChartData.Series(name: "\(l) best so far", continuous: true,
                             points: steps.filter { $0.benchmark == l }.map { .init(x: ChartData.x($0.date), y: $0.score, label: $0.model) })
        }
        if showAllResults {
            series += Dictionary(grouping: dots, by: { Analysis.shortName($0.benchmark) }).sorted { $0.key < $1.key }.map { l, rs in
                ChartData.Series(name: "\(l) results", continuous: false,
                                 points: rs.sorted { $0.releaseDate < $1.releaseDate }.map { .init(x: ChartData.x($0.releaseDate), y: $0.score, label: $0.modelGroup) })
            }
        }
        return ChartData(title: "\(area.name): best score over time", summary: summary,
                         x: .date("Date"), y: .number("Score", format: percent), series: series)
    }

    private func tooltipLines(at date: Date, steps: [Step]) -> [String] {
        labels.compactMap { label in
            guard let s = steps.last(where: { $0.benchmark == label && $0.date <= date }) else { return nil }
            return "\(label): \(Format.percent(s.score)) · \(s.model)"
        }
    }
}
