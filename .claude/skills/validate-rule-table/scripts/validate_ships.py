#!/usr/bin/env python3
# Validate data/rules/ships.json (loaded by scripts/autoload/data_manager.gd): the 41
# Ship Data Chart rows (SDC, 1997 Close Action p.106) and the four order-of-battle ships.
# Catches transcription slips and stale keys: wrong id set, leftover keys, hit-point
# rows that decrease, point-cost columns out of order, carronade twins that drifted
# apart, bad aliases.
#
# Usage: python3 .claude/skills/validate-rule-table/scripts/validate_ships.py [--file PATH] [--rules-dir DIR]
# Exit status 1 on any error.

import argparse
import json
import re
import sys
from pathlib import Path

SDC_IDS = [
    "br_100", "br_98l", "br_98", "br_80", "br_74l", "br_74c", "br_74", "br_64c", "br_64",
    "br_50", "br_44rz", "br_40", "br_38", "br_36", "br_32l", "br_32",
    "fr_120", "fr_110", "fr_80c", "fr_80", "fr_74l", "fr_74c", "fr_74", "fr_50rz", "fr_44",
    "fr_40c", "fr_40", "fr_38", "fr_36",
    "sp_130", "sp_112", "sp_80l", "sp_80", "sp_74", "sp_64", "sp_40", "sp_34",
    "am_44", "am_38", "am_36", "am_32",
]
OB_IDS = ["br_44_diomede", "fr_20_babet", "fr_20_rosalie", "fr_14_coureur"]
EXPECTED_IDS = SDC_IDS + OB_IDS

ALLOWED_KEYS = [
    "name", "nationality", "rating", "year", "class", "maneuverability", "speed_type", "draft",
    "ch_modifier", "rigging_hp", "hull_hp", "crew_count", "marine_count", "gun_factors",
    "freeboard", "lower_deck_modifier", "point_costs",
]
OPTIONAL_KEYS = ["aliases", "armament"]
NATIONS = {"br": "British", "fr": "French", "sp": "Spanish", "am": "American"}
COST_COLUMNS = ["A3", "B3", "C3", "C4", "C5", "D4", "D5", "E4", "E5"]
OB_COST_RE = re.compile(r"^[A-G][2-6]$")
TWINS = [("br_74c", "br_74"), ("br_64c", "br_64"), ("fr_80c", "fr_80"), ("fr_74c", "fr_74"),
         ("fr_40c", "fr_40")]
TWIN_FIELDS = ["class", "maneuverability", "speed_type", "draft", "ch_modifier", "rigging_hp",
               "hull_hp", "crew_count", "marine_count", "freeboard", "lower_deck_modifier"]
EXPECTED_ALIASES = {"frigate_38": "br_38", "frigate_32": "br_32", "ship_of_line_74": "br_74"}


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


class Report:
    def __init__(self):
        self.errors = []

    def err(self, ship_id, msg):
        self.errors.append("%s: %s" % (ship_id, msg))


def int_in(rep, sid, row, key, lo, hi):
    v = row.get(key)
    if not is_int(v) or not lo <= v <= hi:
        rep.err(sid, "%s must be an int %d..%d, got %r" % (key, lo, hi, v))


def four_ints(rep, sid, row, key):
    v = row.get(key)
    if not (isinstance(v, list) and len(v) == 4 and all(is_int(x) and x >= 1 for x in v)):
        rep.err(sid, "%s must be four ints >= 1, got %r" % (key, v))
    elif any(v[i] > v[i + 1] for i in range(3)):
        rep.err(sid, "%s must be non-decreasing, got %r" % (key, v))


def check_row(rep, sid, row, movement_keys):
    ob = sid in OB_IDS
    keys = set(row.keys())
    for k in sorted(keys - set(ALLOWED_KEYS) - set(OPTIONAL_KEYS)):
        rep.err(sid, "unexpected key '%s'" % k)
    for k in ALLOWED_KEYS:
        if k not in keys:
            rep.err(sid, "missing key '%s'" % k)
    if NATIONS.get(sid[:2]) != row.get("nationality"):
        rep.err(sid, "nationality %r does not match the id prefix" % row.get("nationality"))
    if not (isinstance(row.get("name"), str) and row["name"].strip()):
        rep.err(sid, "name must be a non-empty string")
    int_in(rep, sid, row, "rating", 10, 140)
    int_in(rep, sid, row, "year", 1780, 1815)
    int_in(rep, sid, row, "class", 1, 4 if ob else 3)
    if row.get("maneuverability") not in ("A", "B", "C", "D"):
        rep.err(sid, "maneuverability must be A, B, C or D, got %r" % row.get("maneuverability"))
    if row.get("speed_type") not in movement_keys:
        rep.err(sid, "speed_type %r is not a movement_allowance.json key" % row.get("speed_type"))
    int_in(rep, sid, row, "draft", 10, 30)
    int_in(rep, sid, row, "ch_modifier", -4, 1)
    for k in ("rigging_hp", "hull_hp", "crew_count"):
        four_ints(rep, sid, row, k)
    if not is_int(row.get("marine_count")) or row["marine_count"] < 1:
        rep.err(sid, "marine_count must be an int >= 1, got %r" % row.get("marine_count"))
    gf = row.get("gun_factors")
    if not (isinstance(gf, dict) and set(gf) == {"lg", "mg", "cr"}
            and all(is_int(v) and v >= 0 for v in gf.values())):
        rep.err(sid, "gun_factors must be exactly lg, mg, cr ints >= 0, got %r" % gf)
    else:
        if sum(gf.values()) <= 0:
            rep.err(sid, "gun_factors sum must be > 0")
        if gf["mg"] > 0 and sid != "br_44_diomede":
            rep.err(sid, "only br_44_diomede has medium guns, got mg %d" % gf["mg"])
    int_in(rep, sid, row, "freeboard", 1, 6)
    int_in(rep, sid, row, "lower_deck_modifier", -8, -1)
    costs = row.get("point_costs")
    if not (isinstance(costs, dict) and costs and all(is_int(v) and v > 0 for v in costs.values())):
        rep.err(sid, "point_costs must be a non-empty dict of positive ints, got %r" % costs)
    elif ob:
        if len(costs) != 1 or not OB_COST_RE.match(next(iter(costs))):
            rep.err(sid, "OB point_costs must be exactly one key like D4, got %r" % costs)
    else:
        bad = [k for k in costs if k not in COST_COLUMNS]
        if bad:
            rep.err(sid, "point_costs has unknown columns %s" % bad)
        else:
            vals = [costs[c] for c in COST_COLUMNS if c in costs]
            if any(vals[i] <= vals[i + 1] for i in range(len(vals) - 1)):
                rep.err(sid, "point_costs must strictly decrease in column order, got %r" % costs)


def validate(ships, movement_keys):
    rep = Report()
    ids = [k for k in ships if not k.startswith("_")]
    for sid in EXPECTED_IDS:
        if sid not in ids:
            rep.err(sid, "missing ship type")
    for sid in ids:
        if sid not in EXPECTED_IDS:
            rep.err(sid, "unexpected ship type")
    for sid in ids:
        if sid in EXPECTED_IDS and isinstance(ships[sid], dict):
            check_row(rep, sid, ships[sid], movement_keys)
        elif sid in EXPECTED_IDS:
            rep.err(sid, "row is not an object")
    for a, b in TWINS:
        if a in ships and b in ships and isinstance(ships[a], dict) and isinstance(ships[b], dict):
            for f in TWIN_FIELDS:
                if ships[a].get(f) != ships[b].get(f):
                    rep.err(a, "twin mismatch with %s on %s: %r vs %r" % (b, f, ships[a].get(f), ships[b].get(f)))
    aliases = {}
    for sid in ids:
        row = ships[sid]
        if isinstance(row, dict):
            for al in row.get("aliases", []):
                aliases[al] = sid
    if aliases != EXPECTED_ALIASES:
        rep.err("aliases", "expected %r, got %r" % (EXPECTED_ALIASES, aliases))
    return rep, len(ids)


def main():
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parents[4]
    ap.add_argument("--rules-dir", default=str(root / "data" / "rules"))
    ap.add_argument("--file", default=None)
    args = ap.parse_args()
    rules = Path(args.rules_dir)
    path = Path(args.file) if args.file else rules / "ships.json"
    ships = json.loads(path.read_text())
    movement = json.loads((rules / "movement_allowance.json").read_text())
    rep, count = validate(ships, set(movement.keys()))
    if rep.errors:
        for e in rep.errors:
            print("ERROR:", e)
        sys.exit(1)
    print("OK: %d ship types" % count)


if __name__ == "__main__":
    main()
