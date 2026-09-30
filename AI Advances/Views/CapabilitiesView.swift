import SwiftUI
import Charts

struct CapabilitiesView: View {
    @Environment(DataStore.self) private var store
    @State private var areaName = ""
    @State private var sinceYears = 2.0

    var body: some View {
        let data = store.data
        let area = data.areas.first { $0.name == areaName } ?? data.areas.first!

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Capabilities",
                       summary: "Every tracked model result by capability area. Lines trace the best score so far; dots are individual models.")

            HStack {
                Picker("Area", selection: $areaName) {
                    ForEach(data.areas) { Text($0.name).tag($0.name) }
                }
                .frame(maxWidth: 300)
                Picker("Since", selection: $sinceYears) {
                    Text("1 year").tag(1.0)
                    Text("2 years").tag(2.0)
                    Text("4 years").tag(4.0)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            Card(title: area.name, subtitle: area.summary) {
                FrontierChart(area: area, results: data.results, since: yearsAgo(sinceYears), showAllResults: true, height: 380)
                Footnote(text: "Scores come from Epoch AI's benchmarking hub, which mixes its own runs with results reported by benchmark authors. Each model's best reasoning-effort setting is shown.")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                ForEach(area.benchmarks, id: \.self) { b in
                    leaderboard(b, data: data)
                }
            }
        }
        .onAppear { if areaName.isEmpty { areaName = data.areas.first?.name ?? "" } }
    }

    private func leaderboard(_ benchmark: String, data: Dataset) -> some View {
        let best = Dictionary(grouping: data.results.filter { $0.benchmark == benchmark }, by: \.modelGroup)
            .compactMap { $0.value.max { $0.score < $1.score } }
            .sorted { $0.score > $1.score }
            .prefix(8)
        let info = data.benchmarks.first { $0.name == benchmark }
        return Card(title: Analysis.shortName(benchmark),
                    subtitle: info?.releaseDate.map { "Benchmark published \(Format.date.string(from: $0))" }) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach(Array(best.enumerated()), id: \.element.id) { i, r in
                    GridRow {
                        Text("\(i + 1)").foregroundStyle(.secondary).monospacedDigit()
                        VStack(alignment: .leading, spacing: 0) {
                            Text(r.modelGroup).lineLimit(1)
                            Text(r.organization).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(Format.percent(r.score, digits: 1)).monospacedDigit()
                    }
                }
            }
        }
    }
}
