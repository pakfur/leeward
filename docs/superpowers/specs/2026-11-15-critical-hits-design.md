# Critical Hits, Rigging Checks and Hull Checks — Design

**Status:** approved, in implementation · **Date:** 2026-11-15 · **Closes:** `feature_diff.md` §1 item 1, §2.1 "Critical hits" row

## 0. Decisions (binding; they override anything below that disagrees)

From the answers in §6:

- **Deferred (do not implement; tracked in `feature_diff.md` §2.2):**
  - **Q6 Crew disorganized (hull #4):** apply only the box loss (1 sailor; none for class 4). No disorganized section, no reorganize countdown, no effect on sail changes or sections firing. Log the result as "crew disorganized (not yet simulated)". Revisit with crew tasks.
  - **Q10 Minor explosion fire roll (hull #10):** apply 1H and −2 guns dismounted on the engaged broadside. Do not roll for fire. Log "fire roll not yet simulated". Revisit with crew tasks and fire (8.E).
  - **Q16 Signal halyards cut (rigging #3):** apply only the 1R loss at MS or PS. No effect entry and no fix roll. Revisit with signalling.
- **Q2 Explosion (hull #12):** if the 2d10 explosion roll says the ship explodes, the ship is **destroyed**. That is a new status `DESTROYED`, removed from play: it cannot move, fire, drift, change sail, unfoul or be targeted, and it counts as lost for victory. It stays on the map as an obstruction: its two hexes still block movement (collisions) and line of sight. The view swaps the ship model for a "wreck with debris" look; generate it procedurally, since no asset exists. Afire without an explosion: increment `fires` and log it (fire itself is not simulated).
- **Q4:** [D] filters only the dismantling shot's own crit, not the RC/HC checks it causes.
- **Q5:** no HC for losing hull section 4 (the ship strikes).
- **Q7:** implement the 5.E.5 base reductions (two rigging sections lost, WS = 1, towing; floor 1) in `get_speed_change_limits`.
- **Q8:** ignore the Braces Cut "changing sail state" exception.
- **Q9:** bearing off with Rudder Destroyed is +3 (rudder) +1 (poor maneuvering) = **+4**.
- **Q12:** for non-rake fire from outside the target's arcs, the engaged side is set by relative bearing, with a d6 on the centre line (1–3 port, 4–6 starboard).
- **Q13:** "bow arc" for 7.E.6 means `rake == "bow"` only.
- **Q14:** scenarios gain an optional integer `year`; the ≤1783 −1 DRM applies only when it is present and ≤ 1783.
- **Q15:** Rudder Jammed's "last MP used" is the last step the ship executed this turn when the crit happens. If the ship did not move this turn, it is the last step of its previous move; with no step at all, treat it as straight.
- **UI (§4, no answers given; the spec's recommendations apply):** one status-panel line per active effect; failed critical-hit rolls are shown in the log (every roll is traceable); the planning UI shows a poor-maneuvering chance beside turn steps, as it does the tacking chance; no map badges, except the wreck model for a destroyed ship.
**Sources:** rule text `docs/rules/close_action.md` (7.C.11, 7.C.12b, 7.D.6–12, 7.E.5–6, 5.E.5–6, 5.F.9, 6.F, 8.D.5, 9.B.1e, glossary RC/HC); numbers only from the scans `docs/rules/images/rigging-critical-hits.jpg` (p.112), `hull-critical-hits.jpg` (p.113), `gunfire-results-chart.jpg` (CH# column, p.110), `boarding-combat-chart.jpg` (Unfouling, Poor Maneuvering, Tacking and Bearing Off DRMs, p.109). PDF p.25 confirms 7.D.11: "the second DR (± the target's \"CH mod\" value) is ≤ the critical hit number".

---

## 1. Rules summary

### 1.1 When a roll happens

| Trigger | Rule | Dice | Table / column |
|---|---|---|---|
| A shot's gunnery d6 is a natural **6** | 7.D.11 | d6 + target's `ch_modifier`; crit if result **≤ CH#** of the FGN row | — |
| …crit occurs | 7.D.11a | **2d6** (2–12) | Firing **low** → Hull "Crit" column; firing **high** → Rigging "Crit" column |
| A **rigging section** is completely marked out (any cause: gunfire, collision 6.E.3, crit extra boxes 7.D.12, "cross out current section") | 7.D.7, 7.D.12 | **d6** | Rigging table, "RC" column |
| A **hull section** is completely marked out | 7.D.8a, 7.D.12 | **d6** | Hull table, "HC" column |
| Hull result #7 "Rigging damage" | hull chart | **2d6** | Rigging "Crit" column |

- `ch_modifier` (SDC "CH mod", +1 to −4; Leeward: frigates −2, 74 0) is **added** to the second d6. The worked example (scenario book, *Majestic* G-T 8: FGN 40, CH# ≤5, CH mod −2 ⇒ "automatically") confirms *add* and *≤*; the OCR reads "(= the target's CH mod)" and "<".
- CH# by FGN (chart, matches `gunfire_results_table.json` `ch`): 1–6 ≤0, 7–14 ≤1, 15–22 ≤2, 23–30 ≤3, 31–38 ≤4, 39–46 ≤5, 47–52+ ≤6. With CH mod −2 a natural-6 shot at FGN ≥ 7 can crit (d6 ≤ CH# + 2).
- Crits take effect immediately but never affect the target's return fire (7.D.11b) — already true, all shots are previewed from start-of-step state.
- **[D]** results do not apply if the shot was Dismantling Shot; DS causes **no hull crits at all** (7.C.12b). (RC/HC checks are not shots; [D] does not apply to them — Open question 3.)
- **◆** rigging results are ignored if the target became dismasted in the current combat phase. **No rigging crits** (from the 2d6 Crit column, incl. via hull #7) on a ship dismasted before the current combat phase (rigging chart notes).
- Extra boxes from crits are marked out like gunfire hits; emptied sections trigger RC/HC/MC exactly as for gunfire (7.D.12). Crit crew losses are not doubled by a stern rake (7.E.5a); crit "guns dismounted" hit **both** sides on a stern rake (7.E.5b, hull chart note *).
- "Engaged broadside" = the side of the target the fire hit; bow rake: roll randomly; stern rake: both broadsides (hull chart note *).
- RJ/RD cannot happen from a bow rake / bow arc; lose 1H instead (7.E.6, hull #2 note).
- Multiple copies of a result may coexist unless noted (both chart notes).
- An MC called for by a crit is a 9.B.1e trigger.

### 1.2 Rigging Critical Hits table (p.112) — fully legible

| RC | Crit | Id | Flags | Effect |
|---|---|---|---|---|
| 1 | 2 | `mast_may_fall` | ◆ [D] | d6 + DRMs (+1 MS, +2 PS, +1 per rigging section lost incl. first, +1 WS 4, −1 WS 1 or 0); **≥ 8** → cross out current rigging section |
| 2 | 3 | `signal_halyards_cut` [SH] | | Lose 1R at MS or PS. No new messages until fixed. Dismasted ships must still fix. Fix: Unfouling table |
| 3 | 4 | `braces_cut` [BC] | ◆ | Accel **and** decel ≤ 1 MP per g-t (may exceed decel by turning into a WF with lower max MA than current speed, or by changing sail). Fix: Unfouling table |
| 4 | 5 | `lines_jammed` [LJ] | ◆ | May not alter sail; a change in progress is aborted (5.F.9c). Dismasted ships fix automatically. Fix: Unfouling table |
| 5 | 6 | `broadside_obscured` [−2P/−2S] | | Lose 1R at MS, 2R at PS (none at FS). d6: 1–3 port, 4–6 starboard; that broadside −2 to gunfire until fixed (7.C.11). Fix: Unfouling table |
| 6 | 7 | `sheets_cut` [−1] | ◆ | −1 MP in all directions and sail states, −1 acceleration (may reach 0, 5.E.6), **next g-t only**, then auto-fixed. Max one per ship per g-t |
| — | 8 | `leadership_casualties` [MC] | | Lose 1 marine box (none for class 4; sailor if no marines). MC |
| — | 9 | `shrouds_severed` [SS] | ◆ | Lose 1R. −1 MP all directions/sail states until repaired (1 CS, 5 g-t ± SK, "RS") |
| — | 10 | `yard_shot_away` [−2P and −2S] | [D] | Lose 1R FS / 2R MS / 3R PS. Both broadsides −2 until fixed, each side fixed separately |
| — | 11 | `stays_cut` [SC] | ◆ | d10; if **≤ current speed**, cross out current rigging section and MC. Then lose 1 more R |
| — | 12 | `mast_falls_on_deck` [MC] | [D] | Cross out current rigging section. Lose 3C (class 1–2), 2C (class 3), 1C (class 4), marines first. MC |

### 1.3 Hull Critical Hits table (p.113) — fully legible

| HC | Crit | Id | Flags | Effect |
|---|---|---|---|---|
| — | 2 | `rudder` | [D] | d6 1–3 **Rudder Destroyed** (RD): one 60° turn per g-t, Poor Maneuvering with "keep rolling each subsequent hex until it succeeds", entering WF=L ⇒ automatically in irons; no effect if already RD; cancels RJ; never fixed. d6 4–6 **Rudder Jammed** (RJ): if moving, must keep turning in the direction of the last MP used; if that was straight, may not turn; if a turn, must turn at least once that way per movement phase and never the other way (a ship that can stop need not turn). One RJ at a time; ignored if RD. Fix: Unfouling table. Bow rake/bow arc ⇒ 1H instead |
| — | 3 | `wheel_shot_away` | | One 60° turn per g-t + Poor Maneuvering (6.F). Never repaired |
| — | 4 | `crew_disorganized` | | Lose 1 sailor box (none class 4). Highest-numbered sailor section not already disorganized is disorganized; its tasks are cancelled; reorganize "RO" for 5 g-t ± SK |
| 1 | 5 | `leadership_casualties` | | As rigging #8 (1 marine, MC) |
| 2 | 6 | `hull_structural_damage` | [D] | Lose 1H. (Anchored/towing d6 = 1 cuts cable — not modelled) |
| 3 | 7 | `rigging_damage` | | Roll 2d6 on the Rigging Crit column |
| 4,5 | 8 | `guns_dismounted_1` | [D] | −1 guns dismounted, engaged broadside |
| 6 | 9 | `guns_dismounted_2` | [D] | −2 guns dismounted, engaged broadside |
| — | 10 | `minor_explosion` [FIRE] | [D] | Lose 1H, −2 guns dismounted engaged broadside. d10 **≥ 6 (± SK)** ⇒ afire + MC |
| — | 11 | `waterline_damage` | [D] | Send sailor boxes to the pumps: class 1 = 4, 2 = 3, 3 = 2, 4 = 1 (marines if sailors short); marked off like crew losses. Not enough crew ⇒ strikes and rolls to sink |
| — | 12 | `afire_major_explosion` [FIRE] | [D] | Afire, 1H, −2 guns dismounted **each** broadside, MC. 2d10 + DRMs **< class** ⇒ explodes. DRMs: CQ A +3, B +2, C +1, E −1, F −2, G −3; each existing fire −2; scenario year ≤ 1783 −1 |

Note: hull HC column has no entry for crits 2–4 and 10–12; a d6 HC can only produce #5–#9.

### 1.4 Dependent rules

| Rule | Effect in Leeward |
|---|---|
| 7.C.11 | −2 per `broadside_obscured`/`yard_shot_away` side entry on that broadside's shots |
| 5.E.5–6 | Braces Cut: accel = 1 (and decel = 1); Sheets Cut: accel −1, floor 0. Base 5.E.5 reductions (two rigging sections lost, WS = 1, towing; floor 1) are a separate missing row (§2.2) — implement them in the same helper (Open question 6) |
| 5.F.9a/c | A sail change is cancelled by Lines Jammed, or when one of its sections is disorganized |
| 6.F.2–5 | Poor maneuvering: d10 **≤** chart number per plotted turn; fail ⇒ one extra hex ahead then turn, drop the last plotted MP; last-MP failure carries the turn to the next g-t's first MP (auto-success); at MA 0 roll Poor Maneuvering and Tacking |
| Tacking DRMs (chart) | Rudder Destroyed **+3** |
| Bearing Off DRMs (chart) | Rudder Destroyed/Jammed **+3**, Poor Maneuvering **+1** |
| 8.D.5 | Fix obscured broadsides, braces cut, lines jammed, signal halyards cut, rudder jammed: d10 + SK mod (+1 marines not available — n/a) ≤ Unfouling number for the attempt (1: ≤2, 2: ≤3, 3+: ≤4) |
| 9.B.1e | Crit MCs noted via `note_morale_check` with a unique trigger |

Poor Maneuvering table (d10, roll ≤ n), CQ × maneuver type A/B/C/D: A 6/7/8/8 · B 5/6/7/8 · C 5/5/6/7 · D 4/5/5/6 · E 4/4/4/5 · F 4/4/4/4 · G 4/4/4/4. (6.F.3 example: type B, CQ E, "must roll ≤ 4" — matches.)

---

## 2. Data model

### 2.1 `data/rules/critical_hits_table.json`

```json
{
  "_doc": "Rigging and Hull Critical Hits tables (1997, p.112-113). crit = 2d6 (2-12); check = d6 RC/HC column. flags: D = not with dismantling shot; diamond = ignore if dismasted this combat phase.",
  "rigging": {
    "check": {"1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7},
    "crit": {
      "2":  {"id": "mast_may_fall", "flags": ["diamond", "D"], "fall_at": 8, "drm": {"ms": 1, "ps": 2, "per_section_lost": 1, "ws4": 1, "ws_le_1": -1}},
      "3":  {"id": "signal_halyards_cut", "flags": [], "rigging": {"fs": 0, "ms": 1, "ps": 1}, "fixable": true},
      "4":  {"id": "braces_cut", "flags": ["diamond"], "fixable": true},
      "5":  {"id": "lines_jammed", "flags": ["diamond"], "fixable": true},
      "6":  {"id": "broadside_obscured", "flags": [], "rigging": {"fs": 0, "ms": 1, "ps": 2}, "gunfire": -2, "fixable": true},
      "7":  {"id": "sheets_cut", "flags": ["diamond"], "mp": -1, "accel": -1, "turns": 1},
      "8":  {"id": "leadership_casualties", "flags": [], "marines": 1, "mc": 1},
      "9":  {"id": "shrouds_severed", "flags": ["diamond"], "rigging_all": 1, "mp": -1},
      "10": {"id": "yard_shot_away", "flags": ["D"], "rigging": {"fs": 1, "ms": 2, "ps": 3}, "gunfire": -2, "fixable": true},
      "11": {"id": "stays_cut", "flags": ["diamond"], "extra_rigging": 1, "mc": 1},
      "12": {"id": "mast_falls_on_deck", "flags": ["D"], "crew_by_class": {"1": 3, "2": 3, "3": 2, "4": 1}, "mc": 1}
    }
  },
  "hull": {
    "check": {"1": 5, "2": 6, "3": 7, "4": 8, "5": 8, "6": 9},
    "crit": {
      "2":  {"id": "rudder", "flags": ["D"], "destroyed_max": 3, "bow_hull": 1},
      "3":  {"id": "wheel_shot_away", "flags": []},
      "4":  {"id": "crew_disorganized", "flags": [], "sailors_by_class": {"1": 1, "2": 1, "3": 1, "4": 0}, "reorganize_turns": 5},
      "5":  {"id": "leadership_casualties", "flags": [], "marines": 1, "mc": 1},
      "6":  {"id": "hull_structural_damage", "flags": ["D"], "hull": 1},
      "7":  {"id": "rigging_damage", "flags": []},
      "8":  {"id": "guns_dismounted", "flags": ["D"], "guns": 1},
      "9":  {"id": "guns_dismounted", "flags": ["D"], "guns": 2},
      "10": {"id": "minor_explosion", "flags": ["D"], "hull": 1, "guns": 2, "fire_at": 6},
      "11": {"id": "waterline_damage", "flags": ["D"], "pumps_by_class": {"1": 4, "2": 3, "3": 2, "4": 1}},
      "12": {"id": "afire_major_explosion", "flags": ["D"], "hull": 1, "guns_both": 2, "mc": 1,
             "explode_drm": {"A": 3, "B": 2, "C": 1, "D": 0, "E": -1, "F": -2, "G": -3, "per_fire": -2, "year_le_1783": -1}}
    }
  }
}
```
Plus `data/rules/poor_maneuvering_table.json` (`{"A": {"a": 6, "b": 7, "c": 8, "d": 8}, …}`, values in §1.4). Extend `validate_combat.py`: crit keys 2–12 present, check keys 1–6 map to existing crit keys, ids from a known set.

### 2.2 `CombatTables` accessors (`scripts/autoload/combat_tables.gd`)
`critical_hit_number(fgn)` (exists) · `rigging_check(d6) -> Dictionary` · `rigging_crit(roll_2d6) -> Dictionary` · `hull_check(d6)` · `hull_crit(roll_2d6)` · `poor_maneuvering_number(crew_quality, maneuverability) -> int` (asserts like the others). Accessors return a deep copy of the row.

### 2.3 `ShipState` (mutated only through `ShipStateController`)

```
@export var critical_effects: Array[Dictionary] = []
# each: {"seq": int, "id": String, "turn": int, "side": int (-1 = none),
#        "attempts": int (fix rolls so far), "expires_after_turn": int (-1 = no expiry),
#        "section": int (-1; crew_disorganized), "turns_left": int (reorganize countdown)}
@export var critical_seq: int = 0          # next seq, also makes morale triggers unique
@export var rudder_destroyed: bool = false # log box, permanent
@export var wheel_shot_away: bool = false  # log box, permanent
@export var fires: int = 0                 # stored only until 8.E exists
```
Active ids in `critical_effects`: `signal_halyards_cut`, `braces_cut`, `lines_jammed`, `broadside_obscured` (side), `sheets_cut`, `shrouds_severed`, `rudder_jammed` (side = jam direction: −1 straight, 0 port, 1 starboard), `crew_disorganized` (section). One-shot results (boxes, guns, MCs) leave no entry.

Read-only helpers on `ShipState`: `has_critical(id)`, `critical_count(id, side=-1)`, `obscured_penalty(side)` (−2 × entries on that side), `critical_mp_loss()` (sheets cut ≤ 1 + shrouds severed count), `is_poor_maneuvering()` (`rudder_destroyed or wheel_shot_away`), `max_turns_per_gt()` (1 if poor maneuvering else unlimited), `disorganized_sections()`. Serialize/deserialize all new fields (state-history snapshots then capture them automatically).

`ShipStateController`: `add_critical_effect(ship_id, effect) -> int seq`, `update_critical_effect(ship_id, seq, changes)`, `remove_critical_effect(ship_id, seq)`, `set_rudder_destroyed`, `set_wheel_shot_away`, `add_fire`, `cross_out_rigging_section(ship_id) -> int` (section index or −1). All with the `is_server` guard.

---

## 3. Server design

### 3.1 `CriticalHitController` (new, `scripts/server/critical_hit_controller.gd`)
Created in `GameState._initialize_server_controllers()` as `critical_hit_controller`, takes `game_state`, rolls only through `game_state.dice`. A separate controller keeps `DamageController` (box bookkeeping) small and avoids recursion: it owns a **work queue**.

```
check_gunfire_crit(shot_ctx, phase)   # called by GunneryResolver after apply_hits
queue_rigging_check(ship_id, ctx)     # called by DamageController when a rigging section empties
queue_hull_check(ship_id, ctx)        # ... hull section 1-3 empties (section 4 strikes; Open q. 4)
drain(phase)                          # processes the queue FIFO until empty
resolve_fixes(phase)                  # STATUS_ADJUSTMENT: 8.D.5 rolls, reorganize countdown, expiries
```
`ctx` = `{source_id, aim, ammo, rake, engaged_side, dismasted_at_start, phase_kind: "combat"|"movement"}`. Each crit result is a `match id:` arm that calls `damage_controller.apply_hits` / new `apply_crew_boxes(ship_id, marines, sailors, phase)` (direct box loss, no Crew Loss roll — leadership, pumps, mast on deck, disorganized), `ship_controller` setters, and `_note_crit_morale(ship_id)` (trigger `"crit_%d" % seq`). Box losses that empty sections enqueue further checks; `drain` finishes them before the next shot. Bounded: at most 4 rigging + 3 hull sections can empty.

### 3.2 Hooks in existing code

| File / function | Change |
|---|---|
| `gunnery_resolver.gd` `_resolve_shot` | After `apply_hits` and the dismasted-rake MC: if `d6 == 6 and fgn >= 1`, call `check_gunfire_crit`, then `drain`. Pass `dismasted_at_start`. Extend the dice-order doc: **5.** CH d6 (only on natural 6), **6.** crit 2d6 and its sub-rolls, **7.** RC/HC d6s in queue order. FIRE event gains `ch_number`. |
| `damage_controller.gd` `_apply_rigging` / `_apply_hull` | Detect each section that goes from >0 to 0 and `queue_rigging_check` / `queue_hull_check` (hull 1–3; skip if the ship struck). New `apply_crew_boxes`. `_apply_rigging` on dismasting also clears `lines_jammed` (auto-fix). |
| `movement_resolver.gd` `_apply_rigging_damage` | Collision rigging loss already goes through `apply_hits`; call `critical_hit_controller.drain(MOVEMENT_RESOLUTION)` after it (RC with ◆ handling; no `[D]`). |
| `gunnery_calculator.gd` `preview` | `_add_modifier(p, "broadside_obscured", firer.obscured_penalty(order.side))`; label in `PhaseEvents.MODIFIER_LABELS`. |
| `ship_state_controller.gd` `get_movement_allowance` and `movement_validator.gd` `_build_plotting_state` | `ma = max(ma - ship.critical_mp_loss(), 0)` before blocked wind (5.G applies after every other change). |
| new `ShipStateController.get_speed_change_limits(ship_id) -> {accel, decel}` | Table value → 5.E.5 reductions (floor 1) → Braces Cut (accel = min(accel,1), decel = min(decel,1)) → Sheets Cut (accel − 1, floor 0). Used by `movement_validator._build_plotting_state`, `movement_resolver._deceleration_minimum`, `game_controller.gd` (~line 862). Braces Cut decel exceptions are already covered: validator sets `min_ma = 0` at MA 0 and resolver 5.E.9 handles WF caps; sail change exception: Open q. 7. |
| `movement_validator.gd` `_calculate_real_valid_hexes` / `_add_pivot_options` | No pivot after `max_turns_per_gt()` used; Rudder Jammed: restrict pivot direction per §1.3 and require ≥ 1 turn in the jam direction when the plot moves (`validate_submission`). |
| `movement_resolver.gd` turn execution | Poor maneuvering roll per plotted turn (6.F.3); RD variant keeps rolling each hex; 6.F.4 carry-over via new `ShipState.pending_turn` (−1/0/1); 6.F.5 roll both at MA 0; RD entering WF=L ⇒ in irons. **Must use the resolver's `rng`** like the tacking roll, so replays reproduce it (the accepted exception in CLAUDE.md). |
| `movement_resolver.gd` `_calculate_tacking_drm` / `_bearing_off_drm` | +3 rudder destroyed (tacking); +3 RD or RJ, +1 poor maneuvering (bearing off). |
| `sail_controller.gd` `plot_sail_change` / `_cancel_reason` / `_free_sections` | Refuse plotting while `lines_jammed` ("lines jammed"); cancel in progress with reason "lines jammed" at crit time (immediate, logged SAIL_CHANGE cancelled) and "crew disorganized" when a change section is disorganized; `_free_sections` skips disorganized sections. |
| `turn_phase_controller.gd` STATUS_ADJUSTMENT | `fouling_controller.resolve_unfouling()` → `critical_hit_controller.resolve_fixes()` → `sail_controller.advance_changes()`. |
| `ship_state.gd` `sections_able_to_fire` | Exclude disorganized sections (Open q. 5). |

`resolve_fixes` dice order: ships by ship_id, effects by `seq`; each fixable effect rolls d10; success if `d10 + skill_modifier(cq) <= unfouling_success_max(attempts+1)`. Struck ships do not roll. Then `crew_disorganized.turns_left -= 1` (removed at 0); `sheets_cut` with `expires_after_turn <= current_turn` is removed (inflicted on turn T ⇒ affects T+1's movement, removed in T+1's STATUS_ADJUSTMENT).

### 3.3 Fire (8.E out of scope)
Hull #10 (d10 ≥ 6 ± SK) and #12 increment `ShipState.fires`, log `FIRE_STARTED`, note the table MC. No spread, damage or firefighting. #12 explosion roll (2d10 + DRMs < class) is rolled and logged on the CRITICAL_HIT event (`explosion: {roll, modifier, total, needed, explodes}`); on "explodes" the ship is **destroyed** (`DamageController.destroy`, status `DESTROYED`, `DESTROYED` event; §0 Q2 supersedes the earlier "strikes" plan). Explosion DRM "each existing fire −2" reads `fires` before the increment.

### 3.4 `PhaseEvents.Type` additions and log text

| Type | Data | Text (example) |
|---|---|---|
| `CRITICAL_ROLL` | `{d6, ch_mod, ch_number, hit}` | "Vengeance: critical hit roll 3 −2 = 1 ≤ 4 — critical hit!" / "… 6 +0 = 6 > 4, no critical" |
| `CRITICAL_HIT` | `{source: gunfire/rigging_check/hull_check/hull_7, table, roll, result_id, side, sub_rolls, ignored_reason}` | "Vengeance: hull critical 9 — guns dismounted −2 (port)"; "rigging check 4 — lines jammed"; "rigging critical 4 — braces cut (ignored: dismasted)" |
| `CRITICAL_FIXED` | `{result_id, side, roll, modifier, needed, success}` | "Vengeance fixes the port broadside obscured (3 −2 = 1 ≤ 2)" / "fails to clear jammed lines (7 −2 = 5 > 2)" |
| `CRITICAL_ENDED` | `{result_id}` | "Vengeance: sheets cut repaired" / "section 4 reorganized" |
| `FIRE_STARTED` | `{roll, needed, fires}` | "Vengeance is afire (not yet simulated)" |
| `POOR_MANEUVERING` | `{roll, needed, success}` (movement) | "Vengeance's damaged steering fails the turn (7 > 5) — one hex ahead" |

Box losses keep using `DAMAGE` (with `source_id` and a `cause: "critical"` field); MCs use `MORALE_NOTED` with trigger text "critical hit".

---

## 4. UI touchpoints (minimal; choices are questions)

1. **Ship status panel** (`ship_status_panel.gd` `_update_display`): one line per active effect, e.g. "Braces cut (fix roll in maintenance)", "Port broadside −2 (obscured)", "Rudder destroyed — poor maneuvering", "Section 4 disorganized (2 turns)", "Afire ×1 (not simulated)". *Q: one compact comma list, or one line each?*
2. **Combat log** (`combat_log_panel.gd` via `PhaseEvents` text): the texts in §3.4. *Q: show failed `CRITICAL_ROLL`s (natural 6, no crit) or hide them?*
3. **Fire panel**: the modifier list already renders `modifier_label`; add "broadside obscured". No new widget.
4. **Planning UI** (`planning_phase_ui.gd`): MA and accel/decel range already shown from the validator; add a poor-maneuvering chance next to turn steps like the tacking chance. *Q: needed in the first cut?*
5. **Map markers**: *Q: add a small icon/badge on ships with active crits (fire, rudder) or rely on the status panel only?* Recommendation: none in the first cut.

---

## 5. Implementation plan (each step: GUT tests with `ScriptedDice`, `make test`, both validators)

1. **Data:** `critical_hits_table.json`, `poor_maneuvering_table.json`, `CombatTables` accessors, validator checks, `test_combat_tables.gd` spot checks.
2. **State:** `ShipState` fields + helpers + serialization; `ShipStateController` mutators with server guards.
3. **Controller skeleton + gunfire trigger:** `CriticalHitController`, `CRITICAL_ROLL`/`CRITICAL_HIT` events, `GunneryResolver` hook, dice-order doc. Results that only remove boxes or add guns dismounted: hull #5, #6, #8, #9, #11, rigging #3, #6 (box part), #8, #9 (box part), #10 (box part), #12.
4. **RC/HC checks:** section-emptied detection in `DamageController`, queue + drain, collision path, 7.D.12 chaining, ◆/[D]/dismasted rules, stern-rake both sides, engaged side.
5. **Gunfire effects:** obscured/yard −2 in `GunneryCalculator`; `resolve_fixes` in STATUS_ADJUSTMENT (8.D.5).
6. **Movement effects:** MP loss (sheets, shrouds), `get_speed_change_limits` (braces, sheets, plus 5.E.5 base reductions if approved), sheets-cut expiry.
7. **Sail and crew:** lines jammed (refuse/abort/auto-fix on dismasting), crew disorganized (cancel change, reorganize countdown, sections firing).
8. **Steering:** rudder destroyed/jammed, wheel shot away, one-turn limit, RJ direction rules in the validator, poor maneuvering roll in the resolver (6.F.3–5), tacking/bearing-off DRMs, bow-rake conversion.
9. **Fire stub and explosion roll**, mast may fall, stays cut, mast falls on deck (section crossing).
10. **UI** per §4 answers; `feature_diff.md` (§1 item 1 → Partly fixed/Fixed, §2.1 row, §2.2 5.E.5 row, §3 tacking/bearing-off rows, §5), CLAUDE.md "Not implemented" line; `scv-reviewer`.

### Test list (expected values from the rules/charts)

| # | Setup | Expected | Rule |
|---|---|---|---|
| 1 | FGN 40, gunnery d6 6, CH d6 6, target CH mod −2 | 6 − 2 = 4 ≤ 5 ⇒ crit | 7.D.11, scen. book G-T 8 |
| 2 | FGN 40, d6 6, CH d6 6, CH mod 0 | 6 > 5 ⇒ no crit; one CRITICAL_ROLL logged | 7.D.11 |
| 3 | FGN 6 (CH# ≤0), d6 6, CH d6 2, CH mod −2 | 0 ≤ 0 ⇒ crit | CH# column |
| 4 | gunnery d6 5 | no CH d6 consumed | 7.D.11 |
| 5 | Aim low, 2d6 = 9 | hull crit −2 guns dismounted engaged side only | hull #9 |
| 6 | Same, stern rake | −2 on **both** sides | 7.E.5b |
| 7 | Aim low, dismantling shot | no hull crit roll at all | 7.C.12b |
| 8 | Aim high DS, 2d6 = 10 | yard shot away ignored ([D]) | rigging notes |
| 9 | Hull section 1 emptied, HC d6 = 3 | hull #7 ⇒ rigging 2d6 rolled | 7.D.8a, hull chart |
| 10 | Rigging section emptied, RC d6 = 6 | sheets cut: next turn MA −1, accel −1 (type B: 2 → 1) | 7.D.7, 5.E.6 |
| 11 | Two sheets cut same turn | only one effect | rigging #7 |
| 12 | Type C (accel 3) braces cut | accel 1, decel 1 | 5.E.5 |
| 13 | 3 rigging sections left + shrouds + sheets (Majestic G-T 17 case) | MA reduced by 2 | rigging #7, #9 |
| 14 | Rigging #6, target at PS, d6 4 | 2R lost, starboard −2 on that ship's shots | 7.C.11 |
| 15 | Fix: CQ B, attempt 1, d10 4 | 4 − 2 = 2 ≤ 2 ⇒ fixed; d10 5 ⇒ fails; 2nd attempt d10 5 ⇒ 3 ≤ 3 fixed | 8.D.5, Unfouling |
| 16 | Lines jammed during MS→PS change | change cancelled "lines jammed"; plotting refused | 5.F.9c |
| 17 | Lines jammed, then dismasted | effect removed | rigging #5 |
| 18 | Class 2 ship hull #11, S2 has 2 boxes | 2 from S2 + 1 from S3; S2 empty ⇒ MC noted | 7.D.12 example |
| 19 | Class 3 frigate hull #11 | 2 sailor boxes | hull #11 |
| 20 | Rigging #12 on class 3, 1 marine left | section crossed out; 1 marine + 1 sailor lost; RC for the section; MC | rigging #12, 7.D.12 |
| 21 | Stays cut, speed 4, d10 3 | section crossed out, MC, then 1R from next section | rigging #11 |
| 22 | Mast may fall: MS, 1 section lost, WS 4, d6 5 | 5+1+1+1 = 8 ≥ 8 ⇒ next section crossed out ⇒ another RC | rigging #2 |
| 23 | Braces cut on a ship that became dismasted this combat phase | ignored (◆) | rigging notes |
| 24 | Ship dismasted before the combat phase, aim high crit | no rigging crit | rigging note |
| 25 | Bow rake, hull 2d6 = 2 | 1H instead of rudder | 7.E.6 |
| 26 | Rudder d6 2 then later d6 5 | destroyed; jammed ignored | hull #2 |
| 27 | Poor maneuvering, type B, CQ E, plot S2S, d10 5 | fails (> 4): plot becomes 1S2 | 6.F.3 example |
| 28 | Poor maneuvering, plot 4S, fail | moves 5; next turn first MP is S, auto-success | 6.F.4 ex. 1 |
| 29 | Wheel shot away, plot P1P | second pivot refused | hull #3 |
| 30 | Tacking with rudder destroyed | DRM +3 | Tacking chart |
| 31 | Bearing off, RD | +3 +1 = +4 (Open q. 8) | Bearing Off chart |
| 32 | Hull #4 on class 3, sections 1–4 manned | 1 sailor lost; section 4 disorganized; turns = 5 + SK (CQ B: 3) | hull #4 |
| 33 | Hull #10, CQ B, d10 7 | 7 − 2 = 5 < 6 ⇒ no fire (if "± SK" adds SK mod; Open q. 9) | hull #10 |
| 34 | Hull #12, CQ D, no fires, class 2, 2d10 = 1 | 1 < 2 ⇒ explodes ⇒ destroyed (§0 Q2) | hull #12 |
| 35 | Crit MC twice in one turn | two MCs noted (unique triggers) | 9.B.1e |
| 36 | Collision empties rigging section 1 | RC rolled in MOVEMENT_RESOLUTION | 7.D.7, 6.E.3 |

---

## 6. Open questions

1. ~~**7.D.11 OCR**~~ Settled: PDF p.25 reads "± the target's CH mod … ≤ the critical hit number"; the text is corrected in `close_action.md`.
2. **Explosion (hull #12)** without 8.E: strike the ship ("exploded"), remove it from the map, or log only? No blast damage either way. Answer: Remove from play but keep the model visible on the map as an obstruction that can be hit, change the model to a "destroyed model with debris" and update the ship state.
4. Do **[D]** exemptions apply to RC/HC checks caused by a dismantling-shot hit (e.g. RC 1 "mast may fall")? Proposal: no — [D] filters only the shot's own crit. Answer: approved the proposed answer that [D] only filters own crit.
5. **Hull section 4** loss strikes the ship in Leeward. Roll its HC anyway (effects on a struck ship are mostly moot)? Proposal: skip. Answer: approved the proposed answer to skip.
6. **Crew disorganized**: Leeward has no crew tasks. Proposal: the section cannot work sail and does not count for "sections firing" until reorganized. Count down 5 + SK mod g-ts automatically (no RO plot)? Answer: mark this as something to come back to when planning crew tasks feature is designed and implemented. Update the rules_diff.md to keep track of this.
7. Implement the missing **5.E.5 base reductions** (two rigging sections lost, WS 1, towing) in the same helper now? Answer: Yes
8. **Braces Cut decel exception "by changing sail state"**: allow a larger decel on a turn when a sail change completes? Proposal: ignore (sail changes complete after movement). Answer: approved your proposal to ignore.
9. **Bearing off with Rudder Destroyed**: RD is also poor maneuvering — +3 and +1 (= +4), or +3 only? Answer: yes
10. **Hull #10 "≥ 6 (± SK)"**: is SK added to the d10 (CQ A, −3, makes fire less likely) or to the 6? Proposal: d10 + SK mod ≥ 6. Answer: approved your proposal Answer: Same as #6. mark this as something to come back to when planning crew tasks feature is designed and implemented. Update the rules_diff.md to keep track of this.
12. **Engaged broadside** for non-rake fire from outside the target's arcs (beyond range 5): side by relative bearing, d6 on the centre line? Answer: Yes
13. **"Bow arc"** for 7.E.6: treat as `rake == "bow"` only, or any firer forward of the target's beam line? Answer: Yes, treat as `rake == "bow"`
14. **Scenario year** DRM for #12 (≤ 1783 −1): scenarios have no year; add an optional `year` to scenario JSON? Answer: Yes
15. **Rudder Jammed "last MP used"**: the last plotted step at the time of the crit (current turn's movement) — confirm. Answer: confirmed
16. Signal halyards cut has no effect until signalling exists — keep it as a fixable no-op effect? Answer: mark this as something to revisit when signaling is implemented. Update the rules_diff.md
