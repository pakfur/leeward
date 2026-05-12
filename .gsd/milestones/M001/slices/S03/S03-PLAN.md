# S03: MovementValidator real rules (single-ship, no contests)

**Goal:** Replace mock MovementValidator with real single-ship movement rules: MA from DataManager with speed range, turning table enforcement, pivot caps, luffing/tacking detection, fast-tack bonus. PlotStep carries move_type. Trace logs every rule-block.
**Demo:** All single-ship fixture scenarios pass: MA exhaustion, turn-then-forward, fast-tack bonus, pivot caps, luffing, in-irons plot. PlotStep carries move_type. Trace logs every rule-block.

## Must-Haves

- All single-ship fixture scenarios pass: MA exhaustion, turn-then-forward minimum, fast-tack +1 MA bonus, pivot caps (max 2/turn, no consecutive), luffing stops movement, in-irons at plot start. PlotStep.move_type populated. Trace.trace_log on every rule-block. No regression in existing 196 passing tests.

## Proof Level

- This slice proves: Contract + fixture: unit tests verify each rule in isolation; fixture scenarios verify rule interactions for canonical movement patterns.

## Integration Closure

Upstream: S02's GameState.rng available (not consumed yet — tacking rolls are S06). S01's DataManager wrappers for all rule tables. Downstream: S04 consumes valid_next_hexes from validator. S05 reads session.is_tacking_attempt. New wiring: MovementValidator reads DataManager tables directly instead of delegating to ShipState.get_movement_allowance(). Session tracks pivots_used, forward_hexes_since_last_pivot, last_pivot_direction.

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: Add move_type to PlotStep and tracking fields to MovementPlottingSession** `est:30m`
  Add move_type: MoveType field to PlotStep class in movement_types.gd. Add pivots_used: int, forward_hexes_since_last_pivot: int, last_pivot_direction: MoveType (PORT/STARBOARD/NONE) to MovementPlottingSession. Update session.select_hex() to accept and store move_type on the PlotStep. Update session.undo_to_version() to recompute tracking fields from remaining path. Ensure serialize() includes new fields.
  - Files: `scripts/server/movement_types.gd`, `scripts/server/movement_plotting_session.gd`
  - Verify: Existing tests pass. New fields accessible on PlotStep and session. Undo correctly recomputes tracking state.

- [x] **T02: Rewrite MovementValidator with real MA calculation and speed range** `est:45m`
  Replace _mock_valid_hexes and _get_movement_allowance with real implementations. MA lookup: use DataManager.get_movement_allowance(speed_type, wind_speed, wind_facing, sail_state, rigging_quality) where wind_facing computed via hex_grid.get_wind_facing(current_facing, wind_direction). Speed range: min_ma = max(speed_last_turn - decel, 0), max_ma = min(speed_last_turn + accel, MA). Remaining MA tracks across path and recalculates on each pivot (new facing → new wind_facing → new MA). Forward moves cost 1 MA each; pivots cost 1 MA (or 0 if remaining MA is 0 and no free pivot used yet). Add an internal PlottingState snapshot class to hold computed state during validation.
  - Files: `scripts/server/movement_validator.gd`
  - Verify: Unit test: frigate at C facing, wind speed 3, MS sail → MA=4. Speed range respects accel/decel from speed_change_table. Pivot recalculates MA for new facing.

- [x] **T03: Implement turning rules: min-forward, pivot caps, no consecutive pivots** `est:40m`
  In calculate_valid_moves: (1) Check forward_hexes_since_last_pivot >= min from turning_table before offering port/starboard. Use DataManager.get_min_heading_change_movement_required(direction, ship_speed, maneuverability) where direction is same_direction if last_pivot_direction matches, opposite_direction otherwise. (2) Enforce max 2 pivots per turn (pivots_used < 2). (3) No consecutive pivots — if last step was a pivot, only offer forward. (4) Free pivot at MA=0: if remaining_ma == 0 and pivots_used == 0, offer one free pivot (cost 0). Trace.trace_log on each rule that blocks a move option.
  - Files: `scripts/server/movement_validator.gd`
  - Verify: Fixture: ship at speed 5, maneuverability a → must move forward N hexes before turning (from turning table). Max 2 pivots per turn. No consecutive pivots. Free pivot at MA=0.

- [x] **T04: Implement luffing, in-irons, fast-tack bonus, and tacking detection** `est:40m`
  Luffing: if a pivot would make wind_facing=L, allow it but set remaining_ma=0 and mark can_submit=true (movement ends). In-irons: if ship starts turn at wind_facing=L with speed=0, movement is blocked (empty valid_hexes, can_submit=true for no-movement submission). Tacking detection: if ship pivots to L and then pivots again same direction (through L), set session.is_tacking_attempt=true. Fast-tack bonus: if ship is at wind_facing=C and first move is a pivot to wind_facing=B, add +1 to remaining MA (close-hauled to broad reach bonus). Trace all of these.
  - Files: `scripts/server/movement_validator.gd`, `scripts/server/movement_plotting_session.gd`
  - Verify: Fixture: pivot into L ends movement. In-irons ship gets empty moves. Tacking through L sets is_tacking_attempt. C→B first pivot gets +1 MA.

- [x] **T05: Write comprehensive fixture tests for all single-ship movement rules** `est:60m`
  Create test/unit/test_movement_validator.gd with fixture tests: (1) MA exhaustion — ship with MA=3 can make exactly 3 forward moves. (2) Turn-then-forward — ship must move minimum forward hexes before next turn per turning table. (3) Pivot caps — max 2 pivots, no consecutive pivots. (4) Luffing — pivot into L stops movement. (5) In-irons — speed=0 facing L gets no moves. (6) Fast-tack bonus — C→B first pivot gives +1 MA. (7) Free pivot at MA=0. (8) Speed range — accel/decel bounds enforced. (9) MA recalculation on pivot. Each test creates a minimal ShipState + EnvironmentState, calls calculate_valid_moves with appropriate path_so_far, and asserts the result.
  - Files: `test/unit/test_movement_validator.gd`
  - Verify: make test-file F=test/unit/test_movement_validator.gd passes all tests; make test full suite no regression

## Files Likely Touched

- scripts/server/movement_types.gd
- scripts/server/movement_plotting_session.gd
- scripts/server/movement_validator.gd
- test/unit/test_movement_validator.gd
