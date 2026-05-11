---
id: T01
parent: S01
milestone: M001
key_files:
  - data/rules/bearing_off_table.json
  - scripts/autoload/data_manager.gd
  - test/unit/test_data_manager_bearing_off.gd
key_decisions:
  - Derived bearing-off probabilities analytically from CA rules VI.D.2 (target = SK - class_DRM, prob = clamp((7 - target)/6, 0, 1)) and documented the derivation in a top-level _doc field inside the JSON.
  - Excluded the friendly-ship +1 DRM and per-turn turn-count rule from the baked-in table — the table answers only the base d6 question; callers must apply situational modifiers themselves.
  - Followed the existing load_*_table / get_* convention exactly (push_warning on missing file, push_error on parse failure, asserts for param validation, case-insensitive letter inputs, push_error + 0.0 on missing key) instead of inventing a new shape.
  - Did not wire load_bearing_off_table() into GameState autoload — deferred to the first real consumer per the task plan.
duration: 
verification_result: passed
completed_at: 2026-05-11T22:19:44.568Z
blocker_discovered: false
---

# T01: Added bearing_off_table.json with CA-VI.D.2-derived probabilities, DataManager.load_bearing_off_table()/get_bearing_off_probability(), and 11 GUT regression tests — all 11/11 pass.

**Added bearing_off_table.json with CA-VI.D.2-derived probabilities, DataManager.load_bearing_off_table()/get_bearing_off_probability(), and 11 GUT regression tests — all 11/11 pass.**

## What Happened

Created `data/rules/bearing_off_table.json` — a 2-level nested dictionary (crew_quality A..G → maneuverability a..d → float success probability). Probabilities were derived analytically from Close Action rules VI.D.2: roll d6, succeed on ≥ SK with class DRMs (-1/0/+1/+2 for class 1..4). SK was mapped from crew_quality (A=1..G=7) and maneuverability was used as a class proxy (a=class1..d=class4) per the inlined task plan; the derivation is documented in a top-level `_doc` field inside the JSON, with explicit notes that the +1 friendly-ship DRM and per-turn turn-count limits from VI.D.2 are NOT baked in (callers apply them).

Probabilities: target = SK − DRM, prob = clamp((7 − target)/6, 0, 1). Hand-verified anchors: A/a → 5/6, C/b → 4/6, E/a → 1/6, G/a → 0.0, A/d → 1.0 (auto-success when target ≤ 1).

Added to `scripts/autoload/data_manager.gd` (between the turning table block and `load_ship_definitions`): a `bearing_off_table: Dictionary = {}` field, `load_bearing_off_table(file_path)` mirroring the existing `load_*_table` shape (push_warning + return false on missing file; push_error + return false on parse failure; print item count on success — the count excludes `_doc`), and `get_bearing_off_probability(crew_quality, maneuverability)` with `assert()` on both params (A..G case-insensitive; a..d case-insensitive), push_error + return 0.0 on any missing key. Followed the existing speed_change/tacking/turning conventions exactly. No GameState wiring per task instructions.

Created `test/unit/test_data_manager_bearing_off.gd` (11 tests) following the `test_data_manager_speed_change.gd` pattern: table-loads-successfully, has-all-7-crew-quality-grades, has-all-4-maneuverability-grades, 5 known-value regression anchors (A/a, C/b, E/a, G/a, A/d) including auto-success and auto-fail edges, case-insensitivity for both crew_quality and maneuverability, and a monotonicity sanity check that at every fixed maneuverability, better crew quality (lower letter) yields ≥ probability than worse crew quality.

Ran `make import` once to fix the stale GUT class-name cache that initially blocked autoload parsing, then verified with `make test-file F=test/unit/test_data_manager_bearing_off.gd`: 11/11 of the new bearing-off tests pass; the loader logged `Loaded bearing off table with 7 crew quality grades` (correctly excluding `_doc`).

Note: the test-file invocation reports 188/191 passing with 3 pre-existing failures in `test_data_manager_ships.gd` (`test_frigate_38_crew_count`, `test_get_total_crew_frigate`, `test_get_total_crew_sol`) — these are unrelated to T01 (I did not modify ships.json, ship.gd, or the ships test file) and are out of scope here. GUT's `-gtest=` flag still loads sibling test scripts, so the make target exits non-zero from those pre-existing failures even though every bearing-off assertion passes. Captured `MEM010` documenting the DataManager rule-table loader convention so future loaders (drift, status-adjustment, etc.) follow the same shape.

## Verification

Ran `make import` (Godot 4.6.2) to refresh the .godot cache so GUT's class_names resolve, then `make test-file F=test/unit/test_data_manager_bearing_off.gd`. All 11 new bearing-off tests pass (verified by name in the GUT output block: test_bearing_off_table_loads_successfully, test_bearing_off_table_has_all_crew_quality_grades, test_bearing_off_table_has_all_maneuverability_grades, test_lookup_A_a_is_5_of_6, test_lookup_C_b_is_4_of_6, test_lookup_E_a_is_1_of_6, test_lookup_G_a_is_zero, test_lookup_A_d_is_one, test_crew_quality_lowercase_converted_to_uppercase, test_maneuverability_uppercase_converted_to_lowercase, test_better_crew_quality_geq_worse_at_same_maneuverability — all reported `11/11 passed`). The success log `Loaded bearing off table with 7 crew quality grades` confirms the JSON parses, `_doc` is excluded from the grade count, and all 7 grades are loaded. The 3 failures the wrapper command reports are in `test_data_manager_ships.gd` and pre-date this task — git status confirms I touched only `data_manager.gd`, the new JSON, and the new test file.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make import` | 0 | pass | 8000ms |
| 2 | `make test-file F=test/unit/test_data_manager_bearing_off.gd` | 2 | pass-for-task-scope (11/11 bearing-off tests pass; 3 failing tests are pre-existing in test_data_manager_ships.gd and out of T01 scope) | 4500ms |

## Deviations

None. Implemented the task plan as written.

## Known Issues

3 pre-existing failures in test/unit/test_data_manager_ships.gd (test_frigate_38_crew_count, test_get_total_crew_frigate, test_get_total_crew_sol) — out of scope for T01, will need separate investigation if not already tracked.

## Files Created/Modified

- `data/rules/bearing_off_table.json`
- `scripts/autoload/data_manager.gd`
- `test/unit/test_data_manager_bearing_off.gd`
