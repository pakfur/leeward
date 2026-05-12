---
id: S05
parent: M001
milestone: M001
provides:
  - is_tacking_attempt_flag
  - tacking_probability_display
requires:
  []
affects:
  []
key_files:
  - scripts/server/movement_types.gd
  - scripts/server/movement_plotting_controller.gd
  - scripts/ui/movement_plotting_client.gd
  - scripts/server/movement_validator.gd
  - scripts/core/game_controller.gd
  - scripts/ui/planning_phase_ui.gd
  - scenes/ui/planning_phase_ui.tscn
  - test/unit/test_movement_tacking.gd
key_decisions:
  - Tacking flag authoritative path: validator → ValidMovesResult → controller → session → response → client signal → GameController → UI
  - Session._recompute_tracking resets flag; controller sets authoritative value from validator after undo — no HexGrid dependency in session
  - Gold-colored label in plotting controls section, hidden by default
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T16:44:27.452Z
blocker_discovered: false
---

# S05: Tacking attempt detection and live probability UX

**Tacking attempts detected during plotting, live probability displayed in UI, flag reverts on undo**

## What Happened

Flowed is_tacking_attempt through the full response chain: MovementValidator computes it in PlottingState (pivots_used >= 2 AND luffing_ended), ValidMovesResult carries it, controller writes it to session and all three response types (PlottingStarted, HexSelected, UndoComplete), client carries it through signals. GameController computes tacking probability from DataManager.get_tacking_percent using ship maneuverability and current wind speed, passes to PlanningPhaseUI which displays a gold 'Tacking: NN% success' label inside plotting controls. Label hides when is_tacking_attempt is false or plotting controls are hidden. Session._recompute_tracking resets the flag on undo; the controller then sets the authoritative value from the validator. 12 new unit tests cover detection, non-detection edge cases, undo revert, probability lookup, and response serialization.

## Verification

make test: 226/226 pass (12 new tacking tests + 214 existing)

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
