# S04: Planning UI fleet workflow: Movement button, plot display, End Planning

**Goal:** Add End Planning button, ship submission tracking, re-plot support, and fleet workflow to the Planning UI
**Demo:** Manual playtest: load test_fleet.json, plot all player-0 ships through the Movement button, see MA / path live, undo/cancel/submit per ship, End Planning gates on completion, all protocol responses under 50ms.

## Must-Haves

- Complete the planned slice outcomes.

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: End Planning button, submission tracking, re-plot support** `est:30m`
  Add EndPlanningButton with N/M counter, track submitted ships with visual feedback (green tint + [OK]), support re-plotting submitted ships, wire End Planning to phase controller, replace print() with Trace.trace_log(), fix 3 pre-existing crew_count test assertions.
  - Files: `scripts/ui/planning_phase_ui.gd`, `scenes/ui/planning_phase_ui.tscn`, `scripts/core/game_controller.gd`, `scripts/ui/ship_list_item.gd`, `test/unit/test_data_manager_ships.gd`
  - Verify: make test passes all 214 tests

## Files Likely Touched

- scripts/ui/planning_phase_ui.gd
- scenes/ui/planning_phase_ui.tscn
- scripts/core/game_controller.gd
- scripts/ui/ship_list_item.gd
- test/unit/test_data_manager_ships.gd
