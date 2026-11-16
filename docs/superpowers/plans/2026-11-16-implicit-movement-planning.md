# Implicit Movement Planning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-ship Movement mode with always-on course editing. Every own ship's course and next hexes are on the map, a click extends or cuts a course, End Planning is always available, and Cancel resets the turn's orders. Unplotted ships follow rule 6.G.2.

**Architecture:** Every own ship always has a stored course (`plotted_actions.movement`). A new pure `DefaultCourse` gives the 6.G.2 course, which is stored at PLANNING start and used by the resolver for any ship with no plot. Two stateless server requests on `TurnPhaseController` (`player_extend_course`, `player_cut_course`) validate each click with the existing `MovementValidator` and store the result, and one read-only query (`course_options`) feeds the view. A per-ship start-of-turn snapshot on `TurnPhaseController` backs `player_reset_planning`. In the view, `MovementPlottingClient` is dropped. `GameController` draws every course from the stored plots and routes clicks through a pure `CourseClicks.route`.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5 (`make test`).

**Spec:** `docs/superpowers/specs/2026-11-16-implicit-movement-planning-design.md`. Read it before starting a task.

## Global Constraints

- Server authority (CLAUDE.md "Server Authority"): view code (`scripts/ui`, `scripts/view`, `scripts/core`) never writes `ShipState` and never calls a `ShipStateController` mutator. Every edit is a `TurnPhaseController.player_*` request returning `""` or a reason. `test_server_authority.gd` must pass.
- Runtime logging goes through `Trace`, never `print()`. A hook blocks raw `print`.
- Rolls go through `game_state.dice`. This feature needs no new rolls.
- `make test` after every task, with zero failures. The auto-test hook runs it after edits under `scripts/server|state|core|autoload` and `test/unit`.
- Rule 6.G.2 wording to cite in comments: "ahead at the same actual speed as the previous g-t … or the speed closest to it that it can legally reach".
- Default course length: `min(ShipState.speed, movement allowance)`, ahead steps only, stopping early if the validator offers no ahead move. The MA wins over the 5.A.4 deceleration minimum.
- Click rules (spec, user decisions):
  - Course wins over ships.
  - A turn step is drawn and clicked on the bow hex it keeps.
  - A cut removes the clicked step and all later ones. Where several steps share a hex, cut at the latest one.
  - At a course's end, a valid next hex beats a course hex of the same ship.
  - On overlap between ships: the selected ship wins. Otherwise the ship whose course end is nearest the hex (hex distance) wins. Ties go to the lower ship_id.
- Cancel copy: "Reset all orders for this turn? Courses, crew, sail and boarding orders go back to how they were at the start of the turn." Buttons: **Reset** and **Keep orders**.
- Instructions copy: "Click a ship's highlighted hexes to plot its course. Click a hex on its course to cut it back."
- Remove the Movement button, the shared plotting box, per-ship Submit/Cancel, `submitted_ships`, ✓ marks and "(orders given)".
- End Planning is always enabled in PLANNING until the plan is submitted, with no "(n/N)".

## Review Focus

1. **A ship that cannot plot at planning start** (fouled, grappled, struck, dismasted, a prize): it gets no stored course and no hexes, and clicks never reach it. Covered in Task 3's `test_planning_start_skips_ships_that_cannot_plot` and Task 4's routing tests (a ship with no options is never routed to).
2. **Two own ships whose hexes overlap, neither selected:** the click goes to the nearer course end, and the other ship's course is untouched. Covered in Task 4's `test_overlap_without_selection_goes_to_nearest_course_end`.
3. **Clicking the next ahead hex right after a turn:** it must extend the course, not cut the turn. Covered in Task 4's `test_hex_ahead_after_a_turn_extends`.
4. **Cancel after the crew overlay changed Automatic and the boarding order:** both go back to their start-of-turn values. A sail change already in progress is untouched. Covered in Task 3's `test_reset_restores_auto_and_boarding_and_keeps_tasks_in_progress`.
5. **End Planning with a ship never touched:** that ship moves on its 6.G.2 course, not zero. Covered in Task 1's resolver test and Task 3's planning-start test.

---

### Task 1: 6.G.2 default course and the resolver fallback

**Files:**
- Create: `scripts/server/default_course.gd`
- Modify:
  - `scripts/state/ship_state.gd` (`empty_plot`)
  - `scripts/server/ship_state_controller.gd` (`set_plotted_movement`)
  - `scripts/server/movement_resolver.gd` (`_get_plotted_steps` ~1658, `SKIP_NO_PLOT` branch ~273)
  - `docs/rules/feature_diff.md` (row 6.G.2)
- Test: `test/unit/test_default_course.gd` (new); `test/unit/test_movement_resolver.gd`

**Interfaces:**
- Produces:
  - `DefaultCourse.for_ship(game_state: Node, ship: ShipState) -> Array[MovementTypes.PlotStep]` (static, pure). Empty when MA is 0 or speed is 0. Returns `[]` for a ship that cannot plot (`DefaultCourse.can_plot(ship) == false`).
  - `DefaultCourse.can_plot(ship: ShipState) -> bool` (static). False if captured, fouled, grappled, destroyed, struck or dismasted. These are the same refusals as `MovementPlottingController.handle_start_plotting` lines 76-87; make that handler call it.
  - `DefaultCourse.as_dicts(steps: Array) -> Array` (static), giving `PlotStep.to_dict()` per step.
  - `ShipState.empty_plot()` gains `"movement_plotted": false`. `ShipStateController.set_plotted_movement` sets it `true`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_default_course.gd`. Build a ship the way `test_movement_validator.gd` does: a fixture ship on open water, wind giving MA 4.
  - `test_default_course_keeps_last_speed`: speed 3, MA 4. Result has 3 steps, all `MoveType.FORWARD`, each `hex` one step further along the facing from the bow, facing unchanged.
  - `test_default_course_capped_by_movement_allowance`: speed 6, MA 4. 4 steps.
  - `test_default_course_empty_at_ma_zero`: the ship faces into the wind (WF L). `[]`.
  - `test_default_course_empty_at_speed_zero`: speed 0. `[]`.
  - `test_default_course_none_for_a_ship_that_cannot_plot`: `fouled_with = "x"`. `[]`, and `can_plot` is false.
  - `test_set_plotted_movement_marks_the_plot`: `set_plotted_movement(id, [])` makes `plotted_actions.movement_plotted` true. `empty_plot()` has it false.
- [ ] **Step 2:** Add to `test_movement_resolver.gd`:
  - `test_unplotted_ship_moves_on_its_6g2_course`: speed 2, nothing plotted. The ship ends 2 hexes ahead, and there is no `SKIP_NO_PLOT` event.
  - `test_explicit_empty_plot_holds_position`: `set_plotted_movement(id, [])`. The ship stays put.
- [ ] **Step 3:** Run `make test`. Expected: the new tests FAIL (DefaultCourse is undefined).
- [ ] **Step 4: Implement `DefaultCourse`.** Loop up to `n = min(ship.speed, game_state.ship_controller.get_movement_allowance(ship.ship_id))` times:
  - call `MovementValidator.new(game_state).calculate_valid_moves(ship, cur_hex, cur_facing, path)`;
  - take the `forward` move whose `metadata.resulting_hex` is `HexGrid` neighbour of `cur_hex` in `cur_facing`;
  - stop if there is none.

  Comment the 6.G.2 wording and the two planner's calls from the spec (actual speed, MA wins over deceleration).
- [ ] **Step 5: Resolver.** In `_get_plotted_steps`, when `movement` is empty and `movement_plotted` is false, return `DefaultCourse.as_dicts(DefaultCourse.for_ship(game_state, ship_state))`. Drop the `SKIP_NO_PLOT` event in the branch near line 279, but keep the enum value (`MovementTypes`, playback) unless nothing else uses it. Grep `SKIP_NO_PLOT` in `scripts/view/movement_resolution_playback_controller.gd` and `test_playback_controller.gd`.
- [ ] **Step 6:** Run `make test`. Fix every test that relied on an unplotted ship staying put by plotting `set_plotted_movement(id, [])` in that test. Expected: all PASS.
- [ ] **Step 7:** Update the `feature_diff.md` row 6.G.2 to "as the rules". Note the actual-speed and MA-over-deceleration calls, and the new file reference. Commit: `feat(movement): 6.G.2 default course for unplotted ships`.

### Task 2: Course editing requests

**Files:**
- Modify: `scripts/server/turn_phase_controller.gd` (next to `player_clear_movement` ~213)
- Test: `test/unit/test_course_requests.gd` (new)

**Interfaces:**
- Consumes: `DefaultCourse.can_plot` (Task 1); `MovementValidator.validate_hex_selection(ship, cur_hex, cur_facing, hex, path)` and `calculate_valid_moves(...)`; `ShipStateController.set_plotted_movement`.
- Produces on `TurnPhaseController`:
  - `player_extend_course(player_id: int, ship_id: String, hex: Vector2i) -> String`. Validates as SELECT_HEX does (`movement_plotting_controller.gd:172-195`): the stored step is `PlotStep(validation.metadata.resulting_hex, validation.new_facing, move_type)`. Then it stores the course.
  - `player_cut_course(player_id: int, ship_id: String, step_index: int) -> String`. Keeps steps `[0, step_index)` and stores them. `step_index` must be in `[0, size]`; otherwise it returns a reason.
  - `course_options(ship_id: String) -> Dictionary`, read-only:
    - `{path: Array[PlotStep], valid_next: MovementTypes.ValidNextHexes, remaining_ma: int, is_tacking_attempt: bool, rudder_error: String}`
    - `{}` when the ship cannot plot.
  - `_course_request_error(player_id, ship_id) -> String`: the `_crew_request_error` checks (phase, ready, owner) plus `DefaultCourse.can_plot`.
  - Helper `stored_course(ship: ShipState) -> Array[PlotStep]`, built with `PlotStep.from_dict` from `plotted_actions.movement`.

- [ ] **Step 1: Write the failing tests.** Use a PLANNING setup with `players_ready = [false, false]`, as `test_turn_phase_controller.gd` does.
  - `test_extend_appends_a_valid_move_and_stores_it`
  - `test_extend_refuses_an_invalid_hex_and_keeps_the_course`: non-"" result, course unchanged.
  - `test_extend_refused_outside_planning_after_ready_or_for_another_players_ship`: three asserts.
  - `test_extend_refused_for_a_fouled_ship`
  - `test_cut_at_last_step_removes_one_step`
  - `test_cut_at_zero_clears_the_course`: `movement` is `[]` and `movement_plotted` is true.
  - `test_cut_out_of_range_is_refused`
  - `test_extend_after_a_turn_continues_from_the_new_facing`: plot a turn, then the hex ahead in the new facing. 2 steps.
  - `test_course_options_lists_next_hexes_from_the_course_end`
- [ ] **Step 2:** Run `make test`. Expected: FAIL (methods undefined).
- [ ] **Step 3:** Implement the four methods. Current hex and facing come from the last stored step, else the ship's `hex_position` and `facing`. No session objects are created.
- [ ] **Step 4:** Run `make test`. Expected: PASS. Commit: `feat(movement): stateless course extend/cut requests`.

### Task 3: Planning start defaults, snapshot and reset

**Files:**
- Modify:
  - `scripts/server/turn_phase_controller.gd` (`_enter_planning_phase` ~165, `_enter_end_turn_phase` ~800, new vars)
  - `scripts/autoload/game_state.gd` (`start_scenario` ~179-197)
- Test: `test/unit/test_planning_reset.gd` (new)

**Interfaces:**
- Consumes: `DefaultCourse.for_ship` / `as_dicts` (Task 1); `ShipStateController.clear_crew_plot`, `set_crew_auto`, `set_crew_orders`.
- Produces:
  - `TurnPhaseController.human_player_ids: Array[int]`, set by `GameState.start_scenario` next to `bear_off_prompt_player_ids`.
  - `TurnPhaseController.planning_snapshot: Dictionary`: ship_id → `{course: Array (dicts), crew_auto: bool, boarding: String}`.
  - `TurnPhaseController.player_reset_planning(player_id: int) -> String`.
  - `TurnPhaseController.start_of_turn_course(ship_id: String) -> Array` (read-only; Reset course uses it).
  - `TurnPhaseController.player_reset_course(player_id: int, ship_id: String) -> String`: the card's Reset course button; restores that ship's snapshot course only.

- [ ] **Step 1: Write the failing tests.** Set `human_player_ids = [0]` in the setup.
  - `test_planning_start_stores_the_default_course_for_human_ships`: speed 2. 2 stored steps, `movement_plotted` true. The snapshot course is equal.
  - `test_planning_start_skips_ships_that_cannot_plot`: a fouled ship. Movement stays `[]`, `movement_plotted` is false, and the snapshot has `course == []`.
  - `test_planning_start_leaves_ai_ships_alone`: a ship of player 1 is not given a stored course by this step.
  - `test_reset_restores_course_crew_and_sail`:
    - setup: extend the course, plot a crew plan, order a sail change;
    - call `player_reset_planning(0)`;
    - expect: the course equals the snapshot, `crew_plotted` is false, `sail_target` is "".
  - `test_reset_restores_auto_and_boarding_and_keeps_tasks_in_progress`:
    - setup: `crew_auto` true at start, set false; boarding "" at start, set "ready"; give a SAIL task in progress (`CrewFixtures.give_sail_change`);
    - call `player_reset_planning(0)`;
    - expect: auto is true, boarding is "", and the task is still live.
  - `test_reset_refused_after_ready_and_outside_planning`
  - `test_reset_course_restores_one_ship_only`
  - `test_snapshot_cleared_at_end_turn`
- [ ] **Step 2:** Run `make test`. Expected: FAIL.
- [ ] **Step 3:** Implement. In `_enter_planning_phase`, before `stub_ai.plot_all_ai_ships()`: for each ship whose `player_id` is in `human_player_ids`:
  - if `DefaultCourse.can_plot`, store its default course;
  - always record the snapshot.

  Then implement `player_reset_planning`. It checks phase, ready and player. For each of the player's ships in the snapshot:
  - `set_plotted_movement(course)`;
  - `clear_crew_plot`;
  - `set_crew_auto(snapshot)`;
  - `set_crew_orders` with the boarding order from the snapshot. Use the existing setter; check its signature at `ship_state_controller.gd:496`.

  Clear `planning_snapshot` in `_enter_end_turn_phase`.
- [ ] **Step 4:** Run `make test`. Expected: PASS. Commit: `feat(planning): default courses at planning start and a planning reset`.

### Task 4: Click routing helper and per-ship overlay layers

**Files:**
- Create: `scripts/ui/course_clicks.gd`
- Modify: `scripts/view/hex_overlay.gd`
- Test: `test/unit/test_course_clicks.gd` (new); `test/unit/test_hex_overlay.gd` (or the existing overlay test file; find it with `grep -l HexOverlay test/unit`)

**Interfaces:**
- Produces:
  - `CourseClicks.route(hex: Vector2i, courses: Dictionary, selected_id: String) -> Dictionary` (static, pure).
    - `courses` maps ship_id → `{path_hexes: Array[Vector2i] (one per step, the step's PlotStep.hex), next_hexes: Array[Vector2i] (ValidMove.hex click targets), end_hex: Vector2i}`.
    - Returns `{}` (no course claims the hex), or `{ship_id, kind: "extend" | "cut", step_index: int}`. For `"extend"`, `step_index` is -1.
  - `HexOverlay.show_course(ship_id: String, path_hexes: Array[Vector2i], next_hexes: Array[Vector2i], collision_hexes: Array[Vector2i], hex_grid: HexGrid, selected: bool) -> void`
  - `HexOverlay.clear_course(ship_id: String) -> void`
  - `HexOverlay.clear_courses() -> void`
  - `HexOverlay.hex_at_world_pos(world_pos: Vector3, hex_grid: HexGrid) -> Vector2i`: any hex, not only valid ones, so routing can decide.
  - Drop the single `_valid_hex_positions`, `valid_hexes_node` / `plotted_path_node` use for planning, and `show_submitted_path` / `submitted_paths_node` once Task 6 stops calling them. Keep `show_blocked_hexes`, arcs and targets.

- [ ] **Step 1: Write the failing routing tests.**
  - `test_valid_next_hex_extends_that_ship`
  - `test_course_hex_cuts_at_that_step`: path `[a, b, c]`; click `b` gives `{kind: "cut", step_index: 1}`.
  - `test_shared_hex_cuts_at_the_latest_step`: path `[a, a(turn)]`; click `a` gives step_index 1.
  - `test_hex_ahead_after_a_turn_extends`: path `[a, a(turn)]`, `next_hexes` has `d`, `d` is not in the path; click `d` extends.
  - `test_course_end_valid_hex_beats_course_hex`: the clicked hex is the same ship's `end_hex` (the last entry of `path_hexes`) and is also in its `next_hexes`. Expect extend.
  - `test_selected_ship_wins_overlap`
  - `test_overlap_without_selection_goes_to_nearest_course_end`
  - `test_overlap_tie_goes_to_lower_ship_id`
  - `test_unclaimed_hex_routes_nowhere`: `{}`.
- [ ] **Step 2: Overlay test.** `test_show_course_keeps_one_layer_per_ship`: two `show_course` calls give two child containers named `Course_<id>`. `clear_course(a)` leaves `b`.
- [ ] **Step 3:** Run `make test`. Expected: FAIL.
- [ ] **Step 4:** Implement.
  - Distance: `HexGrid` axial distance. Find the existing helper, e.g. `HexGrid.distance` or `FireGeometry`.
  - Within one ship, the order is: `next_hexes` hit when the hex is that ship's `end_hex`, then `path_hexes`, then `next_hexes`.
  - The selected ship's layer uses the existing materials. Other ships' layers use the same colours at about half alpha (new materials in `_ready`).
- [ ] **Step 5:** Run `make test`. Expected: PASS. Commit: `feat(ui): course click routing and per-ship course layers`.

### Task 5: Planning panel without the Movement mode

**Files:**
- Modify:
  - `scripts/ui/planning_phase_ui.gd`
  - `scenes/ui/planning_phase_ui.tscn`
  - `scripts/ui/ship_list_item.gd`
  - `scenes/ui/ship_list_item.tscn`
  - `scripts/ui/planning_text.gd` (`instructions`)
- Test: `test/unit/test_planning_phase_ui.gd`, `test/unit/test_planning_text.gd`

**Interfaces:**
- Produces:
  - `PlanningPhaseUI` signals:
    - `ship_selected(ship_id)` (kept)
    - `end_planning_pressed()` (kept)
    - `crew_overlay_requested(ship_id)` (kept)
    - `reset_planning_confirmed()` (new)
    - `reset_course_requested(ship_id)` (new)
  - Removed signals: `action_toggled`, `undo_pressed`, `undo_all_pressed`, `submit_pressed`, `cancel_pressed`.
  - `PlanningPhaseUI.set_course_info(ship_id: String, info: Dictionary) -> void`. `info` is `{used: int, allowance: int, tacking: String, steering: String, collision: String}`; `""` hides a line. It forwards to the card.
  - `ShipListItem.set_course_info(info: Dictionary) -> void`. The expanded card shows a "Course" block under the status box: "Course: %d of %d MP", the three notes when non-empty, and a **Reset course** button that emits `reset_course_pressed()`.
  - `PlanningText.instructions() -> String` (no parameters), returning the instructions copy from Global Constraints.
  - Footer: an **End Planning** button (always enabled while the panel is shown) and a **Cancel** button. Cancel opens a `ConfirmationDialog` with the Cancel copy. Its OK button is "Reset" and its cancel button is "Keep orders". Confirming emits `reset_planning_confirmed`.

- [ ] **Step 1: Update the tests.** Remove the tests that drive `_on_action_button_pressed`, `mark_ship_submitted`, the "✓"/"(orders given)" titles and the (n/N) count. Add:
  - `test_cards_have_no_movement_button`
  - `test_end_planning_is_enabled_with_no_orders_given`
  - `test_cancel_asks_before_resetting`: pressing Cancel shows the dialog and emits nothing. Confirming emits `reset_planning_confirmed` once.
  - `test_course_info_on_the_selected_card`: after `set_course_info("p2", {used: 3, allowance: 5, …})`, the card text contains "Course: 3 of 5 MP".
  - `test_reset_course_button_asks_for_that_ship`
  - `test_instructions_text`
- [ ] **Step 2:** Run `make test`. Expected: FAIL.
- [ ] **Step 3:** Implement. Remove from the scene and script:
  - the Movement button, `PlottingControls` and its labels;
  - `submitted_ships`;
  - `show_plotting_controls` / `hide_plotting_controls` / `_scroll_plotting_into_view`;
  - `update_plotting_state`, `set_allowance_note`, `set_collision_warning`, `update_tacking_state`, `update_steering_state`;
  - `mark_ship_*`, `deactivate_movement_button`;
  - the (n/N) logic.

  Movement-blocked cards keep their badge and tooltip. Style the Course block with `CrewStyle` / theme variations, as the status box is styled.
- [ ] **Step 4:** Run `make test`. Expected: PASS. (GameController is rewired in Task 6. Until then `make test` must still pass; if the scene fails to parse because GameController connects removed signals, do Tasks 5 and 6 in one commit.) Commit: `feat(ui): planning panel without the Movement mode`.

### Task 6: GameController wiring: always-on courses

**Files:**
- Modify: `scripts/core/game_controller.gd`
- Delete: `scripts/ui/movement_plotting_client.gd` (+ `.uid`), once nothing references it
- Test: `test/unit/test_planning_phase_ui.gd` (integration bits) and the new `test/unit/test_course_view.gd` for pure helpers moved out of GameController

**Interfaces:**
- Consumes:
  - `TurnPhaseController.player_extend_course`, `player_cut_course`, `course_options`, `player_reset_planning`, `player_reset_course`, `start_of_turn_course` (Tasks 2-3)
  - `CourseClicks.route` and the `HexOverlay` course API (Task 4)
  - the `PlanningPhaseUI` API (Task 5)
- Produces:
  - `GameController._refresh_courses() -> void`: for every own ship with non-empty `course_options`, it calls `show_course` (selected = `selected_ship_id`), rebuilds `_courses` (the `CourseClicks` input) and `_hover_candidates` per ship, and pushes `set_course_info` for each ship.
  - Pure statics, moved to `scripts/ui/course_view.gd` (`class_name CourseView`) so they can be tested:
    - `course_input(options: Dictionary, ship: ShipState) -> Dictionary`: one `CourseClicks` entry.
    - `course_info(options: Dictionary, ship: ShipState, allowance: int) -> Dictionary`

- [ ] **Step 1: Write the failing tests** in `test_course_view.gd`:
  - `test_course_input_lists_path_and_next_hexes`
  - `test_course_info_counts_mp_used_and_allowance`
- [ ] **Step 2:** Run `make test`. Expected: FAIL.
- [ ] **Step 3:** Rewire `GameController`:
  - `_enter_planning_phase` → `_refresh_courses()`.
  - `_unhandled_input` in PLANNING, before ship selection:
    - `hex_overlay.hex_at_world_pos` → `CourseClicks.route`;
    - if routed, call extend or cut;
    - on "", `planning_ui.select_ship(id)` and `_refresh_courses()`;
    - on a reason, `Trace` it and show it as the card's collision line;
    - mark the input handled.
  - Hover: `_update_plotting_hover` uses the routed ship's `_hover_candidates` and `ShipState.speed`.
  - Collision warnings and tacking/steering text are computed per ship for `set_course_info`. Reuse the existing helpers `_update_collision_hexes` / `offered_collisions` / `path_collision_text` / `_update_tacking_display` / `_update_steering_display` by giving them a `ship_id` parameter in place of `movement_client.active_ship_id`.
  - Delete:
    - `_on_planning_action_toggled`
    - `_on_plotting_*`, `_on_hex_selected`, `_on_undo_complete`, `_on_movement_submitted`
    - `_connect_movement_signals`
    - `submitted_paths`
    - the own-ship plotting guard (~622)
    - the plot cancel on card change (~813) and on opening the crew overlay (~286)
    - `crew_client.close()` on plot start
  - `_on_end_planning_pressed`: just `player_submit_plan(HUMAN_PLAYER_ID)`.
  - Connect `reset_planning_confirmed` → `player_reset_planning(HUMAN_PLAYER_ID)`, then `_refresh_courses()`, `planning_ui.refresh_crew_summaries()` and `crew_client.refresh()`.
  - Connect `reset_course_requested(id)` → `player_reset_course`, then `_refresh_courses()`.
  - After any crew or sail change (`_on_crew_changed`), call `_refresh_courses()`: the MA can change with the sail order.
  - Status plate: in `_update_status_hover`, during PLANNING never call `set_hover_target` (click-only). Remove `movement_client.is_plotting()` from `set_suppressed`.
  - When PLANNING ends, `hex_overlay.clear_courses()`.
- [ ] **Step 4:** Run `make test`. Expected: PASS, including `test_server_authority.gd`.
- [ ] **Step 5: Live check.** Use the screenshot script (`--script`, scenario `test_fleet`; see the session scratchpad's `snap_planning.gd` pattern) or godot-mcp `run_project` + `game_click`. Confirm:
  - both own ships show their default course and next hexes at planning start;
  - clicking a next hex extends that ship and selects its card;
  - clicking a course hex cuts it;
  - End Planning with untouched ships moves them at last speed;
  - Cancel → Reset restores the courses.
  - `game_get_errors` returns zero.
- [ ] **Step 6:** Commit: `feat(planning): always-on course editing on the map`.

### Task 7: Docs and final audit

**Files:**
- Modify: `CLAUDE.md`
  - PLANNING bullet
  - "Movement Plotting Protocol": sessions are now the StubAI's path; the player uses `player_extend_course` / `player_cut_course` / `course_options`
  - "Planning Panel"
  - the `test_server_authority` list of requests: add the new `player_*` requests
- [ ] **Step 1:** Update the CLAUDE.md sections above. Also remove the "Sessions auto-expire after 5 minutes" claim, which is not implemented.
- [ ] **Step 2:** Run `make test` and both rule-table validators. Expected: PASS.
- [ ] **Step 3:** Run the `scv-reviewer` agent. Fix every violation it finds.
- [ ] **Step 4:** Commit: `docs: implicit movement planning`.
