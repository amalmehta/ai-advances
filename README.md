# AI Advances

![Forecasts: a timeline of dated predictions with 90% ranges, under an auto-written outlook](docs/images/forecasts.png)

**A Mac app that tracks where AI is heading.** It follows the latest model releases, what each model and lab is working on, and the long-run trends in capability, cost, context and compute, and turns those trends into dated forecasts that update themselves from public data.

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
    C[Researched highlights<br>bundled] --> P
    L[Researched lab notes<br>bundled] --> P
    P --> T[Trends<br>frontier · doubling time · price drops]
    T --> F[Forecasts<br>trend fits + 90% ranges]
    F --> G[Forecast log<br>saved each day]
    T --> A[AI Advances<br>Mac app]
    F --> A
    G --> A
```

The app checks for fresh data on launch and every 6 hours while it's open. It needs no API keys, and a snapshot is bundled so it works offline.

**[Setup and usage guide →](docs/GUIDE.md)**

Data: [Epoch AI](https://epoch.ai/benchmarks) (CC BY 4.0) and [OpenRouter](https://openrouter.ai/models).
