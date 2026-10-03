import * as Plot from "https://cdn.jsdelivr.net/npm/@observablehq/plot@0.6/+esm";

const ISSUES_URL = "https://github.com/amalmehta/ai-advances/issues/new";
const DAY = 86_400_000;
const YEAR = 365.25 * DAY;

const PAGES = [
  ["trends", "Direction Trends"],
  ["forecasts", "Forecasts"],
  ["labs", "Labs"],
  ["advances", "Latest Advances"],
  ["capabilities", "Capabilities"],
  ["models", "Models"],
  ["cost", "Cost"],
  ["context", "Context & Modalities"],
  ["compute", "Compute"],
];

// ---------- Helpers ----------

const $ = (sel) => document.querySelector(sel);

/** Builds an element: el("div", {class: "card"}, child, "text", ...). */
function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (k === "html") node.innerHTML = v;
    else node.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat(Infinity)) if (c != null && c !== false) node.append(c instanceof Node ? c : String(c));
  return node;
}

const date = (s) => (s ? new Date(s + "T00:00:00Z") : null);
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const fmt = {
  pct: (v, d = 0) => (v == null ? "–" : `${(v * 100).toFixed(d)}%`),
  price: (v) => (v == null ? "–" : v >= 10 ? `$${v.toFixed(0)}` : v >= 1 ? `$${v.toFixed(2)}` : `$${v.toFixed(3)}`),
  tokens: (n) => (n >= 1e6 ? `${+(n / 1e6).toPrecision(n % 1e6 === 0 ? 3 : 2)}M` : n >= 1000 ? `${Math.floor(n / 1000)}K` : `${n}`),
  flop: (v) => { const e = Math.floor(Math.log10(v)); return `${(v / 10 ** e).toFixed(1)} × 10^${e}`; },
  minutes: (m) => (m < 60 ? `${m.toFixed(0)} min` : m < 1440 ? `${(m / 60).toFixed(1)} hours` : `${(m / 1440).toFixed(1)} days`),
  months: (m) => `${m.toFixed(1)} months`,
  monthYear: (d) => `${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`,
  date: (d) => `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`,
};

/** Current theme colors, read from CSS so charts follow light/dark. */
function colors() {
  const cs = getComputedStyle(document.documentElement);
  const v = (n) => cs.getPropertyValue(n).trim();
  return {
    series: [1, 2, 3, 4, 5, 6, 7, 8].map((i) => v(`--s${i}`)),
    surface: v("--surface"), border: v("--border"), text: v("--text"), text2: v("--text-2"), muted: v("--muted"),
  };
}

function card(title, subtitle, ...content) {
  return el("section", { class: "card" },
    el("div", { class: "card-head" }, el("h3", {}, title), subtitle ? el("p", {}, subtitle) : null),
    ...content);
}

function header(title, summary) {
  return el("div", {}, el("h1", {}, title), el("p", { class: "muted", style: "margin:0;font-size:17px" }, summary));
}

const footnote = (text) => el("p", { class: "footnote" }, text);

function segmented(name, options, value, onChange) {
  return el("div", { class: "segmented", role: "radiogroup" },
    options.map(([v, label]) => el("label", {},
      el("input", { type: "radio", name, value: v, checked: String(v) === String(value), onchange: () => onChange(v) }),
      el("span", {}, label))));
}

function select(options, value, onChange, label) {
  const s = el("select", { "aria-label": label, onchange: (e) => onChange(e.target.value) },
    options.map(([v, text]) => el("option", { value: v, selected: v === value }, text)));
  return s;
}

function legend(items) {
  return el("div", { class: "legend" }, items.map(([label, color, line]) =>
    el("span", {}, el("i", { class: line ? "line" : null, style: `background:${color}` }), label)));
}

/** A chart slot that re-renders at its own width (on resize and theme change). */
function chart(render) {
  const host = el("div", { class: "chart" });
  host._render = () => {
    const w = host.clientWidth || 800;
    host.replaceChildren(render(w, colors()));
    host.querySelectorAll("svg[aria-label]").forEach((svg) => svg.setAttribute("role", "img"));
  };
  queueMicrotask(host._render);
  return host;
}

function rerenderCharts() { document.querySelectorAll(".chart").forEach((c) => c._render?.()); }

const plotBase = (C, extra) => ({
  style: { background: "transparent", color: C.text2, fontSize: "12px", overflow: "visible" },
  ...extra,
});
const tip = (C) => ({ fill: C.surface, stroke: C.border });

// ---------- Data helpers (mirroring the app's Analysis) ----------

let D; // site.json, with dates parsed

// "New since your last visit": IDs of feed items this browser has already seen. Kept in
// localStorage, which can be missing or blocked, so every access is guarded.
const SEEN_KEY = "ai-advances.seen-feed";
let NEW_IDS = new Set();
function loadSeen() {
  try {
    const seen = JSON.parse(localStorage.getItem(SEEN_KEY) ?? "null");
    if (!Array.isArray(seen)) { markSeen(); return; } // first visit: nothing is "new" yet
    const known = new Set(seen);
    NEW_IDS = new Set(D.feed.filter((i) => !known.has(i.id)).map((i) => i.id));
  } catch { NEW_IDS = new Set(); }
}
function markSeen() {
  try { localStorage.setItem(SEEN_KEY, JSON.stringify(D.feed.map((i) => i.id))); } catch {}
}
function updateNewBadge() {
  const link = document.querySelector('#nav a[data-page="advances"]');
  if (!link) return;
  link.querySelector(".new-count")?.remove();
  if (NEW_IDS.size) link.append(el("span", { class: "new-count", "aria-label": `${NEW_IDS.size} new` }, String(NEW_IDS.size)));
}
let CLAUDE = null; // outlook.json, when the daily build has one

function prepare(raw) {
  const d = structuredClone(raw);
  for (const r of d.results) r.d = date(r.d);
  for (const m of d.models) { m.released = date(m.released); m.listedOn = date(m.listedOn); }
  for (const l of d.listed) l.created = date(l.created);
  for (const s of d.modalityShares) s.start = date(s.start);
  for (const p of d.contextMedians) p.date = date(p.date);
  for (const p of d.computeFit) p.date = date(p.date);
  for (const n of d.notable) n.date = date(n.date);
  for (const h of d.horizons) h.date = date(h.date);
  for (const i of d.feed) i.date = date(i.date);
  for (const f of d.forecasts) for (const k of ["reached", "predicted", "early", "late"]) f[k] = date(f[k]);
  for (const h of d.history) {
    h.asOf = date(h.asOf);
    for (const s of Object.values(h.forecasts)) for (const k of ["reached", "predicted", "early", "late"]) s[k] = date(s[k]);
  }
  for (const l of d.labs) { l.latestDate = date(l.latestDate); for (const q of l.releasesByQuarter) q.start = date(q.start); }
  d.generatedAt = date(d.generatedAt);
  d.latestDataDate = date(d.latestDataDate);
  d.short = Object.fromEntries(d.benchmarks.map((b) => [b.name, b.short]));
  d.ceiling = Object.fromEntries(d.benchmarks.map((b) => [b.name, b.ceiling]));
  return d;
}

const short = (b) => D.short[b] ?? b.replace("-Private", "");

/** Record-setting results on one benchmark, oldest first. */
function frontier(benchmark) {
  const rows = D.results.filter((r) => r.b === benchmark)
    .sort((a, b) => a.d - b.d || b.s - a.s);
  let best = -Infinity;
  const out = [];
  for (const r of rows) if (r.s > best + 1e-9) { best = r.s; out.push(r); }
  return out;
}

/** Step-line points for each benchmark of an area since a date, extended to today. */
function frontierSteps(area, since) {
  const now = new Date();
  return area.benchmarks.flatMap((b) => {
    const f = frontier(b);
    if (!f.length) return [];
    const label = short(b);
    const out = [];
    const start = f.filter((p) => p.d <= since).pop();
    if (start) out.push({ benchmark: label, d: since, s: start.s, m: start.m });
    for (const p of f) if (p.d > since) out.push({ benchmark: label, d: p.d, s: p.s, m: p.m });
    if (out.length) out.push({ ...out[out.length - 1], d: now });
    return out;
  });
}

/** Least-squares fit of log10(y) on years. */
function expFit(points) {
  const pts = points.filter(([, y]) => y > 0).map(([d, y]) => [d / YEAR, Math.log10(y)]);
  if (pts.length < 3) return null;
  const n = pts.length, mx = pts.reduce((a, p) => a + p[0], 0) / n, my = pts.reduce((a, p) => a + p[1], 0) / n;
  const sxx = pts.reduce((a, p) => a + (p[0] - mx) ** 2, 0);
  if (!sxx) return null;
  const slope = pts.reduce((a, p) => a + (p[0] - mx) * (p[1] - my), 0) / sxx;
  return { slope, factorPerYear: 10 ** slope };
}

function cheapestOverTime(benchmark, threshold) {
  const c = D.models.filter((m) => m.price != null && (m.scores[benchmark] ?? -1) >= threshold)
    .map((m) => ({ model: m.name, price: m.price, score: m.scores[benchmark], d: m.listedOn && m.listedOn < m.released ? m.listedOn : m.released }))
    .sort((a, b) => a.d - b.d);
  let best = Infinity;
  return c.filter((x) => (x.price < best ? ((best = x.price), true) : false));
}

// ---------- Pages ----------

const DEFAULTS = { window: "12", areaName: null, since: 2, kind: "All", direction: "All directions",
  search: "", lab: "All labs", recent: true, sort: ["released", -1], selected: null,
  costBench: "GPQA diamond", threshold: 0.8, computeSince: 2018, forecastId: null };

// Settings that belong in each page's link, so a copied URL opens the same view:
// [link parameter, state key, parse].
const LINKED = {
  trends: [["window", "window", String]],
  forecasts: [["forecast", "forecastId", String]],
  advances: [["show", "kind", String], ["direction", "direction", String]],
  capabilities: [["area", "areaName", String], ["years", "since", Number]],
  models: [["model", "selected", String], ["lab", "lab", String], ["q", "search", String]],
  cost: [["benchmark", "costBench", String], ["score", "threshold", Number]],
  compute: [["since", "computeSince", Number]],
};
let currentPage = null;

/** Rewrites the address bar to match the current page's settings, without adding history entries. */
function syncLink() {
  if (!currentPage) return;
  const params = new URLSearchParams();
  for (const [param, key] of LINKED[currentPage] ?? []) {
    if (state[key] != null && state[key] !== "" && String(state[key]) !== String(DEFAULTS[key])) params.set(param, state[key]);
  }
  const hash = `#/${currentPage}${params.size ? "?" + params : ""}`;
  if (location.hash !== hash) history.replaceState(null, "", hash);
}

// Any change to a linked setting updates the link.
const state = new Proxy({ ...DEFAULTS }, {
  set(target, key, value) {
    target[key] = value;
    queueMicrotask(syncLink);
    return true;
  },
});

const pages = {};

pages.trends = () => {
  const t = D.tiles;
  const tiles = el("div", { class: "grid tiles" },
    tile("Training compute", t.computeFactorPerYear ? `${t.computeFactorPerYear.toFixed(1)}× / year` : "–",
      t.computeDoublingMonths ? `Frontier training runs double every ${fmt.months(t.computeDoublingMonths)} (fit since 2020, ${t.computeModels} models).` : ""),
    tile("Longest task AI can do", t.horizonMinutes ? fmt.minutes(t.horizonMinutes) : "–",
      `${t.horizonModel ?? ""}, METR 50% time horizon. ${t.horizonDoublingMonths ? `Doubles every ${fmt.months(t.horizonDoublingMonths)}.` : ""}`),
    tile("Price of GPQA ≥ 80%", fmt.price(t.priceNow),
      t.priceNow ? `Per million tokens, ${t.priceModel}. ${(t.priceFirst / t.priceNow).toFixed(0)}× cheaper than the first model to get there, ${t.priceFirstModel}.` : "No priced model has reached 80% yet."),
    tile("Largest context window", `${fmt.tokens(t.maxContext)} tokens`,
      t.medianContextThisQuarter ? `Median for models listed this quarter: ${fmt.tokens(t.medianContextThisQuarter)}.` : ""));

  const momentumChart = chart((w, C) => {
    const rows = D.areas.filter((a) => a.momentum[state.window])
      .map((a) => ({ area: a.name, ...a.momentum[state.window] }))
      .sort((a, b) => b.gapClosed - a.gapClosed);
    return Plot.plot(plotBase(C, {
      ariaLabel: `Bar chart of the share of remaining headroom each capability area closed in the last ${state.window} months: ${rows.map((r) => `${r.area} ${fmt.pct(r.gapClosed)}`).join(", ")}.`,
      width: w, height: rows.length * 36 + 40, marginLeft: Math.min(170, w * 0.35), marginRight: 110,
      x: { domain: [0, 1], tickFormat: (v) => fmt.pct(v), label: null, grid: true },
      y: { domain: rows.map((r) => r.area), label: null },
      marks: [
        Plot.barX(rows, { x: "gapClosed", y: "area", fill: C.series[0], rx: 4, insetTop: 6, insetBottom: 6,
          tip: { ...tip(C), format: { x: (v) => fmt.pct(v) } },
          channels: { "Points gained": (r) => `${r.pointsGained >= 0 ? "+" : ""}${r.pointsGained.toFixed(0)}`, Benchmarks: "benchmarksUsed" } }),
        Plot.text(rows, { x: "gapClosed", y: "area", dx: 6, textAnchor: "start", fill: C.text2,
          text: (r) => `${fmt.pct(r.gapClosed)} · ${r.pointsGained >= 0 ? "+" : ""}${r.pointsGained.toFixed(0)} pts` }),
      ],
    }));
  });

  return el("div", {},
    header("Where AI is heading", "The four long-run trends, and which capabilities are moving fastest. Everything here recalculates when new data arrives."),
    tiles,
    card("Where progress is fastest", "Share of the remaining headroom closed on each area's benchmarks, averaged. 100% would mean the benchmarks are solved.",
      segmented("window", [["6", "Last 6 months"], ["12", "Last 12 months"], ["24", "Last 24 months"]], state.window,
        (v) => { state.window = v; momentumChart._render(); }),
      momentumChart,
      footnote("Hover a bar for the details. Benchmarks newer than the window count from their first result.")),
    el("h2", {}, "Frontier by capability area"),
    el("p", { class: "muted", style: "margin-top:2px" }, "Best score so far on each benchmark since January 2024. Hover for the model holding each record."),
    el("div", { class: "grid" }, D.areas.map((a) => card(a.name, a.summary, frontierChart(a, date("2024-01-01"), false, 190)))));
};

function tile(label, value, detail) {
  return el("div", { class: "card tile" }, el("div", { class: "label" }, label), el("div", { class: "value" }, value), el("div", { class: "detail" }, detail));
}

function frontierChart(area, since, showAll, height) {
  return chart((w, C) => {
    const names = area.benchmarks.filter((b) => D.results.some((r) => r.b === b)).map(short);
    const steps = frontierSteps(area, since);
    const dots = showAll ? D.results.filter((r) => area.benchmarks.includes(r.b) && r.d >= since).map((r) => ({ ...r, benchmark: short(r.b) })) : [];
    return Plot.plot(plotBase(C, {
      ariaLabel: `Line chart of the best score so far on ${names.join(", ")} since ${fmt.monthYear(since)}. Current bests: ${names.map((n) => { const s = steps.filter((x) => x.benchmark === n).pop(); return s ? `${n} ${fmt.pct(s.s)} (${s.m})` : n; }).join("; ")}.`,
      width: w, height, marginRight: 44,
      x: { type: "utc", label: null },
      y: { domain: [0, 1], tickFormat: (v) => fmt.pct(v), label: null, grid: true, axis: "right", ticks: 4 },
      color: { domain: names, range: names.map((_, i) => C.series[i]), legend: true },
      marks: [
        showAll ? Plot.dot(dots, { x: "d", y: "s", fill: "benchmark", r: 2.5, fillOpacity: 0.4,
          tip: { ...tip(C), format: { x: (d) => fmt.date(d), y: (v) => fmt.pct(v, 1), fill: true } },
          channels: { Model: "m", Lab: "o" } }) : null,
        Plot.line(steps, { x: "d", y: "s", z: "benchmark", stroke: "benchmark", strokeWidth: 2, curve: "step-after" }),
        showAll ? null : Plot.dot(steps, Plot.pointerX({ x: "d", y: "s", fill: "benchmark", r: 4,
          tip: { ...tip(C), format: { x: (d) => fmt.date(d), y: (v) => fmt.pct(v), fill: true } }, channels: { Model: "m" } })),
      ],
    }));
  });
}

pages.forecasts = () => {
  const upcoming = D.forecasts.filter((f) => !f.reached && f.predicted).sort((a, b) => a.predicted - b.predicted);
  const reached = D.forecasts.filter((f) => f.reached).sort((a, b) => b.reached - a.reached);
  const stalled = D.forecasts.filter((f) => !f.reached && !f.predicted);
  const now = new Date();
  const axisEnd = new Date(Math.min(+now + 7.5 * YEAR, +upcoming[upcoming.length - 1].predicted + 270 * DAY));
  const kinds = ["Capabilities", "Agents", "Cost", "Scale"];
  // A link may name a forecast that no longer exists (reached, or dropped); fall back to the first.
  DEFAULTS.forecastId = upcoming[0]?.id; // the automatic pick stays out of the link
  if (!upcoming.some((f) => f.id === state.forecastId)) state.forecastId = upcoming[0]?.id;

  const timeline = chart((w, C) => {
    const clamp = (d) => new Date(Math.min(+d, +axisEnd));
    const rows = upcoming.map((f) => ({ ...f, x1: clamp(f.early ?? f.predicted), x2: clamp(f.late ?? axisEnd), p: clamp(f.predicted) }));
    // Titles go in a left column when there's room, otherwise above each row.
    const narrow = w < 960;
    return Plot.plot(plotBase(C, {
      ariaLabel: `Timeline of ${rows.length} forecasts, soonest first. ${rows.map((r) => `${r.title}: most likely ${fmt.monthYear(r.predicted)}, likely range ${r.early ? fmt.monthYear(r.early) : "?"} to ${r.late ? fmt.monthYear(r.late) : "open-ended"}`).join(". ")}.`,
      width: w, height: rows.length * (narrow ? 44 : 30) + 50, marginLeft: narrow ? 8 : 330, marginRight: 70,
      x: { type: "utc", domain: [now, axisEnd], label: null, grid: true },
      y: { domain: rows.map((r) => r.title), label: null, axis: narrow ? null : "left" },
      color: { domain: kinds, range: kinds.map((_, i) => C.series[i]), legend: true },
      marks: [
        Plot.ruleX([now], { stroke: C.muted, strokeDasharray: "3,3" }),
        Plot.ruleY(rows, { y: "title", x1: "x1", x2: "x2", stroke: "kind", strokeWidth: 7, strokeOpacity: 0.35, strokeLinecap: "round" }),
        Plot.dot(rows, { x: "p", y: "title", fill: "kind", r: 5,
          tip: { ...tip(C), format: { x: false, y: false, fill: false } },
          channels: {
            Forecast: "title",
            "Most likely": (r) => fmt.monthYear(r.predicted),
            "Likely range": (r) => `${r.early ? fmt.monthYear(r.early) : "?"} – ${r.late ? fmt.monthYear(r.late) : "open-ended"}`,
            Now: "current",
          } }),
        Plot.text(rows, { x: "p", y: "title", text: (r) => fmt.monthYear(r.predicted), dx: 9, textAnchor: "start", fill: C.text2 }),
        narrow ? Plot.text(rows, { x: now, y: "title", text: "title", dy: -13, dx: 4, textAnchor: "start", fill: C.text, fontSize: 11.5 }) : null,
      ],
    }));
  });

  const historySlot = el("div");
  const renderHistory = () => historySlot.replaceChildren(historyChart(upcoming.find((f) => f.id === state.forecastId) ?? upcoming[0], now));
  renderHistory();

  return el("div", {},
    header("Where the field is going next", "Dated predictions from extrapolating today's trends. Every forecast is recomputed daily, and each day's set is logged so you can watch them move."),
    CLAUDE ? claudeCard() : null,
    card(CLAUDE ? "Computed outlook" : "Outlook", "Written by a fixed template from the numbers below; changes when they do.", el("p", { style: "margin:0" }, D.outlook)),
    card("Forecast timeline", "Dot: most likely date if the trend holds. Bar: likely range. Ranges running off the right edge are open-ended."
      + (D.trackRecord.coverage != null ? ` Past ranges caught the real date ${fmt.pct(D.trackRecord.coverage)} of the time (see Track record).` : ""),
      timeline, footnote("Hover a dot for its range and current value.")),
    D.shifts.length ? card("What moved in the last 3 months", "Change in each predicted date since the forecast computed three months ago. Earlier means the field sped up.",
      el("div", { class: "rows" }, D.shifts.slice(0, 8).map((s) => {
        const m = Math.round(Math.abs(s.months));
        return el("div", { class: "row" },
          el("span", {}, el("span", { class: s.months < 0 ? "up" : "down" }, s.months < 0 ? "◀ " : "▶ "), s.title),
          el("span", { class: "muted tnum" }, `${m} month${m === 1 ? "" : "s"} ${s.months < 0 ? "earlier" : "later"} · now ${fmt.monthYear(date(s.predicted))}`));
      }))) : null,
    card("How a forecast has shifted", "The predicted date as computed on each date. Hollow points are recomputed from only the data public then; filled points were saved by the daily update.",
      el("div", { class: "controls" }, select(upcoming.map((f) => [f.id, f.title]), state.forecastId, (v) => { state.forecastId = v; renderHistory(); }, "Forecast")),
      historySlot),
    D.trackRecord.items.length ? trackRecordCard() : null,
    el("div", { class: "grid" },
      card("Already happened", "Milestones the trends have already crossed.",
        el("div", { class: "rows" }, reached.map((f) => el("div", { class: "row" },
          el("span", {}, el("span", { class: "check" }, "✓ "), f.title), el("span", { class: "muted tnum" }, fmt.monthYear(f.reached)))))),
      stalled.length ? card("Stalled or off trend", "Milestones the current trend can't date: progress has stopped short of them, or they're too far out.",
        el("div", { class: "rows" }, stalled.map((f) => el("div", {}, el("div", {}, f.title), el("div", { class: "small muted" }, `${f.current}. ${f.note ?? ""}.`))))) : null),
    footnote("Method: compute, task horizon and price use straight-line fits on a log scale (steady exponential change). Benchmarks use an S-curve fitted to the record-setting scores of the last two years, since scores flatten as they near 100%. Likely ranges combine the uncertainty in the fitted slope with how far records scatter around the trend; they don't account for breakthroughs, benchmark changes or slowdowns, and the track record shows how often they've held. Extrapolations, not guarantees."));
};

/** When hand-researched content was last updated; a warning once it's more than 45 days old. */
function freshnessNote(iso, what) {
  if (!iso) return null;
  const d = date(iso);
  const days = Math.max(0, Math.floor((Date.now() - d) / DAY));
  const stale = days > 45;
  const age = days === 0 ? "today" : days === 1 ? "1 day ago" : `${days} days ago`;
  return el("p", { class: stale ? "freshness stale" : "freshness", role: stale ? "status" : null },
    stale ? "⚠ " : "",
    `${what} ${fmt.date(d)} (${age}).`,
    stale ? " It may be out of date: the data-driven parts of this page are current, but these notes only change when they're re-researched." : "");
}

function trackRecordCard() {
  const r = D.trackRecord;
  return card("Track record", "How earlier forecasts did on milestones that have since been reached. For each, the forecast made closest to six months ahead.",
    el("p", { style: "margin:0 0 10px" }, r.summary),
    el("div", { class: "table-wrap", style: "max-height:none" }, el("table", {},
      el("thead", {}, el("tr", {}, ["Milestone", "Forecast in", "Predicted", "Happened", ""].map((h) => el("th", { scope: "col", style: "cursor:default" }, h)))),
      el("tbody", {}, r.items.map((i) => el("tr", { style: "cursor:default" },
        el("td", {}, i.title),
        el("td", { class: "muted" }, fmt.monthYear(date(i.madeOn))),
        el("td", {}, fmt.monthYear(date(i.predicted))),
        el("td", {}, fmt.monthYear(date(i.reached))),
        el("td", { class: i.inside ? "check" : "down" },
          i.inside ? "✓ Within range" : i.errorMonths > 0 ? "✗ Later than range" : "✗ Earlier than range")))))));
}

function claudeCard() {
  const when = new Date(CLAUDE.generatedAt);
  return el("section", { class: "card claude" },
    el("div", { class: "card-head" },
      el("span", { class: "badge" }, "Written by Claude"),
      el("h3", {}, CLAUDE.headline)),
    el("p", { style: "margin:0" }, CLAUDE.outlook),
    footnote(`Claude (${CLAUDE.model}) wrote this on ${fmt.date(new Date(Date.UTC(when.getUTCFullYear(), when.getUTCMonth(), when.getUTCDate())))} from the numbers on this site (data through ${fmt.date(date(CLAUDE.dataThrough))}). It's an AI-written reading of trend extrapolations, not a prediction you should rely on.`));
}

function historyChart(f, now) {
  if (!f) return el("p", { class: "muted" }, "No forecasts yet.");
  const cap = new Date(+now + 10 * YEAR);
  const pts = D.history.map((h) => {
    const s = h.forecasts[f.id];
    if (!s?.predicted) return null;
    return { asOf: h.asOf, live: h.live, p: s.predicted, e: s.early ?? s.predicted, l: new Date(Math.min(+(s.late ?? cap), +cap)) };
  }).filter(Boolean);
  const wrap = el("div");
  wrap.append(chart((w, C) => Plot.plot(plotBase(C, {
    ariaLabel: pts.length ? `How the predicted date for "${f.title}" changed: computed in ${fmt.monthYear(pts[0].asOf)} it pointed to ${fmt.monthYear(pts[0].p)}; computed most recently it points to ${fmt.monthYear(pts[pts.length - 1].p)}.` : `No past forecasts for "${f.title}".`,
    width: w, height: 260, marginLeft: 70,
    x: { type: "utc", label: null },
    y: { type: "utc", label: null, grid: true, tickFormat: (d) => fmt.monthYear(d) },
    marks: [
      Plot.areaY(pts, { x: "asOf", y1: "e", y2: "l", fill: C.series[0], fillOpacity: 0.15 }),
      Plot.line(pts, { x: "asOf", y: "p", stroke: C.series[0], strokeWidth: 2 }),
      Plot.dot(pts, { x: "asOf", y: "p", r: 4, stroke: C.series[0], fill: (d) => (d.live ? C.series[0] : C.surface), strokeWidth: 1.5,
        tip: { ...tip(C), format: { x: (d) => `computed ${fmt.date(d)}`, y: (d) => `predicted ${fmt.monthYear(d)}`, fill: false } } }),
    ],
  }))));
  wrap.append(legend([["Recomputed from past data", "transparent"], ["Saved by the daily update", colors().series[0]]]));
  wrap.querySelector(".legend i").style.border = `1.5px solid ${colors().series[0]}`;
  if (pts.length) {
    const first = pts[0], last = pts[pts.length - 1];
    const moved = (last.p - first.p) / (30.44 * DAY);
    const change = Math.abs(moved) < 1 ? "about the same" : `${Math.round(Math.abs(moved))} months ${moved < 0 ? "earlier" : "later"}`;
    wrap.append(footnote(`In ${fmt.monthYear(first.asOf)} the trend pointed to ${fmt.monthYear(first.p)}; it now points to ${fmt.monthYear(last.p)}, ${change}. Daily log: ${D.history.filter((h) => h.live).length} day(s) so far.`));
  }
  return wrap;
}

pages.labs = () => {
  const avg = (l) => { const v = Object.values(l.standing); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : 0; };
  const labs = [...D.labs].sort((a, b) => avg(b) - avg(a));
  const areas = D.areas.map((a) => a.name);
  const areaOf = Object.fromEntries(D.areas.flatMap((a) => a.benchmarks.map((b) => [short(b), a.name])));

  const standing = heatmap(labs.flatMap((l) => areas.map((a) => ({
    lab: l.name, col: a, value: l.standing[a],
    label: l.standing[a] == null ? "–" : fmt.pct(l.standing[a]) + (l.recordsHeld.some((b) => areaOf[b] === a) ? " ★" : ""),
  }))), labs.map((l) => l.name), areas, 150, "Each lab's standing by capability area, as a share of the best score; a star marks a current record");

  const quarters = [...new Set(labs.flatMap((l) => l.releasesByQuarter.map((q) => q.quarter)))]
    .sort((a, b) => { const [qa, ya] = a.split(" "), [qb, yb] = b.split(" "); return ya - yb || qa.localeCompare(qb); });
  const maxCount = Math.max(1, ...labs.flatMap((l) => l.releasesByQuarter.map((q) => q.count)));
  const pace = heatmap(labs.flatMap((l) => quarters.map((q) => {
    const n = l.releasesByQuarter.find((x) => x.quarter === q)?.count ?? 0;
    return { lab: l.name, col: q, value: n ? n / maxCount : null, label: n ? String(n) : "" };
  })), labs.map((l) => l.name), quarters, 70, "New models first seen per lab per quarter");

  return el("div", {},
    header("Who's working on what", "Where each major lab leads, how fast it ships, and what it says it's betting on. The charts update daily; the focus notes are researched and dated."),
    freshnessNote(D.labNotesAsOf, "Lab focus notes researched"),
    card("Where each lab stands", "Each lab's best score as a share of the overall best, averaged over the area's benchmarks it has results on. – = not tested. ★ = holds a current record in that area.", standing),
    card("Release pace", "New models first seen each quarter, in Epoch's benchmark results or OpenRouter's listings.", pace),
    el("div", { class: "grid", style: "--min: 420px" }, labs.map(labCard)),
    footnote("Standing compares best-ever scores, so a lab that stopped submitting to a benchmark keeps its last result. Labs differ in how many of their models Epoch has evaluated."));
};

const RAMP = ["#cde2fb", "#b7d3f6", "#9ec5f4", "#86b6ef", "#6da7ec", "#5598e7", "#3987e5", "#2a78d6", "#256abf", "#1c5cab", "#184f95", "#104281", "#0d366b"];
function rampColor(v) { const i = Math.max(0, Math.min(RAMP.length - 1, Math.round(v * (RAMP.length - 1)))); return [RAMP[i], i < 6]; }

function heatmap(cells, rows, cols, minColumn = 70, label = "Heatmap") {
  // Hidden for sighted users but read by screen readers. The wrapper does the hiding: a table
  // ignores the 1px width and would push the page sideways on phones.
  const table = el("div", { class: "sr-only" }, el("table", {},
    el("caption", {}, label),
    el("thead", {}, el("tr", {}, el("th", { scope: "col" }, "Lab"), cols.map((c) => el("th", { scope: "col" }, c)))),
    el("tbody", {}, rows.map((r) => el("tr", {}, el("th", { scope: "row" }, r),
      cols.map((c) => el("td", {}, cells.find((x) => x.lab === r && x.col === c)?.label || "none")))))));
  return el("div", {}, table, el("div", { class: "scroll-x", "aria-hidden": "true" }, chart((w, C) => {
    const width = Math.max(w, 140 + cols.length * minColumn);
    return Plot.plot(plotBase(C, {
      ariaLabel: label,
      width, height: rows.length * 32 + 40, marginLeft: 140, marginTop: 30,
      x: { domain: cols, axis: "top", label: null, tickSize: 0 },
      y: { domain: rows, label: null, tickSize: 0 },
      marks: [
        Plot.cell(cells, { x: "col", y: "lab", inset: 1.5, rx: 3, fill: (c) => (c.value == null ? C.border : rampColor(c.value)[0]), fillOpacity: (c) => (c.value == null ? 0.5 : 1) }),
        Plot.text(cells, { x: "col", y: "lab", text: "label", fill: (c) => (c.value == null ? C.muted : rampColor(c.value)[1] ? "#111" : "#fff"), fontSize: 11.5 }),
      ],
    }));
  })));
}

function labCard(l) {
  const n = l.note;
  const facts = [];
  if (l.latestName) facts.push(["Latest model", `${l.latestName} · ${fmt.date(l.latestDate)}`]);
  facts.push(["Models in the last year", l.recentModels.length ? `${l.recentModels.length}: ${l.recentModels.slice(0, 5).join(", ")}${l.recentModels.length > 5 ? "…" : ""}` : "None seen"]);
  if (l.recordsHeld.length) facts.push(["Holds records on", l.recordsHeld.join(", ")]);
  const push = Object.entries(l.recentRecords).sort((a, b) => b[1] - a[1])[0];
  if (push) facts.push(["Most records set (12 mo)", `${push[0]} (${push[1]})`]);
  const mods = Object.entries(l.modalityShare).filter(([, v]) => v > 0).map(([k, v]) => `${k.toLowerCase()} ${fmt.pct(v)}`);
  if (Object.keys(l.modalityShare).length) facts.push(["Modalities (new models)", mods.length ? mods.join(", ") : "text only"]);
  if (l.openShare != null) facts.push(["Open weights", `${fmt.pct(l.openShare)} of notable models, last 2 years`]);
  if (l.priceMin != null) facts.push(["API prices", `${fmt.price(l.priceMin)} – ${fmt.price(l.priceMax)} / M tokens`]);
  if (l.largestRun) facts.push(["Largest training run", `${fmt.flop(l.largestRun)} FLOP`]);
  return card(l.name, n?.flagships?.length ? `Flagships: ${n.flagships.join(", ")}` : null,
    n ? el("div", {},
      el("div", {}, n.focus.map((t) => el("span", { class: "tag" }, t))),
      el("p", { style: "margin:6px 0" }, n.summary),
      el("div", { class: "small muted", style: "font-weight:600" }, "Betting on"),
      el("ul", { class: "bullets" }, n.bets.map((b) => el("li", {}, b))),
      el("p", { class: "small muted" }, `Researched ${n.asOf} · `, n.sources.map((s, i) => [el("a", { href: s, target: "_blank", rel: "noopener" }, `source ${i + 1}`), i < n.sources.length - 1 ? ", " : ""])),
      el("hr", { style: "border:0;border-top:1px solid var(--border);margin:10px 0" })) : null,
    el("dl", { class: "facts" }, facts.map(([k, v]) => [el("dt", {}, k), el("dd", {}, v)])));
}

pages.advances = () => {
  // The items new on arrival stay marked for this whole visit, even after they're recorded as seen.
  const shownNew = new Set(NEW_IDS);
  const now = new Date();
  const kinds = ["All", ...(shownNew.size ? ["New to you"] : []), "Highlights", "New records", "New models"];
  if (state.kind === "New to you" && !shownNew.size) state.kind = "All";
  const directions = ["All directions", ...[...new Set(D.feed.map((i) => i.direction))].sort()];
  const list = el("ul", { class: "feed" });
  const count = el("span", { class: "muted" });
  const sym = { "Highlights": "✦", "New records": "🏆", "New models": "▣" };
  const renderList = () => {
    const shown = D.feed.filter((i) => (state.kind === "All" || i.kind === state.kind || (state.kind === "New to you" && shownNew.has(i.id)))
      && (state.direction === "All directions" || i.direction === state.direction));
    count.textContent = `${shown.length} items`;
    list.replaceChildren(...shown.map((i) => el("li", {},
      el("span", { class: "date" }, fmt.date(i.date)),
      el("span", { class: "sym", "aria-hidden": "true" }, sym[i.kind]),
      el("div", {},
        shownNew.has(i.id) ? el("span", { class: "badge new" }, "New") : null,
        i.link ? el("a", { href: i.link, target: "_blank", rel: "noopener", style: "font-weight:550" }, i.title) : el("strong", {}, i.title),
        el("div", { class: "muted" }, i.detail),
        el("div", { class: "meta" }, `${i.lab} · ${i.direction}`)))));
  };
  renderList();

  const monthly = chart((w, C) => {
    const yearAgo = new Date(+now - YEAR);
    const items = D.feed.filter((i) => i.kind !== "New models" && i.date >= yearAgo);
    const key = (d) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
    const counts = new Map();
    for (const i of items) { const k = key(i.date) + "|" + i.direction; counts.set(k, (counts.get(k) ?? 0) + 1); }
    const rows = [...counts].map(([k, n]) => { const [m, dir] = k.split("|"); return { month: m, direction: dir, n }; });
    const order = [...new Set(rows.map((r) => r.direction))].sort((a, b) =>
      rows.filter((r) => r.direction === b).reduce((s, r) => s + r.n, 0) - rows.filter((r) => r.direction === a).reduce((s, r) => s + r.n, 0));
    const months = [];
    for (let d = new Date(Date.UTC(yearAgo.getUTCFullYear(), yearAgo.getUTCMonth(), 1)); d <= now; d = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1))) months.push(key(d));
    return Plot.plot(plotBase(C, {
      ariaLabel: `Stacked bar chart of highlights and new records per month over the last year, by direction. Totals: ${order.map((o) => `${o} ${rows.filter((r) => r.direction === o).reduce((s, r) => s + r.n, 0)}`).join(", ")}.`,
      width: w, height: 230,
      x: { domain: months, label: null, tickFormat: (m) => { const [y, mo] = m.split("-"); return mo === "01" || m === months[0] ? `${MONTHS[mo - 1]} ${y}` : MONTHS[mo - 1]; } },
      y: { label: null, grid: true },
      color: { domain: order, range: order.map((_, i) => C.series[i]), legend: true },
      marks: [Plot.barY(rows, { x: "month", y: "n", fill: "direction", order, tip: tip(C) }), Plot.ruleY([0], { stroke: C.border })],
    }));
  });

  // Seeing this page counts as seeing these items: they stay marked "New" for this visit only.
  markSeen();
  NEW_IDS = new Set();
  queueMicrotask(updateNewBadge);
  return el("div", {},
    header("Latest advances", "Researched highlights, plus new benchmark records and newly listed models detected in the data every day."),
    freshnessNote(D.highlightsThrough, "Researched highlights run through"),
    card("Highlights and records per month, by direction", "What the last year's advances have been about. New model listings are left out because they'd swamp the chart.", monthly),
    el("div", { class: "controls" },
      segmented("kind", kinds.map((k) => [k, k === "All" ? "Everything" : k === "New to you" ? `New to you (${shownNew.size})` : k]), state.kind, (v) => { state.kind = v; renderList(); }),
      select(directions.map((d) => [d, d]), state.direction, (v) => { state.direction = v; renderList(); }, "Direction"),
      count),
    list);
};

pages.capabilities = () => {
  DEFAULTS.areaName = D.areas[0].name; // the automatic pick stays out of the link
  if (!D.areas.some((a) => a.name === state.areaName)) state.areaName = D.areas[0].name;
  const slot = el("div");
  const render = () => {
    const area = D.areas.find((a) => a.name === state.areaName);
    const since = new Date(Date.now() - state.since * YEAR);
    slot.replaceChildren(
      card(area.name, area.summary, frontierChart(area, since, true, 400),
        footnote("Lines trace the best score so far; dots are individual models (hover for details). Scores come from Epoch AI's benchmarking hub, which mixes its own runs with results reported by benchmark authors. Each model's best reasoning-effort setting is shown.")),
      el("div", { class: "grid", style: "--min: 300px; margin-top: 16px" }, area.benchmarks.map(leaderboard)));
  };
  render();
  return el("div", {},
    header("Capabilities", "Every tracked model result by capability area."),
    el("div", { class: "controls" },
      select(D.areas.map((a) => [a.name, a.name]), state.areaName, (v) => { state.areaName = v; render(); }, "Area"),
      segmented("since", [[1, "1 year"], [2, "2 years"], [4, "4 years"]], state.since, (v) => { state.since = +v; render(); })),
    slot);
};

function leaderboard(benchmark) {
  const best = new Map();
  for (const r of D.results) if (r.b === benchmark && (!best.has(r.m) || best.get(r.m).s < r.s)) best.set(r.m, r);
  const top = [...best.values()].sort((a, b) => b.s - a.s).slice(0, 8);
  const info = D.benchmarks.find((b) => b.name === benchmark);
  return card(short(benchmark), info?.released ? `Benchmark published ${fmt.date(date(info.released))}` : null,
    el("div", { class: "rows" }, top.map((r, i) => el("div", { class: "row" },
      el("span", {}, el("span", { class: "muted tnum" }, `${i + 1}  `), r.m, el("span", { class: "small muted" }, ` · ${r.o}`)),
      el("span", { class: "tnum" }, fmt.pct(r.s, 1))))));
}

pages.models = () => {
  const keys = D.keyBenchmarks;
  const yearAgo = new Date(Date.now() - YEAR);
  const labCounts = new Map();
  for (const m of D.models) labCounts.set(m.lab, (labCounts.get(m.lab) ?? 0) + 1);
  const labs = [...labCounts].sort((a, b) => b[1] - a[1]).slice(0, 14).map(([l]) => l);

  const cols = [
    ["name", "Model", (m) => m.name], ["released", "Released", (m) => +m.released],
    ["price", "$ / M tokens", (m) => m.price ?? Infinity], ["context", "Context", (m) => m.context ?? 0],
    ...keys.map(([b, label]) => [b, label, (m) => m.scores[b] ?? -1]),
  ];
  const tableWrap = el("div", { class: "table-wrap" });
  const count = el("span", { class: "muted" });
  const detail = el("div");

  const render = () => {
    const [key, dir] = state.sort;
    const getter = cols.find((c) => c[0] === key)[2];
    const rows = D.models
      .filter((m) => !state.recent || m.released >= yearAgo)
      .filter((m) => state.lab === "All labs" || m.lab === state.lab)
      .filter((m) => !state.search || (m.name + " " + m.lab).toLowerCase().includes(state.search.toLowerCase()))
      .filter((m) => keys.some(([b]) => m.scores[b] != null) || m.horizonMinutes != null)
      .sort((a, b) => { const x = getter(a), y = getter(b); return (x < y ? -1 : x > y ? 1 : 0) * dir; });
    count.textContent = `${rows.length} models`;
    // Sort controls are real buttons so they work from the keyboard; aria-sort announces the order.
    const thead = el("thead", {}, el("tr", {}, cols.map(([k, label]) => el("th", {
      scope: "col", "aria-sort": k === key ? (dir > 0 ? "ascending" : "descending") : "none",
    }, el("button", { type: "button", class: "sort", onclick: () => {
      state.sort = [k, k === key ? -dir : k === "name" ? 1 : -1];
      render();
      tableWrap.querySelector(`th:nth-child(${cols.findIndex((c) => c[0] === k) + 1}) button`)?.focus();
    } }, label)))));
    const tbody = el("tbody", {}, rows.map((m) => el("tr", {
      "aria-selected": state.selected === m.name ? "true" : null,
      onclick: () => { state.selected = m.name; render(); detail.scrollIntoView({ behavior: "smooth", block: "nearest" }); },
    },
      el("td", {}, el("button", { type: "button", class: "linklike", "aria-label": `${m.name}, show full profile`,
        onclick: (e) => { e.stopPropagation(); state.selected = m.name; render(); detail.querySelector("h3")?.setAttribute("tabindex", "-1"); detail.querySelector("h3")?.focus(); } }, m.name),
        el("span", { class: "sub" }, m.lab)),
      el("td", {}, fmt.date(m.released)),
      el("td", { class: m.price == null ? "na" : null }, m.price == null ? "–" : fmt.price(m.price)),
      el("td", { class: m.context ? null : "na" }, m.context ? fmt.tokens(m.context) : "–"),
      keys.map(([b]) => el("td", { class: m.scores[b] == null ? "na" : null }, fmt.pct(m.scores[b]))))));
    tableWrap.replaceChildren(el("table", {}, thead, tbody));
    const sel = D.models.find((m) => m.name === state.selected);
    detail.replaceChildren(sel ? modelDetail(sel) : el("span"));
  };
  render();

  return el("div", {},
    header("Models", "What each model can do: its best score on the key benchmarks, with price and context window where the model is sold through an API."),
    el("div", { class: "controls" },
      el("input", { type: "search", placeholder: "Search models or labs", value: state.search, "aria-label": "Search", oninput: (e) => { state.search = e.target.value; render(); } }),
      select([["All labs", "All labs"], ...labs.map((l) => [l, l])], state.lab, (v) => { state.lab = v; render(); }, "Lab"),
      el("label", {}, el("input", { type: "checkbox", checked: state.recent, onchange: (e) => { state.recent = e.target.checked; render(); } }), "Released in the last year"),
      count),
    tableWrap,
    footnote("Price is a 3:1 blend of input and output price per million tokens, from OpenRouter; it shows only when the names match. Scores are the best across reasoning-effort settings, from Epoch AI. Click a column to sort; select a row for the full profile."),
    detail);
};

function modelDetail(m) {
  const scores = Object.entries(m.scores).sort((a, b) => b[1] - a[1]);
  const facts = [];
  if (m.price != null) {
    facts.push(["Price", `${fmt.price(m.inputPrice)} in · ${fmt.price(m.outputPrice)} out per M tokens`], ["Context", `${fmt.tokens(m.context)} tokens`],
      ["Takes in", m.inputModalities.join(", ")], ["Produces", m.outputModalities.join(", ")]);
  } else facts.push(["API", "Not listed on OpenRouter under this name"]);
  if (m.computeFLOP) facts.push(["Training compute", `${fmt.flop(m.computeFLOP)} FLOP`]);
  if (m.horizonMinutes) facts.push(["Task horizon", fmt.minutes(m.horizonMinutes)]);
  if (m.openWeights != null) facts.push(["Weights", m.openWeights ? "Open" : "Closed"]);
  return card(m.name, `${m.lab} · first result ${fmt.date(m.released)} · ${scores.length} benchmarks`,
    el("div", { class: "grid", style: "--min: 280px" },
      el("dl", { class: "facts" }, facts.map(([k, v]) => [el("dt", {}, k), el("dd", {}, v)])),
      chart((w, C) => Plot.plot(plotBase(C, {
        ariaLabel: `Bar chart of ${m.name}'s best scores: ${scores.map(([b, s]) => `${short(b)} ${fmt.pct(s, 1)}`).join(", ")}.`,
        width: w, height: scores.length * 22 + 20, marginLeft: Math.min(200, w * 0.45), marginRight: 50,
        x: { domain: [0, 1], axis: null }, y: { domain: scores.map(([b]) => short(b)), label: null, tickSize: 0 },
        marks: [
          Plot.barX(scores, { x: ([, s]) => s, y: ([b]) => short(b), fill: C.series[0], rx: 3, insetTop: 4, insetBottom: 4 }),
          Plot.text(scores, { x: ([, s]) => s, y: ([b]) => short(b), text: ([, s]) => fmt.pct(s, 1), dx: 5, textAnchor: "start", fill: C.text2 }),
        ],
      })))));
}

pages.cost = () => {
  if (!D.keyBenchmarks.some(([b]) => b === state.costBench)) state.costBench = DEFAULTS.costBench;
  state.threshold = Math.min(0.95, Math.max(0.1, state.threshold));
  const slot = el("div");
  const best = (b) => Math.max(0, ...D.results.filter((r) => r.b === b).map((r) => r.s));
  const thresholdLabel = el("span", { class: "tnum", style: "min-width:3em" });
  const slider = el("input", { type: "range", min: 0.1, max: 0.95, step: 0.05, value: state.threshold, "aria-label": "Score at least",
    oninput: (e) => { state.threshold = +e.target.value; render(); } });
  const bestLabel = el("span", { class: "muted" });

  const render = () => {
    const b = state.costBench, t = state.threshold;
    thresholdLabel.textContent = fmt.pct(t);
    bestLabel.textContent = `Current best: ${fmt.pct(best(b))}`;
    const steps = cheapestOverTime(b, t);
    const fit = expFit(steps.map((s) => [+s.d, s.price]));
    const sixMonths = new Date(Date.now() - YEAR / 2);
    const dots = D.models.filter((m) => m.price != null && m.scores[b] != null)
      .map((m) => ({ name: m.name, lab: m.lab, price: m.price, score: m.scores[b], recent: m.released >= sixMonths ? "Released in the last 6 months" : "Older", released: m.released }));
    slot.replaceChildren(
      card(`Cheapest price to reach ${fmt.pct(t)} on ${short(b)}`,
        steps.length >= 3 && fit ? `Falling about ${(1 / fit.factorPerYear).toFixed(0)}× per year (exponential fit over ${steps.length} price drops).` : "Too few price drops yet to fit a trend.",
        steps.length ? chart((w, C) => Plot.plot(plotBase(C, {
          ariaLabel: `Step chart of the cheapest listed price for a model scoring at least ${fmt.pct(t)} on ${short(b)}: ${steps.map((s) => `${s.model} at ${fmt.price(s.price)} from ${fmt.monthYear(s.d)}`).join(", then ")}.`,
          width: w, height: 300, marginRight: 30, marginLeft: 56,
          x: { type: "utc", label: null, domain: [steps[0].d, new Date()] },
          y: { type: "log", label: null, grid: true, tickFormat: fmt.price },
          marks: [
            Plot.line([...steps, { ...steps[steps.length - 1], d: new Date() }], { x: "d", y: "price", curve: "step-after", stroke: C.series[0], strokeWidth: 2 }),
            Plot.dot(steps, { x: "d", y: "price", fill: C.series[0], r: 4.5,
              tip: { ...tip(C), format: { x: (d) => fmt.date(d), y: fmt.price } }, channels: { Model: "model", Score: (s) => fmt.pct(s.score, 1) } }),
            Plot.text(steps, { x: "d", y: "price", text: "model", dx: 6, dy: -9, textAnchor: "start", fill: C.text2, fontSize: 11 }),
          ],
        }))) : el("p", { class: "muted" }, "No model with a listed price has reached this score yet. Lower the threshold.")),
      card(`Price against score, ${short(b)}`, "Every model with both a score and a listed price. Up and to the left is better value.",
        chart((w, C) => Plot.plot(plotBase(C, {
          ariaLabel: `Scatter plot of price per million tokens against score on ${short(b)} for ${dots.length} models.` + (dots.length ? ` Highest score: ${[...dots].sort((x, y) => y.score - x.score)[0].name} at ${fmt.pct([...dots].sort((x, y) => y.score - x.score)[0].score, 1)}. Cheapest: ${[...dots].sort((x, y) => x.price - y.price)[0].name} at ${fmt.price([...dots].sort((x, y) => x.price - y.price)[0].price)}.` : ""),
          width: w, height: 320, marginLeft: 48,
          x: { type: "log", label: "Price per million tokens →", tickFormat: fmt.price, grid: true },
          y: { label: null, grid: true, tickFormat: (v) => fmt.pct(v) },
          color: { domain: ["Released in the last 6 months", "Older"], range: [C.series[1], C.series[0]], legend: true },
          marks: [Plot.dot(dots, { x: "price", y: "score", fill: "recent", r: 4,
            tip: { ...tip(C), format: { x: fmt.price, y: (v) => fmt.pct(v, 1), fill: false } }, channels: { Model: "name", Lab: "lab" } })],
        }))),
        footnote("Prices are today's OpenRouter list prices (3:1 input:output blend), so older models show their current, often reduced, price.")));
  };
  render();
  return el("div", {},
    header("Cost", "How fast a given level of capability gets cheaper. Pick a benchmark and a score; the line shows the cheapest model that had reached it by each date."),
    el("div", { class: "controls" },
      select(D.keyBenchmarks.map(([b, l]) => [b, l]), state.costBench, (v) => {
        state.costBench = v;
        state.threshold = Math.max(0.1, Math.round((best(v) * 0.75) / 0.05) * 0.05);
        slider.value = state.threshold;
        render();
      }, "Benchmark"),
      el("label", {}, "Score at least", slider, thresholdLabel), bestLabel),
    slot);
};

pages.context = () => {
  const listed = D.listed.filter((l) => l.context > 0);
  const top = [...listed].sort((a, b) => b.context - a.context)[0];
  return el("div", {},
    header("Context & Modalities", "How much text models can take in at once, and which kinds of input and output they handle. From every model listed on OpenRouter since 2024."),
    card("Context window by release", "Each dot is a model. The line is the median for models listed that quarter.",
      chart((w, C) => Plot.plot(plotBase(C, {
        ariaLabel: `Scatter plot of context window against listing date for ${listed.length} models since 2024. The quarterly median went from ${fmt.tokens(D.contextMedians[0]?.value ?? 0)} to ${fmt.tokens(D.contextMedians[D.contextMedians.length - 1]?.value ?? 0)} tokens.` + (top ? ` Largest: ${top.name} at ${fmt.tokens(top.context)}.` : ""),
        width: w, height: 320, marginLeft: 48,
        x: { type: "utc", label: null },
        y: { type: "log", label: null, grid: true, ticks: [4096, 32768, 131072, 1e6, 1e7], tickFormat: fmt.tokens },
        marks: [
          Plot.dot(listed, { x: "created", y: "context", r: 2.5, fill: C.series[0], fillOpacity: 0.45,
            tip: { ...tip(C), format: { x: (d) => fmt.date(d), y: (v) => `${fmt.tokens(v)} tokens` } }, channels: { Model: "name", Lab: "lab" } }),
          Plot.line(D.contextMedians, { x: (p) => new Date(+p.date + 45 * DAY), y: "value", stroke: C.series[1], strokeWidth: 2, marker: "circle-stroke" }),
        ],
      }))),
      legend([["Model", colors().series[0]], ["Quarterly median", colors().series[1], true]]),
      top ? footnote(`Largest so far: ${top.name} (${top.lab}) at ${fmt.tokens(top.context)} tokens, listed ${fmt.date(top.created)}.`) : null),
    card("Which modalities new models support", "Share of models first listed each quarter that accept or produce each kind of media.",
      chart((w, C) => {
        const mods = [...new Set(D.modalityShares.map((s) => s.modality))];
        return Plot.plot(plotBase(C, {
          ariaLabel: (() => { const q = D.modalityShares[D.modalityShares.length - 1]?.quarter; return `Line chart of the share of new models supporting each modality, by quarter. In ${q}: ${D.modalityShares.filter((s) => s.quarter === q).map((s) => `${s.modality} ${fmt.pct(s.share)}`).join(", ")}.`; })(),
          width: w, height: 280,
          x: { type: "utc", label: null },
          y: { domain: [0, 1], grid: true, label: null, tickFormat: (v) => fmt.pct(v) },
          color: { domain: mods, range: mods.map((_, i) => C.series[i]), legend: true },
          marks: [
            Plot.line(D.modalityShares, { x: "start", y: "share", stroke: "modality", strokeWidth: 2, marker: "circle-stroke" }),
            Plot.dot(D.modalityShares, Plot.pointerX({ x: "start", y: "share", fill: "modality", r: 4,
              tip: { ...tip(C), format: { x: false, y: (v) => fmt.pct(v) } }, channels: { Quarter: "quarter", Models: "count" } })),
          ],
        }));
      }),
      footnote("Models later removed from OpenRouter aren't counted, so older quarters are thinner.")));
};

pages.compute = () => {
  const slot = el("div");
  const largest = [...D.notable].sort((a, b) => b.flop - a.flop).slice(0, 10);
  const render = () => {
    const since = date(`${state.computeSince}-01-01`);
    const models = D.notable.filter((n) => n.date >= since).map((n) => ({ ...n, kind: n.frontier ? "Frontier model" : "Other notable model" }));
    const t = D.tiles;
    slot.replaceChildren(card("Training compute over time",
      t.computeFactorPerYear ? `Frontier runs grow about ${t.computeFactorPerYear.toFixed(1)}× per year, doubling every ${fmt.months(t.computeDoublingMonths)} (dashed line, fit since 2020).` : null,
      chart((w, C) => Plot.plot(plotBase(C, {
        ariaLabel: `Scatter plot of training compute for ${models.length} notable models since ${state.computeSince}, frontier models highlighted, with a trend line.` + (t.computeFactorPerYear ? ` Frontier runs grow about ${t.computeFactorPerYear.toFixed(1)}x per year.` : "") + (models.length ? ` Largest: ${[...models].sort((a, b) => b.flop - a.flop)[0].name}.` : ""),
        width: w, height: 380, marginLeft: 52,
        x: { type: "utc", label: null },
        y: { type: "log", label: null, grid: true, tickFormat: (v) => `10^${Math.round(Math.log10(v))}`, ticks: 8 },
        color: { domain: ["Frontier model", "Other notable model"], range: [C.series[1], C.series[0]], legend: true },
        marks: [
          Plot.dot(models, { x: "date", y: "flop", fill: "kind", r: (n) => (n.frontier ? 3.5 : 2.5), fillOpacity: (n) => (n.frontier ? 0.9 : 0.35),
            tip: { ...tip(C), format: { x: (d) => fmt.date(d), y: (v) => `${fmt.flop(v)} FLOP`, fill: false, r: false, fillOpacity: false } },
            channels: { Model: "name", Org: "org" } }),
          Plot.line(D.computeFit.filter((p) => p.date >= since || D.computeFit.indexOf(p) === 1), { x: "date", y: "value", stroke: C.muted, strokeDasharray: "5,4", strokeWidth: 1.5 }),
        ],
      })))));
  };
  render();
  return el("div", {},
    header("Compute", "Training compute of notable AI models, from Epoch AI. Frontier models are those among the ten largest training runs when they were released."),
    segmented("csince", [[2012, "2012"], [2018, "2018"], [2022, "2022"]], state.computeSince, (v) => { state.computeSince = +v; render(); }),
    slot,
    card("Largest training runs", "Estimated by Epoch AI from disclosures, hardware and timing; most labs don't publish these figures.",
      el("div", { class: "rows" }, largest.map((n, i) => el("div", { class: "row" },
        el("span", {}, el("span", { class: "muted tnum" }, `${i + 1}  `), n.name, el("span", { class: "small muted" }, ` · ${n.org} · ${fmt.date(n.date)}`)),
        el("span", { class: "tnum" }, `${fmt.flop(n.flop)} FLOP`))))));
};

// ---------- Shell ----------

function route() {
  // Only "#/page" hashes are routes; anything else (an in-page anchor) leaves the page as it is.
  if (location.hash && !location.hash.startsWith("#/") && $("#page").childElementCount) return;
  const id = (location.hash.match(/^#\/(\w+)/) ?? [])[1];
  const page = PAGES.find(([p]) => p === id) ?? PAGES[0];
  // Settings carried in the link (e.g. #/cost?benchmark=HLE&score=0.5) override the current ones.
  const params = new URLSearchParams(location.hash.split("?")[1] ?? "");
  for (const [param, key, parse] of LINKED[page[0]] ?? []) {
    if (!params.has(param)) continue;
    const value = parse(params.get(param));
    if (!(typeof value === "number" && Number.isNaN(value))) state[key] = value;
  }
  currentPage = page[0];
  document.querySelectorAll("#nav a").forEach((a) => {
    if (a.dataset.page === page[0]) a.setAttribute("aria-current", "page");
    else a.removeAttribute("aria-current");
  });
  $("#page-name").textContent = page[1];
  document.title = page[0] === "trends" ? "AI Advances" : `${page[1]} · AI Advances`;
  $("#page").replaceChildren(pages[page[0]]());
  $("#page").focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

function shell() {
  $("#nav").replaceChildren(...PAGES.map(([id, name]) => el("li", {}, el("a", { href: `#/${id}`, "data-page": id }, name))));
  $("#status").textContent = `Data through ${fmt.date(D.latestDataDate)} · updated ${fmt.date(D.generatedAt)}`;
  $("#sources-panel").replaceChildren(
    el("strong", {}, "Data sources"),
    ...D.sources.map((s) => el("p", {}, el("a", { href: s.page, target: "_blank", rel: "noopener" }, s.name), el("br"), el("span", { class: "small muted" }, s.credit))),
    el("p", { class: "small muted" }, "A GitHub Action downloads the sources, recomputes every trend and forecast, and republishes this site daily. The same analysis runs in the AI Advances Mac app."));
}

function feedback() {
  const dialog = $("#feedback"), text = $("#feedback-text"), send = $("#feedback-send");
  $("#feedback-open").addEventListener("click", () => dialog.showModal());
  text.addEventListener("input", () => { send.disabled = !text.value.trim(); });
  dialog.addEventListener("close", () => {
    if (dialog.returnValue !== "send") return;
    const kind = dialog.querySelector("input[name=kind]:checked").value;
    const firstLine = text.value.trim().split("\n")[0].slice(0, 70);
    const url = new URL(ISSUES_URL);
    url.searchParams.set("title", `[${kind}] ${firstLine}`);
    url.searchParams.set("body", `${text.value.trim()}\n\n---\nAI Advances website, ${navigator.userAgent}`);
    window.open(url, "_blank", "noopener");
    text.value = ""; send.disabled = true;
  });
}

async function main() {
  feedback();
  $(".skip-link").addEventListener("click", (e) => { e.preventDefault(); $("#page").focus(); });
  try {
    const res = await fetch("data/site.json", { cache: "no-cache" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    D = prepare(await res.json());
    // The Claude outlook is optional: missing or broken just means the card isn't shown.
    CLAUDE = await fetch("data/outlook.json", { cache: "no-cache" }).then((r) => (r.ok ? r.json() : null)).catch(() => null);
  } catch (e) {
    $("#page").replaceChildren(el("p", {}, `Couldn't load the data (${e.message}).`));
    return;
  }
  shell();
  loadSeen();
  updateNewBadge();
  route();
  addEventListener("hashchange", route);
  let t;
  addEventListener("resize", () => { clearTimeout(t); t = setTimeout(rerenderCharts, 150); });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", rerenderCharts);
}

main();
