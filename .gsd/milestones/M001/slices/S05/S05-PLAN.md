# S05: Tacking attempt detection and live probability UX

**Goal:** Detect tacking attempts during plotting and display live tacking success probability in the Planning UI
**Demo:** Plot pivot-to-L then pivot-same-direction; session.is_tacking_attempt flips true; UI shows tacking-success % from tacking_table.json + DRMs. Undoing past the trigger flips it back to false.

## Must-Haves

- Plot pivot-to-L then pivot-same-direction; session.is_tacking_attempt flips true; UI shows tacking-success % from tacking_table.json + DRMs. Undoing past the trigger flips it back to false.

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: Flow is_tacking_attempt through response chain** `est:20m`
  Add is_tacking_attempt to ValidMovesResult, HexSelectedResponse, UndoCompleteResponse, PlottingStartedResponse. Update MovementPlottingController to read is_tacking_attempt from the validator's PlottingState and write it to the session. Update MovementPlottingClient to carry the flag through signals. Fix _recompute_tracking() in session to properly detect tacking by tracking luffing_ended.
  - Files: `scripts/server/movement_types.gd`, `scripts/server/movement_plotting_controller.gd`, `scripts/server/movement_plotting_session.gd`, `scripts/ui/movement_plotting_client.gd`
  - Verify: make test passes; tacking flag reaches client signal

- [x] **T02: Calculate and display tacking probability in Planning UI** `est:15m`
  In GameController, read is_tacking_attempt from client signals and pass tacking probability (looked up from DataManager.get_tacking_percent) to PlanningPhaseUI. Add a tacking probability label to the plotting controls section of the planning UI. Show 'Tacking: NN%' when is_tacking_attempt is true, hide otherwise. Compute probability from ship's maneuverability and current wind speed.
  - Files: `scripts/core/game_controller.gd`, `scripts/ui/planning_phase_ui.gd`, `scenes/ui/planning_phase_ui.tscn`
  - Verify: make test passes; label visible/hidden correctly in manual test

- [x] **T03: Unit tests for tacking detection and undo revert** `est:20m`
  Write unit tests that: (1) verify is_tacking_attempt flips true when a path involves pivot-to-L then same-direction pivot, (2) verify undoing past the tacking trigger flips is_tacking_attempt back to false, (3) verify _recompute_tracking in session correctly handles the luffing/tacking detection.
  - Files: `test/unit/test_movement_tacking.gd`
  - Verify: make test-file F=test/unit/test_movement_tacking.gd passes

## Files Likely Touched

- scripts/server/movement_types.gd
- scripts/server/movement_plotting_controller.gd
- scripts/server/movement_plotting_session.gd
- scripts/ui/movement_plotting_client.gd
- scripts/core/game_controller.gd
- scripts/ui/planning_phase_ui.gd
- scenes/ui/planning_phase_ui.tscn
- test/unit/test_movement_tacking.gd
