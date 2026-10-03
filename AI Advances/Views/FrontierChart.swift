import SwiftUI
import Charts

/// Best score so far on each benchmark in an area, as a step line; optionally every result as dots.
struct FrontierChart: View {
    let area: CapabilityArea
    let results: [BenchmarkResult]
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

    private var names: [String] { area.benchmarks.filter { b in results.contains { $0.benchmark == b } } }
    private var labels: [String] { names.map(Analysis.shortName) }
    private var colors: [Color] { names.indices.map(Palette.color) }

    private var steps: [Step] {
        let now = Date()
        return names.flatMap { b -> [Step] in
            let f = Analysis.frontier(results, benchmark: b)
            let label = Analysis.shortName(b)
            var out: [Step] = []
            if let start = f.last(where: { $0.date <= since }) {
                out.append(Step(benchmark: label, date: since, score: start.score, model: start.model))
            }
            out += f.filter { $0.date > since }.map { Step(benchmark: label, date: $0.date, score: $0.score, model: $0.model) }
            if let last = out.last { out.append(Step(benchmark: label, date: now, score: last.score, model: last.model)) }
            return out
        }
    }

    private var dots: [BenchmarkResult] {
        guard showAllResults else { return [] }
        let set = Set(names)
        return results.filter { set.contains($0.benchmark) && $0.releaseDate >= since }
    }

    var body: some View {
        let steps = steps
        let dots = dots
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
        .chartSummary("Line chart of the best score so far on \(labels.joined(separator: ", ")) since \(Format.monthYear(since)). Current bests: " + labels.compactMap { l in steps.last { $0.benchmark == l }.map { "\(l) \(Format.percent($0.score)) (\($0.model))" } }.joined(separator: "; ") + ".")
    }

    private func tooltipLines(at date: Date, steps: [Step]) -> [String] {
        labels.compactMap { label in
            guard let s = steps.last(where: { $0.benchmark == label && $0.date <= date }) else { return nil }
            return "\(label): \(Format.percent(s.score)) · \(s.model)"
        }
    }
}
