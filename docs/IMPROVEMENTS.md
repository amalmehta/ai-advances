# 100 improvements (October 2026)

Found by five audits on Oct 20, 2026 (website, Mac app, data and forecasting, CI and reliability, docs and content), each backed by a reproduction, measurement or file reference. ✅ = done in this round; ◐ = partly done, with what's left.

## Data and forecasting correctness (shared Swift core, used by app and site)

1. ✅ Benchmarks whose Epoch metadata loses its `source_file` (HLE, DeepSWE on Oct 20) silently vanished: fall back to `<slug>_external.csv`, and warn when a tracked benchmark has no results.
2. ✅ Reconstructed past forecasts used benchmarks that weren't released yet: only forecast a benchmark from its release date on.
3. ✅ Track record ignored forecasts whose range expired without the milestone: count them as misses.
4. ✅ Track record counted open-ended ranges as hits: report them separately.
5. ✅ Track record counted near-identical monthly forecasts as independent: score one per milestone per month and report the number of milestones.
6. ✅ Benchmarks Epoch no longer updates (GDPval, VPCT, GeoBench, Terminal Bench) were forecast and flagged as "stalled": mark them inactive after 120 days and leave them out of forecasts, momentum and records.
7. ✅ Saturated benchmarks inflated "where progress is fastest": leave reached benchmarks out of momentum and say so.
8. ✅ Model-name matching merged different models (sizes in parentheses, "+", ".", preview vs release): keep those distinctions.
9. ✅ Missed obvious matches (a lab name inside the model name, host prefixes like `chutes/`): strip them.
10. ✅ 45–59 models had no lab and Google appeared as three labs: map organizations to the canonical lab list everywhere.
11. ✅ Record-setting price steps were backdated through loose listing matches: only use a listing's date for an exact match.
12. ✅ The task-horizon headline extrapolated METR's measurement ceiling as an exact value: show it as "at least", with the measurement date.
13. ✅ The computed outlook said "closest to saturating its hardest benchmarks" for something it didn't compute: say what it computes.
14. ✅ Random-chance baselines were parsed but unused: normalize lab standing and momentum against chance.
15. ✅ Feed records were dated before their benchmark existed: date them no earlier than the benchmark's release.
16. ✅ The compute trend relied on Epoch's lagging "frontier" flag: fit the running maximum of training compute.
17. ✅ Partial quarters (20 days in) were treated as full: mark them and require a minimum count.
18. ✅ Rows dropped despite recoverable data (missing release date or model version): fall back to model metadata and the Name column.
19. ✅ Superseded benchmarks stayed in use (WeirdML → WeirdML v3): follow `superseded_by`.
20. ✅ Date parsing made launch take ~2.8 s: parse ISO dates directly; cache each highlight's date.
21. ✅ Reconstructing 18 months of forecasts took ~3.3 s: memoize name matching and lab lookups.
22. ✅ A global, test-mutated range width was a data race: pass it as a parameter.
23. ✅ Grammar in generated text ("a APEX-Agents record").

## Website

24. ✅ Escape on the feedback dialog re-sent the previous issue.
25. ✅ If the chart library failed to load, the page said "Loading…" forever.
26. ✅ Sorting put missing values first.
27. ✅ Lab filter showed a blank option (labs follow item 10).
28. ✅ The compute trend line vanished for "Since 2022".
29. ✅ Out-of-range link values (e.g. `window=5`) gave empty pages: validate every link value.
30. ✅ Charts clipped labels on phones (Trends bars, Cost labels).
31. ✅ The current page was hidden in the scrolled phone nav: scroll it into view.
32. ✅ Legends kept old colors after a light/dark switch.
33. ✅ Small text, white-on-accent and status colors failed contrast.
34. ✅ The Labs heatmap was clipped at 1280 px.
35. ✅ The Cost slider wrote float noise into the link (`0.7000000000000001`).
36. ✅ Plot loaded as 48 unpinned modules from a moving version range: pin one bundle.
37. ✅ Every chart redrew when a phone's address bar moved: redraw only on width changes.
38. ✅ Site and outlook data loaded one after the other; the optional outlook logged a 404.
39. ✅ Wide tables lost row names when scrolled on phones: sticky first column.
40. ✅ A fifth compared model silently dropped the first: say so.
41. ✅ Segmented controls had no accessible names.
42. ✅ Invalid `aria-selected` on table rows; non-sortable headers looked clickable.
43. ✅ "1 items", empty results without a message, "0 day(s)".
44. ✅ "0 months later" for small shifts.
45. ✅ "Released" vs "first result" for the same date.
46. ✅ The Sources popover didn't close on Escape or an outside click.
47. ✅ Raw "10^27", a dangling ". ." and "null" tokens in formatted text.
48. ✅ A stale Claude outlook was shown without saying so.
49. ✅ Sources that fell back to the snapshot weren't shown.
50. ✅ Forecast ranges starting "today" weren't explained.
51. ✅ Jargon without explanations (headroom, time horizon, benchmarks): add plain-language definitions.
52. ✅ No first-visit explanation of what the site answers.
53. ✅ Page names differed between nav and headings ("Direction Trends").

## Mac app

54. ✅ Unit tests ran the real app, touching the user's data and the network.
55. ✅ Overlapping reloads raced each other.
56. ✅ New windows restarted the whole data pipeline.
57. ✅ A bad cached file left the app stuck on an error screen: fall back to the bundled copy, with Retry.
58. ✅ Cache replacement wasn't atomic; failed refreshes still re-parsed everything.
59. ✅ No warning when data is stale; "Updated…" never advanced.
60. ✅ Failed refreshes were silent and never retried.
61. ✅ Heavy analysis ran inside view bodies and on every hover.
62. ✅ Page settings reset when switching pages.
63. ✅ Scroll position carried over between pages.
64. ✅ The selected model's detail could go stale or be hard to find.
65. ◐ Missing keyboard shortcuts and menus (pages, search, help, updates). Left: no ⌘F shortcut to the Models search field. (A toolbar search field and an inspector for model details were tried, but an inspector in the split view's detail column left the Models page blank, so the search field and details stay on the page.)
66. ✅ Chart details were hover-only: add accessible chart descriptors (and Audio Graphs).
67. ✅ No model comparison (the website has it).
68. ✅ Launching with `-page` locked the sidebar to that page.
69. ✅ Pickers could start or drift to a selection with no option.
70. ✅ No empty state when filters match nothing; "1 items".
71. ✅ Hard-coded snapshot date and raw date strings.
72. ✅ The update check ran twice per launch; sources downloaded one at a time.
73. ✅ Blocking unzip on a shared thread: parsing, validation and unzip now run on a dedicated thread.

## CI, automation and reliability

74. ✅ A corrupt forecast log would have been silently replaced by one entry: refuse to overwrite; the log can't shrink.
75. ✅ Forecasts were saved before the deploy gates ran: save only after a successful deploy.
76. ✅ A later run could log a day computed from the fallback snapshot: don't log when a source fell back.
77. ✅ The outlook had failed since Oct 17 (rejected key) with only a log warning: open an issue when it's stale.
78. ✅ Failed or cancelled builds told no one: open an issue (closed on the next success).
79. ✅ Downloads were only checked for HTTP errors: validate content and fall back on garbage.
80. ✅ Unpinned `anthropic` and an uncaught error path: pin it and catch everything.
81. ✅ The smoke test depended on specific model names in live data: pick them from the data.
82. ✅ Every job held write tokens: least-privilege permissions per job.
83. ✅ Unpinned Playwright downloaded every run: pin with a lockfile and cache the browser.
84. ✅ Node 20 actions deprecated: move to current majors; add Dependabot.
85. ✅ Scheduled runs re-ran macOS tests on unchanged code: only on pushes.
86. ✅ No timeouts anywhere.
87. ✅ The exporter runs on Linux but was only tested on macOS: add a Linux job.
88. ✅ Release tag and app version could disagree: set the version from the tag.
89. ✅ Releases could silently overwrite published binaries or ship from any branch.
90. ✅ The release version input went straight into shell: validate it.
91. ✅ Test failures left no diagnostics: upload the result bundle.
92. ✅ The SwiftPM target scanned the whole repo.
93. ✅ The forecast log was written pretty-printed and grows daily: write it compactly.
94. ✅ The smoke test could race the server and ignored 404s.

## Content and docs

95. ✅ Highlights contradicted the data (OSWorld 2 "70.6%", FrontierMath T4 "close to solved", Kimi K3 date).
96. ✅ Lab notes contradicted the data (Muse Spark Open, Mistral Large 4, Argon availability, Haiku 5.5): refresh them, and add October's highlights.
97. ✅ Monthly re-research as a pull request (approved): a workflow that has Claude update lab notes and highlights with sources, for review.
98. ✅ Docs disagreed with the code (range coverage numbers, schedule, 12 vs 18 months) and put contributor steps before users: rewrite.
99. ✅ The secret's name (`NEW_SECRET`) says nothing: accept `ANTHROPIC_API_KEY` too and explain it.
100. ✅ README screenshots predated most of the UI: regenerate.

Left for later: an external scheduler for exact 7 AM runs (needs a personal access token), a dated price history (needs daily OpenRouter snapshots to accumulate), branch protection rules (a repository setting for the owner), per-claim sources for each lab bet.
