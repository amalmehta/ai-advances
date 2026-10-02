"""Open a GitHub issue when the hand-researched content (lab notes, highlights) is more than
45 days old, and close it once the content has been refreshed. Run by the daily website build.

    python3 scripts/check_freshness.py [--today YYYY-MM-DD] [--dry-run]

Needs the gh CLI with GH_TOKEN set (unless --dry-run).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess

STALE_AFTER_DAYS = 45
TITLE = "Researched content is out of date"
RESOURCES = "AI Advances/Resources"


def ages(today: dt.date) -> dict:
    labs = json.load(open(f"{RESOURCES}/Labs.json"))
    advances = json.load(open(f"{RESOURCES}/Advances.json"))
    notes = min(dt.date.fromisoformat(l["asOf"]) for l in labs)
    highlights = max(dt.date.fromisoformat(a["date"]) for a in advances)
    return {
        "Lab focus notes (Labs.json)": (notes, (today - notes).days),
        "Highlights (Advances.json)": (highlights, (today - highlights).days),
    }


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--today", type=dt.date.fromisoformat, default=dt.date.today())
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    found = ages(args.today)
    stale = {k: v for k, v in found.items() if v[1] > STALE_AFTER_DAYS}
    for name, (when, days) in found.items():
        print(f"{name}: {when} ({days} days old){' - STALE' if name in stale else ''}")

    if args.dry_run:
        print("Dry run: would", "open or update the issue" if stale else "close any open issue")
        return

    open_issues = json.loads(gh("issue", "list", "--state", "open", "--search", f'"{TITLE}" in:title', "--json", "number,title"))
    existing = next((i["number"] for i in open_issues if i["title"] == TITLE), None)

    if stale:
        lines = "\n".join(f"- **{k}**: last updated {w}, {d} days ago" for k, (w, d) in stale.items())
        body = (f"The website and app flag these as possibly out of date (more than {STALE_AFTER_DAYS} days old):\n\n{lines}\n\n"
                "Everything data-driven is still updating daily. To refresh, re-research the files above "
                "(see docs/GUIDE.md, \"Refreshing the lab notes\"); this issue closes itself on the next "
                "daily build after they're updated.")
        if existing:
            gh("issue", "edit", str(existing), "--body", body)
            print(f"Updated issue #{existing}")
        else:
            print(gh("issue", "create", "--title", TITLE, "--body", body).strip())
    elif existing:
        gh("issue", "close", str(existing), "--comment", "The researched content has been refreshed, so this is resolved.")
        print(f"Closed issue #{existing}")


if __name__ == "__main__":
    main()
