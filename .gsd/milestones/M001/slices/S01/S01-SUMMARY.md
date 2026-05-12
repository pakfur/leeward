---
id: S01
parent: M001
milestone: M001
provides:
  - (none)
requires:
  []
affects:
  []
key_files:
  - scripts/autoload/data_manager.gd
  - data/rules/bearing_off_table.json
  - data/rules/ships.json
  - data/rules/speed_change_table.json
  - data/rules/tacking_table.json
  - data/rules/turning_table.json
  - data/scenarios/test_basic.json
  - data/scenarios/test_fleet.json
  - test/unit/test_data_manager_bearing_off.gd
  - test/unit/test_data_manager_scenarios.gd
key_decisions:
  - Renamed 'readme' to '_doc' in all rule JSON files and strip on load (consistent with bearing_off_table convention D008)
  - Crew quality uses word→letter mapping: Elite→A, Veteran→B, Crack→C, Trained→D, Green→E, Poor→F, Demoralized→G
  - Seed contract: integer required, -1 generates fresh, missing hard-errors
  - crew_count arrays padded to 4 elements per ship to match game's 4-section damage model
patterns_established:
  - _doc key convention for rule table documentation (stripped on load)
  - assert_push_error/assert_engine_error pattern for testing expected errors in GUT
  - Lowercase maneuverability keys in all rule JSON files
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T14:55:51.047Z
blocker_discovered: false
---

# S01: DataManager Rule Tables + Scenario Hardening

**Delivered bearing_off_table DataManager wrapper, scenario seed validation, crew_quality normalization, and fixed all 45 preexisting test failures to reach 196/196 green**

## What Happened

S01 delivered four major pieces:

**T01 — Bearing Off Table**: Merged bearing_off_table.json (CA-VI.D.2-derived probabilities, 7 crew quality grades × 4 maneuverability grades) and DataManager wrapper (load_bearing_off_table + get_bearing_off_probability) from the worktree. 11 tests covering loading, known-value anchors, case insensitivity, and monotonicity.

**T02 — Scenario Seed Validation + Crew Quality Normalization**: Added seed contract to load_scenario (integer required, -1 generates fresh via unix timestamp, missing seed hard-errors). Added _normalize_crew_quality() that maps word forms (Elite→A through Demoralized→G) to single-letter grades. Added seed field to test_basic.json and test_fleet.json. 5 new scenario tests.

**T03 — Fix Preexisting Test Failures**: Fixed 45 failures across 4 data files: ships.json crew_count arrays padded to 4 elements; speed_change_table.json and tacking_table.json keys lowercased from A/B/C/D to a/b/c/d; "readme" keys renamed to "_doc" and stripped on load in all table loaders.

**T04 — Clean-Room Verification**: make clean && make import && make test → 196/196 passing, 730 asserts, 0 failures.

## Verification

Clean-room gate: make clean && make import && make test → 196/196 tests, 730 asserts, 0 failures, 0 errors across 8 test scripts

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

None.

## Known Limitations

None.

## Follow-ups

None.

## Files Created/Modified

None.
