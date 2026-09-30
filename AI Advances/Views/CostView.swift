import SwiftUI
import Charts

struct CostView: View {
    @Environment(DataStore.self) private var store
    @State private var benchmark = "GPQA diamond"
    @State private var threshold = 0.8
    @State private var hoverStep: String?
    @State private var hoverDot: String?

    private struct Dot: Identifiable {
        var id: String { name }
        let name: String
        let lab: String
        let price: Double
        let score: Double
        let released: Date
    }

    var body: some View {
        let profiles = store.profiles
        let steps = Analysis.cheapestOverTime(profiles, benchmark: benchmark, threshold: threshold)
        let fit = ExpFit.fit(steps.map { ($0.date, $0.price) })
        let dots = profiles.compactMap { p -> Dot? in
            guard let s = p.score(benchmark), let l = p.listing, !l.isFree else { return nil }
            return Dot(name: p.name, lab: p.lab, price: l.blendedPrice, score: s, released: p.released)
        }
        let best = Analysis.frontierValue(Analysis.frontier(store.data.results, benchmark: benchmark), at: Date()) ?? 1

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Cost",
                       summary: "How fast a given level of capability gets cheaper. Pick a benchmark and a score; the line shows the cheapest model that had reached it by each date.")

            HStack(spacing: 16) {
                Picker("Benchmark", selection: $benchmark) {
                    ForEach(Analysis.keyBenchmarks, id: \.name) { Text($0.label).tag($0.name) }
                }
                .frame(maxWidth: 220)
                Text("Score at least").foregroundStyle(.secondary)
                Slider(value: $threshold, in: 0.1...0.95, step: 0.05).frame(maxWidth: 220)
                Text(Format.percent(threshold)).monospacedDigit().frame(width: 44, alignment: .leading)
                Text("Current best: \(Format.percent(best))").foregroundStyle(.secondary)
            }
            .onChange(of: benchmark) {
                threshold = max(0.1, (best * 0.75 / 0.05).rounded() * 0.05)
            }

            Card(title: "Cheapest price to reach \(Format.percent(threshold)) on \(Analysis.shortName(benchmark))",
                 subtitle: fit.map { f in steps.count >= 3 ? "Falling about \(String(format: "%.0f", 1 / f.factorPerYear))× per year (exponential fit over \(steps.count) price drops)." : "" } ?? "Too few price drops yet to fit a trend.") {
                if steps.isEmpty {
                    Text("No model with a listed price has reached this score yet. Lower the threshold.").foregroundStyle(.secondary).frame(height: 120)
                } else {
                    Chart {
                        ForEach(steps) { s in
                            LineMark(x: .value("Date", s.date), y: .value("Price", s.price))
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(Palette.color(0))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            PointMark(x: .value("Date", s.date), y: .value("Price", s.price))
                                .foregroundStyle(Palette.color(0))
                                .symbolSize(hoverStep == s.id ? 110 : 50)
                                .annotation(position: .topTrailing, alignment: .leading, spacing: 2) {
                                    if hoverStep == s.id {
                                        Tooltip(title: s.model, lines: ["\(Format.price(s.price)) / M tokens", "\(Analysis.shortName(benchmark)): \(Format.percent(s.score, digits: 1))", Format.date.string(from: s.date)])
                                    } else {
                                        Text(s.model).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                        }
                        if let last = steps.last {
                            RuleMark(xStart: .value("From", last.date), xEnd: .value("To", Date()), y: .value("Price", last.price))
                                .foregroundStyle(Palette.color(0).opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                    }
                    .chartYScale(type: .log)
                    .chartYAxis { AxisMarks { v in
                        AxisGridLine().foregroundStyle(Palette.grid)
                        AxisValueLabel { Text(v.as(Double.self).map(Format.price) ?? "") }.foregroundStyle(Palette.muted)
                    } }
                    .quietAxes()
                    .chartOverlay { proxy in HoverLayer(proxy: proxy, points: steps.map { ($0.id, $0.date, $0.price) }, selection: $hoverStep) }
                    .frame(height: 300)
                }
            }

            Card(title: "Price against score, \(Analysis.shortName(benchmark))",
                 subtitle: "Every model with both a score and a listed price. Up and to the left is better value.") {
                Chart(dots) { d in
                    PointMark(x: .value("Price", d.price), y: .value("Score", d.score))
                        .foregroundStyle(d.released >= yearsAgo(0.5) ? Palette.color(1) : Palette.color(0))
                        .symbolSize(hoverDot == d.id ? 110 : 40)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                            if hoverDot == d.id {
                                Tooltip(title: d.name, lines: ["\(d.lab) · \(Format.date.string(from: d.released))", "\(Format.percent(d.score, digits: 1)) at \(Format.price(d.price)) / M tokens"])
                            }
                        }
                }
                .chartXScale(type: .log)
                .chartXAxis { AxisMarks { v in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel { Text(v.as(Double.self).map(Format.price) ?? "") }.foregroundStyle(Palette.muted)
                } }
                .chartYAxis { AxisMarks { v in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel { Text(Format.percent(v.as(Double.self))) }.foregroundStyle(Palette.muted)
                } }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                guard case .active(let loc) = phase, let plot = proxy.plotFrame else { hoverDot = nil; return }
                                let o = geo[plot].origin
                                hoverDot = dots.min { a, b in
                                    distance(a, loc, o, proxy) < distance(b, loc, o, proxy)
                                }.flatMap { distance($0, loc, o, proxy) < 30 ? $0.id : nil }
                            }
                    }
                }
                .frame(height: 320)
                HStack(spacing: 16) {
                    LegendItem(label: "Released in the last 6 months", color: Palette.color(1))
                    LegendItem(label: "Older", color: Palette.color(0))
                }
                .font(.caption)
                Footnote(text: "Prices are today's OpenRouter list prices (3:1 input:output blend), so older models show their current, often reduced, price.")
            }
        }
    }

    private func distance(_ d: Dot, _ loc: CGPoint, _ origin: CGPoint, _ proxy: ChartProxy) -> CGFloat {
        guard let x = proxy.position(forX: d.price), let y = proxy.position(forY: d.score) else { return .infinity }
        return hypot(x + origin.x - loc.x, y + origin.y - loc.y)
    }
}
