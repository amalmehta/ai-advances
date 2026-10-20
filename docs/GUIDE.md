# AI Advances Guide

AI Advances answers three questions from public data: **what just happened** in AI, **who is working on what**, and **where the field is heading**, as dated forecasts that update every day. It's a website and a Mac app with the same nine pages.

- [Using it](#using-it): the website, the Mac app, what each page answers, and the terms it uses
- [How the forecasts work](#how-the-forecasts-work), and how well they've done
- [Claude's daily outlook](#claudes-daily-outlook)
- [Where the data comes from](#where-the-data-comes-from), and its caveats
- [For contributors](#for-contributors): building, testing, the daily build, releases and customizing

## Using it

### Website

**https://amalmehta.github.io/ai-advances/** works in any browser, including on phones. It's rebuilt every morning, ready by 7:00 AM Pacific. If the morning update ever stops running, the site says so: once its data is more than 2 days old, the status pill and a banner show when it was last updated.

### Install the Mac app

Download the latest **AI-Advances-vX.Y.zip** from [Releases](https://github.com/amalmehta/ai-advances/releases/latest), unzip it, and move **AI Advances** to Applications. It runs on Apple Silicon and Intel Macs with macOS 14 or later. Each release lists the zip's SHA-256 if you want to check the download (`shasum -a 256 AI-Advances-vX.Y.zip`).

The app isn't notarized by Apple (that needs a paid developer account), so the first time you open it macOS says it can't verify the developer. Open **System Settings → Privacy & Security**, scroll to the message about AI Advances, and click **Open Anyway**. You only need to do this once.

The app updates its data once each morning: when you open it, at 7:00 AM local time if it's already open, or when your Mac wakes, whichever comes first after 7. If an update fails it retries later, and the toolbar says when data was last updated; click it for sources and any errors. **⌘R** updates any time. When a newer version of the app is released, a **Version X available** button appears in the toolbar and opens the download page.

### Pages

| Page | What it answers |
|---|---|
| **Trends** | Where things are heading. Four headline trends: training compute growth, the longest task AI can do (METR time horizon), the price of GPQA ≥ 80%, and the largest context window. Also which capability areas closed the most headroom over the last 6, 12 or 24 months, and the best score over time per area. |
| **Forecasts** | Where the field goes next. Dated predictions with likely ranges: when AI handles week- and month-long tasks, when each tracked benchmark reaches 90%, when training runs reach 10²⁸ and 10²⁹ FLOP, and when GPQA-level ability costs under $0.01 per million tokens. Also an outlook, the forecasts that moved most in the last 3 months, each forecast's history, the track record, and milestones already reached or stalled. |
| **Labs** | Who's working on what. Each lab's standing per capability area (★ = holds a record), release pace by quarter, and a card per lab with its researched focus, bets and flagship models, plus live facts: latest model, records held, modalities, open-weights share, price range and largest training run. |
| **Latest Advances** | What happened recently. Researched highlights with sources, plus new benchmark records and newly listed models, detected on every update. Filter by kind, by direction (Reasoning, Coding, Agents, and so on), or to items new since your last visit. |
| **Capabilities** | Pick an area to see every model result, the record line on top, and a top-8 leaderboard for each benchmark. |
| **Models** | A sortable table of recent models with price, context window and their best score on seven key benchmarks. Select a row for the model's full profile; select up to four to compare them side by side. |
| **Cost** | Pick a benchmark and a score to see the cheapest model that had reached it by each date, and price against score. |
| **Context & Modalities** | Context windows over time, and the share of new models taking image, file, audio or video input, or producing images. |
| **Compute** | Training compute of notable models on a log scale, with the trend of the largest runs. |

Hover or tap any chart for details. Every chart also has a text description for screen readers.

**Comparing models:** on the Models page, tick up to four models (or open one's profile and choose *Compare*). The comparison shows each model's price, context window, modalities and scores side by side, with the best value in each row highlighted. A fifth pick replaces the oldest one, and the page says so.

**New since your last visit:** Latest Advances marks items that appeared since you last opened it, shows a count in the navigation, and adds a *New to you* filter. Nothing is marked on a first visit. The website remembers this in your browser; the app in its preferences.

**Shareable links:** the website's address keeps what you're looking at, so a copied link opens the same view. For example `#/models?model=GPT-6 Astra` opens that profile, `#/models?compare=GPT-6 Astra|Claude Opus 5.5` opens a comparison, `#/cost?benchmark=SimpleQA Verified&score=0.6` sets the Cost page, and `#/capabilities?area=Coding&years=4` picks an area and time range. Unknown or out-of-range values fall back to the defaults.

**Feed and lab counts:** a serving mode of a model (e.g. "GPT-6.1 Sol Pro" alongside "GPT-6.1 Sol") counts as the same model: listed on the same day, they appear once in the feed as "GPT-6.1 Sol (also as Pro)", and the Labs page counts them once. A "Pro" with no plain sibling (e.g. "Gemini 3 Pro") is its own model. Different models such as Flash or Mini always stay separate.

### Terms

- **Benchmark:** a fixed test set that models are scored on, such as GPQA Diamond (hard science questions) or SWE-bench (real software fixes).
- **Record:** the best score any model had reached on a benchmark by a given date. The record line only goes up.
- **Headroom:** how far a benchmark's record is from a perfect score, after subtracting what random guessing would get. "Closed 40% of the headroom" means the gap to perfect shrank by 40%.
- **Time horizon:** from [METR](https://metr.org): the length of task, measured by how long it takes a skilled person, that a model completes half the time. It's measured up to a ceiling, so the latest value is shown as "at least".
- **Likely range:** the span of dates a forecast expects a milestone in. See [how wide it is](#how-the-forecasts-work).
- **Open weights:** models whose trained parameters are published for anyone to run.
- **FLOP:** floating-point operations, the standard measure of how much computation a training run used.

## How the forecasts work

- **Compute, task horizon and price:** a straight-line fit on a log scale, meaning steady exponential change. Task horizon uses METR record-setters since 2023. Compute uses the running record of Epoch's largest training runs since 2020. Price uses the successive drops in the cheapest model scoring at least 80% on GPQA Diamond.
- **Benchmarks:** an S-curve (linear in logit) fitted to the record-setting scores of the last two years, since scores flatten as they near 100%. Only benchmarks Epoch still updates are forecast; ones with no new result for 120 days are listed as inactive, and benchmarks that have been replaced by a new version follow the new one.
- **Likely ranges:** the range combines the uncertainty in the fitted slope with how far records scatter around the trend, at a width calibrated on past forecasts (`Forecasts.calibratedZ`). A range that starts at today means the trend says the milestone could happen any time now.
- **Track record:** forecasts are recomputed as they would have looked at the start of each of the last 18 months, using only data public then, and scored against what happened. Each milestone counts once per month, so near-identical forecasts don't inflate the score. A range counts as a hit if it contained the real date, and a miss if the milestone came outside it or the range ran out with the milestone still unreached. Open-ended ranges are reported separately. The Forecasts page shows the current hit rate, the number of milestones behind it, and the typical miss. On the data as of ⟪TRACK_DATE⟫ that's ⟪TRACK_RESULT⟫.
- **Calibration:** the range width was chosen on those same 18 months of reconstructed forecasts. Holding out each milestone in turn and tuning on the rest, about 2 in 3 held; the misses were a benchmark stalling for months and one jumping years early, which no smooth trend anticipates. That's why the ranges are called "likely", not "90%".
- **Stalled milestones:** if a trend says a milestone was due in the past but nobody has reached it, it's listed as *behind trend* rather than given a date. Milestones more than 15 years out are listed as off trend.
- **History:** the website keeps every day's forecasts in `forecast-log.json` on the repository's `data` branch, so each forecast's history chart shows how it has moved. The Mac app keeps its own log in `~/Library/Application Support/AI Advances/Forecast Log.json`; before that starts, the history is reconstructed from the data public at the start of each month. If the log file is ever damaged, the app sets it aside (as `Forecast Log.damaged-<date>.json`) and starts a new one.

## Claude's daily outlook

Each daily build can also have Claude write a short outlook: a headline and 3–5 sentences on where the field is heading. It appears at the top of the Forecasts page on the website and in the Mac app, labeled "Written by Claude", above the outlook computed from the numbers. If it's more than a day old, it says so.

- **How it's written:** `scripts/write_outlook.py` turns `site.json` into a compact fact sheet (headline trends, forecasts and their ranges, recent records and highlights, lab standing) and sends it to Claude Opus 5.5 with instructions to use only those facts. There's no web search, so it can only reflect the data the site already has.
- **Number check:** the figures Claude sees are rounded to 3 significant digits, and every number in its reply must appear in the fact sheet (allowing rounding, percentages and minutes-as-hours). If one doesn't, Claude is asked once to rewrite using only fact-sheet numbers; if it still doesn't comply, the previous outlook is kept.
- **When it can't run:** without a key, if the API errors, or if the request is declined, the build keeps the previous outlook and the site still publishes. If the outlook goes more than 36 hours without updating, the build opens a GitHub issue titled "Daily outlook is not updating", and closes it once it updates again.
- **Cost:** one request a day of about 3,000 input tokens plus Claude's reasoning and reply, roughly 5–10 cents a day (about $2–3 a month at $4 / $20 per million input/output tokens). Later runs on the same morning reuse an outlook less than 8 hours old.
- **The Mac app** downloads the website's outlook when it updates, so it needs no key of its own.

**Turning it on:** add your Anthropic API key as a repository secret named `ANTHROPIC_API_KEY`. You'll be prompted to paste the key, so it never goes on the command line:

```bash
gh secret set ANTHROPIC_API_KEY --repo amalmehta/ai-advances
```

The workflows also accept the older secret name `NEW_SECRET`, used if `ANTHROPIC_API_KEY` isn't set; once `ANTHROPIC_API_KEY` is set you can delete `NEW_SECRET`. To replace a key that has expired or been revoked, run the same command with the new key.

## Where the data comes from

| Source | Used for | URL |
|---|---|---|
| Epoch AI benchmarking hub | Benchmark scores, METR time horizons | `https://epoch.ai/data/benchmark_data.zip` |
| Epoch AI notable models | Training compute | `https://epoch.ai/data/notable_ai_models.csv` |
| OpenRouter models API | Prices, context windows, modalities, new listings | `https://openrouter.ai/api/v1/models` |
| `AI Advances/Resources/Advances.json` | Researched highlights, with sources | bundled |
| `AI Advances/Resources/Labs.json` | Researched lab focus notes, with sources | bundled |

Each download is checked before it's used (a readable zip, the expected CSV columns, a non-trivial model list). If a source can't be downloaded or doesn't check out, the snapshot bundled in `AI Advances/Resources/Seed/` is used instead, and both the site and the app say which sources fell back. The website's build also opens a GitHub issue when that happens. The Mac app caches downloads in `~/Library/Application Support/AI Advances/Data/`.

The highlights and lab notes are researched rather than downloaded. The Labs and Latest Advances pages say when they were last updated and show a warning once that's more than 45 days ago. Each month, a workflow has Claude re-research them with web search and opens a pull request for review ([below](#monthly-re-research)).

### Caveats

- Epoch's scores mix its own runs with results reported by benchmark authors. Each model shows its best reasoning-effort setting.
- Prices are OpenRouter's current list prices, blended 3:1 input:output. Older models show today's price, which is often lower than their launch price.
- Prices and benchmark scores are matched by model name. Different sizes or versions of a model stay separate, so a model that's named differently in the two sources shows no price.
- OpenRouter drops retired models, so the context and modality charts thin out before 2025.
- The latest quarter is partial until it ends; the release-pace heatmap marks it.

## For contributors

### Build from source

You need macOS 14 or later and Xcode 16 or later.

```bash
git clone git@github.com:amalmehta/ai-advances.git
```

```bash
cd ai-advances && open "AI Advances.xcodeproj"
```

Press **⌘R** in Xcode to run. To build from the terminal instead:

```bash
xcodebuild -project "AI Advances.xcodeproj" -scheme "AI Advances" -derivedDataPath build build
```

```bash
open "build/Build/Products/Debug/AI Advances.app"
```

The Xcode project is generated from `project.yml`; `Package.swift` only builds the website's data exporter. After adding or moving files, regenerate it with `xcodegen generate` (install it with `brew install xcodegen`).

### Tests

```bash
xcodebuild -project "AI Advances.xcodeproj" -scheme "AI Advances" -derivedDataPath build test
```

The unit tests run against the bundled snapshot in a separate host, so they never touch your own data or the network. To render the Forecasts and Labs pages to full-length PNGs for review, set `TEST_RUNNER_RENDER_PAGES` to an output folder. To re-run the range-width calibration, set `TEST_RUNNER_CALIBRATE=1` and run the `CalibrationExperiment` test.

The **Accessibility Audit** scheme runs Xcode's accessibility audit on every page of the running app (VoiceOver descriptions, contrast, hit areas). Keep the app's window unobstructed while it runs, since contrast is measured from the screen:

```bash
xcodebuild -project "AI Advances.xcodeproj" -scheme "Accessibility Audit" -derivedDataPath build test
```

The Python scripts have offline checks too:

```bash
python3 scripts/test_write_outlook.py site/data/site.json
```

### Work on the website

The site is plain HTML, CSS and JavaScript (`site/index.html`, `site/styles.css`, `site/app.js`) with charts from a pinned build of Observable Plot. There's no build step. Generate its data from the bundled snapshot and serve it:

```bash
swift build -c release
```

```bash
.build/release/ai-advances-export --sources "AI Advances/Resources/Seed" --resources "AI Advances/Resources" --out site/data
```

```bash
python3 -m http.server 8766 --directory site
```

Then open http://localhost:8766. To run the browser smoke test (Playwright is pinned in `package.json`):

```bash
npm ci && npx playwright install chromium
```

```bash
node scripts/smoke_test.mjs http://localhost:8766/ site/data/site.json
```

### The daily build

`.github/workflows/update-website.yml` runs three times each morning (6:47, 8:59 and 13:13 UTC; GitHub often starts scheduled runs hours late, so the early runs are what get the site out by 7 AM Pacific), on every push that touches the site or the analysis code, and on demand (Actions → *Update website* → *Run workflow*). Each run:

1. Downloads and checks the three sources, falling back to the snapshot for any that fail.
2. Builds `ai-advances-export` from the same `AI Advances/Data` code as the Mac app and writes `site.json`, plus Claude's outlook if a key is set.
3. Loads every page in headless Chromium at desktop and phone widths (`scripts/smoke_test.mjs`): nothing errors or 404s, every chart renders, no page shows "NaN" or "undefined", nothing scrolls sideways, and shareable links restore their view.
4. On pushes, runs the unit tests (`tests.yml`, which also runs on every pull request and tests the exporter on Linux).
5. Publishes to GitHub Pages only if those pass. Otherwise yesterday's site stays up.
6. After a successful publish, adds the day's forecasts to `forecast-log.json` on the `data` branch. It skips this if any source fell back to the snapshot, and refuses to write a log that's shorter than before.
7. Opens a GitHub issue if the build fails, the outlook is stale, a source fell back, or the researched content is more than 45 days old, and closes each issue once it's resolved.

Try the issue checks without touching GitHub:

```bash
python3 scripts/check_freshness.py --today 2026-12-01 --dry-run
```

### Monthly re-research

`.github/workflows/reresearch.yml` runs on the 1st of each month (or on demand, optionally for named labs). For each lab, `scripts/reresearch.py` has Claude Opus 5.5 search the web for what has changed and return an updated note; it also looks for notable advances since the last highlight. Every entry must cite pages that actually appeared in Claude's search results, stay within the word limits and use the known tags; anything that doesn't is dropped and the old entry kept. The workflow then opens a pull request with the changes and a summary of each one, for a person to review. Nothing merges on its own. It uses the same `ANTHROPIC_API_KEY` secret and costs roughly $1–3 a run. To see the prompts without calling the API:

```bash
python3 scripts/reresearch.py --dry-run
```

You can also edit `Labs.json` and `Advances.json` by hand. Each lab note needs `name` (matching `Labs.directory` in `AI Advances/Data/Labs.swift`), `focus`, `summary`, `bets`, `flagships`, `sources` and `asOf`; each highlight needs a date, title, lab, direction, summary and source URL. Tests check both.

### Releases

`.github/workflows/release-mac-app.yml` builds a universal app and attaches it to a GitHub Release. Run it from Actions → *Release Mac app* → *Run workflow* with a version such as `v1.5`, or push a tag of that name from `main`. The app's version is set from the tag. It refuses to replace the zip of an existing release unless you tick *overwrite*.

### Customizing

- **Capability areas:** edit `AI Advances/Resources/CapabilityAreas.json`. The benchmark names must match the `benchmark` column in Epoch's `benchmark_metadata.csv`. A test checks this.
- **Model table columns:** `Analysis.keyBenchmarks` in `AI Advances/Data/Analysis.swift`.
- **Labs:** `Labs.directory` in `AI Advances/Data/Labs.swift` lists each lab and the organization names that map to it.

## Feedback

Click **Feedback** at the bottom of the sidebar (in the app) or the page footer (on the website). It opens a pre-filled GitHub issue that you can review before posting.
