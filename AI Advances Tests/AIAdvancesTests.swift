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
    /// Parsed once and shared by every test class that needs real data.
    static let data: Dataset! = {
        let files = Dictionary(uniqueKeysWithValues: DataStore.sources.map { s in
            (s.file, Bundle.main.url(forResource: (s.file as NSString).deletingPathExtension,
                                     withExtension: (s.file as NSString).pathExtension)!)
        })
        return try! DataStore.parseAll(files)
    }()

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

final class ForecastTests: XCTestCase {
    func testLinearFitPredictsCrossingWithBracketingRange() {
        // y = 2x + 1 with small alternating noise.
        let pts: [(x: Double, y: Double)] = (0..<10).map { i in
            let x = Double(i)
            let noise: Double = i % 2 == 0 ? 0.1 : -0.1
            return (x: x, y: 2 * x + 1 + noise)
        }
        let fit = LinearFit.fit(pts)!
        XCTAssertEqual(fit.slope, 2, accuracy: 0.05)
        let x = fit.x(reaching: 41)!
        XCTAssertEqual(x, 20, accuracy: 0.5)
        let r = fit.range(reaching: 41)
        XCTAssertLessThan(r.early!, x)
        XCTAssertGreaterThan(r.late!, x)
    }

    func testFallingSeriesNeverReachesHigherTarget() {
        let pts: [(x: Double, y: Double)] = (0..<6).map { i in (x: Double(i), y: 10 - Double(i)) }
        XCTAssertNil(LinearFit.fit(pts)!.x(reaching: 20))
    }

    func testSnapshotForecastsAreOrderedAndInTheFuture() {
        let data = SnapshotTests.data!
        let now = Dates.parse("2026-09-30")!
        let fs = Forecasts.all(data, profiles: Analysis.profiles(data), asOf: now)
        XCTAssertGreaterThan(fs.count, 15)
        for f in fs {
            print("FORECAST", f.id, "| reached:", f.reached.map(Format.monthYear) ?? "-",
                  "| predicted:", f.predicted.map(Format.monthYear) ?? "-",
                  "| range:", f.early.map(Format.monthYear) ?? "-", "–", f.late.map(Format.monthYear) ?? "open", "|", f.current)
            if let p = f.predicted {
                XCTAssertGreaterThanOrEqual(p, now, f.id)
                if let e = f.early { XCTAssertLessThanOrEqual(e, p, f.id) }
                if let l = f.late { XCTAssertGreaterThanOrEqual(l, p, f.id) }
            }
            if f.reached != nil { XCTAssertNil(f.predicted, f.id) }
        }
        XCTAssertNotNil(fs.first { $0.id == "metr-week" }?.predicted ?? fs.first { $0.id == "metr-week" }?.reached)
    }

    func testReconstructionOnlyUsesPastData() {
        let data = SnapshotTests.data!
        let asOf = Dates.parse("2025-06-01")!
        let past = Forecasts.dataset(data, asOf: asOf)
        XCTAssertFalse(past.results.contains { $0.releaseDate > asOf })
        XCTAssertFalse(past.listed.contains { $0.created > asOf })
        let log = Forecasts.reconstructed(data, now: Dates.parse("2026-09-30")!)
        XCTAssertEqual(log.count, 12)
        XCTAssertTrue(log.allSatisfy(\.reconstructed))
    }

    func testLabSummariesCoverMajorLabs() {
        let data = SnapshotTests.data!
        let labs = Labs.summaries(data, notes: [], now: Dates.parse("2026-09-30")!)
        for name in ["OpenAI", "Anthropic", "Google DeepMind", "DeepSeek", "Alibaba (Qwen)"] {
            let l = labs.first { $0.name == name }
            XCTAssertNotNil(l, name)
            XCTAssertFalse(l?.standing.isEmpty ?? true, name)
            XCTAssertFalse(l?.recentModels.isEmpty ?? true, name)
        }
        for l in labs {
            print("LAB", l.name, "| held:", l.recordsHeld.count, "| models 12mo:", l.recentModels.count,
                  "| standing:", l.standing.sorted { $0.key < $1.key }.map { "\($0.key.prefix(6))=\(Int($0.value * 100))" }.joined(separator: " "))
            XCTAssertTrue(l.standing.values.allSatisfy { (0...1.0001).contains($0) }, l.name)
        }
    }
}

final class LabNoteTests: XCTestCase {
    func testEveryTrackedLabHasAResearchedNote() throws {
        let notes = try DataStore.bundled([LabNote].self, "Labs")
        for lab in Labs.directory {
            let note = notes.first { $0.name == lab.name }
            XCTAssertNotNil(note, "No note for \(lab.name)")
            XCTAssertFalse(note?.sources.isEmpty ?? true, lab.name)
        }
    }
}
