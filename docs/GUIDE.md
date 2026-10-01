# AI Advances Guide

## Setup

You need macOS 14 or later and Xcode 16 or later.

```bash
git clone git@github.com:amalmehta/ai-advances.git
cd ai-advances
open "AI Advances.xcodeproj"
```

Press **⌘R** in Xcode to run. To build from the terminal instead:

```bash
xcodebuild -project "AI Advances.xcodeproj" -scheme "AI Advances" -derivedDataPath build build
open "build/Build/Products/Debug/AI Advances.app"
```

Run the tests with:

```bash
xcodebuild -project "AI Advances.xcodeproj" -scheme "AI Advances" -derivedDataPath build test
```

To render the Forecasts and Labs pages to full-length PNGs for review, set `TEST_RUNNER_RENDER_PAGES` to an output folder when running the tests.

The Xcode project is generated from `project.yml`; `Package.swift` only builds the website's data exporter. After adding or moving files, regenerate it with `xcodegen generate` (install it with `brew install xcodegen`).

## Website

The website at **https://amalmehta.github.io/ai-advances/** has the same nine pages as the app. It's built by `.github/workflows/update-website.yml`, which runs every day at 06:17 UTC, on every push that touches the site or the analysis code, and on demand (Actions → *Update website* → *Run workflow*). Each run:

1. Downloads the three sources (falling back to the snapshot in the repo if one fails).
2. Builds `ai-advances-export` (the `Package.swift` target) from the same `AI Advances/Data` code as the Mac app, and writes `site/data/site.json`.
3. Adds the day's forecasts to `forecast-log.json` on the `data` branch, as a commit by `github-actions[bot]`. This is the website's forecast history; `main` stays clean.
4. Publishes `site/` to GitHub Pages.

To work on the site locally:

```bash
swift build -c release
```

```bash
.build/release/ai-advances-export --sources "AI Advances/Resources/Seed" --resources "AI Advances/Resources" --out site/data
```

```bash
python3 -m http.server 8765 --directory site
```

Then open http://localhost:8765. The site is plain HTML, CSS and JavaScript (`site/index.html`, `site/styles.css`, `site/app.js`), with charts from Observable Plot loaded from jsDelivr. There's no build step.

## Pages

| Page | What it answers |
|---|---|
| **Direction Trends** | Where things are heading. Four headline trends: training compute growth, the longest task AI can do (METR time horizon), the price of GPQA ≥ 80%, and the largest context window. Also shows which capability areas closed the most headroom over the last 6, 12 or 24 months, and small charts of the best score over time per area. |
| **Forecasts** | Where the field goes next. Dated predictions with 90% ranges: when AI handles week- and month-long tasks, when each tracked benchmark reaches 90%, when training runs reach 10^28 and 10^29 FLOP, and when GPQA-level ability costs under $0.01 per million tokens. Also an outlook written from those numbers, the forecasts that moved most in the last 3 months, a history chart for each forecast, and lists of milestones already reached and those that have stalled. |
| **Labs** | Who's working on what. A heatmap of each lab's standing per capability area (★ = holds a record), a heatmap of release pace by quarter, and a card per lab with its researched focus, bets and flagships, plus live facts: latest model, records held, modalities, open-weights share, price range and largest training run. |
| **Latest Advances** | What happened recently. Researched highlights with sources, plus new benchmark records and newly listed models, which are detected on every refresh. Filter by kind and by direction (Reasoning, Coding, Agents, and so on). |
| **Capabilities** | Pick an area to see every model result as a dot, with the record line on top, and a top-8 leaderboard for each benchmark. |
| **Models** | A sortable table of recent models with price, context window and their best score on seven key benchmarks. Select a row for the model's full profile. |
| **Cost** | Pick a benchmark and a score. The chart shows the cheapest model that had reached that score by each date, and a price-vs-score scatter. |
| **Context & Modalities** | Context windows over time, and the share of new models taking image, file, audio or video input, or producing images. |
| **Compute** | Training compute of notable models on a log scale, with the frontier trend line and the largest training runs. |

Hover any chart for details. The toolbar shows when data last updated; click it for sources and any update errors. **⌘R** or the refresh button fetches new data immediately.

## How the forecasts work

- **Compute, task horizon and price:** a straight-line fit on a log scale, meaning steady exponential change. Task horizon uses METR record-setters since 2023, compute uses Epoch's frontier training runs since 2020, and price uses the successive drops in the cheapest model scoring at least 80% on GPQA Diamond.
- **Benchmarks:** an S-curve (linear in logit) fitted to the record-setting scores of the last two years, since scores flatten as they near 100%.
- **Ranges:** the 90% range comes from the uncertainty in the fitted slope. It doesn't account for breakthroughs, slowdowns or benchmark changes.
- **Stalled milestones:** if a trend says a milestone was due in the past but nobody has reached it, it's listed as *behind trend* rather than given a date. Milestones more than 15 years out are listed as off trend.
- **History:** the points before you first ran the app are recomputed from only the data public at the start of each month. From then on, each day's forecasts are saved to `~/Library/Application Support/AI Advances/Forecast Log.json`. Delete that file to start the log over.

## Refreshing the lab notes

The charts on the Labs page update on their own. The focus notes in `AI Advances/Resources/Labs.json` are researched and dated (`asOf`). To refresh them, ask Claude Code to re-research the labs into that file, or edit it by hand. Each entry needs `name` (matching `Labs.directory` in `AI Advances/Data/Labs.swift`), `focus`, `summary`, `bets`, `flagships`, `sources` and `asOf`. A test checks that every tracked lab has a note with sources.

## Where the data comes from

| Source | Used for | URL |
|---|---|---|
| Epoch AI benchmarking hub | Benchmark scores, METR time horizons | `https://epoch.ai/data/benchmark_data.zip` |
| Epoch AI notable models | Training compute | `https://epoch.ai/data/notable_ai_models.csv` |
| OpenRouter models API | Prices, context windows, modalities, new listings | `https://openrouter.ai/api/v1/models` |
| `AI Advances/Resources/Advances.json` | Researched highlights (Oct 2025 – Sep 2026) | bundled |
| `AI Advances/Resources/Labs.json` | Researched lab focus notes (as of Sep 30, 2026) | bundled |

Downloads are cached in `~/Library/Application Support/AI Advances/Data/`. The first launch uses the snapshot bundled in `AI Advances/Resources/Seed/`, taken on Sept 30, 2026. A download that fails to parse is discarded, and the previous copy stays in use.

### Caveats

- Epoch's scores mix its own runs with results reported by benchmark authors. The app shows each model's best reasoning-effort setting.
- Prices are OpenRouter's current list prices, blended 3:1 input:output. Older models show today's price, which is often lower than their launch price.
- Prices and benchmark scores are matched by model name, so models that are named differently in the two sources won't show a price.
- OpenRouter drops retired models, so the context and modality charts thin out before 2025.

## Customizing

- **Capability areas:** edit `AI Advances/Resources/CapabilityAreas.json`. The benchmark names must match the `benchmark` column in Epoch's `benchmark_metadata.csv`. A test checks this.
- **Model table columns:** `Analysis.keyBenchmarks` in `AI Advances/Data/Analysis.swift`.
- **Highlights:** add entries to `AI Advances/Resources/Advances.json`. Every entry needs a date, a title, a direction and a source URL.

## Feedback

Click **Feedback** at the bottom of the sidebar. It opens a pre-filled GitHub issue that you can review before posting.
