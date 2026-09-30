import XCTest
@testable import AI_Advances

final class CSVTests: XCTestCase {
    func testQuotedFieldsWithCommasQuotesAndNewlines() {
        let text = "a,b,c\n1,\"x, \"\"y\"\"\nz\",3\n"
        let rows = CSV.records(text)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["b"], "x, \"y\"\nz")
        XCTAssertEqual(rows[0]["c"], "3")
    }

    func testMissingTrailingNewlineAndCRLF() {
        let rows = CSV.records("a,b\r\n1,2\r\n3,4")
        XCTAssertEqual(rows.map { $0["b"] }, ["2", "4"])
    }
}

final class AnalysisTests: XCTestCase {
    private func result(_ b: String, _ model: String, _ date: String, _ score: Double) -> BenchmarkResult {
        BenchmarkResult(benchmark: b, modelVersion: model, modelGroup: model, organization: "Lab",
                        releaseDate: Dates.parse(date)!, score: score)
    }

    func testMatchKeyJoinsEpochAndOpenRouterNames() {
        XCTAssertEqual(Analysis.matchKey("Claude Opus 5.5"), Analysis.matchKey("Anthropic: Claude Opus 5.5"))
        XCTAssertEqual(Analysis.matchKey("Gemini 3.1 Pro"), Analysis.matchKey("Google: Gemini 3.1 Pro Preview"))
        XCTAssertNotEqual(Analysis.matchKey("GPT-6 Sol"), Analysis.matchKey("GPT-6.1 Sol"))
    }

    func testFrontierKeepsOnlyRecords() {
        let rs = [result("B", "a", "2025-01-01", 0.5), result("B", "b", "2025-02-01", 0.4),
                  result("B", "c", "2025-03-01", 0.7), result("B", "d", "2025-03-01", 0.6)]
        let f = Analysis.frontier(rs, benchmark: "B")
        XCTAssertEqual(f.map(\.model), ["a", "c"])
        XCTAssertEqual(Analysis.frontierValue(f, at: Dates.parse("2025-02-15")!), 0.5)
    }

    func testExponentialFitRecoversDoublingTime() {
        let start = Dates.parse("2020-01-01")!
        // Doubles every 6 months.
        let pts = (0..<10).map { i in (start.addingTimeInterval(Double(i) * 0.5 * 365.25 * 86_400), pow(2, Double(i))) }
        let fit = ExpFit.fit(pts)!
        XCTAssertEqual(fit.doublingMonths, 6, accuracy: 0.01)
        XCTAssertEqual(fit.factorPerYear, 4, accuracy: 0.01)
    }

    func testMomentumMeasuresHeadroomClosed() {
        let area = CapabilityArea(name: "A", summary: "", benchmarks: ["B"])
        let now = Dates.parse("2026-01-01")!
        let rs = [result("B", "old", "2024-06-01", 0.5), result("B", "new", "2025-06-01", 0.75)]
        let m = Analysis.momentum(area: area, results: rs, infos: [], now: now, months: 12)!
        XCTAssertEqual(m.gapClosed, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.pointsGained, 25, accuracy: 1e-9)
    }

    func testCheapestOverTimeOnlyStepsDown() {
        func listing(_ name: String, _ price: Double) -> ListedModel {
            ListedModel(id: name, name: name, lab: "Lab", created: Dates.parse("2020-01-01")!, contextLength: 1000,
                        inputPrice: price, outputPrice: price, inputModalities: ["text"], outputModalities: ["text"])
        }
        func profile(_ name: String, _ date: String, _ score: Double, _ price: Double) -> ModelProfile {
            ModelProfile(name: name, lab: "Lab", released: Dates.parse(date)!, scores: ["B": score],
                         horizonMinutes: nil, listing: listing(name, price), computeFLOP: nil, openWeights: nil)
        }
        let ps = [profile("a", "2025-01-01", 0.9, 10), profile("b", "2025-02-01", 0.95, 20),
                  profile("c", "2025-03-01", 0.85, 2), profile("d", "2025-04-01", 0.5, 0.1)]
        let steps = Analysis.cheapestOverTime(ps, benchmark: "B", threshold: 0.8)
        XCTAssertEqual(steps.map(\.model), ["a", "c"])
    }
}

/// Parses the snapshot bundled with the app, so a format change in a source shows up here.
final class SnapshotTests: XCTestCase {
    static var data: Dataset!

    override class func setUp() {
        let files = Dictionary(uniqueKeysWithValues: DataStore.sources.map { s in
            (s.file, Bundle.main.url(forResource: (s.file as NSString).deletingPathExtension,
                                     withExtension: (s.file as NSString).pathExtension)!)
        })
        data = try! DataStore.parseAll(files)
    }

    func testSourcesParse() {
        XCTAssertGreaterThan(Self.data.results.count, 3000)
        XCTAssertGreaterThan(Self.data.horizons.count, 20)
        XCTAssertGreaterThan(Self.data.notable.filter { $0.computeFLOP != nil }.count, 400)
        XCTAssertGreaterThan(Self.data.listed.count, 200)
        XCTAssertFalse(Self.data.listed.contains { $0.id.contains(":") })
        XCTAssertGreaterThanOrEqual(Self.data.advances.count, 25)
    }

    func testEveryTrackedBenchmarkExistsInTheData() {
        let names = Set(Self.data.results.map(\.benchmark))
        for b in Self.data.areas.flatMap(\.benchmarks) + Analysis.keyBenchmarks.map(\.name) {
            XCTAssertTrue(names.contains(b), "\(b) missing from Epoch data")
        }
    }

    func testProfilesJoinPricesForMajorModels() {
        let profiles = Analysis.profiles(Self.data)
        let priced = profiles.filter { $0.listing != nil }
        XCTAssertGreaterThan(priced.count, 40, "Name matching between Epoch and OpenRouter looks broken")
        XCTAssertNotNil(profiles.first { $0.name == "Claude Opus 5.5" }?.listing)
    }

    func testTrendsAreSensible() {
        let compute = Analysis.computeFit(Self.data.notable, since: Dates.parse("2020-01-01")!)!
        XCTAssert((2...10).contains(compute.factorPerYear), "compute grows \(compute.factorPerYear)x/yr")
        let horizons = Analysis.horizonFrontier(Self.data.horizons)
        XCTAssertGreaterThan(horizons.last!.minutes, 60)
        for area in Self.data.areas {
            XCTAssertNotNil(Analysis.momentum(area: area, results: Self.data.results, infos: Self.data.benchmarks, now: Date()), area.name)
        }
    }

    func testAdvancesHaveSources() {
        for a in Self.data.advances {
            XCTAssertNotNil(Dates.parse(a.date), a.title)
            XCTAssertTrue(a.source.hasPrefix("https://"), a.title)
        }
    }
}
