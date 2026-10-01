import SwiftUI
import Charts

struct ForecastsView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedID = ""
    @State private var hoverTitle: String?

    static let kinds = Forecast.Kind.allCases.map(\.rawValue)

    var body: some View {
        let now = Date()
        let upcoming = store.forecasts.filter { $0.reached == nil && $0.predicted != nil }
            .sorted { $0.predicted! < $1.predicted! }
        // End the axis a little after the last predicted date (at most 7.5 years out); longer ranges run off the edge.
        let axisEnd = min(now.addingTimeInterval(Forecasts.maxYearsOut / 2 * 365.25 * 86_400),
                          (upcoming.last?.predicted ?? now).addingTimeInterval(270 * 86_400))
        let stalled = store.forecasts.filter { $0.reached == nil && $0.predicted == nil }
        let reached = store.forecasts.filter { $0.reached != nil }.sorted { $0.reached! > $1.reached! }
        let shifts = Forecasts.shifts(upcoming, history: store.reconstructedLog + store.liveLog, now: now)
        let selected = upcoming.first { $0.id == selectedID } ?? upcoming.first

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Where the field is going next",
                       summary: "Dated predictions from extrapolating today's trends. Every forecast is recomputed when new data arrives, and each day's set is logged so you can watch them move.")

            if store.forecasts.isEmpty {
                ProgressView("Computing forecasts…")
            } else {
                Card(title: "Outlook", subtitle: "Written from the numbers below; changes when they do.") {
                    Text(Forecasts.outlook(upcoming, shifts: shifts, now: now))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Card(title: "Forecast timeline",
                     subtitle: "Dot: most likely date if the trend holds. Bar: 90% range. Ranges running off the right edge are open-ended.") {
                    timeline(upcoming, now: now, axisEnd: axisEnd)
                    if let t = hoverTitle, let f = upcoming.first(where: { $0.title == t }) {
                        detail(f)
                    } else {
                        Footnote(text: "Hover a row for its current value and how it was fitted.")
                    }
                }

                if !shifts.isEmpty {
                    Card(title: "What moved in the last 3 months",
                         subtitle: "Change in each predicted date since the forecast was computed three months ago. Earlier means the field sped up.") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            ForEach(shifts.prefix(8)) { s in
                                GridRow {
                                    Image(systemName: s.months < 0 ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                                        .foregroundStyle(s.months < 0 ? Palette.color(2) : Palette.color(1))
                                    Text(s.forecast.title)
                                    Text("\(Int(abs(s.months).rounded())) month\(Int(abs(s.months).rounded()) == 1 ? "" : "s") \(s.months < 0 ? "earlier" : "later")")
                                        .foregroundStyle(.secondary).monospacedDigit()
                                    Text("now \(Format.monthYear(s.forecast.predicted!))").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Card(title: "How a forecast has shifted",
                     subtitle: "The predicted date as computed on each date. Circles are recomputed from only the data public then; squares were saved by the app on the day.") {
                    Picker("Forecast", selection: $selectedID) {
                        ForEach(upcoming) { Text($0.title).tag($0.id) }
                    }
                    .frame(maxWidth: 420)
                    if let f = selected { history(f, now: now) }
                }

                HStack(alignment: .top, spacing: 16) {
                    Card(title: "Already happened", subtitle: "Milestones the trends have already crossed.") {
                        ForEach(reached) { f in
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.color(2))
                                Text(f.title)
                                Spacer()
                                Text(Format.monthYear(f.reached!)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                    if !stalled.isEmpty {
                        Card(title: "Stalled or off trend", subtitle: "Milestones the current trend can't date: progress has stopped short of them, or they're too far out.") {
                            ForEach(stalled) { f in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.title)
                                    Text("\(f.current). \(f.note ?? "").").font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                Footnote(text: "Method: compute, task horizon and price use straight-line fits on a log scale (steady exponential change). Benchmarks use an S-curve fitted to the record-setting scores of the last two years, since scores flatten as they near 100%. Ranges come from the uncertainty in the fitted slope; they don't account for breakthroughs, benchmark changes or slowdowns. Extrapolations, not guarantees.")
            }
        }
        .onAppear { if selectedID.isEmpty { selectedID = upcoming.first?.id ?? "" } }
    }

    // MARK: Timeline

    private func timeline(_ fs: [Forecast], now: Date, axisEnd: Date) -> some View {
        Chart(fs) { f in
            RuleMark(xStart: .value("Early", min(f.early ?? f.predicted!, axisEnd)),
                     xEnd: .value("Late", min(f.late ?? axisEnd, axisEnd)),
                     y: .value("Forecast", f.title))
                .lineStyle(StrokeStyle(lineWidth: 7, lineCap: .round))
                .foregroundStyle(by: .value("Kind", f.kind.rawValue))
                .opacity(hoverTitle == nil || hoverTitle == f.title ? 0.45 : 0.15)
            PointMark(x: .value("Predicted", min(f.predicted!, axisEnd)), y: .value("Forecast", f.title))
                .foregroundStyle(by: .value("Kind", f.kind.rawValue))
                .symbolSize(hoverTitle == f.title ? 120 : 70)
                .annotation(position: .trailing, spacing: 6) {
                    Text(Format.monthYear(f.predicted!)).font(.caption).foregroundStyle(.secondary)
                }
            RuleMark(x: .value("Today", now))
                .foregroundStyle(Palette.muted.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(domain: Self.kinds, range: Self.kinds.indices.map(Palette.color))
        .chartXScale(domain: now...axisEnd)
        .chartYAxis { AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(horizontalSpacing: 8).foregroundStyle(Color.primary) } }
        .quietAxes()
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYSelection(value: $hoverTitle)
        .frame(height: CGFloat(fs.count) * 28 + 60)
    }

    private func detail(_ f: Forecast) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(f.target): most likely \(Format.monthYear(f.predicted!)), 90% range \(f.early.map(Format.monthYear) ?? "?") to \(f.late.map(Format.monthYear) ?? "beyond \(Int(Forecasts.maxYearsOut)) years").")
            Text("Now: \(f.current). \(f.basis).").foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    // MARK: History

    private struct HistoryPoint: Identifiable {
        var id: Date { asOf }
        let asOf: Date
        let predicted: Date
        let early: Date
        let late: Date
        let live: Bool
    }

    private func history(_ f: Forecast, now: Date) -> some View {
        let cap = now.addingTimeInterval(Forecasts.maxYearsOut * 365.25 * 86_400)
        let entries = store.reconstructedLog + store.liveLog
        let points = entries.compactMap { e -> HistoryPoint? in
            guard let s = e.forecasts[f.id], let p = s.predicted else { return nil }
            return HistoryPoint(asOf: e.asOf, predicted: p, early: s.early ?? p, late: min(s.late ?? cap, cap), live: !e.reconstructed)
        }
        .sorted { $0.asOf < $1.asOf }
        let maxY = min(points.map(\.late).max() ?? cap, now.addingTimeInterval(10 * 365.25 * 86_400))

        return VStack(alignment: .leading, spacing: 8) {
            // Dates are plotted as fractional years so later dates sit higher on the axis.
            let y = { (d: Date) in Dates.years(d) }
            Chart(points) { p in
                AreaMark(x: .value("Computed on", p.asOf),
                         yStart: .value("Early", y(p.early)), yEnd: .value("Late", y(min(p.late, maxY))))
                    .foregroundStyle(Palette.color(0).opacity(0.15))
                LineMark(x: .value("Computed on", p.asOf), y: .value("Predicted", y(p.predicted)))
                    .foregroundStyle(Palette.color(0))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Computed on", p.asOf), y: .value("Predicted", y(p.predicted)))
                    .foregroundStyle(Palette.color(0))
                    .symbol(by: .value("Source", p.live ? "Saved by the app" : "Recomputed from past data"))
                    .symbolSize(50)
            }
            .chartSymbolScale(domain: ["Recomputed from past data", "Saved by the app"], range: [BasicChartSymbolShape.circle, .square])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYScale(domain: y(points.map(\.early).min() ?? now)...y(maxY))
            .chartYAxis { AxisMarks { v in
                AxisGridLine().foregroundStyle(Palette.grid)
                AxisValueLabel {
                    Text(v.as(Double.self).map { Format.monthYear(Date(timeIntervalSinceReferenceDate: $0 * 365.25 * 86_400)) } ?? "")
                }
                .foregroundStyle(Palette.muted)
            } }
            .quietAxes()
            .frame(height: 240)
            if points.isEmpty {
                Footnote(text: "This milestone wasn't on a forecastable trend in the past year.")
            } else if let first = points.first, let last = points.last {
                let moved = Dates.months(from: first.predicted, to: last.predicted)
                let change = abs(moved) < 1 ? "about the same" : "\(Int(abs(moved).rounded())) months \(moved < 0 ? "earlier" : "later")"
                Footnote(text: "In \(Format.monthYear(first.asOf)) the trend pointed to \(Format.monthYear(first.predicted)); it now points to \(Format.monthYear(last.predicted)), \(change). Saved log: \(store.liveLog.count) day\(store.liveLog.count == 1 ? "" : "s") so far.")
            }
        }
    }
}
