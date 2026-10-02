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
        // Snapshot dates and labels on listings don't make a different model.
        XCTAssertEqual(Analysis.matchKey("DeepSeek-V4-Pro"), Analysis.matchKey("DeepSeek: DeepSeek V4 Pro 0423"))
        XCTAssertEqual(Analysis.matchKey("Mistral Large 3"), Analysis.matchKey("Mistral: Mistral Large 3 2512"))
        XCTAssertEqual(Analysis.matchKey("Gemma 4 31B IT"), Analysis.matchKey("Google: Gemma 4 31B"))
        XCTAssertEqual(Analysis.matchKey("Grok 4.3 Beta"), Analysis.matchKey("SpaceXAI: Grok 4.3"))
        XCTAssertEqual(Analysis.matchKey("Qwen 3.5 Plus (hosted 397B-A17B)"), Analysis.matchKey("Qwen: Qwen3.5 Plus 2026-02-15"))
        // ...but real differences still count.
        XCTAssertNotEqual(Analysis.matchKey("Muse Spark"), Analysis.matchKey("Meta: Muse Spark 1.2"))
        XCTAssertNotEqual(Analysis.matchKey("Qwen3.5-27B"), Analysis.matchKey("Qwen: Qwen3.6 27B"))
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
        XCTAssertEqual(log.count, 18)
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

final class TrackRecordTests: XCTestCase {
    func testScoresForecastsMadeAtLeastThreeMonthsAhead() {
        let reached = Dates.parse("2026-06-01")!
        let f = Forecast(id: "x", kind: .capabilities, area: "A", title: "X", target: "", current: "", basis: "",
                         reached: reached, predicted: nil, early: nil, late: nil, note: nil)
        func entry(_ asOf: String, _ p: String, _ e: String, _ l: String?) -> ForecastLogEntry {
            ForecastLogEntry(asOf: Dates.parse(asOf)!, reconstructed: true, forecasts: [
                "x": ForecastSnapshot(predicted: Dates.parse(p), early: Dates.parse(e), late: l.flatMap(Dates.parse), reached: nil)])
        }
        let history = [
            entry("2025-12-01", "2026-04-01", "2026-03-01", "2026-05-01"),  // outside: reached after the late end
            entry("2026-01-01", "2026-05-01", "2026-03-01", nil),           // inside: open-ended range
            entry("2026-05-01", "2026-06-01", "2026-05-15", "2026-07-01"),  // too close to the event; ignored
        ]
        let r = TrackRecord.score(history: history, current: [f])
        XCTAssertEqual(r.scored, 2)
        XCTAssertEqual(r.inside, 1)
        XCTAssertEqual(r.items.first?.madeOn, Dates.parse("2025-12-01"))   // closest to six months ahead
        XCTAssertEqual(r.items.first?.errorMonths ?? 0, 2, accuracy: 0.1)  // happened ~2 months later than forecast
    }

    /// Hindcast coverage on the bundled data: how often the likely range contained the real date.
    func testHindcastCoverage() {
        let data = SnapshotTests.data!
        let now = Dates.parse("2026-09-30")!
        let current = Forecasts.all(data, profiles: Analysis.profiles(data), asOf: now)
        let history = Forecasts.reconstructed(data, now: now, months: 18)
        let r = TrackRecord.score(history: history, current: current)
        print("HINDCAST scored \(r.scored), inside \(r.inside), coverage \(Format.percent(r.coverage)), median error \(r.medianAbsErrorMonths.map { String(format: "%.1f", $0) } ?? "–") months")
        for i in r.items {
            print("HINDCAST \(i.forecastID): made \(Format.monthYear(i.madeOn)), predicted \(Format.monthYear(i.predicted)), reached \(Format.monthYear(i.reached)), \(i.inside ? "inside" : "outside")")
        }
        XCTAssertGreaterThan(r.scored, 5)
    }
}

final class FreshnessTests: XCTestCase {
    func testStaleAfter45Days() {
        let now = Dates.parse("2026-12-01")!
        XCTAssertFalse(Freshness(Dates.parse("2026-11-01"), now: now)!.isStale)
        let old = Freshness(Dates.parse("2026-09-30"), now: now)!
        XCTAssertTrue(old.isStale)
        XCTAssertEqual(old.days, 62)
        XCTAssertTrue(old.sentence("Researched").contains("may be out of date"))
        XCTAssertNil(Freshness(nil))
    }

    func testBundledContentDates() throws {
        let notes = try DataStore.bundled([LabNote].self, "Labs")
        XCTAssertEqual(Freshness.labNotes(notes), Dates.parse("2026-09-30"))
        XCTAssertNotNil(Freshness.highlights(SnapshotTests.data.advances))
    }
}

final class AppVersionTests: XCTestCase {
    func testComparesVersionsNumerically() {
        XCTAssertTrue(AppVersion.isNewer("v1.2", than: "1.1"))
        XCTAssertTrue(AppVersion.isNewer("v1.10", than: "1.9"))     // not string order
        XCTAssertTrue(AppVersion.isNewer("1.1.1", than: "1.1"))
        XCTAssertFalse(AppVersion.isNewer("v1.1", than: "1.1"))
        XCTAssertFalse(AppVersion.isNewer("v1.1", than: "1.1.0"))
        XCTAssertFalse(AppVersion.isNewer("v1.0", than: "1.1"))
    }
}
