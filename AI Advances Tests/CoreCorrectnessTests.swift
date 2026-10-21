import XCTest
@testable import AI_Advances

/// Behaviour of the shared analysis core (parsing, matching, forecasts, track record, feed).
final class CoreCorrectnessTests: XCTestCase {
    private func d(_ s: String) -> Date { Dates.parse(s)! }

    private func result(_ b: String, _ model: String, _ date: String, _ score: Double, org: String = "Lab") -> BenchmarkResult {
        BenchmarkResult(benchmark: b, modelVersion: model, modelGroup: model, organization: org,
                        releaseDate: d(date), score: score)
    }

    private func info(_ name: String, released: String? = nil, baseline: Double = 0, ceiling: Double = 1,
                      supersededBy: String? = nil) -> BenchmarkInfo {
        BenchmarkInfo(name: name, sourceFile: "", scoreColumn: "", scale: 1, randomBaseline: baseline, ceiling: ceiling,
                      releaseDate: released.flatMap(Dates.parse), supersededBy: supersededBy)
    }

    private func listing(_ name: String, _ day: String, lab: String = "Lab", price: Double = 1) -> ListedModel {
        ListedModel(id: name, name: name, lab: lab, created: d(day), contextLength: 1000,
                    inputPrice: price, outputPrice: price, inputModalities: ["text"], outputModalities: ["text"])
    }

    // MARK: 1, 18 Parsing fallbacks

    private func folder(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("core-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testBenchmarkWithoutSourceFileFallsBackToItsExternalFile() throws {
        let dir = try folder([
            "benchmark_metadata.csv": """
                benchmark,in_eci,source_file,score_column,scale,random_baseline,score_ceiling,release_date,superseded_by
                HLE,False,,,1.0,0.048,1.0,2025-01-23,
                Some Bench,False,,,1.0,0,1.0,2025-01-23,
                GPQA diamond,True,gpqa_diamond.csv,mean_score,1.0,0.25,1.0,2023-11-20,

                """,
            "hle_external.csv": "Model version,Accuracy,Release date,Organization\nm-1,0.5,2026-01-01,OpenAI\n",
            "some_bench_external.csv": "Model version,Score,Release date,Organization\nm-1,0.5,2026-01-01,OpenAI\n",
            // Row 2 has no release date (model_metadata has one); row 3 has no version (Name does).
            "gpqa_diamond.csv": "Model version,mean_score,Release date,Organization,Name\nm-1,0.8,2026-01-01,OpenAI,\nm-2,0.7,,OpenAI,\n,0.6,2026-02-01,OpenAI,Some Model\n,0.5,,,\n",
            "model_metadata.csv": "model_version,model_group,date,display_name,organization\nm-2,Model Two,2025-12-01,,OpenAI\n",
        ])
        let p = try EpochParser.parse(in: dir)
        XCTAssertEqual(p.results.filter { $0.benchmark == "HLE" }.count, 1)
        XCTAssertEqual(p.infos.first { $0.name == "HLE" }?.scoreColumn, "Accuracy")
        XCTAssertTrue(p.warnings.contains { $0.hasPrefix("HLE:") })
        // An untracked benchmark with no source stays skipped, unless it's tracked.
        XCTAssertFalse(p.results.contains { $0.benchmark == "Some Bench" })
        XCTAssertEqual(try EpochParser.parse(in: dir, tracked: ["Some Bench"]).results.filter { $0.benchmark == "Some Bench" }.count, 1)

        let gpqa = p.results.filter { $0.benchmark == "GPQA diamond" }
        XCTAssertEqual(gpqa.count, 3)
        XCTAssertEqual(gpqa.first { $0.modelVersion == "m-2" }?.releaseDate, d("2025-12-01"))
        XCTAssertEqual(gpqa.first { $0.modelVersion == "Some Model" }?.score, 0.6)
        XCTAssertEqual(p.recoveredRows, 2)
    }

    func testFallbackFileMatchesIgnoringCaseAndPunctuation() {
        XCTAssertEqual(EpochParser.fallbackFile(for: "ScienceQA", among: ["science_qa_external.csv", "x.csv"]), "science_qa_external.csv")
        XCTAssertEqual(EpochParser.fallbackFile(for: "DeepSWE", among: ["DeepSWE_External.csv"]), "DeepSWE_External.csv")
        XCTAssertNil(EpochParser.fallbackFile(for: "Nothing", among: ["hle_external.csv"]))
    }

    func testTrackedBenchmarkWithNoResultsIsReported() {
        var data = Dataset()
        data.areas = [CapabilityArea(name: "A", summary: "", benchmarks: ["Present", "Gone"])]
        data.results = [result("Present", "m", "2026-01-01", 0.5)]
        XCTAssertTrue(Loader.missingTracked(data).contains("Gone"))
        XCTAssertFalse(Loader.missingTracked(data).contains("Present"))
    }

    // MARK: 2 Reconstruction respects benchmark release dates

    func testReconstructionLeavesOutBenchmarksNotYetReleased() {
        var data = Dataset()
        data.benchmarks = [info("Old", released: "2024-01-01"), info("New", released: "2026-03-01")]
        data.areas = [CapabilityArea(name: "A", summary: "", benchmarks: ["Old", "New"])]
        data.results = [result("Old", "m", "2025-06-01", 0.5), result("New", "m", "2025-06-01", 0.4)]
        let past = Forecasts.dataset(data, asOf: d("2026-01-01"))
        XCTAssertEqual(past.areas[0].benchmarks, ["Old"])
        XCTAssertFalse(past.results.contains { $0.benchmark == "New" })
        XCTAssertFalse(past.benchmarks.contains { $0.name == "New" })
        XCTAssertFalse(Forecasts.saturationForecasts(past, asOf: d("2026-01-01")).contains { $0.id == "sat-New" })
    }

    func testSnapshotReconstructionNeverForecastsAnUnreleasedBenchmark() {
        let data = SnapshotTests.data!
        let released = Dictionary(data.benchmarks.map { ($0.name, $0.releaseDate) }, uniquingKeysWith: { a, _ in a })
        for e in Forecasts.reconstructed(data, now: Dates.parse("2026-09-30")!, months: 18) {
            for id in e.forecasts.keys where id.hasPrefix("sat-") {
                if let r = released[String(id.dropFirst(4))] ?? nil { XCTAssertLessThanOrEqual(r, e.asOf, id) }
            }
        }
    }

    // MARK: 3–5 Track record

    private func forecast(_ id: String, reached: String? = nil, inactive: Bool = false) -> Forecast {
        Forecast(id: id, kind: .capabilities, area: "A", title: id, target: "", current: "", basis: "",
                 reached: reached.flatMap(Dates.parse), predicted: nil, early: nil, late: nil, note: nil, inactive: inactive)
    }

    private func entry(_ asOf: String, live: Bool = false, _ snaps: [String: (String, String, String?)]) -> ForecastLogEntry {
        ForecastLogEntry(asOf: d(asOf), reconstructed: !live, forecasts: snaps.mapValues { s in
            ForecastSnapshot(predicted: Dates.parse(s.0), early: Dates.parse(s.1), late: s.2.flatMap(Dates.parse), reached: nil)
        })
    }

    func testExpiredRangesCountAsMissesAndOpenEndedAreSeparate() {
        let now = d("2026-10-01")
        let history = [
            entry("2025-10-01", ["hit": ("2026-05-01", "2026-03-01", "2026-08-01"),
                                 "overdue": ("2026-03-01", "2026-01-01", "2026-06-01"),
                                 "open": ("2026-05-01", "2026-03-01", nil)]),
            // Still running: late end in the future, so not scored yet.
            entry("2026-05-01", ["overdue": ("2026-12-01", "2026-11-01", "2027-03-01")]),
        ]
        let r = TrackRecord.score(history: history, current: [forecast("hit", reached: "2026-06-01"), forecast("overdue"),
                                                              forecast("open", reached: "2026-06-01")], now: now)
        XCTAssertEqual(r.scored, 2)          // hit + overdue
        XCTAssertEqual(r.inside, 1)
        XCTAssertEqual(r.expired, 1)
        XCTAssertEqual(r.openEnded, 1)
        XCTAssertEqual(r.milestones, 3)
        XCTAssertEqual(r.missed.map(\.forecastID), ["overdue"])
        XCTAssertEqual(r.missed.first?.outcome, .expired)
        XCTAssertEqual(r.coverage, 0.5)
        XCTAssertTrue(r.summary.contains("1 of 2 forecasts on 3 milestones"), r.summary)
        XCTAssertTrue(r.summary.contains("ran out"), r.summary)
        XCTAssertTrue(r.summary.contains("no end date"), r.summary)
        XCTAssertEqual(r.summary.filter { $0 == "." }.count, 1, "one sentence: \(r.summary)")
    }

    func testInactiveForecastsAreNotScoredAsExpired() {
        let history = [entry("2025-10-01", ["gone": ("2026-03-01", "2026-01-01", "2026-06-01")])]
        let r = TrackRecord.score(history: history, current: [forecast("gone", inactive: true)], now: d("2026-10-01"))
        XCTAssertEqual(r.scored, 0)
    }

    func testOneScoredForecastPerMilestonePerMonth() {
        let snap = ["x": ("2026-05-01", "2026-03-01", "2026-08-01")]
        // A daily log: thirty near-identical forecasts in one month, plus a reconstructed one.
        var history = (1...28).map { day in entry(String(format: "2025-11-%02d", day), live: true, snap) }
        history.append(entry("2025-11-01", snap))
        history.append(entry("2025-12-01", snap))
        let r = TrackRecord.score(history: history, current: [forecast("x", reached: "2026-06-01")], now: d("2026-10-01"))
        XCTAssertEqual(r.scored, 2)
        XCTAssertEqual(r.allItems.map(\.madeOn), [d("2025-11-01"), d("2025-12-01")])
    }

    // MARK: 6 Inactive benchmarks

    private func inactiveData() -> Dataset {
        var data = Dataset()
        data.benchmarks = [info("Live"), info("Stale")]
        data.areas = [CapabilityArea(name: "A", summary: "", benchmarks: ["Live", "Stale"])]
        data.results = [
            result("Live", "a", "2025-01-01", 0.2, org: "OpenAI"), result("Live", "b", "2025-06-01", 0.3, org: "OpenAI"),
            result("Live", "c", "2025-11-01", 0.4, org: "OpenAI"), result("Live", "d", "2026-04-01", 0.5, org: "OpenAI"),
            result("Live", "e", "2026-09-01", 0.6, org: "OpenAI"),
            result("Stale", "a", "2025-01-01", 0.2, org: "Anthropic"), result("Stale", "b", "2025-03-01", 0.3, org: "Anthropic"),
            result("Stale", "c", "2025-05-01", 0.4, org: "Anthropic"), result("Stale", "d", "2026-04-01", 0.5, org: "Anthropic"),
        ]
        return data
    }

    func testInactiveBenchmarksAreLeftOutEverywhere() {
        let data = inactiveData()
        let now = d("2026-10-01")
        XCTAssertEqual(Analysis.inactiveBenchmarks(data.results, now: now), ["Stale"])

        let sat = Forecasts.saturationForecasts(data, asOf: now)
        let stale = sat.first { $0.id == "sat-Stale" }!
        XCTAssertTrue(stale.inactive)
        XCTAssertNil(stale.predicted)
        XCTAssertEqual(stale.note, "No longer updated by Epoch")
        XCTAssertFalse(sat.first { $0.id == "sat-Live" }!.inactive)

        let m = Analysis.momentum(area: data.areas[0], results: data.results, infos: data.benchmarks, now: now)!
        XCTAssertEqual(m.benchmarksUsed, 1)
        XCTAssertEqual(m.excludedInactive, 1)

        XCTAssertFalse(Analysis.recentRecords(data, since: d("2025-01-01"), now: now).contains { $0.point.benchmark == "Stale" })
        XCTAssertTrue(Analysis.recentRecords(data, since: d("2025-01-01")).contains { $0.point.benchmark == "Stale" })
        XCTAssertFalse(Feed.items(data, now: now).contains { $0.title.contains("Stale") })

        let labs = Labs.summaries(data, notes: [], now: now)
        XCTAssertEqual(labs.first { $0.name == "OpenAI" }?.recordsHeld, ["Live"])
        XCTAssertEqual(labs.first { $0.name == "Anthropic" }?.recordsHeld ?? [], [])
    }

    // MARK: 7, 14 Momentum

    func testMomentumLeavesOutReachedBenchmarks() {
        let area = CapabilityArea(name: "A", summary: "", benchmarks: ["Done", "Open"])
        let now = d("2026-01-01")
        let rs = [result("Done", "a", "2025-06-01", 0.85), result("Done", "b", "2025-12-01", 0.95),
                  result("Open", "a", "2024-12-01", 0.5), result("Open", "b", "2025-10-01", 0.75)]
        let m = Analysis.momentum(area: area, results: rs, infos: [], now: now, months: 12)!
        XCTAssertEqual(m.benchmarksUsed, 1)
        XCTAssertEqual(m.excludedReached, 1)
        XCTAssertEqual(m.gapClosed, 0.5, accuracy: 1e-9)
    }

    func testMomentumAndStandingMeasureFromRandomChance() {
        // 25% is chance on a 4-way multiple-choice benchmark: going from below chance to 62.5%
        // closes half of the above-chance headroom, not 62.5 / 100 of it.
        let b = info("MC", baseline: 0.25)
        XCTAssertEqual(Analysis.normalized(0.625, info: b), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Analysis.normalized(0.1, info: b), 0)
        let area = CapabilityArea(name: "A", summary: "", benchmarks: ["MC"])
        let rs = [result("MC", "a", "2024-06-01", 0.1), result("MC", "b", "2025-06-01", 0.625)]
        let m = Analysis.momentum(area: area, results: rs, infos: [b], now: d("2025-07-01"), months: 12)!
        XCTAssertEqual(m.gapClosed, 0.5, accuracy: 1e-9)

        var data = Dataset()
        data.benchmarks = [b]
        data.areas = [area]
        data.results = [result("MC", "a", "2025-06-01", 0.25, org: "OpenAI"), result("MC", "b", "2025-07-01", 1.0, org: "Anthropic")]
        let labs = Labs.summaries(data, notes: [], now: d("2025-08-01"))
        XCTAssertEqual(labs.first { $0.name == "OpenAI" }?.standing["A"] ?? -1, 0, accuracy: 1e-9)   // chance level = no standing
    }

    // MARK: 8, 9, 11, 21 Name matching

    func testMatchKeyKeepsRealDistinctions() {
        XCTAssertNotEqual(Analysis.matchKey("Qwen2.5-Coder (1.5B)"), Analysis.matchKey("Qwen2.5-Coder (7B)"))
        XCTAssertNotEqual(Analysis.matchKey("GPT-4o (Aug 2024)"), Analysis.matchKey("GPT-4o (May 2024)"))
        XCTAssertEqual(Analysis.matchKey("GPT-4o (Aug 2024)"), Analysis.matchKey("OpenAI: GPT-4o (2024-08-06)"))
        XCTAssertNotEqual(Analysis.matchKey("Command A"), Analysis.matchKey("Command A+"))
        XCTAssertNotEqual(Analysis.matchKey("OPT-1.3B"), Analysis.matchKey("opt-13b"))
        XCTAssertNotEqual(Analysis.matchKey("o1"), Analysis.matchKey("o1-preview"))
        XCTAssertNotEqual(Analysis.matchKey("Qwen2.5-Coder-32B"), Analysis.matchKey("Qwen2.5-Coder-32B-Instruct"))
        XCTAssertNotEqual(Analysis.matchKey("GPT-6.1"), Analysis.matchKey("GPT-6"))
    }

    func testMatchKeyStripsLabAndHostPrefixes() {
        XCTAssertEqual(Analysis.matchKey("Tencent Hy4 preview"), Analysis.matchKey("Tencent: Hy4 preview"))
        XCTAssertEqual(Analysis.matchKey("Tencent Hy4 preview"), Analysis.matchKey("Hy4 preview"))
        XCTAssertEqual(Analysis.matchKey("chutes/GLM-4.5"), Analysis.matchKey("Z.ai: GLM 4.5"))
        XCTAssertEqual(Analysis.matchKey("deepinfra/Qwen3-Next-80B-A3B-Instruct"), Analysis.matchKey("Qwen: Qwen3 Next 80B A3B Instruct"))
        XCTAssertEqual(Analysis.matchKey("accounts/fireworks/models/kimi-k2"), Analysis.matchKey("MoonshotAI: Kimi K2"))
        XCTAssertEqual(Analysis.matchKey("nvidia-nemotron-nano-9b-v2"), Analysis.matchKey("NVIDIA: Nemotron Nano 9B V2"))
    }

    func testProfilesPreferExactMatchesAndDontShareListings() {
        var data = Dataset()
        data.results = ["Gemini 3.1 Pro", "o1", "o1-preview", "DeepSeek-V4-Pro", "Gemini 2.5 Flash (May 2025)", "Gemini 2.5 Flash (Jun 2025)"]
            .map { result("B", $0, "2026-01-01", 0.5) }
        data.listed = [listing("Gemini 3.1 Pro Preview", "2025-11-01"), listing("Gemini 3.1 Pro", "2026-01-15"),
                       listing("o1", "2024-12-17"), listing("o1-preview", "2024-09-12"),
                       listing("DeepSeek V4 Pro 0423", "2026-04-23"), listing("Gemini 2.5 Flash", "2025-06-17")]
        let ps = Dictionary(uniqueKeysWithValues: Analysis.profiles(data).map { ($0.name, $0) })
        XCTAssertEqual(ps["Gemini 3.1 Pro"]?.listing?.name, "Gemini 3.1 Pro")       // not the earlier preview
        XCTAssertEqual(ps["Gemini 3.1 Pro"]?.listingIsExact, true)
        XCTAssertEqual(ps["o1"]?.listing?.name, "o1")
        XCTAssertEqual(ps["o1-preview"]?.listing?.name, "o1-preview")
        XCTAssertEqual(ps["DeepSeek-V4-Pro"]?.listing?.name, "DeepSeek V4 Pro 0423")   // loose, unambiguous
        XCTAssertEqual(ps["DeepSeek-V4-Pro"]?.listingIsExact, false)
        // Two dated Epoch entries share the loose key: the listing goes to the one dated nearest it.
        XCTAssertEqual(ps["Gemini 2.5 Flash (Jun 2025)"]?.listing?.name, "Gemini 2.5 Flash")
        XCTAssertNil(ps["Gemini 2.5 Flash (May 2025)"]?.listing)
    }

    func testLooseListingDateDoesNotBackdatePriceSteps() {
        func profile(_ exact: Bool) -> ModelProfile {
            ModelProfile(name: "m", lab: "Lab", released: d("2026-06-01"), scores: ["B": 0.9], horizonMinutes: nil,
                         listing: listing("m 0101", "2025-01-01"), computeFLOP: nil, openWeights: nil, listingIsExact: exact)
        }
        XCTAssertEqual(Analysis.cheapestOverTime([profile(true)], benchmark: "B", threshold: 0.8).first?.date, d("2025-01-01"))
        XCTAssertEqual(Analysis.cheapestOverTime([profile(false)], benchmark: "B", threshold: 0.8).first?.date, d("2026-06-01"))
    }

    // MARK: 10 Canonical labs

    func testOrganizationsMapToCanonicalLabs() {
        XCTAssertEqual(Labs.canonical(openRouter: "Google"), "Google DeepMind")
        XCTAssertEqual(Labs.canonical(openRouter: "Mistral"), "Mistral AI")
        XCTAssertEqual(Labs.canonical(openRouter: "Meta Llama"), "Meta")
        XCTAssertEqual(Labs.canonical(epoch: "Meta AI"), "Meta")
        XCTAssertEqual(Labs.canonical(epoch: "Google"), "Google DeepMind")
        XCTAssertEqual(Labs.canonical(epoch: "Z.ai (Zhipu AI),Tsinghua University"), "Z.ai")
        XCTAssertEqual(Labs.canonical(epoch: "Poolside"), "Poolside")   // unknown: its own name

        var data = Dataset()
        data.results = [result("B", "Hy4", "2026-01-01", 0.5, org: ""), result("B", "Gem", "2026-01-01", 0.5, org: "Google")]
        data.listed = [listing("Hy4", "2026-01-01", lab: "Tencent")]
        let ps = Dictionary(uniqueKeysWithValues: Analysis.profiles(data).map { ($0.name, $0.lab) })
        XCTAssertEqual(ps["Hy4"], "Tencent")             // no Epoch organization: from its listing
        XCTAssertEqual(ps["Gem"], "Google DeepMind")

        // No organization, no listing: the family's lab.
        XCTAssertEqual(Labs.family("Qwen2.5-Coder-3B-Instruct"), "qwen")
        XCTAssertEqual(Labs.family("chutes/GLM-4.5-FP8"), "glm")
        XCTAssertEqual(Labs.inferredLab("granite-4.0-1b", families: [:]), "IBM")
        XCTAssertNil(Labs.inferredLab("gpt-j-6b", families: ["gpt": ["OpenAI", "EleutherAI"]]))
        XCTAssertNil(Labs.inferredLab("tiny-recursion-model", families: [:]))
        XCTAssertEqual(Labs.canonical(openRouter: "mistralai"), "Mistral AI")
        XCTAssertEqual(Labs.canonical(openRouter: "microsoft"), Labs.canonical(epoch: "Microsoft Research"))

        let items = Feed.modelListings([listing("Mistral Small 5", "2026-01-01", lab: "Mistral")])
        XCTAssertEqual(items.first?.lab, "Mistral AI")
        XCTAssertEqual(items.first?.title, "Mistral AI lists Mistral Small 5")
    }

    // MARK: 12 METR lower bound

    func testHorizonAtTheTopOfTheSuiteIsALowerBound() {
        func h(_ minutes: Double, _ score: Double?) -> TimeHorizon {
            TimeHorizon(modelVersion: "m", modelGroup: "M", organization: "", releaseDate: d("2026-04-07"), minutes: minutes, averageScore: score)
        }
        XCTAssertTrue(Analysis.horizonIsLowerBound(h(1044, 0.85)))
        XCTAssertTrue(Analysis.horizonIsLowerBound(h(1000, nil)))
        XCTAssertFalse(Analysis.horizonIsLowerBound(h(700, 0.79)))

        var data = Dataset()
        data.horizons = [h(10, 0.2), h(30, 0.3), h(100, 0.5), h(300, 0.7), h(1044, 0.86)].enumerated().map { i, x in
            TimeHorizon(modelVersion: "m\(i)", modelGroup: "M\(i)", organization: "", releaseDate: d("2023-06-01").addingTimeInterval(Double(i) * 200 * 86_400),
                        minutes: x.minutes, averageScore: x.averageScore)
        }
        let f = Forecasts.horizon(data, asOf: d("2026-10-01")).first!
        XCTAssertTrue(f.current.hasPrefix("at least "), f.current)
        XCTAssertTrue(f.basis.contains("newest model METR has measured was released"), f.basis)
    }

    // MARK: 13, 22 Outlook wording, range width as a parameter

    func testOutlookSaysWhatItComputes() {
        func up(_ id: String, _ area: String, _ p: String) -> Forecast {
            Forecast(id: id, kind: .capabilities, area: area, title: "\(id) reaches 90%", target: "", current: "", basis: "",
                     reached: nil, predicted: d(p), early: d(p), late: d(p), note: nil)
        }
        let upcoming = [up("a", "Math", "2027-01-01"), up("b", "Coding", "2028-01-01")]
        let reached = Forecast(id: "c", kind: .capabilities, area: "Vision", title: "c", target: "", current: "", basis: "",
                               reached: d("2026-01-01"), predicted: nil, early: nil, late: nil, note: nil)
        let now = d("2026-10-01")
        let shift = ForecastShift(forecast: upcoming[0], months: -2, since: d("2026-07-01"))
        let text = Forecasts.outlook(upcoming, shifts: [shift], now: now, all: upcoming + [reached])
        XCTAssertFalse(text.contains("closest to saturating"))
        XCTAssertTrue(text.contains("math has the nearest upcoming benchmark milestone"), text)
        XCTAssertTrue(text.contains("In vision, every tracked benchmark Epoch still updates has already passed its target"), text)
        XCTAssertTrue(text.contains("Compared with the forecasts made in Jul 2026"), text)
    }

    func testRangeWidthIsAParameter() {
        let data = SnapshotTests.data!
        let now = Dates.parse("2026-09-30")!
        let profiles = Analysis.profiles(data)
        let narrow = Forecasts.all(data, profiles: profiles, asOf: now, z: 1)
        let wide = Forecasts.all(data, profiles: profiles, asOf: now, z: 4)
        let byID = Dictionary(uniqueKeysWithValues: wide.map { ($0.id, $0) })
        var compared = 0
        for f in narrow {
            guard let e1 = f.early, let e2 = byID[f.id]?.early else { continue }
            XCTAssertLessThanOrEqual(e2, e1, f.id)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 3)
        XCTAssertEqual(Forecasts.all(data, profiles: profiles, asOf: now).map(\.early),
                       Forecasts.all(data, profiles: profiles, asOf: now, z: Forecasts.calibratedZ).map(\.early))
    }

    // MARK: 15 Record dates

    func testRecordIsNotDatedBeforeItsBenchmark() {
        var data = Dataset()
        data.benchmarks = [info("B", released: "2026-05-01")]
        data.areas = [CapabilityArea(name: "A", summary: "", benchmarks: ["B"])]
        data.results = [result("B", "old", "2025-01-01", 0.3), result("B", "older-but-better", "2026-04-01", 0.5)]
        let r = Analysis.recentRecords(data, since: d("2025-01-01")).first!
        XCTAssertEqual(r.date, d("2026-05-01"))
        let item = Feed.items(data, now: d("2026-06-01")).first { $0.kind == .records }!
        XCTAssertEqual(item.date, d("2026-05-01"))
    }

    // MARK: 16 Compute trend

    func testComputeFitUsesRunningMaximumNotFrontierFlag() {
        func m(_ name: String, _ date: String, _ flop: Double, frontier: Bool) -> NotableModel {
            NotableModel(name: name, organization: "", date: d(date), domain: "", computeFLOP: flop, parameters: nil,
                         isFrontier: frontier, openWeights: nil)
        }
        let models = [m("a", "2020-06-01", 1e23, frontier: false), m("small", "2021-01-01", 1e20, frontier: true),
                      m("b", "2021-06-01", 1e24, frontier: false), m("c", "2022-06-01", 1e25, frontier: false),
                      m("d", "2023-06-01", 1e26, frontier: false)]
        XCTAssertEqual(Analysis.computeRecords(models, since: d("2020-01-01")).map(\.name), ["a", "b", "c", "d"])
        XCTAssertEqual(Analysis.computeFit(models, since: d("2020-01-01"))!.factorPerYear, 10, accuracy: 0.05)
    }

    // MARK: 17 Partial quarters

    func testPartialAndSparseQuartersAreMarkedOrDropped() {
        let listed = (0..<10).map { listing("full\($0)", "2026-04-1\($0 % 9)") }
            + (0..<9).map { listing("now\($0)", "2026-10-0\($0 % 9 + 1)") }
            + (0..<3).map { listing("sparse\($0)", "2026-01-0\($0 + 1)") }
        let now = d("2026-10-20")
        let shares = Analysis.modalityShares(listed, since: d("2026-01-01"), now: now)
        XCTAssertEqual(Set(shares.map(\.quarter)), ["Q2 2026", "Q4 2026"])
        XCTAssertEqual(shares.first { $0.quarter == "Q4 2026" }?.partial, true)
        XCTAssertEqual(shares.first { $0.quarter == "Q2 2026" }?.partial, false)
        let medians = Analysis.contextMedians(listed, since: d("2026-01-01"), now: now)
        XCTAssertEqual(medians.map(\.partial), [false, true])
        XCTAssertEqual(Analysis.medianContextByQuarter(listed, since: d("2026-01-01"), now: now).count, 2)
    }

    // MARK: 19 Supersession

    func testSupersededBenchmarksAreFollowedWhenTheSuccessorHasData() {
        var data = Dataset()
        data.benchmarks = [info("WeirdML"), info("WeirdML v3"), info("Old", supersededBy: "New"), info("New")]
        data.results = [result("WeirdML", "m", "2026-01-01", 0.5), result("Old", "m", "2026-01-01", 0.5)]
        XCTAssertEqual(Analysis.keyBenchmarks(for: data).first { $0.label == "WeirdML" }?.name, "WeirdML")   // v3 has no data
        data.results += [result("WeirdML v3", "m", "2026-01-01", 0.4), result("New", "m", "2026-01-01", 0.4)]
        XCTAssertEqual(Analysis.keyBenchmarks(for: data).first { $0.label == "WeirdML" }?.name, "WeirdML v3")
        let areas = Analysis.followSupersession([CapabilityArea(name: "A", summary: "", benchmarks: ["Old", "New", "X"])], data: data)
        XCTAssertEqual(areas[0].benchmarks, ["New", "X"])
    }

    // MARK: 20 Dates

    func testFastDateParsingMatchesTheFormatter() {
        for s in ["2026-10-20", "2024-02-29", "1999-12-31", "2026-01-01T12:00:00Z", "2000-03-01 extra"] {
            XCTAssertEqual(Dates.parse(s), Dates.day.date(from: String(s.prefix(10))), s)
        }
        for s in ["2026-02-30", "2026-13-01", "2025-02-29", "2026-00-10", "abc", "", "2026-1-5", "26-10-20xx"] {
            XCTAssertNil(Dates.parse(s), s)
        }
        XCTAssertNil(Dates.parse(nil))
    }

    func testAdvanceDayIsDecodedOnce() throws {
        let json = #"[{"date":"2026-09-03","title":"t","lab":"l","category":"c","direction":"d","summary":"s","source":"https://x"}]"#
        let a = try JSONDecoder().decode([Advance].self, from: Data(json.utf8))[0]
        XCTAssertEqual(a.day, d("2026-09-03"))
        XCTAssertNil(a.datePrecision)
        let back = try JSONDecoder().decode([Advance].self, from: JSONEncoder().encode([a]))
        XCTAssertEqual(back, [a])
    }

    // MARK: 21 Performance

    func testReconstructionIsFast() {
        let data = SnapshotTests.data!
        _ = Analysis.profiles(data)   // warm the name-key memo as the app does on load
        // CPU time of this thread, so a busy machine doesn't fail the test.
        func cpu() -> Double {
            var t = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
            return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
        }
        let start = cpu()
        let log = Forecasts.reconstructed(data, now: Dates.parse("2026-09-30")!, months: 18)
        let seconds = cpu() - start
        print(String(format: "PERF reconstructed(18 months) %.2f s CPU", seconds))
        XCTAssertEqual(log.count, 18)
        // About 0.8 s optimized (2.0 s before memoizing name keys); unoptimized Debug builds run ~10x slower.
        #if DEBUG
        let limit = 20.0
        #else
        let limit = 2.0
        #endif
        XCTAssertLessThan(seconds, limit, "reconstructing 18 months took \(seconds) s of CPU")
    }

    // MARK: 23 Grammar

    func testArticleFollowsTheSound() {
        XCTAssertEqual(Feed.article("APEX-Agents"), "an")
        XCTAssertEqual(Feed.article("HLE"), "an")
        XCTAssertEqual(Feed.article("OSWorld 2"), "an")
        XCTAssertEqual(Feed.article("ARC-AGI-2"), "an")
        XCTAssertEqual(Feed.article("GPQA"), "a")
        XCTAssertEqual(Feed.article("FrontierMath"), "a")
        XCTAssertEqual(Feed.article("METR Time Horizons"), "a")
        XCTAssertEqual(Feed.article("SWE-bench"), "a")
        XCTAssertEqual(Feed.article("SimpleQA"), "a")
    }
}
