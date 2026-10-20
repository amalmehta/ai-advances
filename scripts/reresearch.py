"""Monthly re-research of the hand-curated content (lab focus notes and highlights).

Claude Opus 5.5 searches the web for each lab's latest news and for new highlights since the last
one, and returns updated entries. Every entry must cite sources that actually appeared in that
call's search or fetch results; anything that doesn't validate is dropped and the old entry kept.
The workflow then opens a pull request with the changes for a person to review; nothing merges
automatically.

    python3 scripts/reresearch.py [--labs "OpenAI,Anthropic"] [--skip-labs] [--skip-highlights] [--dry-run]

Needs ANTHROPIC_API_KEY (unless --dry-run). Writes AI Advances/Resources/Labs.json and
Advances.json in place, and a summary of changes to reresearch-summary.md.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys

MODEL = "claude-opus-5-5"
RESOURCES = "AI Advances/Resources"
DIRECTIONS = {"Reasoning", "Coding", "Agents", "Multimodal", "Efficiency", "Openness", "Scale"}
FOCUS_TAGS = {"Reasoning", "Coding", "Agents", "Multimodal", "Science", "Robotics", "Open weights",
              "Efficiency", "Consumer", "Enterprise", "Infrastructure", "Safety"}
TOOLS = [
    {"type": "web_search_20260209", "name": "web_search", "max_uses": 8},
    {"type": "web_fetch_20260209", "name": "web_fetch", "max_uses": 6},
]

SYSTEM = """You research the AI industry for AI Advances, a site that tracks where AI is heading. \
Use web search and fetch to verify everything. Only state facts you confirmed on a page you \
loaded; never guess dates, names or numbers. Prefer the lab's own announcement pages, then \
reputable outlets; avoid aggregators, index pages and Wikipedia when a primary source exists. \
Write in your own words, plainly, for a technically literate reader; explain any tier or \
product name a newcomer wouldn't know. When you're done, reply with only the JSON requested, \
inside <json></json> tags."""


def words(s: str) -> int:
    return len(s.split())


def cited_urls(content) -> set[str]:
    """URLs that appeared in this response's web search and fetch results."""
    urls: set[str] = set()
    for block in content:
        t = getattr(block, "type", "")
        if t == "web_search_tool_result" and isinstance(block.content, list):
            urls.update(r.url for r in block.content if getattr(r, "url", None))
        elif t == "web_fetch_tool_result" and getattr(block.content, "url", None):
            urls.add(block.content.url)
        elif t == "text":
            for c in getattr(block, "citations", None) or []:
                if getattr(c, "url", None):
                    urls.add(c.url)
    return urls


def norm(url: str) -> str:
    return url.split("#")[0].rstrip("/").lower()


def ask(client, prompt: str) -> tuple[dict | list | None, set[str], str]:
    """One research task: runs the search loop to completion and returns (parsed JSON, seen URLs, error)."""
    import anthropic

    messages = [{"role": "user", "content": prompt}]
    seen: set[str] = set()
    for _ in range(6):  # pause_turn continuations
        try:
            with client.beta.messages.stream(
                model=MODEL, max_tokens=32000, system=SYSTEM, messages=messages, tools=TOOLS,
                output_config={"effort": "medium"},
                betas=["server-side-fallback-2026-07-01"], fallbacks="default",
            ) as stream:
                response = stream.get_final_message()
        except anthropic.APIStatusError as e:
            return None, seen, f"API error {e.status_code}: {e.message}"
        except anthropic.APIConnectionError:
            return None, seen, "couldn't reach the API"
        except Exception as e:  # never let one task stop the others
            return None, seen, f"{type(e).__name__}: {e}"
        seen |= cited_urls(response.content)
        if response.stop_reason == "pause_turn":
            messages += [{"role": "assistant", "content": response.content}]
            continue
        if response.stop_reason == "refusal":
            return None, seen, "declined"
        text = "".join(b.text for b in response.content if getattr(b, "type", "") == "text")
        m = re.search(r"<json>(.*?)</json>", text, re.S)
        if not m:
            return None, seen, "no <json> block in the reply"
        try:
            return json.loads(m.group(1)), seen, ""
        except json.JSONDecodeError as e:
            return None, seen, f"invalid JSON: {e}"
    return None, seen, "too many continuations"


def valid_sources(sources: list, seen: set[str]) -> list[str]:
    seen_n = {norm(u) for u in seen}
    return [s for s in sources if isinstance(s, str) and s.startswith("https://") and norm(s) in seen_n]


def check_lab(note: dict, name: str, seen: set[str], today: str) -> tuple[dict | None, str]:
    try:
        assert note["name"] == name, "name changed"
        focus = [f for f in note["focus"] if f in FOCUS_TAGS]
        assert 2 <= len(focus) <= 4, "focus tags"
        assert words(note["summary"]) <= 70, "summary too long"
        bets = [b for b in note["bets"] if isinstance(b, str) and words(b) <= 22][:4]
        assert len(bets) >= 2, "too few bets"
        sources = valid_sources(note["sources"], seen)[:4]
        assert len(sources) >= 2, f"only {len(sources)} sources appeared in the search results"
        flagships = [f for f in note["flagships"] if isinstance(f, str)][:5]
        assert flagships, "no flagships"
    except (KeyError, TypeError, AssertionError) as e:
        return None, str(e)
    return {"name": name, "focus": focus, "summary": note["summary"].strip(), "bets": bets,
            "flagships": flagships, "sources": sources, "asOf": today}, ""


def check_highlight(h: dict, seen: set[str], after: str, today: str) -> tuple[dict | None, str]:
    try:
        date = dt.date.fromisoformat(h["date"]).isoformat()
        assert after < date <= today, f"date {date} outside {after}..{today}"
        assert h["direction"] in DIRECTIONS, "direction"
        assert words(h["summary"]) <= 35 and words(h["title"]) <= 14, "too long"
        sources = valid_sources([h["source"]], seen)
        assert sources, "source didn't appear in the search results"
    except (KeyError, TypeError, ValueError, AssertionError) as e:
        return None, str(e)
    return {"date": date, "datePrecision": "day", "title": h["title"].strip(), "lab": h["lab"].strip(),
            "category": h.get("category", h["direction"]), "direction": h["direction"],
            "summary": h["summary"].strip(), "source": sources[0]}, ""


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--labs", help="comma-separated lab names (default: all)")
    p.add_argument("--skip-labs", action="store_true")
    p.add_argument("--skip-highlights", action="store_true")
    p.add_argument("--dry-run", action="store_true", help="print the prompts and exit")
    p.add_argument("--today", default=dt.date.today().isoformat())
    args = p.parse_args()

    labs = json.load(open(f"{RESOURCES}/Labs.json"))
    advances = json.load(open(f"{RESOURCES}/Advances.json"))
    wanted = set(args.labs.split(",")) if args.labs else {l["name"] for l in labs}
    last = max(a["date"] for a in advances)

    lab_prompts = {l["name"]: (
        f"Today is {args.today}. Here is our note on {l['name']}, last researched {l['asOf']}:\n\n"
        f"{json.dumps(l, indent=1, ensure_ascii=False)}\n\n"
        "Research what has changed since then: new flagship models, shifts in focus, announced plans. "
        "Return the updated note with exactly the same fields. name stays the same; focus has 2-4 tags from "
        f"{sorted(FOCUS_TAGS)}; summary ≤ 60 words; 2-4 bets ≤ 18 words each; flagships are current model "
        "names; sources are 2-4 URLs of pages you loaded that support the note. If nothing changed, return "
        "the note as is with sources you re-verified.") for l in labs if l["name"] in wanted}
    highlight_prompt = (
        f"Today is {args.today}. Find the 3-8 most notable AI advances between {last} and {args.today} "
        "(exclusive of the start): major model releases, benchmark records, notable open-weight releases, "
        "big price or capability shifts, important research results. Return a JSON array of objects with "
        "date (YYYY-MM-DD), title (≤ 12 words), lab, direction (one of "
        f"{sorted(DIRECTIONS)}), summary (≤ 30 words) and source (the URL of the page you loaded that "
        "supports it). Newest first. Return [] if you can't verify any.")

    if args.dry_run:
        for name, prompt in lab_prompts.items():
            print(f"--- {name}\n{prompt[:400]}…\n")
        print(f"--- highlights\n{highlight_prompt}")
        return 0
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("ANTHROPIC_API_KEY is not set", file=sys.stderr)
        return 1

    import anthropic
    client = anthropic.Anthropic()
    summary = [f"# Re-research {args.today}\n"]

    if not args.skip_labs:
        summary.append("## Lab notes\n")
        for i, l in enumerate(labs):
            if l["name"] not in wanted:
                continue
            note, seen, err = ask(client, lab_prompts[l["name"]])
            new, why = check_lab(note, l["name"], seen, args.today) if isinstance(note, dict) else (None, err)
            if new:
                changed = {k for k in ("focus", "summary", "bets", "flagships") if new[k] != l[k]}
                labs[i] = new
                summary.append(f"- **{l['name']}**: " + (f"updated {', '.join(sorted(changed))}" if changed else "re-verified, no change")
                               + "; sources: " + ", ".join(new["sources"]))
            else:
                summary.append(f"- **{l['name']}**: kept the old note ({why})")
            print(summary[-1], flush=True)
        json.dump(labs, open(f"{RESOURCES}/Labs.json", "w"), indent=2, ensure_ascii=False)

    if not args.skip_highlights:
        summary.append("\n## New highlights\n")
        found, seen, err = ask(client, highlight_prompt)
        added = 0
        for h in found if isinstance(found, list) else []:
            new, why = check_highlight(h, seen, last, args.today)
            if new and not any(a["title"] == new["title"] for a in advances):
                advances.append(new)
                added += 1
                summary.append(f"- {new['date']} **{new['title']}** ({new['lab']}): {new['source']}")
            elif not new:
                summary.append(f"- dropped \"{h.get('title', '?')}\": {why}")
        if err:
            summary.append(f"- highlight search failed: {err}")
        advances.sort(key=lambda a: a["date"], reverse=True)
        json.dump(advances, open(f"{RESOURCES}/Advances.json", "w"), indent=2, ensure_ascii=False)
        print(f"Added {added} highlights", flush=True)

    open("reresearch-summary.md", "w").write("\n".join(summary) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
