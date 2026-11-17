# Rule Fixes (Feature-Gap Sub-Project 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the small Close Action rule gaps of `feature_diff.md` §2 that need no new system: 5.E.8, reverse tack, in irons after a calm, 6.D.3c bear-off order, friendly blocking hexes, voluntary MGN reduction, the game-end rule, prizes grappling/unfouling, removing exploded ships at the end of the g-t, and closing three rows as "not in the rules" or "deliberate".

**Architecture:** Each rule is a local change in the controller that owns it (validator, resolver, environment, fire geometry/calculator, victory, grappling/fouling, turn phase), with a GUT test and its `feature_diff.md` row in the same commit. New state: `ShipState.irons_entry_turn`, `ShipState.removed_from_map`, `EnvironmentState.calm_ended_turn`, `FireOrder.mgn_reduction`. Map queries skip removed ships through `Occupancy.build`, `BlockedWind.is_blocked` and the resolver's ship list.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5 (`make test`).

**Spec:** `docs/superpowers/specs/2026-11-16-rule-fixes-design.md` (roadmap: `2026-11-16-feature-gap-roadmap-design.md`). Read the spec before starting a task.

## Global Constraints

- Server authority (CLAUDE.md "Server Authority"): view code never writes `ShipState`/`EnvironmentState` and never calls a `ShipStateController` mutator. New state is set only through `ShipStateController` (or `EnvironmentController`) with the `is_server` guard. `test_server_authority.gd` must pass.
- Rolls go through `game_state.dice`, except in `MovementResolver`, which rolls from its own `rng` (accepted exception) so replays repeat.
- Runtime logging through `Trace`, never `print()`.
- `make test` green after every task (currently 1660 passing; the suite only grows).
- Every task updates its `docs/rules/feature_diff.md` row in the same commit (close-action-rules skill: status word, code column names file and function, no line numbers). The last task sets the header's "Compared against" commit.
- New `ShipState`/`EnvironmentState` fields are serialized (`to_dict`/`from_dict`, `serialize`/`deserialize`) with a default that keeps old saves loading.
- Test expected values come from the rule, cited in a comment (`# 5.E.8: ...`).
- User decisions (2026-11-16): 6.C.3 the winner always enters; exploded ships leave the map at END_TURN (8.G.1f), not at once; the game ends when a side has no ship able to move **or** fight.
- Copy: no-shot reason "Blocked by friendly ship %s"; victory reason "no ship able to move or fight"; MGN modifier label "Voluntary reduction".

## Review Focus

1. **A ship stopped last g-t whose first plotted step is ahead** must still accelerate normally; only a first-step *turn* ends the move. Task 2 `test_stopped_ship_moving_ahead_first_is_unaffected`.
2. **A ship that reached WF=L by a wind shift** (no turn) gets no reverse-tack +3 whichever way it turns. Task 3 `test_wind_shift_into_luffing_has_no_entry_turn`.
3. **A target sitting inside a blocking hex** can still be fired on (the LOS ends there). Task 6 `test_target_in_blocking_hex_can_be_hit`.
4. **A wreck in the g-t it exploded** still blocks drift and LOS until END_TURN, and is gone the next g-t. Task 11 `test_wreck_blocks_until_end_turn_then_is_removed`.
5. **A dismasted enemy that can still fire** does not end the game. Task 9 `test_dismasted_but_armed_side_is_not_defeated`.

---

### Task 1: Close the "not a rule" rows and the 6.C.3 deviation

**Files:**
- Modify: `scripts/server/turn_phase_controller.gd` (`_enter_environment_phase`: delete the `# TODO: Perform sail checks…` line), `scripts/server/movement_resolver.gd` (`_stern_contest` doc comment and the bow-contest winner code in `_resolve_contested_hex`: say "deliberate: the winner always enters (6.C.3, user decision 2026-11-16)")
- Modify: `docs/rules/feature_diff.md` (remove the §2.1 "Sinking" row and the §2.2 "Sail checks after a wind change" row; add both to §6 as "settled: not in Volume 1" with the reason from the spec item 11; move the §2.2 6.C.3 row to §4 as a deliberate change), `CLAUDE.md` (Known Limitations: drop "sinking")

- [ ] **Step 1:** Make the edits above. No behaviour change.
- [ ] **Step 2:** Run `make test`. Expected: all pass, same count as before.
- [ ] **Step 3:** Commit: `docs(rules): close sinking and sail-check rows, record 6.C.3 as deliberate`.

### Task 2: 5.E.8 a stopped ship that turns first moves no further

**Files:**
- Modify: `scripts/server/movement_validator.gd` (`_build_plotting_state`)
- Test: `test/unit/test_movement_validator.gd`
- Modify: `docs/rules/feature_diff.md` (5.E.8 row → §5, Fixed)

**Interfaces:** Produces `PlottingState.ma_zero_turn_ended == true` (reused flag) and `remaining_ma == 0` after such a turn; `calculate_valid_moves` then returns no moves.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_stopped_ship_turning_first_cannot_move_further():
	# 5.E.8: a stopped ship which uses its first MP to turn can move no further that g-t.
	# Ship with speed 0 last turn, MA > 0 at its facing; path = [one STARBOARD turn].
	var moves = validator.calculate_valid_moves(ship, path_with_one_turn, ...)
	assert_eq(moves.size(), 0)

func test_stopped_ship_moving_ahead_first_is_unaffected():
	# 5.E.8 only concerns a first-MP turn; ahead then turn stays legal within acceleration.
	# speed 0, path = [AHEAD]: valid moves still include the next ahead or a turn.
	assert_gt(moves.size(), 0)

func test_moving_ship_turning_first_may_continue():
	# speed 2 last turn, path = [turn]: further moves offered.
	assert_gt(moves.size(), 0)
```

Use the file's existing ship/validator fixtures; the wind must give MA ≥ 2 at the ship's facing so the old MA-0 rule does not fire.

- [ ] **Step 2:** Run `make test`. Expected: the first test FAILS (moves offered), the others pass.
- [ ] **Step 3:** In `_build_plotting_state`, after the existing MA-0 block: if `ps.speed_last_turn == 0` and `path_so_far[0].move_type` is PORT or STARBOARD, set `ps.ma_zero_turn_ended = true` and `ps.remaining_ma = 0`. Comment with the rule.
- [ ] **Step 4:** Run `make test`. Expected: all pass. If an AI or default-course test breaks, it is plotting a now-illegal course; fix the test's course, not the rule.
- [ ] **Step 5:** Update the feature_diff row; commit `feat(movement): 5.E.8 a stopped ship that turns first moves no further`.

### Task 3: Reverse tack (5.D.3b)

**Files:**
- Modify: `scripts/state/ship_state.gd` (field + serialization), `scripts/server/ship_state_controller.gd` (setter), `scripts/server/movement_resolver.gd` (`apply_results`, `_calculate_tacking_drm`, `tacking_chance`)
- Test: `test/unit/test_movement_tacking.gd`
- Modify: `docs/rules/feature_diff.md` (5.D.3 row → §5)

**Interfaces:**
- Produces: `ShipState.irons_entry_turn: int = -1` (-1, `ShipState.PORT`, `ShipState.STARBOARD`), serialized as `"irons_entry_turn"`; `ShipStateController.set_irons_entry_turn(ship_id: String, direction: int) -> void`; `MovementResolver.is_reverse_tack(ship_state: ShipState, turn_direction: int) -> bool` (static-friendly; true when the ship is at WF=L, `irons_entry_turn != -1` and `turn_direction != irons_entry_turn`).
- `_calculate_tacking_drm(ship_state, sections := -1, turn_direction := -2)`: -2 means "read the direction from the ship's first plotted step".

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_turning_into_luffing_records_entry_turn():
	# Ship ends the g-t at WF=L after a STARBOARD turn.
	assert_eq(ship.irons_entry_turn, ShipState.STARBOARD)

func test_leaving_luffing_clears_entry_turn():
	assert_eq(ship.irons_entry_turn, -1)

func test_wind_shift_into_luffing_has_no_entry_turn():
	# WF=L reached by wind direction change, no turn executed: -1, and no +3 either way.
	assert_eq(ship.irons_entry_turn, -1)
	assert_false(resolver.is_reverse_tack(ship, ShipState.PORT))

func test_reverse_tack_adds_three():
	# 5.D.3b: turning back the way it came takes the Reversing Tack DRM (+3, chart).
	var same := resolver._calculate_tacking_drm(ship, 3, ShipState.STARBOARD)  # continue = tack
	var back := resolver._calculate_tacking_drm(ship, 3, ShipState.PORT)       # reverse
	assert_eq(back - same, 3)

func test_reverse_tack_stacks_with_in_irons():
	# speed 0 at WF=L (in irons, +1) and reversing (+3): both apply.
```

- [ ] **Step 2:** Run `make test`. Expected: new tests FAIL (field/method missing).
- [ ] **Step 3:** Add the field (serialize it, default -1). In `apply_results`, after the facing is set: if the final WF is "L" and `_last_step_direction(result)` is PORT or STARBOARD, set it to that direction; if the final WF is not "L", set -1; otherwise (no step at WF=L) leave it. Add `is_reverse_tack` and the +3 "reversing tack (5.D.3b)" in `_calculate_tacking_drm`; `tacking_chance` passes the plotted direction so the planning chance includes it.
- [ ] **Step 4:** Run `make test`. Expected: all pass.
- [ ] **Step 5:** Update the feature_diff row (note the planner's calls: +3 whenever still at WF=L turning back; stacks with in irons); commit `feat(movement): reverse tack +3 (5.D.3b)`.

### Task 4: Not in irons the g-t after a calm (5.D.4c, 3.D.4)

**Files:**
- Modify: `scripts/state/environment_state.gd` (field + serialize), `scripts/server/environment_controller.gd` (`tick_environment`), `scripts/server/movement_resolver.gd` (`_is_in_irons`, `_calculate_tacking_drm`), `scripts/ui/planning_text.gd` if its irons note re-derives the test
- Test: `test/unit/test_environment_controller.gd`, `test/unit/test_movement_tacking.gd`
- Modify: `docs/rules/feature_diff.md` (in-irons exceptions row: "Partly fixed", still missing the anchoring exceptions, sub-project 4)

**Interfaces:**
- Produces: `EnvironmentState.calm_ended_turn: int = -1` (serialized `"calm_ended_turn"`), set by `tick_environment(env_state, turn_number)` to `turn_number` when it applies a pending change taking `wind_speed` from 0 to ≥ 1. The parameter `_turn_number` becomes `turn_number`.
- `MovementResolver._is_in_irons(ship_state, environment)` returns false when `environment.calm_ended_turn == game_state.current_turn`. `_calculate_tacking_drm`'s in-irons +1 calls `_is_in_irons`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_wind_rising_from_calm_records_turn():  # environment test
	env.wind_speed = 0; env.pending_wind_speed = 1
	controller.tick_environment(env, 7)
	assert_eq(env.calm_ended_turn, 7)

func test_not_in_irons_first_turn_after_calm():  # tacking test
	# 3.D.4 / 5.D.4c: ships in WF=L are not in irons on the first g-t after WS rises from 0.
	# speed 0, WF=L, calm_ended_turn == current_turn: no +1 in the tacking DRM, no IN_IRONS event.

func test_in_irons_again_the_g_t_after():
	# calm_ended_turn == current_turn - 1: in irons as usual.
```

- [ ] **Step 2:** Run `make test`; new tests FAIL.
- [ ] **Step 3:** Implement as in Interfaces. Check the planning irons note follows the resolver (expose `MovementResolver.is_in_irons` publicly if `planning_text.gd` needs it; a read-only query is fine for view code).
- [ ] **Step 4:** Run `make test`; all pass.
- [ ] **Step 5:** Update feature_diff; commit `feat(movement): not in irons the g-t after a calm (3.D.4)`.

### Task 5: Bear-off order by d10 (6.D.3c)

**Files:**
- Modify: `scripts/server/movement_resolver.gd` (`_resolve_impulse`, `_resolve_collision_or_bearoff`, `ResolutionPass`/`Segment`), `scripts/server/movement_types.gd` (event type), the combat-log text where resolution events are rendered (`log_outcomes` / `PhaseEvents` only if the order is logged as a phase event)
- Test: `test/unit/test_bear_off_phase.gd` (or a new `test/unit/test_bear_off_order.gd`)
- Modify: `docs/rules/feature_diff.md` (6.D.3c row → §5)

**Interfaces:** Produces `MovementTypes.ResolutionEventType.BEAR_OFF_ORDER` (detail lists the ships in order and their d10s). No public API change.

**Approach (the algorithm the tests do not fix):** bear-off situations found in one segment are queued instead of handled inline: `_resolve_collision_or_bearoff` appends `[loser_id, blocker_id]` to `seg.pending_bear_offs` when called during the segment's group resolution. At the end of the segment (before the segment is closed and before stern/bow bookkeeping that depends on the losers being stopped is read), if the queue holds one situation it is handled exactly as today; with two or more, each rolls `rng.randi_range(0, 9)`, ties among the tied re-roll, highest first, one `BEAR_OFF_ORDER` event is logged, and they are handled in that order. Everything else (prompting, `decision_needed`, StubAI choice, settled bear-offs, replay) is unchanged. If deferring a situation to the end of the segment breaks an existing collision or overlap test, keep inline handling for the single-situation case and only defer when a second situation appears in the same segment.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_two_bear_offs_same_segment_ordered_by_d10():
	# 6.D.3c: two bearing-off situations on the same segment; a d10 decides which is resolved first.
	# Two prompted ships each heading for a collision on segment n; seed the resolver RNG so the
	# second ship (by id) rolls higher: it is the one in log.pending_bear_off.
	assert_eq(log.pending_bear_off.ship_id, "ship_b")

func test_order_rolls_repeat_on_replay():
	# Submit the first decision; the replayed log has the same BEAR_OFF_ORDER rolls.

func test_single_bear_off_rolls_no_order():
	# One situation: no BEAR_OFF_ORDER event, RNG consumption unchanged.
```

- [ ] **Step 2:** Run `make test`; new tests FAIL.
- [ ] **Step 3:** Implement per Approach.
- [ ] **Step 4:** Run `make test`; all pass (the bear-off, collision and overlap suites are the guard).
- [ ] **Step 5:** Update feature_diff; commit `feat(movement): order same-segment bear-offs by d10 (6.D.3c)`.

### Task 6: Friendly ships make blocking hexes (7.B.10–12)

**Files:**
- Modify: `scripts/core/fire_geometry.gd`, `scripts/server/gunnery_calculator.gd` (`preview`, `_occupied_hexes`, eligibility), `scripts/server/stub_ai.gd` (`_score_position`), `scripts/ui/fire_declaration_panel.gd` (`no_shot_reason` if the reason text is mapped there)
- Test: `test/unit/test_fire_geometry.gd`, `test/unit/test_gunnery_calculator.gd`, `test/unit/test_stub_ai.gd`
- Modify: `docs/rules/feature_diff.md` (7.B.10–12 row → §5)

**Interfaces:**
- `FireGeometry.blocking_hexes(battery_hex: Vector2i, facing: int, side: int, firer_hexes: Array[Vector2i], friendly: Array) -> Dictionary` — `friendly` is an Array of `Array[Vector2i]` (each friendly ship's two hexes, firer excluded); returns `{hex: true}`. A friend counts only if one of its hexes is `in_battery_arc`. `r = range_between(firer_hexes, friend_hexes)`; radius 1 for r 5–9, 2 for r 10–15, else none; a hex within radius of either friend hex is blocking when `range_between(firer_hexes, [hex]) >= r`.
- `has_line_of_sight(from_hex, to_hex, occupied: Dictionary, blocking: Dictionary = {}) -> bool`: an intermediate sample blocks when both nudged hexes are in `occupied` **or** both are in `blocking` (same test as occupied). End hexes never block.
- `battery_bears(battery_hex, facing, side, target_hexes, occupied, blocking: Dictionary = {}) -> bool`.
- `GunneryCalculator`: friendly = ships with the firer's `player_id`, other than the firer, struck included, `is_on_map()` only once Task 11 lands (until then all). When a battery is in arc but blocked only by blocking hexes, `ShotPreview.reason` is `"Blocked by friendly ship %s" % friend_name` (the friend whose blocking hexes cut the line).

- [ ] **Step 1: Write the failing tests** (geometry from Diagram 18; build positions in axial coordinates in the test)

```gdscript
func test_friend_at_range_4_makes_no_blocking_hexes():  # 7.B.10, ships B/C in Diagram 18
	assert_true(geometry.blocking_hexes(...).is_empty())

func test_friend_at_medium_range_blocks_adjacent_hexes_beyond_it():
	# 7.B.10a: range 5-9 -> adjacent hexes at least as far from the firer as the friend.
	assert_true(blocking.has(hex_beyond)); assert_false(blocking.has(hex_nearer))

func test_friend_at_long_range_blocks_two_hexes_out():  # 7.B.10b

func test_friend_outside_arc_makes_none():  # 7.B.11, ships X

func test_los_through_blocking_hex_is_blocked():  # 7.B.10c
func test_target_in_blocking_hex_can_be_hit():  # 7.B.10c "An LOS may enter a blocking hex"

func test_preview_names_blocking_friend():  # calculator
	assert_eq(preview.reason, "Blocked by friendly ship %s" % friend_name)

func test_enemy_ship_makes_no_blocking_hexes():  # only friendly ships

func test_ai_does_not_score_blocked_shot():  # stub_ai
```

- [ ] **Step 2:** Run `make test`; new tests FAIL.
- [ ] **Step 3:** Implement the geometry, then thread `blocking` through the calculator (per battery) and StubAI.
- [ ] **Step 4:** Run `make test`; all pass. Existing gunnery tests with two friendly ships at range ≥ 5 may now see blocked shots: check each against the rule before changing its expectation.
- [ ] **Step 5:** Update feature_diff; commit `feat(gunnery): friendly ships make blocking hexes (7.B.10-12)`.

### Task 7: Voluntary MGN reduction, server side (7.C.14)

**Files:**
- Modify: `scripts/server/gunnery_types.gd` (`FireOrder`), `scripts/server/gunnery_calculator.gd` (`preview`, `validate_orders`), `scripts/server/fire_rules.gd` (`make_order`)
- Test: `test/unit/test_gunnery_calculator.gd`, `test/unit/test_gunnery_resolver.gd`

**Interfaces:**
- `FireOrder.mgn_reduction: int = 0`, in `from_dict` (`int(d.get("mgn_reduction", 0))`) and `to_dict`.
- `preview()` adds modifier `"Voluntary reduction"` = `-mgn_reduction` when > 0 (via the existing modifier helper, so it appears in `modifiers` and `breakdown_text`).
- `validate_orders` refuses `mgn_reduction < 0` with "Reduction cannot be negative".
- `FireRules.make_order(..., range_hexes: int, mgn_reduction: int = 0)`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_reduction_lowers_mgn():  # 7.C.14
	assert_eq(reduced.mgn, plain.mgn - 4)
	assert_true(reduced.modifiers.has("Voluntary reduction"))

func test_negative_reduction_refused():
	assert_ne(calculator.validate_orders(player, [order_with(-1)]), "")

func test_reduction_below_one_does_no_damage():
	# FGN < 1 -> no result, no crit (CombatTables.gunfire_result returns []).

func test_reduction_round_trips_through_dict():
```

- [ ] **Step 2:** Run `make test`; FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `make test`; all pass.
- [ ] **Step 5:** Commit `feat(gunnery): voluntary MGN reduction in fire orders (7.C.14)` (feature_diff row is updated in Task 8 once players can use it).

### Task 8: Voluntary MGN reduction in the fire panel

**Files:**
- Modify: `scripts/ui/fire_declaration_panel.gd` (per-side state, `panel_orders`, row UI), its scene if the row is a scene
- Test: `test/unit/test_fire_declaration_panel.gd` (existing static-function tests; create if absent)
- Modify: `docs/rules/feature_diff.md` (7.C.14 row → §5)

**Interfaces:** per-side state gains `"reductions": {row_key(target_id, battery): int}`; `panel_orders(ship_id, sides, ranges)` passes `reductions.get(row_key(target, battery), 0)` to `FireRules.make_order`. A new static `set_reduction(state: Dictionary, target_id: String, battery: String, n: int) -> Dictionary` (clamped at 0).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_panel_orders_carry_row_reduction():
	var state := FireDeclarationPanel.set_reduction(side_state, "enemy_1", "full", 3)
	var orders := FireDeclarationPanel.panel_orders("ship_a", {1: state}, ranges)
	assert_eq(orders[0].mgn_reduction, 3)

func test_split_side_reduces_one_shot_only():  # planner's call: per order
func test_reduction_clamped_at_zero():
```

- [ ] **Step 2:** Run `make test`; FAIL.
- [ ] **Step 3:** Implement the statics, then a small "Reduce fire" stepper (−/+ buttons with the value, `CounterLabel` variation) on each chosen row, default 0; changing it re-previews the row (its MGN and breakdown update). The stepper sits only on chosen rows.
- [ ] **Step 4:** Run `make test`; all pass. Launch the game (`run_project`), open the fire panel, change a reduction, confirm the preview drops and `game_get_errors` is empty.
- [ ] **Step 5:** Update feature_diff; commit `feat(ui): reduce-fire stepper in the fire panel (7.C.14)`.

### Task 9: Game ends when a side has no ship able to move or fight (2.A.1, user decision)

**Files:**
- Modify: `scripts/server/victory_controller.gd` (`check`, new helper)
- Test: `test/unit/test_victory_controller.gd`
- Modify: `docs/rules/feature_diff.md` (2.A.1 row: "Partly fixed", deliberate change in §4 for the "or", ending by agreement still missing → sub-project 2)

**Interfaces:** `VictoryController.can_move_or_fight(ship: ShipState) -> bool` = `not ship.is_out_of_play() and (ship.rigging_level() > 0 or has an undismounted gun factor on either side)`. "Undismounted gun factor": total gun factors per side from `ship.ship.gun_factors` minus `ship.guns_dismounted[side]` > 0 for some side (use the existing gun-factor helper on `ShipState` if there is one). `check(turn)`: after the "all struck" test, if any side has no ship with `can_move_or_fight`, reason = `"no ship able to move or fight"`; winner by points.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_side_with_only_dismasted_gunless_ships_ends_game():
	assert_eq(result.reason, "no ship able to move or fight")

func test_dismasted_but_armed_side_is_not_defeated():
	assert_true(victory.check(3).is_empty())

func test_armless_but_sailing_side_is_not_defeated():

func test_fouled_or_grappled_ship_counts_as_able():

func test_all_struck_reason_still_wins_precedence():
```

- [ ] **Step 2:** Run `make test`; FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `make test`; all pass (check `test_battle_to_victory.gd`).
- [ ] **Step 5:** Update feature_diff (§2.2 row, §4 deliberate "or"); commit `feat(victory): end when a side has no ship able to move or fight (2.A.1)`.

### Task 10: Prizes grapple, ungrapple and unfoul (10.H.2)

**Files:**
- Modify: `scripts/server/grappling_controller.gd` (`grapple_error`, `ungrapple_error`), `scripts/server/fouling_controller.gd` (`_attempt`), `scripts/server/stub_ai.gd` (`grapple_orders`, `ungrapple_orders`)
- Test: `test/unit/test_grappling_controller.gd`, `test/unit/test_fouling_controller.gd`, `test/unit/test_stub_ai.gd`
- Modify: `docs/rules/feature_diff.md` (boarding row's "Still different" sentence; CLAUDE.md Known Limitations "A prize does not grapple, ungrapple or unfoul")

**Interfaces:** the out-of-play guard becomes `ship.is_out_of_play() and not (ship.is_captured() and ship.has_prize_crew())` in those three places (a small `ShipState.can_handle_lines() -> bool` helper is the builder's choice). All other limits (8.C.3 burning / CQ F–G with the prize crew's CQ, ≤ 2 MPs) still apply. StubAI: a prize never appears in its grapple orders; it orders every ungrapple it may (its options); unfouling is already automatic.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_prize_with_prize_crew_may_grapple():  # 10.H.2
	assert_eq(grappling.grapple_error(prize_id, enemy_id), "")
func test_prize_without_prize_crew_may_not():  # captors still reorganizing
	assert_ne(grappling.grapple_error(prize_id, enemy_id), "")
func test_prize_may_ungrapple():
func test_prize_rolls_to_unfoul():  # fouling controller rolls for the prize
func test_ai_prize_never_grapples_and_cuts_grapples():
func test_player_prize_offered_in_maintenance_options():  # options list it under the captor's player
```

- [ ] **Step 2:** Run `make test`; FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run `make test`; all pass.
- [ ] **Step 5:** Update feature_diff and CLAUDE.md; commit `feat(boarding): prizes grapple, ungrapple and unfoul (10.H.2)`.

### Task 11: Exploded ships leave the map at the end of the g-t (8.G.1f)

**Files:**
- Modify: `scripts/state/ship_state.gd` (field, `is_on_map`, serialize), `scripts/server/ship_state_controller.gd` (`remove_from_map`), `scripts/server/turn_phase_controller.gd` (`_enter_end_turn_phase`; the resolver's `all_ships` before `movement_resolver.run`), `scripts/server/occupancy.gd` (`build`), `scripts/server/blocked_wind.gd` (`is_blocked`), `scripts/server/gunnery_calculator.gd` (friendly list from Task 6), `scripts/core/game_controller.gd` (`ship_at_hex` callers get filtered ships via `Occupancy.build`), `scripts/view/ship_view.gd`, the minimap and status-overlay scripts that list ships
- Test: new `test/unit/test_ship_removal.gd`
- Modify: `docs/rules/feature_diff.md` (fire row's "Still different", §2.2 8.G.1f exploded part, §1 if listed), `CLAUDE.md` (Ship Status DESTROYED paragraph and Known Limitations "An exploded ship stays on the map as a wreck")

**Interfaces:**
- `ShipState.removed_from_map: bool = false` (serialized `"removed_from_map"`), `ShipState.is_on_map() -> bool` = `not removed_from_map`.
- `ShipStateController.remove_from_map(ship_id: String) -> void` (server guard; also clears `fouled_with`/grapples defensively, already empty for a destroyed ship).
- `TurnPhaseController._enter_end_turn_phase`: before `victory_controller.check`, call `remove_from_map` for every ship with `is_destroyed() and is_on_map()`.
- `Occupancy.build` skips `not s.is_on_map()`; `BlockedWind.is_blocked` skips them; the resolver is passed only on-map ships. `GameState` gains `ships_on_map() -> Array[ShipState]` (read-only) for these callers.
- View: `ShipView` already shows the wreck on `is_destroyed()`; when it sees `not is_on_map()` it fades the wreck (tween alpha/sink ~1.5 s) and `queue_free`s; the minimap and status overlay skip ships not on the map.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_wreck_blocks_until_end_turn_then_is_removed():  # 8.G.1f
	# Destroy a ship mid-turn: Occupancy.build still has its hexes; after END_TURN it does not.
func test_removed_ship_no_longer_blocks_los():
func test_removed_ship_no_longer_blocks_wind():
func test_removed_ship_still_counts_as_lost_for_victory():
func test_removed_from_map_round_trips():
func test_struck_ship_is_not_removed():  # only destroyed (escape comes in sub-project 3)
```

- [ ] **Step 2:** Run `make test`; FAIL.
- [ ] **Step 3:** Implement server side, then the view fade.
- [ ] **Step 4:** Run `make test`; all pass. Launch the game, use `dev_commands` to blow up a ship (start a fire and damage the hull to 0, or the explode path), advance to the next turn, confirm the wreck fades and `game_get_errors` is empty.
- [ ] **Step 5:** Update feature_diff and CLAUDE.md; commit `feat(state): remove exploded ships at end of turn (8.G.1f)`.

### Task 12: Wrap-up

- [ ] **Step 1:** Set `feature_diff.md`'s "Compared against" to `git rev-parse --short HEAD` and list this sub-project's commits; check §2 has no row this plan fixed. Update CLAUDE.md where sections describe the changed behaviour (Turn Phase Cycle END_TURN removal step, Dice/RNG note for the bear-off order roll, Sides/Arcs blocking hexes, FireOrder field).
- [ ] **Step 2:** Run both validators (`python3 .claude/skills/validate-rule-table/scripts/validate.py`, `.../validate_combat.py`) and `make test`. Expected: all pass.
- [ ] **Step 3:** Run the `scv-reviewer` agent; fix any violations, re-run `make test`.
- [ ] **Step 4:** Commit `docs: feature_diff and CLAUDE.md for rule fixes`.
