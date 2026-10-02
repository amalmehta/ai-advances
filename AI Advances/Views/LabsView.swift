import SwiftUI
import Charts

struct LabsView: View {
    @Environment(DataStore.self) private var store
    @State private var hoverCell: String?

    /// Sequential blue ramp, light to dark, for heatmap cells.
    static let ramp: [UInt32] = [0xcde2fb, 0xb7d3f6, 0x9ec5f4, 0x86b6ef, 0x6da7ec, 0x5598e7, 0x3987e5, 0x2a78d6, 0x256abf, 0x1c5cab, 0x184f95, 0x104281, 0x0d366b]

    static func cell(_ v: Double) -> (fill: Color, darkText: Bool) {
        let i = min(ramp.count - 1, max(0, Int((v * Double(ramp.count - 1)).rounded())))
        let h = ramp[i]
        let c = Color(.sRGB, red: Double((h >> 16) & 0xff) / 255, green: Double((h >> 8) & 0xff) / 255, blue: Double(h & 0xff) / 255)
        return (c, i < 6)
    }

    private struct Cell: Identifiable {
        var id: String { lab + "|" + column }
        let lab: String
        let column: String
        let value: Double
        let label: String
        let star: Bool
    }

    var body: some View {
        let labs = store.labs.sorted { avg($0) > avg($1) }
        let areas = store.data.areas.map(\.name)

        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Who's working on what",
                       summary: "Where each major lab leads, how fast it ships, and what it says it's betting on. The charts update with the data; the focus notes are researched and dated.")

            if let f = Freshness(Freshness.labNotes(store.labs.compactMap(\.note))) {
                FreshnessNote(freshness: f, what: "Lab focus notes researched")
            }

            if labs.isEmpty {
                ProgressView("Summarizing labs…")
            } else {
                Card(title: "Where each lab stands",
                     subtitle: "Each lab's best score as a share of the overall best, averaged over the area's benchmarks it has results on. – = not tested. ★ = holds a current record in that area.") {
                    standingHeatmap(labs, areas: areas)
                }

                Card(title: "Release pace",
                     subtitle: "New models first seen each quarter, in Epoch's benchmark results or OpenRouter's listings.") {
                    paceHeatmap(labs)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(labs) { LabCard(lab: $0) }
                }

                Footnote(text: "Standing compares best-ever scores, so a lab that stopped submitting to a benchmark keeps its last result. Labs differ in how many of their models Epoch has evaluated.")
            }
        }
    }

    private func avg(_ l: LabSummary) -> Double {
        l.standing.isEmpty ? 0 : l.standing.values.reduce(0, +) / Double(l.standing.count)
    }

    private func standingHeatmap(_ labs: [LabSummary], areas: [String]) -> some View {
        let areaOf = Dictionary(store.data.areas.flatMap { a in a.benchmarks.map { ($0, a.name) } }, uniquingKeysWith: { a, _ in a })
        let cells = labs.flatMap { lab in
            areas.map { a -> Cell in
                let v = lab.standing[a]
                return Cell(lab: lab.name, column: a, value: v ?? 0, label: v.map { Format.percent($0) } ?? "–",
                            star: lab.recordsHeld.contains { areaOf[$0] == a })
            }
        }
        return heatmap(cells, rows: labs.map(\.name), columns: areas, height: CGFloat(labs.count) * 30 + 40)
    }

    private func paceHeatmap(_ labs: [LabSummary]) -> some View {
        let quarters = Set(labs.flatMap { $0.releasesByQuarter.keys }).sorted()
        let maxCount = Double(labs.flatMap { $0.releasesByQuarter.values }.max() ?? 1)
        let columns = quarters.map(Analysis.quarterLabel)
        let cells = labs.flatMap { lab in
            quarters.map { q -> Cell in
                let n = lab.releasesByQuarter[q] ?? 0
                return Cell(lab: lab.name, column: Analysis.quarterLabel(q), value: Double(n) / maxCount,
                            label: n == 0 ? "" : "\(n)", star: false)
            }
        }
        return heatmap(cells, rows: labs.map(\.name), columns: columns, height: CGFloat(labs.count) * 30 + 40)
    }

    private func heatmap(_ cells: [Cell], rows: [String], columns: [String], height: CGFloat) -> some View {
        Chart(cells) { c in
            let style = Self.cell(c.value)
            RectangleMark(x: .value("Column", c.column), y: .value("Lab", c.lab), width: .ratio(0.96), height: .ratio(0.9))
                .foregroundStyle(c.label == "–" || c.label.isEmpty ? Palette.grid.opacity(0.5) : style.fill)
                .cornerRadius(3)
                .annotation(position: .overlay) {
                    Text(c.label + (c.star ? " ★" : ""))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(c.label == "–" ? Color.secondary : style.darkText ? Color.black.opacity(0.8) : Color.white)
                }
        }
        .chartXScale(domain: columns)
        .chartYScale(domain: rows)
        .chartXAxis { AxisMarks(position: .top) { _ in AxisValueLabel().foregroundStyle(Color.primary) } }
        .chartYAxis { AxisMarks(preset: .extended, position: .leading) { _ in AxisValueLabel(horizontalSpacing: 8).foregroundStyle(Color.primary) } }
        .frame(height: height)
    }
}

struct LabCard: View {
    let lab: LabSummary

    var body: some View {
        Card(title: lab.name, subtitle: subtitle) {
            if let note = lab.note {
                HStack(spacing: 6) {
                    ForEach(note.focus, id: \.self) { tag in
                        Text(tag).font(.caption.weight(.medium))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Palette.grid, in: Capsule())
                    }
                }
                Text(note.summary).fixedSize(horizontal: false, vertical: true)
                if !note.bets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Betting on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(note.bets, id: \.self) { b in
                            Label(b, systemImage: "arrow.forward").font(.callout).labelStyle(BulletLabel())
                        }
                    }
                }
                HStack(spacing: 10) {
                    Text("Researched \(note.asOf)").font(.caption).foregroundStyle(.tertiary)
                    ForEach(Array(note.sources.enumerated()), id: \.offset) { i, s in
                        if let url = URL(string: s) { Link("Source \(i + 1)", destination: url).font(.caption) }
                    }
                }
                Divider()
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                if let latest = lab.latest {
                    fact("Latest model", "\(latest.name) · \(Format.date.string(from: latest.date))")
                }
                fact("Models in the last year", lab.recentModels.isEmpty ? "None seen" : "\(lab.recentModels.count): " + lab.recentModels.prefix(5).joined(separator: ", ") + (lab.recentModels.count > 5 ? "…" : ""))
                if !lab.recordsHeld.isEmpty {
                    fact("Holds records on", lab.recordsHeld.map(Analysis.shortName).joined(separator: ", "))
                }
                if let push = lab.pushingHardest {
                    fact("Most records set (12 mo)", "\(push) (\(lab.recentRecords[push]!))")
                }
                if lab.listedCount > 0 {
                    let mods = Analysis.modalities.compactMap { m -> String? in
                        guard let v = lab.modalityShare[m.label], v > 0 else { return nil }
                        return "\(m.label.lowercased()) \(Format.percent(v))"
                    }
                    fact("Modalities (new models)", mods.isEmpty ? "text only" : mods.joined(separator: ", "))
                }
                if let o = lab.openShare { fact("Open weights", "\(Format.percent(o)) of notable models, last 2 years") }
                if let p = lab.priceRange { fact("API prices", "\(Format.price(p.lowerBound)) – \(Format.price(p.upperBound)) / M tokens") }
                if let c = lab.largestRun { fact("Largest training run", Format.flop(c) + " FLOP") }
            }
        }
    }

    private var subtitle: String? {
        lab.note.map { $0.flagships.isEmpty ? "" : "Flagships: " + $0.flagships.joined(separator: ", ") }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BulletLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.caption2).foregroundStyle(.secondary)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
