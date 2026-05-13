---
id: T02
parent: S01
milestone: M001
key_files:
  - scripts/autoload/data_manager.gd
  - data/scenarios/test_basic.json
  - data/scenarios/test_fleet.json
  - test/unit/test_data_manager_scenarios.gd
key_decisions:
  - (none)
duration: 
verification_result: untested
completed_at: 2026-05-12T14:50:40.132Z
blocker_discovered: false
---

# T02: Added seed validation, fresh-seed generation, and crew_quality word-to-letter normalization to load_scenario

**Added seed validation, fresh-seed generation, and crew_quality word-to-letter normalization to load_scenario**

## What Happened

Modified load_scenario() to: (1) validate that scenario JSON has an integer seed field — missing or non-int triggers push_error and returns empty dict; (2) if seed == -1, generate fresh seed via Time.get_unix_time_from_system(), write back to dict, and Trace.trace_log it; (3) normalize crew_quality words to letters (Elite→A, Veteran→B, Crack→C, Trained→D, Green→E, Poor→F, Demoralized→G) for all ships in the scenario. Added optional file_path parameter to load_scenario for test flexibility. Updated test_basic.json and test_fleet.json with seed:42. Updated _create_default_scenario() with seed:-1. Added 5 new tests to test_data_manager_scenarios.gd: seed field exists, seed -1 generates fresh, missing seed hard errors, crew_quality normalized to letters, Trained maps to D. All scenario tests pass.

## Verification

make test-file F=test/unit/test_data_manager_scenarios.gd — all 16 scenario tests pass; 0 scenario failures in the failing-tests list (45 preexisting failures remain from other test files)

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| — | No verification commands discovered | — | — | — |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/autoload/data_manager.gd`
- `data/scenarios/test_basic.json`
- `data/scenarios/test_fleet.json`
- `test/unit/test_data_manager_scenarios.gd`
