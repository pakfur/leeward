# Towing: design

Date: 2026-11-18. Roadmap sub-project 5 of the sub-projects 3–7 run
(`2026-11-17-subprojects-3-7-decisions.md` §0 and §4, both binding). Status: draft written for the unattended
run. **U** marks the user's binding answers from the register; **B** the builder's calls, the register's or
new ones made here. A new or refined call is tagged **B (new)** or **B (refined)**, with its reason beside it.
Research memo: `docs/superpowers/research/sp5.md`. Rules: `docs/rules/close_action.md` 12.A (all), 5.D.1b, 5.D.7,
5.E.5, 8.A.6, 9.B.1b, 10.H.2, SoP V.B, the Hull Critical Hits chart (#6, Structural Damage), the Grappling chart
("attempting to tow −1"), Diagram 24; ship log task codes (`docs/rules/images/ship-log-blank-1.png`, checked: PT
Prepare to Tow 5 ± SK, 1 CS; TX Cut Tow 1, 1 CS).

## Intent

A dismasted ship or a prize in Leeward is stuck where it lies until the enemy takes it or it drifts ashore.
Chapter 12 gives the book's answer: a friendly ship prepares a hawser, passes it, and tows the cripple out of the
fight, slowly, as one unit. Sub-project 3 added escape edges, so a tow can now save a ship. This sub-project adds
all of 12.A. The stub AI plays it, and a view-only minimum draws it.

## Goals

1. Two crew tasks from the ship log: PT, Prepare to Tow (5 ± SK, one section), and TX, Cut Tow (1 g-t, one
   section). They run on the existing crew-task engine, manual or Automatic (U).
2. Beginning a tow is faithful (U):
   - the tower has completed PT;
   - its stern is in the hex directly ahead of the tow's bow (12.A.4a);
   - neither ship is fouled or grappled to any ship (12.A.4b);
   - every 8.C limit applies, including both ships having used ≤ 2 MPs this g-t;
   - the tower rolls a grapple, d10 + DRMs ≤ 2, with the chart's "attempting to tow −1";
   - the attempt is rolled in the Grappling sub-phase (B, register).
3. What may be towed (B, register): a friendly ship, or a friendly prize with or without her prize crew
   (12.A.2, 10.H.2). An own-side struck ship may not be towed: she has surrendered. One tow per tower, one tower
   per tow, and a towed ship cannot tow (12.A.2).
4. The towed ship follows in the wake (U). On each step the tower makes, the towed ship's bow takes the hex the
   tower's stern has just left and points at the tower. This must hold under proportional movement, bear-off
   pauses, overlap rollbacks and deterministic re-runs.
5. Blocked tows (B, register):
   - When the tower is stopped by a collision, the towed ship rams it: an automatic collision with no bear-off,
     rigging loss, and a fouling roll. The tow is kept (12.A.11).
   - A follow move into a hex held by a third ship undoes the tower's step, like an overlap rollback.
   - No momentum is invented for the towed ship. The 12.A.11 "decelerates faster" case is dropped.
6. Speed and handling (B, register):
   - the 12.A.7 MA loss;
   - the Tacking +1 and the 5.E.5 acceleration reduction for the tower, through the existing `towing` readers;
   - only the tower plots (12.A.6);
   - a towed ship's bow wins a contested hex (12.A.10);
   - a dismasted towed ship turns (5.D.1b), and a towed ship is out of irons (5.D.7).
7. Cutting (B, register):
   - TX by either ship takes effect in SoP V.B, the same g-t (12.A.9).
   - Hull critical #6 rolls a d6, and on a 1 the tow is cut (12.A.6).
   - The tow is cut automatically when either ship strikes, is destroyed or is taken.
8. Drift as one group (8.A.6). The 9.B.1b exception: a dismasted ship raked while under tow takes no MC unless
   her tower is dismasted too.
9. Escape (B, register): a towed ship escapes with her tower and scores as escaped.
10. The stub AI (B, register): with no enemy within 8 hexes, it prepares and tows its nearest friendly dismasted
    ship or prize toward its side's escape edge, or away from the enemy. It cuts when an enemy closes within 3.
11. A view-only minimum (U):
    - the towed ship follows in playback;
    - a tow line on the map;
    - TOWING / IN TOW badges;
    - combat-log lines;
    - a read-only tow station in the crew overlay;
    - Developer UI buttons to take in tow and cut, for manual testing.
12. Scenario: an optional starting tow; a test scenario with a tow under way and an AI tow to be made.

## Non-goals

- New input controls (U). A human orders a tow through `player_plot_crew`, using the crew order `tow` or
  hand-placed PT/TX sections. There is no maintenance-panel row and no course preview that drags the tow.
- The 12.A.11 deceleration collision (B, register: no momentum is invented).
- Diagram 24's lagging follower (U: the wake rule replaces it; recorded in feature_diff §4).
- Towing by ships' boats, and towing becalmed ships (the rules have neither, 1.E.4).
- A TOW signal order (research Q4c). A later change can add it to `SignalOrders`.

## Design

### 1. Geometry

Directions are `HexGrid.DIRECTIONS`: 0 = E (1, 0), 1 = SE (0, 1), 2 = SW (−1, 1), 3 = W (−1, 0), 4 = NW (0, −1),
5 = NE (1, −1). `stern_of(bow, f) = bow + DIRECTIONS[(f + 3) % 6]`.

**Tow station (12.A.4a).** For a ship to be towed whose bow is at `Tb` and whose facing is `g`, the station is
`Tb + DIRECTIONS[g]`, the hex ahead of her bow. A tow may begin only when the tower's stern hex is that station.
The two ships need not share a wind facing.

**Tow invariant.** While a tow stands and the towed ship can follow:

    towed.bow + DIRECTIONS[towed.facing] == tower.stern

The tow begins in this position, and every follow keeps it.

**Follow pose (U).** The tower makes one step from bow `B`, facing `f` (stern `S = stern_of(B, f)`) to bow `B'`,
facing `f'` (stern `S' = stern_of(B', f')`). The towed ship then takes:
- bow = `S` (the hex the tower's stern just left);
- facing = `d`, where `S + DIRECTIONS[d] == S'` (it points at the tower's new stern);
- stern `X = S − DIRECTIONS[d]`.

`S` and `S'` are always neighbours:
- **Ahead step:** `S' = B`, so `d = f`.
- **Turn:** `S' = B − DIRECTIONS[f']`. A starboard turn (`f' = f + 1`) gives `d = f − 1`; a port turn gives
  `d = f + 1`.

`TowRules.follow_pose` computes this. The follow footprint never overlaps the tower's new footprint: `X` and
`S'` lie on opposite sides of `S`.

The wake rule's consequence (recorded in feature_diff §4):
- A straight tow is a train: `X` is the towed ship's old bow, so she enters one new hex.
- After the tower turns, the towed ship points 120° off the tower's heading. On the tower's next step she swings
  round again, so her stern may enter a hex two away from where it was.
- Diagram 24 shows the tow lagging, then catching up. Here she follows every MP.

### 2. Ship state

`ShipState.towing: bool` is replaced by two ids (**B (refined)**: the research's `tow_partner` + role is the same
information; two ids read better at the call sites).

| Field | Meaning |
|---|---|
| `towing_id: String` | The ship this one tows, `""` when none. |
| `towed_by: String` | The ship towing this one, `""` when none. |
| `tow_prepared: bool` | PT completed and not yet used (12.A.3). Kept until a tow begins; after any cut the ship must prepare again (a new hawser). |

All three are serialized and mutated only through `ShipStateController`:
- `begin_tow(tower_id, towed_id)` sets both ids and clears the tower's `tow_prepared`.
- `cut_tow(ship_id)` clears both ends; either id may be passed.
- `set_tow_prepared(ship_id, on)`.
- `remove_from_map` clears any tow of the ship, at both ends, with no event.

Helpers:
- `is_towing()` (`towing_id != ""`) and `is_towed()` (`towed_by != ""`).
- `tow_partner()`: the other ship, or `""`.
- `drift_group_ids()`: `linked_ids()` ∪ `tow_partner()`, sorted.
- `tow_order()`: the crew order, §3.

The three readers of the old flag switch to `is_towing()`: `MovementResolver._calculate_tacking_drm` (+1),
`ShipStateController.speed_change_limits` (5.E.5) and their tests.

**The tow is not added to `linked_ids()`** (research §2). That list means fouled or grappled. Marine fire,
boarding, `take_link_snapshot`, fire spread, unfouling and the "cannot move" checks all read it, and a tow must
not count for any of them.

### 3. Crew tasks and the tow order

`crew_tasks.json` gains:
- `"PT": {"name": "Prepare to tow", "sections": [1, 1], "turns": {"sk_base": 5}}` (CQ C: 4; A: 2; G: 8);
- `"TX": {"name": "Cut tow", "sections": [1, 1], "turns": {"fixed": 1}}`.

**Legality.** `TowRules.refusal(ship, code, accepted)` is pure and quotes the rule in each reason. In every case
the ship's crew must be able to act, and a prize may plot neither task (10.H.2: boarding and repairs only).
- PT is refused when:
  - the ship is towing ("already towing (12.A.2)");
  - the ship is in tow ("a towed ship cannot tow (12.A.2)");
  - the ship has already prepared ("already prepared to tow (12.A.3)");
  - a PT is already in the plan.
- TX is refused when:
  - there is no tow ("no tow to cut (12.A.9)");
  - a TX is already in the plan.

**Ordering them.**
- **The crew order `crew_orders.tow`** takes one of three values (**B (new)**: the attempt is ordered in PLANNING,
  §4):
  - `""`;
  - `"take:<ship_id>"`, "take that ship in tow": prepare if needed, then make the attempt whenever legal;
  - `"cut"`.
- `plot_crew` refuses an order of any other shape: "Unknown tow order %s". For `take:`, it also refuses an
  unknown, own, or other-side target, or a struck or destroyed one, with the §4 reasons.
- **Standing rules.** `"take:<id>"` is a standing order, like the boarding order: `clear_crew_plot` and
  `clear_plotted_actions` keep it. It lapses when the tow begins (`TowController.begin` clears it). `"cut"` lapses
  every g-t.
- **Automatic crew:** a new rule **A2d** in `CrewAuto.allocate`, after A2c. It runs `TowRules.order_task(ship,
  order)` (`take:` gives PT when the ship is not prepared, not towing and has no live PT; `cut` gives TX when the
  ship is in a tow). When `TowRules.refusal` allows it, the task goes to the first free section in worker order.
  A PT in progress continues under A2.
- **Manual crew:** `CrewRules.normalize` gets a `_normalize_towing` branch, like `_normalize_anchoring`.
- `CrewRules.station_of` maps PT and TX to the station `"tow"`.

**The handler.** `TowController` (`scripts/server/tow_controller.gd`) extends `CrewTaskHandler` and is registered
for PT and TX:
- `prepare`: `TowRules.refusal`.
- `on_complete`:
  - PT: `set_tow_prepared(true)`;
  - TX: nothing (the cut ran in V.B, §6).
- `cancel_reason`: the base reasons, plus:
  - for PT, "towing" once a tow has begun;
  - for TX, "no tow" once the tow is gone (cut automatically).

### 4. Beginning a tow (12.A.4; U)

`TowRules.pair_error(tower, towed, setup := false) -> String` returns the reason the tower may not try now, or
`""`. Checks, in this order:
1. The same ship: "a ship cannot tow itself".
2. Either ship not on the map: "%s is not on the map".
3. The tower is not active (struck, destroyed, captured, escaped or waiting): "%s cannot tow (12.A.2, 10.H.2)".
   A prize cannot tow, because it cannot sail.
4. The towed ship is struck or destroyed: "%s has struck: a ship that has surrendered is not towed (ruling)". A
   prize is allowed.
5. `towed.side != tower.side`: "only friendly ships may be towed (12.A.2)". A prize's `side` is her captor's.
6. Either ship already towing or in tow: "%s already tows %s" / "%s is already in tow" / "a towed ship cannot tow
   (12.A.2)".
7. Either ship anchored: "%s is anchored". **B (new)**: 13.C.3 says an anchored ship cannot move, and the rules
   have no towing of an anchored ship. The other way round, a ship towing or in tow may not plot A
   (`AnchorRules.refusal`: "a ship towing or in tow cannot anchor: cut the tow first (ruling)").
8. Either ship aground: "%s is aground (13.G.3)".
9. The tower dismasted: "a dismasted ship cannot tow". **B (new)**: it cannot sail, so the tow could never move.
10. Not in position: "%s's stern must lie in the hex ahead of %s's bow (12.A.4a)".
11. Either ship fouled or grappled to any ship: "neither ship may be fouled or grappled (12.A.4b)".

When `setup` is false (a real attempt), these also apply:

12. The tower has not prepared: "%s has not prepared to tow (PT, 12.A.3)".
13. The tower is burning: "%s is on fire (8.C.3)".
14. The tower's crew is CQ F or G: "a crew at CQ %s cannot grapple (8.C.3)".
15. The tower has used more than 2 MPs: "%s used %d MPs this turn (at most 2, 8.C.1)".
16. The towed ship has used more than 2 MPs: the same message for her.

The Developer UI and a scenario's starting tow use `setup = true`.

**The roll.**
- `GrapplingController.grapple_chance(ship_id, target_id, towing := false)`: with `towing` true it adds the
  modifier `towing` (`CombatTables.grapple_drm("towing")`, −1).
- Otherwise the roll is "rolled normally" (12.A.4b): ± SK, marines not available +1, WS 4 +1, target used
  0 MPs −1. The fouled DRM cannot arise.
- d10 + modifier ≤ `grapple_success_max()` (2) succeeds.
- Example: CQ C (SK −1), towed ship stopped (−1), towing −1 → modifier −3, so a d10 of 0–5 succeeds (60 %).

**When (B (refined)).** The register sets the tow up in the GRAPPLE maintenance step. Here
`TowController.resolve_tow_attempts(phase)` runs at the start of STATUS_ADJUSTMENT, the first part of the
Grappling sub-phase (SoP V.C), before the grapple prompt and the grapple rolls. Reasons:
- The tower alone rolls (12.A.4b).
- A tow must begin before an enemy's grapple could make it illegal.
- Grapple options and prompts then see the new tow.
- There is no prompt: no new input controls (U), and the intent was already given in PLANNING by the crew order.

The procedure:
- For each ship in ship-id order whose `tow_order()` is `take:<id>`, call `pair_error(tower, towed)`.
- A refusal is traced and the order stands (the tower keeps trying).
- Otherwise roll one d10 through `game_state.dice` and log `TOW_BEGUN` (§9) on success or failure.
- On success, `begin(tower_id, towed_id, phase)` runs: `ShipStateController.begin_tow`, and the tower's tow order
  is cleared.

**B (new):** the position is checked when the attempt is rolled, after drift. 12.A.4a says "at the end of the
Movement Phase", but a drift that has moved one of the pair spoils the attempt. Checking once, with the positions
as they stand, keeps the step simple and needs no snapshot.

### 5. Movement (12.A.5–12.A.11; U and B)

This is the hardest part. It is built so the towed ship's moves are a pure function of the tower's resolved steps
in the same pass, and so every replay (rollbacks, cycle breaks, bear-off re-runs, stern contests) repeats them.

**Plotting.**
- `DefaultCourse.can_plot` is false for a towed ship. `_plot_refusal` gives `SHIP_TOWED`: "Ship %s is in tow and
  follows her tower (12.A.6)".
- A tower whose tow is fouled or grappled to any ship is held (8.C.7 applied to the unit, research §5). This is
  checked before the `can_plot` early return, `TOW_HELD`: "Ship %s cannot move: her tow %s is fouled or grappled
  (8.C.7)". `DefaultCourse.for_ship` returns nothing for her.
- `MovementResolver._get_plotted_steps` returns `[]` for a towed ship and for a held tower, as a defence.
- `StubAI.LOCKED_ERROR_CODES` gains both codes.

**MA (12.A.7).**
- `TowRules.ma_loss(tower, towed) = 1 + max(0, tower.class − towed.class) + (1 if the towed ship is dismasted or
  carries no sail (sail_state NS) else 0)`. Class 1 is the largest.
- Examples: a class 3 ship towing a dismasted class 1 ship loses 4. A class 3 ship towing an unrigged class 3 ship
  under sail loses 1.
- `ShipStateController.tow_mp_loss(ship)` returns that loss for a tower, else 0.
- Both MA paths subtract it after the table and `critical_mp_loss`, floored at 0, and before blocked wind:
  - `get_movement_allowance`;
  - `MovementValidator._build_plotting_state`, as `ps.mp_loss += tow_mp_loss`.
- The towed ship's own MA plays no part (12.A.6).

**Irons.** `IronsRules.excused` is true for a towed ship (5.D.7: she is towed out of irons). She is never told "in
irons", and she has no tacking roll, because she plots nothing. A tower at MA 0 tacks as any ship (12.A.8), with
+1 for towing.

**The resolver.**

*Per pass:*
- `ResolutionPass.tows` maps tower_id → towed_id for every pair whose two ships are in the run.
- `ResolutionPass.tow_hold` maps towed_id → reason, from the moment she can no longer follow this pass:
  `"collision"` or `"fouled"`.
- `ResolutionPass.tow_amendments` is an array.
- All are rebuilt each pass, so a replay starts clean.

*12.A.10, the towed bow wins.*
- When a tower's step succeeds, `_settle` re-holds the tower's old stern hex `S` for the towed ship
  (`seg.held[S] = towed_id`), unless she is in `tow_hold`.
- A group waiting to enter `S` (it waits for the tower, as an old-stern owner) then finds it held by the towed
  ship, and the usual potential-collision path follows (bear off or collide, with the towed ship as the blocker).
- The towed ship's own hexes are held for the whole segment, as any non-moving ship's are. **B (new):** she
  vacates them only from the next segment, a conservative simplification (a ship sailing close astern of a tow
  meets her as a stationary ship).

*The follow, `_follow_tows(p, seg)`.* Called in `_resolve_impulse` after `_resolve_pending_bear_offs` and before
the cycle check and `_note_left_map`. For each tower in ship-id order that has an intended move this segment:
1. **The step was made** (`seg.moves` has it):
   - If the towed ship is in `tow_hold`: a tow rollback (below), reason `tow_<hold>`.
   - Else compute `follow_pose`. The new bow `S` and stern `X` must each be free of every other ship's footprint
     as it stands at the end of the segment (the pair excepted). A ship whose stern swung into that hex this
     segment (`seg.swings`) does not count: that is a 6.B overlap, and the overlap check now meets the towed
     ship. `X` must also be on the map and not land (`S` always is: the tower's stern was there).
   - If a hex is held, or `X` is off the map or land: a tow rollback, reason `"blocked"`, `other_id` = the holder
     (`""` for the edge or land).
   - If clear, and the new bow `S` lies in a shallow area: roll the depth (`_roll_depth`, the resolver's rng). If
     depth ≤ draft, the towed ship runs aground where she stands (AGROUND, rigging dice as for a collision,
     13.G.2). She does not follow, and the tow is struck from `p.tows`: the tower sails on free. After movement,
     `MapController.ground` cuts the tow (§6).
   - Otherwise apply the follow: `p.current_hexes`/`current_facings` and the towed result's `final_hex`/
     `final_facing` are set, and a `TOW_FOLLOW` resolution event is added (`from_hex`, `to_hex`, `from_facing`,
     `facing`, the tower's segment).
2. **The step was not made because a collision stopped the tower this segment** (the tower's result
   `stopped_at_impulse == seg.impulse` and `collided_with != ""`). The towed ship rams her tower,
   `_apply_tow_collision(p, seg, towed_id, tower_id)`:
   - The towed ship rolls rigging loss as the ship that runs in (6.E.3, `_roll_collision_rigging_loss`).
   - COLLISION events: on the towed ship, detail "collided with <tower>, rigging_loss=n, tow"; on the tower, "hit
     by <towed>, tow".
   - The towed ship's `collided_with` is set if empty. The tower's is not overwritten (it keeps the third ship).
   - A fouling roll `roll_fouling(towed, tower)` is made unless either is already fouled, before or in this
     resolution. On a foul, FOULING events and `fouled_with` on both.
   - The towed ship goes into `tow_hold` (`"collision"`). The tow is kept (12.A.11).
3. **Not made for any other reason** (stern contest lost, edge, aground, bear-off amendment pending, or the
   tower's own rollback): nothing happens. The towed ship stays.

*Holding.* A towed ship hit by a third ship this pass (her `collided_with` set by `_apply_collision`), or fouled
this pass, goes into `tow_hold` at once, so the tower's next step is undone. This rule is recorded in
feature_diff §4. `_follow_tows` checks the towed ship's result before step 1.

*Tow rollback, kind `"tow"`.*
- A record goes into `p.tow_amendments`: `{ship_id: tower, kind: "tow", segment, step: the tower's step index,
  other_id, hex, reason, pre_bow, pre_facing}`.
- `_resolve_pass` returns it with the contest and bear-off amendments.
- `run()` amends the tower's plot to `steps.slice(0, step)`, with **no deceleration padding**. **B (new):** the tow
  holds her back, as an edge holds a ship. Padding with ahead steps would only meet the same block again. Every
  such rollback removes at least one step, so the pass bound stands.
- The final log gets a `TOW_HELD` event on the tower at that segment (`_record_tow_hold`, skipped when the tower
  no longer reaches it), `blocked_by` = `other_id`, and `stopped_at_impulse` = the segment.
- `stop_cause` gives `{"cause": "tow", "other": id}`, so STOPPED_SHORT says why.

*Proportional pace and the playback.*
- The towed ship has no schedule of her own. Each follow happens on the tower's segment.
- `ResolutionLog.towed_by` (towed_id → tower_id) lets the view glide her at the tower's pace.
- Bear-off pauses: a paused log contains the follows made before the decision. The re-run repeats them, so the
  view resumes cleanly.

*After movement (`apply_results`).* For a towed ship:
- `moved_this_turn` = any TOW_FOLLOW event that moved her bow;
- `mp_used_this_turn` = the number of TOW_FOLLOW events;
- speed = her tower's resulting speed (the same formula the tower gets), or 0 when she was in a collision or ran
  aground (5.E.3b).
- **B (refined):** "the hexes she actually moved" (research §5) would make a towed ship stopped while her tower
  sails, and drift would then move her. The pair moves as a unit, so she takes the unit's speed. On a later cut,
  her deceleration minimum starts from it.
- `log_outcomes` logs her ramming COLLISION with `"tow": true`.

*Dice (the resolver's rng, the accepted exception).* Inside `_follow_tows`, towers in ship-id order:
- the towed bow's depth d6, then the rigging dice if she runs aground;
- or the ram's rigging dice, then the fouling d10.

They are drawn after the segment's groups and bear-off decisions. Nothing tow-related is drawn when no ship tows,
so every existing resolution is unchanged.

### 6. Cutting and keeping the tow

**TX (12.A.9).** `TowController.resolve_cuts(phase)` is SoP V.B "Anchoring & Towing". It is called in
`_enter_drift_calculation_phase` after `anchor_controller.resolve_anchoring` (after drift). For each ship in a tow,
by ship id: a live TX task begun this g-t cuts the tow (`TOW_CUT`, cause `"tx"`, `by` that ship). Either ship's TX
will do, but a prize cannot plot it.

**Automatic cuts (B, register).** `TowController.on_ship_changed(ship_id, phase)` cuts the ship's tow when
`TowRules.broken_reason(tower, towed)` is not `""`. The reason is, in this order:
- `"destroyed"`: either ship destroyed;
- `"struck"`: either ship struck;
- `"aground"`: either ship aground (**B (new)**: an aground ship cannot move, so the tow is cast off rather than
  holding both ships);
- `"taken"`: the tower captured, or the towed ship's side no longer the tower's.

It is called at the end of:
- `DamageController.strike`;
- `DamageController.destroy`;
- `BoardingController.capture` (for the taken ship);
- `BoardingController.retake`;
- `MapController.ground`.

**Hull critical #6 (12.A.6).** In `CriticalHitController`, "hull_structural_damage": after the 1H, if the ship is
still towing or in tow, roll one d6 (`game_state.dice`), stored as `data["tow_roll"]`. On a 1 the tow is cut
(`"structural"`, `by` the ship). This adds a die to the hull-crit dice order only when the ship tows or is towed.

**Escape.** See §8.

### 7. Drift (8.A.6) and gunnery (9.B.1b)

- `DriftResolver._linked_group` and `_held_by` walk `drift_group_ids()` instead of `linked_ids()`. A tower and her
  tow drift as one group: one d10 by the member least likely to drift, no partial drift, held when any hex is
  blocked.
- `_is_eligible` is unchanged. A pair that moved this g-t (both `moved_this_turn`) does not drift. A pair whose
  tower did not move does.
- `GunneryResolver`: the `raked_dismasted` MC is skipped when the target is in tow and her tower is not
  dismasted (9.B.1b).

### 8. Escape (B, register; refined)

- **Tower escapes.** `MapController.escape(tower_id, ...)` first notes the towed ship. Once the tower has escaped,
  it carries the towed ship with her:
  - an own ship escapes too: `escape(towed_id, {"how": "in_tow", "tower": tower_id})`. She becomes ESCAPED and
    scores the escape share;
  - a prize is carried off: off the map, her tasks dropped, ESCAPED event with `"how": "in_tow", "prize": true`.
    She keeps her CAPTURED status. **B (refined):** ESCAPED status would hand her value back to her original side
    (an escaped ship scores for her owner, VI.B.6). Her captor carried her off, so she stays a capture.
  - The tow is then cleared without a TOW_CUT event.
- `BoardingController.recapture_due` is false for a ship off the map, so a carried-off prize is never retaken.
- `MapController.resolve_escapes` skips a towed ship (she escapes only with her tower).
- For a tower, the D.1c speed test takes her 12.A.7 loss off her own maximum (`MapRules.condition(..., mp_loss)`).
- An escape edge crossed in movement works through `_leave_map` as today. The follow of that last step has put the
  towed ship in the hex the tower's stern left.

### 9. Events and the combat log

New `PhaseEvents.Type` values, appended after `VEER_IN`:

| Type | Data | Line |
|---|---|---|
| TOW_BEGUN | roll, modifier, modifiers, total, needed, success; ship_id the tower, target_id the towed ship | "Ajax takes Brunswick in tow (d10 3 −3 = 0, needs 2 or less)" / "Ajax fails to pass a tow to Brunswick (…)" |
| TOW_CUT | cause (`tx`, `struck`, `destroyed`, `taken`, `aground`, `structural`), by | "The tow between Ajax and Brunswick is cut by Ajax" / "… parts: Brunswick has struck" |

New `MovementTypes.ResolutionEventType` values, appended after `LEAD_SOUNDING`:
- `TOW_FOLLOW`: the towed ship follows, played like a MOVE;
- `TOW_HELD`: the tower's step is undone because her tow cannot follow; detail is the reason.

Other changes:
- STOPPED_SHORT with cause `"tow"`: "… held back by her tow".
- COLLISION with `"tow": true`: "Brunswick runs into her tower Ajax".
- ESCAPED `"how": "in_tow"`: "Brunswick escapes in tow of Ajax" / "Ajax carries off the prize Brunswick".
- CREW_TASK names: PT "prepare to tow" / "preparing to tow"; TX "cut the tow" / "cutting the tow".
- None of the new types counts boxes, so `PlayerView.BOX_FIELDS` is unchanged.

### 10. PlayerView (B (new), mirroring anchoring ruling 8)

- The tow itself is public: `towing_id` and `towed_by` are on the board.
- `tow_prepared` is hidden from every reader who does not command the ship.
- PT crew tasks are hidden from those readers, as are CREW_TASK events with code PT.
- With limited information off, everything shows.

### 11. Stub AI (B, register; refined)

Constants: `TOW_SAFE_RANGE := 8`, `TOW_CUT_RANGE := 3`.

**`tow_target(ship) -> String`** returns `""` unless:
- the ship is active, its crew can act, and it is neither towing nor towed;
- it is not anchored, not aground, not dismasted and not linked;
- no enemy in play is within `TOW_SAFE_RANGE` (closest hexes).

Otherwise the target is the nearest friendly ship on the map (closest hexes, ties by ship id) that:
- is dismasted or a captured prize;
- is not struck or destroyed;
- is neither towing nor towed;
- is not anchored, not aground and not linked.

**B (new):** a candidate goes only to the nearest such AI ship of her side, ties by ship id. Two towers never chase
one cripple.

**`tow_order(ship)`, set in `assign_crew` as `crew_orders.tow`:**
- towing: `"cut"` when an enemy in play is within `TOW_CUT_RANGE`, else `""`;
- in tow: `""` (**B (new)**: the tower decides);
- otherwise `"take:<target>"` or `""`.

**Strategy (`_get_strategy`, before the escape posture):**
- towing: `"escape"` when `MapRules.may_declare(scenario, side, turn)` (declare, then run for the edge, taking the
  tow), else `"disengage"`;
- with a tow target: the new `"tow"` strategy.

The `"tow"` strategy steers for the station pose:
- The ideal bow is `station + DIRECTIONS[target.facing]`, the stern on the station, straight ahead of the tow.
- The score is `FIRING_POSITION_BASE − _turn_steps(facing, target.facing)` with the stern on the station, else
  `−(2 × distance(bow, ideal bow) + misalignment)`.
- It runs through `_steer(..., hold = true, avoid_bows = true, max_moves = 1)`. The new `max_moves` stops adding
  moves once that many are made and the course can be submitted.
- So the ship slows by her full deceleration each turn and arrives at ≤ 2 MPs, which 8.C.1 needs.
- Deceleration padding avoids the other ships' hexes, as for follow.

### 12. Scenario, Developer UI and server authority

- **Starting tow (B (refined)).** The register said "no tow at scenario start unless trivial". It is trivial and it
  lets the test scenario open with a tow under way.
  - Format: per ship, `"tow": "<towed ship id>"` on the tower.
  - `TowRules.scenario_errors(scenario, ships)` (reported by `GameState.placement_errors`) checks: an unknown id,
    the ship itself, a ship towed twice or both towing and towed, and `pair_error(setup = true)` at the placed
    positions.
  - `TowController.place_scenario_tows()` runs in `GameState.start_new_game` after `place_scenario_anchors`.
- **Dev commands** (server and debug builds only):
  - `DevCommands.tow_ships(tower_id, towed_id := "") -> String`. An empty `towed_id` means the ship whose tow
    station is the tower's stern hex. It checks `pair_error(setup = true)` and needs no PT and no roll.
  - `DevCommands.cut_tow(ship_id) -> String`.
  - The Developer UI's per-ship controls gain "Take in tow" and "Cut tow".
- **`test_server_authority.gd`** forbids, in view code:
  - writes to `towing_id`, `towed_by` and `tow_prepared`;
  - calls to `begin_tow`, `cut_tow` and `set_tow_prepared`;
  - any `tow_controller.` use.

### 13. View (U: view-only minimum)

- **Playback.** `MovementResolutionPlaybackController._posed_in` poses `TOW_FOLLOW` like `MOVE`.
  `_special_events` skips it. `TOW_HELD` pauses like a bear-off. `_tracks` gives a towed ship the plot steps of
  her tower (`log.towed_by`).
- **`TowLines`** (`scripts/view/tow_lines.gd`, like `GrappleLines`): one hawser from each tower's stern hex to her
  tow's bow hex. `GameController._sync_all_views` refreshes it.
- **Badges.** `PlanningSailUi.status_badge` shows `"TOWING"` and `"IN TOW"` after `"ANCHORED"` and before
  `"DISMASTED"`. Both are listed in `movement_block_reason`: the IN TOW reason is "Ship is in tow and follows her
  tower (12.A.6).". TOWING does not block plotting, so `can_plot_movement` stays true for it.
- **Crew overlay.** A read-only "Tow" station (`TowRules.STATION`). It is shown while the ship is towing, in tow,
  prepared, or has a section on PT/TX, with a rect in `deck_layouts.json`. Its refusal says towing is ordered with
  the crew orders.
- **Combat log:** the §9 lines.

### 14. Determinism

- The movement resolver draws tow dice only from its own rng, inside the pass. Re-runs from `rng_start` repeat
  them.
- `game_state.dice` gets:
  - the tow attempt d10s (STATUS_ADJUSTMENT, towers by ship id, before the grapple rolls);
  - the hull #6 d6 (only for a ship in a tow).
- Drift groups use the existing dice order.
- With no tow on the board, no die is added anywhere.

### 15. Builder's calls, collected

Register calls kept:
- the wake rule (U);
- the faithful start (U);
- blocked tows: the tower collision ram, and a third ship's hex undoing the tower's step;
- no momentum;
- friendly ships and prizes may be towed, own struck ships may not;
- the 12.A.7 loss, the tacking and acceleration readers;
- drift as a group;
- hull #6;
- the 9.B.1b exception;
- escape with the tower;
- the AI;
- automatic cuts.

New or refined, with their reasons in their sections:
- two ids rather than a partner and a role (§2);
- the tow attempt ordered by a standing crew order and rolled at the start of the Grappling sub-phase with no
  prompt (§3, §4);
- the position checked when the attempt is rolled (§4);
- anchored ships neither tow nor are towed, and a ship in a tow cannot anchor (§4);
- a dismasted ship cannot tow (§4);
- the towed ship's old hexes are held for the segment (§5);
- a towed ship hit or fouled holds her tower (§5);
- a tow rollback without deceleration padding (§5);
- a towed ship takes the unit's speed (§5);
- a tow parts when either ship runs aground (§5, §6);
- a carried-off prize stays CAPTURED (§8);
- preparation hidden (§10);
- the AI's claim rule and the towed ship never cutting (§11);
- a starting tow in scenarios (§12).
