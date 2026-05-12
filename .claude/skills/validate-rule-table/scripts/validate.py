#!/usr/bin/env python3
# Validate data/rules/movement_allowance.json against the project's 5-level
# lookup schema. Fails fast on errors (wrong keys, bad types) and warns on
# coverage gaps that would silently return 0 at lookup time.

import argparse
import json
import sys
from pathlib import Path

EXPECTED_SPEED_TYPES = {
    "L/F", "L/S", "L/VS",
    "F/F", "F/S", "F/VS",
    "C/F", "C/S", "C/VS",
}
# Wind facings: C=close-hauled, B=broad reach, R=reach. "L" (luffing) is
# intentionally absent from the table — DataManager.get_movement_allowance()
# returns 0 for "L" without consulting the table.
EXPECTED_FACINGS = {"C", "B", "R"}
VALID_WIND_SPEEDS = {"1", "2", "3", "4"}
VALID_RIGGING_QUALITIES = {"1", "2", "3", "4"}
VALID_SAIL_STATES = {"fs", "ms", "ps", "ns"}


class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def err(self, path, msg):
        self.errors.append(f"  {path}: {msg}")

    def warn(self, path, msg):
        self.warnings.append(f"  {path}: {msg}")

    def print(self):
        if self.errors:
            print(f"\nERRORS ({len(self.errors)}):")
            for e in self.errors:
                print(e)
        if self.warnings:
            print(f"\nWARNINGS ({len(self.warnings)}):")
            for w in self.warnings:
                print(w)
        if not self.errors and not self.warnings:
            print("OK: no errors, no warnings.")
        elif not self.errors:
            print(f"\nOK with {len(self.warnings)} warning(s).")


def validate_movement_allowance(table, report):
    if not isinstance(table, dict):
        report.err("<root>", f"expected object, got {type(table).__name__}")
        return

    # Top level: speed types
    extra = set(table.keys()) - EXPECTED_SPEED_TYPES
    missing = EXPECTED_SPEED_TYPES - set(table.keys())
    for st in sorted(extra):
        report.err(st, "unknown speed_type (not in expected set)")
    for st in sorted(missing):
        report.err(st, "missing speed_type")

    for speed_type, facings in table.items():
        if speed_type not in EXPECTED_SPEED_TYPES:
            continue  # already reported
        if not isinstance(facings, dict):
            report.err(speed_type, f"expected object, got {type(facings).__name__}")
            continue
        _validate_facings(speed_type, facings, report)


def _validate_facings(speed_type, facings, report):
    extra = set(facings.keys()) - EXPECTED_FACINGS
    missing = EXPECTED_FACINGS - set(facings.keys())
    for f in sorted(extra):
        path = f"{speed_type}.{f}"
        if f == "L":
            report.err(path, "wind_facing 'L' must not appear in the table — "
                             "DataManager handles luffing specially. Remove it.")
        else:
            report.err(path, "unknown wind_facing (expected one of C, B, R)")
    for f in sorted(missing):
        report.err(f"{speed_type}.{f}", "missing wind_facing")

    for facing, wind_speeds in facings.items():
        if facing not in EXPECTED_FACINGS:
            continue
        if not isinstance(wind_speeds, dict):
            report.err(f"{speed_type}.{facing}",
                       f"expected object, got {type(wind_speeds).__name__}")
            continue
        _validate_wind_speeds(speed_type, facing, wind_speeds, report)


def _validate_wind_speeds(speed_type, facing, wind_speeds, report):
    extra = set(wind_speeds.keys()) - VALID_WIND_SPEEDS
    for ws in sorted(extra):
        report.err(f"{speed_type}.{facing}.{ws}",
                   "wind_speed key must be one of '1','2','3','4' (as strings)")

    missing = VALID_WIND_SPEEDS - set(wind_speeds.keys())
    for ws in sorted(missing):
        # Missing wind speed = 0 lookup for every rigging quality / sail state
        # at that ws. Almost always a mistake.
        report.warn(f"{speed_type}.{facing}.{ws}",
                    "missing wind_speed — every lookup at this ws will return 0")

    for ws, rigging_qualities in wind_speeds.items():
        if ws not in VALID_WIND_SPEEDS:
            continue
        if not isinstance(rigging_qualities, dict):
            report.err(f"{speed_type}.{facing}.{ws}",
                       f"expected object, got {type(rigging_qualities).__name__}")
            continue
        _validate_rigging_qualities(speed_type, facing, ws, rigging_qualities, report)


def _validate_rigging_qualities(speed_type, facing, ws, rigging_qualities, report):
    extra = set(rigging_qualities.keys()) - VALID_RIGGING_QUALITIES
    for rq in sorted(extra):
        report.err(f"{speed_type}.{facing}.{ws}.{rq}",
                   "rigging_quality key must be one of '1','2','3','4' (as strings)")

    missing = VALID_RIGGING_QUALITIES - set(rigging_qualities.keys())
    for rq in sorted(missing):
        # Missing rq is sometimes intentional (low rq has no usable sail).
        report.warn(f"{speed_type}.{facing}.{ws}.{rq}",
                    "missing rigging_quality — lookups at this rq return 0")

    for rq, sail_states in rigging_qualities.items():
        if rq not in VALID_RIGGING_QUALITIES:
            continue
        if not isinstance(sail_states, dict):
            report.err(f"{speed_type}.{facing}.{ws}.{rq}",
                       f"expected object, got {type(sail_states).__name__}")
            continue
        _validate_sail_states(speed_type, facing, ws, rq, sail_states, report)


def _validate_sail_states(speed_type, facing, ws, rq, sail_states, report):
    if not sail_states:
        report.warn(f"{speed_type}.{facing}.{ws}.{rq}",
                    "empty sail_states object — every lookup here returns 0")

    extra = set(sail_states.keys()) - VALID_SAIL_STATES
    for ss in sorted(extra):
        report.err(f"{speed_type}.{facing}.{ws}.{rq}.{ss}",
                   "sail_state key must be one of 'fs','ms','ps','ns' (lowercase)")

    for ss, value in sail_states.items():
        if ss not in VALID_SAIL_STATES:
            continue
        path = f"{speed_type}.{facing}.{ws}.{rq}.{ss}"
        if not isinstance(value, int) or isinstance(value, bool):
            report.err(path, f"MA must be an integer, got {type(value).__name__} ({value!r})")
        elif value < 0:
            report.err(path, f"MA must be non-negative, got {value}")


def main():
    parser = argparse.ArgumentParser(
        description="Validate data/rules/movement_allowance.json schema.")
    parser.add_argument(
        "path",
        nargs="?",
        default="data/rules/movement_allowance.json",
        help="Path to movement_allowance.json (default: data/rules/movement_allowance.json)",
    )
    args = parser.parse_args()

    p = Path(args.path)
    if not p.exists():
        print(f"FAIL: file not found: {p}", file=sys.stderr)
        return 2

    try:
        with p.open() as fh:
            data = json.load(fh)
    except json.JSONDecodeError as e:
        print(f"FAIL: invalid JSON in {p}: {e}", file=sys.stderr)
        return 2

    print(f"Validating {p}...")
    report = Report()
    validate_movement_allowance(data, report)
    report.print()
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
