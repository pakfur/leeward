# Close Action vs. Leeward: Feature Diff

**Scope:** *Close Action: The Age of Fighting Sail, Vol. 1* (1997) rules book, sections 1–14 (`docs/rules/close_action.md`, lines 132–1967). The rating system, tournament rules, designer's notes and scenario book are out of scope.

**Compared against:** the Leeward code on `main` at `30a2c35` (`scripts/`, `data/rules/`, `data/scenarios/`). Rows changed later were re-checked against the code when they were edited; latest: `9d8e8e2` + blocked wind (5.G), collision rigging loss (6.E.3), the fast-tack bonus removal (5.B.3) next-turn wind changes (3.B.6) and bearing off as a decision (6.D).

**Purpose:** a feature-level list of what the board game has that Leeward lacks, and of the places where both have a feature but the outcome differs significantly. It is not a play-by-play comparison. UI and presentation differences are ignored.

**Method:** eight reviewers each read one slice of the rules and compared it with the code. The lead reviewer then re-read the code behind every finding marked ✔ below. Unmarked findings come from the slice reviews only, and should be treated as reliable but not re-checked. Findings marked **?** could not be settled from the rules text alone, usually because the deciding chart or diagram is an image.

**Legend:**
- **Known**: already listed in `CLAUDE.md` as Milestone 2/3 or as a known limitation.
- **New**: not recorded anywhere in the project docs.
- Status words, the same in §1 (Type column) and §3 (lead word of the Leeward column): **Missing** (Leeward lacks it), **Differs** (both have it, the outcome differs), **Partly fixed** (a difference was fixed, another remains), **Fixed** (it now matches the rules). A §3 row with no lead word still differs.

---

## 1. Headline items

These are the gaps and differences that most change how a game plays out, in rough order of impact.

| # | Item | Rule | Type | Status |
|---|------|------|------|--------|
| 1 | Critical hits, rigging checks and hull checks. **Partly fixed:** the gunfire crit roll (natural 6, CH d6 ± CH mod ≤ CH#), the 2d6 Crit column by aim, RC/HC d6 for every emptied rigging section and hull sections 1–3 (gunfire, crit boxes, collisions; FIFO chaining, 7.D.12), the ◆/[D]/dismasted chart notes, stern-rake guns on both sides, the bow-rake rudder conversion and crit MCs are in (`critical_hit_controller.gd`). Broadside obscured −2 per entry on the firing side (7.C.11, in the gunnery preview), the 8.D.5 fix rolls in STATUS_ADJUSTMENT (obscured sides, braces cut, lines jammed, rudder jammed; sheets cut ends after the next turn), and Lines Jammed (no sail plotting, a change in progress cancelled, cleared on dismasting) are in. Movement effects are in: −1 MP for sheets cut (at most one, from the g-t after it was inflicted) and each shrouds severed, before blocked wind; `ShipStateController.get_speed_change_limits` (table, 5.E.5 reductions with floor 1, Braces Cut ≤ 1/1, Sheets Cut −1 to 0). Steering is in: the Rudder Jammed direction (last step executed, spec Q15) and its plotting limits, one turn per g-t for rudder destroyed / wheel shot away, the Poor Maneuvering roll per plotted turn (6.F.3–5, RD rerolls each hex, left-over turn via `ShipState.pending_turn`, both rolls at MA 0), RD entering WF=L in irons, and the Tacking (+3 RD) and Bearing Off (+3 RD/RJ, +1 poor maneuvering) DRMs (`movement_validator.gd`, `movement_resolver.gd` (`_roll_poor_maneuvering`)). Hull #12 is in: afire (`fires` + 1, logged FIRE_STARTED; fire itself is not simulated), 1H, −2 guns on each broadside, an MC, and the 2d10 explosion roll (CQ A +3 … G −3, −2 per existing fire, −1 when the scenario's optional `year` ≤ 1783; explodes when < class). An explosion sets the new status DESTROYED (spec Q2): out of play like a struck ship and counted as lost for victory, but it never drifts, fouls (its partner is freed) or takes damage, and its two hexes still block movement and line of sight; the view shows a procedural wreck. | 7.D.7, 7.D.8a, 7.D.11–12, 6.F | Fixed (except the deferred items in §2.2) | Known |
| 2 | **Fixed.** The tacking roll never ran during play. Now any turn plotted at MA 0 rolls on the Tacking table, a failed roll erases the turn, and the turn ends the ship's move for that g-t. ✔ | 5.D.1–3 | Fixed | — |
| 3 | **Fixed.** A ship in irons could not turn out. Now it may plot one turn, rolled with the +1 in-irons DRM; if it plots no turn it stays in irons. ✔ | 5.D.6 | Fixed | — |
| 4 | **Fixed.** Blocked wind (wind shadow) was absent. Now a ship whose windward hexes (two at WF=C/B, one at WF=R) are all held by ships at FS or above, not dismasted, loses 1 MA, never down to 0. ✔ | 5.G | Fixed | — |
| 5 | Boarding, grappling, capture and prize crews are absent, so a struck ship is the end state. | 8.C, 10.A–H | Missing | Known |
| 6 | Fire, explosions and repairs are absent, so all damage is permanent. | 8.E, 8.F | Missing | Known |
| 7 | **Fixed.** Bearing off is the owner's decision: movement playback pauses at the player's potential collision and asks bear off to port / starboard (only legal turns, with the chart odds) or hold course; the other ships' remaining plots are shown (6.D.3a). On success the ship turns, then moves ahead to its deceleration minimum; once per g-t. The AI always bears off when it can (never rams). ✔ | 6.D.2–5 | Fixed | — |
| 8 | **Fixed.** Collision rigging loss was a fixed 2/4/6 boxes. Now it is d6−1 (FS), d6+1 (MS) or 2d6 (PS), taken by the ship that runs into the other, and by both when they run into each other. ✔ | 6.E.3 | Fixed | — |
| 9 | **Fixed.** Speed counts executed steps, turns included, if the ship moved ahead at least once, else 0 (5.E.2). The "fast-tack" +1 MA bonus for a first turn from C to B, which the rules forbid, is gone. ✔ | 5.E.2, 5.B.3 | Fixed | — |
| 10 | **Fixed.** Wind changes took effect in the turn they were rolled. Now a change rolled in turn N is held as pending, logged as a forecast ("Next turn the wind …"), shown on the minimap, and takes effect at the start of turn N+1's weather phase. ✔ | 3.B.6 | Fixed | — |
| 11 | **Fixed.** The contested-hex class bonus went the wrong way. Now it is +1 per class larger (lower class number). ✔ | 6.C.2c | Fixed | — |
| 12 | **Fixed.** Each side has a bow and a stern battery with its own arc and LOS (7.B.2–6); range is to the closest hex (7.C.4). Fire orders name the battery (7.B.1): a full broadside when both bear, otherwise the bow or stern battery as a half broadside (−8, not with two targets, 7.C.12f–g); a side may split its batteries between two targets (partial targets); the initial-broadside bonus counts once per broadside (7.C.10). The fire panel offers these choices and shows the numbers the resolver rolls. | 7.B.1–6, 7.C.10, 7.C.12f | Fixed | New |

---

## 2. Features in the board game that Leeward lacks

### 2.1 Already known (CLAUDE.md, Milestone 2/3)

| System | Rules | Notes |
|---|---|---|
| Critical hits (rigging and hull tables, RC/HC checks, CH#) | 7.D.7, 7.D.8a, 7.D.11–12 | **Partly fixed:** crits and RC/HC checks are rolled and their boxes, guns dismounted, MCs (9.B.1e) and effect entries applied (see §1 item 1). Broadside obscured −2 (7.C.11), fixing with the Unfouling table (8.D.5) and the Lines Jammed sail-change rules (5.F.9c) are in. Poor maneuvering (6.F), Braces Cut and Sheets Cut acceleration (5.E.5–6) and MP loss are in. **Still missing:** the reorganize sail-change cancellation (5.F.9a, deferred with crew disorganized). |
| Fire and explosions | 8.E.1–11, 9.B.1c–d | Includes firefighting, spread, blast and flaming debris. Hull #12 counts fires and rolls its explosion (a destroyed ship stays on the map as a wreck, spec Q2); the blast damage to nearby ships is not applied. |
| Sinking | 8.E.8, 8.G | |
| Repairs | 8.F, 8.G.1b | Damage is permanent. |
| Grappling and ungrappling | 8.C | Fouling (from collisions) is the only way ships become entangled. |
| Boarding, capture, reorganizing, prize crews | 10.A–H | Only the `bcf_sailor` and `bcf_marine` values in `crew_quality_table.json` exist, and nothing reads them. Struck ships never change sides. Captured-ship BGN (1.G.8) is also absent. |
| Marine fire | 7.G, 4.B.4b | Marines count only as crew boxes. |
| General crew-task plotting (CS tasks) | 4.A.3c, 4.B | Sail changes are the only crew task. There are no tasks for tacking (T), boarding, repair, firefighting, anchoring or towing. |
| Lower-deck guns, freeboard vs. sea state | 7.F, 3.E.1 | `freeboard` and `lower_deck_modifier` are stored but never used. |
| Anchoring (springs, veering, cutting) | 8.B, 8.A.7, 13.A–F, 7.C.12c | Also missing: the anchored +1 gunfire modifier and the "free turn after cutting" exception to being in irons. |
| Medium guns, chase guns, class 4 ships | 1.G.7 | `mg` is 0 in the data. |

### 2.2 Not tracked anywhere yet

| Feature | Rules | Notes |
|---|---|---|
| Reinforcements | 2.B.1, 3.A | Every ship is placed at the start. |
| Escape and exit from the map, removal of escaped ships | 2.B.5g, 8.G.1f | Plotted movement is not even limited to the map (Known limitation). |
| Shallow water, land, running aground, casting the lead | 13.G | No depth map. `draft` is loaded and never read. Land does not block LOS (7.B.7). |
| Towing | 12.A | A `towing` field exists on the ship state, but no logic uses it. |
| Signalling and its limits | 4.A.4, 11, 8.G.1e | The MESSAGE_DELIVERY phase is a stub. This mostly matters for multi-player games. |
| Sail checks after a wind change | 2.B.1 | `# TODO` in the ENVIRONMENT phase. |
| Friendly-ship blocking hexes for LOS (medium and long range) | 7.B.10–12 | Only the hexes a ship occupies block LOS (both of its hexes now). Nothing discourages firing past friendly ships. |
| Voluntarily reducing the MGN | 7.C.14 | |
| Acceleration reductions (two rigging sections missing, WS=1, towing) | 5.E.5 | **Fixed:** −1 each, never below 1 (`ShipStateController.speed_change_limits`); towing itself does not exist yet. |
| "A stopped ship whose first MP is a turn cannot move further" | 5.E.8 | |
| A collision or grapple in WF=L puts the ship in irons | 5.D.5 | |
| Exceptions to being in irons (WS just rose from 0, cut cable, anchored) | 3.D.4c, 5.D.4 | A ship at WF=L with speed 0 always counts as in irons. |
| Reverse tack | 5.D.3 | |
| Contested-hex winner may force the loser into the hex | 6.C.3 | The winner always enters. |
| Order of bear-off resolution in one segment | 6.D.3c | Two potential collisions on the same segment are decided in the resolver's group order, not by a d10. Earlier segments do come first (6.D.3b) and the once-per-turn limit (6.D.5) is implemented. |
| Game ends by mutual agreement, or when one side has no ship that can move and fight | 2.A.1 | Leeward ends only when a side is all struck, or at `turn_limit`. A side that is dismasted but not struck keeps the game going. |
| Struck ships count as CQ G | 9.C.4 | Only matters once firefighting and ungrappling exist. |
| Crew disorganized (hull critical #4) | Hull Critical Hits #4, 5.F.9a | **Deferred until crew tasks exist.** Only the sailor box is lost. The section is not disorganized: it can still work sail and fire, and there is no reorganize ("RO") countdown. |
| Fire roll after a minor explosion (hull critical #10) | Hull Critical Hits #10, 8.E | **Deferred until crew tasks and fire exist.** 1H and −2 guns dismounted apply. The d10 ≥ 6 (± SK) fire roll is not made (it is also open whether SK modifies the die or the target). |
| Signal halyards cut (rigging critical #3) | Rigging Critical Hits #3, 11 | **Deferred until signalling exists.** Only the 1R loss at MS or PS applies. No lasting effect is recorded and no fix roll is made. |
| **Optional rules (14):** impulse movement with fire at the end of an impulse, voluntary surrender and rallying, limited information, fatigue, historical gunfire limits (E/F/G crews fire low only on 1–3; 50% forced high when firing to windward at WF=C/B) | 14.A–E | None are offered. Leeward's movement does resolve "impulses", but each one is a standard segment, not the 4-impulse proportional system of 14.A. |

---

## 3. Features in both, with significantly different outcomes

| Rule | Board game | Leeward | Effect on outcome | Code |
|---|---|---|---|---|
| **3.B.6** When weather changes take effect ✔ | A change rolled in turn N takes effect at the start of turn N+1. | **Fixed:** the ENVIRONMENT phase first applies the change rolled last turn, then rolls against the wind now blowing and stores the result as `pending_wind_speed` / `pending_wind_direction` (logged as a forecast WIND line, shown on the minimap). | Matches. | `environment_controller.gd` (`tick_environment`) |
| **3.D.3** Floor on wind speed ✔ | WS can only fall to 0 if the scenario started below 1. Otherwise a −1 at WS 1 is "No Change". | No floor. Any scenario can become calm. | Unplanned calms, with ships unable to move. | `environment_controller.gd:40-61` |
| **3.D.4b** Ending a calm ✔ | At WS 0, any "changes" result raises WS to 1. | The d10 is still rolled, and a decrease is clamped back to 0. | Calms last about twice as long. | `environment_controller.gd:48-61` |
| **3.B.5 / 7.C.12e** Sea state | Range 1–5. Its main effect is closing lower-deck gunports by comparison with freeboard. | Loaded and fixed (correct), but the code comments and dev UI treat it as 0–3. Its only effect is the dismasted-firer −sea state modifier. | Sea state hardly matters. | `environment_state.gd:17`, `gunnery_calculator.gd:82` |
| **5.B.3** How MA is spent ✔ | MA caps hexes ahead in the current WF. Turns use MPs against the speed band only. | Turns also cost 1 MA (`remaining = max_ma − spent`), with a free pivot when MA runs out. | Plots that mix turns and moves ahead give different totals. | `movement_validator.gd:150-190` |
| **5.B.3** "Never gain MPs by turning to a faster WF" ✔ | Explicit rule. | **Fixed:** the +1 MA "fast-tack bonus" for a first turn from C to B has been removed. | Matches. | `movement_validator.gd` (`_build_plotting_state`) |
| **5.C.3–4** Turn spacing | Applies across turn boundaries, and the table is indexed by this turn's plotted speed. | Reset every turn, and indexed by last turn's speed. | A ship can turn at the end of one turn and again at the start of the next. | `movement_validator.gd:194-200, 313-327` |
| **5.D.1–3** Tacking at MA 0 ✔ | Roll d10 on the Tacking table, with DRMs for SK, CSs not plotted to "T", rigging lost, in irons, towing, reversing tack, rudder, and not at WF=L (−2). A natural 0 always succeeds. If the roll fails, the turn is erased. | **Partly fixed:** the roll runs for any turn plotted at MA 0, uses the transcribed chart (`tacking_table.json`, which had stored every value 10% low) and applies the chart DRMs for SK, rigging, in irons, towing and not at WF=L. A natural 0 succeeds, the ship moves no further that g-t, and ships cannot turn in a calm (5.D.1a). The planning screen shows the same chance, modifiers included, whenever the ship starts at MA 0. The Rudder Destroyed +3 DRM is in. **Still missing:** the CS-plotted DRM (no crew tasks, so every ship counts as fully plotted) and reverse tack. | Matches, apart from the missing DRMs. | `movement_resolver.gd` (`_roll_tacking`, `_calculate_tacking_drm`) |
| **5.D.6** Turning out of irons ✔ | The player plots a turn and rolls with +1 DRM. On success the ship turns. | **Fixed:** the validator offers a ship in irons its two turns, and the plotted turn goes through the Tacking roll with the +1 in-irons DRM. A ship that plots no turn stays in irons. | Matches. | `movement_validator.gd`, `movement_resolver.gd` (`_remain_in_irons`) |
| **5.E.2** Definition of speed ✔ | Total MPs used, turns included. | **Fixed:** executed steps, turns included, if the ship moved ahead at least once, else 0; `moved_this_turn` follows the same test. | Matches. | `movement_resolver.gd` (`_count_steps_executed`) |
| **5.A.4 / 5.E** Deceleration minimum | The ship must use at least last speed − decel. | `validate_submission` is a stub that always succeeds. **?** Whether the plotting UI enforces `min_ma` was not traced. | Ships may be able to stop dead from high speed. | `movement_validator.gd:90-98, 140` |
| **6.C.2c** Contested hex, class bonus ✔ | +1 per class *larger* (class 1 is the largest). | **Fixed:** +1 per class larger. | Matches. | `movement_resolver.gd` (`_calculate_contest_drm_relative`) |
| **6.D** Bearing off ✔ | The player chooses whether to bear off. Roll d10 against the Bearing Off table, with +1/+2 DRMs for 4–6/7+ MPs plotted. On success the ship turns in an eligible direction and then meets its deceleration minimum. | **Fixed:** eligibility uses the plotting validator's turning rules on the steps made so far (6.D.2). The player's ship pauses playback and is asked (port / starboard / hold course, other plots shown); the answer feeds a re-run from the same dice. Success amends the plot (turn, then ahead to the deceleration minimum) and replays; once per g-t. The direction is chosen before the roll rather than after (same outcome). Rudder Destroyed/Jammed +3 and Poor Maneuvering +1 are in (RD = +4, spec Q9). | Matches. | `movement_resolver.gd` (`_resolve_collision_or_bearoff`, `bear_off_situation`, `_amended_steps`), `turn_phase_controller.gd` (`player_submit_bear_off`), `stub_ai.gd` (`bear_off_choice`) |
| **6.E.3** Collision rigging loss ✔ | d6−1 (FS), d6+1 (MS), 2d6 (PS), taken by the ship pointing at the other, or by both ships when they run into each other. The chart says "ramming ship only". | **Fixed:** rolled per the chart with the resolver's RNG for the ship whose move ahead runs into the other. The ship it hits rolls too when its own move ahead that segment was into the first ship (head-on). Drifting ships take none (drift has no rigging loss). | Matches. | `movement_resolver.gd` (`_apply_collision`, `collision_rigging_loss`, `_runs_into`) |
| **6.G.2** Failure to plot ✔ | The ship continues at last turn's speed. | The ship stays where it is (`SKIP_NO_PLOT`) and its speed becomes 0. | A ship whose player does not plot stops dead. Matters for the AI and for timeouts. | `movement_resolver.gd:55-67` |
| **7.E.2** Rake geometry ✔ | Target within 5 hexes, with the firer outside **all** of the target's fire arcs, or directly ahead or astern and adjacent. | **Fixed:** range to the closest hexes ≤ 5, firer outside all four of the target's battery arcs, or directly ahead of the bow / astern of the stern and adjacent. Stern vs bow rake by the target's beam line. | Matches. | `fire_geometry.gd` (`rake_type_ships`) |
| **7.C.12g** Two targets | The rule text says −10. | −12. The chart wins (already decided). | Recorded only. | `gunfire_modifiers.json` |
| **7.B.1 / 7.C.12f** Battery orders and half broadsides ✔ | Each side fires as a full broadside or as bow/stern half broadsides (−8), possibly at different targets; at most two targets. | **Fixed:** `FireOrder.battery` (`full`/`bow`/`stern`); `validate_orders` refuses a battery fired twice, more than two targets, and bow+stern of one side at one target; `preview_orders` gives two-target −12 (no −8) and the initial broadside once per broadside. The fire panel declares by battery. | Matches. | `gunnery_calculator.gd`, `fire_declaration_panel.gd` |
| **8.A.1 / 8.A.6** Who may drift ✔? | A stopped ship. A fouled pair that includes a ship that moved does not drift (example 2). | A ship drifts if it did not move, **or** collided, **or** is fouled. | Fouled ships drift in cases where the rules hold them. Depends on reading "stopped". | `drift_resolver.gd:68-72` |
| **8.D.1** Unfouling DRMs ✔ | Chart: ≤2/≤3/≤4 by attempt. DRMs (all uses): ± SK, +1 if marines not available. Ungrappling-only DRMs don't apply to fouling. | Same thresholds, ± SK. "Marines not available" can't arise because marine tasks don't exist. | Matches. | `fouling_controller.gd` |
| **9.B.1** Morale checks for lost sections ✔ | The ship log shows hull sections 1, 2 and 3 with 1, 1 and 2 MC marks (section 4 strikes), each sailor section and the marines with 1, and dismasting with 1. | The same counts: `HULL_MORALE_CHECKS = [1, 1, 2]`, 1 per emptied crew section including marines, and 1 on dismasting. | Matches. | `damage_controller.gd` |
| **9.C.3** Firing on struck ships ✔ | Struck ships "cannot do anything". The rules do not say they cannot be fired on. | Struck ships cannot be targeted. | Deliberate (see §4). It removes the option of shooting at a struck ship. | `gunnery_calculator.gd:28-29` |

---

## 4. Deliberate simplifications (for the record)

These are conscious design choices. They are listed because each one removes board-game outcomes.

- **Ships are 2-hex (Phase 1 done).** Per-hex LOS and partial targets (7.B.4–6), range to the closest hex, rake per 7.E.2, the automatic half broadside, bow-pivot turning and speed counting turns (5.E.2) are implemented. **Phase 2 done:** temporary overlap and rollback for swinging sterns (6.B), stern-vs-stern contests (6.C.5) and partial drift of a single unfouled ship (8.A.5: the free end drifts, the ship pivots, then fouling is rolled; groups never partially drift). **Phase 3 done:** explicit battery orders (7.B.1): full broadside, bow or stern battery (half broadside −8), split sides at partial targets, chosen in the fire panel.
- **A separate fire-declaration step after movement** (2.B.2, 7.A.2). Orders stay hidden until both sides have submitted. The outcome is the same as the board game's simultaneous fire.
- **Two sides, one human against the stub AI.** The multi-player rules (signalling 11.B, limited information 14.C) have nothing to apply to.
- **Struck ships cannot be targeted** (see the 9.C.3 row in §3).

---

## 5. Implemented and matching

Implemented with essentially the same outcome as the rules:

- Movement allowance lookup with rigging-level caps (5.A.2, 5.F.2–3).
- No MA gained by turning into a faster WF (5.B.3).
- Blocked wind: MA −1 (never to 0) when every windward hex (two at WF=C/B, one at WF=R) is held by a ship at FS or above that is not dismasted (5.G.1–3). Checked at the plotted position against the other ships where they stand. `BlockedWind` (`blocked_wind.gd`), used by `ShipStateController.get_movement_allowance` and the movement validator.
- Sail-change cost, timing and cancellation when a crew section is lost (5.F.6–9, 4.A.3b, 4.B.2–3).
- No more than two turns per g-t, pivoting on the bow (5.C.1–2).
- A turn into WF=L stops the ship (5.B.4).
- Simultaneous segment-by-segment movement (6.A.1–2).
- Contested-hex d6 roll with ties and the CQ and speed DRMs (6.C.2a–b, 6.C.6).
- Bearing off as the owner's decision: legal turns only, chart odds and plotted-MP DRM, turn then deceleration minimum, once per g-t; the player is asked mid-playback with the other ships' plots shown; the AI never rams (6.D.1–6.D.5, except 6.D.3c).
- Both ships stop on a collision, fouling at 6+, dismasted ships never foul (6.E.2, 6.E.4–5).
- Collision rigging loss: d6−1/d6+1/2d6 by sail state, for the ramming ship, or both ships head-on (6.E.3).
- The gunnery pipeline: TGF → BGN with French guns, CQ, sections firing, guns dismounted, initial broadside, rake bonus, plain sail at WS 2 or more, WS 4, dismantling shot, FGN = MGN + d6, slashed results, damage columns by sail state with furled sails halved, lowest section first, crew split by cause, stern rake doubling crew hits (7.C–7.E).
- Simultaneous fire with stern rakes, then bow rakes, then everything else in order (7.C.2).
- LOS blocked by ships in between (7.B.7–9).
- Drift odds, the downwind-first order, the blocked-drift foul roll, and fouled pairs drifting together (8.A.1–4, 8.A.6).
- Unfouling chances that rise with each attempt, with the SK DRM (8.D.1–3).
- Morale-check counts for lost sections, matching the ship log (9.B.1).
- Two-hex footprint: bow-pivot turns, stern swing blocking, per-battery arcs and LOS, closest-hex range, rake (5.C.1–2, 5.E.2, 7.B.2–6, 7.C.4, 7.E.2).
- Tacking roll and DRMs at MA 0, apart from the crew-section and reverse-tack DRMs (5.D.1–2, 5.D.6).
- Poor maneuvering (6.F.2–5) and the acceleration limits 5.E.4–6.
- Morale: d10 ≥ MR passes, a failure lowers CQ one step, a failure at CQ G strikes, the dismasting and raked-while-dismasted triggers, striking when all hull or all crew boxes are gone (9.A–9.C).
- Wind changes take effect the turn after they are rolled, with the pending change shown to players (3.B.6).
- Wind direction and speed rolls with the 16+ step back toward the starting wind, oceanic/coastal and steady/gusty frequencies, and direction rolls continuing at WS 0 (3.C, 3.D.1–2). The thresholds match the chart.

---

## 6. Items settled from the chart scans

The combat chart (`docs/combat_tables_1.jpeg`), the ship log and Diagram 20 settled every item that depended on a chart or diagram. Two items marked "?" remain open: the deceleration minimum (5.A.4), which needs the plotting UI traced, and who may drift (8.A.1), which depends on how "stopped" is read.

- **Tacking and Bearing Off:** the transcriptions were wrong and are now fixed (see §3).
- **Collision Resolution:** fouling on d10 + DRMs ≥ 6, with MS +1, PS +2 and drifting −1, matches the code. Rigging loss of d6−1/d6+1/2d6, ramming ship only: now implemented (6.E.3).
- **Unfouling, Drifting, Wind Speed Change and Wind Direction Change:** match their JSON files and the code.
- **Morale-check counts:** match the ship log (9.B.1).
- **Rake region:** confirmed too narrow (7.E.2); fixed in 2-hex Phase 1.
