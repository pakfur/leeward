---
id: T01
parent: S01
milestone: M001
key_files:
  - data/rules/bearing_off_table.json
  - scripts/autoload/data_manager.gd
  - test/unit/test_data_manager_bearing_off.gd
key_decisions:
  - (none)
duration: 
verification_result: untested
completed_at: 2026-05-12T14:46:52.932Z
blocker_discovered: false
---

# T01: Merged bearing_off_table.json, DataManager wrapper methods, and unit tests from worktree into main tree

**Merged bearing_off_table.json, DataManager wrapper methods, and unit tests from worktree into main tree**

## What Happened

Copied bearing_off_table.json (CA-VI.D.2-derived probabilities), load_bearing_off_table() and get_bearing_off_probability() methods, and test_data_manager_bearing_off.gd from the .gsd/worktrees/M001/ worktree into the main tree. The JSON uses lowercase maneuverability keys (a..d) and uppercase crew_quality keys (A..G) with exact float probabilities. All 11 bearing_off tests pass: table loading, all crew quality grades present, all maneuverability grades present, 5 known-value regression anchors, case insensitivity for both parameters, and monotonicity validation.

## Verification

make test-file F=test/unit/test_data_manager_bearing_off.gd — all 11 bearing_off tests pass (preexisting 45 failures are from other test files, handled in T03)

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| — | No verification commands discovered | — | — | — |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `data/rules/bearing_off_table.json`
- `scripts/autoload/data_manager.gd`
- `test/unit/test_data_manager_bearing_off.gd`
