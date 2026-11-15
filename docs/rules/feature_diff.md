# Close Action vs. Leeward: Feature Diff

**Scope:** *Close Action: The Age of Fighting Sail, Vol. 1* (1997) rules book, sections 1–14 (`docs/rules/close_action.md`, lines 132–1967). The rating system, tournament rules, designer's notes and scenario book are out of scope.

**Compared against:** the Leeward code on `main` at `30a2c35` (`scripts/`, `data/rules/`, `data/scenarios/`).

**Purpose:** a feature-level list of what the board game has that Leeward lacks, and of the places where both have a feature but the outcome differs significantly. It is not a play-by-play comparison. UI and presentation differences are ignored.

**Method:** eight reviewers each read one slice of the rules and compared it with the code. The lead reviewer then re-read the code behind every finding marked ✔ below. Unmarked findings come from the slice reviews only, and should be treated as reliable but not re-checked. Findings marked **?** could not be settled from the rules text alone, usually because the deciding chart or diagram is an image.

**Legend:**
- **Known**: already listed in `CLAUDE.md` as Milestone 2/3 or as a known limitation.
- **New**: not recorded anywhere in the project docs.

---

## 1. Headline items

These are the gaps and differences that most change how a game plays out, in rough order of impact.

| # | Item | Rule | Type | Status |
|---|------|------|------|--------|
| 1 | Critical hits, rigging checks and hull checks are absent. This removes the main source of variance, sinking, rudder and wheel damage, fires, and "poor maneuvering". | 7.D.7, 7.D.8a, 7.D.11–12, 6.F | Missing | Known |
| 2 | **Fixed.** The tacking roll never ran during play. Now any turn plotted at MA 0 rolls on the Tacking table, a failed roll erases the turn, and the turn ends the ship's move for that g-t. ✔ | 5.D.1–3 | Fixed | — |
| 3 | **Fixed.** A ship in irons could not turn out. Now it may plot one turn, rolled with the +1 in-irons DRM; if it plots no turn it stays in irons. ✔ | 5.D.6 | Fixed | — |
| 4 | Blocked wind (wind shadow) is absent. Ships sailing in the lee of others lose no MA. | 5.G | Missing | New |
| 5 | Boarding, grappling, capture and prize crews are absent, so a struck ship is the end state. | 8.C, 10.A–H | Missing | Known |
| 6 | Fire, explosions and repairs are absent, so all damage is permanent. | 8.E, 8.F | Missing | Known |
| 7 | Bearing off is cut down. The player has no choice, the ship makes no turn when it succeeds (it just stops), and the odds come from a home-made probability table rather than the printed d10 chart. ✔ | 6.D.2–4 | Differs | New |
| 8 | Collision rigging loss is a fixed 2/4/6 boxes, taken by one ship only. The rules use d6−1, d6+1 or 2d6, and both ships roll when they run into each other. ✔ | 6.E.3 | Differs | New |
| 9 | Speed is measured in hexes moved ahead, not in MPs (turns are not counted). This lowers the base for acceleration and deceleration. A "fast-tack" +1 MA bonus that is not in the rules has been added. ✔ | 5.E.2, 5.B.3 | Differs | New |
| 10 | Wind changes take effect in the same turn they are rolled, not the next, so players get no warning. ✔ | 3.B.6 | Differs | New |
| 11 | **Fixed.** The contested-hex class bonus went the wrong way. Now it is +1 per class larger (lower class number). ✔ | 6.C.2c | Fixed | — |
| 12 | There are no batteries. Each side fires as one whole broadside, so there is no bow/stern split, no half broadside (−8), and no per-battery arc or LOS. | 7.B.1–6, 7.C.12f | Differs | New |

---

## 2. Features in the board game that Leeward lacks

### 2.1 Already known (CLAUDE.md, Milestone 2/3)

| System | Rules | Notes |
|---|---|---|
| Critical hits (rigging and hull tables, RC/HC checks, CH#) | 7.D.7, 7.D.8a, 7.D.11–12 | CH# and `ch_modifier` are stored but never used. Everything that depends on them is missing too: broadside obscured −2 (7.C.11), poor maneuvering (6.F), Braces Cut and Sheets Cut acceleration (5.E.5–6), the CH morale trigger (9.B.1e), "fixing" criticals with the unfouling table (8.D.5), and the Lines Jammed and reorganize sail-change cancellations (5.F.9). |
| Fire and explosions | 8.E.1–11, 9.B.1c–d | Includes firefighting, spread, blast and flaming debris. |
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
| Blocked wind (wind shadow) | 5.G.1–3 | MA −1 when ships at FS or above sit in the windward hexes. Without it, line-astern and lee positions cost nothing. |
| Reinforcements | 2.B.1, 3.A | Every ship is placed at the start. |
| Escape and exit from the map, removal of escaped ships | 2.B.5g, 8.G.1f | Plotted movement is not even limited to the map (Known limitation). |
| Shallow water, land, running aground, casting the lead | 13.G | No depth map. `draft` is loaded and never read. Land does not block LOS (7.B.7). |
| Towing | 12.A | A `towing` field exists on the ship state, but no logic uses it. |
| Signalling and its limits | 4.A.4, 11, 8.G.1e | The MESSAGE_DELIVERY phase is a stub. This mostly matters for multi-player games. |
| Sail checks after a wind change | 2.B.1 | `# TODO` in the ENVIRONMENT phase. |
| Friendly-ship blocking hexes for LOS (medium and long range) | 7.B.10–12 | Only the hex a ship occupies blocks LOS. Nothing discourages firing past friendly ships. |
| Voluntarily reducing the MGN | 7.C.14 | |
| Acceleration reductions (two rigging sections missing, WS=1, towing) | 5.E.5 | The acceleration value comes straight from the table. |
| "A stopped ship whose first MP is a turn cannot move further" | 5.E.8 | |
| A collision or grapple in WF=L puts the ship in irons | 5.D.5 | |
| Exceptions to being in irons (WS just rose from 0, cut cable, anchored) | 3.D.4c, 5.D.4 | A ship at WF=L with speed 0 always counts as in irons. |
| Reverse tack | 5.D.3 | |
| Contested-hex winner may force the loser into the hex | 6.C.3 | The winner always enters. |
| Overlapping ships and stern-vs-stern contests | 6.B, 6.C.5 | Not possible with 1-hex ships (see §4). |
| Order of bear-off resolution and the once-per-turn limit | 6.D.3b–c, 6.D.5 | Hexes are resolved in dictionary order. |
| Game ends by mutual agreement, or when one side has no ship that can move and fight | 2.A.1 | Leeward ends only when a side is all struck, or at `turn_limit`. A side that is dismasted but not struck keeps the game going. |
| Struck ships count as CQ G | 9.C.4 | Only matters once firefighting and ungrappling exist. |
| **Optional rules (14):** impulse movement with fire at the end of an impulse, voluntary surrender and rallying, limited information, fatigue, historical gunfire limits (E/F/G crews fire low only on 1–3; 50% forced high when firing to windward at WF=C/B) | 14.A–E | None are offered. Leeward's movement does resolve "impulses", but each one is a standard segment, not the 4-impulse proportional system of 14.A. |

---

## 3. Features in both, with significantly different outcomes

| Rule | Board game | Leeward | Effect on outcome | Code |
|---|---|---|---|---|
| **3.B.6** When weather changes take effect ✔ | A change rolled in turn N takes effect at the start of turn N+1. | Rolled and applied in the same ENVIRONMENT phase. | Players plot against a wind they had no warning of. | `environment_controller.gd:27-36` |
| **3.D.3** Floor on wind speed ✔ | WS can only fall to 0 if the scenario started below 1. Otherwise a −1 at WS 1 is "No Change". | No floor. Any scenario can become calm. | Unplanned calms, with ships unable to move. | `environment_controller.gd:40-61` |
| **3.D.4b** Ending a calm ✔ | At WS 0, any "changes" result raises WS to 1. | The d10 is still rolled, and a decrease is clamped back to 0. | Calms last about twice as long. | `environment_controller.gd:48-61` |
| **3.B.5 / 7.C.12e** Sea state | Range 1–5. Its main effect is closing lower-deck gunports by comparison with freeboard. | Loaded and fixed (correct), but the code comments and dev UI treat it as 0–3. Its only effect is the dismasted-firer −sea state modifier. | Sea state hardly matters. | `environment_state.gd:17`, `gunnery_calculator.gd:82` |
| **5.B.3** How MA is spent ✔ | MA caps hexes ahead in the current WF. Turns use MPs against the speed band only. | Turns also cost 1 MA (`remaining = max_ma − spent`), with a free pivot when MA runs out. | Plots that mix turns and moves ahead give different totals. | `movement_validator.gd:150-190` |
| **5.B.3** "Never gain MPs by turning to a faster WF" ✔ | Explicit rule. | +1 MA "fast-tack bonus" when the first pivot goes from C to B. | Ships gain MA that the rules forbid. | `movement_validator.gd:156-161` |
| **5.C.3–4** Turn spacing | Applies across turn boundaries, and the table is indexed by this turn's plotted speed. | Reset every turn, and indexed by last turn's speed. | A ship can turn at the end of one turn and again at the start of the next. | `movement_validator.gd:194-200, 313-327` |
| **5.D.1–3** Tacking at MA 0 ✔ | Roll d10 on the Tacking table, with DRMs for CSs on "T", CQ, not at WF=L (−2) and rigging. If the roll fails, the turn is erased. | **Roll now fixed:** it runs for any turn plotted at MA 0, a failure erases the turn, and the ship moves no further that g-t. **Still different:** the roll is a 0–1 float check against a percentage, with ad-hoc DRMs (+0.2 per rigging section lost, +0.1 at WF=L, +0.1 in irons) and no CS or CQ terms. Reverse tack is not modelled. | Odds are not comparable with the d10 chart. | `movement_resolver.gd` (`_find_tacking_impulse`, `_calculate_tacking_drm`) |
| **5.D.6** Turning out of irons ✔ | The player plots a turn and rolls with +1 DRM. On success the ship turns. | **Fixed:** the validator offers a ship in irons its two turns, and the plotted turn goes through the Tacking roll with the in-irons DRM. A ship that plots no turn stays in irons. | Matches, apart from the roll mechanics noted under 5.D.1–3. | `movement_validator.gd`, `movement_resolver.gd` (`_remain_in_irons`) |
| **5.E.2** Definition of speed ✔ | Total MPs used, turns included. | Hexes moved ahead only (`_count_hexes_moved`). | Next turn's acceleration and deceleration band sits lower after any turn. | `movement_resolver.gd:726` |
| **5.A.4 / 5.E** Deceleration minimum | The ship must use at least last speed − decel. | `validate_submission` is a stub that always succeeds. **?** Whether the plotting UI enforces `min_ma` was not traced. | Ships may be able to stop dead from high speed. | `movement_validator.gd:90-98, 140` |
| **6.C.2c** Contested hex, class bonus ✔ | +1 per class *larger* (class 1 is the largest). | **Fixed:** +1 per class larger. | Matches. | `movement_resolver.gd` (`_calculate_contest_drm_relative`) |
| **6.D** Bearing off ✔ | The player chooses whether to bear off. Roll d10 against the Bearing Off table, with a plotted-speed DRM. On success the ship turns in an eligible direction and then meets its deceleration minimum. | Always attempted when eligible. The chance comes from `bearing_off_table.json` (a CQ × maneuverability probability marked "derived") checked with `randf()`. On success the ship just stops, with the same facing. | Odds differ, ships never turn away, and a player can never choose to ram. | `movement_resolver.gd:318-365` |
| **6.E.3** Collision rigging loss ✔ | d6−1 (FS), d6+1 (MS), 2d6 (PS), taken by the ship pointing at the other, or by both ships when they run into each other. | Fixed at 2, 4 or 6, applied to the moving ship only. | No variance, and head-on collisions are one-sided. | `movement_resolver.gd:478-483` |
| **6.G.2** Failure to plot ✔ | The ship continues at last turn's speed. | The ship stays where it is (`SKIP_NO_PLOT`) and its speed becomes 0. | A ship whose player does not plot stops dead. Matters for the AI and for timeouts. | `movement_resolver.gd:55-67` |
| **7.E.2** Rake geometry ✔? | Target within 5 hexes, with the firer outside **all** of the target's fire arcs, or directly ahead or astern. | Firer within **30°** of the target's bow or stern line, boundary excluded. | Probably fewer rakes than the rules give. A broadside arc covers 60°–120° off the bow, so "outside all arcs" suggests ±60°. Check against Diagram 20. | `fire_geometry.gd:40-49` |
| **7.C.12g** Two targets | The rule text says −10. | −12. The chart wins (already decided). | Recorded only. | `gunfire_modifiers.json` |
| **8.A.1 / 8.A.6** Who may drift ✔? | A stopped ship. A fouled pair that includes a ship that moved does not drift (example 2). | A ship drifts if it did not move, **or** collided, **or** is fouled. | Fouled ships drift in cases where the rules hold them. Depends on reading "stopped". | `drift_resolver.gd:68-72` |
| **8.D.1** Unfouling DRMs **?** | "DRMs (All Uses)" column on the chart. | The crew-quality SK modifier only. The rules example (B3 needs "<2") cannot be reconciled with the code from the text alone. | Needs checking against the chart scan. | `fouling_controller.gd:42-47` |
| **9.B.1** Morale checks for lost sections **?** | One MC for each "@" printed on the ship log. | Hardcoded: hull sections 1, 2 and 3 give 1, 1 and 2 checks, and each crew section gives 1. | Correct only if the log layout matches. Check against the ship-log image. | `damage_controller.gd:7, 89-114` |
| **9.C.3** Firing on struck ships ✔ | Struck ships "cannot do anything". The rules do not say they cannot be fired on. | Struck ships cannot be targeted. | Deliberate (see §4). It removes the option of shooting at a struck ship. | `gunnery_calculator.gd:28-29` |

---

## 4. Deliberate simplifications (for the record)

These are conscious design choices. They are listed because each one removes board-game outcomes.

- **1-hex ships** (1.E.2). This removes overlap (6.B), stern-vs-stern contests (6.C.5), partial drift (8.A.5), per-battery LOS and partial targets (7.B.4–6), and the ship's own hex blocking LOS. Turns that the rules resolve as "no collision" become ordinary conflicts.
- **One battery per broadside** (7.B.1). There is no bow/stern split and no half broadside.
- **A separate fire-declaration step after movement** (2.B.2, 7.A.2). Orders stay hidden until both sides have submitted. The outcome is the same as the board game's simultaneous fire.
- **Two sides, one human against the stub AI.** The multi-player rules (signalling 11.B, limited information 14.C) have nothing to apply to.
- **Struck ships cannot be targeted** (see the 9.C.3 row in §3).

---

## 5. Implemented and matching

Implemented with essentially the same outcome as the rules:

- Movement allowance lookup with rigging-level caps (5.A.2, 5.F.2–3).
- Sail-change cost, timing and cancellation when a crew section is lost (5.F.6–9, 4.A.3b, 4.B.2–3).
- No more than two turns per g-t, pivoting on the bow (5.C.1–2).
- A turn into WF=L stops the ship (5.B.4).
- Simultaneous segment-by-segment movement (6.A.1–2).
- Contested-hex d6 roll with ties and the CQ and speed DRMs (6.C.2a–b, 6.C.6).
- Both ships stop on a collision, fouling at 6+, dismasted ships never foul (6.E.2, 6.E.4–5).
- The gunnery pipeline: TGF → BGN with French guns, CQ, sections firing, guns dismounted, initial broadside, rake bonus, plain sail at WS 2 or more, WS 4, dismantling shot, FGN = MGN + d6, slashed results, damage columns by sail state with furled sails halved, lowest section first, crew split by cause, stern rake doubling crew hits (7.C–7.E).
- Simultaneous fire with stern rakes, then bow rakes, then everything else in order (7.C.2).
- LOS blocked by ships in between (7.B.7–9).
- Drift odds, the downwind-first order, the blocked-drift foul roll, and fouled pairs drifting together (8.A.1–4, 8.A.6).
- Unfouling chances that rise with each attempt (8.D.1–3).
- Morale: d10 ≥ MR passes, a failure lowers CQ one step, a failure at CQ G strikes, the dismasting and raked-while-dismasted triggers, striking when all hull or all crew boxes are gone (9.A–9.C).
- Wind direction and speed rolls with the 16+ step back toward the starting wind, oceanic/coastal and steady/gusty frequencies, and direction rolls continuing at WS 0 (3.C, 3.D.1–2). **?** The thresholds were not checked against the red-sheet scans.

---

## 6. Suggested next checks (need the chart or diagram images)

1. Diagram 20 (rake region): settles whether ±30° is too narrow.
2. Ship-log "@" layout: settles the morale-check counts for lost sections.
3. Unfouling, Tacking and Bearing Off charts: settle the DRMs and thresholds.
4. Collision Resolution chart: settles the fouling modifiers (MS +1, PS +2, drifting −1).
5. The wind-change thresholds on the red sheet.
