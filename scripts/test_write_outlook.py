"""Offline checks for write_outlook.py (no API calls): python3 scripts/test_write_outlook.py site/data/site.json"""

import json
import sys

sys.path.insert(0, "scripts")
import write_outlook as w  # noqa: E402

site = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "site/data/site.json"))
facts = w.rounded(w.fact_sheet(site))
tiles = facts["headlineTrends"]

# Rounding: every figure reaching Claude has at most 3 significant digits ($0.0512 is fine; $0.05123 isn't).
assert all(float(f"{v:.3g}") == v for v in tiles.values() if isinstance(v, float)), tiles
assert w.rounded(0.051234) == 0.0512 and w.rounded(3.4375) == 3.44 and w.rounded(1044.78) == 1040.0

# Restating fact-sheet numbers is fine: rounded, as a percentage, minutes as hours.
months = round(tiles["horizonDoublingMonths"], 1)
hours = round(tiles["horizonMinutes"] / 60, 1)
ok = {"headline": "Steady progress", "outlook": f"Task length doubles every {months} months, now {hours} hours; "
      f"the cheapest GPQA-80% model costs ${tiles['priceNow']} per million tokens."}
assert w.unsupported_numbers(ok, facts) == [], w.unsupported_numbers(ok, facts)

# Invented numbers are caught.
bad = {"headline": "A 73.2% leap", "outlook": "Compute will reach 1,234 exaflops by 2031."}
found = w.unsupported_numbers(bad, facts)
assert 73.2 in found and 1234 in found, found

print("write_outlook checks passed")
