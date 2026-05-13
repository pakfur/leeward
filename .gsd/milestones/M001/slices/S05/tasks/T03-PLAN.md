---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T03: Unit tests for tacking detection and undo revert

Write unit tests that: (1) verify is_tacking_attempt flips true when a path involves pivot-to-L then same-direction pivot, (2) verify undoing past the tacking trigger flips is_tacking_attempt back to false, (3) verify _recompute_tracking in session correctly handles the luffing/tacking detection.

## Inputs

- `MovementValidator`
- `MovementPlottingSession`
- `tacking_table.json`

## Expected Output

- `test_movement_tacking.gd with tests for tacking detection, probability lookup, and undo revert`

## Verification

make test-file F=test/unit/test_movement_tacking.gd passes
