# Sub-project 5 — Towing: decision inputs

## 1. Rules summary (docs/rules/close_action.md 1708–1762, charts checked)

- **12.A.2 Restrictions.** Only friendly ships may be towed, captured prizes included. One tow per tower, one tower per tow; a towed ship cannot tow.
- **12.A.3 Preparing (PT).** One CS plots PT for **5 ± SK** consecutive g-t's and does nothing else. The OCR reads "54SK"; the ship log (ship-log-blank-1.png) gives "PT Prepare to Tow 5±SK", 1 CS. The rule does not say how long a ship stays prepared.
- **12.A.4 Beginning the tow.**
  - (a) At the end of movement the tower's **stern** must be in the hex **ahead of the towed ship's bow**. Wind facings may differ.
  - (b) In the Grappling sub-phase (SoP V.C) only the tower rolls a grapple, "rolled normally", with its SK modifier. Neither ship may be grappled or fouled to any ship, each other included.
  - The grappling chart adds **"attempting to tow −1"** (`grappling_table.json` `drm.towing`, already transcribed).
  - (c) If the grapple succeeds, a tow counter is placed and the two ships move as a unit until the tow is cut.
- **12.A.5 Following.** The towed ship follows the tower's general path. In priority order it (a) must stay adjacent, (b) points its bow at the tower if possible, and (c) may move ahead and turn, or turn and move ahead, in **one segment**.
  - In Diagram 24 the positions are numbered 1–4, while the text calls them A–E. Settled: the unnumbered Heureux/"X" position is A, and 1–4 are B–E.
  - In the example the towed ship moves only when it must. In position C it does not move while the tower moves ahead, so it lags behind.
- **12.A.6 Plotting.** Only the tower plots, and only its MA counts. **Hull critical #6 (Structural Damage)**: lose 1H, and if the ship is towing or towed, roll d6; on a 1 the tow cable is cut. This is confirmed on the hull-critical-hits.jpg chart, for either ship.
- **12.A.7 Speed loss (MPs).** The tower loses:
  - −1 for towing;
  - −1 per class it is smaller than the tow (class 1 is the largest, so the loss is max(0, tower.class − towed.class));
  - −1 more if the tow is dismasted or furled.
  - Example: a class 3 ship towing a dismasted class 1 ship loses 4.
- **5.E.5.** The tower's acceleration is −1, never below 1. This is implemented.
- **Tacking table.** The tower gets +1 (`tacking_table.json`, implemented). **12.A.8**: a tower at MA 0 may turn by rolling on the Tacking table, as normal.
- **12.A.9 Cutting (TX).** Either ship may cut by plotting TX: 1 CS, 1 g-t (ship log: "TX Cut Tow 1"). The cut takes effect in the Maintenance Phase, SoP **V.B "Anchoring & Towing"**, which comes after drift (V.A) and before grappling (V.C) (2.B.5b).
- **12.A.10.** When a towed ship's bow contests a hex with any other ship, the towed ship always wins.
- **12.A.11 Tow collisions.** The towed ship and the tower can collide, either when the tower "decelerates faster than the towed ship can" or when the tower collides with a third ship. The towed ship cannot bear off and collides automatically: rigging damage, then a fouling roll. The tow is not broken.
- **Elsewhere:**
  - 5.D.1b: a dismasted ship turns while under tow.
  - 5.D.7: a ship can be "towed out of irons".
  - 8.A.6: a tower and its tow drift as one group.
  - 9.B.1b: a dismasted ship raked while under tow takes no MC unless the tower is also dismasted.
  - 10.H.2: prizes may be towed by friendly ships. A prize cannot plot TX (it plots only boarding and repairs), so only the tower can cut.
  - 2.B.2: PT is plotted in the Plot Phase.
- **Searched and not found:** a ships'-boats or boat-towing rule. 1.E.4 says the boats counters are unused in CA. There is no rule for towing becalmed ships, and no other chapter-12 content.

## 2. Current code

- `scripts/state/ship_state.gd`: `towing: bool` (l.76), serialized (l.602/677). Nothing sets it, and there is no towed-by or partner field.
- **Readers of `towing`:**
  - `movement_resolver.gd:_calculate_tacking_drm` (+1, l.1594);
  - `ship_state_controller.gd:speed_change_limits` (5.E.5, l.79);
  - tests `test_movement_resolver.gd:381/503` and `test_critical_steering.gd:255`.
  - `grappling_controller.gd:grapple_chance` does **not** apply the tow −1; the header says "no towing in Leeward". `CombatTables.grapple_drm("towing")` exists.
- **MA is computed in two places**, so the 12.A.7 loss must go into both:
  - `ShipStateController.get_movement_allowance`: table, then `critical_mp_loss`, then `BlockedWind`;
  - `MovementValidator._build_plotting_state`: `mp_loss` l.183, `BlockedWind` l.209.
- **Movement:** `MovementResolver.run` → `_resolve_pass` → `_resolve_impulse`.
  - Each ship makes one plotted step per segment and enters exactly one hex (`_entered_hex`): bow for an ahead step, stern for a turn.
  - Each segment groups stern entries and bow entries, then resolves them in dependency order with cycle speculation.
  - Overlap rollbacks, stern contests and bear-off re-runs replay the whole pass from `rng_start`.
  - `_get_plotted_steps` returns [] for linked or out-of-play ships.
  - Nothing in the resolver models a ship whose steps are derived from another ship.
- **Plot refusals:** `MovementPlottingController._plot_refusal` and `DefaultCourse.can_plot` (SHIP_FOULED, SHIP_GRAPPLED, …).
- **Drift:** `drift_resolver.gd:_linked_group` walks `ShipState.linked_ids()` (fouled ∪ grapples). `linked_ids()` is also read by marine fire, boarding, `take_link_snapshot` and fire spread, so a tow must **not** be added to it.
- **Grappling:**
  - `GrapplingController.grapple_error/options/chance` and `resolve_grapples` (ordered pairs, d10 per attempt in ship_id order).
  - `grapple_error` includes the 8.C.1 rule (both ships ≤ 2 MPs) and bans burning ships and CQ F/G.
  - Maintenance prompt: `TurnPhaseController` `MaintenanceStep {GRAPPLE, UNGRAPPLE, PRIZE}`, `maintenance_options`, `player_submit_maintenance_orders`. UI: `scripts/ui/maintenance_orders_panel.gd`.
- **Crew tasks:**
  - Handlers are registered in `game_state.gd:130–143`.
  - `crew_tasks.json` has no PT or TX rows.
  - Crew orders live in `plotted_actions.crew_orders` (`sail_target`, `boarding`); `CrewAuto.allocate` places ordered tasks.
- **Hull #6:** `critical_hit_controller.gd:473` (`_hull_boxes` only).
- **Dismasted rake MC:** `gunnery_resolver.gd:163` (`raked_dismasted_tN`).
- **Prizes:** `ShipState.is_captured()` and `has_prize_crew()`; `can_handle_lines()`.
- **StubAI:**
  - Strategies engage, close, follow, line, disengage, via `_steer`.
  - `grapple_orders`/`ungrapple_orders` never grapple friends.
  - There is no tow logic.
- **feature_diff §2.2** row "Towing | 12.A" is open, and the 5.E.5 row notes that towing does not exist yet.

## 3. Work breakdown

| # | Component | Files | Size |
|---|---|---|---|
| A | Tow state: `tow_partner`/`towed_by` ids (replace or derive `towing`), `tow_prepared`; serialize; `ShipStateController.begin_tow/cut_tow`; `is_towing()`/`is_towed()` | ship_state.gd, ship_state_controller.gd | S |
| B | PT and TX crew tasks: json rows, `TowTaskHandler` (PT completes → prepared; TX completes → cut in V.B), `CrewRules` refusals (PT needs no tow, TX needs a tow, a prize may not TX), a crew order `tow: "prepare"/"cut"` placed by `CrewAuto` | crew_tasks.json, new tow_task_handler.gd, crew_rules.gd, crew_auto.gd, game_state.gd | M |
| C | Begin tow: `tow_error/options/chance` (12.A.4a position, prepared, friendly, no links, the 8.C grapple bans, tow −1 DRM); new `MaintenanceStep.TOW`, or tow options folded into GRAPPLE; `TOW_BEGUN`/`TOW_FAILED` events | grappling_controller.gd (or new tow_controller.gd), turn_phase_controller.gd, phase_events.gd | M |
| D | Cutting: V.B step after drift (TX), plus automatic cuts (either ship struck, destroyed or captured by the enemy; the tower becomes linked to a third ship?); hull #6 d6 (changes the dice order only when towing); `TOW_CUT` | turn_phase_controller.gd, critical_hit_controller.gd, damage/boarding hooks | S–M |
| E | 12.A.7 MA loss in both MA paths; the towed ship refuses plots (`SHIP_TOWED`) and `DefaultCourse` skips it; grapple DRM | ship_state_controller.gd, movement_validator.gd, movement_plotting_controller.gd, default_course.gd | S |
| F | **Resolver: the towed ship follows the tower each segment.** Its step is derived after the tower's step settles. It may enter 2 hexes in one segment, wins hex contests (12.A.10), and must stay correct under rollbacks, cycle speculation, bear-off re-runs and stern contests. New event type(s); speed and `moved_this_turn` of the towed ship; clears in-irons | movement_resolver.gd, movement_types.gd, apply_results | **L — the hardest part** |
| G | 12.A.11 tow collisions (scope depends on Q2) | movement_resolver.gd | S–M |
| H | Drift group adds the tow partner (separate helper, not `linked_ids`); the towed ship drifts only with its stopped tower | drift_resolver.gd | S |
| I | 9.B.1b MC exemption | gunnery_resolver.gd | S |
| J | StubAI: when to PT, steer to the tow position, tow order, behaviour while towing, TX (Q4) | stub_ai.gd | M–L |
| K | View: playback of follower moves (two hex moves in one segment), tow line on the map (reuse `GrappleLines`), maintenance panel row, crew overlay PT/TX stations (`deck_layouts.json`), card badge (Q5) | ship_view, grapple_lines, maintenance_orders_panel, crew_overlay | S–M (minimum) / L (full) |
| L | `PlayerView` (tow fields stay visible), `dev_commands.tow_ships(a,b)`, server-authority scan list, scenario field for a tow at start? | player_view.gd, dev_commands.gd, test_server_authority.gd | S |
| M | Tests (ScriptedDice dice order for tow grapple and hull #6), feature_diff §2.2 → §2.1 ✔ and §4 deviations, CLAUDE.md | test/unit, docs | M |

## 4. Decisions needing the user (in order of importance)

**Q1. How the towed ship moves.** This is the core of F.
- **(a) Rule as written.** Each segment, after the tower's step, the towed ship picks the smallest move that keeps it adjacent and pointing at the tower: stay, turn, ahead, ahead+turn, turn+ahead. It lags as in Diagram 24 position C. This is faithful, but the resolver must allow two hex entries per segment, and the candidate tie-breaks are ours to invent.
- **(b) Wake-following ("train").** On every tower step the towed ship's bow takes the hex the tower's stern just left, pointing at the tower. It never needs two entries in a segment, it nearly always enters hexes the tower has just vacated, and it is easy to show and predict. The towed ship moves every MP where the rule lets it lag, so a turning tow swings differently from Diagram 24.
- **(c) Post-pass.** Resolve everyone else, then place the towed ship by rule (a) with no conflict checks. This is the cheapest. Third ships can end up overlapping the tow, or need ad-hoc fixes.
- **Recommendation: (b), recorded in §4.** It reuses the one-hex-per-step machinery, so rollbacks and replays stay sound, and it is the most predictable for players. Diagram 24's opening move (B) is the same under both models.

**Q2. What happens when the tow is blocked or the tower stops (12.A.11, and a third ship in the towed ship's path).**
- (a) Full rule: the tower's deceleration (tracking the towed ship's own momentum) and the tower's collision both make the towed ship ram the tower (rigging damage, fouling roll, tow kept).
- (b) Only the third-ship case: when the tower is stopped by a collision, the towed ship rams it (automatic collision, rigging, fouling roll). The deceleration case is dropped, because under 12.A.6 the towed ship has no momentum of its own.
- (c) No tow-internal collisions: the towed ship just stops when the tower stops.
- A follow move into a hex held by a stationary third ship is handled the same way in every option: (i) the tower's step is undone, like an overlap rollback, or (ii) the towed ship collides with that ship.
- **Recommendation:** (b) plus (i). It keeps the dramatic case without inventing momentum for a ship that cannot plot.

**Q3. How costly starting a tow is.**
- (a) Faithful: PT for 5 ± SK g-t's; the tower's stern ahead of the tow's bow; a grapple roll at ≤ 2 with tow −1; every 8.C ban, including both ships using ≤ 2 MPs that g-t.
- (b) As (a) but without the 8.C.1 MP limit ("rolled normally" arguably means the roll and its DRMs only).
- (c) Simplified: no PT; a tow is ordered and always succeeds when in position.
- **Recommendation: (a).** Towing is a slow rescue, and the cost is the game. Note that (a) makes AI towing rare.

**Q4. When the stub AI tows.**
- (a) Never initiates a tow. It only cuts or accepts tows, so it is not "able to play" the feature.
- (b) Narrow: an AI ship with no enemy within N hexes (e.g. 8) prepares, then tows its nearest friendly dismasted ship or prize, then disengages, pulling it toward its side's starting edge. It cuts with TX when an enemy closes within K hexes, or never cuts.
- (c) Rich: a standing order "TOW <ship>" by signal (sub-project 2's `SignalOrders`), plus (b).
- **Recommendation: (b), with "cut when an enemy is within 3".** A TOW signal order can follow cheaply if wanted.

**Q5. Is any UI in scope?**
- (a) Back end only, plus `dev_commands.tow_ships`; the towed ship snaps to its new hexes after playback.
- (b) Minimum to see and play:
  - follower playback in `ShipView`;
  - a tow line on the map;
  - a TOW option in the existing maintenance panel;
  - PT/TX stations in the crew overlay;
  - a TOWING/IN TOW card badge.
- (c) Full UX, including the tower's course preview dragging the tow and the MA-loss breakdown on the card.
- **Recommendation: (b).** Without follower playback the game looks broken, and the rest reuses existing widgets.

**Q6. What may be towed beyond active friendly ships.**
- Allowed by the rule: friendly prizes (10.H.2), with or without a prize crew.
- Silent in the rule: own-side **struck** ships. Options: (a) allow, since a struck ship is still "friendly" by side, or (b) forbid, since a struck ship has surrendered (9.C) and the enemy should take her.
- **Recommendation: (b).** It avoids "rescuing" a surrendered ship, which reads as an exploit in PVP.

**Q7. Order against sub-project 3 (map exit/escape).** Towing's main payoff is getting a cripple or prize off the map.
- (a) Build towing now as-is.
- (b) Build after sub-project 3, and let a towed ship escape with its tower for points.
- **Recommendation:** if sub-project 3 is not yet built, either (b) or accept that towing only moves ships out of gun range for now. Either way, settle whether an escaped tow scores as "saved".

## 5. Decisions the builder can make alone

- State: `tow_partner: String` on both ships plus `tow_role` (or `towing_id`/`towed_by`). Keep `towing` as a derived `is_towing()` and update its three readers and the tests.
- Being prepared persists until a tow begins. After any cut, the ship must prepare again (new cable). Losing the PT section mid-task resets progress (4.A.3 engine).
- Begin tow sits in the GRAPPLE maintenance step as a second option kind `{"tow": [[tower, towed]]}`. It is rolled in the same pass in ship_id order. A tow attempt and a grapple between the same pair are exclusive.
- The tow is cut automatically, with no TX and no roll, when either ship is struck, destroyed or captured by the enemy, or when the towed ship becomes enemy to the tower. The towed ship's grapples to others block the unit's movement (8.C.7 applies to the unit). The tow is not cut.
- TX may be plotted by the tower or the towed ship, but not by a prize, which may only plot boarding and repairs. The cut applies in V.B, before grappling, in the same g-t.
- 12.A.7 loss applies after the table and `critical_mp_loss`, floor 0, before `BlockedWind`. "Furled" means sail state `ns`. Class difference is max(0, tower.class − towed.class).
- Tacking +1 applies to the tower only. When the tower tacks at MA 0, the towed ship follows the turn. A towed ship that turns leaves irons (5.D.7); dismasted towed ships turn (5.D.1b).
- After movement the towed ship's speed equals the hexes it actually moved, with `moved_this_turn` by the same test. On a later cut, its deceleration minimum comes from that.
- Drift: a new `drift_group_ids()` = `linked_ids()` ∪ tow partner. A towed ship drifts only when its tower drifts.
- Hull #6: one d6 after the 1H when the ship is towing or towed; on a 1, `TOW_CUT` with cause "structural". Document the dice-order change.
- 9.B.1b: skip the `raked_dismasted` MC when the target is towed by a ship that is not dismasted.
- Teams: no consent from the towed ship's commander; either commander may TX. Both see the tow (it is position-like, so not hidden by `PlayerView`).
- No tow at scenario start (no scenario field) unless trivial.

## 6. Dependencies and risks

- **Resolver complexity:** `movement_resolver.gd` (2,130 lines) replays whole passes on rollbacks, contests and bear-offs. A derived ship must be a pure function of the tower's resolved steps, or replays diverge. Its new hexes must take part in occupancy, cycle detection and 6.B overlaps. Consider adding a property-style test that runs every existing resolver scenario with a tow attached.
- **Grapple roll vs PT:** the PT handler and begin-tow logic sit in GrapplingController or a new TowController, and `test_server_authority.gd` needs its query list extended.
- **Sub-project 3** (escape, map edge): the value of towing and a possible "saved by tow" scoring rule. **Sub-project 4** (anchoring) shares SoP V.B "Anchoring & Towing" and hull #6 (anchor cable cut), so build one V.B step and one #6 roll path both can extend.
- **Sub-project 2 (signals):** an optional TOW standing order (Q4c) extends `SignalOrders`.
- **View:** `ShipView` playback assumes one step per segment per ship. A follower with two moves in a segment under Q1(a) needs view work, which is one more reason for Q1(b).
- **AI:** steering to "stern ahead of the tow's bow" is a new `_steer` score. It may fail upwind, which is already a known limitation ("stalls instead of tacking").
