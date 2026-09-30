import SwiftUI
import Charts

struct ContextView: View {
    @Environment(DataStore.self) private var store
    @State private var hover: String?
    @State private var hoverQuarter: Date?

    var body: some View {
        let since = Dates.parse("2024-01-01")!
        let listed = store.data.listed.filter { $0.created >= since && $0.contextLength > 0 }
        let frontier = Analysis.contextFrontier(store.data.listed).filter { $0.created >= since }
        let medians = Analysis.medianContextByQuarter(store.data.listed, since: since)
        let shares = Analysis.modalityShares(store.data.listed, since: since)
        let labels = Analysis.modalities.map(\.label)

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Context & Modalities",
                       summary: "How much text models can take in at once, and which kinds of input and output they handle. From every model listed on OpenRouter since 2024.")

            Card(title: "Context window by release", subtitle: "Each dot is a model. The line is the median for models listed that quarter.") {
                Chart {
                    ForEach(listed) { m in
                        PointMark(x: .value("Listed", m.created), y: .value("Context", Double(m.contextLength)))
                            .foregroundStyle(Palette.color(0))
                            .opacity(hover == m.id ? 1 : 0.4)
                            .symbolSize(hover == m.id ? 90 : 18)
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                                if hover == m.id {
                                    Tooltip(title: m.name, lines: ["\(m.lab) · \(Format.date.string(from: m.created))", "\(Format.tokens(m.contextLength)) tokens"])
                                }
                            }
                    }
                    ForEach(medians, id: \.0) { q, v in
                        LineMark(x: .value("Quarter", q.addingTimeInterval(45 * 86_400)), y: .value("Median", v))
                            .foregroundStyle(Palette.color(1))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .symbol(.circle)
                    }
                }
                .chartYScale(type: .log)
                .chartYAxis { AxisMarks(values: [4_096, 32_768, 131_072, 1_000_000, 10_000_000]) { v in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel { Text(v.as(Double.self).map { Format.tokens(Int($0)) } ?? "") }.foregroundStyle(Palette.muted)
                } }
                .quietAxes()
                .chartOverlay { proxy in HoverLayer(proxy: proxy, points: listed.map { ($0.id, $0.created, Double($0.contextLength)) }, selection: $hover, radius: 12) }
                .frame(height: 320)
                HStack(spacing: 16) {
                    LegendItem(label: "Model", color: Palette.color(0))
                    LegendItem(label: "Quarterly median", color: Palette.color(1), line: true)
                }
                .font(.caption)
                if let top = frontier.last {
                    Footnote(text: "Largest so far: \(top.name) (\(top.lab)) at \(Format.tokens(top.contextLength)) tokens, listed \(Format.date.string(from: top.created)).")
                }
            }

            Card(title: "Which modalities new models support",
                 subtitle: "Share of models first listed each quarter that accept or produce each kind of media.") {
                Chart(shares) { s in
                    LineMark(x: .value("Quarter", s.quarterStart), y: .value("Share", s.share))
                        .foregroundStyle(by: .value("Modality", s.modality))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .symbol(by: .value("Modality", s.modality))
                    if let q = hoverQuarter, Analysis.quarterStart(q) == s.quarterStart {
                        RuleMark(x: .value("Quarter", s.quarterStart))
                            .foregroundStyle(Palette.muted.opacity(0.4))
                    }
                }
                .chartForegroundStyleScale(domain: labels, range: labels.indices.map(Palette.color))
                .chartYScale(domain: 0...1)
                .chartYAxis { AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { v in
                    AxisGridLine().foregroundStyle(Palette.grid)
                    AxisValueLabel { Text(Format.percent(v.as(Double.self))) }.foregroundStyle(Palette.muted)
                } }
                .quietAxes()
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXSelection(value: $hoverQuarter)
                .frame(height: 280)
                if let q = hoverQuarter {
                    let rows = shares.filter { $0.quarterStart == Analysis.quarterStart(q) }
                    if let first = rows.first {
                        Footnote(text: "\(first.quarter), \(first.count) models: " + rows.map { "\($0.modality) \(Format.percent($0.share))" }.joined(separator: " · "))
                    }
                } else {
                    Footnote(text: "Hover for the exact shares. Models later removed from OpenRouter aren't counted, so older quarters are thinner.")
                }
            }
        }
    }
}
