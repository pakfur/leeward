# Crew Tasks, Fire and Repairs — Design

**Status:** ready for implementation; §9 answered (all ★ defaults approved) · **Date:** 2026-11-15 · **Closes:** `feature_diff.md` §1 item 6; §2.1 rows "General crew-task plotting", "Fire and explosions", "Repairs" and the "Still missing" part of "Critical hits"; §2.2 rows "Crew disorganized", "Fire roll after a minor explosion", "Signal halyards cut" (partly) and "Struck ships count as CQ G" (partly); the CS-plotted DRM in §3 row 5.D.1–3; the "marines not available" note in §3 row 8.D.1.
**Compared against:** `e719ea7`.
**UX source:** the approved crew overlay: `2026-11-15-crew-overlay-rules-mapping.md`, the HTML prototype `docs/superpowers/prototypes/crew-overlay.html` (v15) and the Godot prototype `prototypes/crew_overlay/` (`make proto-crew`). Where they disagree the Godot prototype wins on size and layout, the HTML on wording.
**Consumers:** `2026-11-15-boarding-design.md` builds FB/BR/BA/BD, marine fire and prize crews on the contract in §3.9.

**Sources.** Procedure: `docs/rules/close_action.md` 2.B.2–5, 4.A.3, 4.B, 5.D.1–2, 5.F.6–9, 7.D.9, 8.D.5, 8.E, 8.F, 8.G, 9.A.2, 9.B.1c–e, 9.B.2, 9.C.3–4, 10.A.2, 10.G.4, Sequence of Play II–V, Scenario Book VI.B.4, the Majestic narrative (pdf p.98). Numbers: ship log (`ship-log-blank-1.png`, Crew Task Order Codes), `boarding-combat-chart.jpg` (Unfouling, Tacking, Skill Factors), `rb-p26-1.png` (blast table), `hull-critical-hits.jpg` (#4, #10, #12), `rigging-critical-hits.jpg` (#3, #9), `gunfire-results-chart.jpg`.

**Checked against the PDF for this spec:**
- p.29 (Rules Book p.26): 8.E.3 "DR ≤ the indicated number"; 8.E.4 "≤4 (± SK of the ship being spread to)"; 8.E.8 "a result of ≤2"; 8.E.11 "DR ≥ its range"; 8.F.3b "move ≤ 4 MPs"; the blast table 40/35/30/25 and 25/20/15/10. `close_action.md` already reads this way.
- p.45 (Sequence of Play): V.F.4 "≤ 2 on 2d6". **Fixed in `close_action.md`** (OCR read "< 2").
- p.13: 5.D.2 "If the result is ≤ the number required". **Fixed** (OCR read "<").
- p.28: 8.C.1 "each used ≤ two MPs". **Fixed** (OCR read "< fvo"). Used by the boarding spec and by 8.F.3b's MP count.

---

## 0. Decisions (binding; they override anything below that disagrees)

### 0.1 Settled from the approved prototype

| Draft question | Decision | Settled by |
|---|---|---|
| Q-UX1 where crew is assigned | The crew overlay: tokens are crew sections, stations are task codes (§4). Not the row panel, task panel or log grid. | Prototype v15 |
| Q-UX2 defaults | Tasks in progress stay; every fire gets a section automatically (AUTO tag); everyone else serves the guns (sailors) or is at marine fire (M). A finished task returns its section to the default. Nothing else is auto-plotted unless Automatic is on (§3.3). | Mapping §4, prototype `defaults()`, `next_turn()` |
| Q-UX3 mandatory firefighting | The server fills an empty fire slot and marks it AUTO; submit is never refused. | Prototype `autoFire()`; mapping §2 |
| Q-UX4 tacking crew | The Braces (T) station, shown only when a turn at MA 0 is plotted, 0–3 sections, with the chance. | Mapping §2 |
| Q-UX5 showing fire and tasks | Fire stations on the upper deck under Marine fire; DAMAGE (N) list; progress tags on tokens; roster rows. Map effects are §9 Q6. | Prototype v15 |
| Q-UX6 gun cost preview | The Guns readout, live. | Prototype |
| Q-UX7 log detail | Every firefighting roll is logged (pass and fail); repair progress is not logged per turn, only start, completion and loss. | Draft recommendation, in line with the critical-hits spec ("every roll is traceable"); the prototype has no log |
| Q3 default sections | Fires: lowest-numbered free sailor section. Other automatic tasks: §3.3. | Mapping §4 and "later-phase item 2" |
| Q7 repeated repairs | One box per task. The section goes back to the default; it (or Automatic) plots the next box as a new task from 0. | Prototype `next_turn()`; Majestic g-t 11–15 (a new RR each time) |
| Mapping §2 open question (boarders and sections fighting a fire) | No skip. A burning ship cannot board or be boarded (10.A.2) and its unengaged boarders are disbanded (8.E.2), so the case arises only for a voluntary FF, and 4.B.2's example makes S1 form boarders even when another section could. Only eliminated and forced (RO, engaged) sections are passed over. The prototype's skip is dropped. | 10.A.2, 8.E.2, 4.B.2 example |

### 0.2 Settled from the rules and charts

| Draft question | Decision | Settled by |
|---|---|---|
| Q1 spread roll | d10 against 4 (8.E.4), not the Sequence of Play's "d6 1–3". Both are 50 % at SK 0; 8.E.4 is the full rule and carries SK. | 8.E.4, 8.E.1b |
| Q4 fires that start in sub-phase steps 3–4 | They do no damage that g-t: "Perform all steps in exactly the order shown" puts damage (2) before growth and spread (3) and explosions (4). Their fear MC is noted at once. Fires that start in the Combat Phase burn that g-t. | SoP note, V.F; Majestic g-t 18 |
| Q5 attempt column | The Unfouling column (1 / 2 / 3+) is the number of g-t's the *same section* has fought that fire; a new section starts at 1. | 4.A.3 (progress belongs to the CS); Majestic g-t 19–20 |
| Q5 marines as firefighters | "Marines not available +1" applies whenever the marine section is plotted to a non-boarding task, including when it is itself the section fighting the fire. | Chart DRM "(All Uses)"; Majestic g-t 6 |
| Q6 repair placement with no boxes left | Dismasted: the box goes to rigging section 4 (the section last emptied), giving rigging level 1. Hull cannot be at 0 without the ship having struck, and struck ships do not repair. | 8.F.5 ("next-lowest-numbered" = the section emptied last), 9.C.3 |
| Q8 blast | FGN = table number (the MGN) + d6, "firing high" side, column by the target's carried sail state, no other modifier. Crew boxes use the Crew Loss "All Other Causes" row. No critical-hit roll: 7.D.11 belongs to a shot, and a blast has no firer, side or rake. | 8.E.10, 7.D.9 |
| Q9 hull #12 explosion | It causes blast and debris too: the chart says "explodes and is removed from the map, after doing all appropriate blast damage, etc." | `hull-critical-hits.jpg` #12 |
| Q10 wreck | Unchanged from the critical-hits spec (Q2): the wreck stays as an obstruction, does not burn and spreads no fire. Already in `feature_diff.md`. | Earlier decision |
| Q11 unfought-fire MC | Only for a fire that existed when the ship plotted and that no section could be found for. A fire that breaks out after plotting gives only its fear MC. | 8.E.6 ("does not have enough CSs"); Majestic g-t 18 (two MCs: the fire and the hull section) |
| Q12 any section may alter sail | Yes, marines included. | 4.B.1; Majestic g-t 4–6 |
| Critical-hits Q6 crew disorganized | Implemented in phase 2 (§3.6). | Hull chart #4, 5.F.9a, Majestic g-t 16–17 |
| Critical-hits Q10 fire roll | Implemented in phase 4 (§3.5). The sign of "± SK" is §9 Q1. | Hull chart #10 |
| Critical-hits Q16 signal halyards | The effect entry and its 8.D.5 fix roll are implemented in phase 2. "No new messages" has nothing to block until signalling (ch. 11) exists; the `feature_diff.md` row becomes **Partly fixed**. | Rigging chart #3, 8.D.5 |

### 0.3 Rules interpretations made here (say so if you disagree)

1. **A sail change cannot be abandoned by choice** once begun: "must continue plotting until the sail change is completed, unless…" (5.F.9). The overlay locks those tokens. Only the fire draft (§3.4), section loss, Lines Jammed, dismasting or crew disorganized ends it. Other multi-g-t tasks may be abandoned (4.A.3), with the prototype's warning.
2. **A section plotted to any task does not serve the guns that g-t**, even if the task ends early (a failed tack, hull repair cancelled for moving more than 4 MPs). 4.B.4 speaks of sections "not plotted"; Majestic g-t 17 has the T sections silent.
3. **RO sections do not serve the guns** (Majestic g-t 17: "All the sailor sections are busy"), and RO time does not count the g-t of the hit: "S4 must now plot RO for the next 5 g-ts ± SK" (g-t 16).
4. **Voluntary FF** (8.E.2 HINT): a section standing by is attached to the first fire that breaks out that g-t and rolls in that g-t's firefighting step, in the "1" column. Standing-by time earns no column.
5. **A fire created in the Fire & Explosions sub-phase** counts its five g-t's from the next g-t, the first in which it burns. A fire that starts at the end of g-t 11 grows a new one at the end of g-t 16. (8.E.5 says "including the g-t on which it started"; for a Combat Phase fire that is the current g-t.)
6. **"Rigging hit" for 8.F.6** is any event that tells a ship already dismasted to mark out a rigging box: a gunfire or blast result with an *r*, a fire's 1R, a critical hit's rigging loss.
7. **A hull section lost a second time** dismounts no guns again: on the log the guns are marked with the section, once. It also gives no Hull Check or MC (8.F.5, 9.B.2).
8. **Struck ships** fight fires as CQ G (9.C.3–4), always with automatic allocation, and take no morale checks. A struck ship with no crew cannot fight.

---

## 1. Rules summary

### 1.1 Crew sections and tasks (4.A.3, 4.B)

- Five crew sections (CS): sailors S1–S4 and marines M. Tasks are plotted in the Plot Phase (SoP II.B). **Any CS may do any task** except boarding, where sailor sections go lowest-numbered first (4.B.1).
- **One task per CS per g-t** (4.B.2). A multi-g-t task must be done by the **same CS(s) every g-t**; if a CS stops plotting it, all progress is lost (4.A.3).
- A CS completely marked out loses its task and its progress (4.B.3).
- **Unplotted sailor CSs fire the guns**; each sailor CS not available is −3 (ship log, `sections_firing_modifier`: 4 → 0, 3 → −3, 2 → −6, 1 → −9, 0 → cannot fire). An unplotted M may use marine fire (4.B.4; boarding spec). A ship moves normally with every CS tasked.
- "Marines not available" is **+1** on every Unfouling-table roll (chart "DRMs (All Uses)"): unfouling, fixing, firefighting, ungrappling; and +1 on grappling. Not available = plotted to a non-boarding task, or fighting in a boarding action (8.C.5). Marines at FB/BR/BD are available (10.B.4–5).
- SK (9.A.2) changes task length when CQ changes mid-task (Majestic g-t 18: "extending RR and RO times by a g-t"; scenario rule "reorganizing until end of g-t 5, unless she fails any Morale checks"). G-t's needed are recomputed from the **current** CQ every g-t.

**Crew Task Order Codes (ship log, checked against the scan).** "±SK" = base + SK mod (A −3 … G +3). "a / b" = CQ A–D / CQ E–G. One CS unless stated.

| Code | Task | CS | G-t's | Phase |
|---|---|---|---|---|
| PS, MS | MS→PS, PS→MS | 2 | 2 / 3 | 1 (exists; migrated) |
| MS, FS, Furl | FS→MS, MS/Furl→FS, FS→Furl | 1 | 1 / 2 | 1 (exists; migrated) |
| T | Turn at MA 0. The table assumes 3 CS; +2 on the roll per CS short, at most +6 (5.D.2a erratum; the chart's "up to +8" is wrong) | 0–3 | that g-t | 2 |
| RO | Reorganization | 1 | 5±SK | 2 |
| FF | Fight fire, one CS per fire (FF1, FF2 …) | 1 | until out | 4 |
| RR / RH / RS | Repair rigging / hull / shrouds | 1 | 6±SK / 10±SK / 5±SK | 5 |
| FB / BR / BA / BD | Boarders | 1 | 1 | boarding spec |
| PBA, PSA, PBS, PSS, PT, TX, A, AX, VO, VI, HS | Anchoring, springs, towing | — | — | data only (Milestone 3) |

Checks against examples: CQ A RR 3, RH 7 (8.F.4); CQ D RR 6 (8.F.6); CQ B RS 3 (Majestic g-t 14); CQ A RO 2, CQ E RO 6 (10.G.4); CQ B RR 4 (Majestic g-t 8–11). All match.

### 1.2 Fire and explosions (8.E, 9.B.1c–d)

| Topic | Rule | Behaviour |
|---|---|---|
| Causes | 8.E.1 | Hull crit #10 (d10 ≥ 6 ± SK ⇒ afire + MC) and #12 (afire + MC); spread from a grappled or fouled burning ship; flaming debris; growth of an existing fire. |
| Must fight | 8.E.2 | Every fire is fought by exactly one CS plotted FF, even if another task must be aborted. CSs in RO or engaged in boarding do not stop. FB/BR sections not yet engaged are disbanded. A ship with no fire may plot FF (HINT). |
| Extinguish | 8.E.3, SoP V.F.1 | Per fought fire: d10 + SK + 1 (marines not available) **≤** Unfouling number, 1st g-t 2, 2nd 3, 3rd+ 4. Struck ships fight as CQ G. |
| Damage | 8.E.8, SoP V.F.2 | Each fire still burning: 1H and 1R, including the g-t it catches fire. Ordinary box rules follow (RC/HC, guns, MCs, strike). |
| Growth | 8.E.5, SoP V.F.3 | A fire burning five g-t's (counting its first) creates another, and again every five. New fire ⇒ MC and another FF section. |
| Spread | 8.E.4, SoP V.F.3 | Per ship grappled or fouled to a burning ship, per g-t: d10 against 4 ± SK of the receiving ship ⇒ one more fire there, even if it already burns. |
| Unfought | 8.E.6, 9.B.1d | One MC per g-t per fire the ship has no CS for. |
| Fear | 8.E.7, 9.B.1c | One MC each time a fire breaks out. The MC named by hull #10 and #12 is this MC, not a second one (Majestic g-t 18). |
| Explode | 8.E.8, SoP V.F.4 | A burning ship with no hull boxes strikes and rolls 2d6: **≤ 2** explodes; each later g-t the roll has a further −1 (≤ 3, ≤ 4 …). |
| Blast | 8.E.10 | Range 1 / 2 from the exploding ship, by its class 1/2/3/4: 40/35/30/25 and 25/20/15/10 as the MGN; GRT "firing high"; no modifiers. |
| Debris | 8.E.11 | Every ship within 6 hexes rolls d6: afire if **DR ≥ range**, a 1 never; ships grappled or fouled to it always catch fire. |
| Removal | 8.G.1f | Exploded ships leave the board. Leeward keeps the wreck (existing difference). |

### 1.3 Repairs (8.F, 9.B.2, Scenario Book VI.B.4)

- Rigging box (RR), hull box (RH), shrouds severed (RS) (8.F.1–2).
- A repair may begin only the g-t **after** a box of that type was marked out, or the shrouds were severed (8.F.3). RR only at FS, furled or dismasted (8.F.3a). RH only if the ship moves **≤ 4 MPs** that g-t (8.F.3b); MPs include turns (8.C.1 example 2 counts S1P2 as 5).
- One CS per damage type per g-t; different types at once are fine (8.F.4). Failing to plot continuously, or being unable to because of 8.F.3, cancels the progress.
- Completion (8.F.5): one box, added to the section currently taking damage; if that section is full, to the next-lowest-numbered one. A restored section lost again gives no Rigging Check, Hull Check or MC (9.B.2).
- A dismasted ship that suffers a rigging hit loses all RR progress (8.F.6).
- A section with a repaired box still standing yields no victory points (VI.B.4). `VictoryController.points_lost` already counts only sections at 0.

---

## 2. Data model

### 2.1 Rule data

`data/rules/crew_tasks.json` (new, from the ship log):

```json
{
  "_doc": "Crew Task Order Codes (ship log). sections = [min, max] CS. turns: {ad, eg} by CQ A-D / E-G; {sk_base: n} = max(1, n + SK mod); {fixed: n}; {until: 'out'|'turn'}.",
  "SAIL_MAJOR": {"name": "Alter sail MS<->PS", "sections": [2, 2], "turns": {"ad": 2, "eg": 3}},
  "SAIL_MINOR": {"name": "Alter sail FS<->MS, FS<->Furl", "sections": [1, 1], "turns": {"ad": 1, "eg": 2}},
  "T":  {"name": "Braces (tacking)", "sections": [1, 3], "turns": {"until": "turn"}, "drm_per_section_short": 2, "assumed_sections": 3},
  "RO": {"name": "Reorganize", "sections": [1, 1], "turns": {"sk_base": 5}},
  "FF": {"name": "Fight fire", "sections": [1, 1], "turns": {"until": "out"}},
  "RR": {"name": "Repair rigging", "sections": [1, 1], "turns": {"sk_base": 6}},
  "RH": {"name": "Repair hull", "sections": [1, 1], "turns": {"sk_base": 10}, "max_mp": 4},
  "RS": {"name": "Repair shrouds", "sections": [1, 1], "turns": {"sk_base": 5}}
}
```
The boarding spec adds FB, BR, BA, BD. Anchoring and towing codes are not transcribed until Milestone 3.

`data/rules/fire_table.json` (new): `{"spread_number": 4, "growth_turns": 5, "explode_max": 2, "blast_mgn": {"1": [40, 25], "2": [35, 20], "3": [30, 15], "4": [25, 10]}, "debris_radius": 6, "debris_never": 1}`. Extinguishing uses `unfouling_table.json`. `unfouling_table.json` gains `"marines_unavailable": 1`.

`CombatTables`: `crew_task(code) -> Dictionary`, `task_turns(code, crew_quality) -> int`, `task_sections(code) -> Array`, `blast_mgn(ship_class, range) -> int` (−1 beyond range 2), `fire_rule(name)`, `marines_unavailable_modifier()`. `validate_combat.py`: known codes, sections within 1–3, one turns shape per row, blast rows for classes 1–4 falling with class and range.

### 2.2 `ShipState` (mutated only through `ShipStateController`)

```
const MARINES := 4                        # section index: 0-3 = S1-S4, 4 = M
const SECTION_NAMES := ["S1", "S2", "S3", "S4", "M"]

@export var crew_auto: bool = true        # the Automatic crew setting (§3.3)
@export var crew_tasks: Array[Dictionary] = []
# each: {"seq": int, "code": String ("SAIL","T","RO","FF","RR","RH","RS", boarding codes),
#        "sections": Array[int], "done": int (g-t's completed), "started_turn": int,
#        "params": Dictionary, "forced": bool, "ended": String ("" or the reason; kept until
#        the g-t ends so the log and the guns rule can see it)}
#   params: SAIL {"target": "MS"}; FF {"fire": fire seq, or -1 standing by}; RO {"reason": ...}
@export var task_seq: int = 0
@export var plotted_sections: Array[int] = []   # sections plotted to a task this g-t (0.3 #2)
@export var fire_list: Array[Dictionary] = []
# each: {"seq": int, "created_turn": int (g-t it broke out), "started_turn": int (first g-t it burns:
#        created_turn for a Combat Phase fire, created_turn + 1 for one made in the Fire sub-phase),
#        "cause": "crit"|"spread"|"growth"|"debris"}
@export var fire_seq: int = 0
@export var explosion_checks: int = 0     # 8.E.8: rolls made so far
@export var checked_sections: Dictionary = {"rigging": [false, false, false, false],
                                            "hull": [false, false, false, false]}  # 8.F.5, 9.B.2
@export var mp_used_this_turn: int = 0    # executed steps, turns included (8.F.3b; 8.C.1 in the boarding spec)
```

- **Plot:** `plotted_actions["crew_assignments"]` (declared today, unused) = `{section:int -> {"code": String, "params": Dictionary}}`; a section that is absent is unplotted. `plotted_actions["crew_orders"]` = `{"sail_target": ""}` (the boarding spec adds keys). The keys `sail_change`, `repairs` and `boarding` are removed.
- **Sail migration:** the `sail_change` field goes; a sail change is a `crew_tasks` entry with code `SAIL`. `ShipState.sail_change_info() -> Dictionary` returns the old shape `{target, turns_left, sections}` (or `{}`) for the views and `PlanningSailUi`. `deserialize` converts an old `sail_change`.
- **Fire migration (phase 4):** `fires: int` goes; `fire_count()` = `fire_list.size()`. Until phase 4 `fires` stays and `is_burning()` reads it.
- **Read-only helpers:** `section_boxes(i)`, `section_alive(i)`, `task_of(i) -> Dictionary`, `tasks_with(code) -> Array`, `is_disorganized(i)` (a live RO task with `params.reason == "crew_disorganized"`), `sections_able_to_fire()` (sailor sections with boxes that are not in `plotted_sections`; replaces today's sail-only test), `marines_available()` (marines have boxes and are not in `plotted_sections`, or their code is one a handler reports as "available"), `is_burning()`, `fire_count()`, `tack_sections()` (size of the live T task, 0–3), `missing_boxes(kind)`.
- **`ShipStateController`** (all with the `is_server` guard): `set_crew_auto`, `set_crew_assignments`, `set_crew_orders`, `add_task`, `update_task`, `end_task`, `set_plotted_sections`, `add_fire(ship_id, cause, in_fire_subphase) -> seq`, `remove_fire`, `set_explosion_checks`, `repair_box(ship_id, kind) -> section`, `mark_section_checked(ship_id, kind, section)`, `set_mp_used`. `clear_turn_flags` clears `plotted_sections`, `mp_used_this_turn`, and tasks with `ended != ""`. Everything above is serialized, so state-history snapshots hold it.

### 2.3 Deck layouts (presentation only)

`data/ui/deck_layouts.json` (new; the rules engine never reads it). Coordinates are the prototypes' landscape deck units, 1000 × 360, stern at x = 0.

```json
{
  "ship_types": {"frigate_38": "frigate", "frigate_32": "frigate", "ship_of_line_74": "sol74"},
  "layouts": {
    "frigate": {"decks": [{"id": "upper", "name": "Upper deck", "guns": 4},
                          {"id": "gun", "name": "Gun deck", "guns": 19},
                          {"id": "orlop", "name": "Orlop", "guns": 0}], "gun_decks": ["gun"]},
    "sol74":   {"decks": [{"id": "upper", "name": "Upper deck", "guns": 6},
                          {"id": "gun_up", "name": "Upper gun deck", "guns": 14},
                          {"id": "gun_low", "name": "Lower gun deck", "guns": 14},
                          {"id": "orlop", "name": "Orlop", "guns": 0}], "gun_decks": ["gun_up", "gun_low"]}
  },
  "stations": {
    "guns":        {"decks": "gun_decks", "rect": [190, 118, 620, 124]},
    "marine_fire": {"decks": ["upper"], "rect": [78, 70, 170, 96]},
    "boarders":    {"decks": ["upper"], "rect": [272, 64, 168, 98]},
    "braces":      {"decks": ["upper"], "rect": [448, 64, 150, 98]},
    "sails":       {"decks": ["upper"], "rect": [606, 92, 210, 176]},
    "rs":          {"decks": ["upper"], "rect": [272, 196, 140, 96]},
    "rr":          {"decks": ["upper"], "rect": [420, 196, 160, 96]},
    "rh":          {"decks": ["orlop"], "rect": [330, 118, 300, 124]},
    "fire_zone":   {"decks": ["upper"], "rect": [78, 192, 170, 106]},
    "reorganizing": {"decks": ["upper"], "rect": [830, 120, 110, 120]}
  }
}
```
Both layouts use the same station rectangles, as in the prototypes; the 74 differs only in its second gun deck, where the Guns station is drawn again with the same tokens. The `guns` count per deck is the number of gun ports drawn a side, decoration only. The deck card's note ("19 eighteen-pounders a side") is built from the ship type's display-only `armament` block in `ships.json` where it names that deck, and is left out otherwise (`frigate_32` has none); the prototypes hard-code it. `reorganizing` is new here (§4.3).

---

## 3. Server design

### 3.1 Pieces

| Piece | File | Role |
|---|---|---|
| `CrewRules` | `scripts/server/crew_rules.gd` (pure statics, like `FireRules`) | Which stations exist, why a section cannot go to one, the fire draft, plot normalisation, the guns preview. Used by the server, the AI and the overlay, so displayed and enforced rules are the same code. |
| `CrewAuto` | `scripts/server/crew_auto.gd` (pure statics) | The Automatic allocation (§3.3). |
| `CrewTaskController` | `scripts/server/crew_task_controller.gd`, `game_state.crew_task_controller` | Stores plots, turns them into tasks, counts g-t's, completes and cancels. One small handler per code. |
| `SailController` | existing | Becomes the SAIL handler: `available_targets`, `change_cost` and `plot_sail_change` keep their signatures; `begin_plotted_changes` and `advance_changes` are folded into the engine; `cancel_change` calls `end_task`. |
| `FireController` | `scripts/server/fire_controller.gd`, `game_state.fire_controller` (phase 4) | Fires, the Fire & Explosions sub-phase, blast and debris; the FF handler. |
| `RepairController` | `scripts/server/repair_controller.gd` (phase 5) | The RR, RH and RS handlers. |

Handler interface: `can_plot(ship, sections, params, plan) -> String`, `turns_required(ship, task) -> int` (−1 = open-ended), `on_start`, `on_complete`, `cancel_reason(ship, task) -> String`, and flags `forced`, `abandonable` (false for SAIL and forced tasks), `fire_exempt` (RO, engaged boarding), `marines_available` (FB, BR, BD), `section_order` ("" or "lowest_sailor_first").

### 3.2 `CrewRules` and `CrewTaskController` API

```
# CrewRules (static; `plan` = {"assignments": {...}, "orders": {...}} being edited, `ctx` = CrewRules.context(game_state, ship))
context(game_state, ship) -> Dictionary        # {ma0_turn_plotted, plotted_mps, enemy_in_gun_range, enemy_adjacent, turn}
stations(ship, plan, ctx) -> Array[Dictionary]  # [{id, code, label, short, capacity, turns, accepts, note,
                                                #   disabled_reason, occupants, locked: [sections], fire: {seq, age} or {}}]
refusal(ship, plan, ctx, section, station_id) -> String      # "" = allowed
progress_warning(ship, plan, section, station_id) -> String  # "" or "S3 has 2 of 4 turns on rigging repair. Moving it loses them (4.A.3)."
assign(ship, plan, ctx, section, station_id) -> Dictionary   # the new plan
normalize(ship, plan, ctx) -> Dictionary        # {"assignments", "orders", "auto": [sections], "warnings": [String], "dropped": [...]}
default_plan(ship, ctx) -> Dictionary           # carry-over defaults (0.1 Q-UX2)
fire_draft(ship, assignments, fire_seq) -> int  # the section to send, or -1 (§3.4)
guns_preview(ship, plan) -> Dictionary          # {"sections": n, "modifier": int or null, "missing": [{"section", "why"}]}
summary(ship, plan) -> Array[Dictionary]        # the planning-panel chips, §4.8

# CrewTaskController
plot_crew(player_id, ship_id, plan) -> String   # "" or the refusal; stores normalize(plan)
set_auto(player_id, ship_id, on) -> String
current_plan(ship_id) -> Dictionary             # the stored plan, or default_plan
finalize_plots()                                # End Planning: normalize every ship against its final movement plot
begin_turn_tasks(phase)                         # start of MOVEMENT_RESOLUTION: plots -> crew_tasks, plotted_sections
after_movement(phase)                           # RH and the 4-MP limit
advance_tasks(phase)                            # Reconciliation: count, complete, drop
cancel_section(ship_id, section, reason, phase) # CS eliminated or disorganized
force_task(ship_id, sections, code, params, phase)   # RO; the boarding spec's FB and RO
reset_progress(ship_id, code, reason, phase)    # 8.F.6
register_handler(code, handler)
```

**`normalize`** is the one place a plan is made legal. In order: (1) drop sections that are eliminated; (2) restore locked sections (forced tasks; a sail change in progress); (3) if `crew_auto`, replace everything else with `CrewAuto.allocate`; (4) otherwise drop assignments that `refusal` rejects, with a warning each (T with no MA-0 turn in the movement plot, RR above FS, a second section on a one-section station); a sail change short of its sections is kept with a warning and simply does not start; (5) fill every fire that has no section, by `fire_draft`, marking the section `auto`; (6) for a struck ship keep only FF. It never refuses; `plot_crew` refuses only "not your ship", "not in planning", "ship is destroyed" and malformed input.

**Continuation.** A plot continues an in-progress task when the same sections carry the same code and the same identifying parameter (sail target; fire seq). Anything else ends the old task ("abandoned") and starts a new one at 0.

**`begin_turn_tasks`** replaces `sail_controller.begin_plotted_changes()` at the start of MOVEMENT_RESOLUTION: for each ship in id order it ends tasks that were not continued, starts new ones (`on_start`; a sail change that fails `available_targets` or Lines Jammed is logged as today), sets `plotted_sections` and clears the plot. SAIL logs `SAIL_CHANGE` exactly as now; other codes log `CREW_TASK`.

**`advance_tasks`** replaces `sail_controller.advance_changes()`: ships in id order, tasks in seq order. A task with a `cancel_reason` ends. Otherwise, if it was plotted this g-t, `done += 1`; when `done >= turns_required` (current CQ) it completes (`on_complete`) and ends. T ends every g-t. No dice.

### 3.3 The Automatic crew setting

**What it is.** `ShipState.crew_auto`. On: the server allocates the ship's crew with the fixed rules below, the same every turn. Off: the player places every section; only the fire draft still acts for them. The player still gives the ship's *orders* in both modes: movement, the sail change target, and (boarding spec) the boarding order.

**Scope: per ship**, with a per-game starting value. New games start every ship with Automatic **on**: today's game already picks the sail-change sections itself and assumes a full tacking crew, so "on" keeps current behaviour. A player turns it off on the ships they want to run by hand. AI ships are always on. (§9 Q2.)

**Rules (`CrewAuto.allocate(ship, orders, ctx) -> assignments`), applied in this order. A section taken by an earlier rule is not available to a later one.**

| # | Rule | Sections taken, in order |
|---|---|---|
| A0 | Locked tasks stay: RO, engaged boarders, a sail change in progress. | their own |
| A1 | **Fires**, lowest fire number first. | The section already fighting that fire, if it still has boxes; else the fire draft (§3.4). |
| A2 | **Tasks in progress** continue with the same sections while still legal. RR is dropped when the ship carries MS or PS; RH is dropped when the movement plot uses more than 4 MPs. | their own |
| A3 | **The ordered sail change** (`orders.sail_target`), 1 or 2 sections. | Worker order |
| A4 | **Tacking:** when the movement plot holds a turn at MA 0, as many of 3 sections as are free. | Worker order |
| A5 | **Repairs**, one section each, in the order RS, RR, RH, each only where §3.7 allows it. | The marines if they are free under the worker order; a sailor section only when no enemy ship in play is within 15 hexes at plot time. |
| A6 | Everyone else: sailors serve the guns, marines are at marine fire. | — |

- **Worker order:** M, then S4, S3, S2, S1. Marines first because they cost no gunfire; then the highest-numbered sailors because crew losses come off the lowest-numbered section first, so a high section is the least likely to be wiped out with its progress (4.B.3).
- **Marines held back:** M is skipped in the worker order while the ship has a fire, has a fixable critical effect (obscured broadside, braces cut, lines jammed, rudder jammed, signal halyards cut), is fouled or grappled, or has an enemy ship adjacent. Each of those is a roll or a use the marines would spoil (+1 "marines not available"; marine fire). A marine task already in progress still continues under A2.
- **Fire order** differs on purpose: the lowest-numbered free *sailor* section first (mapping §4), which also keeps the marines available for the firefighting roll.
- **Tie-breaks:** none are needed; every choice is a fixed list. There are no dice and no hidden inputs: the result depends only on the ship's state, its orders and its movement plot, all of which the overlay shows. The boarding spec inserts its rules between A2 and A3.
- **When it runs:** live, whenever the overlay or the planning panel needs the plan (`normalize`), and for good in `finalize_plots()` when planning ends, so it sees the final movement plot.

**The AI.** `StubAI.assign_crew()` runs at the end of `plot_all_ai_ships()`. It does not allocate sections: it sets the ship's orders (no sail changes today; boarding orders per the boarding spec) and leaves `crew_auto` on. The allocation is the same `CrewAuto` code the player gets, so there is one set of rules to test and to explain.

### 3.4 The fire draft (8.E.2)

`CrewRules.fire_draft` picks the section for a fire nobody fights. First match wins:

1. a section standing by (FF with no fire), lowest-numbered first;
2. the lowest-numbered sailor section that is unplotted;
3. the marines, if unplotted;
4. a section on a one-g-t task (T, BD), highest-numbered first;
5. a section on a multi-g-t task that is not `fire_exempt`: the task with the fewest g-t's done; on a tie RS, RR, RH, then SAIL; then the highest-numbered section. The task ends "called to the fire" (a two-section sail change ends for both).

Never: RO, engaged boarders, eliminated sections. If nothing is left the fire is unfought (§3.5 step 5). In manual mode the draft fills only empty fire slots; the player may put any legal section on a fire.

### 3.5 Fire (`FireController`, phase 4)

**Catching fire.** `start_fire(ship_id, cause, phase, source_id)`: `add_fire` (started_turn = this g-t in the Combat Phase, next g-t in the Fire & Explosions sub-phase), `FIRE_STARTED`, one MC with trigger `fire_<seq>` (unique, so `morale_triggers_used` never swallows it; none for a struck ship), `CrewRules`' standing-by section attached if one exists, and the handler hook `on_fire_breaks_out(ship_id)` (the boarding handler disbands unengaged boarders). Not for a destroyed ship.

- **Hull #10:** after the 1H and the guns, d10; afire per §9 Q1 (recommended: `d10 + SK ≥ 6`). The crit's MC is the fire's MC.
- **Hull #12:** `_afire_major_explosion` calls `start_fire` in place of `sc.add_fire` and its own MC note; `explosion_modifier` reads `fire_count()`. If the 2d10 roll explodes the ship, `fire_controller.explode(ship_id, phase)` runs before the wreck is made.

**The Fire & Explosions sub-phase** (`fire_controller.resolve(phase)`, in STATUS_ADJUSTMENT after the fix rolls). Dice order is the contract for `ScriptedDice`. Ships in ascending `ship_id`; within a ship, fires by `seq`.

1. **Firefighting.** Per fire with a live FF task: d10. Out when `d10 + sk + (1 if not marines_available()) <= unfouling_success_max(task.done + 1)`, with `sk` from CQ G for a struck ship. Out ⇒ `remove_fire`, the task ends. Not out ⇒ the task goes on (its `done` rises in `advance_tasks`). `FIRE_FOUGHT` either way.
2. **Damage.** Per fire still burning whose `started_turn <= turn`: `damage_controller.apply_hits(ship_id, 1, 1, 0, …, damage_cause "fire")`. Rigging and hull checks queued by it are drained per ship as usual (their d6s come here).
3. **Growth, then spread.** Growth, no dice: a fire with `(turn − started_turn + 1) % 5 == 0` starts a new fire (cause `growth`). Spread: for each burning ship in id order, for each ship fouled (later: grappled) to it in id order, one d10 by the receiving ship; afire per §9 Q1 (recommended: `d10 <= 4 + SK`), cause `spread`. Fires that existed at the start of the step are the ones that spread and grow; fires made in this step do neither this g-t.
4. **Explosions.** Per burning ship with no hull boxes, not destroyed: 2d6; explodes when `two_d6 <= 2 + explosion_checks`; otherwise `explosion_checks += 1`. `EXPLOSION_CHECK`. On an explosion, `explode()`.
5. **Unfought fires.** Per fire with `created_turn < turn` (it existed at plotting) and no FF task this g-t, on a ship that has not struck: one MC, trigger `unfought_<seq>_<turn>`, `FIRE_UNFOUGHT`.

**`explode(ship_id, phase)`:** note the ships fouled or grappled to it, then `damage_controller.destroy(ship_id, "exploded", phase)` (clears its fires and tasks). Then, other ships not destroyed, in ascending id: **blast** at range 1–2 (`fire_geometry.range_between`, closest hexes): d6, `fgn = blast_mgn(class, range) + d6`, `gunfire_result(fgn, "high", column of the target's carried sail state)`, slashed results rolled as for gunfire, applied with `apply_hits(…, crew_cause "other", damage_cause "blast")`; `BLAST`. Then **debris**, same ship order, range ≤ 6: ships that were fouled or grappled to it catch fire with no roll; others roll d6 and catch fire when `d6 != 1 and d6 >= range`. In the Combat Phase (hull #12) the critical-hit queue is on hold; damage and fires apply at once and are not seen by shots already computed.

### 3.6 Tacking crew, crew disorganized, marines, signal halyards (phase 2)

- **T.** `MovementResolver._calculate_tacking_drm` adds `2 * (3 − ship.tack_sections())`, so 0–6. `tacking_chance(ship_state, sections := -1)` takes the planned count for the overlay and the planning note. No dice change: the resolver's own RNG rolls as before.
- **Crew disorganized (hull #4).** After the sailor box (as today): the highest-numbered sailor section that has boxes and is not already disorganized is disorganized. `cancel_section(…, "crew disorganized")` ends its task (a sail change it shares ends for both sections, 5.F.9a), then `force_task(ship_id, [section], "RO", {"reason": "crew_disorganized"})`. RO is forced, not abandonable, `fire_exempt`, and needs `max(1, 5 + SK)` g-t's counted from the next g-t. With no such section only the box is lost. The `critical_effects` id `crew_disorganized` and the "not yet simulated" note go.
- **Marines not available.** `FoulingController._attempt` and `CriticalHitController.resolve_fixes` add `marines_unavailable_modifier()` when `not ship.marines_available()`; the events carry it in `modifier`.
- **Signal halyards cut (rigging #3).** Adds the effect `signal_halyards_cut` to `critical_effects` and to `FIXABLE_IDS`; a dismasted ship still rolls (chart). Status line: "Signal halyards cut: no new signals (fix roll in maintenance)".

### 3.7 Repairs (`RepairController`, phase 5)

| Code | `can_plot` | On completion |
|---|---|---|
| RR | A rigging box is missing at plot time; the ship carries FS or NS, or is dismasted; no other section on RR. | `repair_box("rigging")`, `REPAIR`. |
| RH | A hull box is missing; no other section on RH. (The 4-MP limit is checked after movement.) | `repair_box("hull")`, `REPAIR`. |
| RS | A `shrouds_severed` effect exists; no other section on RS. | Removes the oldest `shrouds_severed` effect, `REPAIR`. |

- "Missing at plot time" is 8.F.3's "the g-t after": plotting comes before any damage in a g-t.
- `after_movement`: a ship with `mp_used_this_turn > 4` loses its RH task ("moved more than 4").
- `repair_box(kind)`: the current section is the lowest-numbered one with boxes. If it is below its starting size, add the box there; if it is full, add it to the section before it; if no section has boxes, add it to section 4. Guns dismounted are not restored. A dismasted ship that regains a box stays furled (NS) and must alter sail to FS.
- `checked_sections`: `DamageController` sets the flag when it queues a check for a section, and for an emptied section whose flag is set it queues no check and (hull) dismounts no guns. Morale checks are already once per trigger.
- 8.F.6: `DamageController.apply_hits` and the crit controller's rigging losses call `reset_progress(ship_id, "RR", "rigging hit while dismasted")` when asked to mark rigging on a ship that was dismasted before the call. The task goes on from 0.
- Struck and destroyed ships plot no repairs.

### 3.8 Turn phases, events, log text

| Leeward phase | SoP | Work |
|---|---|---|
| PLANNING | II.B | `StubAI.assign_crew`; the player's `plot_crew` / `set_auto`; at End Planning `finalize_plots()` before the phase advances. |
| MOVEMENT_RESOLUTION, start | III | `begin_turn_tasks` (replaces `begin_plotted_changes`). The Tacking roll reads the T task. |
| MOVEMENT_RESOLUTION, results applied | — | `set_mp_used`; `after_movement`. |
| COMBAT_RESOLUTION | IV.B | Emptied section ⇒ `cancel_section` (4.B.3; from `DamageController` when `remove_crew_box` empties one). Hull #4 ⇒ RO. Hull #10, #12 ⇒ `start_fire`; #12 may `explode`. Rigging hit on a dismasted ship ⇒ `reset_progress`. A ship that strikes ⇒ every task but FF ends. |
| STATUS_ADJUSTMENT | V.E | `resolve_unfouling`, `resolve_fixes` (both with the marines DRM). |
| STATUS_ADJUSTMENT | V.F | `fire_controller.resolve`. |
| STATUS_ADJUSTMENT | V.G.1, .3, .6 | `advance_tasks`: repairs recorded, RO completed, sail changes take effect (5.F.8). |
| MORALE_CHECK | V.G.4 | Unchanged; rolls the MCs noted above. |

`PhaseEvents.Type` additions:

| Type | Data | Example text |
|---|---|---|
| `CREW_TASK` | `{section(s), code, params, state: started / completed / abandoned / cancelled, done, needed, reason, auto}` | "Vengeance: S3 begins repairing rigging (4 turns)" · "S4's shroud repair is lost: crew disorganized" · "S2 is sent to fight the fire" |
| `FIRE_STARTED` (extended) | `{fire, fires, cause, roll, needed, modifier, result_id}` | "Vengeance catches fire from Fougueux (2 ≤ 4)" · "A second fire breaks out aboard Vengeance" |
| `FIRE_FOUGHT` | `{fire, section, roll, modifier, needed, attempt, success}` | "Vengeance's S2 puts out the fire (3 −2 = 1 ≤ 3)" · "…fails to master the fire (8 −2 = 6 > 2)" |
| `FIRE_UNFOUGHT` | `{fire}` | "Vengeance has no crew to fight a fire: morale check" |
| `EXPLOSION_CHECK` | `{roll, needed, explodes}` | "Burning hulk Vengeance: explosion roll 5, needs 3 or less" |
| `BLAST` | `{source, range, mgn, d6, fgn}` then `DAMAGE` (cause `blast`) | "The blast from Vengeance strikes Superb (range 1: 35 + 4 = 39)" |
| `REPAIR` | `{kind, section}` | "Vengeance repairs a rigging box (section 2)" · "…splices the severed shrouds" |

Fire box losses are `DAMAGE` with cause `fire`. An explosion is the existing `DESTROYED` with reason `exploded`. Sail changes keep `SAIL_CHANGE`.

### 3.9 Contract for the boarding spec

- Section indices 0–4 (`ShipState.MARINES`), `crew_tasks`, `plotted_actions["crew_assignments"]` and `["crew_orders"]` as in §2.2.
- `CrewTaskController.register_handler(code, handler)` with the handler interface and flags in §3.1; `force_task`, `cancel_section`.
- Hook `on_fire_breaks_out(ship_id)` on handlers (8.E.2, 10.B.5).
- `CrewRules.stations` asks each handler for its stations, so the Boarders station is supplied by the boarding handler; `CrewAuto` asks registered handlers for rules between A2 and A3.
- `ShipState.is_burning()` (10.A.2, 8.C.3), `marines_available()`, `sections_able_to_fire()`, `plotted_sections`, `mp_used_this_turn`.
- RO: `force_task(…, "RO", {"reason": "boarding", …})`; its length and completion are implemented here (phase 2).

---

## 4. UX: the crew overlay

The approved design, element by element, with what feeds each in the real game. The view lives in `scripts/ui/crew_overlay/` (`crew_overlay.gd`, `deck_view.gd`, `station_panel.gd`, `counter_token.gd`, `crew_overlay_text.gd` for strings) and `scenes/ui/crew_overlay.tscn`. It is rebuilt from the Godot prototype's code, with `CrewProtoModel` replaced by `CrewRules` calls on a local copy of the plan; it never mutates game state. The prototype folder stays as it is. Sizes follow the Godot prototype (`proto_style.gd`: the HTML's CSS pixels × 18/14 on the 1920 × 1080 canvas).

### 4.1 Opening and closing

- The selected ship's card in the planning panel gets a primary button **"Crew & damage"**, and the overlay toggles on the **C** key (§9 Q4: C is "centre the camera" today). **Done** or **Esc** closes it; Esc first drops a picked-up token, then closes.
- The overlay covers the map area only. The planning panel stays visible and, while the overlay is open, shows the roster under the ship card (§4.6); while it is closed it shows the summary line (§4.8).
- It is editable in PLANNING for the player's own ships that are not destroyed. In other phases, and for a struck ship (firefighting is automatic), it opens read-only: no drag, no menu, a header note "Orders are given in the planning phase". Enemy ships cannot be opened (plots are secret).
- Selecting another ship while it is open switches the overlay to that ship. Movement plotting needs the map, so starting to plot a move closes the overlay.
- Header: ship name (display face), "‹type› · crew quality ‹CQ› · carrying ‹sail›" (`PlanningText.name_and_type`, `ShipState.crew_quality`, `sail_state`), the **Automatic** switch (§4.9), **Reset to defaults** (`CrewRules.default_plan`; hidden while Automatic is on), **Done (Esc)**. The prototype's one-button "Crew" tab group is dropped.

### 4.2 Tokens

A token is a crew section; an eliminated section has none. It shows the section id, a coloured band (sailors `#2f6a8e`, marines `#a3322a`), one pip per box left (`section_boxes`; at most 6 drawn, then a number), and in the band:

- the **progress tag** "T2/4": the g-t being worked now of the g-t's needed (`task.done + 1`, `turns_required` at the current CQ), for tasks of more than one g-t; fire parties show the attempt column instead ("1st", "2nd", "3rd+");
- the **AUTO tag** when `normalize` reports the section in `auto`: filled in by the fire draft, or, with Automatic on, any section the rules placed off the guns;
- a **lock** when the section cannot be moved (forced task; sail change in progress; Automatic on), with the reason as the tooltip;
- the **disorganized face** (greyed, "RO") for a section in RO.

### 4.3 Stations

One station is one task code; where it sits has no other meaning. The list, visibility, capacity, occupants and reasons all come from `CrewRules.stations(ship, plan, ctx)`; the overlay draws what it is given.

| Station (label · code) | Deck | Capacity | Shown when | Refusals and notes (text from `CrewRules.refusal`) |
|---|---|---|---|---|
| Serve the guns | gun deck(s) | 4 | always | "Only sailor sections serve the guns. Marines fire muskets instead." Note: "Both broadsides. Unassigned sailors work the guns (4.B.4)." |
| Marine fire | upper, quarterdeck rail | 1 | always | "Only the marine section gives marine fire." Until the boarding spec's marine fire lands, its tooltip says the muskets are not yet in play. |
| Sails aloft · SAIL | upper, at the masts | sections the chosen change needs | `SailController.available_targets` is not empty, or a change is in progress | Target picker on the station: "FS → MS (1 CS, 2 turns)" from `change_cost`; it sets `orders.sail_target`. In progress: tokens locked, "Must be completed (5.F.9)". Lines jammed: disabled, "Lines jammed: no sail changes". Short of sections: warning "Needs 2 sections: 1 placed. The change will not start." |
| Braces (tacking) · T | upper | 3 | `ctx.ma0_turn_plotted` | Header shows the chance for the sections now on it (`tacking_chance(ship, n)`), tooltip the chance for 0, 1, 2 and 3. |
| Fire N · FFN | upper, fire zone under Marine fire | 1 each | one per fire in `fire_list`, in seq order | "Fire 2 already has S1 fighting it. One section per fire (8.E.2)." Empty: red, "Unfought: morale check each turn" (8.E.6). Header right: turns burning. |
| Fire watch · FF | fire zone | no limit | no fire burns (with fires burning it is offered in the right-click menu only) | Note: "A head start if fire breaks out (8.E.2)." |
| Rigging repair · RR | upper, at the masts | 1 | a rigging box is missing | Disabled above FS: "Rigging can be repaired only at fighting sail, furled or dismasted (8.F.3a). You carry MS." |
| Shroud repair · RS | upper, chains | 1 | shrouds severed | — |
| Hull repair · RH | orlop | 1 | a hull box is missing | Note: "Cancelled if the ship moves more than 4 MPs (8.F.3b)." If the current movement plot already exceeds 4: the note turns to a warning. |
| Boarders · FB | upper, waist | 5 | boarding spec | "Boarders come from the lowest-numbered sailor sections first: send S1 before S3 (4.B.1)." |
| Reorganizing · RO | upper, forecastle | — | a section is in RO | Not a drop target; holds the locked RO tokens. |

Every refusal quotes its rule number, as in the prototype. A full station says "‹label› is full (N sections)."

**Fires on the deck.** Fires have no place in the rules; the fire zone is a convention (mapping, prototype). Up to two fires sit side by side with full tokens; more are laid out along the deck, two across the beam, forward as far as Rigging repair, with compact chips when a cell cannot hold a full token (Godot prototype). On the small deck cards the labels are the short codes (Guns, Marines, T, FB, RR, RS, RH, FF1…).

### 4.4 Assigning: drag, click-then-click, right-click

- **Drag** a token (from the deck or the roster) to a station. While it is lifted every station is outlined valid (green) or invalid (red) by `refusal`. Hovering a small deck card for 450 ms shows that deck large. A drop on a small deck's station works too.
- **Click** a token to pick it up (outlined), then click a station. Clicking elsewhere, or Esc, puts it down.
- **Right-click** a token (or the menu key, Shift+F10): a menu "‹S3› · assign to" listing every station shown, fires first; illegal ones are disabled with the reason beneath, the current one is marked.
- Every successful assignment goes to the server at once (`plot_crew`), so closing the overlay never loses work, and the redraw uses the returned normalised plan.
- **Progress loss:** moving a section off an abandonable task with at least one g-t done asks first, in the message bar: "S3 has 2 of 4 turns on rigging repair. Moving it loses them (4.A.3)." **Move anyway** / **Keep it there**.
- **Refusals** show in the message bar (red edge) and fade after about four seconds.
- A fire slot left empty is refilled by the fire draft and tagged AUTO, immediately.

### 4.5 Decks

- The selected deck is drawn large, bow up; its name is the heading. The side column lists every deck as a small card, in the fixed order of both prototypes: Upper deck, Orlop, then the gun deck(s). The enlarged deck stays in the list, highlighted ("shown large"). Clicking a card enlarges it.
- Card badges: "N on tasks" (sections on non-default stations of that deck), "N fires" on the upper deck, "damage" (a crit marker on that deck), "hull" on the orlop when hull boxes are missing, "−2 stbd" / "−2 port" on the first gun deck for an obscured side.
- Decks come from `deck_layouts.json` by ship type: frigates have Upper deck, Gun deck, Orlop; the 74 has Upper deck, Upper gun deck, Lower gun deck, Orlop.
- **Markers** (no token slot; their fix rolls need no crew, 8.D.5), from `critical_effects` and the log boxes: "Wheel shot away" at the wheel, "Rudder destroyed" / "Rudder jammed" at the rudder, "Shrouds severed", "Braces cut", "Lines jammed", "Signal halyards cut" at the masts, "Stbd broadside −2 (obscured)" on the gun decks; and two information markers, "Rigging section N: a/b" at the bow and "Hull section N: a/b" on the orlop, for the section now taking damage.

### 4.6 The left panel (planning panel, selected ship)

| Element | Real source |
|---|---|
| Hull and rigging bars: one group per section, one segment per box, emptied sections outlined red; "Rigging 19/22 · carries up to plain sail" | `ship.hull_hp` / `rigging_hp` (start) and `hull_current_hp` / `rigging_current_hp`; `max_sail_state()`. Reuses `ship_status_bars.gd`. |
| **Guns readout:** "3 of 4 sections · −3", red at −6 or worse; "Guns silent" at 0. Second line: who is missing and why ("S1 lost · S3 repairing rigging"). Third line: the marines' task. | `CrewRules.guns_preview(ship, plan)`: sailor sections with boxes that the plan leaves unplotted, and `sections_firing_modifier`. Sections lost for good count as missing, as on the chart. It is the modifier this turn's broadsides will get, both sides. |
| **DAMAGE (N)**, collapsible | One line per fire ("Fire 1: burning 3 turns · 1 hull and 1 rigging a turn · fought by S2 (2nd turn)" or "unfought: morale check each turn"), then `ShipStatusPanel.critical_lines(ship)`, then "Rigging boxes lost: repairable (RR)" / "Hull boxes lost: repairable (RH)" when `missing_boxes` > 0. N is the line count. |
| **Roster** (overlay open): a row per section with a small draggable token, its task, "Sailors · 3 boxes", a segmented progress bar "Turn 3 of 6" (fire parties: "2nd turn · until it is out"), and "Show on ‹deck›" when the task's station is on another deck. An eliminated section shows a dashed outline and "S2 lost". | The plan and `crew_tasks`. |

### 4.7 The tactical picture

A small map at the top of the side column so the player can weigh guns against tasks without closing the overlay: the selected ship in the centre, bow as on the map, every ship within 8 hexes in owner colours, and the wind arrow. Caption: the nearest enemy in play, its range and bearing, and the wind, e.g. "Topaze 4 hexes off the starboard bow · wind SW 2"; with no enemy within 15 hexes, "No enemy within gun range". Source: ship positions and `EnvironmentState`; range by `fire_geometry.range_between`; bearing words from the angle off the bow (ahead, off the port/starboard bow, on the beam, on the quarter, astern). It reuses the minimap's drawing code. A pending wind change is appended as the minimap shows it. Ships are drawn where they are now, not where the plot will put them.

### 4.8 The planning-panel summary line

With the overlay closed, the ship card shows one line of chips from `CrewRules.summary`: sections grouped by task in section order, "S1 sails · S2 FF1 · S3 S4 guns · M fire", with a fire chip in the fire colour and a warning chip (red outline) for anything in `warnings` or an unfought fire. Automatic adds a leading "Auto" chip. (The v15 prototype has the chip styles but shows the Guns readout and the button in this place; the line is specified by the mapping, §4.) The existing sail row stays as the quick way to order a sail change: it sets `orders.sail_target`; in manual mode it also places the worker-order sections on Sails if the station is empty.

The tacking note gains the crew: "Tack: 60 % with 2 at the braces (3: 80 %)", from `tacking_chance`.

### 4.9 The overlay while Automatic is on

- The switch reads "Automatic crew: on". Tokens sit where `CrewAuto` puts them, each with the AUTO tag (except default stations), and are locked. A drag or menu attempt shows: "Automatic crew is on: the ship's officers place the sections. Turn it off to place them yourself." with a **Turn off** button.
- Stations, notes, warnings, the Guns readout and the tactical picture work as usual, so the player sees what the rules did and why; held-back marines show "Marines held back: fire aboard" (or the other reason) on the Marine fire station.
- The sail target picker stays live (it is an order). So does the boarding order (boarding spec).
- Turning Automatic **off** keeps the current allocation as the starting manual plan: nothing moves. Turning it **on** re-allocates at once; tasks in progress are kept by rule A2, so nothing is lost.
- A small "?" beside the switch lists rules A0–A6 in the words of §3.3.

### 4.10 Where the prototype's fake data hid a rules question

| Prototype | Real game |
|---|---|
| Any token can be dragged off any task with a warning. | Sail changes in progress, RO and engaged boarders are locked (0.3 #1; 8.E.2; 10.E.1). |
| `autoFire` uses only sailors at the guns and gives up otherwise. | The fire draft goes on to marines and then to sections on tasks (§3.4), because 8.E.2 says a task must be aborted if need be. |
| Boarders skip a lower section that fights a fire. | No skip (0.1). |
| Repair stations appear from a "damaged" flag. | From boxes missing at plot time; the rigging and hull markers name the section taking damage. |
| RR is refused unless the sail is FS. | Also allowed furled (NS) and dismasted (8.F.3a). |
| Sail change turns are fixed numbers (FS→MS 2 turns). | From `change_cost`: 1 or 2 g-t's at CQ A–D, 2 or 3 at E–G; FS→MS at CQ D is 1. |
| A finished task sends the section to the guns. | The same, and Automatic may at once re-plot it (repairs, A5). |
| "End turn" advances every task by one. | A task advances only if it was plotted that g-t and nothing cancelled it; needed g-t's follow the current CQ. |
| The Guns readout counts "of 4". | Eliminated sections count as missing; the second line says which. |
| Fire age is turn − started + 1. | The same, from `started_turn` (0.3 #5). |
| Deck notes are hard-coded per prototype ship. | Built from `ships.json` `armament`, or omitted (§2.3). |

---

## 5. Fonts

The overlay and the theme take three faces, the ones the HTML prototype used. All are under the SIL Open Font License 1.1, which allows bundling in a game, free or sold, provided the licence and copyright notice travel with the fonts and the files are not sold on their own. Nothing is downloaded by this spec; the engineer fetches the files in phase 6 and must read the `OFL.txt` that comes with each family before committing it.

| Role | Face | Why | Licence | Source |
|---|---|---|---|---|
| Display: screen titles, ship names, deck names | **IM Fell English SC** (Igino Marini) | A revival of the Fell types, in daily use at English presses through the 18th century; the small caps read as an engraved title page. One weight. | OFL 1.1 | Google Fonts, `github.com/google/fonts/tree/main/ofl/imfellenglishsc`; the designer's site iginomarini.com/fell |
| UI text: labels, notes, log | **Source Sans 3** (Adobe, Paul D. Hunt) | Not a period face, chosen for reading small text on a dark panel; a humanist sans that sits quietly under the Fell titles; has tabular figures. | OFL 1.1 ("Source" is a reserved font name) | `github.com/adobe-fonts/source-sans`; Google Fonts `ofl/sourcesans3` |
| Condensed: tokens, station headers, chips, numbers | **Barlow Condensed** SemiBold and Bold (Jeremy Tribby) | Narrow and sturdy, like stencilled counter type; fits "S2 · T2/4" on a token. | OFL 1.1 | `github.com/jpt/barlow`; Google Fonts `ofl/barlowcondensed` |
| Optional, for long period text (scenario briefings, the rules reference) | **Libre Caslon Text** (Pablo Impallari) | Caslon was the standard English book face of the 1790s. Not needed by the overlay. | OFL 1.1 | `github.com/impallari/Libre-Caslon-Text`; Google Fonts `ofl/librecaslontext` |

**Adding them to the Godot theme (phase 6).**
1. Files go in `assets/fonts/<family>/` with that family's `OFL.txt`, unmodified and not renamed (subsetting or renaming a font with a reserved name is not allowed under the OFL). Use the static TTFs: `IMFellEnglishSC-Regular.ttf`; `SourceSans3-Regular.ttf`, `-SemiBold.ttf`, `-Bold.ttf`; `BarlowCondensed-SemiBold.ttf`, `-Bold.ttf`. Add `assets/fonts/README.md` listing each family, its copyright line and licence, and add the same list to the game's credits.
2. Import with Godot's defaults (dynamic font, antialiasing on, no MSDF: the Fell outlines are deliberately rough and gain nothing from it). In each font's import settings add the project's default font as a fallback, since IM Fell covers Latin only.
3. In `assets/ui/leeward_theme.tres`: set `default_font` to Source Sans 3 Regular (keep `default_font_size = 18`); set `HeaderLabel/fonts/font` to IM Fell English SC; add type variations `DisplayLabel` (Label; IM Fell, 26), `CounterLabel` (Label; Barlow Condensed SemiBold) and `StrongLabel` (Label; Source Sans 3 SemiBold). Bold weights are their own font files, not `FontVariation.variation_embolden`. Tabular figures for number columns: a `FontVariation` resource over Source Sans 3 with `opentype_features = {"tnum": 1}`.
4. `proto_style.gd`'s `display_font()` / `bold_font()` stand-ins are replaced in the real overlay by the theme variations; code that draws text in `_draw()` (tokens) takes its font with `get_theme_font("font", "CounterLabel")`.
5. Check every existing screen at 1920 × 1080 and at the Retina scale after the default font changes: Source Sans 3 is narrower than Godot's default face, so labels will not grow, but truncation settings should be looked at once. `make test` has no font dependence.

---

## 6. Implementation plan

Every phase: GUT tests with `ScriptedDice` (d10 = 0–9), `make test`, both validators, the `feature_diff.md` rows in §7, CLAUDE.md where it names a changed item, and a relaunch with `game_get_errors` at zero. Each phase leaves the game playable. The `scv-reviewer` runs once, at the end of phase 6.

1. **Crew-task engine and Automatic.** `crew_tasks.json`, accessors, validator. `ShipState` fields, helpers, serialization (§2.2, without the fire fields). `CrewRules`, `CrewAuto` (rules A0, A2, A3, A6), `CrewTaskController`; `SailController` as the SAIL handler; `finalize_plots` in `player_submit_plan`; `begin_turn_tasks` / `advance_tasks` in `TurnPhaseController`; `sections_able_to_fire` from `plotted_sections`; `mp_used_this_turn`; the marines DRM on unfouling and fix rolls; `StubAI.assign_crew`. Every ship is on Automatic and there is no switch yet. *Visible change:* a sail change is worked by the marines first (unless held back), so it often no longer costs −3 on the guns; a busy marine section costs +1 on unfouling and fix rolls. The planning panel's sail row works as before. Existing sail tests are updated where they assert S4-first.
2. **Tacking crew, crew disorganized, signal halyards.** T handler and rule A4; the tacking DRM and chance; hull #4 with RO; rigging #3 effect and fix roll; status-panel lines ("S4 reorganizing, 2 of 5 turns"); the planning tacking note with the crew count. *Visible change:* a ship turning at MA 0 has up to three sections at the braces and those do not fire that turn.
3. **The crew overlay.** `deck_layouts.json`; the overlay scene and scripts (§4) with every station type drawn from `CrewRules.stations` (fire and repair stations simply are not listed yet); the Automatic switch and `set_auto`; the roster, Guns readout, DAMAGE (N), tactical picture, summary line; manual allocation; the fire draft code path (unit-tested with fake fires). The key binding per §9 Q4. Driven and screenshot-checked through the `godot-mcp` tools with real clicks.
4. **Fire and explosions.** `fire_table.json`; `fire_list` migration; `FireController`; the FF handler and Fire watch; rule A1; hull #10 roll; hull #12 through `start_fire` and `explode`; blast, debris, growth, spread, unfought MCs, explosion checks; struck ships fighting fires; the "AFIRE" badge in the ship list; map effects per §9 Q6.
5. **Repairs.** `RepairController`; rule A5; `repair_box`, `checked_sections`, the 4-MP check, 8.F.6; the repair stations go live.
6. **Fonts and finish.** §5; log wording pass; `CONTRIBUTING.md`/CLAUDE.md ("Not implemented" list, the new controllers, the overlay); `scv-reviewer`.

The boarding spec's phases follow phase 3 (they need the overlay's Boarders station) and phase 4 (`is_burning`).

---

## 7. `feature_diff.md` changes by phase

| Phase | Rows |
|---|---|
| 1 | §2.1 "General crew-task plotting" → **Partly fixed** (engine; any CS may alter sail; still missing: tasks other than sail). §3 8.D.1 → marines-not-available DRM applies. §5 sail line: any section. **New §4 entry:** "Automatic crew allocation: the player may leave section-by-section plotting to fixed rules (default on); the result is always a legal plot." |
| 2 | §3 5.D.1–3 → **Fixed** except reverse tack. §2.2 "Crew disorganized" → **Fixed**. §2.1 "Critical hits" → the 5.F.9a item no longer missing. §2.2 "Signal halyards cut" → **Partly fixed** (effect and fix roll; no signalling to block). |
| 3 | None (presentation). |
| 4 | §1 item 6 → **Partly fixed**. §2.1 "Fire and explosions" → **Fixed**, noting the kept wreck (8.G.1f) and the SK reading chosen in §9 Q1. §2.2 "Fire roll after a minor explosion" → **Fixed**. §2.2 "Struck ships count as CQ G" → **Partly fixed** (firefighting). **New §3 row:** 8.E.2 "Mandatory firefighting: the server sends a section (fixed order) rather than leaving the choice wholly to the player; the player may change it." |
| 5 | §1 item 6 → **Fixed**. §2.1 "Repairs" → **Fixed**. §5 gains fire, repairs, crew tasks with rule numbers. |

---

## 8. Tests (expected values from the rules and charts)

`test/unit/test_crew_rules.gd`, `test_crew_auto.gd`, `test_crew_task_controller.gd`, `test_fire_controller.gd`, `test_repair_controller.gd`, plus additions to the sail, tacking, critical-hit and victory tests. Fixtures must set rigging and crew explicitly.

| # | Setup | Expected | Rule |
|---|---|---|---|
| 1 | A plan puts S3 on two stations | The second replaces the first; one task per CS | 4.B.2 |
| 2 | RR by S3 in g-t 1; g-t 2 S4 plots RR instead | S3's task ends "abandoned"; S4's starts at 0 | 4.A.3, 8.F.4 |
| 3 | Two sections on RR | Second refused; RR + RH together accepted | 8.F.4 |
| 4 | MS→PS by M and S4, CQ B | 2 g-t's, PS from the next g-t; moves and takes damage at MS until then | Ship log 2/3, 5.F.8 |
| 5 | FS→MS, CQ E | 2 g-t's | Ship log 1/2 |
| 6 | S2 on a task | Gunfire −3; two sailor sections on tasks −6; all four: cannot fire | Ship log; Majestic g-t 7, 17 |
| 7 | M altering sail, CQ B, obscured side, fix d10 3 | 3 −2 +1 = 2 ≤ 2: fixed. With M free and d10 4: 4 −2 = 2: fixed | Chart DRM; Majestic g-t 6 |
| 8 | Crew loss empties S1 doing RR 2 of 4 | Task ends "crew lost", progress gone | 4.B.3 |
| 9 | Sail change in progress; plan moves its section | Section restored (locked) | 5.F.9 |
| 10 | Turn at MA 0, 1 CS at T, CQ B, no rigging lost, at WF=L, not in irons | DRM −2 (SK) +4 = +2 | 5.D.2a; Majestic g-t 18 |
| 11 | No CS at T | +6, not +8 | 5.D.2a erratum |
| 12 | Type A, WS 3, CQ B, 3 CS at T, at WF=L | Chart ≤ 6, DRM −2: succeeds on 0–8, 90 % | 5.D.3 example (Prince) |
| 13 | T sections after a failed tack | Still do not fire this g-t | 0.3 #2; Majestic g-t 17 |
| 14 | Hull #4, CQ B, S4 on RS 2 of 3 | 1 sailor box lost; RS ends; S4 in RO needing 3, done 0; free after 3 more g-t's | Hull #4; Majestic g-t 16 |
| 15 | Second hull #4 while S4 is in RO | S3 disorganized | Hull #4 ("not already disorganized") |
| 16 | RO at CQ A / CQ E | 2 / 6 g-t's | 10.G.4 |
| 17 | CQ falls B→C in the MC of g-t 3 of a 4-g-t RR | Needed becomes 5; completes a g-t later | 9.A.2; Majestic g-t 16–20 |
| 18 | Hull #4 on a section sharing a 2-CS sail change | The change is cancelled for both | 5.F.9a |
| 19 | Rigging #3 at MS; later fix d10 2 at CQ D | 1R lost, effect recorded; 2 ≤ 2: fixed | Rigging #3, 8.D.5 |
| 20 | Automatic: fire aboard, S1 on RR in progress, MA-0 turn plotted | Fire: S2 (lowest free sailor). S1 keeps RR. T: S4, S3 only (M held back: fire); nothing left for a third | §3.3 |
| 21 | Automatic: no fire, FS→MS ordered, no enemy near | M alters sail; four sections at the guns | §3.3 A3 |
| 22 | Automatic: rigging and hull boxes missing, FS, enemy at 10 hexes, M free | M on RR; no RH (sailors stay at the guns). Enemy at 16: S4 on RH as well | §3.3 A5 |
| 23 | Automatic twice on the same state | Identical plans | §3.3 |
| 24 | Fire draft: sailors all on tasks, M free | M | §3.4 |
| 25 | Fire draft: S1 RO, S2 RR 3 done, S3 RH 1 done, S4 and M engaged or lost | S3 (fewest g-t's done); RH ends "called to the fire" | 8.E.2 |
| 26 | Fire draft: only RO sections left | −1; fire unfought | 8.E.2 exception |
| 27 | Hull #10, CQ D, d10 6 / 5 | Afire + 1 MC / no fire | Hull #10 |
| 28 | Hull #10, CQ A, d10 8 / 9 (recommended reading) | No fire (8 −3 = 5) / afire | §9 Q1 |
| 29 | Fire starts in combat, no FF plotted | No roll; 1R and 1H that g-t; one MC only | 8.E.8, 8.E.7; Majestic g-t 18 |
| 30 | FF, CQ B, 1st g-t, d10 4 / 5 | Out (4 −2 = 2 ≤ 2), no damage that g-t / burns, 1R 1H | 8.E.3, Unfouling |
| 31 | FF 3rd g-t by the same CS, CQ D, M on RR, d10 3 | 3 +1 = 4 ≤ 4: out | Unfouling 3+, marines DRM |
| 32 | FF 2nd g-t, then a different CS takes over | Its roll uses column 1 (≤ 2) | 0.2 Q5 |
| 33 | Fire watch plotted; fire breaks out in combat; CQ D, d10 2 | Rolled this g-t, column 1: out, no damage | 8.E.2 HINT |
| 34 | Fire started g-t 7, never put out | Second fire in step 3 of g-t 11, with an MC; it does no damage in g-t 11; FF2 needed from g-t 12; third fire from the first at g-t 16 | 8.E.5 example |
| 35 | Two fires, one CS able | One MC per g-t for the unfought fire | 8.E.6, 9.B.1d |
| 36 | Fouled to a burning ship, CQ D, d10 4 / 5 | Catches fire (+ MC) / does not | 8.E.4 |
| 37 | Burning, the fire takes the last hull box; 2d6 = 3; next g-t 2d6 = 3 | Strikes, no explosion; then explodes (≤ 3) | 8.E.8 example |
| 38 | Class 2 explodes; target at range 1 at FS, d6 4 | FGN 39, firing high, FS: 5r-h-c; no crit roll; crew box on "All Other Causes" | 8.E.10, chart row 39, 7.D.9 |
| 39 | Class 3 explodes; target at range 2, d6 1 / range 3 | FGN 16 high / no blast | 8.E.10 table |
| 40 | Debris: range 5, d6 5 / 4; range 1, d6 1; a ship fouled to it | Fire / none / none / fire without a roll | 8.E.11 example |
| 41 | Hull #12 explodes (2d10 + DRM < class) | Blast and debris as above; the wreck stays | Hull #12 |
| 42 | Struck burning ship, CQ had been B, FF 1st g-t, d10 0 | 0 +3 = 3 > 2: still burning (struck ships fight as G) | 8.E.3, 9.C.4 |
| 43 | Struck ship with fires and no crew | No roll, no MC; burns; explosion checks once hull is 0 | 9.C.3 |
| 44 | Fire with S3 in RO and nobody else | S3 keeps RO; fire unfought, MC | 8.E.2 exception |
| 45 | RR plotted at MS; at NS; dismasted | Refused; accepted; accepted | 8.F.3a |
| 46 | RH in progress, ship uses 5 MPs (turns counted); 4 MPs | Lost; kept | 8.F.3b (≤ 4, PDF) |
| 47 | Rigging first damaged in g-t 3 | RR station absent in g-t 3 planning, present in g-t 4 | 8.F.3 |
| 48 | CQ A RR / RH; CQ D RR; CQ B RS | 3 / 7; 6; 3 g-t's, and RS removes the −1 MP | 8.F.4, 8.F.6 examples; Majestic g-t 14 |
| 49 | Rigging 3-of-7 in section 1, RR completes | Section 1 has 4 | 8.F.5 |
| 50 | Rigging section 1 at 0, section 2 full, RR completes | Section 1 has 1; rigging level 4 | 8.F.5 example |
| 51 | That box is lost again | No Rigging Check, no MC | 8.F.5, 9.B.2 |
| 52 | Hull section 1 repaired then lost again | No Hull Check, no MC, no guns dismounted again | 8.F.5, 0.3 #7 |
| 53 | Dismasted, CQ D, RR 5 of 6, takes a rigging hit (gunfire *r*; a fire's 1R) | `done` back to 0; the task goes on | 8.F.6 example |
| 54 | Dismasted, RR completes | Section 4 has 1 box; level 1; sail state still NS | 0.2 Q6 |
| 55 | A ship with rigging section 1 at 0 scores 5 %; after a repair there | 0 % for that section | Scenario Book VI.B.4 |
| 56 | `stations()` with a 2-CS sail change chosen and one token | Warning "Needs 2 sections"; at `begin_turn_tasks` no change starts | 5.F.6b |
| 57 | Serialize and deserialize a ship with tasks and fires; an old save with `sail_change` | Round-trips; the old field becomes a SAIL task | — |

---

## 9. Open questions for the user

**Answered 2026-11-15: the user approved every ★ recommendation below.** Implement the ★ option in each case.

1. **Which way does "± SK" work for catching fire?** Hull #10 says "d10 ≥ 6 (± SK)"; 8.E.4 says "≤ 4 (± SK of the ship being spread to)". Everywhere else SK is added to the die, which here would make a crack crew *more* likely to catch a spreading fire.
   - ★ **Better crews resist both:** hull #10 afire on `d10 + SK ≥ 6` (CQ A 10 %, D 40 %, G 70 %); spread on `d10 ≤ 4 + SK` (A 20 %, D 50 %, G 80 %). It matches hull #12, where a good crew is +3 against exploding.
   - Literal "add SK to the die" in both: spread becomes A 80 %, G 20 %. Consistent with the other charts, odd in play.
   - Either way it is a reading of an ambiguous line, recorded in `feature_diff.md`.
2. **Automatic crew: per ship or per game, and on or off at the start?**
   - ★ **Per ship, on at the start.** A player can run the flagship by hand and leave the rest to the rules; today's behaviour (sections picked for you) is unchanged until they switch it off.
   - Per game: one switch, simpler to explain, but all-or-nothing in a fleet action.
   - Off at the start: closer to the board game, but every new player must learn the overlay before their first tack.
3. **How eager is Automatic with repairs?**
   - ★ **Marines whenever free; sailors only with no enemy within 15 hexes.** Predictable, never costs gunfire in action. Consequence: in a long close fight only one repair runs at a time.
   - Always repair with whoever is free: faster repairs, −3 per section on the guns without being asked.
   - Never repair automatically: repairs only happen on ships run by hand.
4. **The C key.** The prototype opens the overlay with C; in the game C centres the camera on all ships.
   - ★ **C opens Crew & damage; centre-camera moves to Home.** The key on the button matches what was approved.
   - Keep C for the camera and open the overlay with another key (say V). The button label changes.
5. **Does a ship whose marine section is wiped out count as "marines not available" (+1)?** The chart does not say.
   - ★ **No.** The DRM is for marines busy elsewhere; otherwise a ship with no marines is 10 % worse at every fix and firefight for the rest of the game.
   - Yes: harsher, arguably what "not available" literally means.
6. **Fire on the map.**
   - ★ **Procedural flame and smoke on a burning ship (more with more fires), a flash and debris ring on an explosion, in phase 4.** Fire is the most dangerous state in the game and should be visible without opening a panel.
   - Badge and log only: no art work, but an exploding neighbour comes as a surprise.
