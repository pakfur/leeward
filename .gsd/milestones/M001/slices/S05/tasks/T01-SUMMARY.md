---
id: T01
parent: S05
milestone: M001
key_files:
  - scripts/server/movement_types.gd
  - scripts/server/movement_plotting_controller.gd
  - scripts/ui/movement_plotting_client.gd
  - scripts/server/movement_validator.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T16:43:57.484Z
blocker_discovered: false
---

# T01: Flowed is_tacking_attempt through ValidMovesResult, response types, controller, client signals

**Flowed is_tacking_attempt through ValidMovesResult, response types, controller, client signals**

## What Happened

Added is_tacking_attempt to ValidMovesResult, PlottingStartedResponse, HexSelectedResponse, and UndoCompleteResponse. Updated MovementValidator to populate it from PlottingState. Updated MovementPlottingController to write the flag from validator result to session and responses in handle_start_plotting, handle_select_hex, and handle_undo. Updated MovementPlottingClient to carry the flag through all three signals and state, with proper reset in _clear_session.

## Verification

make test: all 226 tests pass

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test` | 0 | pass | 10000ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/movement_types.gd`
- `scripts/server/movement_plotting_controller.gd`
- `scripts/ui/movement_plotting_client.gd`
- `scripts/server/movement_validator.gd`
