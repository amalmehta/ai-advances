"""After each daily build: raise (or clear) GitHub issues for problems that don't fail the build
but leave the site wrong, so they're seen instead of sitting in a log as warnings.

  - the Claude outlook is more than 36 hours behind the site's data (e.g. a rejected API key)
  - a data source couldn't be downloaded and the build fell back to the bundled snapshot

    python3 scripts/report_health.py <built site dir> [--dry-run]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys

sys.path.insert(0, "scripts")
import github_issue  # noqa: E402

OUTLOOK_TITLE = "Daily outlook is not updating"
SOURCES_TITLE = "Data sources fell back to the bundled snapshot"
OUTLOOK_MAX_LAG = dt.timedelta(hours=36)


def problems(site_dir: str, now: dt.datetime) -> dict[str, str | None]:
    site = json.load(open(os.path.join(site_dir, "data", "site.json")))
    found: dict[str, str | None] = {OUTLOOK_TITLE: None, SOURCES_TITLE: None}

    outlook_path = os.path.join(site_dir, "data", "outlook.json")
    if os.path.exists(outlook_path):
        written = dt.datetime.fromisoformat(json.load(open(outlook_path))["generatedAt"])
        if now - written > OUTLOOK_MAX_LAG:
            found[OUTLOOK_TITLE] = (
                f"The Claude-written outlook was last written {written:%b %d, %Y %H:%M} UTC, "
                f"{(now - written).days} days ago, so the site and app are showing an old outlook.\n\n"
                "Check the latest *Update website* run's \"Write Claude outlook\" step. The usual cause is a revoked or "
                "expired API key: replace the `NEW_SECRET` repository secret. This issue closes itself once a fresh outlook is written.")

    fell_back = site.get("sourcesFellBack") or []
    if fell_back:
        found[SOURCES_TITLE] = (
            "Today's build couldn't download or validate: " + ", ".join(f"`{f}`" for f in fell_back) +
            ". It used the snapshot bundled in the repo instead, so parts of the site show older data, and today's "
            "forecasts weren't logged. Usually temporary; this issue closes itself when all sources download again.")
    return found


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("site_dir")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--now", help="ISO time, for testing")
    args = p.parse_args()
    now = dt.datetime.fromisoformat(args.now) if args.now else dt.datetime.now(dt.timezone.utc)
    for title, body in problems(args.site_dir, now).items():
        if args.dry_run:
            print(f"{'PROBLEM' if body else 'ok     '} {title}" + (f": {body[:90]}…" if body else ""))
        elif body:
            github_issue.upsert(title, body)
        else:
            github_issue.close(title, "Resolved: the latest build no longer has this problem.")


if __name__ == "__main__":
    main()
