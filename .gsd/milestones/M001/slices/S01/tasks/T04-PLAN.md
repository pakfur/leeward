---
estimated_steps: 7
estimated_files: 6
skills_used: []
---

# T04: Clean-room verification gate: 0 failures, 0 errors, full suite green from a clean import cache

Final verification gate for S01, added per override D010. Run `make clean && make test` from a clean import cache (forces full reimport so a stale `.godot` cache cannot mask data-file edits made in T03). This task creates no new code — it is the override-mandated cold verification gate that S01 must clear before it can complete.

Confirm:
(a) totals line shows `Failing Tests 0`;
(b) no `Errors` lines anywhere in the output;
(c) test count is at or above the current baseline of 180 (the bearing-off file from T01 adds tests, the new scenario tests from T02 add more; if the total drops, a test was lost and that is itself a regression);
(d) all of these test files are in the run and all green: test_data_manager_bearing_off, test_data_manager_scenarios, test_data_manager_movement, test_data_manager_ships, test_data_manager_speed_change, test_data_manager_tacking, test_data_manager_turning, test_trace.

Save the full output to `.gsd/runtime/s01_t04_clean_make_test.log`. The verify line below enforces all four conditions.

## Inputs

- `T03 completion (full suite green from a warm cache)`
- `.gsd/OVERRIDES.md exit bar (all tests must pass, even preexisting failures)`
- `.gsd/DECISIONS.md D010`

## Expected Output

- `make clean succeeds; .godot cache rebuilt`
- `make test reports `Failing Tests 0` from the clean import cache`
- `Zero Errors lines in the output`
- `Test total count >= 180 (baseline + new tests from T01/T02)`
- `.gsd/runtime/s01_t04_clean_make_test.log archives the clean-room green run`
- `S01 ready to mark complete`

## Verification

mkdir -p .gsd/runtime && make clean && make test 2>&1 | tee .gsd/runtime/s01_t04_clean_make_test.log && grep -qE 'Failing Tests +0' .gsd/runtime/s01_t04_clean_make_test.log && ! grep -qE 'Failing Tests +[1-9]|^[[:space:]]*Errors' .gsd/runtime/s01_t04_clean_make_test.log && grep -qE 'Tests[[:space:]]+(18[0-9]|19[0-9]|[2-9][0-9]{2,})' .gsd/runtime/s01_t04_clean_make_test.log

## Observability Impact

No code-level observability impact. Process-level: archiving the clean-room green run to .gsd/runtime/ provides a checkable artifact for any future "did S01 really exit green?" forensics.
