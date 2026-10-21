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
        /// Release date of the newest model METR has measured.
        let horizonAsOf: Date?
        /// Release date of the headline (record) model.
        let horizonDate: Date?
        /// The headline is at the top of what METR's task suite can measure: show "at least".
        let horizonIsLowerBound: Bool
        /// The quarter behind `medianContextThisQuarter` isn't over yet.
        let medianContextPartial: Bool
    }

    struct Momentum: Encodable {
        let gapClosed, pointsGained: Double
        let benchmarksUsed: Int
        /// Left out: already past the saturation target / no longer updated by Epoch.
        let excludedReached, excludedInactive: Int
    }

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
        /// Release date of the newest model with a result.
        let lastResult: Date?
        /// No new result for 120 days: Epoch no longer updates it. Left out of forecasts,
        /// momentum, records and labs' records held.
        let inactive: Bool
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
        /// False when the listing was found by the loose name match (a different snapshot or preview).
        let listingExact: Bool
    }

    struct Listed: Encodable {
        let id, name, lab: String
        let created: Date
        let context: Int
        let price: Double
        let free: Bool
        let input, output: [String]
    }

    struct Share: Encodable { let quarter: String; let start: Date; let modality: String; let share: Double; let count: Int; let partial: Bool }
    struct Point: Encodable { let date: Date; let value: Double }
    struct QuarterPoint: Encodable { let date: Date; let value: Double; let count: Int; let partial: Bool }

    struct Notable: Encodable {
        let name, org: String
        let date: Date
        let flop: Double
        let frontier: Bool
        /// The largest known training run when published (what the compute trend is fitted to).
        let record: Bool
    }

    struct Item: Encodable {
        let id: String
        let date: Date
        let title, detail, lab, kind, direction: String
        let link: String?
    }

    struct Forecast: Encodable {
        let id, kind, area, title, target, current, basis: String
        let reached, predicted, early, late: Date?
        let note: String?
        /// The benchmark is no longer updated by Epoch; `note` says so and there are no dates.
        let inactive: Bool
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
            /// "inside", "early", "late", "openEnded" or "expired". For "expired", `reached` is
            /// the scoring date (the milestone hasn't happened) and `errorMonths` how overdue it is.
            let outcome: String
        }
        let summary: String
        let scored, inside: Int
        let coverage, medianAbsErrorMonths: Double?
        /// Forecasts on reached milestones with an open-ended range, not counted in `scored`.
        let openEnded: Int
        /// Scored forecasts whose range ended without the milestone (misses, included in `scored`).
        let expired: Int
        /// Distinct milestones behind the figures.
        let milestones: Int
        let items: [Item]
        /// For each overdue milestone, the latest forecast whose range has run out.
        let missed: [Item]
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
    let contextMedians: [QuarterPoint]
    let notable: [Notable]
    let computeFit: [Point]
    let feed: [Item]
    let forecasts: [Forecast]
    let outlook: String
    let shifts: [Shift]
    let history: [HistoryEntry]
    let trackRecord: Record
    /// Sources that couldn't be downloaded today, so the site used the bundled snapshot for them.
    let sourcesFellBack: [String]
    /// Dates of the hand-researched content, so the site can flag it when it goes stale.
    let labNotesAsOf: Date?
    let highlightsThrough: Date?
    let labs: [Lab]
    /// Benchmarks no longer updated by Epoch (same as `benchmarks[].inactive`, including untracked ones).
    let inactiveBenchmarks: [String]
    /// Parsing problems worth knowing about (fallback files used, tracked benchmarks with no data).
    let warnings: [String]
}
