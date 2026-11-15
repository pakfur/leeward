# Crew Tasks, Fire and Repairs — Design

**Status:** draft, awaiting answers to §4 and §7 · **Date:** 2026-11-15 · **Closes:** `feature_diff.md` §1 item 6, §2.1 rows "General crew-task plotting", "Fire and explosions", "Repairs"; §2.2 rows "Crew disorganized", "Fire roll after a minor explosion"; the CS-plotted DRM in §3 row 5.D.1–3.
**Compared against:** `e68aa2f`.
**Consumers:** the grappling-and-boarding spec (written in parallel) builds FB/BR/BA/BD/RO on the crew-task model in §2–3. §3.7 is the contract it may rely on.

**Sources.** Procedure: `docs/rules/close_action.md` 2.B.5, 4.A.3, 4.B, 5.D.2a, 5.F.6–9, 8.E, 8.F, 8.G, 9.A.2, 9.B.1c–d, 9.B.2, 9.C.4, 10.B.5, 10.G.4, Sequence of Play V.E–G, Majestic narrative (scenario book p.98). Numbers: ship log `ship-log-blank-1.png` (Crew Task Order Codes), `boarding-combat-chart.jpg` (Unfouling, Tacking, SK), `rb-p26-1.png` (blast table), `hull-critical-hits.jpg` (#4, #10, #12, as transcribed in the critical-hits spec). **OCR checked against PDF p.29 (Rules Book p.26):** 8.E.3 "DR **≤** the indicated number"; 8.E.4 "DR is **≤4** (± SK of the ship being spread to)"; 8.E.8 "2d6; a result of **≤2**"; 8.E.11 "DR **≥** its range" (the OCR's "=" is wrong); 8.F.3b "move **≤ 4** MPs" (the OCR's "< 4" is wrong). Fix these in `close_action.md` with phase 1.

---

## 1. Rules summary

### 1.1 Crew sections and tasks (4.A.3, 4.B)

- A ship has five crew sections (CS): sailor sections S1–S4 and the marine section M. Tasks are plotted in the Plot Phase (SoP II.B). **Any CS may do any task**, except boarding, which uses the lowest-numbered sailor sections first (4.B.1).
- **One task per CS per g-t** (4.B.2). A multi-g-t task must be done by the **same CS(s) every g-t**; if a CS stops plotting it, all progress is lost (4.A.3).
- A CS that is completely marked out loses its task and all progress (4.B.3). A CS hit by Crew Disorganized (hull #4) loses its task and must plot RO (hull chart; 5.F.9a for sail).
- **Unplotted sailor CSs fire the guns**; each sailor CS not available is −3 on gunfire (ship log, existing `sections_firing_modifier`). An unplotted M may use marine fire (4.B.4; not in Leeward). A ship moves normally with every CS tasked.
- Marines "not available" (plotted to a task) give **+1** on Unfouling-table rolls (chart DRM, used for fixing, firefighting and ungrappling; Majestic G-T 6).
- SK (9.A.2) changes task length when CQ changes mid-task: Majestic G-T 18 "extending RR and RO times by a g-t". Required g-t's are therefore recomputed from the **current** SK every g-t.

**Crew Task Order Codes (ship log).** "±SK" = base + SK mod (A −3 … G +3). "a / b" = CQ A–D / CQ E–G. 1 CS unless stated.

| Code | Task | CS | G-T's | Leeward |
|---|---|---|---|---|
| PS / MS / MS / FS / Furl | MS→PS, PS→MS (2 CS); FS→MS, MS/Furl→FS, FS→Furl | 2 / 1 | 2/3, 1/2 | exists (`SailController`), migrated |
| T | MA=0 turn (tacking); Tacking DRM +2 per CS short of 3, max +6 (5.D.2a errata) | up to 3 | that g-t | phase 2 |
| FF | Fight fire (one CS per fire, FF1, FF2…) | 1 | until out | phase 4 |
| RR / RH / RS | Repair rigging / hull / shrouds | 1 | 6±SK / 10±SK / 5±SK | phase 5 |
| RO | Reorganization (10.G.4: "5 + SK"; CQ A 2, CQ E 6) | per CS | 5±SK | phase 3 |
| FB / BR / BA / BD | Form / ready / away / disband boarders | 1 | 1 | boarding spec |
| PBA / PSA / PBS / PSS / PT / TX / A / AX / VO / VI / HS | Anchoring, springs, towing | 1 | 2/3, 6±SK, 2×(5±SK), 2×(6±SK), 5±SK, 1… | data only (Milestone 3) |

Checks of the table against examples: CQ A RR 3, RH 7 (8.F.4 ex.); CQ D dismasted RR 6 (8.F.6 ex.); CQ B RS 3 (Majestic G-T 14); CQ A RO 2, CQ E RO 6 (10.G.4). All match.

### 1.2 Fire and explosions (8.E, 9.B.1c–d)

| Topic | Rule | Behaviour |
|---|---|---|
| Causes | 8.E.1 | Hull crit #10 (d10 ≥ 6 ± SK ⇒ afire + MC) and #12 (afire + MC); spread from a grappled/fouled ship; flaming debris from an explosion; growth of an existing fire. |
| Must fight | 8.E.2 | Each fire is fought by exactly one CS plotted FF, even if another task must be aborted. **Exception:** CSs in boarding or RO do not stop. FB/BR CSs not yet engaged are disbanded (boarding spec). A ship may plot FF with no fire burning (HINT: head start). |
| Extinguish | 8.E.3, SoP V.F.1 | Maintenance: per fought fire, d10 + SK (+1 marines not available) **≤** Unfouling number: 1st g-t ≤2, 2nd ≤3, 3rd+ ≤4. Out ⇒ remove. Struck ships still fight fires (as CQ G, 9.C.4). |
| Damage | 8.E.8, SoP V.F.2 | Each fire still burning: 1R and 1H, **including the g-t it catches fire** (Majestic G-T 18). Normal box rules: emptied sections ⇒ RC/HC, guns dismounted, MCs, strike. |
| Growth | 8.E.5, SoP V.F.3 | A fire burning 5 g-t's (counting its first) creates another fire, and again every 5 g-t's. New fire ⇒ new CS must plot FF2, and an MC. |
| Spread | 8.E.4, 8.E.1b, SoP V.F.3 | Per ship grappled/fouled to a burning ship, per g-t: d10 ≤ 4 (± SK of the receiving ship) ⇒ one more fire there (even if already burning). SoP says "d6 1–3"; both are 50 % at SK 0 (Open q. 1). |
| Unfought | 8.E.6, 9.B.1d | A ship without enough CSs to fight every fire takes one MC per unfought fire every g-t. |
| Fear | 8.E.7, 9.B.1c | One MC every time a fire breaks out (each new fire). |
| Explode | 8.E.8, SoP V.F.4 | A burning ship with **no hull boxes left** strikes and rolls 2d6: **≤ 2** explodes; else roll again next g-t with a further −1 DRM per g-t (needs ≤2, ≤3, ≤4 …). |
| Blast | 8.E.10, `rb-p26-1.png` | Ships at range 1–2: MGN by exploding ship's class 1/2/3/4 = range 1: 40/35/30/25, range 2: 25/20/15/10; roll on the GRT **firing high** side, no modifiers. |
| Debris | 8.E.11 | Every ship within 6 hexes rolls d6: afire if **DR ≥ range**, a 1 never; ships grappled/fouled to it always catch fire. |
| Removal | 8.G.1f | Exploded ships leave the board. Leeward keeps the wreck as an obstruction (critical-hits spec Q2; unchanged). |

### 1.3 Repairs (8.F, 8.G.1b, 9.B.2)

- Types: rigging box (RR), hull box (RH), shrouds severed (RS, removes one `shrouds_severed` effect) (8.F.1–2).
- May begin only the g-t **after** a box of that type was marked out, or a shrouds-severed crit was received (8.F.3). RR only at FS, Furled or dismasted (8.F.3a). RH only if the ship moves **≤ 4 MPs** that g-t (8.F.3b).
- One CS per damage type per g-t; different types at once are fine (8.F.4). Continuous plotting by the same CS; breaking it, or being unable to plot because of 8.F.3, loses the progress.
- Completion (8.F.5): one box is added to the **section currently taking damage**; if that section is full, to the next-lowest-numbered section. Repairs are recorded in Reconciliation (8.G.1b). A restored section lost again gives no new Rigging/Hull Check and no MC (8.F.5, 9.B.2).
- A dismasted ship that takes a rigging hit loses all RR progress (8.F.6).
- RS needs 1 CS for 5±SK g-t's (rigging chart #9, ship log).

---

## 2. Data model

### 2.1 `data/rules/crew_tasks.json` (new; transcribed from the ship log)

```json
{
  "_doc": "Crew Task Order Codes (ship log). turns: {sk_base: n} = n + SK mod (min 1); {ad: a, eg: b} by CQ; {fixed: n}; {until: 'out'|'turn'}. sections = CSs required (min..max).",
  "SAIL_MAJOR": {"name": "Alter sail MS<->PS", "sections": [2, 2], "turns": {"ad": 2, "eg": 3}},
  "SAIL_MINOR": {"name": "Alter sail FS<->MS, FS<->Furl", "sections": [1, 1], "turns": {"ad": 1, "eg": 2}},
  "T":  {"name": "Tacking", "sections": [1, 3], "turns": {"until": "turn"}},
  "FF": {"name": "Fight fire", "sections": [1, 1], "turns": {"until": "out"}},
  "RR": {"name": "Repair rigging", "sections": [1, 1], "turns": {"sk_base": 6}},
  "RH": {"name": "Repair hull", "sections": [1, 1], "turns": {"sk_base": 10}},
  "RS": {"name": "Repair shrouds", "sections": [1, 1], "turns": {"sk_base": 5}},
  "RO": {"name": "Reorganize", "sections": [1, 1], "turns": {"sk_base": 5}, "forced": true},
  "FB": {"name": "Form boarders", "sections": [1, 1], "turns": {"fixed": 1}, "implemented": false}
}
```
(plus BR, BA, BD, PBA, PSA, PBS, PSS, PT, TX, A, AX, VO, VI, HS with `"implemented": false`). `data/rules/fire_table.json`: `{"extinguish": "unfouling", "spread_max": 4, "growth_turns": 5, "explode_max": 2, "explode_drm_per_turn": -1, "blast_mgn": {"1": [40, 25], "2": [35, 20], "3": [30, 15], "4": [25, 10]}, "debris_radius": 6, "debris_never": 1}`. `CombatTables` accessors: `crew_task(code)`, `task_turns(code, crew_quality) -> int`, `blast_mgn(class, range)`, `fire_rule(name)`. Extend `validate_combat.py` (codes known, sections 1–3, turns shape).

### 2.2 `ShipState` (mutated only through `ShipStateController`)

```
const MARINES := 4                        # section index: 0-3 = S1-S4, 4 = M
@export var crew_tasks: Array[Dictionary] = []
# each in-progress task: {"seq": int, "code": String, "sections": Array[int],
#   "done": int (g-t's completed), "started_turn": int, "params": Dictionary}
#   params: SAIL {"target": "MS"}; FF {"fire": fire_seq}; T {}; RO {"reason": "crew_disorganized"}
@export var task_seq: int = 0
@export var fire_list: Array[Dictionary] = []
# each fire: {"seq": int, "started_turn": int, "cause": "crit"|"spread"|"growth"|"debris",
#             "fought_turns": int (consecutive g-t's fought by the same CS)}
@export var explosion_checks: int = 0     # 8.E.8: times rolled so far (the -1 DRM per extra g-t)
@export var checked_sections: Dictionary = {"rigging": [false, false, false, false],
                                            "hull": [false, false, false, false]}  # 8.F.5
```
- `plotted_actions["crew_assignments"]` (already declared, unused) becomes the per-turn plot: `{section: {"code": String, "task": seq or -1, "params": {}}}`. `plotted_actions["sail_change"]` and `"repairs"` are folded into it.
- **Sail change migration:** `sail_change` storage moves into `crew_tasks` (code `SAIL_MAJOR`/`SAIL_MINOR`, `params.target`, `done`). Keep a read-only `sail_change()` helper returning the old dict shape so views and `PlanningSailUi` keep working until phase 2 replaces them; `deserialize` converts an old `sail_change` field.
- `fires: int` becomes `fire_count()` (derived from `fire_list`). `CriticalHitController.explosion_modifier` and `add_fire` move to the new storage.
- Helpers (read-only): `section_boxes(i)`, `section_alive(i)`, `task_of(i)`, `free_sections()`, `sections_able_to_fire()` (sailor sections with boxes and no task — replaces the sail-only version), `marines_available()`, `unfought_fires()`, `is_burning()`, `repairable(code)` (8.F.3 checks, minus movement), `task_turns_left(task)`.
- `ShipStateController`: `set_crew_assignments`, `start_task`, `update_task`, `end_task`, `add_fire(ship_id, cause) -> seq`, `update_fire`, `remove_fire`, `set_explosion_checks`, `repair_box(ship_id, kind) -> section`, `mark_section_checked(kind, section)`. All with the `is_server` guard; all serialized so state-history snapshots capture them.

---

## 3. Server design

### 3.1 `CrewTaskController` (new, `scripts/server/crew_task_controller.gd`, `game_state.crew_task_controller`)

Generic engine, task rules in a small handler per code (`SailController` becomes the SAIL handler; new `FireController` owns FF; `RepairController` owns RR/RH/RS; the boarding spec adds its own).

```
legal_tasks(ship_id, section) -> Array[{code, params, label, reason}]   # for UI and AI
plot_assignments(player_id, ship_id, assignments) -> String              # "" or refusal
default_assignments(ship_id) -> Dictionary                               # §4 Q2
begin_turn_tasks(phase)        # start of MOVEMENT_RESOLUTION: plots -> crew_tasks (replaces begin_plotted_changes)
after_movement(phase)          # RH movement check (> 4 MPs: progress lost)
advance_tasks(phase)           # Reconciliation: count g-t's, complete/cancel (replaces advance_changes)
cancel_section(ship_id, section, reason, phase)   # CS eliminated / disorganized / struck
force_task(ship_id, section, code, params, phase) # RO (crit, boarding victory); not plottable away
```
Handler interface: `can_plot(ship, sections, params) -> String`, `turns_required(ship, task) -> int` (recomputed every g-t, so SK changes apply), `on_start`, `on_complete`, `cancel_reason(ship, task) -> String`, `interruptible_by_fire: bool`, `blocks_guns: bool` (true for all).

**Plot validation (server):** one task per CS; CS has boxes; not in a forced task (RO, engaged boarding); section count within the code's range; continuing task must keep the same sections; per-type limits (one RR, one RH, one RS per ship; FF count ≤ fires + voluntary); every fire must have an FF CS when any non-exempt CS exists (8.E.2); struck ships may only plot FF; destroyed ships nothing. Plots that drop an in-progress task end it with "abandoned" at `begin_turn_tasks`.

### 3.2 Turn phases (Leeward ↔ SoP)

| Leeward phase | SoP step | Work |
|---|---|---|
| PLANNING | II.B | AI `assign_crew`; player plots; validation. Required FF filled by default. |
| MOVEMENT_RESOLUTION start | III.B ("men in rigging") | `begin_turn_tasks`. Tacking roll reads T sections (5.D.2a). |
| MOVEMENT_RESOLUTION end | — | `after_movement`: RH cancelled if MPs used > 4. |
| COMBAT_RESOLUTION | IV.B | Crew loss ⇒ `cancel_section` for emptied CSs (4.B.3). Hull #4 ⇒ `force_task(RO)`. Hull #10/#12 ⇒ `add_fire` + MC. Dismasted ship hit in rigging ⇒ RR progress reset (8.F.6). |
| DRIFT_CALCULATION | V.A | unchanged |
| STATUS_ADJUSTMENT | V.E | `fouling_controller.resolve_unfouling` → `critical_hit_controller.resolve_fixes` (now with +1 marines not available) |
| STATUS_ADJUSTMENT | V.F | `fire_controller.resolve(phase)`: 1 firefight, 2 damage, 3 growth then spread, 4 explode (+ blast, debris) |
| STATUS_ADJUSTMENT | V.G.1, .3, .6 | `crew_task_controller.advance_tasks`: repairs recorded, RO completed, sail changes completed (status update, 5.F.8) |
| MORALE_CHECK | V.G.4 | unchanged; resolves the fire MCs noted above |

### 3.3 Dice order (STATUS_ADJUSTMENT, after crit fixes)

Ships in ascending `ship_id`; within a ship, fires by `seq`.
1. **Firefight:** per fought fire, d10. Success: `d10 + sk + (1 if marines not available) <= unfouling_success_max(fought_turns + 1)`.
2. **Damage:** no dice except the Crew-Loss-free box removal and any RC/HC d6s it queues (drained per ship, FIFO, as in the crit controller).
3. **Growth** (no dice: age = turn − started_turn + 1; a multiple of 5 ⇒ new fire, cause growth, MC). **Spread:** per fouled/grappled pair with a burning partner, receiving ship's d10 (once per partner per g-t). New fire ⇒ MC.
4. **Explode:** per burning ship with 0 hull boxes, 2d6; explodes if `2d6 + (-1 × explosion_checks) <= 2` — i.e. needs ≤ 2 + previous checks. On explosion: `damage_controller.destroy(…, "exploded")`, then blast per ship within 2 hexes (range by `fire_geometry.range_between`, ascending ship_id): d6, FGN = MGN + d6, `gunfire_result(fgn, "high", column of target's sail state)`, applied with `apply_hits(cause "blast")`; then debris per ship within 6 hexes: d6. Debris and spread fires taken this step **do** burn in the next g-t's damage step only (they arrive after step 2; Open q. 4).
5. Unfought fires (no FF CS this g-t because the ship lacked CSs): one MC each (8.E.6), noted with trigger `unfought_fire_<turn>_<seq>`.

Fire MCs use unique triggers (`fire_<seq>`) so `morale_triggers_used` never suppresses them.

### 3.4 Repairs (`RepairController`, in `advance_tasks`)

`done += 1`; if `done >= task_turns(code, cq)`: RR/RH ⇒ `repair_box(kind)`: section = lowest index with boxes; if it is full, the section below it (index − 1); if none has boxes, the last section (Open q. 6). RS ⇒ remove the oldest `shrouds_severed` effect. Log `REPAIR`; the task ends (the player re-plots to repair another box; Open q. 7). `DamageController._queue_check` skips sections with `checked_sections[kind][i]` set, and sets it when queueing. Guns dismounted from a lost hull section are not restored (8.F.5 restores only boxes).

### 3.5 Events (`PhaseEvents.Type` additions) and log text

| Type | Data | Example text |
|---|---|---|
| `CREW_TASK` | `{section, code, params, state: started/progress/completed/abandoned/cancelled, done, needed, reason}` | "Vengeance: S3 begins repairing rigging (1 of 4)" · "S4's shroud repair cancelled — crew disorganized" |
| `FIRE_STARTED` (exists, extended) | `{fires, cause, roll, needed, result_id}` | "Vengeance catches fire from Fougueux (roll 2 ≤ 4)" · "A second fire breaks out aboard Vengeance" |
| `FIRE_FOUGHT` | `{fire, section, roll, modifier, needed, attempt, success}` | "Vengeance's S2 puts out the fire (3 −2 = 1 ≤ 3)" · "fails to master the fire (8 −2 = 6 > 2)" |
| `FIRE_UNFOUGHT` | `{fire}` | "Vengeance has no crew to fight a fire — morale check" |
| `EXPLOSION_CHECK` | `{roll, modifier, needed, explodes}` | "Burning hulk Vengeance: explosion roll 5 > 3" |
| `BLAST` | `{source, range, mgn, d6, fgn}` + `DAMAGE` | "Blast from Vengeance hits Superb (range 1, 35 + 4)" |
| `REPAIR` | `{kind, section}` | "Vengeance repairs a rigging box (section 2)" · "…clears severed shrouds" |

Fire box losses keep using `DAMAGE` with `cause: "fire"`. An explosion is the existing `DESTROYED` with `reason: "exploded"`.

### 3.6 AI (`StubAI.assign_crew`, called after `plot_all_ai_ships` movement)

Order: (1) forced tasks stay; (2) one FF per fire, preferring M, then S4…S1 (highest sailor sections are the last to lose boxes); (3) continue every in-progress task; (4) T: 3 CSs when the plot holds an MA=0 turn and no enemy can be fired on this turn, else 1; (5) RS if shrouds severed; (6) RR when at FS/Furled/dismasted with rigging damage; RH when the plotted MPs ≤ 4 and hull is damaged; (7) leave at least two sailor sections on the guns when an enemy is within 15 hexes (repairs use M first). Struck AI ships auto-plot FF only. Deterministic, no dice.

### 3.7 Contract for the boarding spec

- Section indices 0–4 (`ShipState.MARINES`), `crew_tasks`, `crew_assignments` shape, `CrewTaskController.register_handler(code, handler)`.
- Handler flags available: `forced` (cannot be re-plotted away), `interruptible_by_fire` (false for RO and engaged boarding, per 8.E.2), `section_order: "lowest_sailor_first"` (4.B.1), `exempt_from_fire_duty`.
- Hook `on_fire_breaks_out(ship_id)` lets the boarding handler disband FB/BR not yet engaged (8.E.2, 10.B.5).
- `force_task(…"RO"…)` and `RO` completion are implemented here (phase 3); boarding victory (10.G.2) calls `force_task`.
- `is_burning()` for 8.C.3 (burning ships cannot grapple); `marines_available()` for its +1 DRMs.

---

## 4. UX design — questions for the user

**Q-UX1. Where the player assigns crew in PLANNING.**
- **A. Crew panel, one row per section** (S1 S2 S3 S4 M): boxes left, current task with progress ("RR 2/4"), a dropdown of legal tasks. Mirrors the ship log; multi-CS tasks (MS↔PS, T) ask for the second/third section.
- **B. Task panel** (extends today's sail row): buttons per task (Sail, Fight fire, Repair rigging/hull/shrouds, Tacking crew) that pick sections automatically, plus a strip of five section chips showing who does what; clicking a chip reassigns that section.
- **C. Ship-log grid** (turns × sections) like the paper log.
- **Recommendation: B.** It keeps the sail flow players know, makes the common case one click, and the chip strip gives per-section control the boarding spec needs. A is the fallback if B gets crowded.

**Q-UX2. Defaults when the player assigns nothing.**
- **A.** In-progress tasks continue; each fire gets an FF section automatically; tacking gets 3 sections when an MA=0 turn is plotted; every other section is idle (on the guns).
- **B.** Nothing carries over; unassigned in-progress tasks are lost (paper rules, strict).
- **C.** A per-ship "crew orders: auto" toggle that uses the AI heuristic (§3.6).
- **Recommendation: A**, with C as a later addition. B silently destroys repair progress.

**Q-UX3. Mandatory firefighting.** When a fire burns and the player removes or never sets FF: **A.** the server fills it on submit, taking the lowest-priority section (idle, then repairs), and says so; **B.** submit is refused with a reason. **Recommendation: A** (B blocks the turn on a rule the player cannot break anyway).

**Q-UX4. Tacking crew.** **A.** The tacking note in the planning panel gains "Crew: 0/1/2/3" with the chance for each (it already shows the chance); **B.** always 3, no control. **Recommendation: A**, default 3 (today's behaviour).

**Q-UX5. Showing fire and repairs.**
- Status panel: one line per fire ("Fire 2 — 3rd turn, S2 fighting, out on ≤ 4 with −2 SK") and per task ("S3 repairing rigging, 2 of 4 turns").
- Ship list: an "AFIRE" badge next to the existing status badges.
- Map: **A.** flame and smoke particles on burning ships, an explosion effect and the existing wreck; **B.** none.
- **Recommendation:** all three text items, and map option A (fire is the most visible event at sea; exploding needs a cue).

**Q-UX6. Gun cost preview.** Show live "Guns: 2 of 4 sailor sections (−6)" in the crew panel while assigning? **Recommendation: yes** — the trade-off between repairs and guns is the decision being made.

**Q-UX7. Log detail.** Show every firefighting roll (pass and fail) and repair progress each turn, or only outcomes (fire out, repair complete, task lost)? **Recommendation:** rolls yes (traceable, as for crits), per-turn repair progress no.

---

## 5. What each phase un-defers

| Phase | Un-defers (`feature_diff.md`) |
|---|---|
| 1 Crew-task model | §2.1 "General crew-task plotting" → Partly fixed (model, sail migrated, any CS may alter sail) |
| 2 Crew UI + T | §3 5.D.1–3 tacking "CS-plotted DRM" → Fixed |
| 3 RO + crew disorganized | §2.2 "Crew disorganized (hull #4)" → Fixed; §2.1 crit row "reorganize sail-change cancellation (5.F.9a)" → Fixed |
| 4 Fire and explosions | §2.2 "Fire roll after a minor explosion (hull #10)" → Fixed; §2.1 "Fire and explosions" (incl. hull #12 blast) → Fixed; §2.2 "Struck ships count as CQ G" → Partly fixed (firefighting) |
| 5 Repairs | §2.1 "Repairs" → Fixed; shrouds severed repair (rigging #9) → Fixed; §1 item 6 → Fixed |
| — | Signal halyards cut stays deferred (needs signalling, ch. 11) |

---

## 6. Implementation plan

Each phase: GUT tests with `ScriptedDice` (d10 = 0–9), `make test`, both validators, `feature_diff.md` rows per §5. Final phase: CLAUDE.md "Not implemented", `scv-reviewer`.

1. **Model.** `crew_tasks.json`, `fire_table.json`, accessors, validator; `ShipState` fields/helpers/serialization; `CrewTaskController` engine; SAIL handler (migrate `SailController` storage, `begin_plotted_changes` → `begin_turn_tasks`, `advance_changes` → `advance_tasks`); `sections_able_to_fire` from tasks; `plot_assignments` server API; `default_assignments`. Existing sail tests keep passing (section choice now M, S4…S1 by default — Open q. 3). Fix the five OCR errors in `close_action.md`.
2. **UI + T.** Crew panel per Q-UX1/2/4/6; T handler; tacking DRM +2 per CS short of 3 (max +6) in `movement_resolver._calculate_tacking_drm` and the planning chance.
3. **RO.** RO handler (forced, 5±SK, min 1); hull #4 assigns RO to the highest-numbered sailor section not already disorganized, cancels its task (sail: 5.F.9a reason "crew disorganized"); `crew_disorganized` effect replaced by the RO task.
4. **Fire.** `FireController`; hull #10 roll; #12 via `add_fire`; FF handler; damage, growth, spread, unfought MCs, explosion check, blast, debris; hull #12 explosion also blasts and scatters debris; +1 marines-not-available on `resolve_fixes`; map effects per Q-UX5.
5. **Repairs.** RR/RH/RS handlers, 8.F.3 limits, RH movement check, box placement, `checked_sections`, 8.F.6 reset.
6. **AI and polish.** `StubAI.assign_crew`; status panel lines; log texts; docs; `scv-reviewer`.

### Test list (expected values from rules and charts)

| # | Setup | Expected | Rule |
|---|---|---|---|
| 1 | Plot S3 for two tasks | refused | 4.B.2 |
| 2 | RR on S3 turn 1, S4 plots RR turn 2 | S3's progress lost, S4 starts at 0 | 4.A.3, 8.F.4 |
| 3 | Two CSs plot RR | refused; RR + RH accepted | 8.F.4 |
| 4 | MS→PS ordered by M and S4, CQ B | 2 g-t's; then PS | ship log, 5.F.8 (Majestic g-t 4–5) |
| 5 | CQ E FS→MS | 2 g-t's | ship log 1/2 |
| 6 | S2 on a task | gunfire −3 for one sailor CS missing | ship log gunnery |
| 7 | M on a task, sailors idle | no gunfire penalty; fix roll +1 | chart DRM, Majestic g-t 6 |
| 8 | Crew loss empties S1 doing RR | task cancelled "crew lost" | 4.B.3 |
| 9 | MA=0 turn, 1 CS on T, CQ B | DRM −2 (SK) +4 = +2 | 5.D.2a (Majestic g-t 18) |
| 10 | No CS on T | +6, not +8 | 5.D.2a errata |
| 11 | Hull #4, CQ B, S4 on RS 2 of 3 | RS cancelled; S4 RO for 3 g-t's | hull #4, Majestic g-t 16 |
| 12 | CQ A RO / CQ E RO | 2 / 6 g-t's | 10.G.4 |
| 13 | CQ drops B→C mid-RR | needed rises 4 → 5 | 9.A.2, Majestic g-t 18 |
| 14 | Hull #10, CQ D, d10 6 / 5 | fire + MC / no fire | hull #10 |
| 15 | Fire starts in combat, no FF | 1R 1H that g-t; 1 MC (fear) only | 8.E.8, 8.E.7, Majestic g-t 18 |
| 16 | FF CQ B, attempt 1, d10 4 / 5 | out (4−2 = 2 ≤ 2) / burns | 8.E.3, Unfouling |
| 17 | FF 3rd g-t, CQ D, M busy, d10 3 | 3+1 = 4 ≤ 4 ⇒ out | 8.E.3, Unfouling 3+ |
| 18 | Fire started g-t 7, unfought till g-t 11 | second fire at g-t 11 step 3; MC; FF2 needed g-t 12 | 8.E.5 example |
| 19 | 2 fires, only 1 CS able | 1 MC per g-t for the unfought fire | 8.E.6, 9.B.1d |
| 20 | Fouled to burning ship, SK 0, d10 4 / 5 | catches fire / not | 8.E.4 |
| 21 | Burning, last hull box lost, 2d6 = 3; next g-t 3 | strikes, no explosion; explodes (≤ 3) | 8.E.8 example |
| 22 | Class 2 explodes, ship at range 1, d6 4 | FGN 39 on firing-high column | 8.E.10 |
| 23 | Debris range 5, d6 5 / 4; range 1 d6 1; fouled ship | fire / none / none / fire | 8.E.11 example |
| 24 | Struck burning ship | still rolls FF at CQ G (+3) | 8.E.3, 9.C.4 |
| 25 | RR plotted at MS | refused | 8.F.3a |
| 26 | RH plotted, ship uses 5 MPs | progress lost; 4 MPs keeps it | 8.F.3b (≤ 4, PDF) |
| 27 | Rigging damaged this g-t, RR plotted same g-t | impossible (plot precedes damage); allowed next g-t | 8.F.3 |
| 28 | CQ A RR / RH | 3 / 7 g-t's | 8.F.4 example |
| 29 | CQ B RS | 3 g-t's; shrouds severed removed; MA +1 | rigging #9, Majestic g-t 14 |
| 30 | Section 1 rigging lost, section 2 full, RR completes | box added to section 1; rigging level 4 | 8.F.5 example |
| 31 | That box lost again | no Rigging Check, no MC | 8.F.5, 9.B.2 |
| 32 | Dismasted CQ D, RR 5 of 6, rigging hit | progress reset to 0 | 8.F.6 example |
| 33 | Fire breaks out with M on RR and no free CS | M switches to FF (RR progress lost) | 8.E.2 |
| 34 | Fire with S3 in RO | S3 keeps RO; another CS must fight | 8.E.2 exception |
| 35 | Voluntary FF, fire breaks out in combat | rolled this g-t, attempt 1 | 8.E.2 HINT |

---

## 7. Open questions

1. **Spread roll:** 8.E.4 says d10 ≤ 4 (± SK of the receiving ship); the Sequence of Play says d6 1–3. Proposal: 8.E.4 (it is the detailed rule and carries SK).
2. **Sign of "± SK"** for spread (8.E.4) and the hull #10 fire roll (≥ 6 ± SK, deferred as critical-hits Q10). Elsewhere "± SK" is added to the die, which here would make good crews catch fire *more* easily from a spread. Proposal: better crews resist in both — spread on `d10 <= 4 + SK` (CQ A: ≤ 1), hull #10 fire on `d10 + SK >= 6`.
3. **Default sections** for automatically chosen tasks (sail today uses S4 downwards): proposal M, S4, S3, S2, S1 — high sections lose boxes last, and marines have no other use until marine fire exists.
4. **Fires that start in step 3–4** (growth, spread, debris): first damage now or next g-t? 8.E.8 says "including the g-t it catches fire", but the SoP puts damage (step 2) before them. Proposal: next g-t's damage step; the fear MC is immediate.
5. **Firefighting attempt column:** count consecutive g-t's the fire has been fought by its CS (resetting when the CS changes)? And does a CS that is itself the marines count as "marines not available" (+1)? Proposal: yes and yes.
6. **Repair placement** when no section has boxes (dismasted, or hull 0 on a struck ship): proposal: the last section (index 3), giving rigging level 1. Struck ships cannot repair at all.
7. **Repeated repairs:** after one box, does RR continue automatically for the next box (same CS, progress reset), or must it be re-plotted? Proposal: continues by default (Q-UX2 A) with progress reset.
8. **Blast damage details:** GRT column by the target's sail state; d6 added to the MGN like gunfire; no critical-hit check; crew losses use the gunfire Crew Loss column. Confirm.
9. **Hull #12 explosion** (2d10 < class, already implemented) — apply 8.E.10–11 blast and debris to it too? Proposal: yes.
10. **Burning wreck:** a destroyed (exploded) ship stays on the map as a wreck (crit-spec Q2), while 8.G.1f removes it. Keep the wreck; it cannot burn or spread fire. Confirm.
11. **Unfought-fire MC (8.E.6)** only when the ship truly lacks CSs, not when a fire broke out after plotting (Majestic g-t 18 takes no such MC). Confirm.
12. **Sail change with marines:** allowing M (and any sailor section) to alter sail is a behaviour change from today's sailor-only rule but matches 4.B.1 and Majestic. Confirm.
