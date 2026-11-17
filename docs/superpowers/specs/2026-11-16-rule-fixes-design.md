# Rule fixes (feature-gap sub-project 1): design

Date: 2026-11-16. Status: approved by the user 2026-11-16. Part of `2026-11-16-feature-gap-roadmap-design.md`.

## Intent

Clear the small rule gaps in §2 of `docs/rules/feature_diff.md` that need no new game system, before the larger sub-projects (players and sides, map, anchoring, towing, ships and guns, optional rules). The guiding principle is the roadmap's: playability before fidelity. Where a rule is not worth its cost it is recorded as a deliberate change instead of built.

## Goals

Each item below either matches the rule afterwards or is recorded as a deliberate change, and its `feature_diff.md` row is updated in the same change.

1. **5.E.8 Accelerating from stopped.** A ship that was stopped last g-t (`ShipState.speed == 0`) and whose first plotted step is a turn can plot nothing more that g-t.
2. **5.D.3b Reverse tack.** A ship at WF=L that turns back the way it turned in rolls on the Tacking table with the +3 "reversing tack" DRM (the chart's DRM; already in `tacking_table.json`'s `_doc`).
3. **5.D.4c / 3.D.4 In irons after a calm.** A ship at WF=L is not in irons in the first g-t after the wind speed rises from 0 to 1. It still turns by the MA-0 rules (a Tacking roll, without the +1 in-irons DRM).
4. **6.C.3 Contested hex (deliberate change, user decision 2026-11-16).** The winner always enters; it never forces the loser in. Recorded in §4. No code change beyond comments.
5. **6.D.3c Bear-off order.** When two or more bear-off situations arise in the same segment, a d10 orders them.
6. **7.B.10–12 Friendly ships blocking line of sight.** A friendly ship at least partly in a battery's arc, at range 5–9 from the firing ship, makes every hex adjacent to it that is at least as far from the firer as the friendly ship a blocking hex; at range 10–15, every hex within two hexes of it that is at least as far. A line of sight passing *through* a blocking hex is blocked; one ending in it is not.
7. **7.C.14 Voluntarily reducing the MGN.** A fire order may carry a reduction of 0 or more, subtracted from the MGN before the roll.
8. **2.A.1 Game end (part).** The game ends when a side has no ship that can move or fight (deliberate change from the strict rule, see §8). Ending by agreement is sub-project 2.
9. **10.H.2 Prizes grapple, ungrapple and unfoul.** A prize with her prize crew aboard may try all three, ordered by the side that holds her.
10. **8.G.1f Exploded ships are removed from the map** at the end of the g-t.
11. **Closed as "not in the rules":** the "Sinking" row (Volume 1 has no sinking rule: a ship with no hull boxes strikes, and explodes only if burning, 8.E.8) and "Sail checks after a wind change" (no such rule in 2.B.1 or ch. 3; the `# TODO` in `TurnPhaseController._enter_environment_phase` is removed).

## Non-goals

- Signalling, flagships, ending by agreement, limited information (sub-project 2).
- Map exit and escape (sub-project 3). Item 10 only adds the "on the map" notion that escape will reuse.
- The anchoring exceptions to being in irons (5.D.4a–b, 13.F.3; sub-project 4).
- Any change to AI strategy beyond what these rules force (the AI never reduces its MGN, never forces a contested-hex loser, and fires around blocking hexes because its shot search uses the same geometry).

## Anti-goals

- **A rule the player cannot see.** Every new restriction shows where the player meets it: the map stops offering hexes after a 5.E.8 turn, the tacking chance includes the reverse-tack +3, and the fire panel names a blocking friendly ship as the reason a battery cannot fire.
- **Server authority weakened.** All new state is set by server controllers; the fire panel only adds a field to the order it already sends.
- **Replays that diverge.** New movement rolls (6.D.3c) go through the resolver's RNG so a bear-off or overlap replay repeats them.

## Approaches

Each item is a local change to the controller that already owns the rule, plus its test and its `feature_diff.md` row. The alternative, a separate "rules variants" layer that switches each rule on or off, was rejected: none of these rules needs to be optional, and the optional rules (14) get their own switches in sub-project 7. For 6.C.3 the user chose to keep "winner always enters" (B) over a mid-movement prompt like bear-off (A), because the case is rare and a second interruption costs more than the choice is worth.

## Design

### 1. 5.E.8 (movement validator)

In `MovementValidator._build_plotting_state()`, beside the existing MA-0 rule (`ma_zero_turn_ended`): when `ps.speed_last_turn == 0` and the first step of the path is a turn, set `remaining_ma = 0` (reuse `ma_zero_turn_ended` or a sibling flag). `calculate_valid_moves` then offers nothing after it, so the map, `course_options`, the AI and the validator of a stored plot all agree. `DefaultCourse` plots ahead steps only and is unaffected. A turn into WF=L already stops the ship (5.D.3); nothing changes there.

### 2. Reverse tack (ship state + resolver)

- New `ShipState` field `irons_entry_turn: int` (-1, `PORT` or `STARBOARD`): the direction of the turn that brought the ship to WF=L. Set in `MovementResolver.apply_results()` when the ship ends the g-t at WF=L and its last executed turn took it there; reset to -1 whenever it ends a g-t at another WF. A ship that came to WF=L by a wind shift has -1. Serialized with the ship (`to_dict`/`from_dict`).
- `_calculate_tacking_drm()` adds +3 "reversing tack" when the ship is at WF=L, `irons_entry_turn != -1` and the plotted MA-0 turn is the opposite direction. `tacking_chance()` uses the same DRM, so the planning screen shows it.
- **Planner's call:** the +3 applies whenever a ship still at WF=L turns back the way it came, not only on the g-t right after entering. That is the simplest reading and the turn is still "back the way it came".
- **Planner's call:** the +3 adds to the +1 in irons when both apply (they are separate chart DRMs).

### 3. In irons after a calm (environment + resolver)

- `EnvironmentState` gets `calm_ended_turn: int` (-1 = never), set by `EnvironmentController.tick_environment()` when it applies a pending wind speed change from 0 to 1.
- `MovementResolver._is_in_irons()` returns false in that g-t (`calm_ended_turn == current turn`). The ship has MA 0 at WF=L, so any turn already goes through the Tacking roll; it just loses the +1. The in-irons +1 in `_calculate_tacking_drm()` must read `_is_in_irons()` (not its own speed/WF test), so the exception drops it there too.
- The planning note (`planning_text.gd` `IRONS_NOTE`) follows `_is_in_irons` (expose a static or query if needed).

### 4. 6.C.3 (deliberate change)

No behaviour change. Reword the `_stern_contest` stub comment and the bow-contest code so they say "deliberate: the winner always enters (user decision 2026-11-16)". `feature_diff.md`: move the 6.C.3 row from §2.2 to §4.

### 5. 6.D.3c bear-off order (resolver)

In `_resolve_impulse()`, when more than one bear-off situation is found in the same segment (two or more groups whose resolution reaches `_resolve_collision_or_bearoff`), each situation rolls one d10 from the resolver's RNG, re-rolling ties among the tied ones; the highest goes first. That order decides which prompted ship becomes `decision_needed` and the order in which StubAI ships decide. Log the rolls (a `BEAR_OFF_ORDER` resolution entry, shown in the combat log only when it decided something).

**Planner's call:** highest d10 first; ties re-rolled. The rule only says "roll a d10".

**Planner's call (builder check):** the d10 only orders the situations within the segment's existing single pass: who is asked first and the order of the dice. The resolver is not restructured to settle one situation, replay, and only then look at the next. The existing machinery already gets most of the way there: a successful bear-off amends the plot and replays the whole resolution, so a later situation that no longer arises disappears on the replay. The rolls come from the resolver's RNG, so they repeat on every replay.

### 6. Friendly blocking hexes (fire geometry + calculator)

- New pure function `FireGeometry.blocking_hexes(battery_hex, firer_hexes, friendly_ships_hexes) -> Dictionary` (hex set). For each friendly ship (other than the firer) with at least one hex in the battery's arc (`in_battery_arc`), range `r` = closest distance from the firing ship's hexes to the friendly ship's hexes (7.B.12, as for gunfire range, 7.C.4). `r` in 5–9: radius 1; 10–15: radius 2; otherwise none. Every hex within that radius of either of its hexes whose own range from the firing ship is ≥ `r` is blocking. The friendly ship's own hexes already block as occupied.
- `has_line_of_sight(from, to, occupied, blocking := {})`: an intermediate hex in `blocking` blocks just as an occupied one does (same sampling and nudging rule). The end hexes never block, so a target sitting in a blocking hex can still be hit.
- `battery_bears` takes the blocking set per battery. `GunneryCalculator` builds it from the firer's side: friendly = same `player_id` (the side in control, so a prize counts for her captor's side), struck ships included, removed ships excluded (item 10).
- The no-shot reason names the ship: "Blocked by friendly ship <name>". `StubAI._score_position` passes the same blocking set, so the AI does not count shots it cannot take.
- Diagram 18 is the test source for which hexes block.
- **Planner's call (builder check):** any hex may be a blocking hex, the target's own hexes included (Diagram 19 shows a blocking hex on a target). Only the two end hexes of a line of sight are exempt, as for occupied hexes.

### 7. Voluntary MGN reduction (fire orders + panel)

- `FireOrder.mgn_reduction: int = 0` (in `from_dict`/`to_dict`). `GunneryCalculator.preview()` adds it as a modifier ("Voluntary reduction −n") when > 0, so `preview_orders`, the resolver and the panel all show and roll the same number. `validate_orders` refuses a negative value. Any size is allowed; an FGN below 1 already means no damage and no critical hit (`CombatTables.gunfire_result`).
- **Planner's call:** the reduction is per order, so a side that splits its fire between two targets can reduce one shot and not the other.
- Fire panel: a small "Reduce fire" stepper per order row (0 by default), kept in the per-side state beside `want_high` / `want_dismantling`, passed through `FireRules.make_order`. The row's preview updates as it changes.
- The AI never reduces.

### 8. Game end: no ship able to move and fight

**User decision 2026-11-16 (2b):** the game ends only when a side has no ship that can move *or* fight at all. A strict reading of 2.A.1 would end the game the moment the enemy is dismasted, before she can be boarded or finished off. Recorded in `feature_diff.md` §4 as a deliberate change.

- `VictoryController.check(turn)` gains a third reason, "no ship able to move or fight", when a side has no *useful* ship. A ship is useful when it is in play (`not is_out_of_play()`) and either can move (not dismasted, `rigging_level() > 0`) or can fight (at least one gun factor not dismounted on some side). Fouled, grappled or in-irons ships count as able to move (those are temporary). A side with no useful ship is defeated, as if all struck.
- Checked at END_TURN, after the existing "all struck" test. If both sides have no useful ship in the same g-t, the winner is by points, as for the turn limit.

### 9. Prizes grapple, ungrapple and unfoul

- `GrapplingController.grapple_error` / `ungrapple_error` and `FoulingController._attempt` accept a captured ship when `has_prize_crew()` is true; all other limits (8.C.3: burning, CQ F/G, used > 2 MPs) apply to her with the prize crew's CQ. A prize whose captors are still reorganizing aboard cannot.
- The maintenance prompt already lists the player's ships by `player_id`, which follows the captor, so the player is asked for his prizes. `StubAI`: a prize never grapples, cuts every grapple it can, and always tries to unfoul.
- Towing a prize is sub-project 5.

### 10. Exploded ships leave the map

**User decision 2026-11-16 (1b):** the wreck is removed at the end of the g-t, as 8.G.1f says, not at once. This replaces the earlier decision to keep the wreck on the map for good (critical-hits spec Q2, crew-tasks spec Q10).

- New `ShipState.removed_from_map: bool` (serialized) and `ShipState.is_on_map()` = `not removed_from_map`. Set only by a new server step, `ShipStateController.remove_from_map(ship_id)`, called at END_TURN for every DESTROYED ship (the 8.G.1f "remove ships" step; sub-project 3 will call it for escaped ships too). Order in `_enter_end_turn_phase`: removal first, then `victory_controller.check`.
- Between the explosion and the end of the g-t nothing changes from today: the wreck is DESTROYED, out of play, and its hexes still block movement, drift, line of sight and wind, as now.
- After removal every map query skips the ship: `Occupancy.build` / `from_positions`, `BlockedWind`, the movement resolver's ship list, drift, LOS occupancy (gunnery calculator, StubAI), grappling/fouling adjacency, fire spread and debris, `GameController.ship_at_hex`, the minimap and the status overlay. A shared helper (e.g. `GameState.ships_on_map()`) keeps callers from re-implementing the filter.
- The ship stays in `GameState.ships` (logs, victory, history). Victory is unchanged: lost, scored as now.
- View: the explosion and the wreck model play as today; when the ship is removed, `ShipView` fades the wreck out (smoke and debris thinning) and frees itself. Selecting or hovering the hex then finds nothing.

### 11. Closing rows

`feature_diff.md`: the "Sinking" row in §2.1 and the "Sail checks" row in §2.2 are removed and noted in §6 ("settled: not in Volume 1"). `CLAUDE.md` "Known Limitations": drop "sinking" and "An exploded ship stays on the map as a wreck".

## Testing

Every item gets GUT tests in `test/unit/`, expected values from the rule text (and Diagram 18 for item 6), rolls pinned with `ScriptedDice` or a seeded resolver RNG. `make test` green after each task; the SCV review at the end.

## Left to the builder

File and function names beyond those named, test file layout, the exact combat-log wording, the stepper widget.

## Decisions log

- 6.C.3: the winner always enters (user, 2026-11-16).
- Exploded ships are removed at the end of the g-t (user, 2026-11-16, reversing critical-hits spec Q2).
- The game ends when a side has no ship able to move or fight (user, 2026-11-16).
- Planner's calls, checked by a builder review: 6.D.3c ordering within the existing pass; reverse-tack +3 stacks with in-irons +1; the calm exception also drops the +1; MGN reduction per order; any hex, a target's included, can be a blocking hex.
