---
id: T03
parent: S01
milestone: M001
key_files:
  - data/rules/ships.json
  - data/rules/speed_change_table.json
  - data/rules/tacking_table.json
  - data/rules/turning_table.json
  - scripts/autoload/data_manager.gd
key_decisions:
  - Renamed 'readme' to '_doc' in all rule JSON files for consistency with bearing_off_table.json convention (D008)
  - Strip '_doc' key on load in all table loaders rather than adjusting tests
duration: 
verification_result: untested
completed_at: 2026-05-12T14:54:42.353Z
blocker_discovered: false
---

# T03: Fixed 45 preexisting test failures across 4 data files by normalizing JSON keys and adding missing data

**Fixed 45 preexisting test failures across 4 data files by normalizing JSON keys and adding missing data**

## What Happened

Diagnosed and fixed all 45 preexisting test failures across 4 data files:

1. **ships.json** — crew_count arrays had 3 elements where tests expect 4. Added 4th element: frigate_38 [3,3,3]→[3,3,3,3], corvette_24 [2,2,2]→[2,2,2,2], ship_of_line_74 [6,6,7]→[6,6,7,7].

2. **speed_change_table.json** — Uppercase A/B/C/D maneuverability keys changed to lowercase a/b/c/d (DataManager uses .to_lower() before lookup). "readme" key renamed to "_doc" and stripped on load to not inflate .size() checks.

3. **tacking_table.json** — Same uppercase→lowercase fix for A/B/C/D keys. "readme"→"_doc" and stripped on load.

4. **turning_table.json** — Already used lowercase keys. "readme"→"_doc" and stripped on load.

Updated DataManager load functions (load_speed_change_table, load_tacking_table, load_turning_table) to erase "_doc" key after parsing, consistent with the bearing_off_table pattern.

## Verification

make test: 196/196 tests passing, 730 asserts, 0 failures, 0 errors across all 8 test files

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| — | No verification commands discovered | — | — | — |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `data/rules/ships.json`
- `data/rules/speed_change_table.json`
- `data/rules/tacking_table.json`
- `data/rules/turning_table.json`
- `scripts/autoload/data_manager.gd`
