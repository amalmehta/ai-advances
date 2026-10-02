# AI Advances

![Forecasts: a timeline of dated predictions with 90% ranges, under an auto-written outlook](docs/images/forecasts.png)

**A Mac app and website that track where AI is heading.** They follow the latest model releases, what each model and lab is working on, and the long-run trends in capability, cost, context and compute, and turn those trends into dated forecasts that update themselves from public data.

**Website:** [amalmehta.github.io/ai-advances](https://amalmehta.github.io/ai-advances/), rebuilt daily.

| Website | |
|---|---|
| ![The AI Advances website on the Forecasts page](docs/images/website.jpg) | Same nine pages as the Mac app, in the browser, on phones too. A GitHub Action rebuilds it every day with the same Swift analysis code. |

| Direction Trends | Labs |
|---|---|
| ![Headline trends and fastest-moving capability areas](docs/images/direction-trends.png) | ![Heatmap of where each lab leads, plus lab focus cards](docs/images/labs.png) |

| Capabilities | Models | Cost |
|---|---|---|
| ![Benchmark frontier over time](docs/images/capabilities.png) | ![Model capability table](docs/images/models.png) | ![Cheapest price to reach a score](docs/images/cost.png) |

| Latest Advances | Context & Modalities | Compute |
|---|---|---|
| ![Feed of advances and records](docs/images/latest-advances.png) | ![Context windows over time](docs/images/context-and-modalities.png) | ![Training compute over time](docs/images/compute.png) |

## How it works

```mermaid
flowchart LR
    E1[Epoch AI<br>benchmark results] --> P[Parse & join<br>by model name]
    E2[Epoch AI<br>notable models] --> P
    O[OpenRouter<br>model list] --> P
    H[Researched highlights<br>and lab notes] --> P
    P --> T[Trends<br>frontier · doubling time · price drops]
    T --> F[Forecasts<br>trend fits + 90% ranges]
    F --> G[Forecast log<br>saved each day]
    F --> CL[Claude Opus 5.5<br>writes a daily outlook]
    T --> A[AI Advances<br>Mac app]
    T --> W[Website<br>rebuilt daily]
    F --> A
    F --> W
    G --> W
    CL --> W
    CL --> A
```

The app checks for fresh data on launch and every 6 hours while it's open; the website is rebuilt every morning (06:17 UTC). The data needs no API keys. The optional Claude-written outlook uses an Anthropic API key stored as the `NEW_SECRET` repository secret.

**[Setup and usage guide →](docs/GUIDE.md)**

Data: [Epoch AI](https://epoch.ai/benchmarks) (CC BY 4.0) and [OpenRouter](https://openrouter.ai/models).
