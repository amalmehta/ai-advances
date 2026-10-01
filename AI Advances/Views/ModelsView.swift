import SwiftUI
import Charts

struct ModelsView: View {
    @Environment(DataStore.self) private var store
    @State private var search = ""
    @State private var lab = "All labs"
    @State private var recentOnly = true
    @State private var selection: ModelRow.ID?
    @State private var sortOrder = [KeyPathComparator(\ModelRow.released, order: .reverse)]

    struct ModelRow: Identifiable {
        var id: String { profile.name }
        let profile: ModelProfile
        var name: String { profile.name }
        var lab: String { profile.lab }
        var released: Date { profile.released }
        var price: Double { profile.listing?.blendedPrice ?? .infinity }
        var context: Int { profile.listing?.contextLength ?? 0 }
        var horizon: Double { profile.horizonMinutes ?? -1 }
        func score(_ i: Int) -> Double { profile.score(Analysis.keyBenchmarks[i].name) ?? -1 }
        var s0: Double { score(0) }
        var s1: Double { score(1) }
        var s2: Double { score(2) }
        var s3: Double { score(3) }
        var s4: Double { score(4) }
        var s5: Double { score(5) }
        var s6: Double { score(6) }
    }

    var body: some View {
        let profiles = store.profiles
        let labs = Dictionary(grouping: profiles, by: \.lab).sorted { $0.value.count > $1.value.count }.prefix(14).map(\.key)
        let cutoff = yearsAgo(1)
        let rows = profiles
            .filter { !recentOnly || $0.released >= cutoff }
            .filter { lab == "All labs" || $0.lab == lab }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.lab.localizedCaseInsensitiveContains(search) }
            .filter { p in Analysis.keyBenchmarks.contains { p.score($0.name) != nil } || p.horizonMinutes != nil }
            .map(ModelRow.init)
            .sorted(using: sortOrder)

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
                Text("\(rows.count) models").foregroundStyle(.secondary)
            }

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Model", value: \.name) { r in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.name)
                        Text(r.lab).font(.caption).foregroundStyle(.secondary)
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
            .frame(height: 460)

            Footnote(text: "Price is a 3:1 blend of input and output price per million tokens, from OpenRouter; it shows only when the names match. Scores are the best across reasoning-effort settings, from Epoch AI. Select a row for the full profile, including METR task horizon and training compute.")

            if let id = selection, let p = profiles.first(where: { $0.name == id }) {
                ModelDetail(profile: p, infos: store.data.benchmarks)
            }
        }
    }

    private func scoreColumn(_ i: Int, _ key: KeyPath<ModelRow, Double>) -> TableColumn<ModelRow, KeyPathComparator<ModelRow>, some View, Text> {
        TableColumn(Analysis.keyBenchmarks[i].label, value: key) { r in
            let v = r[keyPath: key]
            Text(v >= 0 ? Format.percent(v) : "–").monospacedDigit()
                .foregroundStyle(v >= 0 ? .primary : .tertiary)
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
            HStack(alignment: .top, spacing: 24) {
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
                .frame(width: 280, alignment: .leading)

                Chart(scores, id: \.key) { name, score in
                    BarMark(x: .value("Score", score), y: .value("Benchmark", Analysis.shortName(name)), height: .fixed(12))
                        .foregroundStyle(Palette.color(0))
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3))
                        .annotation(position: .trailing) {
                            Text(Format.percent(score, digits: 1)).font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXScale(domain: 0...1.1)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(horizontalSpacing: 8).foregroundStyle(Color.primary) } }
                .frame(height: CGFloat(scores.count) * 20 + 10)
            }
        }
    }

    private var subtitle: String {
        "\(profile.lab) · first result \(Format.date.string(from: profile.released)) · \(profile.scores.count) benchmarks"
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
