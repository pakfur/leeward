# Grappling, Boarding and Capture — Design

**Status:** ready for implementation after the crew-task spec's phases 1–4, §8 answered (all ★ defaults approved) · **Date:** 2026-11-15 · **Closes:** `feature_diff.md` §1 item 5; §2.1 rows "Grappling and ungrappling", "Boarding, capture, reorganizing, prize crews", "Marine fire"; §2.2 rows "A collision or grapple in WF=L puts the ship in irons" (the grapple half) and "Struck ships count as CQ G" (the rest).
**Compared against:** `e719ea7`.
**Depends on:** `2026-11-15-crew-tasks-fire-repairs-design.md` ("the crew spec"). This spec uses its crew-task engine, its Automatic allocation, its crew overlay and its contract (crew spec §3.9); it does not redesign them.
**UX source:** the approved crew overlay (`2026-11-15-crew-overlay-rules-mapping.md`, prototype v15, `prototypes/crew_overlay/`), which has the Boarders and Marine fire stations. Everything boarding needs beyond those two stations is designed here and marked so.

**Sources.** Rule text `docs/rules/close_action.md`: 1.G.8, 2.B.4–5, 4.A.1, 4.B.1–4, 5.D.5, 7.D.9, 7.G, 8.A.6, 8.C, 8.D.4, 8.E.2, 9.C.3–4, 10.A–H, 14.B.2, Scenario Book VI.A–B, the Majestic narrative g-t 19–28. Numbers only from the scans: `boarding-combat-chart.jpg` (Boarding Combat, TBCF odds, Other DRMs, Skill Factors, Grappling, Unfouling; p.109) and `gunfire-results-chart.jpg` (Marine Fire, Crew Loss; p.110). All re-read for this spec; `crew_quality_table.json`, `unfouling_table.json` and `crew_loss_table.json` match them.

**Checked against the PDF:** p.28, 8.C.1 "each used ≤ two MPs" (**fixed in `close_action.md`**; OCR read "< fvo"). p.33, the 10.D.4 example really prints "10% of 58": a misprint in the book (see 0.2).

---

## 0. Decisions (binding; they override anything below that disagrees)

### 0.1 Settled from the approved prototype

| Draft question | Decision | Settled by |
|---|---|---|
| UX2 plotting FB/BR/BA/BD | The **Boarders** station of the crew overlay (upper deck, waist; marines and sailors; lowest-numbered sailor sections first, with the refusal text). The "row panel" and "map action" options are dropped. The board order and standing down, which the prototype does not show, are designed in §4.2. | Prototype station `boarders`; mapping §2–3 |
| Open q. 5 marine fire scope | Implemented in full (7.G): the overlay has **Marine fire** as the marines' default station. | Prototype station `marine_fire`; mapping §2 (4.B.4) |
| Mapping §2 open question (skip sections fighting a fire) | No skip; see the crew spec §0.1. A burning ship cannot form boarders at all. | 10.A.2, 8.E.2, 4.B.2 example |

### 0.2 Settled from the rules and charts

| Draft question | Decision | Settled by |
|---|---|---|
| Open q. 1, the 10.D.4 example | The loss is a percentage of the **roller's** TBCF (Heureux loses 10 % of Majestic's 44 = 4 BCF, not the printed "10% of 58"). | Chart column "Enemy loses this % of Roller's TBCF"; charts win over text |
| Open q. 6 struck ships at game end | No house rule. Capturing an already-struck ship scores nothing extra (VI.B.2–3: struck and captured are the same 100 %); its only rules use is to stop a rally (10.A.3, 14.B), which Leeward lacks. The game still ends when a side is all struck. | VI.A.1c, VI.B.2–3 |
| Open q. 11 MPs for grappling | Every executed step counts, turns included: 8.C.1 example 2 counts "S1P2" as 5 MPs. `ShipState.mp_used_this_turn` (crew spec §2.2). | 8.C.1 example 2 |
| Open q. 13 fire | `ShipState.is_burning()` from the crew spec. | Crew spec §3.9 |
| Grappling when fouled | The chart's "Ships are Fouled: −1" applies, although 8.C.1 says fouling "does not affect their grappling chance". | Chart wins over text |
| Marines when boarded | The marine section defends whenever the ship is boarded, whether it was on a task or unplotted, unless it is already FB/BR/BA. | 10.C.3; SoP IV.A; 2.B.4a |

### 0.3 Draft recommendations applied (no answer was given; none is touched by the prototype)

- **UX3 boarding combat display:** a boarding card in the combat playback for each action, and the same lines in the combat log (§4.5).
- **UX4 captured ship on the map:** ring and pennant take the captor's colour at once; a prize flag is added; dashed ring with a turn counter while the boarders reorganize; hollow icon on the minimap.
- **UX5 commanding a prize:** selectable like an own ship; movement disabled with the reason; the crew overlay offers only what 10.H.2 allows.
- **UX6 prize-crew size:** asked in the maintenance prompt, default the minimum.
- **UX7 several enemies boarding one ship:** defenders are allocated automatically (§3.4).
- UX1 (how grappling is ordered) changes the turn flow, so it stays a question: §8 Q1.

### 0.4 Rules interpretations made here (say so if you disagree)

1. **Rounding** "to the nearest whole BCF": halves round up (10 % of 45 = 4.5 → 5).
2. **Both ships plot BA at each other** (10.C.5b): there is one action. The ship with the higher TBCF is the attacker; the other defends with every section it has FB, BR or BA against that enemy.
3. **CQ F and G** "may not board" (10.A.2): they may not plot BA. They may plot FB to defend, and their marines defend under 10.C.3.
4. **Boarding a burning ship:** refused (10.A.2). The Majestic narrative has Heureux board her in g-t 20 while her fire, lit in g-t 18, is not yet out; the rule text is followed, not the narrative. A fire that breaks out during an action does not end it (8.E.2: engaged sections do not stop).
5. **"Target did not move" −1** (Grappling): the target used 0 MPs this g-t. Drift is not movement.
6. **Link broken while reorganizing** (10.G.2): the boarders are crossed off the parent and, being aboard, become the prize crew when their reorganizing ends (all of them; no return).
7. **Friendly ships** may grapple each other (8.C.1) but the AI never does, and the prompt lists friendly targets after enemy ones.
8. **A ship fouled to several ships:** `fouled_with` still holds one partner (existing limitation; 8.D.3's example has two). Several links are possible through grapples. New `feature_diff.md` §3 row.

---

## 1. Rules summary

### 1.1 Grappling and ungrappling (8.C; SoP V.C–D)

- **Who (8.C.1, 8.C.3):** a ship may try to grapple **each adjacent ship once** per g-t, if **both** ships used **≤ 2 MPs** in the Movement Phase. Orientation does not matter. Friendly ships may grapple each other but must roll. Burning ships, ships at CQ F or G, and struck ships **cannot grapple** (they can be grappled).
- **Roll (8.C.2):** d10 on the Grappling table; one grapple per pair.
- **Ungrappling (8.C.4):** after all grappling attempts, either ship of a grappled pair may roll d10 on the **Unfouling** table with the "All Uses" and "Ungrappling Only" DRMs. Never automatic. Needs no CS.
- **During boarding (8.C.5, 8.D.4, 10.D.8):** ships locked in a boarding action may not ungrapple or unfoul **from each other**; they may from other ships, with **+1** if their marines are fighting in a boarding action.
- **Struck partner (8.C.6, 9.C.4):** a struck ship is CQ G for these DRMs.
- **Grappled ships (8.C.7):** cannot move or turn; they drift, never partially. **8.A.6:** a group grappled or fouled together drifts as one, on one d10 by the member least likely to drift; if any hex is blocked the whole group stays.
- **5.D.5:** a ship grappled at WF=L is in irons. Leeward derives "in irons" from WF=L at speed 0, which a grappled ship always has.

**Grappling table (d10):** **≤ 2 succeeds**. DRMs: ± SK mod · ships are fouled **−1** · attempting to tow **−1** (n/a) · marines not available **+1** · wind speed 4 **+1** · target did not move **−1**.

**Unfouling table (d10)** by g-t of the attempt 1 / 2 / 3+: success **≤ 2 / ≤ 3 / ≤ 4**. DRMs (all uses): ± SK mod, marines not available **+1**. DRMs (ungrappling only): **−1 per CQ level** the roller is better than the enemy, friendly ships **−2**, wind speed 4 **−1**.

**Skill factors:**

| CQ | SK mod | BCF sailor box | BCF marine box |
|---|---|---|---|
| A | −3 | 8 | 10 |
| B | −2 | 7 | 9 |
| C | −1 | 6 | 8 |
| D | 0 | 5 | 7 |
| E | +1 | 4 | 6 |
| F | +2 | 3 | 5 |
| G | +3 | 2 | 4 |

### 1.2 Forming boarders and boarding procedure (10.A–C, 4.B.1)

- **Eligibility (10.A.2):** only between **enemy** ships **fouled or grappled at the start of the g-t**. CQ F or G may not board. Ships on fire may neither board nor be boarded.
- **Struck targets (10.A.3):** may be boarded; the boarders **win automatically and do not reorganize**.
- **FB (10.B.2):** a CS plots FB for one g-t. Sailor CSs form **lowest-numbered first**; the marines may FB regardless. FB sections can **defend in the same g-t** and **board from the next g-t**.
- **BR (10.B.3):** readied CSs plot BR every later g-t until they board (BA) or disband (BD).
- **Restrictions (10.B.4):** FB/BR sections do nothing else. Marines at FB/BR may use marine fire and count as "available".
- **BD (10.B.5):** one g-t, nothing else meanwhile (same marine exception). A CS disbanded by a combat result is free the next g-t.
- **Boarders counter (10.B.6):** forming is announced to all; the counter stays while any CS is FB, BR or BA.
- **BA (10.C.1):** a ship with readied CSs, fouled or grappled to an enemy at the start of the g-t, may plot **BA for one or two readied CSs per g-t**. Sailor CSs attack in numerical order from the lowest section with boxes. **S4 may FB and BR but never BA.** BA sections must board.
- **Defending (10.C.2–3):** a ship defends with its FB/BR sections; its marines join automatically (0.2).
- **Timing (10.C.4, 2.B.4):** (a) BA announced, defenders' marines replot; (b) all gunfire and marine fire; (c) boarding combat, on what is left.
- **Attacker (10.C.5):** the only BA ship; if both plot BA, the higher TBCF, then the better CQ, then a random roll.
- **Fire (8.E.2):** when a fire breaks out, FB/BR sections not yet engaged are disbanded.

### 1.3 Boarding combat (10.D)

1. **TBCF (10.D.1):** the sum over all boxes in the action of BCF(current CQ, sailor or marine).
2. **DRMs (10.D.2):** each side takes the odds DRM on its own F:E ratio, **rounded down** to the next lower listed ratio (1:1 = 0, left off the chart by accident). The attacker alone adds the "Other DRMs".
3. **Roll (10.D.3):** both sides roll 2d6 at once and add their DRMs.
4. **Losses (10.D.4):** the enemy loses the row's % of the *roller's* TBCF, in BCF. Boxes are removed one at a time: d6 on the Crew Loss "All Other Causes" row (S 1–3, M 4–6) unless only one type is in the action; subtract that box's BCF; repeat until the requirement is met. Overshoot is normal.
5. **Special results (10.D.5):** only one side may get one. If both roll one, the higher modified DR applies; equal DR: the higher TBCF before losses; equal TBCF: neither.
6. **10.D.6:** boarders share every result of their parent ship and surrender if it strikes.
7. **10.D.7:** while a ship has boarding tasks plotted, gunfire and marine-fire crew losses against it use "Gunfire at Hull" if **only sailor** CSs are FB/BR/BA/engaged, and "All Other Causes" otherwise.

**Boarding Combat table (2d6, modified):**

| DR | Enemy loses % of roller's TBCF | Special, rolled by attacker | Special, rolled by defender |
|---|---|---|---|
| ≤ 4 | 2 % | No effect | No effect |
| 5 | 4 % | No effect | d10 **< attacker's MR** ⇒ attacker repulsed |
| 6 | 6 % | No effect | d10 < attacker's MR ⇒ attacker repulsed |
| 7 | 8 % | No effect | d10 < attacker's MR ⇒ attacker repulsed |
| 8 | 10 % | No effect | Attacker repulsed and takes 1 MC |
| 9 | 15 % | d10 **< defender's MR** ⇒ defending ship captured | Attacker repulsed and takes 1 MC |
| 10 | 20 % | d10 < defender's MR ⇒ captured | Attacker repulsed and takes 1 MC |
| 11 | 25 % | Defending ship captured | Attacker repulsed and takes 2 MC |
| ≥ 12 | 30 % | Defending ship captured | Attacker repulsed and takes 2 MC |

**TBCF odds DRMs (F:E, both sides):** ≤1:4 **−4** · 1:3 **−3** · 1:2 **−2** · 2:3 **−1** · 1:1 **0** · 3:2 **+1** · 2:1 **+2** · 3:1 **+3** · ≥4:1 **+4**.

**Other DRMs (attacker only):** defending ship class 1 **−3**, class 2 **−2**, class 3 **−1**; defending ship larger class **−1 per class difference**; smaller class **+1 per class difference**. (A frigate boarding a 74: −2 −1 = −3. A 74 boarding a frigate: −1 +1 = 0.)

### 1.4 Worked example (10.D.1–5, Heureux v Majestic), test 30

Heureux (CQ D) boards with marines 6 + S1 4: 6×7 + 4×5 = **62**. Majestic (CQ C) defends with S1 2 + marines 4 (replotted): 2×6 + 4×8 = **44**. Heureux 62:44 = 1.41 → 1:1 → 0, class-2 defender −2 ⇒ **−2**. Majestic 44:62 = 0.71 → 2:3 ⇒ **−1**. Rolls 9 and 9 ⇒ 7 and 8. Majestic loses 8 % × 62 = 4.96 → **5 BCF** (one box). Heureux loses 10 % × 44 = 4.4 → **4 BCF** (one box; the book prints 6, see 0.2). Majestic's 8 is "Attacker repulsed and takes 1 MC"; Heureux's 7 has no attacker special ⇒ Heureux's boarders disband and she takes 1 MC.

### 1.5 Winning, multi-ship, reorganizing, prizes (10.E–H)

- **Continuation (10.E.1):** an action goes on each g-t until won. Engaged CSs are locked. More may join (FB then BA for the attacker; FB for the defender).
- **Attacker wins (10.E.2):** the defender (a) has struck, (b) has no CS to defend with, (c) strikes from hull loss or morale during the action, (d) is "captured" by the table, (e) loses every crew box in the action.
- **Defender wins (10.E.3):** all attacking boxes are gone, or "attacker repulsed". **Counter-boarding (10.E.4):** next g-t every CS that defended (not S4) may BA, not just two.
- **Multi-ship (10.F):** split into one-attacker/one-defender combats, each CS engaged with one named enemy, all resolved separately and at once. A sixth enemy ship boarding captures the ship outright.
- **Reorganizing (10.G.2–5):** every winning attacking CS plots **RO** for **5 + SK** g-t's (CQ A 2, CQ E 6) and can only defend the prize. If parent and prize part meanwhile, the boarders are crossed off the parent. If the prize is boarded meanwhile, reorganizing starts again after that action, and the prize's original crew joins the new defence at CQ G. Defenders who win do not reorganize.
- **Prize crew (10.G.6–9):** minimum by the prize's class: **class 1 = 4 boxes, 2 = 3, 3 = 2, 4 = 1**; more is allowed. Boxes come from the surviving boarders, then from non-boarding CSs, which must then reorganize too. In the Status Update of the g-t RO completes, the boxes leave the parent's marines and/or lowest-numbered sailor CS **without MCs** and are formed into sections of the prize's original sizes (6-6-7-7:7 with 8 sailors + 1 marine → 0-0-1-7:1). The prize crew takes the captor's **current CQ and MR**. The other boarders are back aboard at the start of the next g-t.
- **Captured ships (10.H):** friendly to the captor from capture; the old side may fire at them. They **may not move** or plot any task except **boarding and repairing**; they may grapple, ungrapple, unfoul. The original crew is locked below (pumps and firefighting only). The prize crew takes all crew losses. If it falls **below the minimum**, the original crew retakes the ship at the start of any g-t in which it has **≥ 2×** the prize crew's boxes; the ship is then **CQ/MR G6** and acts normally.
- **BGN (1.G.8c):** a ship used by another navy uses that navy's BGN at ranges 11–15.
- **Victory (VI.B.2–3):** surrendered, destroyed and captured are all "struck": 100 % of VP value, never also damage VPs.

### 1.6 Marine fire (7.G)

Marines only, at an adjacent enemy, one target per g-t. Marines plotted to a non-boarding task cannot fire; FB/BR/BD marines may; BA or engaged marines may not. One d6 on the Marine Fire table by marine boxes at the start of the g-t, simultaneous with gunfire (7.G.5). Each box lost is rolled on Crew Loss "All Other Causes", or per 10.D.7.

| d6 (mod) | 1–2 boxes | 3–4 | 5–6 | 7–8 | 9–10 | 11+ |
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
- `data/rules/boarding_combat_table.json`: rows `"4"` (≤ 4) … `"12"` (≥ 12) → `{"pct": 2, "attacker": "none"|"capture_if_lt_mr"|"capture", "defender": "none"|"repulse_if_lt_mr"|"repulse_mc1"|"repulse_mc2"}`; `odds_drm` as ordered `[[num, den, drm], …]` from 1:4 to 4:1 with 1:1 = 0; `class_drm` `{"1": -3, "2": -2, "3": -1, "per_class_larger": -1, "per_class_smaller": 1}`; `prize_minimum` `{"1": 4, "2": 3, "3": 2, "4": 1}`.
- `data/rules/grappling_table.json`: `{"success_max": 2, "drm": {"fouled": -1, "towing": -1, "marines_unavailable": 1, "ws4": 1, "target_did_not_move": -1}}`; `unfouling_table.json` gains `ungrapple_drm` `{"per_cq_better": -1, "friendly": -2, "ws4": -1}`.
- `data/rules/marine_fire_table.json`: columns 1-2 … 11+, rows ≤ 1 … 6+, the DRMs.
- `crew_tasks.json` gains FB, BR, BA, BD (`sections [1, 1]`, `turns {"fixed": 1}`).
- `CombatTables`: `boarding_row(dr)`, `odds_drm(f, e)` (integer compare `f * den >= e * num`, no floats), `boarding_class_drm(defender_class, attacker_class)`, `prize_minimum(ship_class)`, `bcf(cq, marine)`, `grapple_success_max()`, `grapple_drm(name)`, `ungrapple_drm(name)`, `marine_fire_result(dr, boxes)`. `validate_combat.py`: rows 4–12 present, pct rising, odds ladder ordered, marine-fire rows never rising with the die.

### 2.2 Grappled v fouled
| | Fouled (exists) | Grappled (new) |
|---|---|---|
| Cause | Collision, blocked drift (6.E, 8.A.4) | Grappling roll (8.C.2) |
| Storage | `ShipState.fouled_with: String` (one partner) | `ShipState.grappled_with: Array[String]` (any number, symmetric) |
| Release | Unfouling, `unfoul_attempts` | Ungrappling, `ungrapple_attempts: Dictionary` partner → attempts |
| Movement | Refused (`SHIP_FOULED`) | Refused (new `SHIP_GRAPPLED`) |
| Boarding link | Yes | Yes |

`ShipState.linked_ids()` = fouled partner ∪ grapples. A pair can be both. `ShipStateController.add_grapple(a, b)` / `remove_grapple(a, b)` update both ships. `DamageController.destroy` also clears grapples. `GameState.linked_at_plot: Dictionary` (ship_id → Array of ids) is taken when PLANNING begins: "fouled or grappled at the start of the g-t" (10.A.2).

### 2.3 Boarding actions (new `scripts/state/boarding_state.gd`)
`GameState.boarding_actions: Array[BoardingAction]`, serialized into the turn snapshot (`boarding_history[turn]`).
```
BoardingAction { id: int, attacker_id, defender_id: String,
  attacker_sections: Array[int], defender_sections: Array[int],   # 0-3 sailors, 4 = marines
  started_turn: int, rounds: int,
  state: "declared" | "engaged" | "attacker_won" | "defender_won",
  prize_size: int }                                               # chosen size, 0 = minimum
```
Finished actions are dropped at END_TURN; `attacker_won` stays until its boarders' RO tasks end.

### 2.4 What boarding takes from the crew spec
Section indices, `crew_tasks`, `plotted_actions["crew_assignments"]` / `["crew_orders"]`, `CrewTaskController.register_handler`, `force_task`, `cancel_section`, `CrewRules`, `CrewAuto` (crew spec §3.9). Boarding registers a `BoardingTaskHandler` (`scripts/server/boarding_task_handler.gd`) for FB, BR, BA, BD:

1. **Flags:** `section_order = "lowest_sailor_first"` (4.B.1, 10.B.2, 10.C.1; marines exempt); `forced` and `fire_exempt` for sections in an `engaged` action (10.E.1, 8.E.2); `marines_available = true` for FB, BR, BD (10.B.4–5); `abandonable = true` for FB/BR (leaving them is BD, §4.2).
2. **`can_plot`** delegates to the pure static `BoardingRules.task_error(ship, sections, code, params, plan, ctx) -> String` (like `FireRules`): S4 never BA; at most two *new* BA per g-t unless counter-boarding (10.E.4); BA needs sections readied on an earlier g-t and a target that is an enemy in `linked_at_plot`; not BA at CQ F/G; no FB/BR/BA while burning; a burning or friendly target refused; a prize may plot boarding tasks only for its prize crew.
3. **Continuation:** a section that did FB or BR and is plotted FB/BR again continues as BR. `CrewRules.default_plan` keeps readied sections at BR (10.B.3).
4. **Hook `on_fire_breaks_out`:** ends every FB/BR task not in an engaged action ("disbanded: fire aboard").
5. **Orders:** `crew_orders["boarding"]` = `""` | `"ready"` | `"board:<ship_id>"` | `"stand_down"`.
6. **Automatic rule A2b** (between the crew spec's A2 and A3), fixed like the others:
   - `"ready"`: the marines and the lowest-numbered sailor section with boxes form or stay ready.
   - `"board:<id>"`: as "ready", and the readied ones among those two go BA (the marines and S1 on the first g-t they are ready).
   - `"stand_down"` or `""` with readied sections: they plot BD.
   - While an action is engaged, its sections are locked (A0) and the order is ignored for them.
7. **Server override in COMBAT (10.C.3):** `force_task(defender, [MARINES], "FB", {"reason": "repel boarders"})`, which ends the marines' task and its progress. Repulse (10.D.5a): `cancel_section(…, "repulsed")` on every FB/BR/BA section of the attacker.
8. **Predicates:** `ShipState.has_boarders()` (any FB/BR/BA task: the public counter, the marine-fire −1, 10.D.7) and `boarding_sections(enemy_id)`.
9. **Section loss (4.B.3):** `cancel_section`; an emptied engaged section also leaves its `BoardingAction`.

### 2.5 Capture and control
- `Ship.player_id` stays the **original owner**. New `ShipState.controller_id: int = -1` (−1 = original owner). `ShipState.player_id` returns `controller_id` when ≥ 0, so every current reader (selection, owner colour, gunnery sides, AI) follows control. `ShipState.original_player_id` reads `Ship.player_id`.
- `GameState.transfer_control(ship_id, player_id)` (server, through `ShipStateController.set_controller`) re-indexes `ships_by_player`.
- New status **`CAPTURED`**. `is_out_of_play()` stays "status ≠ ACTIVE", so a prize never keeps its holder alive and plots no movement. New `is_targetable()` = ACTIVE or CAPTURED, used by `GunneryCalculator` in place of the struck test (struck ships stay untargetable, `feature_diff.md` §4; prizes may be fired on, 10.H.1). New `can_be_boarded()` = ACTIVE, STRUCK or CAPTURED, and not burning.
- Prize data on the captured ship: `prize: Dictionary` = `{captor_id}` and `original_crew: {crew_count, marine_count, crew_quality, morale_rating}`. While a prize, the ship's live `crew_count` / `marine_count` / `crew_quality` / `morale_rating` **are the prize crew's**, so damage, morale and the overlay work unchanged. Between capture and prize-crew assignment the live crew is empty and the boarders, still on the parent's log, defend.
- **BGN (1.G.8):** `Ship.is_french_gunned()` becomes `ShipState.is_french_gunned()`: the controlling side's navy. Scenarios gain an optional per-side `navy`, defaulting to the ship type's `nationality`. It matters only if prizes may fire (§8 Q2).
- **Recapture by the original crew (10.H.4):** status ACTIVE, `controller_id` −1, live crew = `original_crew`, CQ G, MR 6.

### 2.6 Victory points
- `VictoryController.points_lost` already gives 100 % for any ship out of play, so CAPTURED is covered. `_points_scored(p)` must sum the ships whose **original** owner is the enemy (new `GameState.get_original_player_ships`), since `get_player_ships` now follows control.
- `_is_defeated(p)` is unchanged: it counts ships p controls that are ACTIVE. A side holding only prizes is defeated.
- Boxes detached as a prize crew: §8 Q4. Recaptured ships: §8 Q5.

---

## 3. Server design

### 3.1 Phase placement
| Step | Phase | Call |
|---|---|---|
| Plot FB/BR/BA/BD | PLANNING | Crew spec engine + `BoardingRules`; `linked_at_plot` taken on entry |
| Announce BA; marines replot; instant wins (10.E.2a–b) | COMBAT_RESOLUTION, on entry, before DECLARE | `boarding_controller.declare(phase)` |
| Gunfire and marine fire | DECLARE → RESOLVE | `gunnery_resolver.resolve`, then `marine_fire_resolver.resolve`, on the same start-of-step state |
| Boarding combat | RESOLVE, right after the fire | `boarding_controller.resolve(phase)` |
| Group drift | DRIFT_CALCULATION | `drift_resolver` (8.A.6 groups) |
| Grappling, then ungrappling | STATUS_ADJUSTMENT, **before** unfouling (2.B.5c–e) | `grappling_controller.resolve_grapples`, `resolve_ungrapples` |
| Unfouling, fixes, fire | STATUS_ADJUSTMENT | as the crew spec; unfouling skips pairs locked in boarding |
| RO countdown; prize crew put aboard | STATUS_ADJUSTMENT, after `advance_tasks` (8.G.1c) | `boarding_controller.advance_reorganizing` |
| Boarding MCs | MORALE_CHECK | existing `morale_controller` |
| Boarders back aboard; 10.H.4 recapture | start of the next turn (`_start_new_turn`) | `boarding_controller.start_of_turn` |

`_enter_combat_resolution_phase` skips combat today when no shot is eligible. New test: skip only when there is no eligible gunfire, no eligible marine fire, no BA declared and no engaged action. With boarding but no fire, DECLARE is skipped and RESOLVE runs boarding alone. Boarding needs no choice mid-combat, so `CombatStep` is unchanged; its events join the RESOLVE log.

**Maintenance orders (§8 Q1).** Grappling and ungrappling are not plotted (4.A.1). STATUS_ADJUSTMENT gains a waiting step, `MaintenanceStep.ORDERS`, like the bear-off pause, entered only when the human has a choice: an eligible grapple, a grapple to throw off, or a prize-crew size. `maintenance_orders_requested(options)` is emitted; the player answers with `player_submit_maintenance_orders(player_id, orders) -> String` (`{"grapple": [[ship, target]], "ungrapple": [[ship, partner]], "prize_size": {action_id: n}}`). The AI answers at once. Headless tests leave the prompt list empty, as for bear-off.

### 3.2 Controllers
- **`GrapplingController`** (`scripts/server/grappling_controller.gd`). `grapple_options(ship_id)` (pure): adjacent ships (any hex of one next to any hex of the other), both `mp_used_this_turn ≤ 2`, roller not burning, CQ not F/G, in play, not already grappled to it. `grapple_chance(ship_id, target_id)` for the prompt. `resolve_grapples(orders, phase)`, then `resolve_ungrapples(orders, phase)`.
- **`BoardingController`** (`scripts/server/boarding_controller.gd`). `declare`, `resolve`, `advance_reorganizing`, `start_of_turn`, `capture(defender_id, captor_id, struck_target, phase)`. Mutations go through `ShipStateController`, `DamageController` and the crew-task controller. Pure helpers: `tbcf(ship_id, sections)`, `drms(action) -> {attacker: {odds, other, total}, defender: {…}}`, `preview(ship_id, enemy_id, sections)` for the overlay.
- **`MarineFireResolver`** (`scripts/server/marine_fire_resolver.gd`). Marine orders are a second list in the fire submission (`{ship_id, target_id}`), validated by `FireRules.marine_error` (marines have boxes; `marines_available()` and not BA/engaged; target adjacent, enemy, targetable; one target). `eligible_marine_shots()` joins `any_eligible_shot` in the skip test.
- **`DamageController`**: `apply_boarding_losses(ship_id, bcf_required, sections, cq, phase) -> Array` (one d6 per box when both types are in the action; sailors from the lowest engaged section; emptied sections note MCs as for gunfire), and `detach_prize_crew(ship_id, sailors, marines)` (no MC). Gunfire and marine-fire crew losses take their Crew Loss row from `BoardingRules.crew_loss_cause(ship, default_cause)` (10.D.7).
- **`DriftResolver`**: groups are the connected components over `linked_ids()` (8.A.6); one roll by the member least likely to drift; no partial drift for a linked ship.
- **Plotting**: `SHIP_GRAPPLED`, and `SHIP_CAPTURED` ("a prize cannot sail, 10.H.2").

### 3.3 Dice order (the contract for `ScriptedDice`)
**Marine fire:** after all gunfire dice; firers in ascending ship_id: one d6, then one Crew Loss d6 per box (none if the target has one crew type).
**Grappling:** rollers by ship_id; for each, its ordered targets by ship_id; one d10 per attempt; a pair grappled earlier in the sub-phase is skipped. Success: `d10 + SK + DRMs ≤ 2`.
**Ungrappling:** pairs by the lower ship_id; the lower id rolls first if it ordered an attempt, the partner only if that failed. Success: `d10 + SK + DRMs ≤ unfouling_success_max(attempt)`.
**Boarding**, per action in (defender_id, attacker_id) order:
1. The 10.C.5b tie-break d6, only when TBCF and CQ tie (1–3: the lower ship_id attacks).
2. Attacker 2d6, then defender 2d6.
3. The defender's loss d6s, then the attacker's (one per box; none with one crew type).
4. The special-result d10, only for a "< MR" result that survives 10.D.5.
TBCFs are computed after all gunfire and marine fire; one action's results do not change another's TBCF in the same g-t (10.F.3).

### 3.4 Declare, resolve, capture
- **`declare`:** for each ship with BA tasks begun this g-t, by target: refuse and end tasks whose target is no longer boardable (it caught fire, was destroyed); create or join the `BoardingAction`; pick the attacker by 10.C.5; `force_task` the defender's marines to FB. Struck target (10.E.2a) or no defender section (10.E.2b): `capture` now, no roll. Log `BOARDERS_AWAY`, `MARINES_DEFEND`.
- **Several attackers on one defender (10.F):** the defender's sections are shared out automatically: marines to the attacker with the highest TBCF, then its readied sailor sections in ascending order to the attackers in descending TBCF, round robin; an attacker left with no defender section wins under 10.E.2b. A sixth boarding ship captures outright. Logged.
- **`resolve`:** per §3.3; apply losses; then the special result. Repulsed: the action is `defender_won`, the attacker's sections are disbanded and its MCs noted (trigger `boarding_<action>_<turn>`). Captured, or all defending boxes in the action gone, or the defender struck this g-t: `capture`. Otherwise the action is `engaged` and its sections stay forced.
- **`capture`:** the action becomes `attacker_won`; status CAPTURED and `controller_id` = the captor's side; the live crew moves to `original_crew` and the live crew is emptied; the prize's plots, tasks (except firefighting by the original crew, which stays automatic as for a struck ship) and pending MCs are dropped; `SHIP_CAPTURED`. Struck target (10.A.3): no RO; the prize crew goes aboard in this g-t's STATUS_ADJUSTMENT. Otherwise each surviving attacking section gets `force_task(…, "RO", {"reason": "boarding", "prize": id})`.
- **`advance_reorganizing`:** when an action's RO tasks have all ended: prize crew of `prize_size` (at least the minimum, at most the surviving boarders; fewer boarders than the minimum: all of them, §8 Q3) via `detach_prize_crew`, formed into sections of the prize's original sizes from S4 down, marines to M, CQ and MR the captor's current ones. `PRIZE_CREW`. If the link to the prize broke meanwhile, every boarder becomes prize crew (0.4 #6).
- **Prize boarded while its captors reorganize (10.G.5):** the RO tasks end, the reorganizing sections defend (forced FB), and the `original_crew` boxes join at CQ G BCFs. If they hold, RO starts again from 0.
- **`start_of_turn`:** boarders whose RO ended are free again; 10.H.4: a prize whose crew is below the minimum and whose `original_crew` has at least twice its boxes reverts (`RECAPTURED`).

### 3.5 Events (`PhaseEvents.Type`) and log text
| Type | Data | Text |
|---|---|---|
| `GRAPPLE` | `{roll, modifier, needed, success}` + target | "Vengeance throws grapples at Hermione: 2 −1 = 1 ≤ 2, grappled" / "…5 > 2, misses" |
| `UNGRAPPLE` | `{roll, modifier, needed, attempt, success}` | "Hermione cuts the grapples to Vengeance (3 −2 −1 = 0 ≤ 2)" |
| `BOARDERS` | `{sections, task}` | "Vengeance forms boarders (S1, marines)" (public, 10.B.6) |
| `BOARDERS_AWAY` | `{sections}` + defender | "Vengeance: boarders away! (S1, marines) onto Hermione" |
| `MARINES_DEFEND` | `{cancelled_task}` | "Hermione's marines drop their repairs to repel boarders" |
| `MARINE_FIRE` | `{boxes, roll, modifier, result}` then `DAMAGE` | "Vengeance's marines fire on Hermione: 3 −1 = 2, one box" |
| `BOARDING_ROUND` | `{attacker: {tbcf, odds, drm, roll, total}, defender: {…}, losses: {att_bcf, def_bcf}}` | "Boarding, Vengeance onto Hermione: 62 v 44; attacker 9 −2 = 7, defender 9 −1 = 8" |
| `DAMAGE` (cause `boarding`) | as today | "Hermione loses 1 sailor box (5 BCF needed)" |
| `BOARDING_RESULT` | `{result, d10, mr, mcs}` | "Vengeance's boarders are repulsed and take 1 MC" / "Hermione is captured!" |
| `SHIP_CAPTURED` | `{captor_id, struck_before}` | "Hermione is taken by Vengeance" |
| `PRIZE_CREW` | `{sailors, marines, cq, mr}` | "Prize crew of 3 (B3) put aboard Hermione" |
| `RECAPTURED` | `{original_boxes, prize_boxes}` | "Hermione's crew rises and retakes the ship (G6)" |

### 3.6 AI (`StubAI`)
The AI gives orders; sections are placed by Automatic (crew spec §3.3, rule A2b here).
- **Boarding order** (in `assign_crew`): `"ready"` when linked to an enemy, or adjacent to an enemy that `has_boarders()`. `"board:<id>"` when its readied TBCF against the enemy's visible defence (its boarders plus its marines) is at least 3:2 after the class DRM, or the target has struck. `"stand_down"` when no enemy has been linked or adjacent for two g-t's.
- **Grapple:** any eligible enemy that has struck, or whose crew boxes × BCF are at most two thirds of its own. Never a friendly ship.
- **Ungrapple:** when grappled to an enemy it would not board by the rule above, and not locked; never from a struck enemy it is boarding.
- **Marine fire:** the adjacent enemy with the best modified die; ties: one that `has_boarders()`, then the lower ship_id.
- **Prize crew:** the minimum, plus one if another enemy ship is within 3 hexes.
- **Movement:** prizes and grappled ships plot nothing.

---

## 4. UX

Boarding is plotted in the crew overlay (crew spec §4). This section covers only what boarding adds.

### 4.1 Stations from the prototype

| Station | Real behaviour |
|---|---|
| **Boarders · FB** (upper deck, waist, capacity 5) | Supplied to `CrewRules.stations` by the boarding handler. Shown for every ship in play. Accepts marines and sailors; sailors lowest-numbered first: "Boarders come from the lowest-numbered sailor sections first: send S1 before S3 (4.B.1)." Disabled, with the reason, when the ship is on fire ("A ship on fire can neither board nor be boarded (10.A.2)"). Token tags: **FB** (forming this turn), **BR** (ready), **BA** (away), **BD** (standing down); a lock and "fighting" for engaged sections. Station note: each sailor section here is −3 on the guns (the Guns readout shows it live); marines here still fire muskets. |
| **Marine fire** (upper deck, quarterdeck rail) | The marines' default. Its note names the muskets' targets: "Adjacent enemy: Hermione" or "No enemy alongside". The target itself is chosen with the guns (§4.4), because it is not plotted (4.A.1). |

### 4.2 The board order and standing down (designed here; not in the prototype)

- The Boarders station carries an order picker, like the Sails station's target picker: **Stand ready** (default) · **Board ‹enemy›!**, one entry per enemy in `linked_at_plot` that can be boarded · on the g-t after a repulse, **Counter-board ‹enemy›!**. It sets `crew_orders.boarding`. Under each "Board" entry: the odds as they stand, "62 v about 44 · you −2", from `BoardingController.preview` (the enemy's side counts only its announced boarders and its marines).
- With "Board ‹enemy›!" chosen, `CrewRules` marks the sections that go: the readied marines and the lowest readied sailor section, two at most (10.C.1); for a counter-board, every section that defended except S4 (10.E.4). Clicking a readied token in the station toggles it between BA and BR; an illegal choice is refused with the rule ("S4 never boards: the minimum crew (10.C.1)", "Only two sections may go in one turn (10.C.1)", "S2 formed this turn: it can board next turn (10.B.2)").
- **Standing down:** dragging a *readied* token off the station does not free it this turn: it shows BD and sits in a "Standing down" strip under the station; the message bar says "S1 stands down this turn and is free next turn (10.B.5)." A token placed on Boarders this same planning phase can be taken off freely.
- The ship card gains two shortcut buttons while an enemy is linked or adjacent: **Prepare boarders** (order "ready") and **Board ‹ship›!**. They work in Automatic too, where rule A2b places the marines and S1.
- The summary line shows "S1 M boarders" and, when boarding, "S1 M board Hermione".
- A boarders badge on the ship list and a small counter on the map ship are public for both sides (10.B.6).

### 4.3 Grappling and prize-crew prompt (§8 Q1)

After drift, when the player has a choice, a small panel (built like the bear-off panel) lists: each eligible grapple as a toggle with its chance, "Grapple Hermione: needs 2 or less, 40 %"; each grapple that may be thrown off, "Cut the grapples to Hermione: 60 %"; and, in the turn a reorganization ends, a stepper for the prize crew from the minimum to the surviving boarders, showing both ships' crews after it ("Vengeance keeps 0-5-6-6:2"). **Done** submits. Nothing to choose: no pause.

### 4.4 Marine fire in the fire panel

The fire-declaration panel gains a "Marines" block for each of the player's ships whose marines may fire: one row per adjacent enemy with the table column and the modified chance of a hit, one choice at most. With no gun shot but a marine shot, the panel still opens.

### 4.5 Boarding card, capture, prizes

- **Boarding card** in the combat playback, one per action, after the broadsides: two columns (attacker, defender) with the sections and boxes engaged, TBCF, odds and other DRMs, the 2d6, the % and BCF lost, the boxes lost by type, then the special result in the display face: "REPULSED · 1 MC", "CAPTURED". The log has the same lines.
- **Capture on the map:** the owner ring and pennant change to the captor's colour at once; a prize flag (captor's colour over white) is added; while the boarders reorganize the ring is dashed with the turns left; the minimap icon is hollow in the captor's colour.
- **Commanding a prize:** selectable like an own ship. The plotting panel shows "Prize: cannot sail (10.H.2)". Its crew overlay shows the prize crew's tokens and only the Boarders and repair stations (10.H.2); Serve the guns is shown disabled, "A prize does not fight" (§8 Q2); fires are fought by the original crew automatically (10.H.3), shown with AUTO and no token. The status panel reads "Prize of Vengeance · prize crew 3 (B3) · original crew 18 below".
- **Reorganizing boarders** appear in the parent's overlay in the Reorganizing tray (crew spec §4.3) as "RO 1/3 · aboard Hermione".

---

## 5. Implementation plan

Each phase: GUT tests with `ScriptedDice`, `make test`, both validators, the `feature_diff.md` rows named, a relaunch with `game_get_errors` at zero. Each leaves the game playable. Needs crew spec phases 1–3 (engine, RO, overlay) and 4 (`is_burning`; until then B3 may read `fires > 0`). The `scv-reviewer` runs once after B6.

- **B1 Data.** The three JSON tables, the FB/BR/BA/BD rows, `CombatTables` accessors, validator checks, spot tests. No behaviour change.
- **B2 Marine fire.** `MarineFireResolver`, `FireRules.marine_error`, the fire-panel block, the AI's choice, the Marine fire station note. *Diff:* §2.1 "Marine fire" → **Fixed** (the −1 for boarders arrives with B4).
- **B3 Grappling.** `grappled_with`, `GrapplingController`, the maintenance-orders step and prompt, `SHIP_GRAPPLED`, group drift (8.A.6), marines-engaged DRM stubbed until B4, AI. *Diff:* §2.1 "Grappling and ungrappling" → **Fixed**; §2.2 5.D.5 → **Fixed**; §2.2 9.C.4 → **Fixed** (with the crew spec's firefighting half); new §3 row for 0.4 #8.
- **B4 Boarders and boarding combat, to capture.** `BoardingTaskHandler`, `BoardingRules`, the Boarders station with its order picker and standing down, rule A2b, `linked_at_plot`, `has_boarders`, 10.D.7; `BoardingAction`, `declare`, `resolve`, continuation, repulse, counter-boarding, the combat skip test, the boarding card; status CAPTURED, `controller_id`, `transfer_control`, `is_targetable`, struck-ship capture, RO for the victors, the prize crew at the minimum, the boarders' return, victory changes, capture visuals; unfouling and ungrappling locked during an action. *Diff:* §1 item 5 → **Partly fixed**; §2.1 "Boarding, capture…" → **Partly fixed** (still missing: prize operations, recapture, multi-ship).
- **B5 Prizes.** The prize-crew size choice, the prize's overlay and its boarding and repair tasks, a prize being boarded during RO (10.G.5), 10.H.4 recapture, 1.G.8 BGN, the status-panel lines.
- **B6 Multi-ship (10.F)** and the sixth-ship rule; log wording; CLAUDE.md ("Not implemented", the new controllers and statuses); `feature_diff.md` §1 item 5 and §2.1 → **Fixed**, §5 lines; `scv-reviewer`.

**B1 as built (2026-11-15).**
- The three tables are as §2.1, checked against the scans (p.109, p.110). `marine_fire_table.json` stores `columns` as `[min, max]` pairs (`[11, null]` = 11+) and rows `"1"` (≤ 1) … `"6"` (6+), 0 for the chart's dot; its DRMs are `grappled_or_fouled`, `cq_e_f`, `cq_g`, `target_boarders`, `larger_class`, `optional_range_2`.
- Extra `CombatTables` helpers beyond §2.1: `boarding_loss_bcf(pct, roller_tbcf)` (static; nearest BCF, halves up, integers only, 0.4 #1), `marine_fire_column(boxes)`, `marine_fire_column_label(boxes)` ("7-8") and `marine_fire_drm(name)`. `boarding_row(dr)` returns the row plus its clamped `dr`. `boarding_class_drm` gives class 4 defenders 0 (no chart line).
- The FB/BR/BA/BD rows are data only: no handler is registered, so nothing can plot them before B4. `validate_combat.py` checks them, the three tables and the ungrappling DRMs (rows 4–12, rising %, odds ladder strictly rising by +1 with 1:1 = 0, the class and prize values, marine-fire hits never rising with the die nor falling with more boxes, 6+ never hits).

**B2 as built (2026-11-15).**
- **Request path:** marine orders are the optional third argument of `player_submit_fire_orders(player_id, orders, marine_orders := [])`, `{ship_id, target_id}` dictionaries, validated with the gun orders (nothing stored on rejection). The fire panel's `fire_pressed` signal is unchanged; `GameController` reads `panel.get_marine_orders()`.
- **Where the queries live:** on `MarineFireResolver` (`preview`, `eligible_marine_shots`, `any_eligible_marine_shot`, `validate_orders`), not on `GunneryCalculator`; eligibility is the pure static `FireRules.marine_error(firer, target, range)` plus `marine_orders_error` (7.G.2). The resolver is split into `prepare(orders)` (before the gunfire: boxes and DRMs at the start of the step, 7.G.5) and `resolve(shots, phase)` (after all gunfire dice, §3.3).
- **Targets:** struck and destroyed ships are refused, as for gunfire. B4's `is_targetable()` should replace the test in `marine_error` so prizes become targets.
- **Crew losses:** new `DamageController.apply_crew_losses(ship_id, count, cause, phase, source_id, damage_cause)` rolls a Crew Loss d6 per box only while the target has both crew types (§3.3); gunfire's `apply_hits` still rolls a d6 per box even with one type (unchanged, so gunfire dice orders stay as they were). The row is always "All Other Causes" until B4 adds 10.D.7 (`BoardingRules.crew_loss_cause`).
- **DRMs not yet live:** "target has boarders" reads live FB/BR/BA tasks through `MarineFireResolver.has_boarders` (B4 should point it at `ShipState.has_boarders()`); "grappled" reads `grappled_with` when that field exists (B3). The optional range 2 is not offered.
- **Panel:** the default marine target is the best chance of a hit, then the lower DRM total, then the target id; rows read "Hermione — 7 marines, column 7-8, alongside −1 — hits on 5 or less (83%)". The main button reads "Fire muskets" / "… and muskets". No HOLD_FIRE line is logged for marines that could fire and did not.
- **AI:** as §3.6, and it never fires a shot that cannot mark out a box on any roll.
- **Overlay:** the Marine fire station note is always shown: "Adjacent enemy: Hermione. Targets are chosen with the guns." or "No enemy alongside."; with Automatic holding the marines back the held-back reason comes first. `CrewRules.context` gains `adjacent_enemies` (names, by ship_id).
- **Log:** MARINE_FIRE `{boxes, column, modifiers, modifier, d6, total, crew}` (appended to `PhaseEvents.Type`), "Vengeance's marines fire on Hermione (7 boxes, column 7-8) — d6 5, alongside −1 → 4: 1 crew box", then DAMAGE with cause `marine_fire` ("Hermione loses 1 sailor to musketry").

**B3 as built (2026-11-15).**
- **State:** `ShipState.grappled_with: Array[String]` (symmetric, sorted) and `ungrapple_attempts: Dictionary` (partner → tries), both `@export` (snapshotted) and serialized; `is_grappled()`, `is_grappled_to(id)`, `linked_ids()` (fouled ∪ grapples, sorted, once each), `is_linked()`. Mutators `ShipStateController.add_grapple`, `remove_grapple` (both sides; drops the attempt counts), `set_ungrapple_attempts`. `DamageController.destroy` drops a wreck's grapples. `GameState.linked_at_plot` is **not** built yet: nothing reads it before B4.
- **`GrapplingController`** as §3.2, plus `grapple_error` / `ungrapple_error` (the refusal reasons, used by the request) and `ungrapple_options` / `ungrapple_chance`. Chances are `{needed, modifier, modifiers [{name, value}], percent}` (+ `attempt`). Dice order as §3.3; an order no longer legal at roll time is dropped with a trace line, not logged.
- **Two prompts, not one (deviation from §3.1/§4.3):** the maintenance step is split into `MaintenanceStep.GRAPPLE` and `MaintenanceStep.UNGRAPPLE`, each entered only when a prompted player has a choice. The ungrapple prompt comes after the grapple rolls, so the player can cut a grapple the enemy made this g-t, as SoP V.D allows; a single prompt before any roll could not offer that. Signal `maintenance_orders_requested(player_id, step, options)`; request `player_submit_maintenance_orders(player_id, {"grapple": [[ship, target], …]})` or `{"ungrapple": …}` (the other key, or `prize_size`, is refused in that step). Prompted players: `maintenance_prompt_player_ids` (GameController sets `[0]`; empty in headless tests, whose ships StubAI orders). `advance_phase` is ignored while waiting. `maintenance_options(player_id, step)` is the option list (enemy targets first, 0.4 #7). Prize-crew sizes join the request with B5.
- **DRM readings:** "Each CQ > enemy: −1" applies only against an enemy partner; a friendly partner takes the −2 alone (spec test 7). The marines-not-available DRM is `marines_busy()` (as for unfouling) or `marines_in_boarding()` (8.C.5, stubbed `false` until B4), so it is never counted twice. `locked_in_boarding()` (8.C.5, 8.D.4) is also a `false` stub; B4 fills both in and makes `FoulingController` skip locked pairs.
- **5.D.5:** a new grapple sets the speed of each of its ships at WF=L to 0 (in irons), logged as `in_irons` on the GRAPPLE event; a collision at WF=L now also stops the ship (`MovementResolver.apply_results`), which closes the collision half of the `feature_diff.md` row.
- **Group drift (8.A.6):** the drift group is the connected component over `linked_ids()`; one d10 by the member with the highest Drifting number; no partial drift for a linked ship; a member held by a blocked member logs `blocked: "partner"` with `link` `"grappled"` or `"group"` (absent = fouled). As before, a blocked group rolls no fouling (existing behaviour; 8.A.6's "check for fouling" is not done for groups).
- **Other readers:** `FireController._attached_ids` (8.E.4 spread, 8.E.11 debris) and `MarineFireResolver.linked` read `linked_ids()`; `CrewRules.marines_held_back` holds the marines back while grappled (new reason "grappled"); `MovementResolver._get_plotted_steps` ignores a linked ship's plot; StubAI skips `SHIP_GRAPPLED` quietly.
- **AI:** `StubAI.grapple_orders(players)` / `ungrapple_orders(players)` as §3.6, with the boarding rule replaced, until B4, by the grappling rule itself: keep a grapple to an enemy it would grapple (struck, or crew BCF ≤ ⅔ of its own), cut every other (friends included). `crew_strength(ship)` = boxes × BCF at the current CQ.
- **View:** `MaintenanceOrdersPanel` (toggle rows "☐ Lively: grapple Topaze — needs 3 or less, 40 %", Done) in the context panel; `GrappleLines` draws hemp lines with grapnels between every touching hex pair of a grappled pair, unshaded and over the hulls; the planning card shows a GRAPPLED badge with Movement disabled, the status panel "Cannot move (grappled)" and "Grappled to Topaze: cannot move; the grapples can be cut in maintenance (8.C)". `test_server_authority.gd` forbids `GrapplingController` mutators and grapple field writes in view code.
- **Log:** GRAPPLE `{roll, modifiers, modifier, total, needed, success, in_irons?}` "HMS Lively throws grapples at Topaze — d10 2, crew +1, target did not move −1 → 2 ≤ 2: grappled" / "… → 6 > 2: they miss"; UNGRAPPLE `{…, attempt}` "Topaze fails to cut the grapples to HMS Lively — d10 4 → 4 > 2 (try 1)".

**B4 as built (2026-11-15).**
- **Pieces.** `BoardingRules` (`scripts/server/boarding_rules.gd`, pure statics: `task_error`, `target_error`, `boardable_error`, `normalize_manual`, `auto_assign` = rule A2b, `with_order`, `toggle_away`, `crew_loss_cause` = 10.D.7, `form_prize_sections`), `BoardingTaskHandler` (`boarding_task_handler.gd`, one instance per code so each task copies its own `marines_available`: true for FB/BR/BD, false for BA), `BoardingController` (`boarding_controller.gd`, `game_state.boarding_controller`), `BoardingAction` (`scripts/state/boarding_state.gd`). `GameState` gains `boarding_actions`, `boarding_seq`, `linked_at_plot`, `boarding_history`, `transfer_control`, `get_original_player_ships`. `ShipState` gains status `CAPTURED`, `controller_id`, `prize`, `detached_boxes` and the helpers `is_captured`, `is_targetable`, `can_be_boarded`, `original_player_id`, `original_morale_rating`, `boarding_task`, `is_readied`, `boarding_action_of`, `has_boarders`, `boarding_sections`, `marines_in_boarding`, `boarding_order`. `ShipStateController`: `set_controller`, `set_prize`, `set_crew`, `remove_crew_box_from`, `add_detached_box`. `DamageController`: `apply_boarding_losses`, `detach_prize_crew`.
- **Task model (how §2.4 #3 is done).** One section per task, params `{"section": s}` (+ `"target"` for BA), so a lost section never ends its partner's task. FB lasts one g-t and on completion adds a BR task (the section is readied); BR is open-ended and continues while plotted; BA lasts its g-t; BD one g-t. "Readied" = a live BR task. An engaged section's task is forced, carries `"action"` and `"enemy"`, and is open-ended; when the defender wins its tasks are released (an engaged FB then completes into BR, a defender's own BA becomes BR), which is what lets it counter-board (10.E.4). A readied section plotted to anything else stands down (BD), with the message "S1 stands down this turn and is free next turn (10.B.5)."
- **Orders.** `crew_orders.boarding` is a **standing** order ("ready" and "board:<id>" survive the plot clears; "stand_down" lapses after its g-t); the server turns "board" back to "ready" once the boarders go away and clears it on a repulse or a capture. `plot_crew` refuses a malformed order or a new "board:" target that may not be boarded. With no order, Automatic disbands readied sections (as §2.4 #6 says).
- **Picker.** Besides "Stand ready" and "Board ‹enemy›!" / "Counter-board ‹enemy›!" (with the odds, "24 v about 14 · you +0"), the picker offers "No boarders" (the default, so Automatic does not form boarders on every ship) and "Stand down" while any section is readied. The ship card's "Prepare boarders" / "Board" shortcut buttons and the map's boarders counter are not built; the planning card and status panel show a BOARDERS badge instead.
- **Standing down strip.** BD sections show as compact "M · BD" tags after the station's counters (the station is too small for a second row of counters).
- **Rules readings.** The 10.C.5b tie-break d6 is rolled at `declare` (it decides who defends, so before any gunfire die), on the TBCFs at that moment; boarding dice otherwise follow §3.3. New FB/BR defender sections join a live action before each round (10.E.1). The "all defending boxes gone" capture (10.E.2e) is checked after the round's losses, before the attacker's "all lost" test. A ship already in an action cannot be boarded by a second ship, nor board a second one (10.F, B6): those boarders stay ready. Boarding a prize is refused (10.G.5, B5). `can_be_boarded` = active or struck, not burning.
- **Capture.** The prize's tasks all end, including firefighting (the original crew fighting fires below, 10.H.3, is B5), its plots and pending MCs are dropped, its live crew is emptied into `prize.original_crew`. Prize crew = the minimum for its class from the surviving boarders, sailors (lowest sections) before marines, all of them when fewer (§8 Q3); all boarders when the ships parted, checked when RO ends (0.4 #6). The prize crew takes the captor's CQ and MR. `start_of_turn` is not needed: sections are free when their RO task ends.
- **Struck-before-damage.** `DamageController` treats a prize like a struck ship for morale checks, rigging/hull checks and striking (`struck_before := is_out_of_play()`).
- **Victory.** Points by original owner; a prize's value uses the original crew's MR. A side holding only prizes is defeated (seen live: capturing the AI's only ship ends the game on that turn). The game-over panel counts ships by original owner.
- **View.** Boarders station with its picker (`BoardingOrderPicker`), BA/BR toggle by clicking a readied token under a "Board" order (manual crew), counter tags FB/BR/BA/BD/"fighting", "RO n/m" for reorganizing boarders; `BoardingCard` (`scripts/ui/boarding_card.gd`) over the map during combat playback, closed at the next PLANNING or by its ×; prize flag (captor's colour over white) and a "PRIZE · reorganizing n/m" label on `ShipView` (the dashed ring was not built); hollow minimap icon; status lines "Prize of …", "S1 reorganizing aboard …". Developer request `dev_commands.grapple_ships(a, b, count_now)`.
- **AI.** `StubAI.boarding_order` as §3.6, but "stand down" is immediate when no enemy is linked or adjacent (no two-g-t wait). Ungrapple: keeps a grapple to an enemy it would board or grapple.
- **Tests.** `test/unit/test_boarding.gd` (§6 tests 8, 9, 12–45 except 46, 47, 52, the combat skip, plus capture through RO, parting while reorganizing, later defenders, multi-ship refusal, log text, the card, the station, standing orders). `test_server_authority.gd` forbids `BoardingController` mutators, capture mutators and writes to the capture and boarding fields in view code.

---

## 6. Tests (expected values from the rules and charts)

| # | Setup | Expected | Rule |
|---|---|---|---|
| 1 | Grappler used 3 MPs (turns counted) | Not eligible | 8.C.1 examples |
| 2 | Both used 2 MPs, adjacent, CQ B, d10 4 | 4 −2 = 2 ≤ 2: grappled | 8.C.1–2, chart |
| 3 | The same, fouled, target did not move, WS 4, d10 5 | 5 −2 −1 −1 +1 = 2: grappled | Grappling DRMs |
| 4 | Roller CQ F, or struck, or burning | No attempt offered; it can still be grappled | 8.C.3 |
| 5 | Both ships order a grapple on each other; the first succeeds | One grapple; the second roll is not made | 8.C.2 |
| 6 | Ungrapple, CQ B from a struck enemy (G), 1st attempt, d10 7 | 7 −2 −5 = 0 ≤ 2: free | 8.C.4, 8.C.6 |
| 7 | Ungrapple from a friendly ship, CQ D, d10 4 | 4 −2 = 2 ≤ 2: free | Unfouling DRMs |
| 8 | A pair locked in boarding | No ungrapple or unfoul roll between them | 8.C.5, 8.D.4 |
| 9 | Marines engaged, ungrappling from a third ship | +1 | 8.C.5 |
| 10 | A grappled ship plots movement | Refused, `SHIP_GRAPPLED` | 8.C.7 |
| 11 | Three ships grappled in a chain, one hex blocked | None drifts; one d10, by the least likely | 8.A.6 |
| 12 | FB by S2 while S1 has boxes and is not forced | Refused; with S1 in RO: allowed | 10.B.2, 4.B.1 |
| 13 | Marines FB with no sailor forming | Allowed | 10.B.2 |
| 14 | BA in the g-t of FB | Refused | 10.B.2 |
| 15 | BA by three readied sections | Refused (two) | 10.C.1 |
| 16 | BA by S4 | Refused | 10.C.1 |
| 17 | BA at CQ F; FB at CQ F | Refused; allowed | 10.A.2, 0.4 #3 |
| 18 | BA at a friendly linked ship, an unlinked enemy, or an enemy linked only since this g-t's movement | Refused | 10.A.2 |
| 19 | BA at a burning ship; FB while burning | Refused; refused | 10.A.2 |
| 20 | Fire breaks out with S1 and M at BR, not engaged | Both disbanded; free next g-t | 8.E.2 |
| 21 | Fire breaks out on a ship with engaged boarders | They fight on; another section is drafted to the fire | 8.E.2 exception |
| 22 | Defender's marines on RR 3 of 4, boarded | Replotted FB; RR progress lost | 10.C.3; Majestic g-t 20 |
| 23 | Defender's marines unplotted, boarded | They defend | SoP IV.A |
| 24 | Defender with no marines and no FB | Captured without a roll | 10.E.2b |
| 25 | Struck defender | Captured; no RO; prize crew this g-t | 10.A.3 |
| 26 | Both BA, TBCF 50 v 40 | The 50 attacks; the other's BA sections defend | 10.C.5b, 0.4 #2 |
| 27 | Odds 62:44; 44:62; 40:10; 10:45 | 0; −1; +4; −4 | 10.D.2, chart |
| 28 | Frigate (3) boards 74 (2); 74 boards frigate | −2 −1 = −3; −1 +1 = 0 | Other DRMs |
| 29 | Attacker's modified 7, roller's TBCF 62 | Defender loses 5 BCF | 10.D.4 |
| 30 | Heureux v Majestic, dice 9 and 9 | 62 v 44; DRMs −2 / −1; losses 5 and 4 BCF; attacker repulsed, 1 MC; all its FB/BR/BA disbanded | 10.D.1–5, §1.4 |
| 31 | Loss 6 BCF at CQ D; d6 2 then 5 | Sailor (5), then marine (7): two boxes | 10.D.4 example |
| 32 | Only sailors in the action | No Crew Loss d6 consumed | 10.D.4a |
| 33 | 10 % of TBCF 45 | 5 BCF | 0.4 #1 |
| 34 | Attacker 9 (d10 pending) and defender 11 | Only the defender's "repulsed, 2 MC" | 10.D.5 |
| 35 | Both modified 9, TBCF 50 v 40 | Only the 50 side's special; equal TBCF: neither | 10.D.5 |
| 36 | Attacker's modified 10, d10 2, defender MR 3 | Captured; d10 3: not | Table ("< MR") |
| 37 | Defender's modified 6, d10 3, attacker MR 3 | Not repulsed | Table |
| 38 | Engaged action, next g-t | Goes on with no new BA; sections locked; unfoul and ungrapple between the two refused | 10.E.1, 10.D.8 |
| 39 | After a repulse, the defender plots BA with M, S1, S2, S3 | Allowed; S4 refused | 10.E.4 |
| 40 | The parent strikes during the action | Its boarders surrender; the defender wins | 10.D.6 |
| 41 | Gunfire on a ship with only S1 at FB, Crew Loss d6 5 | A sailor ("Gunfire at Hull"); with the marines at FB too: a marine | 10.D.7 |
| 42 | Captor CQ B; CQ E | RO 3 g-t's; 6 | 10.G.4 |
| 43 | Class 2 prize, original sections 6-6-7-7:7; prize crew 8 sailors + 1 marine from a parent at 1-6-6-6:2 | Prize 0-0-1-7:1; parent 0-0-5-6:1; no MCs; parent's guns −6 | 10.G.7, 10.G.10 |
| 44 | Prize crew's CQ and MR | The captor's current ones | 10.G.8 |
| 45 | A prize plots movement; the old side fires on it | Refused; allowed | 10.H.1–2 |
| 46 | Class 2 prize, crew down to 1; original crew 1 box / 2 boxes; prize crew 3, original 20 | No / retaken at the next turn start as G6 / no (not below the minimum) | 10.H.4 |
| 47 | Captured ship at game end | 100 % to the captor's side; not counted as a ship in play for its holder | VI.B.2–3 |
| 48 | Marine fire, 7 boxes, grappled to the target, CQ D, d6 5 | 5 −1 = 4, column 7–8: 1 box | Marine Fire table |
| 49 | Marine fire, 2 boxes, d6 2; CQ G, 11 boxes, d6 1 | None; 1 +2 = 3: 1 box | Marine Fire table |
| 50 | Marines BA or engaged; marines on RR; marines at BR | Cannot fire; cannot; can | 7.G.1 |
| 51 | Marine fire and gunfire in one g-t, the firing marines lose a box to gunfire | The marine shot uses the boxes at the start of the g-t | 7.G.5 |
| 52 | Automatic, order "ready", then "board" next g-t | M and S1 at FB; then both BA | §2.4 rule A2b |
| 53 | Two ships board one defender with M, S1, S2 readied | M to the higher TBCF, S1 to the other, S2 to the first; two separate combats | 10.F.2, §3.4 |

---

## 7. `feature_diff.md` entries this spec will add

- §3, 8.D.3: a ship is fouled to one ship at most (0.4 #8).
- §3, 10.F: defenders are shared out among several boarding ships by a fixed rule, not by the player.
- §3, 10.G.6, if §8 Q3 is answered as recommended: prize crews come only from the boarders.
- §3, 10.H.2, if §8 Q2 is answered as recommended: prizes do not fire.
- §4: grappling and ungrappling are ordered in a prompt after drift (same outcome as the board game's sub-phase).

---

## 8. Open questions for the user

**Answered 2026-11-15: the user approved every ★ recommendation below.** Implement the ★ option in each case.

1. **How are grapple and ungrapple attempts ordered?** They are not plotted (4.A.1) and come after drift.
   - ★ **A prompt in the maintenance phase**, only when there is a choice (§4.3). You decide knowing this turn's combat, as at the table. Consequence: one more possible pause per turn, and a new server waiting step.
   - Standing orders set in planning ("grapple Hermione if able"): no pause, but decided before movement and combat; a small change from the book.
   - A block in the fire panel: no new pause when there is a shot, but before combat results, and still a pause when there is none.
2. **May a prize fire its guns?** 10.H.2 forbids moving and plotting tasks, and says prizes "were normally unable to sail or fight for hours"; gunfire is not a plotted task.
   - ★ **No.** Matches the stated intent, and a prize crew of 2–4 boxes would fire at −9 or not at all anyway. 1.G.8's BGN rule then matters only for scenario ships sailing under another navy.
   - Yes: unplotted prize-crew sections serve the guns with the captor's BGN column. More to build (B5) and a prize with a large prize crew becomes a second warship.
3. **Prize crew larger than the surviving boarders (10.G.6)?** The book lets the captor add boxes from sections that did not board, which must then reorganize as well.
   - ★ **Boarders only;** with fewer than the minimum, all of them go. One less prompt and no second reorganization; a knowing difference (`feature_diff.md`). Consequence: a costly boarding can leave a prize that the original crew retakes under 10.H.4.
   - As the book: the prompt also offers boxes from the marines and the lowest sailor section, which then get a forced RO.
4. **Do sections emptied to man a prize count as "crew sections destroyed" for victory points (VI.B.5d)?**
   - ★ **No.** The men are alive aboard the prize; the parent's detached boxes are tracked and left out of `points_lost`. Otherwise taking a prize can cost the captor 10–20 % of its own value.
   - Yes: simpler (boxes are boxes), and it makes large prize crews expensive.
5. **Victory points for a ship that is retaken** (10.H.4, or by boarding the prize back)?
   - ★ **By its state at the end:** back under its original side and in play, it scores by damage like any ship, counting the original crew's sections.
   - Once captured, always 100 %: simpler, but a recapture then changes nothing.
