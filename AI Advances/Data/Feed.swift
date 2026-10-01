import Foundation

/// The Latest Advances feed: researched highlights, new benchmark records and new model listings.
struct FeedItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Codable { case curated = "Highlights", records = "New records", models = "New models" }

    let id: String
    let date: Date
    let title: String
    let detail: String
    let lab: String
    let kind: Kind
    let direction: String
    let link: String?
}

enum Feed {
    static let areaDirection: [String: String] = [
        "Reasoning & knowledge": "Reasoning", "Math": "Reasoning", "Novel problem solving": "Reasoning",
        "Coding": "Coding", "Agents & real work": "Agents", "Vision & spatial": "Multimodal",
    ]

    static func items(_ data: Dataset, now: Date) -> [FeedItem] {
        let yearAgo = now.addingTimeInterval(-365.25 * 86_400)
        let curated = data.advances.map {
            FeedItem(id: "c" + $0.id, date: $0.day, title: $0.title, detail: $0.summary, lab: $0.lab,
                     kind: .curated, direction: $0.direction, link: $0.source)
        }
        let areaOf = Dictionary(data.areas.flatMap { a in a.benchmarks.map { ($0, a.name) } }, uniquingKeysWith: { a, _ in a })
        let records = Analysis.recentRecords(data, since: yearAgo).map { r in
            FeedItem(id: "r" + r.id, date: r.point.date,
                     title: "\(r.point.model) sets a \(Analysis.shortName(r.point.benchmark)) record",
                     detail: "\(Format.percent(r.point.score, digits: 1)), up from \(Format.percent(r.previous, digits: 1)). \(areaOf[r.point.benchmark] ?? "") benchmark.",
                     lab: r.point.organization, kind: .records,
                     direction: areaDirection[areaOf[r.point.benchmark] ?? ""] ?? "Reasoning",
                     link: "https://epoch.ai/benchmarks")
        }
        let models = data.listed.filter { $0.created >= now.addingTimeInterval(-60 * 86_400) }.map { m in
            FeedItem(id: "m" + m.id, date: m.created, title: "\(m.lab) lists \(m.name)",
                     detail: "\(Format.tokens(m.contextLength)) context · \(m.isFree ? "free" : Format.price(m.blendedPrice) + " / M tokens") · takes \(m.inputModalities.sorted().joined(separator: ", "))",
                     lab: m.lab, kind: .models, direction: "New models",
                     link: "https://openrouter.ai/\(m.id)")
        }
        return (curated + records + models).sorted { $0.date > $1.date }
    }
}
