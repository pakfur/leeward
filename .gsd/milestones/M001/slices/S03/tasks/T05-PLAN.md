---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T05: Write comprehensive fixture tests for all single-ship movement rules

Create test/unit/test_movement_validator.gd with fixture tests: (1) MA exhaustion — ship with MA=3 can make exactly 3 forward moves. (2) Turn-then-forward — ship must move minimum forward hexes before next turn per turning table. (3) Pivot caps — max 2 pivots, no consecutive pivots. (4) Luffing — pivot into L stops movement. (5) In-irons — speed=0 facing L gets no moves. (6) Fast-tack bonus — C→B first pivot gives +1 MA. (7) Free pivot at MA=0. (8) Speed range — accel/decel bounds enforced. (9) MA recalculation on pivot. Each test creates a minimal ShipState + EnvironmentState, calls calculate_valid_moves with appropriate path_so_far, and asserts the result.

## Inputs

- `scripts/server/movement_validator.gd`
- `scripts/server/movement_types.gd`
- `scripts/state/ship_state.gd`
- `scripts/state/environment_state.gd`

## Expected Output

- `test/unit/test_movement_validator.gd`

## Verification

make test-file F=test/unit/test_movement_validator.gd passes all tests; make test full suite no regression
