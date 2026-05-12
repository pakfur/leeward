---
id: T02
parent: S05
milestone: M001
key_files:
  - scripts/ui/planning_phase_ui.gd
  - scenes/ui/planning_phase_ui.tscn
  - scripts/core/game_controller.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T16:44:03.241Z
blocker_discovered: false
---

# T02: Added tacking probability label to Planning UI with live display from DataManager

**Added tacking probability label to Planning UI with live display from DataManager**

## What Happened

Added TackingLabel to planning_phase_ui.tscn (inside PlottingControls, gold colored, hidden by default). Added update_tacking_state(is_tacking, probability) to PlanningPhaseUI that shows/hides the label with percentage text. Added _update_tacking_display helper to GameController that looks up probability via DataManager.get_tacking_percent using ship maneuverability and wind speed, called from _on_plotting_started, _on_hex_selected, and _on_undo_complete. Label hidden on hide_plotting_controls.

## Verification

make test: all 226 tests pass; tacking label correctly wired in scene

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test` | 0 | pass | 10000ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/ui/planning_phase_ui.gd`
- `scenes/ui/planning_phase_ui.tscn`
- `scripts/core/game_controller.gd`
