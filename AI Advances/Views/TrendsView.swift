import SwiftUI
import Charts

struct TrendsView: View {
    @Environment(DataStore.self) private var store
    @State private var windowMonths = 12
    @State private var hoverArea: String?

    private var data: Dataset { store.data }

    var body: some View {
        let now = Date()
        let momentum = data.areas.compactMap {
            Analysis.momentum(area: $0, results: data.results, infos: data.benchmarks, now: now, months: windowMonths)
        }
        .sorted { $0.gapClosed > $1.gapClosed }

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Where AI is heading",
                       summary: "The four long-run trends, and which capabilities are moving fastest. Everything here recalculates when new data arrives.")

            tiles(now: now)

            Card(title: "Where progress is fastest",
                 subtitle: "Share of the remaining headroom closed on each area's benchmarks, averaged. 100% would mean the benchmarks are solved.") {
                Picker("Window", selection: $windowMonths) {
                    Text("Last 6 months").tag(6)
                    Text("Last 12 months").tag(12)
                    Text("Last 24 months").tag(24)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .labelsHidden()

                Chart(momentum) { m in
                    BarMark(x: .value("Headroom closed", m.gapClosed), y: .value("Area", m.area), height: .fixed(18))
                        .foregroundStyle(Palette.color(0).opacity(hoverArea == nil || hoverArea == m.area ? 1 : 0.5))
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                        .annotation(position: .trailing) {
                            Text("\(Format.percent(m.gapClosed)) · \(String(format: "%+.0f", m.pointsGained)) pts")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                }
                .chartXScale(domain: 0...1.15)
                .chartXAxis {
                    AxisMarks(values: [0, 0.25, 0.5, 0.75, 1]) { v in
                        AxisGridLine().foregroundStyle(Palette.grid)
                        AxisValueLabel { Text(Format.percent(v.as(Double.self))) }.foregroundStyle(Palette.muted)
                    }
                }
                .chartYAxis { AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(horizontalSpacing: 8).foregroundStyle(Color.primary).font(.callout) } }
                .chartYSelection(value: $hoverArea)
                .frame(height: CGFloat(momentum.count) * 34 + 30)

                if let area = hoverArea, let a = data.areas.first(where: { $0.name == area }),
                   let m = momentum.first(where: { $0.area == area }) {
                    Footnote(text: "\(a.name): \(a.summary) Based on \(m.benchmarksUsed) benchmark\(m.benchmarksUsed == 1 ? "" : "s"): \(a.benchmarks.map(Analysis.shortName).joined(separator: ", ")).")
                } else {
                    Footnote(text: "Hover a bar for the benchmarks behind it. Benchmarks newer than the window count from their first result.")
                }
            }

            Text("Frontier by capability area").font(.title2.weight(.semibold)).padding(.top, 4)
            Text("Best score so far on each benchmark since January 2024. Hover for the model holding each record.")
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 16)], spacing: 16) {
                ForEach(data.areas) { area in
                    Card(title: area.name, subtitle: area.summary) {
                        FrontierChart(area: area, results: data.results, since: Dates.parse("2024-01-01")!)
                    }
                }
            }
        }
    }

    @ViewBuilder private func tiles(now: Date) -> some View {
        let compute = Analysis.computeFit(data.notable, since: Dates.parse("2020-01-01")!)
        let horizons = Analysis.horizonFrontier(data.horizons)
        let horizonFit = ExpFit.fit(horizons.filter { $0.releaseDate >= Dates.parse("2023-01-01")! }.map { ($0.releaseDate, $0.minutes) })
        let price = Analysis.cheapestOverTime(store.profiles, benchmark: "GPQA diamond", threshold: 0.8)
        let maxContext = data.listed.map(\.contextLength).max() ?? 0
        let recentMedian = Analysis.medianContextByQuarter(data.listed, since: yearsAgo(1, from: now)).last?.1

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
            StatTile(label: "Training compute",
                     value: compute.map { String(format: "%.1f× / year", $0.factorPerYear) } ?? "–",
                     detail: compute.map { "Frontier training runs double every \(Format.months($0.doublingMonths)) (fit since 2020, \($0.n) models)." } ?? "",
                     symbol: "cpu")
            StatTile(label: "Longest task AI can do",
                     value: horizons.last.map { Format.minutes($0.minutes) } ?? "–",
                     detail: (horizons.last.map { "\($0.modelGroup), METR 50% time horizon. " } ?? "")
                        + (horizonFit.map { "Doubles every \(Format.months($0.doublingMonths))." } ?? ""),
                     symbol: "timer")
            StatTile(label: "Price of GPQA ≥ 80%",
                     value: price.last.map { Format.price($0.price) } ?? "–",
                     detail: priceDetail(price),
                     symbol: "dollarsign.circle")
            StatTile(label: "Largest context window",
                     value: Format.tokens(maxContext) + " tokens",
                     detail: recentMedian.map { "Median for models listed this quarter: \(Format.tokens(Int($0)))." } ?? "",
                     symbol: "text.page")
        }
    }

    private func priceDetail(_ steps: [PriceStep]) -> String {
        guard let first = steps.first, let last = steps.last else { return "No priced model has reached 80% yet." }
        if steps.count == 1 { return "Per million tokens, \(last.model), the only priced model at this level." }
        let factor = first.price / last.price
        return "Per million tokens, \(last.model). \(String(format: "%.0f", factor))× cheaper than the first model to get there, \(first.model)."
    }
}
