import Foundation

// MARK: - Epoch AI benchmarking hub

struct BenchmarkInfo: Hashable, Sendable {
    let name: String
    let sourceFile: String
    let scoreColumn: String
    let scale: Double
    let randomBaseline: Double
    let ceiling: Double
    let releaseDate: Date?
    let supersededBy: String?
}

struct BenchmarkResult: Hashable, Sendable, Identifiable {
    var id: String { benchmark + "|" + modelVersion }
    let benchmark: String
    let modelVersion: String
    /// Model family without the reasoning-effort suffix, e.g. "Claude Opus 5.5".
    let modelGroup: String
    let organization: String
    let releaseDate: Date
    /// 0...1
    let score: Double
}

struct TimeHorizon: Hashable, Sendable, Identifiable {
    var id: String { modelVersion }
    let modelVersion: String
    let modelGroup: String
    let organization: String
    let releaseDate: Date
    /// METR 50% time horizon, in minutes of human expert time.
    let minutes: Double
}

// MARK: - Epoch AI notable models

struct NotableModel: Hashable, Sendable, Identifiable {
    var id: String { name + "|" + organization }
    let name: String
    let organization: String
    let date: Date
    let domain: String
    let computeFLOP: Double?
    let parameters: Double?
    let isFrontier: Bool
    let openWeights: Bool?
}

// MARK: - OpenRouter model list

struct ListedModel: Hashable, Sendable, Identifiable {
    let id: String
    /// Name without the "Lab: " prefix.
    let name: String
    let lab: String
    let created: Date
    let contextLength: Int
    /// USD per million tokens.
    let inputPrice: Double
    let outputPrice: Double
    let inputModalities: Set<String>
    let outputModalities: Set<String>

    /// 3:1 input:output blend, the usual convention for comparing API prices.
    var blendedPrice: Double { (3 * inputPrice + outputPrice) / 4 }
    var isFree: Bool { inputPrice <= 0 && outputPrice <= 0 }
}

// MARK: - Curated

struct Advance: Codable, Hashable, Sendable, Identifiable {
    var id: String { date + title }
    let date: String
    let datePrecision: String?
    let title: String
    let lab: String
    let category: String
    let direction: String
    let summary: String
    let source: String

    var day: Date { Dates.parse(date) ?? .distantPast }
}

struct CapabilityArea: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    let name: String
    let summary: String
    let benchmarks: [String]
}

/// Everything the app shows, parsed from the raw source files.
struct Dataset: Sendable {
    var benchmarks: [BenchmarkInfo] = []
    var results: [BenchmarkResult] = []
    var horizons: [TimeHorizon] = []
    var notable: [NotableModel] = []
    var listed: [ListedModel] = []
    var advances: [Advance] = []
    var areas: [CapabilityArea] = []

    static let empty = Dataset()
}

/// The daily outlook Claude writes in the website build (site/data/outlook.json).
struct ClaudeOutlook: Codable, Hashable, Sendable {
    let generatedAt: String
    let dataThrough: String?
    let model: String
    let headline: String
    let outlook: String
}
