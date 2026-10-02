import Foundation

/// Everything the website shows, precomputed. Dates encode as "yyyy-MM-dd".
struct SiteData: Encodable {
    struct Source: Encodable { let name, credit, page: String }

    struct Tiles: Encodable {
        let computeFactorPerYear: Double?
        let computeDoublingMonths: Double?
        let computeModels: Int
        let horizonMinutes: Double?
        let horizonModel: String?
        let horizonDoublingMonths: Double?
        let priceNow: Double?
        let priceModel: String?
        let priceFirst: Double?
        let priceFirstModel: String?
        let maxContext: Int
        let medianContextThisQuarter: Double?
    }

    struct Momentum: Encodable { let gapClosed, pointsGained: Double; let benchmarksUsed: Int }

    struct Area: Encodable {
        let name, summary: String
        let benchmarks: [String]
        /// Keyed by window in months: "6", "12", "24".
        let momentum: [String: Momentum]
    }

    struct Benchmark: Encodable {
        let name, short: String
        let ceiling: Double
        let released: Date?
    }

    struct Result: Encodable {
        let b: String      // benchmark
        let m: String      // model group
        let o: String      // organization
        let d: Date        // release date
        let s: Double      // score 0...1
    }

    struct Horizon: Encodable { let model, org: String; let date: Date; let minutes: Double }

    struct Model: Encodable {
        let name, lab: String
        let released: Date
        let scores: [String: Double]
        let horizonMinutes: Double?
        let computeFLOP: Double?
        let openWeights: Bool?
        let price: Double?
        let inputPrice: Double?
        let outputPrice: Double?
        let context: Int?
        let inputModalities: [String]?
        let outputModalities: [String]?
        let listedOn: Date?
    }

    struct Listed: Encodable {
        let id, name, lab: String
        let created: Date
        let context: Int
        let price: Double
        let free: Bool
        let input, output: [String]
    }

    struct Share: Encodable { let quarter: String; let start: Date; let modality: String; let share: Double; let count: Int }
    struct Point: Encodable { let date: Date; let value: Double }

    struct Notable: Encodable {
        let name, org: String
        let date: Date
        let flop: Double
        let frontier: Bool
    }

    struct Item: Encodable {
        let date: Date
        let title, detail, lab, kind, direction: String
        let link: String?
    }

    struct Forecast: Encodable {
        let id, kind, area, title, target, current, basis: String
        let reached, predicted, early, late: Date?
        let note: String?
    }

    struct Shift: Encodable { let id, title: String; let months: Double; let predicted: Date? }

    struct HistoryEntry: Encodable {
        let asOf: Date
        let live: Bool
        let forecasts: [String: ForecastSnapshot]
    }

    struct Record: Encodable {
        struct Item: Encodable {
            let id, title: String
            let madeOn, predicted, reached: Date
            let early, late: Date?
            let errorMonths: Double
            let inside: Bool
        }
        let summary: String
        let scored, inside: Int
        let coverage, medianAbsErrorMonths: Double?
        let items: [Item]
    }

    struct Lab: Encodable {
        struct Quarter: Encodable { let quarter: String; let start: Date; let count: Int }
        let name: String
        let note: LabNote?
        let standing: [String: Double]
        let recordsHeld: [String]
        let recentRecords: [String: Int]
        let releasesByQuarter: [Quarter]
        let recentModels: [String]
        let latestName: String?
        let latestDate: Date?
        let modalityShare: [String: Double]
        let openShare: Double?
        let priceMin, priceMax: Double?
        let largestRun: Double?
    }

    let generatedAt: Date
    let latestDataDate: Date?
    let sources: [Source]
    let tiles: Tiles
    let keyBenchmarks: [[String]]
    let areas: [Area]
    let benchmarks: [Benchmark]
    let results: [Result]
    let horizons: [Horizon]
    let models: [Model]
    let listed: [Listed]
    let modalityShares: [Share]
    let contextMedians: [Point]
    let notable: [Notable]
    let computeFit: [Point]
    let feed: [Item]
    let forecasts: [Forecast]
    let outlook: String
    let shifts: [Shift]
    let history: [HistoryEntry]
    let trackRecord: Record
    let labs: [Lab]
}
