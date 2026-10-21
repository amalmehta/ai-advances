// Loads every page of the built website in headless Chromium and fails if any page throws,
// logs a console error, renders nothing, or shows broken values. The daily build runs this
// before deploying, so a bad data day leaves the previous site up instead of a broken one.
//
//   npm install --no-save playwright && npx playwright install chromium
//   node scripts/smoke_test.mjs http://localhost:8766/ site/data/site.json
//
// The second argument is the site.json being tested; the link checks pick a real model and
// benchmark from it, so they keep working as models come and go.

import { chromium } from "playwright";
import { readFileSync } from "node:fs";

const base = process.argv[2] ?? "http://localhost:8766/";
const GOTO = { waitUntil: "networkidle", timeout: 30000 };

// A model and a non-default key benchmark to put in links.
let model = "GPT-6 Astra", bench = { name: "SimpleQA Verified", short: "SimpleQA" };
if (process.argv[3]) {
  const site = JSON.parse(readFileSync(process.argv[3], "utf8"));
  const best = [...site.models].sort((a, b) => Object.keys(b.scores).length - Object.keys(a.scores).length
    || (b.released ?? "").localeCompare(a.released ?? ""))[0];
  if (best) model = best.name;
  const key = site.keyBenchmarks.map(([name]) => name).find((n) => n !== "GPQA diamond");
  if (key) bench = { name: key, short: site.benchmarks.find((b) => b.name === key)?.short ?? key };
}
console.log(`Link checks use model "${model}" and benchmark "${bench.name}".`);
const pages = {
  trends: { charts: 7 },
  forecasts: { charts: 2, text: ["Track record"] },
  labs: { charts: 2 },
  advances: { charts: 1 },
  capabilities: { charts: 1 },
  models: { rows: 20 },
  cost: { charts: 2 },
  context: { charts: 2 },
  compute: { charts: 1 },
};
// Text that only appears when something upstream produced a missing or broken value.
const broken = ["[object ", "NaN", "undefined", "Invalid Date", "Infinity"];

const browser = await chromium.launch();
const problems = [];
// outlook.json is optional and may legitimately be missing; every other request must succeed.
const optional = (url) => url.split("?")[0].endsWith("outlook.json");
const watch = (page, errors) => {
  page.on("pageerror", (e) => errors.push(`page error: ${e.message}`));
  page.on("console", (m) => {
    if (m.type() === "error" && !optional(m.location()?.url ?? "")) errors.push(`console: ${m.text()}`);
  });
  page.on("requestfailed", (r) => { if (!optional(r.url())) errors.push(`request failed: ${r.url()}`); });
  page.on("response", (r) => { if (r.status() >= 400 && !optional(r.url())) errors.push(`HTTP ${r.status()}: ${r.url()}`); });
};
for (const width of [1280, 390, 375]) {
  const page = await browser.newPage({ viewport: { width, height: 900 } });
  const errors = [];
  watch(page, errors);

  for (const [id, expect] of Object.entries(pages)) {
    const where = `${id} @ ${width}px`;
    errors.length = 0;
    await page.goto(`${base}#/${id}`, GOTO);
    await page.waitForSelector("#page h1", { timeout: 15000 }).catch(() => errors.push("no page heading"));
    await page.waitForTimeout(400); // charts render in a microtask after the page
    const result = await page.evaluate(() => ({
      text: document.querySelector("#page")?.innerText ?? "",
      charts: document.querySelectorAll("#page .chart svg[aria-label]").length,
      rows: document.querySelectorAll("#page tbody tr").length,
      overflow: document.documentElement.scrollWidth > document.documentElement.clientWidth,
    }));
    for (const e of errors) problems.push(`${where}: ${e}`);
    for (const b of broken) if (result.text.includes(b)) problems.push(`${where}: page shows "${b}"`);
    if (expect.charts && result.charts < expect.charts) problems.push(`${where}: ${result.charts} labelled charts, expected at least ${expect.charts}`);
    if (expect.rows && result.rows < expect.rows) problems.push(`${where}: ${result.rows} table rows, expected at least ${expect.rows}`);
    for (const t of expect.text ?? []) if (!result.text.includes(t)) problems.push(`${where}: missing "${t}"`);
    if (result.overflow) problems.push(`${where}: page scrolls sideways`);
    console.log(`${problems.some((p) => p.startsWith(where)) ? "FAIL" : "ok  "} ${where} (${result.charts} charts)`);
  }
  await page.close();
}
// Shareable links: opening a link restores the view, and changing a setting updates the link.
{
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  watch(page, errors);
  const check = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} link: ${what}`); if (!ok) problems.push(`link: ${what}`); };
  const open = async (hash) => { await page.goto(`${base}${hash}`, GOTO); await page.waitForTimeout(500); };
  const hash = () => page.url().split("#")[1];

  await open(`#/cost?benchmark=${encodeURIComponent(bench.name)}&score=0.4`);
  check((await page.textContent("#page")).includes(`reach 40% on ${bench.short}`), `cost link opens ${bench.short} at 40%`);

  await open(`#/models?model=${encodeURIComponent(model)}`);
  check(await page.locator("#page h3", { hasText: model }).count() > 0, `models link opens the ${model} profile`);

  await open("#/forecasts?forecast=metr-month");
  check(await page.locator("#page select").inputValue() === "metr-month", "forecasts link selects the work-month forecast");

  await open("#/capabilities");
  await page.selectOption("#page select", { label: "Coding" });
  await page.waitForTimeout(300);
  check(page.url().endsWith("#/capabilities?area=Coding"), `changing the area updates the link (${page.url().split("#")[1]})`);

  await open("#/cost?score=banana&benchmark=Nonsense");
  check((await page.textContent("#page")).includes("on GPQA") && !(await page.textContent("#page")).includes("NaN"), "a garbled cost link falls back to defaults");

  await open("#/forecasts");
  check(page.url().endsWith("#/forecasts"), `a plain page link stays plain (${page.url().split("#")[1]})`);

  await open("#/capabilities?area=Nonsense");
  check(await page.locator("#page h1", { hasText: "Capabilities" }).count() > 0, "an unknown area falls back instead of crashing");

  // Out-of-range values fall back to the defaults, and the link drops them.
  await open("#/trends?window=5");
  check(await page.locator('#page input[name="window"]:checked').getAttribute("value") === "12" && hash() === "/trends",
    `an out-of-range window falls back to 12 months (${hash()})`);
  await open("#/compute?since=1999");
  check(await page.locator('#page input[name="csince"]:checked').getAttribute("value") === "2018" && hash() === "/compute",
    `an unknown compute start falls back to 2018 (${hash()})`);
  await open("#/models?lab=Nobody&model=Not%20a%20model");
  check(await page.locator("#page select").inputValue() === "All labs" && hash() === "/models", `an unknown lab and model fall back (${hash()})`);

  // The compute trend line is drawn for every start year, including the most recent.
  await open("#/compute?since=2022");
  check(await page.locator('#page .chart [stroke-dasharray="5,4"] path').count() > 0, "the compute trend line shows for 2022");

  // Missing values sort last in both directions.
  await open("#/models");
  const firstPrice = () => page.locator("#page tbody tr:first-child td:nth-child(4)").textContent();
  await page.click("#page th button.sort >> text=$ / M tokens");
  const asc = await firstPrice();
  await page.click("#page th button.sort >> text=$ / M tokens");
  const desc = await firstPrice();
  check(asc !== "–" && desc !== "–", `models without a price sort last both ways (${asc}, ${desc})`);

  // The slider writes a rounded score into the link.
  await open("#/cost");
  await page.locator('#page input[type="range"]').fill("0.7");
  await page.waitForTimeout(200);
  check(/score=0\.7(&|$)/.test(hash()), `the cost slider writes a clean score (${hash()})`);

  for (const e of errors) problems.push(`link pages: ${e}`);
  await page.close();
}
// First visit: the introduction shows on the default page, and stays dismissed.
{
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const check = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} intro: ${what}`); if (!ok) problems.push(`intro: ${what}`); };
  await page.goto(base, GOTO);
  await page.waitForSelector("#page h1", { timeout: 15000 });
  check(await page.locator("#page .intro").count() === 1, "shows on a first visit");
  await page.click("#page .intro button");
  await page.reload(GOTO);
  await page.waitForSelector("#page h1", { timeout: 15000 });
  check(await page.locator("#page .intro").count() === 0, "stays dismissed after a reload");
  // Escape closes the feedback dialog without opening an issue, even after an earlier send
  // (the dialog's returnValue is still "send" then).
  let popups = 0;
  page.on("popup", (p) => { popups++; p.close(); });
  await page.evaluate(() => { document.querySelector("#feedback").returnValue = "send"; });
  await page.click("#feedback-open");
  await page.fill("#feedback-text", "smoke test");
  await page.keyboard.press("Escape");
  await page.waitForTimeout(200);
  check(popups === 0 && !(await page.locator("#feedback[open]").count()), "Escape closes feedback without sending");
  await page.close();
}
await browser.close();

if (problems.length) {
  console.error(`\n${problems.length} problem(s):\n` + problems.map((p) => `  - ${p}`).join("\n"));
  process.exit(1);
}
console.log("\nAll pages rendered cleanly.");
