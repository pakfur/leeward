---
id: T01
parent: S04
milestone: M001
key_files:
  - scripts/ui/planning_phase_ui.gd
  - scenes/ui/planning_phase_ui.tscn
  - scripts/core/game_controller.gd
  - scripts/ui/ship_list_item.gd
  - test/unit/test_data_manager_ships.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T16:35:59.446Z
blocker_discovered: false
---

# T01: Added End Planning button, ship submission tracking with visual feedback, and re-plot support

**Added End Planning button, ship submission tracking with visual feedback, and re-plot support**

## What Happened

Implemented the full planning UI fleet workflow: EndPlanningButton shows submitted/total count and enables when all player-0 ships have plots. Ship list items show green tint and [OK] suffix for submitted ships. Clicking Movement on a submitted ship clears the old submission and starts fresh plotting. End Planning wires through phase controller to advance to MOVEMENT_RESOLUTION. Replaced all print() calls with Trace.trace_log(). Fixed 3 pre-existing crew_count test assertions in test_data_manager_ships.gd.

## Verification

make test: all 214 tests pass with 0 failures

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test` | 0 | pass | 15000ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/ui/planning_phase_ui.gd`
- `scenes/ui/planning_phase_ui.tscn`
- `scripts/core/game_controller.gd`
- `scripts/ui/ship_list_item.gd`
- `test/unit/test_data_manager_ships.gd`
