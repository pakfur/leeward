#!/usr/bin/env python3
# Validate the 1997 combat-table JSON files in data/rules/ (loaded by
# scripts/autoload/combat_tables.gd). Catches transcription slips that would
# silently skew combat: wrong row counts, gaps in TGF bands, BGN values out of
# order, malformed gunfire result strings, unexpected damage dips.
#
# Usage: python3 .claude/skills/validate-rule-table/scripts/validate_combat.py [--rules-dir DIR]
# Exit status 1 on any error.

import argparse
import json
import re
import sys
from pathlib import Path

RANGES = 15
FRENCH_RANGES = 5          # ranges 11-15
BGN_ROWS = 21              # printed TGF bands: 1..12, 13-14, ..., 28-30, 31+
RESULT_ROWS = 52
RESULT_COLUMNS = ("fs", "ms", "ps")
AIMS = ("low", "high")
ALT_RE = re.compile(r"^(?:\.|([1-9][0-9]*)?[rhc])$")

# Places where the printed Gunfire Results chart itself gives less maximum
# damage than the row above (checked against the 1997 chart, p.110). Keyed
# (aim, sail state, fgn of the lower row). Any dip NOT listed here is an error.
# Sail state "ms" = fs + ms columns, "ps" = fs + ms + ps columns.
KNOWN_CHART_DIPS = {
    *(('low', 'fs', f) for f in [4, 6]),
    *(('low', 'ms', f) for f in [4, 6, 10, 16, 22, 25, 28, 31]),
    *(('low', 'ps', f) for f in [4, 6, 8, 10, 14, 16, 22, 48]),
    *(('high', 'fs', f) for f in [4, 6, 8]),
    *(('high', 'ms', f) for f in [4, 8, 13, 20, 26]),
    *(('high', 'ps', f) for f in [4, 8, 10, 13, 16, 20, 23, 26, 31]),
}


class Report:
    def __init__(self):
        self.errors = []

    def err(self, path, msg):
        self.errors.append(f"  {path}: {msg}")


def load(rules_dir, name, report):
    path = rules_dir / name
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        report.err(name, f"cannot load: {e}")
        return None
    if not isinstance(data, dict):
        report.err(name, "top level must be an object")
        return None
    return data


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def check_gunnery_factor(t, r):
    name = "gunnery_factor_table.json"
    for gun in ("lg", "mg", "cr"):
        arr = t.get(gun)
        if not isinstance(arr, list) or len(arr) != RANGES:
            r.err(f"{name}.{gun}", f"must be a {RANGES}-entry array")
            continue
        if not all(is_num(v) and v >= 0 for v in arr):
            r.err(f"{name}.{gun}", "entries must be non-negative numbers")
            continue
        if any(arr[i] < arr[i + 1] for i in range(RANGES - 1)):
            r.err(f"{name}.{gun}", "multiplier must not increase with range")


def check_non_increasing(values, path, r):
    seen_null = False
    prev = None
    for i, v in enumerate(values):
        if v is None:
            seen_null = True
            continue
        if seen_null:
            r.err(path, f"number after a grey (null) box at index {i}")
        if not isinstance(v, int) or isinstance(v, bool) or v < 0:
            r.err(path, f"index {i}: {v!r} is not a non-negative int")
            return
        if prev is not None and v > prev:
            r.err(path, f"index {i}: {v} > previous {prev} (must not increase with range)")
        prev = v


def check_bgn(t, r):
    name = "basic_gunfire_number_table.json"
    rows = t.get("rows")
    if not isinstance(rows, list):
        r.err(name, "missing rows array")
        return
    if len(rows) != BGN_ROWS:
        r.err(name, f"{len(rows)} rows, expected {BGN_ROWS}")
    expected_min = 1
    for i, row in enumerate(rows):
        p = f"{name}.rows[{i}]"
        lo, hi = row.get("tgf_min"), row.get("tgf_max")
        if lo != expected_min:
            r.err(p, f"tgf_min {lo} leaves a gap/overlap (expected {expected_min})")
        if not isinstance(hi, int) or not isinstance(lo, int) or hi < lo:
            r.err(p, f"bad tgf range {lo}..{hi}")
            return
        expected_min = hi + 1
        bgn, french = row.get("bgn"), row.get("french")
        if not isinstance(bgn, list) or len(bgn) != RANGES:
            r.err(p, f"bgn must have {RANGES} entries")
            continue
        if not isinstance(french, list) or len(french) != FRENCH_RANGES:
            r.err(p, f"french must have {FRENCH_RANGES} entries")
            continue
        check_non_increasing(bgn, p + ".bgn", r)
        check_non_increasing(french, p + ".french", r)
        for j, fv in enumerate(french):
            nv = bgn[RANGES - FRENCH_RANGES + j]
            if (fv is None) != (nv is None):
                r.err(p, f"range {11 + j}: french/normal grey boxes disagree")
            elif fv is not None and fv < nv:
                r.err(p, f"range {11 + j}: french {fv} < normal {nv}")
    if rows and rows[-1].get("tgf_max") != 999:
        r.err(name, "last row must be 31+ (tgf_max 999)")
    for key, width in (("bgn", RANGES), ("french", FRENCH_RANGES)):
        for col in range(width):
            prev = None
            for i, row in enumerate(rows):
                vals = row.get(key)
                if not isinstance(vals, list) or len(vals) != width:
                    break
                v = vals[col]
                if v is None:
                    if prev is not None:
                        r.err(f"{name}.rows[{i}].{key}[{col}]", "grey box below a number")
                    continue
                if prev is not None and v < prev:
                    r.err(f"{name}.rows[{i}].{key}[{col}]", f"{v} < {prev} above (must not decrease with TGF)")
                prev = v


def parse_result(text):
    """Returns list of tokens (each a list of (type, count) or None), or raises ValueError."""
    if text == "":
        return []
    tokens = []
    for tok in text.split("-"):
        alts = tok.split("/")
        if len(alts) > 2:
            raise ValueError(f"token {tok!r} has more than two alternatives")
        parsed = []
        for alt in alts:
            if not ALT_RE.match(alt):
                raise ValueError(f"bad alternative {alt!r}")
            parsed.append(None if alt == "." else (alt[-1], int(alt[:-1] or 1)))
        if len(parsed) == 2 and parsed[0] is None and parsed[1] is None:
            raise ValueError(f"token {tok!r} is nothing-or-nothing")
        tokens.append(parsed)
    return tokens


def max_damage(tokens):
    return sum(max((a[1] if a else 0) for a in tok) for tok in tokens)


def check_results(t, r):
    name = "gunfire_results_table.json"
    rows = t.get("rows")
    if not isinstance(rows, list):
        r.err(name, "missing rows array")
        return
    if len(rows) != RESULT_ROWS:
        r.err(name, f"{len(rows)} rows, expected {RESULT_ROWS}")
    prev_ch = 0
    damage = {}  # (aim, state) -> list of max damage by row index
    for i, row in enumerate(rows):
        p = f"{name}.rows[{i}]"
        if row.get("fgn") != i + 1:
            r.err(p, f"fgn {row.get('fgn')} out of order (expected {i + 1})")
        ch = row.get("ch")
        if not isinstance(ch, int) or not 0 <= ch <= 6:
            r.err(p, f"ch {ch!r} must be an int 0..6")
        elif ch < prev_ch:
            r.err(p, f"ch {ch} < previous {prev_ch}")
        else:
            prev_ch = ch
        for aim in AIMS:
            cells = row.get(aim)
            if not isinstance(cells, dict) or set(cells) != set(RESULT_COLUMNS):
                r.err(f"{p}.{aim}", f"must have exactly columns {RESULT_COLUMNS}")
                continue
            running = 0
            for col in RESULT_COLUMNS:
                text = cells[col]
                if not isinstance(text, str):
                    r.err(f"{p}.{aim}.{col}", "must be a string")
                    continue
                try:
                    running += max_damage(parse_result(text))
                except ValueError as e:
                    r.err(f"{p}.{aim}.{col}", f"{text!r}: {e}")
                    continue
                damage.setdefault((aim, col), []).append(running)
    for (aim, state), series in sorted(damage.items()):
        if len(series) != len(rows):
            continue
        for i in range(1, len(series)):
            fgn = i + 1
            dip = series[i] < series[i - 1]
            known = (aim, state, fgn) in KNOWN_CHART_DIPS
            if dip and not known:
                r.err(f"{name} {aim}/{state}", f"fgn {fgn}: max damage {series[i]} < {series[i - 1]} at fgn {fgn - 1} (not a known chart dip)")
            elif known and not dip:
                r.err(f"{name} {aim}/{state}", f"fgn {fgn}: listed in KNOWN_CHART_DIPS but no dip; update the list")
    # Totals must rise across the table as a whole.
    for (aim, state), series in damage.items():
        if series and series[-1] <= series[0]:
            r.err(f"{name} {aim}/{state}", "row 52 does no more damage than row 1")


def check_modifiers(t, r):
    name = "gunfire_modifiers.json"
    if t.get("crew_quality") is None or sorted(t["crew_quality"]) != list("ABCDEFG"):
        r.err(name, "crew_quality must have keys A-G")
    else:
        vals = [t["crew_quality"][k] for k in "ABCDEFG"]
        if any(vals[i] <= vals[i + 1] for i in range(6)):
            r.err(name, "crew_quality must strictly decrease A..G")
    if sorted(t.get("sections_firing", {})) != ["1", "2", "3", "4"]:
        r.err(name, "sections_firing must have keys 1-4")
    for k in ("rake", "initial_broadside"):
        arr = t.get(k)
        if not isinstance(arr, list) or len(arr) != 5 or not all(isinstance(v, int) for v in arr):
            r.err(f"{name}.{k}", "must be 5 ints (ranges 1-5)")
    for k in ("two_targets", "plain_sail", "dismantling_shot", "anchored", "wind_speed_4"):
        if not isinstance(t.get(k), int):
            r.err(f"{name}.{k}", "missing or not an int")


def check_small_tables(tables, r):
    cl = tables["crew_loss_table.json"]
    if cl is not None:
        for cause in ("gunfire_at_hull", "other"):
            v = cl.get(cause, {}).get("sailor_max")
            if not isinstance(v, int) or not 0 <= v <= 6:
                r.err(f"crew_loss_table.json.{cause}", "sailor_max must be an int 0..6")
    dr = tables["drifting_table.json"]
    if dr is not None:
        for key in ("ps", "ms", "fs", "ns", "dismasted"):
            arr = dr.get(key)
            if not isinstance(arr, list) or len(arr) != 5:
                r.err(f"drifting_table.json.{key}", "must have 5 entries (wind speed 0-4)")
                continue
            nums = [v for v in arr if v is not None]
            if any(nums[i] < nums[i + 1] for i in range(len(nums) - 1)):
                r.err(f"drifting_table.json.{key}", "drift number must not increase with wind speed")
        if not isinstance(dr.get("class_drm"), dict):
            r.err("drifting_table.json", "class_drm must be an object")
    uf = tables["unfouling_table.json"]
    if uf is not None:
        arr = uf.get("success_max")
        if not isinstance(arr, list) or len(arr) != 3 or arr != sorted(arr):
            r.err("unfouling_table.json", "success_max must be 3 non-decreasing ints")
    cq = tables["crew_quality_table.json"]
    if cq is not None:
        letters = sorted(k for k in cq if k != "_doc")
        if letters != list("ABCDEFG"):
            r.err("crew_quality_table.json", "must have keys A-G")
        else:
            for k in letters:
                if set(cq[k]) != {"sk", "bcf_sailor", "bcf_marine"}:
                    r.err(f"crew_quality_table.json.{k}", "must have sk, bcf_sailor, bcf_marine")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    default_dir = Path(__file__).resolve().parents[4] / "data" / "rules"
    ap.add_argument("--rules-dir", type=Path, default=default_dir)
    args = ap.parse_args()

    r = Report()
    names = [
        "gunnery_factor_table.json", "basic_gunfire_number_table.json",
        "gunfire_results_table.json", "gunfire_modifiers.json",
        "crew_loss_table.json", "drifting_table.json",
        "unfouling_table.json", "crew_quality_table.json",
    ]
    tables = {n: load(args.rules_dir, n, r) for n in names}
    checks = {
        "gunnery_factor_table.json": check_gunnery_factor,
        "basic_gunfire_number_table.json": check_bgn,
        "gunfire_results_table.json": check_results,
        "gunfire_modifiers.json": check_modifiers,
    }
    for n, fn in checks.items():
        if tables[n] is not None:
            fn(tables[n], r)
    check_small_tables(tables, r)

    if r.errors:
        print(f"ERRORS ({len(r.errors)}):")
        for e in r.errors:
            print(e)
        sys.exit(1)
    print(f"OK: {len(names)} combat tables valid.")


if __name__ == "__main__":
    main()
