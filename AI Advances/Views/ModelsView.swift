import SwiftUI
import Charts

struct ModelsView: View {
    static let maxCompare = 4

    @Environment(DataStore.self) private var store
    @SceneStorage("models.search") private var search = ""
    @SceneStorage("models.lab") private var lab = "All labs"
    @SceneStorage("models.recentOnly") private var recentOnly = true
    @State private var selection: Set<ModelRow.ID> = []
    /// The selection in the order models were picked, so each keeps its color in the comparison.
    @State private var order: [String] = []
    @State private var hitCap = false
    @State private var sortOrder = [KeyPathComparator(\ModelRow.released, order: .reverse)]

    struct ModelRow: Identifiable {
        var id: String { profile.name }
        let profile: ModelProfile
        /// Benchmark names behind the score columns.
        let keys: [String]
        var name: String { profile.name }
        var lab: String { profile.lab }
        var released: Date { profile.released }
        var price: Double { profile.listing?.blendedPrice ?? .infinity }
        var context: Int { profile.listing?.contextLength ?? 0 }
        var horizon: Double { profile.horizonMinutes ?? -1 }
        func score(_ i: Int) -> Double { profile.score(keys[i]) ?? -1 }
        var s0: Double { score(0) }
        var s1: Double { score(1) }
        var s2: Double { score(2) }
        var s3: Double { score(3) }
        var s4: Double { score(4) }
        var s5: Double { score(5) }
        var s6: Double { score(6) }
    }

    private var filtersActive: Bool { !search.isEmpty || lab != "All labs" || recentOnly }

    var body: some View {
        let profiles = store.profiles
        let keys = store.derived.keyBenchmarks.map(\.name)
        let labs = Dictionary(grouping: profiles.filter { !$0.lab.isEmpty }, by: \.lab).sorted { $0.value.count > $1.value.count }.prefix(14).map(\.key)
        let cutoff = yearsAgo(1)
        let rows = profiles
            .filter { !recentOnly || $0.released >= cutoff }
            .filter { lab == "All labs" || $0.lab == lab }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.lab.localizedCaseInsensitiveContains(search) }
            .filter { p in keys.contains { p.score($0) != nil } || p.horizonMinutes != nil }
            .map { ModelRow(profile: $0, keys: keys) }
            .sorted(using: sortOrder)
        let visible = Set(rows.map(\.id))
        let picked = order.compactMap { name in profiles.first { $0.name == name } }

        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Models",
                       summary: "What each model can do: its best score on the key benchmarks, with price and context window where the model is sold through an API.")

            HStack {
                TextField("Search models or labs", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Lab", selection: $lab) {
                    Text("All labs").tag("All labs")
                    ForEach(labs, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 240)
                Toggle("Released in the last year", isOn: $recentOnly)
                Spacer()
                Text(counted(rows.count, "model")).foregroundStyle(Palette.text2)
            }

            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No models match", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(search.isEmpty ? "Try another lab, or include older models." : "Nothing matches “\(search)” with these filters.")
                } actions: {
                    if filtersActive {
                        Button("Clear Filters") { search = ""; lab = "All labs"; recentOnly = false }
                    }
                }
                .frame(height: 520)
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Model", value: \.name) { r in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.name)
                            Text(r.lab).font(.caption).foregroundStyle(Palette.text2)
                        }
                    }
                    .width(min: 140, ideal: 160)
                    TableColumn("Released", value: \.released) { r in Text(Format.date.string(from: r.released)).monospacedDigit() }
                        .width(min: 78, ideal: 84)
                    TableColumn("$ / M tokens", value: \.price) { r in
                        Text(r.price.isFinite ? Format.price(r.price) : "–").monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Context", value: \.context) { r in Text(r.context > 0 ? Format.tokens(r.context) : "–").monospacedDigit() }
                        .width(min: 56, ideal: 64)
                    Group {
                        scoreColumn(0, \.s0)
                        scoreColumn(1, \.s1)
                        scoreColumn(2, \.s2)
                        scoreColumn(3, \.s3)
                        scoreColumn(4, \.s4)
                        scoreColumn(5, \.s5)
                        scoreColumn(6, \.s6)
                    }
                }
                .frame(height: 520)
            }

            Footnote(text: (hitCap ? "You can compare up to \(Self.maxCompare) models at once. " : "")
                     + "Price is a 3:1 blend of input and output price per million tokens, from OpenRouter; it shows only when the names match. Scores are the best across reasoning-effort settings, from Epoch AI. Select a row for the full profile, or ⌘-click up to \(Self.maxCompare) models to compare them.")

            // Below the table rather than in an inspector: an inspector inside the split view's
            // detail column left the whole page blank.
            if picked.count == 1 {
                ModelDetail(profile: picked[0], infos: store.data.benchmarks)
            } else if picked.count > 1 {
                ModelComparison(models: picked, infos: store.data.benchmarks) { selection = [] }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: selection) { old, new in
            if new.count > Self.maxCompare {
                selection = old
                hitCap = true
                return
            }
            hitCap = false
            order = order.filter(new.contains) + new.subtracting(order).sorted()
        }
        // A model hidden by the filters can't stay selected (its details would be stale).
        .onChange(of: visible, initial: true) { _, visible in
            if !selection.isSubset(of: visible) { selection.formIntersection(visible) }
        }
    }

    private func scoreColumn(_ i: Int, _ key: KeyPath<ModelRow, Double>) -> TableColumn<ModelRow, KeyPathComparator<ModelRow>, some View, Text> {
        TableColumn(Analysis.keyBenchmarks[i].label, value: key) { r in
            let v = r[keyPath: key]
            Text(v >= 0 ? Format.percent(v) : "–").monospacedDigit()
                .foregroundStyle(v >= 0 ? Color.primary : Palette.text2)
        }
        .width(min: 50, ideal: 58)
    }
}

struct ModelDetail: View {
    let profile: ModelProfile
    let infos: [BenchmarkInfo]
    @State private var hover: String?

    var body: some View {
        let scores = profile.scores
            .filter { name, _ in infos.first { $0.name == name }?.supersededBy == nil }
            .sorted { $0.value > $1.value }
        Card(title: profile.name, subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let l = profile.listing {
                        fact("Price", "\(Format.price(l.inputPrice)) in · \(Format.price(l.outputPrice)) out per M tokens")
                        fact("Context", Format.tokens(l.contextLength) + " tokens")
                        fact("Takes in", l.inputModalities.sorted().joined(separator: ", "))
                        fact("Produces", l.outputModalities.sorted().joined(separator: ", "))
                    } else {
                        fact("API", "Not listed on OpenRouter under this name")
                    }
                    if let c = profile.computeFLOP { fact("Training compute", Format.flop(c) + " FLOP") }
                    if let h = profile.horizonMinutes { fact("Task horizon", Format.minutes(h)) }
                    if let o = profile.openWeights { fact("Weights", o ? "Open" : "Closed") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Chart(scores, id: \.key) { name, score in
                    BarMark(x: .value("Score", score), y: .value("Benchmark", Analysis.shortName(name)), height: .fixed(12))
                        .foregroundStyle(Palette.color(0))
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3))
                        .annotation(position: .trailing) {
                            Text(Format.percent(score, digits: 1)).font(.caption2).foregroundStyle(Palette.text2)
                        }
                }
                .chartXScale(domain: 0...1.1)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(horizontalSpacing: 8).foregroundStyle(Color.primary) } }
                .frame(height: CGFloat(scores.count) * 20 + 10)
                .chartSummary("Bar chart of \(profile.name)'s best scores: " + scores.map { "\(Analysis.shortName($0.key)) \(Format.percent($0.value, digits: 1))" }.joined(separator: ", ") + ".")
            }
        }
    }

    private var subtitle: String {
        "\(profile.lab) · first result \(Format.date.string(from: profile.released)) · \(profile.scores.count) benchmarks"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(Palette.text2)
            Text(value)
        }
    }
}

/// Two to four models side by side, like the website's comparison: key facts, then the best score
/// on each benchmark at least two of them have results for, with the leader in bold.
struct ModelComparison: View {
    let models: [ModelProfile]
    let infos: [BenchmarkInfo]
    var clear: () -> Void

    private struct Bar: Identifiable {
        var id: String { benchmark + "|" + model }
        let benchmark: String
        let model: String
        let score: Double
    }

    /// Benchmarks at least two of the models have scores on: key benchmarks first, then the most
    /// widely shared; at most 12. Benchmarks replaced by a newer version are left out.
    static func sharedBenchmarks(_ models: [ModelProfile], infos: [BenchmarkInfo]) -> [String] {
        let keyOrder = Analysis.keyBenchmarks.map(\.name)
        let superseded = Set(infos.filter { $0.supersededBy != nil }.map(\.name))
        let count = { (b: String) in models.filter { $0.score(b) != nil }.count }
        return Set(models.flatMap(\.scores.keys))
            .filter { count($0) >= 2 && !superseded.contains($0) }
            .sorted { a, b in
                let ka = keyOrder.firstIndex(of: a) ?? 99, kb = keyOrder.firstIndex(of: b) ?? 99
                if ka != kb { return ka < kb }
                if count(a) != count(b) { return count(a) > count(b) }
                return a < b
            }
            .prefix(12).map { $0 }
    }

    var body: some View {
        let names = models.map(\.name)
        let colors = names.indices.map(Palette.color)
        let shared = Self.sharedBenchmarks(models, infos: infos)
        let bars = shared.flatMap { b in models.compactMap { m in m.score(b).map { Bar(benchmark: Analysis.shortName(b), model: m.name, score: $0) } } }

        Card(title: "Comparing \(models.count) models",
             subtitle: "Best score on each benchmark at least two of them have results for. The leader on each row is bold.") {
            Button("Clear Comparison", action: clear)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(Array(models.enumerated()), id: \.element.name) { i, m in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Circle().fill(colors[i]).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(m.name).font(.callout.weight(.semibold))
                        }
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                factRow("Lab") { $0.lab }
                factRow("First result") { Format.date.string(from: $0.released) }
                factRow("Price / M tokens") { $0.listing.map { Format.price($0.blendedPrice) } ?? "–" }
                factRow("Context") { $0.listing.map { Format.tokens($0.contextLength) } ?? "–" }
                factRow("Task horizon") { $0.horizonMinutes.map(Format.minutes) ?? "–" }
                factRow("Training compute") { $0.computeFLOP.map { Format.flop($0) + " FLOP" } ?? "–" }
                factRow("Weights") { $0.openWeights.map { $0 ? "Open" : "Closed" } ?? "–" }
                if !shared.isEmpty { Divider().gridCellUnsizedAxes(.horizontal) }
                ForEach(shared, id: \.self) { b in
                    let best = models.compactMap { $0.score(b) }.max()
                    GridRow {
                        Text(Analysis.shortName(b)).foregroundStyle(Palette.text2)
                        ForEach(models, id: \.name) { m in
                            let v = m.score(b)
                            Text(Format.percent(v, digits: 1))
                                .fontWeight(v != nil && v == best ? .bold : .regular)
                                .foregroundStyle(v == nil ? Palette.text2 : Color.primary)
                                .monospacedDigit()
                                .accessibilityLabel(v == nil ? "no result" : Format.percent(v, digits: 1) + (v == best ? ", leader" : ""))
                        }
                    }
                }
            }
            .font(.callout)

            if shared.isEmpty {
                Footnote(text: "These models don't share any benchmark results yet.")
            } else {
                Chart(bars) { r in
                    BarMark(x: .value("Score", r.score), y: .value("Benchmark", r.benchmark))
                        .position(by: .value("Model", r.model))
                        .foregroundStyle(by: .value("Model", r.model))
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2))
                }
                .chartForegroundStyleScale(domain: names, range: colors)
                .chartXScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(position: .top, values: [0, 0.25, 0.5, 0.75, 1]) { v in
                        AxisGridLine().foregroundStyle(Palette.grid)
                        AxisValueLabel { Text(Format.percent(v.as(Double.self))) }.foregroundStyle(Palette.muted)
                    }
                }
                .chartYAxis { AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(horizontalSpacing: 8).foregroundStyle(Color.primary) } }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: CGFloat(shared.count) * (CGFloat(models.count) * 11 + 14) + 60)
                .chartSummary("Grouped bar chart comparing \(names.joined(separator: ", ")). " + shared.map { b in
                    "\(Analysis.shortName(b)): " + models.compactMap { m in m.score(b).map { "\(m.name) \(Format.percent($0, digits: 1))" } }.joined(separator: ", ")
                }.joined(separator: ". ") + ".")
            }
        }
    }

    private func factRow(_ label: String, _ value: @escaping (ModelProfile) -> String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Palette.text2)
            ForEach(models, id: \.name) { m in Text(value(m)).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
