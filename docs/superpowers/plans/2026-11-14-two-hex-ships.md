# Two-Hex Ships Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ships occupy two hexes (bow and stern), as in Close Action, instead of one.

**Architecture:**
- `ShipState.hex_position` stays the single stored position and becomes the **bow hex**. The stern hex is derived (the neighbour behind the bow, against the facing), so serialization, sync and the scenario format do not change.
- One `Occupancy` helper replaces the four separate ship-position maps.
- The work is done in three phases. Each phase ends with a working, tested game:
  1. **Footprint:** two-hex blocking, range, LOS and drift; bow-pivot turning; 2-hex view.
  2. **Close quarters:** overlap, stern-vs-stern contests, partial drift.
  3. **Batteries:** bow and stern batteries per side.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5.0 tests (`make test`).

**Spec:** The rules are `docs/rules/close_action.md`, with the chart and diagram scans in `docs/rules/images/`:

| Rule | Topic |
|---|---|
| 1.E.2 | Counters occupy two hexes |
| 5.A.2c | Hex alignment |
| 5.C.2 | Turning pivots on the bow |
| 6.A.4 | Movement conflicts |
| 6.B | Overlapping ships |
| 6.C.1, 6.C.5 | Stern-vs-stern contests |
| 7.B.1–7.B.7 | Batteries, arc and LOS |
| 7.C.4 | Range to the closest hex |
| 7.C.12f | Half broadside |
| 7.E.2 | Rakes |
| 8.A.3–8.A.6 | Drift |
| Diagrams 8, 13, 14, 16, 17, 20 | Worked examples |

The gap analysis is `docs/rules/feature_diff.md` (§4, "Deliberate simplifications").

## Global Constraints

- Hex grid: axial (q, r), pointy-top.
- Directions: 0=E (1,0), 1=SE (0,1), 2=SW (−1,1), 3=W (−1,0), 4=NW (0,−1), 5=NE (1,−1).
- Stern hex = `get_neighbor(bow, (facing + 3) % 6)`.
- A ship always fully occupies two hexes and points at another hex. It never lies along a hex spine (5.A.2c).
- Only one ship per hex, except the temporary overlap allowed by 6.B (Phase 2).
- SCV pattern: all mutations go through `scripts/server/` controllers guarded by `is_server`. State gets derived read-only helpers only. View and UI call read-only queries only.
- New game logic rolls through `game_state.dice`. `MovementResolver`'s own `rng` remains the documented exception.
- Runtime code logs through `Trace`. Raw `print()` is blocked by a hook.
- `make test` runs the whole suite. `make test-file` also runs everything.
- Run the `scv-reviewer` agent once at the end of each phase, not after each task.

## Review Focus

1. **Stern off the map.** A turn or scenario placement that would put the stern outside `map_bounds` has to be refused or blocked, the same as a bow. Tests in Tasks 2 and 3.
2. **Ships side by side turning away from each other** (Diagram 14 A). In Phase 1, a stern swinging into an occupied hex cancels the turn, which is stricter than 6.B.2 allows. Task 4 pins this so the change in Task 10 is visible. Players will notice it.
3. **Clicking the stern hex selects the ship,** and plotting clicks for turns land on a hex distinct from the "ahead" hex. Test in Task 7.
4. **Line of sight to a 2-hex target.** The target's own other hex never blocks (7.B.7 note), and neither does the firer's own other hex. Tests in Task 6.
5. **Fouled pairs and struck ships.** Both hexes of a struck or fouled ship block movement, LOS and drift. Tests in Tasks 4, 5 and 6.

---

## Phase 1: Footprint

### Task 1: Ship footprint and shared occupancy

**Files:**
- Modify: `scripts/core/hex_grid.gd` (add helpers)
- Modify: `scripts/state/ship_state.gd:83` (`get_ship_size` returns 2; add derived helpers)
- Create: `scripts/server/occupancy.gd`
- Test: `test/unit/test_ship_footprint.gd` (new)

**Interfaces:**
- Produces:
  - `HexGrid.stern_of(bow: Vector2i, facing: int) -> Vector2i`
  - `HexGrid.ship_center_world(bow: Vector2i, facing: int) -> Vector3`: the midpoint of the bow and stern centres.
  - `ShipState.stern_hex() -> Vector2i`
  - `ShipState.occupied_hexes() -> Array[Vector2i]`: `[bow, stern]`.
  - `class_name Occupancy`, with these static methods:
    - `Occupancy.build(ships: Array[ShipState], exclude_ids: Array = []) -> Dictionary`: maps hex (Vector2i) to ship_id. Struck ships included.
    - `Occupancy.from_positions(bows: Dictionary, facings: Dictionary, exclude_ids: Array = []) -> Dictionary`: ship_id maps to bow and to facing.
    - `Occupancy.overlapping_ids(ships: Array[ShipState]) -> Array[String]`: ids whose footprints share a hex.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_ship_footprint.gd`:
  - `test_stern_is_behind_bow`: bow (5,5) facing 0 gives stern (4,5); facing 1 gives (5,4); facing 4 gives (5,6).
  - `test_occupied_hexes_bow_first`: `assert_eq(ss.occupied_hexes(), [Vector2i(5,5), Vector2i(4,5)])`.
  - `test_ship_size_is_two`: `assert_eq(ss.get_ship_size(), 2)`.
  - `test_center_is_midpoint`: `ship_center_world((0,0), 0)` equals `(axial_to_world(0,0) + axial_to_world(-1,0)) / 2`.
  - `test_occupancy_maps_both_hexes`: two ships give 4 keys, each mapping to its ship id.
  - `test_occupancy_excludes`: `exclude_ids = ["a"]` leaves only b's two hexes.
  - `test_overlap_detected`: ship a with bow (5,5) facing 0 (stern (4,5)), and ship b with bow (4,5) facing 1. `overlapping_ids` returns both ids.
- [ ] **Step 2: Run `make test`.** Expected: the new tests fail (methods not found). The rest pass.
- [ ] **Step 3: Implement** the helpers and `scripts/server/occupancy.gd` (`class_name Occupancy extends RefCounted`, static methods only, no state). Update the `get_ship_size()` doc comment: ships are 2-hex.
- [ ] **Step 4: Run `make test`.** Expected: the new tests pass. Any test that asserts `get_ship_size() == 1` is updated to 2.
- [ ] **Step 5: Commit:** `feat: ships occupy bow and stern hexes (footprint helpers, Occupancy)`

### Task 2: Scenario placement validation

**Files:**
- Modify: `scripts/autoload/game_state.gd` (`start_new_game`, after ships are added)
- Modify: `data/scenarios/test_basic.json`, `data/scenarios/test_fleet.json`, only if a footprint overlaps or the stern is outside `map_bounds`
- Test: `test/unit/test_data_manager_scenarios.gd`

**Interfaces:**
- Consumes: `Occupancy.overlapping_ids`, `ShipState.stern_hex()`
- Produces: `GameState.placement_errors() -> Array[String]`: one message per overlapping pair or out-of-bounds stern. Empty when the placement is valid.

- [ ] **Step 1: Write the failing tests:**
  - `test_shipped_scenarios_have_valid_placement`: load each file in `data/scenarios/` through `GameState.start_new_game`, then `assert_eq(GameState.placement_errors(), [])`.
  - `test_overlapping_placement_reported`: a scenario dict with two ships whose sterns share a hex. `placement_errors().size() == 1`.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement** `placement_errors()`. Call it at the end of `start_new_game` and `push_error` each message. Use the same `map_bounds` convention as `DriftResolver._in_bounds`, moved into `Occupancy.in_bounds(hex, scenario) -> bool` and called by both. Fix any scenario JSON the test flags.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: scenarios are checked for overlapping or off-map ship footprints`

### Task 3: Turning pivots on the bow (5.C.2)

Today a turn moves the ship into the neighbour hex in the new direction. Under the rules the bow stays in its hex and the stern swings. The turn costs 1 MP, as now.

**Files:**
- Modify: `scripts/server/movement_types.gd` (`MoveMetadata`)
- Modify: `scripts/server/movement_validator.gd` (`_add_pivot_options`, path replay, `_build_plotting_state`)
- Modify: `scripts/server/movement_plotting_controller.gd:162`, `scripts/server/movement_plotting_session.gd:73` (store the resulting bow hex)
- Modify: `scripts/server/stub_ai.gd` (`_strategy_engage`, `_strategy_forward`: score `metadata.resulting_hex`)
- Test: `test/unit/test_movement_validator.gd`, `test/unit/test_movement_tacking.gd`, `test/unit/test_stub_ai.gd`

**Interfaces:**
- Produces:
  - `MoveMetadata.resulting_hex: Vector2i`: the bow hex after the step.
  - `ValidMove.hex` stays the **click target**. For a turn it is `get_neighbor(bow, new_facing)`, the hex the bow will point at, so port and starboard keep distinct click targets.
  - `PlotStep.hex` and the stored plot step `{"hex": ...}` are the **resulting bow hex**. For a turn that is the unchanged bow hex.
  - New stern hex after a turn: `HexGrid.stern_of(resulting_hex, new_facing)`. The resolver (Task 4) treats it as the hex the turn enters.
- Validator: a turn is offered only if the new stern hex is in bounds (`Occupancy.in_bounds`).

- [ ] **Step 1: Write the failing tests:**
  - `test_turn_keeps_bow_hex`: a ship at (5,5) facing 0 turns starboard. `valid.starboard.metadata.resulting_hex == Vector2i(5,5)`, `resulting_facing == 1`, and the click target `valid.starboard.hex == Vector2i(5,6)`.
  - `test_plot_step_stores_bow_hex`: after `select_hex` on the starboard target, the session's last `PlotStep.hex == Vector2i(5,5)` and `facing == 1`.
  - `test_turn_refused_when_stern_off_map`: with the bow on the map edge, a turn whose new stern lies outside `map_bounds` is not offered.
  - Update `test_turn_at_ma_zero_ends_the_move` and the tacking tests that build paths, so turn steps use the unchanged bow hex.
- [ ] **Step 2: Run `make test`.** Expected: the new tests fail.
- [ ] **Step 3: Implement.** The validator's replay must keep `current_hex` unchanged on turn steps. `forward_hexes_since_last_pivot` is unchanged, and pivot MA costs are unchanged. The plotting controller looks up the selected `ValidMove` by click target and stores `metadata.resulting_hex`.
- [ ] **Step 4: Run `make test`.** Expected: PASS, after updating fixtures that relied on turns moving the ship.
- [ ] **Step 5: Commit:** `feat: turns pivot on the bow hex; the stern swings (5.C.2)`

### Task 4: Movement conflicts with two-hex footprints

Phase 1 conflict model. Each step **enters** exactly one hex:
- an ahead move enters the new bow hex;
- a turn enters the new stern hex.

Rules:
- Bow entering a hex held by a stopped ship's bow or stern: bear off or collide, as now.
- Bows entering the same hex: contested (6.C.2–6.C.4), as now.
- A swinging stern entering a hex held or entered by another ship: the turn is cancelled and the ship stops where it was (`STERN_BLOCKED`). This is 6.B.4a/b's outcome without the one-segment overlap allowance, which comes in Task 10.

**Files:**
- Modify: `scripts/server/movement_resolver.gd`:
  - `_resolve_impulse`: classify each intended move as bow-entry or stern-entry.
  - `_find_stationary_occupant`: use footprints.
  - `_apply_move`: track facings.
  - `current_hexes` remains bow positions; add `current_facings: Dictionary`.
- Modify: `scripts/server/movement_types.gd`: `ResolutionEventType.STERN_BLOCKED`; `ResolutionEvent.from_facing: int`.
- Modify: `scripts/server/movement_resolver.gd` `log_outcomes` / `stop_cause`: name the blocking ship for `STERN_BLOCKED`.
- Test: `test/unit/test_movement_resolver.gd`, `test/unit/test_movement_log.gd`

**Interfaces:**
- Consumes: `Occupancy.from_positions`, `HexGrid.stern_of`, `MoveMetadata.resulting_hex` (via plot steps)
- Produces:
  - `MovementResolver._entered_hex(bow: Vector2i, facing: int, step_hex: Vector2i, step_facing: int) -> Vector2i`
  - Event `STERN_BLOCKED` with `detail = "stern blocked by <ship_id>"`.

- [ ] **Step 1: Write the failing tests:**
  - `test_bow_into_stopped_ships_stern_is_conflict`: A sails ahead into B's stern hex. B is stopped. A gets `BEARING_OFF_ROLL` or `COLLISION` with blocker B.
  - `test_two_bows_same_hex_contested`: unchanged expectation, using footprints.
  - `test_stern_swing_into_occupied_hex_cancels_turn`: A at (5,5) facing 0 plots a starboard turn to facing 1, so its new stern is `stern_of((5,5), 1) == (5,4)`. Ship B sits on (5,4). A ends at its start bow and facing, with a `STERN_BLOCKED` event and no `COLLISION`.
  - `test_side_by_side_turn_away_blocked_in_phase_1` (Review Focus 2): the Diagram 14 A layout. Pins the Phase 1 outcome (turn cancelled). Task 10 updates it.
  - `test_struck_ship_both_hexes_block`: a struck ship's stern hex blocks an ahead move.
  - `test_moving_through_own_old_stern_is_free`: a ship moving ahead never conflicts with its own previous stern hex.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Build the segment's occupancy from the stopped ships' footprints plus the footprints moving ships keep this segment. A moving ship's old stern hex is released when its bow advances. Group intended entries by entered hex, keeping bow-entries and stern-entries separate. Resolve bow-entries with the existing contest, bear-off and collision code. Resolve stern-entries as cancelled turns whenever the hex is held or also entered by anyone else.
- [ ] **Step 4: Run `make test`.** Expected: PASS. Update fixtures where 1-hex adjacency assumptions changed. Keep each fixture's intent and move ships apart rather than deleting assertions.
- [ ] **Step 5: Commit:** `feat: movement conflicts use bow and stern hexes`

### Task 5: Whole-ship drift with two hexes

**Files:**
- Modify: `scripts/server/drift_resolver.gd`:
  - `_resolve_group`: target = both hexes shifted one hex downwind.
  - `_occupant`: use `Occupancy.build`, excluding the group.
  - `_in_bounds`: delegate to `Occupancy.in_bounds`.
- Test: `test/unit/test_drift_resolver.gd`

**Interfaces:**
- Consumes: `ShipState.occupied_hexes()`, `Occupancy.build`, `Occupancy.in_bounds`
- Produces: none new. The DRIFT event `data["to"]` is still the new bow hex.

- [ ] **Step 1: Write the failing tests:**
  - `test_drift_moves_bow_and_stern`: after drifting, `hex_position == neighbor(bow, downwind)` and `stern_hex() == neighbor(stern, downwind)`.
  - `test_drift_blocked_by_ship_at_stern_target`: a ship sitting on the stern's downwind hex blocks the drift (`data["blocked"] == "ship"`).
  - `test_drift_blocked_when_stern_leaves_map`: blocked with `"map edge"`.
  - `test_fouled_pair_drifts_as_four_hexes`: a pair is blocked if any of the four target hexes is held by a third ship. The partners' own hexes do not block each other.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Keep the dice order unchanged: drift roll, then the fouling roll.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: drift moves and blocks both hexes`

### Task 6: Gunnery geometry for two-hex ships (whole broadside)

In Phase 1 each side still fires as one order, now judged per battery hex:
- A battery (bow hex or stern hex) **bears** on a target if at least one target hex is in its arc, with a clear LOS to every target hex in its arc (7.B.2, 7.B.5, 7.B.6).
- The side may fire if at least one battery bears.
- If only one battery bears, the shot is a half broadside: −8 (7.C.12f).
- Range is the shortest distance between any firer hex and any target hex (7.C.4).
- Rake (7.E.2): range ≤ 5, and either:
  - the firer's bow or stern hex is not in any of the target's four battery arcs; or
  - one of the firer's hexes is directly ahead of or astern of the target, and adjacent to it.
  - Stern rake if the firer is on the stern side of the target's beam line, otherwise bow rake.

This also fixes the ±30° rake zone that `feature_diff.md` flags.

**Files:**
- Modify: `scripts/core/fire_geometry.gd`
- Modify: `scripts/server/gunnery_calculator.gd`:
  - `preview`: range, arc, LOS and rake from footprints; half-broadside modifier.
  - `_occupied_hexes` → `Occupancy.build`.
- Modify: `data/rules/gunfire_modifiers.json`: add `"half_broadside": -8` if absent. Run `validate_combat.py`.
- Test: `test/unit/test_fire_geometry.gd`, `test/unit/test_gunnery_calculator.gd`

**Interfaces:**
- Consumes: `ShipState.occupied_hexes()`, `Occupancy.build`
- Produces:
  - `FireGeometry.range_between(a: Array[Vector2i], b: Array[Vector2i]) -> int`
  - `FireGeometry.battery_bears(battery_hex: Vector2i, facing: int, side: int, target_hexes: Array[Vector2i], occupied: Dictionary) -> bool`: `occupied` must already exclude the firer's and target's hexes.
  - `FireGeometry.rake_type_ships(target_bow: Vector2i, target_facing: int, firer_hexes: Array[Vector2i]) -> String`: `"bow"`, `"stern"` or `""`. Replaces `rake_type`.
  - `ShotPreview.batteries: int`: 1 or 2. 1 adds the `half_broadside` modifier.

- [ ] **Step 1: Write the failing tests:**
  - `test_range_is_closest_hexes`: the firer's stern is 3 from the target's bow and the other pairs are farther, so the range is 3.
  - `test_target_own_stern_does_not_block`: an LOS from the firer to the target's far hex passes through the target's near hex and is still clear.
  - `test_firers_own_hex_does_not_block`
  - `test_partial_target_only_in_arc_hexes_need_los` (Diagram 17 ship E): the bow battery may fire although the target's other hex is outside its arc and its LOS is blocked.
  - `test_one_battery_bears_gives_half_broadside`: `preview.batteries == 1`, and the modifiers include `half_broadside: -8`.
  - `test_rake_zone_is_outside_all_arcs`: a firer 45° off the target's bow line at range 3 is a bow rake. It was not with the old ±30° test.
  - `test_adjacent_dead_ahead_is_rake`: firer bow hex adjacent and directly ahead of the target's bow, so `"bow"`.
  - `test_struck_ship_blocks_los_with_both_hexes`
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Keep `bearing_side` as the arc test for a single battery hex. `broadside_hexes` (used to draw arcs) gains a `battery_hex` argument; callers pass the bow and the stern and take the union.
- [ ] **Step 4: Run `make test` and `python3 .claude/skills/validate-rule-table/scripts/validate_combat.py`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: gunnery range, arcs, LOS and rakes from both hexes; half broadside`

### Task 7: Two-hex presentation

**Files:**
- Modify: `scripts/view/ship_view.gd`:
  - `_update_position_from_state`: use `HexGrid.ship_center_world(bow, facing)`, so the model sits between bow and stern. The old 2-hex branch pointed toward the bow; remove it.
  - `_create_ship_model`: build the 2-hex model.
  - `_add_click_collision`: cover both hexes.
- Modify: `scripts/view/movement_resolution_playback_controller.gd:133` `_animate_moves`: interpolate `ship_center_world(from_hex, from_facing)` → `ship_center_world(to_hex, facing)`. A turn swings about the bow hex.
- Modify: `scripts/view/hex_overlay.gd`:
  - `show_arc`: union of the bow and stern battery hexes.
  - Plotted path: draw each step's bow hex.
- Modify: `scripts/view/ship_indicator_model.gd`: anchors from the bow hex (direction) and the ship centre (windward).
- Modify: `scripts/core/game_controller.gd`:
  - Hex picking that maps a clicked hex to a ship uses `Occupancy.build` and selects on either hex.
  - Blocked-hex marking (`blocked_hexes_for`) uses click targets.
- Modify: `scripts/ui/ship_status_overlay.gd`: anchor beside the ship centre.
- Test: `test/unit/test_ship_view_owner_marker.gd`, `test/unit/test_playback_controller.gd`, `test/unit/test_ship_indicator_model.gd`, `test/unit/test_fire_geometry.gd` (arc union; there is no hex overlay test file)

**Interfaces:**
- Consumes: `HexGrid.ship_center_world`, `Occupancy.build`, `ResolutionEvent.from_facing` (Task 4)
- Produces:
  - `GameController.ship_at_hex(hex: Vector2i) -> String` (static or instance, pure): the ship_id, or `""`.

- [ ] **Step 1: Write the failing tests:**
  - `test_ship_view_sits_between_bow_and_stern`: `view.position` x/z equals `ship_center_world`.
  - `test_ship_at_hex_matches_stern` (Review Focus 3): `ship_at_hex(stern) == id`.
  - `test_playback_turn_keeps_bow_hex`: after a turn event, the view's final centre is `ship_center_world(bow, new_facing)`.
  - `test_arc_hexes_union_of_batteries`
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Use the existing `_create_2hex_model` as the starting point.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Check in the running game.** Start `res://scenes/main_game.tscn` through the godot-mcp `run_project`. Click with window pixels (unproject × root scale, see CLAUDE.md) and check each of these:
  1. Clicking a stern hex selects the ship.
  2. Plotting a turn shows the stern swing and offers distinct click targets for port and starboard.
  3. Fire arcs cover both batteries.
  4. `game_get_errors` returns 0.
- [ ] **Step 6: Commit:** `feat: two-hex ship models, picking, playback and arcs`

### Task 8: Stub AI on footprints

**Files:**
- Modify: `scripts/server/stub_ai.gd`:
  - `_strategy_engage`: build occupancy with `Occupancy.build`.
  - `_score_position(hex, facing, enemy, occupied)`: score through `GameState.gunnery_calculator` geometry (range_between, battery_bears) instead of single-hex LOS.
- Test: `test/unit/test_stub_ai.gd`

**Interfaces:**
- Consumes: `Occupancy.build`, `FireGeometry.range_between`, `FireGeometry.battery_bears`, `MoveMetadata.resulting_hex`
- Produces: `_score_position(bow: Vector2i, facing: int, enemy: ShipState, occupied: Dictionary) -> int`. The signature changes from enemy hex to enemy ship.

- [ ] **Step 1: Write the failing tests:**
  - `test_ai_scores_broadside_against_two_hex_enemy`: a position with both batteries bearing outscores one with a single battery bearing.
  - `test_ai_never_plots_stern_into_occupied_hex`: an AI ship side by side with a friend does not choose a turn whose stern enters the friend's hex.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: stub AI plans with two-hex footprints`

### Task 9: Phase 1 close-out

**Files:**
- Modify: `CLAUDE.md`:
  - Hex Grid: replace "All ships are 1-hex" with the bow/stern model, `Occupancy`, and the turn click-target vs resulting-hex rule.
  - Legacy Code: drop the `size == 2` note.
- Modify: `docs/rules/feature_diff.md` §4: move per-hex LOS, range, rake and half broadside out of "deliberate simplifications".

- [ ] **Step 1: Run `make test`.** Expected: `All tests passed`.
- [ ] **Step 2:** Play one full turn of `test_fleet` in the running game: movement, combat, drift and morale. `game_get_errors` returns 0.
- [ ] **Step 3:** Run the `scv-reviewer` agent and fix any violations.
- [ ] **Step 4: Commit:** `docs: two-hex ships in CLAUDE.md and the feature diff`

---

## Phase 2: Close quarters

### Task 10: Temporary overlap when a stern swings (6.B.2–6.B.4)

A stern may swing into a hex held or being entered by another ship, provided that one of the two ships vacates it on the **next segment** of the same g-t. If the overlap is still there after that segment, roll back:
- **Already occupied (6.B.4a):** the turning ship returns to the position before the overlap and stops. If that breaks its deceleration minimum, it moves ahead the minimum needed, which may make it a bow-entry conflict resolved by Task 4's code.
- **Bow vs stern (6.B.4b):** a moving bow always beats a swinging stern. The turning ship's move from the overlap onward is invalid, and its plot is amended to stop at the position before the overlap. There is no collision.
- **Sterns turning together (6.B.4c):** contested hex, no collision, and movement ends for both. This is folded into Task 11.

**Files:**
- Modify: `scripts/server/movement_resolver.gd`:
  - Pending overlaps: `ship_id → {hex, other_id, segment, pre_bow, pre_facing}`, checked at the end of the next segment.
  - Rollback restores `current_hexes`/`current_facings` and amends `results[sid]`.
- Modify: `scripts/server/movement_types.gd`: `ResolutionEventType.OVERLAP` and `OVERLAP_ROLLBACK`.
- Modify: `scripts/view/movement_resolution_playback_controller.gd`: play a rollback as the ship swinging back.
- Test: `test/unit/test_movement_resolver.gd`

**Interfaces:**
- Consumes: Task 4's entry classification.
- Produces: events `OVERLAP` (detail `"overlaps <id>"`) and `OVERLAP_ROLLBACK` (detail `"already occupied"` or `"bow precedence"`).

- [ ] **Step 1: Write the failing tests.** Lay out each from the matching position in Diagram 14:
  - `test_turn_away_from_adjacent_ship_allowed` (A): ship 1 plots P1 and ship 2 is stopped. Ship 1 ends at P1, with an `OVERLAP` event and no rollback. Replaces Task 4's pinned Phase 1 test.
  - `test_overlap_not_vacated_rolls_back` (C): both plot S1. Ship 1 returns to its start and stops. Ship 2 gets bear-off-ineligible → `COLLISION`.
  - `test_bow_beats_swinging_stern` (D): ship 2 plots S and ship 1 plots 2. Ship 2's plot is amended to 0, with no collision, and ship 1 completes 2.
  - `test_multiple_overlaps_invalidates_whole_move` (E): ship 1's move is amended to 0.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: temporary overlap and rollback for swinging sterns (6.B)`

### Task 11: Stern-vs-stern contests and complete overlap (6.B.4c, 6.B.5, 6.C.1b, 6.C.5)

Rules:
- Two sterns turning into the same hex in the same segment, with neither ship having further MPs plotted, is a contested hex. Roll with `_roll_contest` and its existing DRMs (6.C.2). The loser's turn is cancelled. There is never a collision.
- Complete overlap (6.B.5): two ships turn so each occupies the other's hexes. Contest. The winner chooses which ship turns; the stub rule is that the winner turns. The loser stops, subject to its deceleration minimum.

**Files:**
- Modify: `scripts/server/movement_resolver.gd` (stern-entry grouping from Task 4)
- Test: `test/unit/test_movement_resolver.gd`

**Interfaces:**
- Consumes: `_roll_contest(contesting_ids, impulse, ship_map, results) -> String`
- Produces: none new.

- [ ] **Step 1: Write the failing tests:**
  - `test_stern_vs_stern_contest_no_collision` (Diagram 14 B): exactly one ship turns, and neither result has `COLLISION`.
  - `test_complete_overlap_one_ship_turns` (Diagram 14 F)
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: stern-vs-stern contested hexes (6.C.5)`

### Task 12: Partial drift (8.A.5)

If only the bow or only the stern can drift, that end drifts and the other stays. The ship pivots and its wind facing changes. Roll on the Collision table for fouling with the blocking ship, with no extra rigging lost. Fouled and grappled ships never partially drift.

**Files:**
- Modify: `scripts/server/drift_resolver.gd` (`_resolve_group`)
- Modify: `scripts/server/phase_events.gd`: DRIFT data gains `"partial": "bow" | "stern"` and `"facing"`.
- Modify: `scripts/server/ship_state_controller.gd`: use the existing `set_ship_position`/`set_ship_facing`.
- Test: `test/unit/test_drift_resolver.gd`

**Interfaces:**
- Produces: `DriftResolver._partial_drift(ship: ShipState, free_end: String, downwind_dir: int) -> Dictionary`: returns `{bow, facing}`. The result must still be a legal 2-hex placement pointing at another hex (5.A.2c). If no legal placement exists, the ship does not drift.

- [ ] **Step 1: Write the failing tests:**
  - `test_partial_drift_stern_free`: bow blocked downwind, stern free. The stern moves one hex downwind, the bow hex is unchanged, the facing changes by one step, `data["partial"] == "stern"`, and a fouling roll is made.
  - `test_fouled_ship_never_partially_drifts`
  - `test_partial_drift_never_lies_on_hex_spine`: if no legal footprint exists, `data["drifted"] == false`.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.** Work the pivot out geometrically: the free end moves one hex downwind. The new facing is the direction from the new stern to the bow, or from the stern to the new bow. Accept the move only if the two hexes are neighbours.
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: partial drift pivots a blocked ship (8.A.5)`
- [ ] **Step 6:** Phase 2 close-out:
  1. Run `make test` and play one turn with ships side by side in the running game. Expect 0 errors.
  2. Run the `scv-reviewer` agent.
  3. Update `feature_diff.md` §4.
  4. Commit: `docs: feature diff after close-quarters rules`

---

## Phase 3: Batteries

### Task 13: Battery fire orders (7.B.1, 7.C.12f)

Each side has a bow battery and a stern battery:
- An order names `battery`:
  - `"full"`: both batteries at one target; both must bear.
  - `"bow"` or `"stern"`: a half broadside, −8.
- Each battery may be in at most one order.
- A ship may fire at no more than two different targets in total (7.A.4). The two-target modifier (−12, the chart value) applies to every order when the ship's orders name two targets.
- Gun factors are the full broadside's in every case. The −8 is the only half-broadside penalty, as on the ship log's BGN track.
- The initial-broadside bonus (7.C.10) stays per side: used when any battery on that side first fires.

**Files:**
- Modify: `scripts/server/gunnery_types.gd`: `FireOrder.battery: String = "full"`, serialized in `to_dict`/`from_dict`.
- Modify: `scripts/server/gunnery_calculator.gd`:
  - `preview`: uses the named battery or batteries.
  - `validate_orders`: no battery twice; at most two targets.
  - `eligible_shots`: one `ShotPreview` per bearing battery combination.
- Modify: `scripts/server/gunnery_resolver.gd`: shot identity includes the battery.
- Modify: `scripts/server/stub_ai.gd` `choose_fire_orders`: prefer `"full"` and fall back to the best single battery.
- Test: `test/unit/test_gunnery_calculator.gd`, `test/unit/test_gunnery_resolver.gd`, `test/unit/test_stub_ai.gd`

**Interfaces:**
- Consumes: `FireGeometry.battery_bears` (Task 6)
- Produces:
  - `FireOrder.battery`: `"full" | "bow" | "stern"`.
  - `GunneryCalculator.validate_orders` rejection strings `"battery fired twice"` and `"more than two targets"`.
  - Task 6's automatic half broadside is replaced by the explicit battery.

- [ ] **Step 1: Write the failing tests:**
  - `test_full_requires_both_batteries`
  - `test_bow_battery_alone_is_half_broadside`: modifiers include `half_broadside: -8`.
  - `test_split_side_two_targets`: bow at X and stern at Y. Both are valid, and both carry −8 and the two-target modifier.
  - `test_three_targets_refused`
  - `test_battery_used_twice_refused`
  - `test_old_orders_default_full`: `FireOrder.from_dict` without a `battery` key gives `"full"`.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat: bow and stern battery fire orders (7.B.1)`

### Task 14: Fire declaration panel by battery

**Files:**
- Modify: `scripts/ui/fire_declaration_panel.gd`: for each side, offer "Full broadside" when both batteries bear, otherwise "Bow battery" or "Stern battery". The breakdown text shows the −8. Static helpers stay pure and testable.
- Modify: `scripts/view/hex_overlay.gd`: highlight the chosen battery's arc.
- Test: `test/unit/test_fire_declaration_panel.gd`

**Interfaces:**
- Consumes: `FireOrder.battery`, `GunneryCalculator.eligible_shots`
- Produces:
  - `FireDeclarationPanel.battery_label(battery: String) -> String`: `"Full broadside"`, `"Bow battery"` or `"Stern battery"`.
  - `FireDeclarationPanel.battery_options(previews: Array) -> Array[String]`

- [ ] **Step 1: Write the failing tests:**
  - `test_battery_label_text`
  - `test_options_offer_full_only_when_both_bear`
  - `test_breakdown_shows_half_broadside`: the text contains `"Half broadside −8"`.
- [ ] **Step 2: Run `make test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `make test`.** Expected: PASS.
- [ ] **Step 5: Check in the running game.** Declare a bow-battery shot at a ship that only the bow arc covers. Expect the shot resolved in the combat log and 0 errors.
- [ ] **Step 6: Commit:** `feat: fire panel declares by battery`
- [ ] **Step 7:** Phase 3 close-out:
  1. Run `make test`.
  2. Run the `scv-reviewer` agent.
  3. Update `feature_diff.md` §1, §3 and §4: batteries, half broadside and partial targets are done.
  4. Update CLAUDE.md "Sides, Arcs and Rake".
  5. Commit.

---

## Out of scope

These are rules that become possible once ships are two hexes, but each is its own feature:
- friendly-ship blocking hexes (7.B.10–12);
- anchoring with springs (13.D);
- towing (12);
- boarding and grappling geometry (8.C, 10).
