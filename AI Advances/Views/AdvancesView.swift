import SwiftUI
import Charts

struct AdvancesView: View {
    @Environment(DataStore.self) private var store
    @State private var kind: Kind = .all
    @State private var direction = "All directions"

    enum Kind: String, CaseIterable, Identifiable {
        case all = "Everything"
        case curated = "Highlights"
        case records = "New records"
        case models = "New models"
        var id: String { rawValue }
    }

    typealias Item = FeedItem

    var body: some View {
        let now = Date()
        let all = Feed.items(store.data, now: now)
        let directions = ["All directions"] + Array(Set(all.map(\.direction))).sorted()
        let shown = all.filter { (kind == .all || $0.kind.rawValue == kind.rawValue) && (direction == "All directions" || $0.direction == direction) }

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Latest advances",
                       summary: "Researched highlights, plus new benchmark records and newly listed models detected in the data on every refresh.")

            if let f = Freshness(Freshness.highlights(store.data.advances)) {
                FreshnessNote(freshness: f, what: "Researched highlights run through")
            }

            Card(title: "Highlights and records per month, by direction",
                 subtitle: "What the last year's advances have been about. New model listings are left out because they'd swamp the chart.") {
                monthChart(all.filter { $0.kind != .models && $0.date >= yearsAgo(1, from: now) })
            }

            HStack {
                Picker("Show", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 440).labelsHidden()
                Picker("Direction", selection: $direction) { ForEach(directions, id: \.self) { Text($0).tag($0) } }
                    .frame(maxWidth: 220)
                Spacer()
                Text("\(shown.count) items").foregroundStyle(.secondary)
            }

            if store.data.advances.isEmpty && kind == .curated {
                ContentUnavailableView("No highlights bundled", systemImage: "sparkles")
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { item in
                    row(item)
                    Divider()
                }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(Format.date.string(from: item.date))
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 96, alignment: .leading)
            Image(systemName: symbol(item.kind)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    if let link = item.link.flatMap(URL.init(string:)) { Link(item.title, destination: link).font(.body.weight(.medium)) }
                    else { Text(item.title).font(.body.weight(.medium)) }
                }
                Text(item.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(item.lab) · \(item.direction)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func symbol(_ k: FeedItem.Kind) -> String {
        switch k {
        case .curated: "sparkles"
        case .records: "trophy"
        case .models: "shippingbox"
        }
    }

    private struct MonthCount: Identifiable {
        var id: String { direction + "\(month.timeIntervalSince1970)" }
        let month: Date
        let direction: String
        let count: Int
    }

    private func monthChart(_ items: [Item]) -> some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let grouped = Dictionary(grouping: items) { i in
            MonthKey(month: cal.date(from: cal.dateComponents([.year, .month], from: i.date))!, direction: i.direction)
        }
        let counts = grouped.map { MonthCount(month: $0.key.month, direction: $0.key.direction, count: $0.value.count) }
        let order = Dictionary(grouping: counts, by: \.direction).mapValues { $0.map(\.count).reduce(0, +) }
            .sorted { $0.value > $1.value }.map(\.key)
        return Chart(counts) { c in
            BarMark(x: .value("Month", c.month, unit: .month), y: .value("Items", c.count))
                .foregroundStyle(by: .value("Direction", c.direction))
        }
        .chartForegroundStyleScale(domain: order, range: order.indices.map(Palette.color))
        .chartYAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(Palette.grid)
            AxisValueLabel().foregroundStyle(Palette.muted)
        } }
        .quietAxes()
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
    }

    private struct MonthKey: Hashable {
        let month: Date
        let direction: String
    }
}
