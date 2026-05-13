---
estimated_steps: 1
estimated_files: 2
skills_used: []
---

# T01: Add move_type to PlotStep and tracking fields to MovementPlottingSession

Add move_type: MoveType field to PlotStep class in movement_types.gd. Add pivots_used: int, forward_hexes_since_last_pivot: int, last_pivot_direction: MoveType (PORT/STARBOARD/NONE) to MovementPlottingSession. Update session.select_hex() to accept and store move_type on the PlotStep. Update session.undo_to_version() to recompute tracking fields from remaining path. Ensure serialize() includes new fields.

## Inputs

- `scripts/server/movement_types.gd`
- `scripts/server/movement_plotting_session.gd`

## Expected Output

- `scripts/server/movement_types.gd`
- `scripts/server/movement_plotting_session.gd`

## Verification

Existing tests pass. New fields accessible on PlotStep and session. Undo correctly recomputes tracking state.
