import Foundation

enum Export {
    static let sources = [
        SiteData.Source(name: "Epoch AI benchmarks", credit: "Epoch AI, ‘Capabilities & benchmarking’ (CC BY 4.0)", page: "https://epoch.ai/benchmarks"),
        SiteData.Source(name: "Epoch AI notable models", credit: "Epoch AI, ‘Data on AI Models’ (CC BY 4.0)", page: "https://epoch.ai/data/ai-models"),
        SiteData.Source(name: "OpenRouter model list", credit: "OpenRouter public models API", page: "https://openrouter.ai/models"),
    ]

    static func build(_ data: Dataset, notes: [LabNote], now: Date, logURL: URL?) -> SiteData {
        let profiles = Analysis.profiles(data)
        let since2022 = Dates.parse("2022-01-01")!
        let since2024 = Dates.parse("2024-01-01")!

        // Forecasts, today's log entry and history.
        let current = Forecasts.all(data, profiles: profiles, asOf: now)
        let live = logURL.map { ForecastLog.record(current, on: now, to: $0) } ?? []
        let history = Forecasts.reconstructed(data, now: now) + live
        let upcoming = current.filter { $0.reached == nil && $0.predicted != nil }.sorted { $0.predicted! < $1.predicted! }
        let shifts = Forecasts.shifts(upcoming, history: history, now: now)

        // Results: only the benchmarks the site charts, since 2022.
        let charted = Set(data.areas.flatMap(\.benchmarks) + Analysis.keyBenchmarks.map(\.name))
        let results = data.results.filter { charted.contains($0.benchmark) && $0.releaseDate >= since2022 }

        return SiteData(
            generatedAt: now,
            latestDataDate: [data.results.map(\.releaseDate).max(), data.listed.map(\.created).max()].compactMap { $0 }.max(),
            sources: sources,
            tiles: tiles(data, profiles: profiles, now: now),
            keyBenchmarks: Analysis.keyBenchmarks.map { [$0.name, $0.label] },
            areas: data.areas.map { a in
                SiteData.Area(name: a.name, summary: a.summary, benchmarks: a.benchmarks,
                              momentum: Dictionary(uniqueKeysWithValues: [6, 12, 24].compactMap { m in
                                  Analysis.momentum(area: a, results: data.results, infos: data.benchmarks, now: now, months: m).map {
                                      ("\(m)", SiteData.Momentum(gapClosed: $0.gapClosed, pointsGained: $0.pointsGained, benchmarksUsed: $0.benchmarksUsed))
                                  }
                              }))
            },
            benchmarks: data.benchmarks.filter { charted.contains($0.name) }.map {
                SiteData.Benchmark(name: $0.name, short: Analysis.shortName($0.name), ceiling: $0.ceiling, released: $0.releaseDate)
            },
            results: results.map { SiteData.Result(b: $0.benchmark, m: $0.modelGroup, o: $0.organization, d: $0.releaseDate, s: round4($0.score)) },
            horizons: Analysis.horizonFrontier(data.horizons).map {
                SiteData.Horizon(model: $0.modelGroup, org: $0.organization, date: $0.releaseDate, minutes: $0.minutes)
            },
            models: profiles.map { p in
                SiteData.Model(name: p.name, lab: p.lab, released: p.released,
                               scores: p.scores.mapValues(round4), horizonMinutes: p.horizonMinutes,
                               computeFLOP: p.computeFLOP, openWeights: p.openWeights,
                               price: p.listing.flatMap { $0.isFree ? nil : $0.blendedPrice },
                               inputPrice: p.listing?.inputPrice, outputPrice: p.listing?.outputPrice,
                               context: p.listing?.contextLength,
                               inputModalities: p.listing?.inputModalities.sorted(),
                               outputModalities: p.listing?.outputModalities.sorted(),
                               listedOn: p.listing?.created)
            },
            listed: data.listed.filter { $0.created >= since2024 }.map {
                SiteData.Listed(id: $0.id, name: $0.name, lab: $0.lab, created: $0.created, context: $0.contextLength,
                                price: $0.blendedPrice, free: $0.isFree,
                                input: $0.inputModalities.sorted(), output: $0.outputModalities.sorted())
            },
            modalityShares: Analysis.modalityShares(data.listed, since: since2024).map {
                SiteData.Share(quarter: $0.quarter, start: $0.quarterStart, modality: $0.modality, share: $0.share, count: $0.count)
            },
            contextMedians: Analysis.medianContextByQuarter(data.listed, since: since2024).map { SiteData.Point(date: $0.0, value: $0.1) },
            notable: data.notable.filter { $0.computeFLOP != nil && $0.date >= Dates.parse("2010-01-01")! }.map {
                SiteData.Notable(name: $0.name, org: $0.organization, date: $0.date, flop: $0.computeFLOP!, frontier: $0.isFrontier)
            },
            computeFit: Analysis.computeFit(data.notable, since: Dates.parse("2020-01-01")!).map { fit in
                [Dates.parse("2020-01-01")!, now].map { SiteData.Point(date: $0, value: fit.value(at: $0)) }
            } ?? [],
            feed: Feed.items(data, now: now).map {
                SiteData.Item(date: $0.date, title: $0.title, detail: $0.detail, lab: $0.lab,
                              kind: $0.kind.rawValue, direction: $0.direction, link: $0.link)
            },
            forecasts: current.map {
                SiteData.Forecast(id: $0.id, kind: $0.kind.rawValue, area: $0.area, title: $0.title, target: $0.target,
                                  current: $0.current, basis: $0.basis, reached: $0.reached, predicted: $0.predicted,
                                  early: $0.early, late: $0.late, note: $0.note)
            },
            outlook: Forecasts.outlook(upcoming, shifts: shifts, now: now),
            shifts: shifts.map { SiteData.Shift(id: $0.id, title: $0.forecast.title, months: $0.months, predicted: $0.forecast.predicted) },
            history: history.sorted { $0.asOf < $1.asOf }.map { SiteData.HistoryEntry(asOf: $0.asOf, live: !$0.reconstructed, forecasts: $0.forecasts) },
            labs: Labs.summaries(data, notes: notes, now: now).map { l in
                SiteData.Lab(name: l.name, note: l.note, standing: l.standing,
                             recordsHeld: l.recordsHeld.map(Analysis.shortName), recentRecords: l.recentRecords,
                             releasesByQuarter: l.releasesByQuarter.sorted { $0.key < $1.key }.map {
                                 .init(quarter: Analysis.quarterLabel($0.key), start: $0.key, count: $0.value)
                             },
                             recentModels: l.recentModels, latestName: l.latest?.name, latestDate: l.latest?.date,
                             modalityShare: l.modalityShare, openShare: l.openShare,
                             priceMin: l.priceRange?.lowerBound, priceMax: l.priceRange?.upperBound, largestRun: l.largestRun)
            })
    }

    static func tiles(_ data: Dataset, profiles: [ModelProfile], now: Date) -> SiteData.Tiles {
        let compute = Analysis.computeFit(data.notable, since: Dates.parse("2020-01-01")!)
        let horizons = Analysis.horizonFrontier(data.horizons)
        let horizonFit = ExpFit.fit(horizons.filter { $0.releaseDate >= Dates.parse("2023-01-01")! }.map { ($0.releaseDate, $0.minutes) })
        let price = Analysis.cheapestOverTime(profiles, benchmark: "GPQA diamond", threshold: 0.8)
        return SiteData.Tiles(
            computeFactorPerYear: compute?.factorPerYear, computeDoublingMonths: compute?.doublingMonths, computeModels: compute?.n ?? 0,
            horizonMinutes: horizons.last?.minutes, horizonModel: horizons.last?.modelGroup,
            horizonDoublingMonths: horizonFit?.doublingMonths,
            priceNow: price.last?.price, priceModel: price.last?.model,
            priceFirst: price.first?.price, priceFirstModel: price.first?.model,
            maxContext: data.listed.map(\.contextLength).max() ?? 0,
            medianContextThisQuarter: Analysis.medianContextByQuarter(data.listed, since: now.addingTimeInterval(-365.25 * 86_400)).last?.1)
    }

    static func round4(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }
}
