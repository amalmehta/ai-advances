import SwiftUI
import Charts

struct ComputeView: View {
    @Environment(DataStore.self) private var store
    @State private var sinceYear = 2018
    @State private var hover: String?

    var body: some View {
        let since = Dates.parse("\(sinceYear)-01-01")!
        let models = store.data.notable.filter { $0.date >= since && $0.computeFLOP != nil }
        let fit = Analysis.computeFit(store.data.notable, since: max(since, Dates.parse("2020-01-01")!))
        let largest = store.data.notable.filter { $0.computeFLOP != nil }.sorted { $0.computeFLOP! > $1.computeFLOP! }.prefix(10)

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Compute",
                       summary: "Training compute of notable AI models, from Epoch AI. Frontier models are those among the ten largest training runs when they were released.")

            Picker("Since", selection: $sinceYear) {
                Text("2012").tag(2012)
                Text("2018").tag(2018)
                Text("2022").tag(2022)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)

            Card(title: "Training compute over time",
                 subtitle: fit.map { "Frontier runs grow about \(String(format: "%.1f", $0.factorPerYear))× per year, doubling every \(Format.months($0.doublingMonths)) (dashed line, fit since \(max(sinceYear, 2020)))." }) {
                Chart {
                    ForEach(models) { m in
                        PointMark(x: .value("Published", m.date), y: .value("FLOP", m.computeFLOP!))
                            .foregroundStyle(m.isFrontier ? Palette.color(1) : Palette.color(0))
                            .opacity(hover == m.id ? 1 : m.isFrontier ? 0.9 : 0.35)
                            .symbolSize(hover == m.id ? 100 : m.isFrontier ? 40 : 20)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                                if hover == m.id {
                                    Tooltip(title: m.name, lines: [m.organization, Format.date.string(from: m.date), Format.flop(m.computeFLOP!) + " FLOP"])
                                }
                            }
                    }
                    if let fit {
                        let start = max(since, Dates.parse("2020-01-01")!)
                        ForEach([start, Date()], id: \.self) { d in
                            LineMark(x: .value("Published", d), y: .value("FLOP", fit.value(at: d)), series: .value("Series", "Fit"))
                                .foregroundStyle(Palette.muted)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                }
                .chartYScale(type: .log)
                .chartYAxis { AxisMarks(values: stride(from: 12.0, through: 30.0, by: 2.0).map { pow(10, $0) }) { v in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel { Text(v.as(Double.self).map { "10^\(Int(log10($0).rounded()))" } ?? "") }.foregroundStyle(Palette.muted)
                } }
                .quietAxes()
                .chartOverlay { proxy in HoverLayer(proxy: proxy, points: models.map { ($0.id, $0.date, $0.computeFLOP!) }, selection: $hover, radius: 12) }
                .frame(height: 380)
                HStack(spacing: 16) {
                    LegendItem(label: "Frontier model", color: Palette.color(1))
                    LegendItem(label: "Other notable model", color: Palette.color(0))
                    LegendItem(label: "Trend", color: Palette.muted, line: true)
                }
                .font(.caption)
            }

            Card(title: "Largest training runs", subtitle: "Estimated by Epoch AI from disclosures, hardware and timing; most labs don't publish these figures.") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(Array(largest.enumerated()), id: \.element.id) { i, m in
                        GridRow {
                            Text("\(i + 1)").foregroundStyle(.secondary).monospacedDigit()
                            Text(m.name)
                            Text(m.organization).foregroundStyle(.secondary).lineLimit(1)
                            Text(Format.date.string(from: m.date)).foregroundStyle(.secondary).monospacedDigit()
                            Text(Format.flop(m.computeFLOP!) + " FLOP").monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}
