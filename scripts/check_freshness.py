"""Open a GitHub issue when the hand-researched content (lab notes, highlights) is more than
45 days old, and close it once the content has been refreshed. Run by the daily website build.

    python3 scripts/check_freshness.py [--today YYYY-MM-DD] [--dry-run]

Needs the gh CLI with GH_TOKEN set (unless --dry-run).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys

sys.path.insert(0, "scripts")
import github_issue  # noqa: E402

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

    if stale:
        lines = "\n".join(f"- **{k}**: last updated {w}, {d} days ago" for k, (w, d) in stale.items())
        github_issue.upsert(TITLE, f"The website and app flag these as possibly out of date (more than {STALE_AFTER_DAYS} days old):\n\n{lines}\n\n"
                            "Everything data-driven is still updating daily. To refresh, run the *Re-research content* workflow or edit the files "
                            "(see docs/GUIDE.md, \"Refreshing the lab notes\"); this issue closes itself on the next daily build after they're updated.")
    else:
        github_issue.close(TITLE, "The researched content has been refreshed, so this is resolved.")

if __name__ == "__main__":
    main()
