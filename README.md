# AI Advances

![Direction Trends: compute, task length, price and context tiles above a chart of which capability areas are improving fastest](docs/images/direction-trends.png)

**A Mac app that tracks where AI is heading.** It follows the latest model releases, what each model can do, and the long-run trends in capability, cost, context and compute. The charts update themselves from public data.

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
    P --> T[Trends<br>frontier · doubling time · price drops]
    T --> A[AI Advances<br>Mac app]
```

The app checks for fresh data on launch and every 6 hours while it's open. It needs no API keys, and a snapshot is bundled so it works offline.

**[Setup and usage guide →](docs/GUIDE.md)**

Data: [Epoch AI](https://epoch.ai/benchmarks) (CC BY 4.0) and [OpenRouter](https://openrouter.ai/models).
