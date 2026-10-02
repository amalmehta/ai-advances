// Loads every page of the built website in headless Chromium and fails if any page throws,
// logs a console error, renders nothing, or shows broken values. The daily build runs this
// before deploying, so a bad data day leaves the previous site up instead of a broken one.
//
//   npm install --no-save playwright && npx playwright install chromium
//   node scripts/smoke_test.mjs http://localhost:8766/

import { chromium } from "playwright";

const base = process.argv[2] ?? "http://localhost:8766/";
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
for (const width of [1280, 390]) {
  const page = await browser.newPage({ viewport: { width, height: 900 } });
  const errors = [];
  page.on("pageerror", (e) => errors.push(`page error: ${e.message}`));
  page.on("console", (m) => {
    // outlook.json is optional and may legitimately be missing.
    if (m.type() === "error" && !m.text().includes("404")) errors.push(`console: ${m.text()}`);
  });
  page.on("requestfailed", (r) => { if (!r.url().endsWith("outlook.json")) errors.push(`request failed: ${r.url()}`); });

  for (const [id, expect] of Object.entries(pages)) {
    const where = `${id} @ ${width}px`;
    errors.length = 0;
    await page.goto(`${base}#/${id}`, { waitUntil: "networkidle" });
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
  const check = (ok, what) => { console.log(`${ok ? "ok  " : "FAIL"} link: ${what}`); if (!ok) problems.push(`link: ${what}`); };
  const open = async (hash) => { await page.goto(`${base}${hash}`, { waitUntil: "networkidle" }); await page.waitForTimeout(500); };

  await open("#/cost?benchmark=SimpleQA%20Verified&score=0.4");
  check((await page.textContent("#page")).includes("reach 40% on SimpleQA"), "cost link opens SimpleQA at 40%");

  await open("#/models?model=GPT-6%20Astra");
  check(await page.locator("#page h3", { hasText: "GPT-6 Astra" }).count() > 0, "models link opens the GPT-6 Astra profile");

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
  await page.close();
}
await browser.close();

if (problems.length) {
  console.error(`\n${problems.length} problem(s):\n` + problems.map((p) => `  - ${p}`).join("\n"));
  process.exit(1);
}
console.log("\nAll pages rendered cleanly.");
