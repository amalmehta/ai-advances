import SwiftUI
import Charts

struct AdvancesView: View {
    @Environment(DataStore.self) private var store
    @State private var kind: Kind = .all
    @State private var direction = "All directions"
    /// What was new when this page opened; it stays marked for the visit after being recorded as seen.
    @State private var shownNew: Set<String> = []

    enum Kind: String, CaseIterable, Identifiable {
        case all = "Everything"
        case new = "New to you"
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
        let shown = all.filter { (kind == .all || $0.kind.rawValue == kind.rawValue || (kind == .new && shownNew.contains($0.id)))
            && (direction == "All directions" || $0.direction == direction) }
        let kinds = Kind.allCases.filter { $0 != .new || !shownNew.isEmpty }

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
                Picker("Show", selection: $kind) {
                    ForEach(kinds) { k in Text(k == .new ? "New to you (\(shownNew.count))" : k.rawValue).tag(k) }
                }
                    .pickerStyle(.segmented).frame(maxWidth: 580).labelsHidden()
                Picker("Direction", selection: $direction) { ForEach(directions, id: \.self) { Text($0).tag($0) } }
                    .frame(maxWidth: 220)
                Spacer()
                Text("\(shown.count) items").foregroundStyle(Palette.text2)
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
        .onAppear {
            shownNew = store.newFeedIDs
            if shownNew.isEmpty && kind == .new { kind = .all }
            store.markFeedSeen()
        }
        // Items that arrive in a refresh while this page is open are new too.
        .onChange(of: store.newFeedIDs) { _, arrived in
            guard !arrived.isEmpty else { return }
            shownNew.formUnion(arrived)
            store.markFeedSeen()
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(Format.date.string(from: item.date))
                .font(.callout).foregroundStyle(Palette.text2).monospacedDigit()
                .frame(width: 96, alignment: .leading)
            Image(systemName: symbol(item.kind)).foregroundStyle(Palette.text2).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    if shownNew.contains(item.id) {
                        Text("New").font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                    if let link = item.link.flatMap(URL.init(string:)) { Link(item.title, destination: link).font(.body.weight(.medium)) }
                    else { Text(item.title).font(.body.weight(.medium)) }
                }
                Text(item.detail).foregroundStyle(Palette.text2).fixedSize(horizontal: false, vertical: true)
                Text("\(item.lab) · \(item.direction)").font(.caption).foregroundStyle(Palette.text2)
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
        .chartSummary("Stacked bar chart of highlights and new records per month over the last year, by direction. Totals: " + order.map { d in "\(d) \(counts.filter { $0.direction == d }.map(\.count).reduce(0, +))" }.joined(separator: ", ") + ".")
    }

    private struct MonthKey: Hashable {
        let month: Date
        let direction: String
    }
}
