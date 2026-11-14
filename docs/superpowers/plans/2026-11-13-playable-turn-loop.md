# Playable Turn Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Leeward playable from turn 1 to a declared winner against the AI: sail changes, gunnery, damage, drift, unfouling, morale, striking and victory, on the 1997 Close Action tables.

**Architecture:** Rule tables become JSON under `data/rules/` read through a new `CombatTables` object owned by `DataManager`. Each stubbed phase gets a small server-side resolver class (RefCounted, constructed by `GameState`, takes `game_state` like the existing controllers) that mutates state only through `ShipStateController` and appends typed events to a per-turn `PhaseLog`. `TurnPhaseController` gains two waits (fire declaration, End Turn) and calls the resolvers; the view layer reads the log.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5.0 (`make test`, `make test-file F=...`), Python 3 table validator.

**Spec:** `docs/superpowers/specs/2026-11-13-playable-turn-loop-design.md` — read it first; section numbers below (§) refer to it.

## Global Constraints

- Work on a new branch `feature/playable-turn-loop` cut from `main` (or an isolated worktree).
- Server authority: every mutating method starts with `if not is_server: push_error(...); return`. State changes go through `ShipStateController`. View/UI code never mutates game state.
- No raw `print()` in runtime code — use `Trace.trace_log(tag, msg)` (a hook blocks `print`).
- All randomness comes from `Dice` (Task 1) built on `game_state.rng`. d10 is **0–9**; 2d10 is 0–18.
- After creating any script with a new `class_name`, run `make import` before running tests, or the headless runner will not know the class.
- Tables are transcribed from the 1997 chart scans in `docs/*.jpeg` (same charts: PDF pages 106–113 of `docs/CoA_-_Close_Action_the_Age_of_Fighting_Sail_vol_1_1997.pdf`). Never take a number from `docs/Close-Action-Rules-v6-1.txt` or `docs/07-naval-combat-mechanics.md`.
- Where the 1997 rule text and chart disagree, the chart wins (two-target modifier is −12).
- The `GamePhase` enum is not changed.
- An edit under `scripts/server|state|core|autoload` or `test/unit` triggers `make test` automatically; keep the suite green at every commit.
- Side indices everywhere: `PORT = 0`, `STARBOARD = 1`. Sail order: `["NS", "FS", "MS", "PS"]`. Crew quality letters `A`–`G`.
- New server objects are created in `GameState._initialize_server_controllers()` under exactly these names: `dice`, `fire_geometry`, `gunnery_calculator`, `damage_controller`, `gunnery_resolver`, `sail_controller`, `drift_resolver`, `fouling_controller`, `morale_controller`, `victory_controller`. Each takes `game_state` in `_init` and reaches its collaborators through it. Tests that need scripted rolls assign `GameState.dice` a `ScriptedDice` (a `Dice` subclass returning queued values; define it once in `test/unit/scripted_dice.gd`).
- Follow `.claude/skills/phase-implementer/` when touching a phase method. Run the `scv-reviewer` agent once, in the final task only.

## Review Focus

Failure modes the spec implies but does not spell out; each has a pinning test in the task named.

1. **Invalid fire orders** (target outside the arc, struck target, two orders for one side, range 10+ aimed low, another player's ship): rejected with a reason, state untouched, the phase still waits. → Task 11.
2. **A player with nothing to do** (all ships fouled, struck or dismasted; or no eligible targets on one side only): planning and fire declaration must still complete and the turn advance. → Tasks 11, 17.
3. **Table edges**: total gunnery factor 0, guns dismounted exceeding the number, modified number negative, final number above 52, grey BGN cell. No error, no shot or a clamped row. → Tasks 5, 8, 10.
4. **Drift at the map edge or into a blocked hex**: treated as blocked, never off-map, never two ships in one hex. → Task 13.
5. **Old snapshots / scenario files without the new fields** (`deserialize`, state history, scenarios that still say `crew_morale`): load with defaults, no null errors. → Task 3.

---

## File Map

**Create**
- `scripts/server/dice.gd` — `Dice`: all die rolls.
- `scripts/autoload/combat_tables.gd` — `CombatTables`: loads and looks up the eight new tables.
- `data/rules/{gunnery_factor_table,basic_gunfire_number_table,gunfire_results_table,gunfire_modifiers,crew_loss_table,drifting_table,unfouling_table,crew_quality_table}.json`
- `.claude/skills/validate-rule-table/scripts/validate_combat.py`
- `scripts/server/phase_events.gd` — `PhaseEvents.PhaseEvent`, `PhaseEvents.PhaseLog`.
- `scripts/core/fire_geometry.gd` — `FireGeometry`: arcs, line of sight, rake (pure).
- `scripts/server/gunnery_types.gd` — `GunneryTypes.FireOrder`, `GunneryTypes.ShotPreview`.
- `scripts/server/gunnery_calculator.gd` — `GunneryCalculator`: eligibility, modified number, order validation (pure queries).
- `scripts/server/damage_controller.gd` — `DamageController`: applies hits, dismounts guns, notes morale checks, strikes.
- `scripts/server/gunnery_resolver.gd` — `GunneryResolver`: simultaneous fire.
- `scripts/server/sail_controller.gd` — `SailController`.
- `scripts/server/drift_resolver.gd` — `DriftResolver`.
- `scripts/server/fouling_controller.gd` — `FoulingController`: unfouling rolls.
- `scripts/server/morale_controller.gd` — `MoraleController`.
- `scripts/server/victory_controller.gd` — `VictoryController`.
- `scripts/ui/fire_declaration_panel.gd` + `scenes/ui/fire_declaration_panel.tscn`
- `scripts/ui/combat_log_panel.gd` + `scenes/ui/combat_log_panel.tscn`
- `scripts/ui/game_over_panel.gd` + `scenes/ui/game_over_panel.tscn`
- One `test/unit/test_<name>.gd` per new class.

**Modify**
- `data/rules/ships.json`, `data/rules/movement_allowance.json`, `data/scenarios/test_basic.json`, `data/scenarios/test_fleet.json`
- `scripts/state/ship.gd`, `scripts/state/ship_state.gd`
- `scripts/server/ship_state_controller.gd`, `environment_controller.gd`, `movement_resolver.gd`, `movement_validator.gd`, `movement_plotting_controller.gd`, `turn_phase_controller.gd`, `stub_ai.gd`
- `scripts/autoload/data_manager.gd`, `scripts/autoload/game_state.gd`
- `scripts/core/game_controller.gd`, `scripts/ui/planning_phase_ui.gd`, `scripts/ui/ship_status_panel.gd`, `scripts/ui/ship_list_item.gd`, `scripts/view/hex_overlay.gd`, `scripts/view/ship_view.gd`
- `.claude/skills/validate-rule-table/scripts/validate.py`, `CLAUDE.md`, `docs/07-naval-combat-mechanics.md`
- Existing tests named in each task.

---

# Stage A — Foundations

### Task 1: Dice helper and wind-roll fixes

**Files:** Create `scripts/server/dice.gd`, `test/unit/test_dice.gd`. Modify `scripts/server/environment_controller.gd`, `scripts/autoload/game_state.gd`, `test/unit/test_rng_determinism.gd` (only if its expected values change).

**Interfaces — Produces:**
```gdscript
class_name Dice extends RefCounted
func _init(p_rng: RandomNumberGenerator) -> void
func d6() -> int        # 1..6
func d10() -> int       # 0..9
func two_d6() -> int    # 2..12
func two_d10() -> int   # 0..18
```
`GameState.dice: Dice`, created in `start_new_game` right after `rng` is seeded (and in `_initialize_server_controllers` with a default RNG so tests that skip `start_new_game` still have one).

- [ ] **Step 1: Write failing tests** in `test/unit/test_dice.gd`:
  - `test_d10_range_is_0_to_9`: 500 rolls, `min == 0`, `max == 9`.
  - `test_d6_range_is_1_to_6`, `test_two_d10_range_is_0_to_18` (2000 rolls).
  - `test_same_seed_same_sequence`: two `Dice` on RNGs seeded 7 produce identical 20-roll sequences.
- [ ] **Step 2:** `make import && make test-file F=test/unit/test_dice.gd` → FAIL (class missing).
- [ ] **Step 3:** Implement `Dice`.
- [ ] **Step 4: Write failing tests** in a new `test/unit/test_environment_controller.gd` for the two chart errors (§6.6). Add a seam: `EnvironmentController._update_wind_speed` and `_update_wind_direction` take their rolls from `game_state.dice`; tests inject `ScriptedDice` (create `test/unit/scripted_dice.gd` here: `class_name ScriptedDice extends Dice`, `func queue(values: Array) -> void`; `d6()`/`d10()` pop the next queued value, `two_d6()`/`two_d10()` pop two and add them; popping an empty queue fails the test with `push_error`).
  - `test_wind_speed_followup_low_roll_decreases`: steady, speed 2, 2d10 parts `[0, 1]` (sum 1 → changes), follow-up d10 `3` → speed 1.
  - `test_wind_speed_followup_high_roll_increases`: same but follow-up `7` → speed 3.
  - `test_coastal_direction_changes_on_2_or_3`: region `coastal`, 2d10 sum 3, follow-up `2` → direction −1 (mod 6); 2d10 sum 5 → unchanged.
  - `test_oceanic_direction_changes_on_0_or_1` and `test_reverts_on_16_to_18` (existing behaviour, now on 0–18).
- [ ] **Step 5:** Rewrite the two methods on `Dice` with chart thresholds: speed changes on sum ≤1 (steady) / ≤3 (gusty), follow-up 0–4 → −1, 5–9 → +1; reverts on sum ≥16; direction oceanic changes on ≤1, coastal on 2–3, follow-up 0–4 left (−1), 5–9 right (+1); reverts on ≥16. Keep the 0–4 clamp on speed.
- [ ] **Step 6:** `make test` → all pass (update seeded expectations in `test_rng_determinism.gd` only if they compare concrete wind values).
- [ ] **Step 7:** Commit `feat: Dice helper; fix wind follow-up and coastal rolls against 1997 chart`.

### Task 2: Ship data and roster from the Ship Data Chart

**Files:** Modify `data/rules/ships.json`, `scripts/state/ship.gd`, `scripts/autoload/data_manager.gd` (`_create_default_ships`), both scenario JSONs, `test/unit/test_data_manager_ships.gd`, `test_data_manager_scenarios.gd`, `test_stub_ai.gd` and any other test naming `corvette_24`.

**Interfaces — Produces** on `Ship` (all set in `from_dict`, emitted by `to_dict`):
```gdscript
var gun_factors: Dictionary   # {"lg": int, "mg": int, "cr": int} — per side
var ch_modifier: int
var freeboard: int
var lower_deck_modifier: int
var point_costs: Dictionary   # e.g. {"A3": 54, "B3": 48, ...}
func is_french_gunned() -> bool            # nationality == "French"
func point_value(crew_quality: String, morale_rating: int) -> float
```
`point_value`: exact key `"<CQ><MR>"`; else same CQ with nearest MR; else the lowest value in the row.

Rows to enter (from `docs/ship_data_chart.jpeg`, British section; `mg` is 0 for all):

| id | class | man. | speed_type | draft | CH | rigging | hull | crew S1–S4 : M | LG | CR | F | L | costs A3 B3 C3 C4 C5 D4 D5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `frigate_38` | 3 | C | F/F | 18 | −2 | 5 5 6 6 | 5 5 5 6 | 3 3 3 3 : 2 | 6 | 4 | 6 | −7 | 54 48 43 42 41 38 36 |
| `ship_of_line_74` | 2 | B | L/F | 22 | 0 | 7 7 7 7 | 8 8 9 9 | 6 6 6 6 : 5 | 17 | 1 | 4 | −5 | 99 88 79 77 75 71 69 |
| `frigate_32` | 3 | C | F/S | 16 | −2 | 4 5 5 5 | 4 4 4 5 | 2 2 2 3 : 2 | 4 | 2 | 5 | −7 | 37 33 30 29 28 26 25 |

Keep each ship's existing `guns` block as display-only data (rename the key to `armament`); give `frigate_32` `"armament": {}`.

- [ ] **Step 1: Failing tests** (`test_data_manager_ships.gd`): `frigate_38.gun_factors == {"lg":6,"mg":0,"cr":4}`; `ship_of_line_74.ship_class == 2` and `hull_hp == [8,8,9,9]`; `frigate_32` exists with `rigging_hp == [4,5,5,5]`; `get_ship_definition("corvette_24") == null`; `frigate_38.point_value("D", 4) == 38.0`; `point_value("D", 6) == 36.0` (nearest MR); `point_value("G", 4) == 36.0` (row minimum). Verify against the property name `Ship` actually uses for class.
- [ ] **Step 2:** Run the file → FAIL.
- [ ] **Step 3:** Update `ships.json`, `Ship`, `_create_default_ships`. In both scenarios replace `"ship_type": "corvette_24"` with `"frigate_32"`. Fix other tests that referenced the corvette.
- [ ] **Step 4:** `make test` → pass.
- [ ] **Step 5:** Commit `feat: ship data from 1997 Ship Data Chart; replace corvette with 32-gun frigate`.

### Task 3: ShipState fields and controller mutators

**Files:** Modify `scripts/state/ship_state.gd`, `scripts/server/ship_state_controller.gd`, `scripts/autoload/game_state.gd` (`_update_ship_from_data`, snapshots), `scripts/ui/ship_status_panel.gd` and `ship_list_item.gd` (rename only). Create `test/unit/test_ship_state.gd`.

**Interfaces — Produces** on `ShipState`:
```gdscript
enum Status { ACTIVE, STRUCK }
const PORT := 0
const STARBOARD := 1
const SAIL_ORDER: Array[String] = ["NS", "FS", "MS", "PS"]
var crew_count: Array[int]            # 4 sailor sections
var morale_rating: int = 4            # replaces crew_morale
var status: Status = Status.ACTIVE
var guns_dismounted: Array[int] = [0, 0]          # positive counts per side
var initial_broadside_fired: Array[bool] = [false, false]
var sail_change: Dictionary = {}      # {} or {"target": String, "turns_left": int, "sections": Array[int]}
var moved_this_turn: bool = false
var pending_morale_checks: int = 0
var morale_triggers_used: Array[String] = []
var unfoul_attempts: int = 0
func is_struck() -> bool
func is_dismasted() -> bool           # all rigging boxes 0
func rigging_level() -> int           # sections with >= 1 box, 0..4
func total_crew_boxes() -> int        # sailors + marines
func sections_able_to_fire() -> int   # sailor sections with boxes and not in sail_change.sections
```
On `ShipStateController` (each server-guarded, emits `ship_state_changed`, returns `bool`):
```gdscript
func set_status(ship_id: String, status: ShipState.Status) -> bool
func add_guns_dismounted(ship_id: String, amount: int) -> bool      # both sides
func set_initial_broadside_fired(ship_id: String, side: int) -> bool
func set_sail_change(ship_id: String, change: Dictionary) -> bool
func set_moved_this_turn(ship_id: String, moved: bool) -> bool
func remove_crew_box(ship_id: String, marine: bool) -> int   # returns sailor section index emptied (0-3), 4 if marines emptied, -1 otherwise
func note_morale_check(ship_id: String, trigger: String, count: int = 1) -> bool  # false if trigger already used
func clear_pending_morale_checks(ship_id: String) -> bool
func set_crew_quality(ship_id: String, quality: String) -> bool
func set_unfoul_attempts(ship_id: String, attempts: int) -> bool
```
`remove_crew_box(marine=false)` takes from the lowest-numbered sailor section with boxes; if that type has none it takes the other type. `set_fouled_with` additionally resets `unfoul_attempts` to 0 on both the new and cleared value.

- [ ] **Step 1: Failing tests** (`test_ship_state.gd`, building a ship from `DataManager.get_ship_definition("frigate_38")` through `initialize_from_scenario`):
  - `test_crew_initialised_from_definition`: `crew_count == [3,3,3,3]`, `marine_count == 2`.
  - `test_scenario_crew_quality_word_normalised`: scenario `"crew_quality": "Trained"` → `"D"`.
  - `test_morale_rating_reads_legacy_key`: scenario with only `"crew_morale": 3` → `morale_rating == 3`.
  - `test_rigging_level_counts_sections_with_boxes`: `[0,5,6,6]` → 3; `[0,0,0,0]` → 0 and `is_dismasted()`.
  - `test_sections_able_to_fire_excludes_sail_change_and_empty`: crew `[0,3,3,3]`, `sail_change.sections == [3]` → 2.
  - `test_serialize_round_trip_keeps_new_fields`.
  - `test_deserialize_old_snapshot_uses_defaults` *(Review Focus 5)*: a dict with none of the new keys → `status == ACTIVE`, `guns_dismounted == [0,0]`, `sail_change == {}`, no error.
  - `test_remove_crew_box_order`: sailor boxes come off section 0 first; returns `0` when it empties; with no marines, `marine=true` takes a sailor.
  - `test_note_morale_check_once_per_trigger`: second call with `"hull_1"` returns false, `pending_morale_checks` stays 1.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Replace `crew_morale` everywhere (`grep -rn crew_morale scripts test`); `set_crew_morale` becomes `set_morale_rating`. Remove the dead `set_crew_count(ship_id, count: int)` if nothing calls it.
- [ ] **Step 4:** `make test` → pass.
- [ ] **Step 5:** Commit `feat: ShipState combat fields, crew initialisation, controller mutators`.

### Task 4: Rigging level and sail availability

**Files:** Modify `data/rules/movement_allowance.json`, `.claude/skills/validate-rule-table/scripts/validate.py`, `scripts/server/ship_state_controller.gd`, `scripts/server/movement_validator.gd`, `scripts/state/ship_state.gd`, `test/unit/test_data_manager_movement.gd`, `scripts/ui/ship_status_panel.gd`.

**Interfaces — Produces:**
```gdscript
# ShipState
func max_sail_state() -> String        # level 4 "PS", 3 "MS", 2-1 "FS", 0 "NS"
func movement_sail_state() -> String   # the lower (in SAIL_ORDER) of sail_state and max_sail_state()
# ShipStateController
func get_rigging_quality(ship_id) -> int   # now returns ship.rigging_level(), 0..4
```
`get_movement_allowance` and `MovementValidator._build_plotting_state` use `movement_sail_state()` and return MA 0 at level 0 without consulting the table.

- [ ] **Step 1: Failing tests:** in `test_data_manager_movement.gd` change `test_rigging_quality_2_close_hauled` to expect `get_movement_allowance("F/F", 2, "C", "fs", 2) == 1` and add `("F/F", 3, "B", "fs", 1) == 3`, `("L/F", 4, "R", "fs", 2) == 3` (chart values). In `test_ship_state.gd` add: rigging `[0,5,6,6]` carrying `"PS"` → `max_sail_state() == "MS"`, `movement_sail_state() == "MS"`, `sail_state` still `"PS"`; rigging `[0,0,6,6]` → `"FS"`. Add a `test_movement_validator.gd` case: a dismasted ship gets MA 0.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Write a one-off Python snippet (not committed) that, for every `speed_type/facing/wind/level` with level `"1"` or `"2"`, renames a lone `ps` (or `ms`) key to `fs`. Extend `validate.py` to require exactly `{fs,ms,ps}` at level 4, `{fs,ms}` at 3, `{fs}` at 2 and 1. Run `python3 .claude/skills/validate-rule-table/scripts/validate.py` → clean. Spot-check 6 cells against `docs/movement_1.jpeg`.
- [ ] **Step 4:** Implement the state/controller/validator changes.
- [ ] **Step 5:** `make test` → pass. Commit `feat: rigging level by sections remaining; fix low-rigging movement table keys`.

### Task 5: Combat tables as data

**Files:** Create the eight JSON files, `scripts/autoload/combat_tables.gd`, `validate_combat.py`, `test/unit/test_combat_tables.gd`. Modify `scripts/autoload/data_manager.gd` (own and load a `CombatTables`).

**Formats** (each file may carry a `_doc` string):
- `gunnery_factor_table.json`: `{"lg": [15 numbers], "mg": [...], "cr": [...]}` indexed by range−1; `0` = cannot fire. `cr` is `[2,2,2,1.5,1,0.5,0,0,0,0,0,0,0,0,0]`.
- `basic_gunfire_number_table.json`: `{"rows": [{"tgf_min": 1, "tgf_max": 1, "bgn": [15 ints or null], "french": [5 ints or null]}, ...]}`; `bgn[i]` is range i+1, `null` = grey; `french[j]` is range 11+j (the small numbers). Last row `tgf_min: 31, tgf_max: 999`.
- `gunfire_results_table.json`: `{"rows": [{"fgn": 1, "ch": 0, "low": {"fs": "", "ms": "", "ps": ""}, "high": {...}}, ... 52 rows]}`. Result grammar: tokens joined by `-`; a token is `<count?><r|h|c>` or two alternatives joined by `/` where `.` means nothing (`"h-c/."` = one hull, then crew-or-nothing). Empty string = no damage.
- `gunfire_modifiers.json`: `{"crew_quality": {"A": 6, "B": 4, "C": 2, "D": 0, "E": -2, "F": -4, "G": -6}, "sections_firing": {"4": 0, "3": -3, "2": -6, "1": -9}, "rake": [4,4,3,2,1], "initial_broadside": [4,4,3,2,1], "two_targets": -12, "plain_sail": -1, "dismantling_shot": 1, "anchored": 1, "wind_speed_4": <read from chart>}`.
- `crew_loss_table.json`: `{"gunfire_at_hull": {"sailor_max": 5}, "other": {"sailor_max": 3}}`.
- `drifting_table.json`: `{"ps": [null,4,3,2,0], "ms": [null,6,5,4,2], "fs": [null,7,6,5,3], "ns": [null,8,7,6,4], "dismasted": [null,10,9,8,6], "class_drm": {"3": 1, "4": 2}}` indexed by wind speed; `null` = never, `0` = automatic.
- `unfouling_table.json`: `{"success_max": [2, 3, 4]}`.
- `crew_quality_table.json`: `{"A": {"sk": -3, "bcf_sailor": 8, "bcf_marine": 10}, ... "G": {"sk": 3, "bcf_sailor": 2, "bcf_marine": 4}}`.

**Interfaces — Produces** (`DataManager.combat_tables: CombatTables`, loaded in `DataManager._ready()`):
```gdscript
class_name CombatTables extends RefCounted
func load_all(dir: String = "res://data/rules/") -> bool
func gunnery_multiplier(gun_type: String, range_hexes: int) -> float   # 0.0 beyond the table
func basic_gunfire_number(tgf: int, range_hexes: int, french: bool) -> int   # -1 = cannot fire
func gunfire_result(fgn: int, aim: String, column: String) -> Array   # of tokens; each token = Array of alternatives; alternative = {} or {"type": "r"|"h"|"c", "count": int}
func critical_hit_number(fgn: int) -> int
func crew_quality_modifier(crew_quality: String) -> int
func sections_firing_modifier(sections: int) -> int
func range_bonus(kind: String, range_hexes: int) -> int   # kind "rake" | "initial_broadside"; 0 beyond range 5
func flat_modifier(name: String) -> int
func crew_loss_is_sailor(cause: String, d6: int) -> bool   # cause "gunfire_at_hull" | "other"
func drift_number(sail_key: String, wind_speed: int) -> int   # -1 = never drifts
func drift_class_drm(ship_class: int) -> int
func unfouling_success_max(attempt: int) -> int   # attempt 1, 2, 3+
func skill_modifier(crew_quality: String) -> int
```
`gunfire_result`: `fgn < 1` → `[]`; `fgn > 52` → row 52.

- [ ] **Step 1: Failing tests** (`test_combat_tables.gd`):
  - Multipliers: `("lg", 15) == 1.0`, `("cr", 4) == 1.5`, `("cr", 7) == 0.0`, `("mg", 11) == 0.5`.
  - BGN: `(14, 1, false) == 24`, `(12, 4, false) == 20`, `(8, 6, false) == 13`, `(6, 7, false) == 9`, `(6, 10, false) == 4`, `(6, 15, false) == -1`, `(19, 1, false) == 27`, `(8, 11, false) == 5`, `(8, 11, true) == 6`, `(31, 1, false) == 32`, `(500, 9, false) == 20`, `(1, 8, false) == -1`.
  - Results: row 1 all columns `[]` and `critical_hit_number(1) == 0`; row 30 low fs parses to r×2, h×1, c×1 and `critical_hit_number(30) == 3`; row 52 low fs = r×9, h×12, c×6; high fs = r×14, h×3, c×3; `gunfire_result(60, "low", "fs") == gunfire_result(52, "low", "fs")`; `gunfire_result(0, "low", "fs") == []` *(Review Focus 3)*; a slashed cell parses to a token with two alternatives.
  - Modifiers: `crew_quality_modifier("A") == 6`, `("G") == -6`; `sections_firing_modifier(1) == -9`; `range_bonus("rake", 3) == 3`, `("rake", 6) == 0`; `flat_modifier("two_targets") == -12`.
  - Crew loss: `("gunfire_at_hull", 5)` true, `(…, 6)` false; `("other", 3)` true, `(…, 4)` false.
  - Drift: `("ps", 4) == 0`, `("dismasted", 1) == 10`, `("ms", 0) == -1`; `drift_class_drm(3) == 1`, `(2) == 0`.
  - Unfouling: `(1) == 2`, `(2) == 3`, `(7) == 4`. Skill: `("A") == -3`, `("D") == 0`, `("G") == 3`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3: Transcribe** the tables from `docs/gunfire_tables_2.jpeg`, `docs/gunfire_tables.jpeg`, `docs/combat_tables_1.jpeg` (zoom in; the PDF pages 109–111 are the same charts at higher resolution). Read `wind_speed_4` from the "Other modifiers" block of the Gunfire Results chart.
- [ ] **Step 4:** Implement `CombatTables` (parse result strings once at load) and `validate_combat.py`, which checks: row counts (BGN 22 rows covering TGF 1–31+ with no gaps; results 52 rows, `fgn` 1..52 in order), 15-entry arrays, BGN non-increasing along each row and non-decreasing down each column, `ch` non-decreasing 0..6, every result string matches the grammar, total damage per results row non-decreasing with `fgn` for each aim.
- [ ] **Step 5:** `python3 .claude/skills/validate-rule-table/scripts/validate_combat.py` → clean; `make test-file F=test/unit/test_combat_tables.gd` → pass.
- [ ] **Step 6: Independent second pass.** A different agent (or person) who did not transcribe re-reads every cell of the three gunnery tables against the scans and lists disagreements; fix them and add each corrected cell as a test assertion. Do not skip this: one wrong row silently skews every battle.
- [ ] **Step 7:** Commit `feat: 1997 combat tables as data with validator`.

### Task 6: Phase event log

**Files:** Create `scripts/server/phase_events.gd`, `test/unit/test_phase_events.gd`. Modify `scripts/autoload/game_state.gd`.

**Interfaces — Produces:**
```gdscript
class_name PhaseEvents
enum Type { FIRE, DAMAGE, GUNS_DISMOUNTED, MORALE_NOTED, MORALE_CHECK, STRIKE, DRIFT, FOULED, UNFOUL, SAIL_CHANGE, VICTORY }
class PhaseEvent extends RefCounted:
    var type: Type
    var phase: int            # TurnPhaseController.GamePhase
    var ship_id: String
    var target_id: String
    var data: Dictionary      # type-specific; rolls, modifiers, table row, amounts
    func to_text(ship_names: Dictionary) -> String   # one readable line
    func to_dict() -> Dictionary
class PhaseLog extends RefCounted:
    var turn: int
    var events: Array[PhaseEvent]
    func add(type: Type, phase: int, ship_id: String, data: Dictionary = {}, target_id: String = "") -> PhaseEvent
    func of_type(type: Type) -> Array[PhaseEvent]
    func to_dict() -> Dictionary
```
`GameState.turn_log: PhaseEvents.PhaseLog` — replaced with a fresh log at each turn start; `GameState.turn_logs: Dictionary` keeps finished logs by turn.

`to_text` for `FIRE` must show every number the player needs (§4): e.g. `"Surprise fires starboard at Renard, range 3, low, roundshot: BGN 22 +2 crew +3 initial broadside = 27, d6 4 → 31: 2 rigging, 1 hull, 1 crew"`.

- [ ] **Step 1: Failing tests:** `add` appends in order and sets fields; `of_type` filters; `to_text` of a FIRE event contains `"BGN 22"`, `"= 27"`, `"d6 4"`, `"31"` and both ship names; `to_dict` round-trips through `JSON.stringify` without error.
- [ ] **Step 2–4:** Run (FAIL) → implement → run (PASS).
- [ ] **Step 5:** Commit `feat: per-turn phase event log`.

---

# Stage B — Combat

### Task 7: Fire geometry

**Files:** Create `scripts/core/fire_geometry.gd`, `test/unit/test_fire_geometry.gd`.

**Interfaces — Produces:**
```gdscript
class_name FireGeometry extends RefCounted
const MAX_RANGE := 15
func _init(p_hex_grid: HexGrid) -> void
func bearing_side(from_hex: Vector2i, facing: int, to_hex: Vector2i) -> int   # ShipState.PORT, STARBOARD, or -1 if in neither broadside arc
func rake_type(target_hex: Vector2i, target_facing: int, firer_hex: Vector2i) -> String   # "bow", "stern" or ""
func has_line_of_sight(from_hex: Vector2i, to_hex: Vector2i, occupied: Dictionary) -> bool  # occupied: Vector2i -> anything
func broadside_hexes(hex: Vector2i, facing: int, side: int, max_range: int = MAX_RANGE) -> Array[Vector2i]
```
Geometry (§9.2–9.3): let θ be the angle, measured in world space with `HexGrid.axial_to_world`, between the ship's heading vector (to its neighbour in `facing`) and the vector to the other hex; ε = 0.5°.
- Broadside arc: `60° − ε ≤ θ ≤ 120° + ε`. Starboard is the side of directions `facing+1`, `facing+2`; port is `facing−1`, `facing−2`.
- Rake: bow if `θ < 30° − ε`, stern if `θ > 150° + ε` (θ here is from the *target's* heading to the *firer*). Range limit is the caller's job.
- Line of sight: step N = hex distance; for i in 1..N−1 take the point at i/N along the centre-to-centre line, nudged by +1e-6 and by −1e-6 perpendicular to the line, and round each to a hex. LOS is blocked if for some i **both** rounded hexes are in `occupied` (when the two are the same hex this is the ordinary case).

- [ ] **Step 1: Failing tests** (ship at `(0,0)` facing 0 unless stated; `n(d)` = neighbour in direction d):
  - `bearing_side` to `n(1)` and `n(2)` → STARBOARD; `n(5)`, `n(4)` → PORT; `n(0)`, `n(3)` → −1; a hex 3 steps along direction 1 → STARBOARD; `n(1)+n(2)` offset (due beam, range 2) → STARBOARD; `n(0)+n(1)` offset (30° off the bow) → −1; facing 3: `n(4)` → STARBOARD.
  - `rake_type`: firer at `n(3)` → `"stern"`; two steps along 0 → `"bow"`; `n(2)` → `""`; `n(3)+n(2)` offset (exactly 150°) → `""`; three steps along 3 plus one along 2 (inside the stern wedge) → `"stern"`.
  - LOS `(0,0)`→`(4,0)`: clear when nothing between; blocked with `(2,0)` occupied; endpoints occupied do not block. Edge case `(0,0)`→`(1,1)`: only `(1,0)` occupied → clear; `(1,0)` and `(0,1)` occupied → blocked.
  - `broadside_hexes((0,0), 0, STARBOARD, 2)` contains `n(1)`, `n(2)`, the due-beam range-2 hex, and nothing for which `bearing_side` is not STARBOARD.
- [ ] **Step 2–4:** Run (FAIL) → implement → run (PASS).
- [ ] **Step 5:** Commit `feat: broadside arcs, rake wedges and line of sight`.

### Task 8: Gunnery calculator (pure queries)

**Files:** Create `scripts/server/gunnery_types.gd`, `scripts/server/gunnery_calculator.gd`, `test/unit/test_gunnery_calculator.gd`. Modify `game_state.gd` (construct `gunnery_calculator`).

**Interfaces — Consumes:** `FireGeometry`, `CombatTables`, `ShipState` helpers (Tasks 3, 5, 7). **Produces:**
```gdscript
class_name GunneryTypes
class FireOrder extends RefCounted:
    var ship_id: String; var side: int; var target_id: String
    var aim: String = "low"      # "low" | "high"
    var ammo: String = "round"   # "round" | "dismantling"
    static func from_dict(d: Dictionary) -> FireOrder
    func to_dict() -> Dictionary
class ShotPreview extends RefCounted:
    var order: FireOrder
    var can_fire: bool; var reason: String      # reason set when can_fire is false
    var range_hexes: int; var rake: String; var initial_broadside: bool; var high_only: bool
    var tgf: int; var bgn: int
    var modifiers: Array[Dictionary]            # [{"name": String, "value": int}], zero-value entries omitted
    var mgn: int

class_name GunneryCalculator extends RefCounted
func _init(p_game_state: Node) -> void
func preview(order: GunneryTypes.FireOrder, two_targets: bool = false) -> GunneryTypes.ShotPreview
func eligible_shots(ship_id: String) -> Array[GunneryTypes.ShotPreview]   # one per (side, target) that can fire with roundshot; aim "low", or "high" when high_only
func any_eligible_shot() -> bool
func validate_orders(player_id: int, orders: Array[GunneryTypes.FireOrder]) -> String   # "" when valid
```
`preview` rules (§9.1–9.4): cannot fire when the firer or target is struck, they are the same side, the target is not in that side's arc, range > 15 (7 for dismantling), LOS is blocked (occupied = every ship hex), `sections_able_to_fire() == 0`, TGF is 0, or the BGN cell is grey. Modifier names, in this order: `crew_quality`, `sections_firing`, `guns_dismounted`, `rake`, `initial_broadside`, `two_targets`, `plain_sail`, `dismantling_shot`, `wind_speed_4`, `dismasted`. `dismasted` = −`environment.sea_state` when the firer is dismasted. A negative `mgn` is still `can_fire` (the shot simply does nothing).
`validate_orders` rejects: ship not owned by `player_id`; two orders for one ship and side; aim not low/high or ammo unknown; aim low when `high_only`; any order whose preview cannot fire (return its `reason`).

- [ ] **Step 1: Failing tests** (helper builds two `frigate_38` on opposite sides; firer at `(0,0)` facing 0, CQ D, MS, wind speed 2, sea state 1):
  - Target at `n(1)`: `range_hexes == 1`, `tgf == 14`, `bgn == 24`, modifiers == `[{"name":"initial_broadside","value":4}]`, `mgn == 28`.
  - After `initial_broadside_fired[STARBOARD] = true`: `mgn == 24`. Firer CQ B: `mgn == 28`.
  - Crew `[0,3,3,3]` → `sections_firing` −3. `guns_dismounted[STARBOARD] = 3` → −3.
  - `two_targets = true` → includes −12. Firer at PS → −1. `ammo = "dismantling"` at range 1 → +1; at range 8 → `can_fire == false`.
  - Target 10 hexes along direction 1: `high_only == true`, `tgf == 6`, `bgn == 4`, no initial-broadside bonus.
  - Target directly ahead (`n(0)`) → `can_fire == false`, reason mentions arc. A third ship on the line → reason mentions line of sight. Struck target → cannot fire.
  - Rake: target at `(0,0)` facing 0, firer at `n(3)` facing 1 (so the target bears on its port side) → `rake == "stern"`, modifier +4; same geometry at range 6 → no rake.
  - Table edges *(Review Focus 3)*: `guns_dismounted` 40 → `mgn` negative, `can_fire` true; firer with all sailor sections empty → cannot fire; `gun_factors` all 0 → cannot fire, no error.
  - `validate_orders`: valid pair → `""`; duplicate side, enemy-owned ship, low aim at range 12, target out of arc → each a non-empty message.
- [ ] **Step 2–4:** Run (FAIL) → implement → run (PASS).
- [ ] **Step 5:** Commit `feat: gunnery eligibility and modified gunfire number`.

### Task 9: Damage controller

**Files:** Create `scripts/server/damage_controller.gd`, `test/unit/test_damage_controller.gd`. Modify `game_state.gd`.

**Interfaces — Consumes:** `ShipStateController` mutators (Task 3), `Dice`, `CombatTables`, `PhaseLog`. **Produces:**
```gdscript
class_name DamageController extends RefCounted
var is_server: bool = true
func _init(p_game_state: Node) -> void
func apply_hits(ship_id: String, rigging: int, hull: int, crew: int, crew_cause: String, phase: int, source_id: String = "") -> void
func strike(ship_id: String, reason: String, phase: int) -> void    # no-op if already struck
```
`apply_hits` (§9.5), logging to `game_state.turn_log`:
- Rigging, then hull: one box at a time from the lowest-numbered section with boxes (use the existing `apply_rigging_damage` / `apply_hull_damage`). Excess beyond the last box is discarded.
- Hull section k emptied (k = 1..3): `add_guns_dismounted(k)` and `note_morale_check("hull_k", [1,1,2][k-1])`. Section 4 emptied: `strike(…, "hull destroyed")`.
- Rigging reaching 0 total: `note_morale_check("dismasted")`, set `sail_state` to `"NS"`, clear `sail_change`.
- Crew: per box, `dice.d6()` → `crew_loss_is_sailor(crew_cause, roll)` → `remove_crew_box`; a returned section index notes `"crew_<index>"`. Zero crew left: `strike(…, "no crew")`.
- One `DAMAGE` event per call with the amounts actually applied and the crew rolls; `GUNS_DISMOUNTED`, `MORALE_NOTED`, `STRIKE` events as they occur.

- [ ] **Step 1: Failing tests** (fresh `frigate_38`: rigging `[5,5,6,6]`, hull `[5,5,5,6]`):
  - 3 rigging → `[2,5,6,6]`; 7 rigging → `[0,3,6,6]`.
  - 5 hull → hull `[0,5,5,6]`, `guns_dismounted == [1,1]`, `pending_morale_checks == 1`.
  - 15 hull → `guns_dismounted == [6,6]`, `pending_morale_checks == 4`, not struck. 21 hull → struck, one STRIKE event; 30 hull → no error.
  - 22 rigging → dismasted, `sail_state == "NS"`, one more pending check; applying 1 more rigging later adds no check.
  - Crew with `ScriptedDice` `[1, 6]`, cause `"gunfire_at_hull"` → crew `[2,3,3,3]`, marines 1. Cause `"other"`, roll 4 → marine.
  - Emptying sailor section 1 notes one check; emptying the marines notes one.
  - All crew removed → struck with reason `"no crew"`.
  - Calling with `is_server = false` changes nothing.
- [ ] **Step 2–4:** Run (FAIL) → implement → run (PASS).
- [ ] **Step 5:** Commit `feat: damage allocation, guns dismounted, morale triggers, striking`.

### Task 10: Gunnery resolver

**Files:** Create `scripts/server/gunnery_resolver.gd`, `test/unit/test_gunnery_resolver.gd`. Modify `game_state.gd`.

**Interfaces — Consumes:** Tasks 5, 8, 9. **Produces:**
```gdscript
class_name GunneryResolver extends RefCounted
var is_server: bool = true
func _init(p_game_state: Node) -> void
func resolve(orders: Array[GunneryTypes.FireOrder], phase: int) -> void
```
Procedure (§7 step 4, §9.3–9.5):
1. Build a `ShotPreview` for every order from the state **before any damage** (`two_targets` true when the ship has two orders); also capture each target's sail state, dismasted flag and each firer's dismasted flag now.
2. Order shots: by target; within a target stern rakes, then bow rakes, then the rest; ties by firer `ship_id` (deterministic).
3. For each shot: mark that side's initial broadside spent; `fgn = mgn + dice.d6()`; if `fgn < 1`, log a FIRE event with no damage. Otherwise sum the result columns for the captured target sail state (PS: fs+ms+ps; MS: fs+ms; FS/NS: fs), resolving each slashed token with one `dice.d6()` (1–3 first alternative).
4. Adjustments: target furled (NS, not dismasted) → rigging halved, an odd half box lost on `dice.d6()` ≤ 3; target dismasted at capture → rigging 0; dismantling shot → hull 0; stern rake → crew doubled.
5. `damage.apply_hits(...)` with cause `"gunfire_at_hull"` only for roundshot aimed low, else `"other"`.
6. A raked target that was dismasted at capture: `note_morale_check("raked_dismasted_t<turn>")`.
7. Log one FIRE event per shot with `bgn`, `modifiers`, `mgn`, `d6`, `fgn`, row results and final amounts.

- [ ] **Step 1: Failing tests** (two `frigate_38`, A at `(0,0)` facing 0, B at `n(1)` facing 3 so each bears on the other with its starboard side; both CQ D, MS, wind speed 2, as in Task 8; `ScriptedDice`):
  - `test_simultaneous_fire_uses_pre_fire_state`: both fire low with d6 = 6 each; B's shot uses A's full crew/gun modifiers even though A's shot (resolved first) damaged B — assert B's FIRE event `mgn == 28`.
  - `test_initial_broadside_spent_after_firing` on the side fired, not the other.
  - `test_target_sail_state_adds_columns`: same `fgn` against a PS target yields rigging ≥ the MS result ≥ the FS result (compute expected sums from `CombatTables`).
  - `test_dismantling_shot_ignores_hull`; `test_stern_rake_doubles_crew`; `test_dismasted_target_takes_no_rigging`; `test_furled_target_halves_rigging` (odd count, scripted d6 3 → rounds up; 4 → rounds down).
  - `test_fgn_below_one_no_damage_but_broadside_spent` *(Review Focus 3)*: `guns_dismounted` 40, d6 1.
  - `test_fgn_above_52_uses_last_row` *(Review Focus 3)*: 74 at range 1, CQ A, stern rake, d6 6.
  - `test_same_seed_same_log`: two runs with real `Dice` seeded 99 give identical `turn_log.to_dict()`.
- [ ] **Step 2–4:** Run (FAIL) → implement → run (PASS).
- [ ] **Step 5:** Commit `feat: simultaneous gunnery resolution`.

### Task 11: Combat phase flow

**Files:** Modify `scripts/server/turn_phase_controller.gd`, `scripts/server/stub_ai.gd` (temporary no-fire submission), `scripts/autoload/game_state.gd`, `test/unit/test_game_loop.gd`. Create `test/unit/test_combat_phase.gd`.

**Interfaces — Produces** on `TurnPhaseController`:
```gdscript
signal fire_declaration_requested()
signal combat_log_ready(log: PhaseEvents.PhaseLog)
enum CombatStep { NONE, DECLARE, RESOLVE }
var combat_step: CombatStep = CombatStep.NONE
func player_submit_fire_orders(player_id: int, orders: Array) -> String   # orders: Array of Dictionary (FireOrder.to_dict()); "" on success, else the rejection reason
func on_combat_playback_completed() -> void
```
`_enter_combat_resolution_phase`: if `gunnery_calculator.any_eligible_shot()` is false → advance at once. Otherwise set `DECLARE`, clear stored orders and readiness, emit `fire_declaration_requested`, then call `stub_ai.submit_fire_orders()` (in this task it submits `[]` for player 1). `player_submit_fire_orders` validates with `validate_orders`; on failure returns the reason and keeps waiting; on success stores the orders and marks the player ready; when both are ready → `RESOLVE`, `gunnery_resolver.resolve(all_orders, COMBAT_RESOLUTION)`, emit `combat_log_ready(game_state.turn_log)` and wait. `on_combat_playback_completed` (only valid in `RESOLVE`) sets `NONE` and advances. `serialize_phase_state` includes `combat_step`.

- [ ] **Step 1: Failing tests** (`test_combat_phase.gd`, driving the real `GameState` as `test_game_loop.gd` does):
  - `test_combat_skipped_when_no_targets`: ships 40 hexes apart → after `on_playback_completed()` the phase passes COMBAT_RESOLUTION without waiting.
  - `test_combat_waits_for_orders_when_in_range`: ships adjacent and bearing → phase stays COMBAT_RESOLUTION, `combat_step == DECLARE`, signal emitted once.
  - `test_invalid_orders_rejected_and_phase_waits` *(Review Focus 1)*: out-of-arc target → non-empty reason, still `DECLARE`, target undamaged; then a valid submission succeeds.
  - `test_empty_orders_allowed` *(Review Focus 2)*: player 0 submits `[]` → resolves, no FIRE events, waits for playback.
  - `test_resolve_then_playback_advances`: after a valid submission `combat_step == RESOLVE` and the target has lost boxes; `on_combat_playback_completed()` moves on past COMBAT_RESOLUTION.
  - `test_submit_outside_declare_rejected`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Update `_run_one_turn` in `test_game_loop.gd` only if its ships now come into range (they should not: they start 15 apart sailing the same way; if they do, submit `[]` and call `on_combat_playback_completed()`).
- [ ] **Step 4:** `make test` → pass.
- [ ] **Step 5:** Commit `feat: fire declaration and resolution steps in the combat phase`.

---

# Stage C — Maintenance, morale, victory

### Task 12: Sail changes

**Files:** Create `scripts/server/sail_controller.gd`, `test/unit/test_sail_controller.gd`. Modify `turn_phase_controller.gd` (`_enter_movement_resolution_phase`, `_enter_status_adjustment_phase`), `game_state.gd`.

**Interfaces — Produces:**
```gdscript
class_name SailController extends RefCounted
var is_server: bool = true
func _init(p_game_state: Node) -> void
func available_targets(ship_id: String) -> Array[String]     # adjacent states in SAIL_ORDER not above max_sail_state(); [] if struck, dismasted, or a change is in progress
func change_cost(ship_id: String, target: String) -> Dictionary   # {"turns": int, "sections": int}
func plot_sail_change(player_id: int, ship_id: String, target: String) -> String   # "" ok; "" target clears the plot; PLANNING phase only
func begin_plotted_changes() -> void     # start of MOVEMENT_RESOLUTION
func advance_changes(phase: int) -> void # STATUS_ADJUSTMENT
```
Costs (§8): FS↔MS and FS↔NS → 1 section, 1 turn; MS↔PS → 2 sections, 2 turns; +1 turn for CQ E, F, G. `begin_plotted_changes` assigns the highest-numbered sailor sections that have boxes; if there are not enough, the order is dropped with a SAIL_CHANGE event `{"cancelled": "no crew"}`. `advance_changes`: cancel (event, clear) if an assigned section is empty or the ship is dismasted or struck; else decrement `turns_left`; at 0 call `set_sail_state` and log.

- [ ] **Step 1: Failing tests:**
  - `available_targets` for MS, full rigging → `["FS", "PS"]`; rigging level 3 at MS → `["FS"]`; at PS with level 3 → `["MS"]`; struck → `[]`.
  - `change_cost` MS→FS, CQ D → `{turns 1, sections 1}`; MS→PS → `{2, 2}`; MS→PS CQ E → turns 3.
  - Plot FS (from MS): after `begin_plotted_changes`, `sail_change.sections == [3]`, `sections_able_to_fire() == 3`, `sail_state` still MS; after one `advance_changes` → FS, `sail_change == {}`.
  - MS→PS: still MS after the first `advance_changes`, PS after the second.
  - Plotting a non-adjacent state, an unavailable state, another player's ship, or outside PLANNING → non-empty error.
  - Section 3 emptied mid-change → cancelled, sail unchanged.
- [ ] **Step 2–4:** Run (FAIL) → implement and wire the two phase calls → `make test` (PASS).
- [ ] **Step 5:** Commit `feat: plotted sail changes`.

### Task 13: Fouled-ship lock and drift

**Files:** Create `scripts/server/drift_resolver.gd`, `test/unit/test_drift_resolver.gd`. Modify `movement_resolver.gd` (set `moved_this_turn`; expose the fouling roll), `movement_plotting_controller.gd`, `stub_ai.gd`, `turn_phase_controller.gd`, `game_state.gd`, `test/unit/test_movement_resolver.gd`.

**Interfaces — Produces:**
```gdscript
class_name DriftResolver extends RefCounted
var is_server: bool = true
func _init(p_game_state: Node) -> void
func resolve(phase: int) -> void
# MovementResolver
func roll_fouling(ship_a: ShipState, ship_b: ShipState, drifting: bool = false) -> bool   # public; drifting adds the -1 DRM
```
- `MovementResolver.apply_results` sets `moved_this_turn` true when the ship advanced at least one hex, false otherwise (for every ship, including those with no plot).
- `handle_start_plotting` returns a `PlottingErrorResponse` with `error_code` `"SHIP_FOULED"`, `"SHIP_STRUCK"` or `"SHIP_DISMASTED"` for such ships. `StubAI` skips them without `push_error`.
- Drift (§10): eligible = not `moved_this_turn`, or `collision_this_turn`, or fouled. Sail key = `"dismasted"` if dismasted else `sail_state.to_lower()`. Number −1 → no drift. Roll `dice.d10() + drift_class_drm(class) >= number`. The downwind hex is the neighbour in direction `(wind_direction + 3) % 6` — `wind_direction` is where the wind blows *from* (a ship whose facing equals it is luffing; confirm with `HexGrid.get_wind_facing`). Order: most leeward first (largest projection on the downwind world vector; ties by `ship_id`). Blocked if the hex is occupied or outside `map_bounds`; if occupied by a ship, and neither is dismasted, and they are not already fouled together, `roll_fouling(drifter, other, true)` → on true set `fouled_with` both ways and log FOULED. Fouled pairs: one roll using the higher drift number of the two (and that ship's class DRM); both move or neither.

- [ ] **Step 1: Failing tests** (wind from direction 0, speed 3, `ScriptedDice`):
  - `test_stationary_ship_drifts_one_hex_downwind`: MS frigate, roll 3 (+1 class 3 = 4 ≥ 4) → hex is `n(3)` of the start, facing unchanged, DRIFT event with roll and number.
  - `test_roll_below_number_no_drift`: roll 2.
  - `test_ship_that_moved_does_not_drift`. `test_wind_speed_zero_no_drift`.
  - `test_plain_sail_wind_4_always_drifts` (roll 0).
  - `test_dismasted_uses_dismasted_row`: wind 3, roll 6 (+1 = 7 < 8) → stays.
  - `test_leeward_ship_resolved_first`: two stationary ships in a line downwind, both roll high → both end one hex downwind (the windward one is not blocked by the leeward one).
  - `test_blocked_by_ship_no_drift_and_may_foul`: leeward neighbour moved this turn; scripted drift roll 9 then fouling roll high → positions unchanged, both `fouled_with` set, FOULED event. With a dismasted ship → no fouling roll consumed.
  - `test_drift_blocked_at_map_edge` *(Review Focus 4)*: ship on the downwind boundary → stays, no error.
  - `test_fouled_pair_moves_together_or_not_at_all`.
  - Plotting: `handle_start_plotting` for a fouled ship → `PlottingErrorResponse` with `"SHIP_FOULED"`; `stub_ai.plot_all_ai_ships()` with a fouled AI ship raises no error.
- [ ] **Step 2–4:** Run (FAIL) → implement, call `drift_resolver.resolve` from `_enter_drift_calculation_phase` → `make test` (PASS).
- [ ] **Step 5:** Commit `feat: drift for stopped ships; fouled and struck ships cannot plot movement`.

### Task 14: Unfouling

**Files:** Create `scripts/server/fouling_controller.gd`, `test/unit/test_fouling_controller.gd`. Modify `turn_phase_controller.gd` (`_enter_status_adjustment_phase`: unfouling first, then `sail_controller.advance_changes`), `game_state.gd`.

**Interfaces — Produces:**
```gdscript
class_name FoulingController extends RefCounted
var is_server: bool = true
func _init(p_game_state: Node) -> void
func resolve_unfouling(phase: int) -> void
```
For each fouled pair once (ordered by the lower `ship_id`), each non-struck ship of the pair, in `ship_id` order: increment its `unfoul_attempts`; roll `dice.d10() + skill_modifier(crew_quality) <= unfouling_success_max(attempts)`; log UNFOUL with roll, modifier, needed and result. If either succeeds, clear `fouled_with` on both (which resets attempts) and stop rolling for that pair. A dangling `fouled_with` (partner missing or not pointing back) is cleared silently.

- [ ] **Step 1: Failing tests:** first attempt CQ D roll 2 → freed, both `fouled_with == ""`; roll 3 → still fouled, attempts 1; second turn roll 3 → freed; CQ A roll 5 (−3 = 2) → freed; CQ G roll 0 (+3 = 3) on first attempt → not freed; first ship fails, second succeeds → freed with two UNFOUL events; struck ship does not roll (only one event); freed ships can start plotting again.
- [ ] **Step 2–4:** Run (FAIL) → implement and wire → `make test` (PASS).
- [ ] **Step 5:** Commit `feat: automatic unfouling rolls`.

### Task 15: Morale and striking

**Files:** Create `scripts/server/morale_controller.gd`, `test/unit/test_morale_controller.gd`. Modify `turn_phase_controller.gd` (`_enter_morale_check_phase`), `game_state.gd`.

**Interfaces — Produces:**
```gdscript
class_name MoraleController extends RefCounted
var is_server: bool = true
func _init(p_game_state: Node) -> void
func resolve_checks(phase: int) -> void
```
For each non-struck ship in `ship_id` order, for each pending check: roll `dice.d10()`; pass if `roll >= morale_rating`. On failure: if crew quality is `"G"` → `damage.strike(ship_id, "morale", phase)` and stop that ship's checks; else lower the quality one letter. Log MORALE_CHECK each time (roll, rating, result, new quality). Clear pending checks for every ship, struck or not.

- [ ] **Step 1: Failing tests:** MR 4, roll 4 → pass, quality unchanged; roll 3 → D becomes E; two pending, rolls `[0, 0]` → D → F; quality G, roll 0 → struck with reason `"morale"`; quality F, rolls `[0, 0]` → G then struck; MR 2, roll 2 → pass; pending cleared afterwards; struck ship's pending checks cleared without rolling (no dice consumed).
- [ ] **Step 2–4:** Run (FAIL) → implement and wire → `make test` (PASS).
- [ ] **Step 5:** Commit `feat: morale checks and striking on morale failure`.

### Task 16: Victory, End Turn and game over

**Files:** Create `scripts/server/victory_controller.gd`, `test/unit/test_victory_controller.gd`. Modify `turn_phase_controller.gd`, `game_state.gd` (start-of-game snapshot of each ship's starting CQ; `turn_log` rotation), `scripts/state/ship_state.gd` (`starting_crew_quality`, serialised), `test/unit/test_game_loop.gd`.

**Interfaces — Produces:**
```gdscript
class_name VictoryController extends RefCounted
func _init(p_game_state: Node) -> void
func points_lost(ship: ShipState) -> float      # points the enemy scores for this ship
func check(turn: int) -> Dictionary             # {} if the game continues; else {"winner": int (-1 draw), "reason": String, "points": {0: float, 1: float}, "turn": int}
# TurnPhaseController
signal game_over(result: Dictionary)
var game_result: Dictionary = {}
func player_end_turn(player_id: int) -> bool    # POST_COMBAT only
```
- `points_lost` (§12.1): value = `ship.ship.point_value(starting_crew_quality, morale_rating)`. Struck → 100%. Otherwise sum for sections with 0 boxes: rigging sections 1–3 5% each, rigging 4 10%, hull 1–3 10% each, each of the four sailor sections and the marines 10% — capped at four crew sections (40%). No rounding.
- `check`: game ends when every ship of a side is struck (`reason "all struck"`) or `turn >= active_scenario.get("turn_limit", 0) > 0` (`"turn limit"`). Winner = side with more points scored (points scored by player p = sum of `points_lost` over the other side's ships); equal → −1.
- POST_COMBAT now waits for `player_end_turn(0)` (the AI needs no call). It enters END_TURN, which runs `check(current_turn)`: if over → store `game_result`, log VICTORY, emit `game_over`, and stop (further `advance_phase` calls are ignored); else save snapshots as today and start the next turn immediately. `_start_new_turn` clears per-turn flags, archives `turn_log` into `turn_logs[turn]` and creates a new one.

- [ ] **Step 1: Failing tests:**
  - `points_lost`: fresh frigate_38 at D4 → 0.0; struck → 38.0; rigging section 1 and hull section 1 empty → `is_equal_approx(5.7)`; all four rigging sections empty → 25% → 9.5; five crew sections empty → 40% → 15.2.
  - `check`: nobody struck, no limit → `{}`; all of player 1 struck → winner 0, reason `"all struck"`; both sides all struck, equal ships → winner −1; `turn_limit` 5 at turn 5 with player 1 more damaged → winner 0, reason `"turn limit"`; at turn 4 → `{}`.
  - Phase flow: `player_end_turn(0)` outside POST_COMBAT → false; in POST_COMBAT with no victory → next turn's PLANNING, `turn_logs` has the finished turn; with all enemies struck → phase END_TURN, `game_result.winner == 0`, `game_over` emitted once, `advance_phase()` afterwards leaves the phase unchanged.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. In `test_game_loop.gd` replace the two manual `advance_phase()` calls after POST_COMBAT with one `player_end_turn(0)` (helper and determinism test).
- [ ] **Step 4:** `make test` → pass.
- [ ] **Step 5:** Commit `feat: victory points, End Turn wait and game over`.

### Task 17: Stub AI — closing and firing

**Files:** Modify `scripts/server/stub_ai.gd`, `test/unit/test_stub_ai.gd`.

**Interfaces — Consumes:** plotting protocol responses (`valid_next_hexes` in `PlottingStartedResponse` / `HexSelectedResponse`), `GunneryCalculator`, `FireGeometry`. **Produces:**
```gdscript
func submit_fire_orders() -> void                 # builds and submits orders for player 1 via phase_controller.player_submit_fire_orders
func choose_fire_orders() -> Array[Dictionary]    # FireOrder dicts
func _strategy_engage(ship_state, session ids…) -> void   # replaces "forward" as the default strategy
```
- Fire: for each AI ship and each side, take `eligible_shots`, pick the highest `mgn` (ties: nearest, then `target_id`); aim `"high"` if `high_only` else `"low"`; roundshot. If two sides both have a target, keep both only when each shot's `mgn − 12 >= 1`; otherwise keep the better one.
- Movement (`engage`): target = nearest non-struck enemy. Greedy, one step at a time from the options the server offers: score an option (resulting hex, facing) as `1000 − range` if the enemy would lie in a broadside arc with clear LOS at range ≤ 5, otherwise `−distance to the enemy`; choose the highest score (ties: keep the current facing, then lowest hex q, r); stop when no options remain or the best option does not improve on staying. Submit the session. Fall back to submitting an empty path if the server offers nothing.

- [ ] **Step 1: Failing tests:**
  - `test_ai_fires_at_best_target`: AI frigate with two enemies in its starboard arc at ranges 2 and 6 → one starboard order at the range-2 ship, aim low.
  - `test_ai_aims_high_beyond_range_9`.
  - `test_ai_holds_second_broadside_when_penalty_wastes_it`: weak second shot (`mgn` 5) → only one order.
  - `test_ai_orders_pass_validation`: `validate_orders(1, choose_fire_orders())` is `""`.
  - `test_ai_closes_distance`: enemy 12 hexes upwind-abeam; after three turns of AI plotting and resolution the distance is smaller than at the start.
  - `test_ai_with_no_movable_ships_does_not_error` *(Review Focus 2)*: all AI ships fouled/struck → `plot_all_ai_ships()` and `submit_fire_orders()` complete, phase advances when the player submits.
- [ ] **Step 2–4:** Run (FAIL) → implement → `make test` (PASS).
- [ ] **Step 5:** Commit `feat: AI closes with the enemy and fires`.

### Task 18: Full-loop integration tests

**Files:** Modify `test/unit/test_game_loop.gd`. Create `test/unit/test_battle_to_victory.gd`.

- [ ] **Step 1: Write tests**
  - `test_scripted_duel_runs_to_a_winner`: two `frigate_38` (player 0 CQ B, player 1 CQ E, both MR 4) start adjacent and bearing on each other, speed 0, wind speed 2, seed 11, `turn_limit` 60. Each turn: no movement plots; player 0 submits its best `eligible_shots` order (low); AI submits its own; complete combat playback; `player_end_turn(0)`. Loop until `game_result` is non-empty. Assert: ends within 60 turns, `winner` is 0 or 1 or −1 with `reason` set, `points` has both keys, at least one FIRE and one DAMAGE event exist in `turn_logs`, and no ship has a negative box count anywhere.
  - `test_battle_is_deterministic`: run the duel twice with the same seed → identical `game_result` and identical `turn_logs` (compare `to_dict()` per turn).
  - `test_turn_with_all_player_ships_struck_still_ends` *(Review Focus 2)*: player 0's only ship struck at start → the game ends at the first END_TURN with winner 1.
  - `test_sail_change_reduces_fire_then_takes_effect`: plot MS→FS, come under fire the same turn → that turn's FIRE event shows `sections_firing −3`; next turn the ship is at FS.
- [ ] **Step 2:** Run → fix whatever integration gaps appear (wiring only; no new rules).
- [ ] **Step 3:** `make test` → pass. Commit `test: scripted battle to victory, determinism across combat`.

---

# Stage D — UI

UI tasks are verified in the running game with the `godot-mcp` server: `run_project`, then `game_get_errors` must return zero, then drive and screenshot as each task says. Keep logic out of UI scripts — they call the server interfaces defined above and render the results.

### Task 19: Sail-change control in planning; fouled/struck ships in the list

**Files:** Modify `scripts/ui/planning_phase_ui.gd`, `scenes/ui/planning_phase_ui.tscn`, `scripts/ui/ship_list_item.gd`, `scenes/ui/ship_list_item.tscn`, `scripts/core/game_controller.gd`.

- [ ] **Step 1:** For the selected own ship show a "Sail" row: current state, one button per `sail.available_targets(ship_id)`, each labelled with its cost from `change_cost` (e.g. `"→ FS (1 turn, 1 section)"`), and a "Cancel order" button when one is plotted. Buttons call `GameState.sail_controller.plot_sail_change(0, ship_id, target)` through `GameController` (mark the call `# SCV:ALLOW` like the existing server calls there). While a change is in progress show `"Changing to PS — 1 turn left"` and no buttons.
- [ ] **Step 2:** Ship list items for fouled, struck or dismasted ships show that status and have the movement button disabled; such ships count as "submitted" for the End Planning check so planning can finish *(Review Focus 2)*.
- [ ] **Step 3: Verify:** `make play`; plot MS→FS, end planning, finish the turn; next planning shows FS. `game_get_errors` → 0. Screenshot the sail row.
- [ ] **Step 4:** Commit `feat: sail-change orders in the planning UI`.

### Task 20: Fire declaration panel and arc overlay

**Files:** Create `scripts/ui/fire_declaration_panel.gd`, `scenes/ui/fire_declaration_panel.tscn`. Modify `scripts/core/game_controller.gd`, `scripts/view/hex_overlay.gd`.

**Interfaces — Consumes:** `phase_controller.fire_declaration_requested`, `gunnery_calculator.eligible_shots(ship_id)`, `gunnery_calculator.preview(order, two_targets)`, `phase_controller.player_submit_fire_orders(0, orders)`, `FireGeometry.broadside_hexes`. **Produces:** `HexOverlay.show_arc(hexes: Array[Vector2i], color: Color) -> void` and `clear_arcs() -> void`.

- [ ] **Step 1:** On `fire_declaration_requested`, `GameController` shows the panel in the context panel area (title "Fire Orders"). The panel lists each own ship that has at least one eligible shot. For each of its two sides with shots: an option list of targets — `"<name> — range N"` plus `"rake"` / `"initial broadside"` tags and the modified number — with "Hold fire" first and selected by default; an aim toggle (low/high; locked to high when `high_only`); an ammunition toggle (roundshot/dismantling; dismantling disabled beyond range 7).
- [ ] **Step 2:** Any change re-queries `preview` for that ship's orders (with `two_targets` when both sides are set) and refreshes the displayed modified numbers and the modifier breakdown (`name value` per line).
- [ ] **Step 3:** Selecting a ship row calls `hex_overlay.show_arc` for both broadsides (two distinct translucent colours) and highlights the chosen targets; leaving the phase calls `clear_arcs`.
- [ ] **Step 4:** "Fire" submits all orders in one call. A non-empty return value is shown in the panel and the panel stays open. If the player has no eligible shots at all, `GameController` submits `[]` immediately and shows nothing.
- [ ] **Step 5: Verify:** start `test_basic`, sail until a broadside bears (or use `game_eval` to place the ships adjacent), confirm the panel appears with correct range and number, arcs draw on the correct sides, and submitting advances. `game_get_errors` → 0. Screenshot.
- [ ] **Step 6:** Commit `feat: fire declaration panel with arc overlay`.

### Task 21: Combat log, playback pacing, ship status and struck visuals

**Files:** Create `scripts/ui/combat_log_panel.gd`, `scenes/ui/combat_log_panel.tscn`. Modify `scripts/core/game_controller.gd`, `scripts/ui/ship_status_panel.gd`, `scripts/view/ship_view.gd`.

- [ ] **Step 1:** Combat log panel: a scrollable, collapsible list bound to `GameState.turn_log` (and earlier turns via `turn_logs`), one line per event from `PhaseEvent.to_text`, grouped under phase headings. It refreshes on `combat_log_ready` and on every `phase_changed`.
- [ ] **Step 2:** On `combat_log_ready`, `GameController` reveals FIRE/DAMAGE lines one at a time (about 0.6 s each, skippable with a click or Space; instant when `skip_post_combat_delay` is set), syncs all ship views, then calls `phase_controller.on_combat_playback_completed()` (`# SCV:ALLOW`).
- [ ] **Step 3:** Ship status panel shows, for own and enemy ships: rigging, hull and crew boxes per section as `current/max`, marines, guns dismounted, crew quality, morale rating, sail state (with `"(moves as MS)"` when `movement_sail_state()` differs), pending sail change, and FOULED / STRUCK / DISMASTED badges.
- [ ] **Step 4:** `ShipView` shows a struck ship distinctly (for example desaturated with a white flag marker) driven by `sync_to_state`.
- [ ] **Step 5: Verify:** fight one exchange; the log lines show table numbers and rolls; the status panel matches `game_get_property` values for the same ship; a struck ship (force with `game_call_method` on `damage_controller.strike`) changes appearance. `game_get_errors` → 0. Screenshot.
- [ ] **Step 6:** Commit `feat: combat log, status panel boxes, struck ship visuals`.

### Task 22: End Turn button and game-over screen

**Files:** Create `scripts/ui/game_over_panel.gd`, `scenes/ui/game_over_panel.tscn`. Modify `scripts/core/game_controller.gd`.

- [ ] **Step 1:** In POST_COMBAT show an "End Turn" button (context panel, title "Turn N complete") instead of the 2-second timer; it calls `phase_controller.player_end_turn(0)`. When `skip_post_combat_delay` is set, call it automatically. Remove `_end_turn()`'s phase advance — END_TURN now advances itself.
- [ ] **Step 2:** On `game_over`, show a modal panel: "Victory" / "Defeat" / "Draw", the reason, turn count, points for each side, ships struck on each side, and a "Back to scenarios" button that returns to `scenario_selection.tscn` through the existing scene navigation in `main.gd`. Input to the map is blocked while it is open.
- [ ] **Step 3: Verify:** play a turn and confirm the game waits for End Turn; force a win (`game_call_method` striking the enemy ship, then End Turn) and confirm the panel and the return to scenario selection; start a second game from there and confirm state was reset. `game_get_errors` → 0. Screenshot.
- [ ] **Step 4:** Commit `feat: End Turn button and game-over screen`.

### Task 23: Documentation, audit and full playthrough

**Files:** Modify `CLAUDE.md`, `docs/07-naval-combat-mechanics.md`, `docs/02-game-rules.md` (phase list only).

- [ ] **Step 1:** `CLAUDE.md`: update the phase list ("implemented" set, the fire-declaration step, End Turn), add the new controllers and `CombatTables` lookups, the ship data format (gun factors per side, point costs), the rigging-level rule, `validate_combat.py`, and the d10 = 0–9 convention. Remove statements that are no longer true (stubbed phases, `corvette_24`, string rigging quality by percentage).
- [ ] **Step 2:** Add a banner at the top of `docs/07-naval-combat-mechanics.md`: "Non-canonical early notes. Combat rules are defined by the 1997 Close Action tables; see `docs/superpowers/specs/2026-11-13-playable-turn-loop-design.md`." In `docs/02-game-rules.md` note that gunnery targets are declared after movement (replacing 2.2.10).
- [ ] **Step 3:** `python3 .claude/skills/validate-rule-table/scripts/validate.py` and `validate_combat.py` → clean. `make test` → all pass.
- [ ] **Step 4:** Run the `scv-reviewer` agent; fix every violation it reports; re-run `make test`.
- [ ] **Step 5: Full playthrough** of `test_basic` with `godot-mcp` from splash screen to the game-over panel, playing normally (movement, a sail change, several exchanges). `game_get_errors` must be zero throughout. Record the turn count and result in the commit message.
- [ ] **Step 6:** Commit `docs: playable turn loop; mark early combat notes non-canonical`.
