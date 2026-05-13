---
estimated_steps: 1
estimated_files: 9
skills_used: []
---

# T03: Run full test suite and confirm no regressions

Run `make test` and verify all tests are green. If any pre-existing test fails because of the new seed requirement or the crew_quality normalization, the fix lives here — but the intended outcome is no regressions, since T02 already updated both scenario JSON files and the default-fallback scenario. Capture the full test output to `/tmp/s01_t03_make_test.log` and confirm: (a) the bearing-off test file is in the run, (b) no Failures/Errors lines appear, (c) the existing test_data_manager_movement, test_data_manager_ships, test_data_manager_speed_change, test_data_manager_tacking, test_data_manager_turning, test_data_manager_scenarios, and test_trace all still pass. This task creates no new code; it is the verification gate for the slice.

## Inputs

- `Makefile`
- `test/unit/test_data_manager_bearing_off.gd`
- `test/unit/test_data_manager_scenarios.gd`
- `test/unit/test_data_manager_movement.gd`
- `test/unit/test_data_manager_ships.gd`
- `test/unit/test_data_manager_speed_change.gd`
- `test/unit/test_data_manager_tacking.gd`
- `test/unit/test_data_manager_turning.gd`
- `test/unit/test_trace.gd`

## Expected Output

- Update the implementation and proof artifacts needed for this task.

## Verification

make test 2>&1 | tee /tmp/s01_t03_make_test.log && ! grep -qE 'Failures|Errors|FAIL' /tmp/s01_t03_make_test.log

## Observability Impact

None — verification-only task. The log at `/tmp/s01_t03_make_test.log` is the evidence artifact.
