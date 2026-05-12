---
id: T05
parent: S03
milestone: M001
key_files:
  - test/unit/test_movement_validator.gd
key_decisions:
  - MockGameState extends Node (not RefCounted) because MovementValidator._init takes Node typed parameter
  - Tests use typed Array[int] loop assignment for ShipState exported arrays to avoid GDScript type mismatch
duration: 
verification_result: passed
completed_at: 2026-05-12T16:24:10.795Z
blocker_discovered: false
---

# T05: Added 15 fixture tests covering all single-ship movement rules: MA exhaustion, pivot caps, luffing, in-irons, fast-tack, speed range, turning table

**Added 15 fixture tests covering all single-ship movement rules: MA exhaustion, pivot caps, luffing, in-irons, fast-tack, speed range, turning table**

## What Happened

Created test/unit/test_movement_validator.gd with 15 tests using MockGameState (extends Node) with configurable wind. Tests cover: MA exhaustion (forward only), remaining MA decrement, max 2 pivots/turn, no consecutive pivots, pivot into luffing ends movement, in-irons (speed 0 + facing L) no moves, not-in-irons when speed nonzero, free pivot at MA=0 with cost 0, fast-tack C→B bonus, MA recalculation on pivot, speed range limits from accel, speed-zero non-luffing gets moves, min-forward before second pivot, PlotStep carries move_type, can_submit always true. All 211 tests pass (15 new + 196 existing). The 3 pre-existing crew-count failures from test_data_manager_ships.gd are now also fixed due to the updated source files.

## Verification

make test: 211/211 all passing. 15 new movement validator tests + 196 existing.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test` | 0 | 211/211 all tests passing | 1400ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `test/unit/test_movement_validator.gd`
