"""Write the daily Claude outlook for the AI Advances website and Mac app.

Reads the site data the exporter produced, gives Claude a compact fact sheet built
only from those numbers, and asks for a short headline and narrative outlook.
Writes outlook.json next to site.json.

Never fails the website build: without an API key, or if the call fails or is
declined, it keeps the previous outlook (from --previous) and exits 0.

    python3 scripts/write_outlook.py --site site/data/site.json \
        --out site/data/outlook.json --previous data-branch/outlook.json [--dry-run]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
import re
import shutil
import sys

MODEL = "claude-opus-5-5"

SYSTEM = """You write the daily outlook for AI Advances, a site that tracks where AI is heading \
using public benchmark, pricing and compute data.

Write for a curious, technically literate reader. Use only the facts in the fact sheet; never add \
numbers, dates, model names or events that aren't in it. The forecasts are trend extrapolations \
with ranges, not certainties, so say "on current trends" or similar where it matters. Pick the two \
or three things that matter most rather than listing everything, and connect them: what is moving \
fastest, what is stalling, and what that suggests for the next year. Plain, calm language, no hype, \
no lists, no markdown."""

SCHEMA = {
    "type": "object",
    "properties": {
        "headline": {
            "type": "string",
            "description": "One line, at most 12 words, summarizing the direction of the field today.",
        },
        "outlook": {
            "type": "string",
            "description": "3 to 5 sentences of narrative outlook grounded in the fact sheet.",
        },
    },
    "required": ["headline", "outlook"],
    "additionalProperties": False,
}


def fact_sheet(site: dict) -> dict:
    """The subset of site.json Claude sees: headline trends, forecasts, momentum, records, labs."""
    today = dt.date.fromisoformat(site["generatedAt"])
    recent = (today - dt.timedelta(days=90)).isoformat()

    def forecast(f):
        out = {k: f.get(k) for k in ("title", "current", "basis") if f.get(k)}
        if f.get("predicted"):
            out["mostLikely"] = f["predicted"]
            out["likelyRange"] = [f.get("early"), f.get("late") or "open-ended"]
        return out

    forecasts = site["forecasts"]
    upcoming = sorted((f for f in forecasts if f.get("predicted") and not f.get("reached")), key=lambda f: f["predicted"])
    reached = sorted((f for f in forecasts if f.get("reached")), key=lambda f: f["reached"], reverse=True)

    standing = sorted(
        ({"lab": l["name"], "averageStanding": round(sum(l["standing"].values()) / len(l["standing"]), 2),
          "recordsHeld": len(l["recordsHeld"]), "latestModel": l.get("latestName")}
         for l in site["labs"] if l["standing"]),
        key=lambda x: -x["averageStanding"])

    return {
        "date": site["generatedAt"],
        "dataThrough": site.get("latestDataDate"),
        "headlineTrends": site["tiles"],
        "headroomClosedLast12Months": {a["name"]: round(a["momentum"]["12"]["gapClosed"], 2)
                                        for a in site["areas"] if "12" in a["momentum"]},
        "upcomingForecasts": [forecast(f) for f in upcoming],
        "milestonesReached": [{"title": f["title"], "reached": f["reached"]} for f in reached],
        "stalledOrOffTrend": [{"title": f["title"], "current": f.get("current"), "note": f.get("note")}
                              for f in forecasts if not f.get("predicted") and not f.get("reached")],
        "forecastShiftsLast3Months": [{"title": s["title"], "monthsMoved": round(s["months"], 1)}
                                      for s in site.get("shifts", [])],
        "recentRecords": [{"date": i["date"], "title": i["title"], "detail": i["detail"]}
                          for i in site["feed"] if i["kind"] == "New records" and i["date"] >= recent][:15],
        "recentHighlights": [{"date": i["date"], "title": i["title"], "lab": i["lab"]}
                             for i in site["feed"] if i["kind"] == "Highlights" and i["date"] >= recent][:12],
        "labStanding": standing[:10],
        "forecastTrackRecord": site.get("trackRecord", {}).get("summary"),
    }


def rounded(value):
    """Rounds every float to 3 significant digits so Claude quotes $3.44, not $3.4375."""
    if isinstance(value, float):
        return float(f"{value:.3g}") if value else 0.0
    if isinstance(value, dict):
        return {k: rounded(v) for k, v in value.items()}
    if isinstance(value, list):
        return [rounded(v) for v in value]
    return value


NUMBER = re.compile(r"(?<![\w.])\$?(\d+(?:,\d{3})*(?:\.\d+)?)")


def numbers_in(text: str) -> set:
    return {float(m.group(1).replace(",", "")) for m in NUMBER.finditer(text)}


def allowed_numbers(facts: dict) -> set:
    """Every number in the fact sheet, plus the ways a writer might legitimately restate it:
    rounded, as a percentage, or (for minutes) in hours."""
    allowed = set(range(0, 11))  # small counts ("two or three", "3 months")
    for v in numbers_in(json.dumps(facts, ensure_ascii=False)):
        for x in (v, v * 100, v / 60):
            allowed.add(x)
            for d in range(0, 3):
                allowed.add(round(x, d))
            if x >= 1:
                allowed.add(float(f"{x:.2g}"))
                allowed.add(float(math.floor(x)))
    return allowed


def unsupported_numbers(written: dict, facts: dict) -> list:
    """Numbers in Claude's headline or outlook that don't come from the fact sheet."""
    allowed = allowed_numbers(facts)
    text = written.get("headline", "") + " " + written.get("outlook", "")
    return sorted(n for n in numbers_in(text) if not any(abs(n - a) <= 1e-9 * max(1, abs(a)) for a in allowed))


def keep_previous(previous: str | None, out: str, reason: str) -> None:
    print(f"::warning::Claude outlook not updated: {reason}")
    if previous and os.path.exists(previous):
        shutil.copyfile(previous, out)
        print(f"Kept the previous outlook from {previous}")
    else:
        print("No previous outlook; the site will show only the computed outlook")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--site", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--previous")
    p.add_argument("--dry-run", action="store_true", help="print the fact sheet and exit without calling Claude")
    args = p.parse_args()

    with open(args.site) as f:
        site = json.load(f)
    facts = rounded(fact_sheet(site))
    prompt = ("Here is today's fact sheet from AI Advances, as JSON. Write today's outlook.\n\n"
              + json.dumps(facts, indent=1, ensure_ascii=False))

    if args.dry_run:
        print(prompt)
        print(f"\n[{len(prompt):,} characters]")
        return 0
    if not os.environ.get("ANTHROPIC_API_KEY"):
        keep_previous(args.previous, args.out, "ANTHROPIC_API_KEY is not set")
        return 0

    import anthropic

    client = anthropic.Anthropic()
    messages = [{"role": "user", "content": prompt}]
    written = None
    # One attempt, plus one retry if the text quotes numbers that aren't in the fact sheet.
    for attempt in range(2):
        try:
            response = client.beta.messages.create(
                model=MODEL,
                max_tokens=16000,
                system=SYSTEM,
                messages=messages,
                output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
                # On a safety decline, re-run on Anthropic's recommended fallback model.
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
            )
        except anthropic.AuthenticationError:
            keep_previous(args.previous, args.out, "the API key was rejected")
            return 0
        except anthropic.RateLimitError:
            keep_previous(args.previous, args.out, "rate limited")
            return 0
        except anthropic.APIStatusError as e:
            keep_previous(args.previous, args.out, f"API error {e.status_code}: {e.message}")
            return 0
        except anthropic.APIConnectionError:
            keep_previous(args.previous, args.out, "couldn't reach the API")
            return 0

        if response.stop_reason == "refusal":
            category = response.stop_details.category if response.stop_details else None
            keep_previous(args.previous, args.out, f"declined (category: {category})")
            return 0
        if response.stop_reason == "max_tokens":
            keep_previous(args.previous, args.out, "response was cut off")
            return 0

        text = next((b.text for b in response.content if b.type == "text"), None)
        try:
            written = json.loads(text)
        except (TypeError, json.JSONDecodeError):
            keep_previous(args.previous, args.out, "response wasn't valid JSON")
            return 0

        bad = unsupported_numbers(written, facts)
        if not bad:
            break
        print(f"Attempt {attempt + 1} quoted numbers not in the fact sheet: {bad}")
        if attempt == 1:
            keep_previous(args.previous, args.out, f"the outlook quoted numbers not in the fact sheet: {bad}")
            return 0
        messages += [
            {"role": "assistant", "content": response.content},
            {"role": "user", "content": "These numbers in your outlook aren't in the fact sheet: "
                + ", ".join(f"{n:g}" for n in bad)
                + ". Rewrite it using only numbers that appear in the fact sheet (rounding is fine)."},
        ]

    result = {
        "generatedAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "dataThrough": site.get("latestDataDate"),
        "model": response.model,
        "headline": written["headline"].strip(),
        "outlook": written["outlook"].strip(),
        "requestId": response._request_id,
    }
    with open(args.out, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print(f"Wrote {args.out} with {response.model} "
          f"({response.usage.input_tokens} in / {response.usage.output_tokens} out tokens, request {response._request_id})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
