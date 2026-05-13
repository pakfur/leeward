---
id: S03
parent: M001
milestone: M001
provides:
  - MovementValidator with real single-ship rules from DataManager tables
  - PlotStep.move_type populated by validator
  - Session tracking: pivots_used, forward_hexes_since_last_pivot, last_pivot_direction, is_tacking_attempt
  - 15 fixture tests for movement rules
requires:
  - slice: S02
    provides: GameState.rng available
  - slice: S01
    provides: DataManager wrappers for rule tables
affects:
  []
key_files:
  - scripts/server/movement_validator.gd
  - scripts/server/movement_types.gd
  - scripts/server/movement_plotting_session.gd
  - scripts/server/movement_plotting_controller.gd
  - test/unit/test_movement_validator.gd
key_decisions:
  - Single MovementValidator class with PlottingState snapshot — procedural, no rule-engine abstraction
  - T02-T04 combined into single rewrite since rules are deeply interdependent
  - MockGameState extends Node for type compatibility with validator constructor
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T16:24:33.324Z
blocker_discovered: false
---

# S03: MovementValidator real rules (single-ship, no contests)

**Replaced mock MovementValidator with real single-ship rules: MA from DataManager, speed range, turning table, pivot caps, luffing, in-irons, tacking detection, fast-tack bonus, 15 fixture tests**

## What Happened

Five tasks delivered the complete single-ship movement validation system. T01 added move_type to PlotStep and tracking fields (pivots_used, forward_hexes_since_last_pivot, last_pivot_direction, is_tacking_attempt, remaining_ma) to MovementPlottingSession. T02-T04 rewrote MovementValidator in a single pass: MA lookup from DataManager with wind-facing recalculation on pivots; speed range from accel/decel tables; turning table min-forward enforcement; max 2 pivots/turn with no consecutive pivots; free pivot at MA=0; luffing (pivot into L) ends movement; in-irons detection; tacking detection; fast-tack C→B +1 MA bonus. Internal PlottingState snapshot class enables clean rule evaluation by replaying the path. T05 added 15 fixture tests covering all rules with MockGameState for configurable wind. All 211 tests pass.

## Verification

make test: 211/211 all passing (15 new movement validator tests + 196 existing). Every rule has at least one dedicated fixture test. Trace.trace_log called on every rule-block.

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
