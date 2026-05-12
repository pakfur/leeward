---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T02: Rewrite MovementValidator with real MA calculation and speed range

Replace _mock_valid_hexes and _get_movement_allowance with real implementations. MA lookup: use DataManager.get_movement_allowance(speed_type, wind_speed, wind_facing, sail_state, rigging_quality) where wind_facing computed via hex_grid.get_wind_facing(current_facing, wind_direction). Speed range: min_ma = max(speed_last_turn - decel, 0), max_ma = min(speed_last_turn + accel, MA). Remaining MA tracks across path and recalculates on each pivot (new facing → new wind_facing → new MA). Forward moves cost 1 MA each; pivots cost 1 MA (or 0 if remaining MA is 0 and no free pivot used yet). Add an internal PlottingState snapshot class to hold computed state during validation.

## Inputs

- `scripts/server/movement_validator.gd`
- `scripts/autoload/data_manager.gd`
- `scripts/core/hex_grid.gd`
- `scripts/state/ship_state.gd`

## Expected Output

- `scripts/server/movement_validator.gd`

## Verification

Unit test: frigate at C facing, wind speed 3, MS sail → MA=4. Speed range respects accel/decel from speed_change_table. Pivot recalculates MA for new facing.
