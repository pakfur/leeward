---
estimated_steps: 1
estimated_files: 4
skills_used: []
---

# T01: Flow is_tacking_attempt through response chain

Add is_tacking_attempt to ValidMovesResult, HexSelectedResponse, UndoCompleteResponse, PlottingStartedResponse. Update MovementPlottingController to read is_tacking_attempt from the validator's PlottingState and write it to the session. Update MovementPlottingClient to carry the flag through signals. Fix _recompute_tracking() in session to properly detect tacking by tracking luffing_ended.

## Inputs

- `ValidMovesResult from MovementValidator`
- `existing response types`
- `session tracking fields`

## Expected Output

- `is_tacking_attempt field on ValidMovesResult`
- `is_tacking_attempt field on HexSelectedResponse/UndoCompleteResponse/PlottingStartedResponse`
- `MovementPlottingClient signals carry is_tacking_attempt`

## Verification

make test passes; tacking flag reaches client signal
