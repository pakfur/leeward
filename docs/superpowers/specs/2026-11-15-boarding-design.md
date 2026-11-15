# Grappling, Boarding and Capture — Design

**Status:** draft, awaiting answers to §4 and §6 · **Date:** 2026-11-15 · **Closes:** `feature_diff.md` §1 item 5, §2.1 rows "Grappling and ungrappling", "Boarding, capture, reorganizing, prize crews", and the boarding half of "Marine fire"

**Depends on:** the crew-task model of `2026-11-15-crew-tasks-fire-repairs-design.md` (written in parallel). This spec does not design that model; §2.4 lists exactly what boarding needs from it.

**Sources:** rule text `docs/rules/close_action.md` (1.G.8, 2.B.4–5, 4.A.1, 4.B.1–4, 5.D.5, 7.G, 8.A.6, 8.C, 8.D.4, 9.C.3–4, 10.A–H, 14.B, Scenario Book "Standard Victory Determination" B.2–B.3, sample-log narrative G-T 19–28). Numbers only from the scans: `boarding-combat-chart.jpg` (Boarding Combat, Skill Factors, Grappling, Unfouling; p.109) and `gunfire-results-chart.jpg` (Marine Fire, Crew Loss; p.110). PDF p.28 confirms 8.C.1 "each used **≤ two** MPs" (OCR reads "< fvo"). PDF p.33 confirms the 10.D.4 example's "10% of 58" is a misprint in the book itself (the roller's TBCF is 44; see §1.4).

---

## 1. Rules summary

### 1.1 Grappling and ungrappling (8.C, Maintenance phase sub-phases C and D)

- **Who (8.C.1, 8.C.3):** a ship may try to grapple **each adjacent ship once** per g-t, if **both** ships used **≤ 2 MPs** in the Movement Phase. Orientation is irrelevant. Fouling does not prevent it (it gives a DRM). Friendly ships may grapple each other but must roll. Burning ships, ships at CQ F or G, and struck ships **cannot grapple** (they can be grappled).
- **Roll (8.C.2):** d10 on the Grappling table; one grapple counter per pair (a second success adds nothing).
- **Ungrappling (8.C.4):** after all grappling attempts, either ship of a grappled pair may roll d10 on the **Unfouling** table with the "All Uses" and "Ungrappling Only" DRMs. Never automatic, even for friendly ships or the ship that grappled. Needs no CS.
- **During boarding (8.C.5, 8.D.4, 10.D.8):** ships locked in a boarding action may not ungrapple or unfoul **from each other**; they may from other ships, with **+1** if their marines are fighting in a boarding action.
- **Struck partner (8.C.6, 9.C.4):** a struck ship is CQ G for these DRMs.
- **Grappled ships (8.C.7):** cannot move or turn; they drift, never partially. **8.A.6:** a group of ships grappled or fouled together drifts as one, on one d10 made by the member least likely to drift; if any hex is blocked the whole group stays.
- **5.D.5:** a ship grappled at WF=L is in irons. (Leeward derives "in irons" from WF=L at speed 0, so this already holds once a grappled ship cannot move.)

**Grappling table (d10):** **≤ 2 succeeds**, 3+ fails. DRMs: ± SK mod · ships are fouled **−1** · attempting to tow **−1** (n/a) · marines not available **+1** · wind speed 4 **+1** · target did not move **−1**.

**Unfouling table (d10)** by attempt number 1 / 2 / 3+: success **≤ 2 / ≤ 3 / ≤ 4**. DRMs (all uses): ± SK mod, marines not available **+1**. DRMs (ungrappling only): **−1 per CQ level** the roller is better than the enemy ("Each CQ > enemy"), friendly ships **−2**, wind speed 4 **−1**.

**Skill factors (Boarding Combat and Skill Factors table):**

| CQ | SK mod | BCF sailor box | BCF marine box |
|---|---|---|---|
| A | −3 | 8 | 10 |
| B | −2 | 7 | 9 |
| C | −1 | 6 | 8 |
| D | 0 | 5 | 7 |
| E | +1 | 4 | 6 |
| F | +2 | 3 | 5 |
| G | +3 | 2 | 4 |

`data/rules/crew_quality_table.json` already holds exactly these values (checked against the scan).

### 1.2 Forming boarders and boarding procedure (10.A–C, 4.B.1)

- **Eligibility (10.A.2):** only between **enemy** ships **fouled or grappled at the start of the g-t**. CQ F or G may not board. Burning ships may neither board nor be boarded.
- **Struck targets (10.A.3):** may be boarded; boarders **win automatically and do not reorganize**.
- **FB (10.B.2):** a CS plots **FB** for one g-t. Sailor CSs form **lowest-numbered first**; the marine CS may FB regardless. FB sections can **defend in the same g-t** and **board from the next g-t**.
- **BR (10.B.3):** readied CSs plot **BR** every later g-t until they board (BA) or disband (BD).
- **Restrictions (10.B.4):** FB/BR CSs do nothing else. Exception: marines FB/BR may use marine fire and count as "available" for grappling and ungrappling.
- **BD (10.B.5):** one g-t, nothing else meanwhile (same marine exception). A CS disbanded by a combat result is free next g-t.
- **Boarders counter (10.B.6):** forming is announced publicly; the counter stays while any CS is FB, BR or BA.
- **BA (10.C.1):** a ship with readied CSs, fouled/grappled to an enemy at the start of the g-t, may plot **BA for one or two readied CSs per g-t** (at most two *new* BA per g-t). Sailor CSs attack in numerical order from the lowest section with boxes. **S4 may FB and BR but never BA.** BA CSs must board.
- **Defending (10.C.2–3):** a ship defends with CSs plotted FB (or BR). If boarded, a marine CS plotted to any non-boarding task is **automatically replotted to FB** (its task progress is lost).
- **Timing (10.C.4, 2.B.4):** (a) announce BA, defenders' marines replot; (b) all gunfire and marine fire; (c) boarding combat. Gunfire losses are taken before boarding.
- **Attacker (10.C.5):** the only BA ship; if both plot BA against each other, higher TBCF attacks, then better CQ, then a random roll.

### 1.3 Boarding combat (10.D)

1. **TBCF (10.D.1):** sum over all boxes in the action of BCF(current CQ, type).
2. **DRMs (10.D.2):** each side takes the TBCF odds DRM on its own F:E ratio, **rounded down** to the next lower listed ratio (1:1 = 0, accidentally omitted from the chart). The attacker alone adds the "Other DRMs".
3. **Roll (10.D.3):** both sides roll 2d6 simultaneously and add their DRMs.
4. **Losses (10.D.4):** the enemy loses *this % of the roller's TBCF*, rounded to the nearest whole BCF. Remove boxes one at a time: d6 on the Crew Loss "All Other Causes" row (S 1–3, M 4–6) unless only one type is in the action; subtract that box's BCF; repeat until the requirement is met (overshoot is normal).
5. **Special results (10.D.5):** only one side may get one. Both rolled one: the higher modified DR applies; equal DR: higher TBCF before losses; equal TBCF: neither.
6. **10.D.6:** boarders share every result of their parent ship and surrender if it strikes.
7. **10.D.7:** while a ship has boarding tasks plotted, gunfire and marine-fire crew losses against it use "Gunfire at Hull" if **only sailor** CSs are FB/BR/BA/engaged, and "All Other Causes" otherwise.

**Boarding Combat table (2d6, modified):**

| DR | Enemy loses % of roller's TBCF | Special — rolled by attacker | Special — rolled by defender |
|---|---|---|---|
| ≤ 4 | 2% | No effect | No effect |
| 5 | 4% | No effect | d10 **< attacker's MR** ⇒ attacker repulsed |
| 6 | 6% | No effect | d10 < attacker's MR ⇒ attacker repulsed |
| 7 | 8% | No effect | d10 < attacker's MR ⇒ attacker repulsed |
| 8 | 10% | No effect | Attacker repulsed and takes 1 MC |
| 9 | 15% | d10 **< defender's MR** ⇒ defending ship captured | Attacker repulsed and takes 1 MC |
| 10 | 20% | d10 < defender's MR ⇒ captured | Attacker repulsed and takes 1 MC |
| 11 | 25% | Defending ship captured | Attacker repulsed and takes 2 MC |
| ≥ 12 | 30% | Defending ship captured | Attacker repulsed and takes 2 MC |

**TBCF odds DRMs (F:E, both sides):** ≤1:4 **−4** · 1:3 **−3** · 1:2 **−2** · 2:3 **−1** · 1:1 **0** · 3:2 **+1** · 2:1 **+2** · 3:1 **+3** · ≥4:1 **+4**.

**Other DRMs (attacker only):** defending ship class 1 **−3**, class 2 **−2**, class 3 **−1**; defending ship larger class **−1 per class difference**; smaller class **+1 per class difference**. (Leeward: 74 = class 2, frigates = class 3. Frigate boarding a 74: −2 −1 = −3. 74 boarding a frigate: −1 +1 = 0.)

**Crew Loss (d6):** Gunfire at Hull S 1–5 / M 6; All Other Causes S 1–3 / M 4–6 (already in `crew_loss_table.json`).

### 1.4 Worked example (10.D.1–5, Heureux vs Majestic) — use as test 30

Heureux (CQ D) BA marines 6 + S1 4: 6×7 + 4×5 = **62**. Majestic (CQ C) S1 2 + marines 4 (auto-FB): 2×6 + 4×8 = **44**. Heureux 62:44 = 1.41 → 1:1 → 0, class-2 defender −2 ⇒ **−2**. Majestic 44:62 = 0.71 → 2:3 ⇒ **−1**. Rolls 9 and 9 ⇒ 7 and 8. Majestic loses 8% × 62 = 4.96 → **5 BCF** (one box). Heureux loses 10% of the *roller's* TBCF: the book prints "10% of 58 = 5.8 → 6", but 58 matches no TBCF in the example, and the chart says the roller's TBCF (44 → 4.4 → **4**). **Follow the chart (4)** (Open question 1). Majestic's 8 = "Attacker repulsed and takes 1 MC"; Heureux's 7 has no attacker special ⇒ Heureux's CSs disband and it takes 1 MC.

### 1.5 Winning, multi-ship, reorganizing, prizes (10.E–H)

- **Continuation (10.E.1):** actions continue each g-t until won. Engaged CSs are locked. More CSs may join (FB then BA for the attacker; FB for the defender).
- **Attacker wins (10.E.2):** defender (a) already struck, (b) has no CS FB (after the 10.C.3 marine replot), (c) strikes from hull loss or morale during the action, (d) "defending ship captured", (e) loses all crew boxes in the action.
- **Defender wins (10.E.3):** all attacking boxes eliminated, or "attacker repulsed". **Counter-boarding (10.E.4):** next g-t, every CS that defended (not S4) may BA, not just two.
- **Multi-ship (10.F):** split into one-attacker/one-defender combats, each CS engaged against one named enemy, all resolved separately and simultaneously. A sixth enemy ship boarding overwhelms and captures the ship.
- **Reorganizing (10.G.2–5):** every winning attacking CS plots **RO** for **5 + SK** g-t's (CQ A: 2, CQ E: 6), doing nothing but defend the prize. If the parent and prize separate meanwhile, the boarders are crossed off the parent. If the prize is boarded meanwhile, reorganizing restarts after that action, and the prize's original crew joins the defence at CQ G. Defenders who win do not reorganize; they may disband.
- **Prize crew (10.G.6–9):** minimum by the prize's class: **class 1 = 4 boxes, 2 = 3, 3 = 2, 4 = 1**. More is allowed. Boxes come from the surviving boarders, then (if needed) from non-boarding CSs, which must also reorganize. In the Status Update of the g-t when RO completes, the boxes leave the parent's marine CS and/or lowest-numbered sailor CS **without MCs**. They are re-formed into sections of the prize's original section sizes (example 6-6-7-7:7 with 8 sailors + 1 marine → 0-0-1-7:1, filled from S4 down). The prize crew takes the capturing ship's **current CQ and MR** (lowest of each if drawn from several ships). The remaining boarders are back aboard at the start of the next g-t.
- **Captured ships (10.H):** friendly to the captor from capture on, and the old side may fire at them. They **may not move** or plot any task except **boarding and repairing**; they may grapple, ungrapple, unfoul, be towed. The original crew is locked below (pumps and firefighting only). The prize crew takes all crew losses. If it falls **below the minimum**, the original crew retakes the ship at the start of any g-t in which it has **≥ 2×** the prize crew's boxes; the ship is then **CQ/MR G6** and acts normally.
- **BGN (1.G.8c, example 2):** a ship used by another navy uses **that navy's** BGN at ranges 11–15 (French small numbers for French users, large for others).
- **Victory (B.2–B.3):** "surrendered, destroyed or captured by boarding" are all "struck": **100%** of VP value to the enemy, never also damage VPs.

### 1.6 Marine fire, only as boarding needs it (7.G)

Marines only, adjacent enemy only, one target per g-t. Marines plotted to non-boarding tasks cannot fire. FB/BR/BD marines may fire, BA or engaged marines may not. d6 on the Marine Fire table by marine boxes at the start of the g-t; simultaneous with gunfire (7.G.5). Losses use the Crew Loss table (All Other Causes, or 10.D.7).

| d6 (mod) | 1–2 | 3–4 | 5–6 | 7–8 | 9–10 | 11+ |
|---|---|---|---|---|---|---|
| ≤ 1 | 1 | 1 | 1 | 1 | 1 | 2 |
| 2 | · | 1 | 1 | 1 | 1 | 1 |
| 3 | · | · | 1 | 1 | 1 | 1 |
| 4 | · | · | · | 1 | 1 | 1 |
| 5 | · | · | · | · | 1 | 1 |
| 6+ | · | · | · | · | · | · |

DRMs: firing ship grappled or fouled to the target **−1** · firing marines CQ E or F **+1** · CQ G **+2** · target has boarders preparing or prepared **−1** · firing class # < target class # **−1** · [optional] range 2 **+1** (not offered).

---

## 2. Data model

### 2.1 Rule data
- `data/rules/boarding_combat_table.json`: rows `"4"`(≤4)…`"12"`(≥12) → `{"pct": 2, "attacker": "none"|"capture_if_lt_mr"|"capture", "defender": "none"|"repulse_if_lt_mr"|"repulse_mc1"|"repulse_mc2"}`; `odds_drm` as ordered `[[num, den, drm], …]` from 1:4 up to 4:1 including 1:1 = 0; `class_drm` `{"1": -3, "2": -2, "3": -1, "per_class_larger": -1, "per_class_smaller": 1}`; `prize_minimum` `{"1": 4, "2": 3, "3": 2, "4": 1}`.
- `data/rules/grappling_table.json`: `{"success_max": 2, "drm": {"fouled": -1, "towing": -1, "marines_unavailable": 1, "ws4": 1, "target_did_not_move": -1}}`; `unfouling_table.json` gains `ungrapple_drm` `{"per_cq_better": -1, "friendly": -2, "ws4": -1}` and `marines_unavailable: 1`.
- `data/rules/marine_fire_table.json` (columns 1-2…11+, rows ≤1…6+, DRMs).
- `CombatTables`: `boarding_row(dr)`, `odds_drm(f, e)` (exact integer compare `f*den >= e*num`, no floats), `boarding_class_drm(def_class, att_class)`, `prize_minimum(class)`, `bcf(cq, marine)`, `grapple_success_max()`, `marine_fire_result(dr, boxes)`. Extend `validate_combat.py`: rows 4–12 present, pct increasing, odds ladder ordered.

### 2.2 Grappled vs fouled
| | Fouled (exists) | Grappled (new) |
|---|---|---|
| Cause | collision, blocked drift (6.E, 8.A.4) | Grappling roll (8.C.2) |
| Storage | `ShipState.fouled_with: String` (one partner) | `ShipState.grappled_with: Array[String]` (any number, symmetric) |
| Release | Unfouling, `unfoul_attempts` | Ungrappling, `ungrapple_attempts: Dictionary` partner → attempts |
| Movement | refused (`SHIP_FOULED`) | refused (new `SHIP_GRAPPLED`) |
| Boarding link | yes | yes |

`ShipState.linked_ids()` = fouled partner ∪ grapples. A pair can be both fouled and grappled. `ShipStateController.add_grapple(a, b)` / `remove_grapple(a, b)` update both ships. `DamageController.destroy` also clears grapples.

### 2.3 Boarding actions (new `scripts/state/boarding_state.gd`)
`GameState.boarding_actions: Array[BoardingAction]`, serialized into the turn snapshot (`boarding_history[turn]`, saved with the ship snapshots).
```
BoardingAction { id: int, attacker_id, defender_id: String,
  attacker_sections: Array[int], defender_sections: Array[int],   # 0-3 sailors, 4 = marines
  started_turn: int, rounds: int,
  state: "declared" | "engaged" | "attacker_won" | "defender_won",
  reorganize: {"turns_left": int, "sections": Array[int]} }       # after attacker_won
```
Repulse and capture leave the record in `turn_log`; finished actions are dropped at END_TURN, except `attacker_won` until reorganizing ends.

### 2.4 What boarding needs from the crew-task model
Built on the crew-task spec's contract (its §3.7): `ShipState.crew_tasks`, `plotted_actions["crew_assignments"]`, section indices 0–3 = S1–S4 and `ShipState.MARINES` = 4, `CrewTaskController.register_handler(code, handler)`, `force_task`, `cancel_section`, `legal_tasks`, `default_assignments`. Boarding registers a `BoardingTaskHandler` (`scripts/server/boarding_task_handler.gd`) and needs:
1. **Task codes:** `FB`, `BR`, `BA` (`params.target` = enemy ship id), `BD` (1 CS each, 1 g-t; BR/BA continue until resolved). `RO` comes from the crew-task spec; boarding victory calls `force_task(…, "RO", {"reason": "boarding", "prize": id})`.
2. **Handler flags:** `section_order: "lowest_sailor_first"` for FB and BA (4.B.1, 10.B.2, 10.C.1; marines exempt); `forced` for BA sections in an `engaged` action and for RO (cannot be plotted away, 10.E.1, 10.G.2); `interruptible_by_fire` false for engaged BA and RO, true for FB/BR (`on_fire_breaks_out` disbands FB/BR not engaged, 8.E.2).
3. **`can_plot` rules** in the pure static `BoardingRules.task_error(ship, sections, code, params, plan) -> String` (like `FireRules`): S4 never BA; at most two *new* BA per g-t unless counter-boarding (10.E.4); BA needs readied sections (FB on an earlier g-t) and a target that is an enemy linked at the start of the g-t; no FB/BA at CQ F/G or while burning (`is_burning()`); prizes may plot boarding tasks only for their prize crew.
4. **Defaults:** `default_assignments` pre-fills BR for readied sections (10.B.3).
5. **Server override in COMBAT** (10.C.3): `force_task(ship_id, MARINES, "FB", {"reason": "repel boarders"})`, which ends the marines' old task with its progress. Disband (10.D.5a) = `cancel_section(…, "repulsed")` on every FB/BR/BA section of the attacker; they plot normally next g-t.
6. **Predicates** (crew-task helpers plus two boarding ones): `sections_able_to_fire()` excludes tasked sections (4.B.4); `marines_available()` is true for marines at FB/BR/BD (10.B.4–5 exception), so the handler must report those codes as "available". New `ShipState.has_boarders()` (any FB/BR/BA: boarders counter, marine-fire −1, 10.D.7) and `boarding_sections(enemy_id)`.
7. **Section loss** (4.B.3): `cancel_section`; an emptied engaged section also leaves its `BoardingAction`.
8. **Prize crews:** for a CAPTURED ship, `legal_tasks` offers only boarding and repair codes (10.H.2); the locked-up original crew offers none (pumps and firefighting belong to the crew-task spec).

### 2.5 Capture and control
- `Ship.player_id` stays immutable as the **original owner**. New `ShipState.controller_id: int = -1` (−1 = original owner). `ShipState.player_id` (the existing getter) returns `controller_id` when ≥ 0, so every current reader (selection, owner colour, gunnery side checks, AI) follows control automatically. `ShipState.original_player_id` reads `Ship.player_id`.
- `GameState.transfer_control(ship_id, player_id)` (server, through `ShipStateController.set_controller`) re-indexes `ships_by_player`.
- New status **`CAPTURED`** in `ShipState.Status`. `is_out_of_play()` stays "status ≠ ACTIVE", so prizes never keep their holder alive and cannot move or plot movement. New `is_targetable()` = ACTIVE or CAPTURED, used by `GunneryCalculator` instead of `is_struck()` (struck ships stay untargetable, §4 of `feature_diff.md`; prizes can be fired on, 10.H.1). New `can_board_or_be_boarded()` = ACTIVE or CAPTURED (struck: boarded only).
- Prize data on the captured ship: `prize: Dictionary` = `{captor_id, crew_count: [4], marine_count, crew_quality, morale_rating}` and `original_crew: {crew_count, marine_count, crew_quality, morale_rating}`. While a prize, the ship's live `crew_count`/`marine_count`/`crew_quality`/`morale_rating` **are the prize crew's** (so gunnery, morale and damage work unchanged); the locked-up original crew sits in `original_crew`. Between capture and prize-crew assignment, the live crew is empty and the boarders (still on the parent's log) defend.
- **BGN (1.G.8):** `Ship.is_french_gunned()` becomes `ShipState.is_french_gunned()`: the controlling side's navy. Scenarios gain an optional per-side `navy` ("French", "British", …), defaulting to the ship type's `nationality`. Only matters if prizes may fire (Open question 4).
- **Recapture by the original crew (10.H.4):** status ACTIVE, `controller_id` −1, live crew = `original_crew`, CQ G, MR 6.

### 2.6 Victory points
- `VictoryController.points_lost` already gives 100% for any out-of-play ship, so CAPTURED is covered. `_points_scored(p)` must sum the ships whose **original** owner is `1 − p` (new `GameState.get_original_player_ships`), not `get_player_ships`, which now follows control.
- `_is_defeated(p)` is unchanged (it counts ships p controls that are ACTIVE). A side with only prizes left is defeated.
- Capturing an **already struck** ship changes no VP under the standard rules (it is already "struck", 100%). Its only rules effect is to stop 14.B rallying, which Leeward lacks (Open question 6).
- Crew boxes detached as prize crew are not "destroyed" (Open question 7).

---

## 3. Server design

### 3.1 Phase placement
| Step | Phase / step | Controller call |
|---|---|---|
| Plot FB/BR/BA/BD/RO | PLANNING | crew-task model + `BoardingRules` |
| Announce BA, marine auto-FB, 10.E.2a/b instant wins | COMBAT_RESOLUTION, entry (new sub-step before DECLARE) | `boarding_controller.declare(phase)` |
| Gunfire + marine fire | COMBAT_RESOLUTION DECLARE → RESOLVE | `gunnery_resolver.resolve` then `marine_fire_resolver.resolve` (same declared order set) |
| Boarding combat | COMBAT_RESOLUTION RESOLVE, right after gunfire | `boarding_controller.resolve(phase)` |
| Drift of grappled/fouled groups | DRIFT_CALCULATION | `drift_resolver` (8.A.6 groups) |
| Grappling, ungrappling | STATUS_ADJUSTMENT, **before** unfouling (2.B.5 c–e) | `grappling_controller.resolve_grapples`, `resolve_ungrapples` |
| Unfouling | STATUS_ADJUSTMENT | `fouling_controller` (skips pairs locked in boarding) |
| Reorganize countdown, prize crew assignment | STATUS_ADJUSTMENT, after sail changes (8.G.1c, before MCs) | `boarding_controller.advance_reorganizing` |
| Boarding MCs | MORALE_CHECK | existing `morale_controller` (noted MCs) |
| Boarders back aboard; 10.H.4 recapture | start of next turn (`_start_new_turn`) | `boarding_controller.start_of_turn` |

`_enter_combat_resolution_phase` currently skips combat when no shot is eligible. New skip condition: no eligible gunfire **and** no eligible marine fire **and** no BA declared **and** no `engaged` action. When there is no shot but there is boarding, DECLARE is skipped and RESOLVE runs boarding only. Boarding needs no mid-combat choice, so no new `CombatStep`; its events join the RESOLVE log and play back with the gunfire.

Grapple and ungrapple choices are not plotted (4.A.1). Recommended (UX Q1): STATUS_ADJUSTMENT gains a waiting step, `MaintenanceStep.ORDERS`, like the bear-off pause. It is entered only when the human has an option: an eligible grapple, a grapple to throw off, or a prize-crew size to choose. `maintenance_orders_requested(options)` is emitted; then `player_submit_maintenance_orders(player_id, orders) -> String`. The AI answers synchronously.

### 3.2 Controllers
- **`GrapplingController`** (`scripts/server/grappling_controller.gd`). `grapple_options(ship_id)` (pure): adjacent ships, both `last_move_mp ≤ 2` (new `ShipState.mp_used_this_turn`, set by the movement resolver, turns included), roller not burning, CQ not F/G, not struck/destroyed, not already grappled to it. `resolve_grapples(orders, phase)`, then `resolve_ungrapples(orders, phase)`.
- **`BoardingController`** (`scripts/server/boarding_controller.gd`). `declare`, `resolve`, `advance_reorganizing`, `start_of_turn`, `capture(defender_id, captor_id, struck_target, phase)`. All mutations go through `ShipStateController`, `DamageController` (box removal and strikes) and the crew-task controller. Pure helpers: `tbcf(ship_id, sections)`, `drms(action)`.
- **`MarineFireResolver`** (or a `GunneryResolver` extension). Marine orders are a separate list in the fire submission (`MarineOrder {ship_id, target_id}`), validated by `FireRules.marine_error`.
- **`DamageController`**: new `apply_boarding_losses(ship_id, bcf_required, sections, cq, phase) -> Array` (rolls per box, removes from the lowest engaged sailor section or marines, notes section-emptied MCs as for gunfire), and `detach_prize_crew(ship_id, sailors, marines)` (no MC). The crew-loss row for gunfire and marine fire uses `BoardingRules.crew_loss_cause(ship, default_cause)` (10.D.7).
- **`DriftResolver`**: groups become connected components over `linked_ids()` (8.A.6); one roll by the member least likely to drift; no partial drift for any linked ship.
- **`MovementValidator` / plotting**: `SHIP_GRAPPLED`, and `SHIP_CAPTURED` ("a prize cannot sail, 10.H.2").

### 3.3 Dice order (contract for `ScriptedDice`)
**Grappling:** rollers by ship_id. For each, targets by ship_id; one d10 per attempt; skip a pair already grappled this sub-phase. Success: `d10 + SK + DRMs ≤ 2`. **Ungrappling:** pairs by lower ship_id; the lower id rolls first (if it chose to try), the partner only if the first fails. Success: `d10 + SK + all DRMs ≤ unfouling_success_max(attempt)`.
**Boarding**, per action in (defender_id, attacker_id) order:
1. 10.C.5b tie-break d6 only when TBCF and CQ tie (1–3: lower ship_id attacks).
2. Attacker 2d6, then defender 2d6.
3. Defender's loss d6s, then attacker's loss d6s (one per box; none if one crew type).
4. Special-result d10 (only for a "< MR" result that survives 10.D.5).
Actions resolve against TBCFs computed after all gunfire; results of one action do not change another's TBCF in the same g-t (10.F.3).

### 3.4 Capture
On a capture (10.E.2): the action becomes `attacker_won` and the defender's engaged CSs go with the ship. `capture()` sets status CAPTURED and `controller_id` = captor's side, moves the live crew into `original_crew`, empties the live crew, cancels the prize's plots, sail change and pending MCs, and logs `SHIP_CAPTURED`. Struck target (10.A.3): no reorganize; prize crew assigned in this g-t's STATUS_ADJUSTMENT. Otherwise `reorganize.turns_left = 5 + SK` of the captor's current CQ. While reorganizing, if the link breaks, the boarders become the prize crew in full (Open question 8). At completion, prize size = chosen size (default minimum, capped at surviving boarders); boarders' remaining boxes return at the next turn start.

### 3.5 Events (`PhaseEvents.Type`) and log texts
| Type | Data | Text |
|---|---|---|
| `GRAPPLE` | `{roll, modifier, needed, success}` + target | "Vengeance throws grapples at Hermione: 2 −1 = 1 ≤ 2 — grappled" / "… 5 > 2, misses" |
| `UNGRAPPLE` | `{roll, modifier, needed, attempt, success}` | "Hermione cuts the grapples to Vengeance (3 −2 −1 = 0 ≤ 2)" |
| `BOARDERS` | `{sections, task}` | "Vengeance forms boarders (S1, marines)" (public, 10.B.6) |
| `BOARDERS_AWAY` | `{sections}` + defender | "Vengeance: boarders away! (S1, marines) onto Hermione" |
| `MARINES_DEFEND` | `{cancelled_task}` | "Hermione's marines drop repairs to repel boarders" |
| `MARINE_FIRE` | `{boxes, roll, modifier, result, losses}` | "Vengeance's marines fire on Hermione: 3 −1 = 2 — 1 box" |
| `BOARDING_ROUND` | `{attacker:{tbcf, odds, drm, roll, total}, defender:{…}, losses:{att_bcf, def_bcf}}` | "Boarding Vengeance → Hermione: 62 v 44; attacker 9 −2 = 7, defender 9 −1 = 8" |
| `DAMAGE` (cause `boarding`) | as today | "Hermione loses 1 sailor box (5 BCF needed)" |
| `BOARDING_RESULT` | `{result, d10, mr, mcs}` | "Vengeance's boarders are repulsed and take 1 MC" / "Hermione is captured!" |
| `SHIP_CAPTURED` | `{captor_id, struck_before}` | "Hermione is taken by Vengeance (prize)" |
| `REORGANIZING` / `PRIZE_CREW` | `{turns_left}` / `{sailors, marines, cq, mr}` | "Prize crew of 3 (B3) put aboard Hermione" |
| `RECAPTURED` | `{original_boxes, prize_boxes}` | "Hermione's crew rises and retakes the ship (G6)" |

### 3.6 AI (`StubAI`)
- **Crew plot:** when linked to an enemy at plot time, or adjacent to an enemy with `boarders`, FB marines + S1 (defence, 10.C.2). BA one or two readied CSs when its estimated odds (own readied TBCF vs the enemy's visible boarders plus its marines) are ≥ 3:2 after the class DRM, or the target is struck. BD when no enemy has been linked for 2 g-t's.
- **Grapple:** try against any eligible enemy that is struck, or whose crew boxes × BCF are ≤ ⅔ of its own. Never grapple friendly ships.
- **Ungrapple:** try whenever grappled to an enemy it would not board (rule above) and not locked; never cut a grapple to a struck enemy it is boarding.
- **Prize crew:** minimum + 1 if another enemy ship is within 3 hexes, else the minimum.
- **Movement:** prizes and grappled ships plot nothing; `engage` keeps its broadside logic.

---

## 4. UX design — questions for you (recommendation marked ★)

**UX1. How does the player declare grapple and ungrapple attempts?**
1. ★ **Maintenance prompt.** After drift, a small panel lists each eligible pair: "Grapple Hermione (needs ≤ 2: 30%)" toggle, "Cut grapples to …" toggle, "Done". It appears only when there is a choice (like bear-off), and comes after combat results, so you can grapple a ship that just struck.
2. A "Grapple" section in the fire-declaration panel (one stop, but before you see this turn's combat results, and needs a pause anyway when no shot exists).
3. Standing orders set in PLANNING ("grapple X if able"). No extra pause, but decided before movement is known.

**UX2. How does the player plot boarding (FB/BR/BA/BD)?**
1. ★ Rows in the crew-task panel (from the crew-task spec): per section a task picker. BA asks for a target among linked enemies. Illegal options are greyed with the rule reason ("S2 must wait for S1", "S4 cannot board"). Plus two shortcut buttons on the selected ship: **"Prepare boarders"** (FB marines + lowest sailor sections) and **"Board <ship>!"** (BA the legal one or two).
2. Shortcut buttons only (simplest, less control).
3. Map action: right-click a linked enemy → "Board".

**UX3. How is boarding combat shown?**
1. ★ A **boarding card** in the combat playback for each action: two columns (attacker / defender) with boxes engaged, TBCF, odds and DRMs, the 2d6, the % and BCF lost, boxes lost by type, then the special result in large text ("REPULSED — 1 MC", "CAPTURED"). The same lines go into the combat log.
2. Combat log lines only.
3. Card plus an on-map effect (crossed cutlasses between the two ships, floating box-loss numbers).

**UX4. What happens on the map when a ship is captured?**
1. ★ The owner ring and pennant switch to the **captor's colour** at once (green/red stays "who controls it"). A small **prize flag** (captor's colour over a struck white ensign) is added. While reorganizing, the ring is dashed with a turn counter. The minimap uses the new colour with a hollow icon.
2. Keep the original colour, add a "captured" badge only.
3. Swap colour only, no badge.

**UX5. How does the player command a captured ship?**
1. ★ Selectable like an own ship. The plotting panel shows "Prize — cannot sail (10.H.2)" with movement disabled. The crew panel offers only boarding and repair tasks for the prize crew. It appears in the fire panel only if Open question 4 allows prizes to fire. The status panel shows "Prize of Vengeance · prize crew 3 (B3) · original crew 18 below".
2. Read-only (inspect but no orders), with boarding defence automatic.

**UX6. Prize-crew size.**
1. ★ Asked in the maintenance prompt the turn reorganizing completes: a stepper from the minimum to the surviving boarders, default the minimum, showing the result for both ships ("Vengeance keeps 0-5-6-6:2").
2. Always the minimum, no prompt.

**UX7. Multi-ship defence (10.F).** When two enemy ships board one of yours:
1. ★ Automatic allocation: marines and lowest sections to the attacker with the higher TBCF, then alternate. Logged.
2. A prompt to assign each FB section to an attacker.

---

## 5. Implementation plan

Each step ships with GUT tests (`ScriptedDice`), `make test` and both validators. The crew-task model must land first (step 0).
1. **Data:** the three JSON tables, `CombatTables` accessors, validator checks, spot tests.
2. **Grappling:** `grappled_with`, attempts, `mp_used_this_turn`, `GrapplingController`, ungrappling, `SHIP_GRAPPLED`, 8.A.6 group drift, unfouling skip for locked pairs, maintenance-orders step + AI.
3. **Boarders:** `BoardingTaskHandler` + `BoardingRules.task_error`, FB/BR/BD wiring, `has_boarders` (public), 10.D.7 crew-loss row.
4. **Boarding combat:** `BoardingAction`, `declare` (BA, marine auto-FB, 10.E.2a/b), `resolve` (TBCF, odds, DRMs, losses, specials, MCs), continuation, counter-boarding, phase-skip change.
5. **Capture:** status CAPTURED, `controller_id`, `transfer_control`, `is_targetable`, struck-ship capture, reorganizing, prize crew, return of boarders, 10.H.4 recapture, victory changes.
6. **Marine fire** (7.G) with its DRMs.
7. **Multi-ship** (10.F) separation, the sixth-ship overwhelm.
8. **UI** per §4; `feature_diff.md` (§1 item 5, §2.1 rows, §2.2 9.C.4 row, §5); CLAUDE.md "Not implemented"; `scv-reviewer`.

### Test list (expected values from the rules and charts)
| # | Setup | Expected | Rule |
|---|---|---|---|
| 1 | Grappler used 3 MPs | not eligible | 8.C.1 ex. 1 |
| 2 | Both used 2 MPs, adjacent, CQ B, d10 4 | 4 −2 = 2 ≤ 2 ⇒ grappled | 8.C.1–2, chart |
| 3 | Same, fouled, target did not move, WS 4, d10 5 | 5 −2 −1 −1 +1 = 2 ⇒ grappled | Grappling DRMs |
| 4 | Roller CQ F, or struck | no attempt offered | 8.C.3 |
| 5 | Both ships succeed against each other | one grapple, second roll not made | 8.C.2 |
| 6 | Ungrapple CQ B vs struck enemy (G), attempt 1, d10 7 | 7 −2 −5 = 0 ≤ 2 ⇒ free | 8.C.4, 8.C.6 |
| 7 | Ungrapple from friendly, CQ D, d10 4 | 4 −2 = 2 ≤ 2 ⇒ free | Unfouling DRMs |
| 8 | Pair locked in boarding | no ungrapple or unfoul roll | 8.C.5, 8.D.4 |
| 9 | Marines engaged, ungrapple from a third ship | +1 | 8.C.5 |
| 10 | Grappled ship plots movement | refused `SHIP_GRAPPLED` | 8.C.7 |
| 11 | Three ships grappled in a chain, one blocked hex | none drift; one d10 by least likely | 8.A.6 |
| 12 | FB S2 while S1 is free | refused | 10.B.2, 4.B.1 |
| 13 | Marines FB with no sailors forming | allowed | 10.B.2 |
| 14 | BA in the same g-t as FB | refused | 10.B.2 |
| 15 | BA three readied CSs | refused (max two) | 10.C.1 |
| 16 | BA S4 | refused | 10.C.1 |
| 17 | BA at CQ F | refused | 10.A.2 |
| 18 | BA to a friendly linked ship, or an unlinked enemy | refused | 10.A.2 |
| 19 | Defender's marines plotted to repair, boarded | replotted FB, progress lost | 10.C.3 |
| 20 | Defender no marines, no FB | captured without a roll | 10.E.2b |
| 21 | Struck defender | captured, no reorganize, prize crew this g-t | 10.A.3 |
| 22 | Both BA, TBCF 50 v 40 | 50 attacks | 10.C.5b |
| 23 | Odds 62:44 | 0; 44:62 → −1; 40:10 → +4; 10:45 → −4 | 10.D.2 |
| 24 | Frigate (3) boards 74 (2) | −2 −1 = −3; 74 boards frigate: −1 +1 = 0 | Other DRMs |
| 25 | Modified 7 by attacker, roller 62 | defender loses 5 BCF | 10.D.4 |
| 26 | Loss 6 BCF, sailor (5) then marine | two boxes lost (overshoot) | 10.D.4 ex. |
| 27 | Only sailors in action | no crew-loss d6 consumed | 10.D.4a |
| 28 | Attacker 9 and defender 11 | defender's "repulsed, 2 MC" only | 10.D.5 |
| 29 | Both modified 9, TBCF 50 v 40 | only the 50 side's special | 10.D.5 |
| 30 | Heureux vs Majestic, dice 9 & 9 | 62 v 44, DRMs −2/−1, losses 5 and 4 BCF, attacker repulsed + 1 MC, attacker's FB/BR disbanded | 10.D.1–5, §1.4 |
| 31 | Attacker modified 10, d10 2, defender MR 3 | captured | Boarding table |
| 32 | Defender modified 6, d10 3, attacker MR 3 | not repulsed (needs < MR) | Boarding table |
| 33 | Engaged action, next g-t | continues without new BA; sections locked | 10.E.1 |
| 34 | Repulse, next g-t defender BA four sections | allowed (not S4) | 10.E.4 |
| 35 | Parent strikes during action | its boarders surrender | 10.D.6 |
| 36 | Gunfire on a ship with only S1 FB, d6 5 | sailor ("Gunfire at Hull") | 10.D.7 |
| 37 | Captor CQ B | reorganize 3 g-t's; CQ E: 6 | 10.G.4 |
| 38 | 74 captured, prize 9 = 8 S + 1 M of 6-6-7-7:7 | prize 0-0-1-7:1; parent 1-6-6-6:2 → 0-0-5-6:1, no MCs | 10.G.7, 10.G.10 |
| 39 | Prize crew CQ/MR | = captor's current | 10.G.8 |
| 40 | Captured ship plots movement | refused; can be fired on by the old side | 10.H.1–2 |
| 41 | Class 2 prize, prize crew falls to 1 (< min 3) | original crew 1 box: no; 2 boxes (≥ 2×1) at the next turn start: retaken, G6; prize crew 3, original 20: no (not below min) | 10.H.4 |
| 42 | Captured 74 (British type) held by French | French BGN 11–15 | 1.G.8 ex. 2 |
| 43 | Captured ship at game end | 100% VP to captor; not counted alive for its holder | B.2–B.3 |
| 44 | Marine fire, 7 boxes, grappled, d6 5 | 5 −1 = 4 ⇒ 1 box | 7.G, Marine Fire |
| 45 | Marines BA | cannot fire | 7.G.1 |

---

## 6. Open questions

1. **10.D.4 example misprint:** use the chart's "roller's TBCF" (Majestic's 4 BCF) rather than the book's "10% of 58"? Recommended: chart.
2. **Rounding .5** to the nearest BCF: round half up? Recommended: yes.
3. **Defender's sections in a mutual-BA action:** do the defender's BA sections fight as defenders this g-t? Recommended: yes, all its FB/BR/BA sections linked to that enemy defend.
4. **May prizes fire their guns?** 10.H.2 forbids moving and plotting tasks, and gunfire is not plotted, but the rule's intent is "unable to sail or fight". Recommended: **no** (simpler, matches the intent). Then 1.G.8 matters only for scenario ships flagged with a different navy. Alternative: yes, with unplotted prize-crew sections and the captor's BGN.
5. **Marine fire scope:** implement 7.G fully in this feature (step 6), or defer and keep only the 10.D.7 crew-loss row and the "marines available" predicate? Recommended: implement. It is small and is the main pre-boarding weapon.
6. **Struck ships at game end:** Leeward ends the game when a side is all struck, so the last struck enemy can never be boarded, and capturing a struck ship gives no VPs. Keep this as is, or add a house rule (for example a +10% capture bonus, or the game continues N turns)? Recommended: keep the rules; note it in `feature_diff.md`.
7. **Prize-crew boxes and VPs:** do sections the captor empties to form a prize crew count as "crew sections destroyed" (B.5d)? Recommended: no; track detached boxes separately.
8. **Link broken while reorganizing (10.G.2):** the boarders "are crossed out on the parent" — do they become the prize crew (recommended) or simply vanish?
9. **Prize crew from non-boarding CSs (10.G.6)** when boarders are below the minimum: allow (with another full reorganize), or require enough boarders? Recommended: allow only surviving boarders; with fewer than the minimum, all boarders become the prize crew.
10. **Recapture VPs:** a ship retaken by its original side (10.H.4 or by boarding the prize). Is it "struck" (100%) or scored by damage? Recommended: by its state at game end (damage only if back under its original side and ACTIVE).
11. **Grapple eligibility "used ≤ 2 MPs":** count turns as MPs (Leeward speed counts turns, 5.E.2)? Recommended: yes, every executed step.
12. **"Target did not move" −1:** means no MP used (0 steps)? Recommended: yes.
13. **Boarders and fire (10.A.2, 8.C.3):** use the crew-task spec's `is_burning()`. Until that lands, block boarding and grappling only when `fires > 0`? Recommended: yes.
14. **Fouled with only one ship:** `fouled_with` holds one partner. Boarding through grapples allows many links, which is enough. Generalise fouling later? Recommended: leave it as is; note it in `feature_diff.md`.
