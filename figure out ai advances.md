PROJECT NAME: figure out ai advances

META-INSTRUCTIONS:

<Read it all before acting. Ask about anything unclear, contradictory or
 underspecified — before starting and mid-build. Ask in the question widget
 (AskUserQuestion): related questions batched, concrete options, your
 recommendation first. Plain text only if the widget isn't available.>

<Don't expand scope. Anything not listed here is a proposal, including changes
 to this file — propose it, don't do it.>

<Prefer doing over describing: run the code, write the files, test it.>

<Always in scope, no proposal needed: when it goes on GitHub, a short README
 that leads with visuals (screenshots, a diagram or a chart) and a line on what
 it is, linking to docs/GUIDE.md for setup and usage; and a small unobtrusive
 feedback tab if what you're building is an application rather than a script.>

<If what you're building is an application, build it as a Mac app first; the
 website comes after, as its own step.>

<Name things the way a person would say them — "Goal Tracker", not
 goal_tracker — for the app, its windows, titles, files people open, repo
 descriptions and README headings. Where a name can't hold spaces (repo names,
 bundle IDs), use hyphens, never underscores.>

<Finish by listing every deliverable: path, what it is, how to check it works.>

<Git rules (no Claude attribution, never commit .claude/) are in
 ~/.claude/CLAUDE.md and apply on their own — nothing to repeat here.>

<Keep the changelog at the bottom current.>

CONTEXT:

figure out the latest advances in ai. figure out the capabilities of different models. create an updating chart of direction trends

OPEN QUESTIONS / ASSUMPTIONS:

<Agent fills in: what it guessed, what it decided without asking.>

Asked and answered (2026-09-30): Mac app first; public data + a researched
seed list, no API keys; track all four trends (benchmarks, cost per
capability, context & modalities, compute); new private GitHub repo.

Decided without asking:
- App name "AI Advances"; repo "ai-advances"; bundle ID com.amalmehta.ai-advances.
- Sources: Epoch AI benchmark zip + notable-models CSV (CC BY), OpenRouter's
  public models API. Refresh on launch if >12 h old, then every 6 h, plus ⌘R.
- A snapshot of all three is bundled so the first launch works offline.
- "Direction trends" = headroom closed per capability area over 6/12/24
  months, plus fitted doubling times for compute and METR task horizon.
- Six capability areas and their benchmarks were picked for recent coverage
  (CapabilityAreas.json). SWE-bench Verified was left out of Coding because
  Epoch's copy is stale.
- Prices are OpenRouter's current prices (3:1 blend); no price history is kept.
- Highlights list: 35 researched entries, Oct 2025 – Sep 2026, each with a
  source. Five rely on secondary sites; one was re-sourced to Epoch's data.
- The feedback tab opens a pre-filled GitHub issue (no backend).
- Not built (proposals): the website version; a stored price history;
  per-lab color coding on the scatter charts.

Asked and answered (2026-09-30, second request, "continually updating
predictions ... and what companies are working on what"): trend
extrapolation only (no LLM, no API key); labs from data + researched notes;
keep a forecast log.

Decided without asking:
- Forecast targets: METR horizon of 40 h and 167 h; 10^28 and 10^29 FLOP
  runs; GPQA ≥ 80% under $0.01/M tokens; every tracked benchmark at 90%.
- Methods: log-linear fits (compute, horizon, price); logit-linear S-curve
  over the last 2 years (benchmarks); 90% range from the slope's standard
  error. Trends due in the past are shown as "behind trend", not dated.
- History: 12 monthly forecasts reconstructed from the data public at the
  time, plus a live log saved each day (Forecast Log.json).
- 14 labs tracked; xAI shown as "xAI (SpaceXAI)" after the SpaceX merger.
  Standing averages only the benchmarks a lab has results on.
- Lab notes (Labs.json) are researched as of 2026-09-30 and refresh only
  when re-researched; about half lean partly on secondary sources.

Asked and answered (2026-10-01, website): GitHub Pages + daily GitHub
Action; all 9 pages. The plan didn't allow Pages on a private repo, so
(asked again) the repo was made public.

Decided without asking:
- Epoch AI blocks browser fetches (no CORS), so the site is prebuilt: a
  Swift exporter (Package.swift) compiles the app's own AI Advances/Data
  code and writes site/data/site.json; no logic is duplicated in JS except
  small interactive bits (cost threshold, sorting, filtering).
- Moved parsing, the outlook text and the advances feed out of app views
  into the shared core so both outputs say the same thing.
- The website's forecast log lives on a `data` branch, committed daily by
  github-actions[bot], so main's history stays clean.
- Front end: plain HTML/CSS/JS + Observable Plot from jsDelivr; follows the
  system light/dark setting; phone layout with a scrolling top nav.
- The feedback tab opens a GitHub issue on the (now public) repo, so anyone
  with a GitHub account can use it.

Asked and answered (2026-10-01, Claude-written outlook): generated daily
in the GitHub Action; Claude Opus 5.5; narrative outlook only.

Decided without asking:
- No web search: the outlook only reads a fact sheet built from site.json,
  so it can't introduce outside claims (and costs ~$2–3/month, not ~$10+).
- Python + the official anthropic SDK in the Action (Swift has no official
  SDK); structured JSON output; effort "high"; server-side refusal fallback
  ("default"); keeps the previous outlook on any failure.
- The Mac app doesn't call Claude; it downloads the website's outlook.json.
- Shown above the computed outlook, labeled "Written by Claude" with a note
  that it's an AI reading of trend extrapolations.
- The user adds the ANTHROPIC_API_KEY secret; Claude never handles the key.

CHANGELOG:

- 2026-09-30 — created
- 2026-09-15 — added meta-instruction: built-out applications include a small feedback tab
- 2026-09-15 — added meta-instruction: no "Claude" attribution in commits, PRs, or branches
- 2026-09-16 — added meta-instruction: always include a README when adding to GitHub
- 2026-09-16 — changed meta-instruction: ask clarifying questions in the question widget
- 2026-09-17 — added meta-instructions: Claude never a contributor; never commit .claude/
- 2026-09-26 — compressed the meta-instructions and every field prompt; git rules moved to the global instruction file
- 2026-09-27 — added meta-instruction: applications are built as a Mac app first, then a website
- 2026-09-28 — folded inputs, instructions, constraints, deliverables and done criteria into one free-form CONTEXT
- 2026-09-28 — changed meta-instruction: a README on GitHub always includes a visual
- 2026-09-28 — added meta-instruction: name things like a person would, never snake_case
- 2026-09-28 — changed meta-instruction: README leads with visuals; instructions live in a linked guide
- 2026-09-30 — built v1.0 of the AI Advances Mac app (seven pages, live Epoch AI + OpenRouter data, 12 tests); README + docs/GUIDE.md; filled in assumptions
- 2026-09-30 — added Forecasts page (dated trend forecasts, 90% ranges, outlook, forecast log + reconstructed history) and Labs page (standing and release-pace heatmaps, researched lab focus notes); 19 tests (one opt-in page render)
- 2026-10-01 — added the website: shared Swift exporter, daily GitHub Action to GitHub Pages, forecast log on the data branch, all nine pages; repo made public for Pages
- 2026-10-01 — added the optional Claude-written daily outlook (Action + website + Mac app); needs the ANTHROPIC_API_KEY repo secret
