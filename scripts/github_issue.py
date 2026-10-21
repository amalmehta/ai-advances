"""Open, update or close one GitHub issue by title, so automated alerts never pile up duplicates.
Needs the gh CLI with GH_TOKEN (and GH_REPO outside a checkout)."""

from __future__ import annotations

import json
import subprocess


def _gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def find_open(title: str) -> int | None:
    issues = json.loads(_gh("issue", "list", "--state", "open", "--search", f'"{title}" in:title', "--json", "number,title"))
    return next((i["number"] for i in issues if i["title"] == title), None)


def upsert(title: str, body: str) -> None:
    """Create the issue, or replace the body of the open one with the same title."""
    existing = find_open(title)
    if existing:
        _gh("issue", "edit", str(existing), "--body", body)
        print(f"Updated issue #{existing}: {title}")
    else:
        print(_gh("issue", "create", "--title", title, "--body", body).strip())


def close(title: str, comment: str) -> None:
    existing = find_open(title)
    if existing:
        _gh("issue", "close", str(existing), "--comment", comment)
        print(f"Closed issue #{existing}: {title}")
