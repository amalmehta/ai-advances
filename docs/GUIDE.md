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

The Xcode project is generated from `project.yml`. After adding or moving files, regenerate it with `xcodegen generate` (install it with `brew install xcodegen`).

## Pages

| Page | What it answers |
|---|---|
| **Direction Trends** | Where things are heading. Four headline trends: training compute growth, the longest task AI can do (METR time horizon), the price of GPQA ≥ 80%, and the largest context window. Also shows which capability areas closed the most headroom over the last 6, 12 or 24 months, and small charts of the best score over time per area. |
| **Latest Advances** | What happened recently. Researched highlights with sources, plus new benchmark records and newly listed models, which are detected on every refresh. Filter by kind and by direction (Reasoning, Coding, Agents, and so on). |
| **Capabilities** | Pick an area to see every model result as a dot, with the record line on top, and a top-8 leaderboard for each benchmark. |
| **Models** | A sortable table of recent models with price, context window and their best score on seven key benchmarks. Select a row for the model's full profile. |
| **Cost** | Pick a benchmark and a score. The chart shows the cheapest model that had reached that score by each date, and a price-vs-score scatter. |
| **Context & Modalities** | Context windows over time, and the share of new models taking image, file, audio or video input, or producing images. |
| **Compute** | Training compute of notable models on a log scale, with the frontier trend line and the largest training runs. |

Hover any chart for details. The toolbar shows when data last updated; click it for sources and any update errors. **⌘R** or the refresh button fetches new data immediately.

## Where the data comes from

| Source | Used for | URL |
|---|---|---|
| Epoch AI benchmarking hub | Benchmark scores, METR time horizons | `https://epoch.ai/data/benchmark_data.zip` |
| Epoch AI notable models | Training compute | `https://epoch.ai/data/notable_ai_models.csv` |
| OpenRouter models API | Prices, context windows, modalities, new listings | `https://openrouter.ai/api/v1/models` |
| `AI Advances/Resources/Advances.json` | Researched highlights (Oct 2025 – Sep 2026) | bundled |

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
