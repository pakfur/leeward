# Anchoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Leeward the whole of Close Action chapter 13 A–F: preparing anchors and springs, anchoring by bow or stern, riding to the anchor (swing, settle, oblique drift, veering), spring turns, cutting, the anchored gunfire bonus and the in-irons exceptions, played by the stub AI and drawn by a view-only minimum.

**Architecture:**
- Nine crew tasks (`crew_tasks.json`) on the existing crew-task engine; their legality and all anchor geometry live in a new pure `AnchorRules` (Tasks 1, 3, 4).
- A new `AnchorController` (a `CrewTaskHandler` registered for the nine codes) completes the preparations and runs two steps: the springs step at the start of MOVEMENT_RESOLUTION (spring turns, veer in) and the anchoring step right after drift (SoP V.A–B: swing, settle, wind shift, veer out, drop, cut) (Tasks 5–7).
- Hooks in existing code: drift holds anchored groups, the resolver's irons test, gunnery's +1, `PlayerView`, plotting refusal (Tasks 2, 6–8).
- Scenario permission and starting anchors, dev commands, the stub AI and signals, the view, docs (Tasks 9–12).

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5. `make test` runs the whole suite. Run `make import` before `make test` whenever a task adds a `class_name`.

**Spec:** `docs/superpowers/specs/2026-11-17-anchoring-design.md`. Executors read it alongside this plan; section numbers below (§n) are the spec's. Binding requirements: `docs/superpowers/specs/2026-11-17-subprojects-3-7-decisions.md` §0 and §3. Rules: `docs/rules/close_action.md` 13.A–F, 8.A.7, 8.B, SoP V.A–B, 5.D.4, 5.D.7, 7.C.12c; Diagram 25 (`docs/rules/images/diagram-25-anchoring.png`). Invoke the `close-action-rules` skill before game-logic work.

## Global Constraints

- Directions: `HexGrid.DIRECTIONS` 0=E (1,0), 1=SE (0,1), 2=SW (−1,1), 3=W (−1,0), 4=NW (0,−1), 5=NE (1,−1). `EnvironmentState.wind_direction` is where the wind comes from; downwind is `(wind_direction + 3) % 6`. WF=L is `facing == wind_direction`. Port turn = `facing − 1`, starboard = `facing + 1` (mod 6).
- Anchor geometry (spec §1): `end_hex = anchor.hex + cable × DIRECTIONS[downwind]`; bow anchor: bow = `end_hex`, stern = `HexGrid.stern_of(bow, facing)`; stern anchor: stern = `end_hex`, bow = `end_hex + DIRECTIONS[facing]`. Proper facing: bow → `wind_direction`, stern → `(wind_direction + 3) % 6`.
- Task lengths (ship log, scan-checked): PBA 2 (CQ A–D) / 3 (E–G); PSA 6 ± SK; PBS 2 × (5 ± SK); PSS 2 × (6 ± SK); A, AX, VO, VI, HS 1. SK: A −3, B −2, C −1, D 0, E +1, F +2, G +3. CQ C: PSA 5, PBS 8, PSS 10.
- At most 3 VOs (cable ≤ 4); at most 2 anchorings per ship (a scenario starting anchor counts as 1).
- Dice: anchoring rolls only through `game_state.dice` (swing d6, fouling d10, depth d6), never `randi()`, never the resolver's `rng`.
- `PhaseEvents.Type` values are appended after `ARRIVAL_DELAYED` in this order: `ANCHORED`, `ANCHOR_MOVE`, `CABLE_CUT`, `SPRING_TURN`, `VEER_IN`. Never renumber.
- Every ShipState mutation goes through `ShipStateController`; every server method checks `is_server` and `push_error`s on a client. View code (`scripts/ui`, `scripts/view`, `scripts/core`, `scripts/commands`) only reads (`test_server_authority.gd` must stay green).
- Use `Trace`, never `print()`.
- `make test` is green at the end of every task. No existing test may change its expected values unless the task says so.
- The PostToolUse hook runs the full `make test` after edits under `scripts/server/`, `scripts/state/`, `scripts/core/`, `scripts/autoload/` and `test/unit/`.
- `docs/rules/feature_diff.md`, `CLAUDE.md` and the scenario-creator skill are updated in Task 12 only.
- Test fixtures: copy the setup pattern of `test/unit/test_drift_resolver.gd` (save and restore `GameState.dice`, `turn_log`, `environment`, `active_scenario`, `ships`, `ships_by_side`; `_make_ship` with explicit rigging and hull; `GameState.dice = ScriptedDice.new()`; wind direction 0, speed 3). A test that expects no die asserts `_dice.remaining() == 0` after queuing nothing; an unexpected roll `push_error`s and fails the test.

## Review Focus

1. **Every existing scenario and anchor-free test resolves exactly as before:** no extra dice, no changed drift order. Pinned by Task 6 `test_no_anchor_no_change` and Task 12 `test_every_scenario_places_cleanly`.
2. **The anchoring g-t order** (13.C.2): the ship drifts normally first, then drops; the forced moves of V.A apply only to ships anchored before this g-t; the +1 BGN only from the next combat. Pinned by Task 6 `test_drop_after_drift` and Task 8 `test_no_bonus_on_anchoring_turn`.
3. **A spring turn happens before any ship moves and is never undone by a resolver re-run.** Pinned by Task 7 `test_spring_turn_before_movement` and `test_spring_turn_survives_bear_off_rerun`.
4. **Blocked forced moves never move a ship partly or off the map** (fouling roll for a ship, aground for land, hold at an edge). Pinned by Task 6 `test_blocked_by_ship_rolls_fouling_and_holds`, `test_forced_move_onto_land_grounds`, `test_forced_move_off_map_holds`.
5. **The AI never cuts a ship that started anchored unless a signal says so,** and never anchors where the scenario forbids it. Pinned by Task 10 `test_start_anchored_stays_without_signal` and `test_no_anchoring_without_permission`.

---

### Task 1: The nine anchoring task codes and the `times` turns form

**Files:**
- Modify: `data/rules/crew_tasks.json`, `scripts/autoload/combat_tables.gd` (`task_turns`), `.claude/skills/validate-rule-table/scripts/validate_combat.py` (`check_crew_tasks`, `TURN_SHAPES`), `scripts/server/phase_events.gd` (`CREW_TASK_NAMES`, `CREW_TASK_GERUNDS`).
- Test: create `test/unit/test_anchor_tasks.gd`.

**Interfaces (Produces):**
- `crew_tasks.json` rows (all `"sections": [1, 1]`):
  `"PBA": {"name": "Prepare bow anchor", "turns": {"ad": 2, "eg": 3}}`, `"PSA": {"name": "Prepare stern anchor", "turns": {"sk_base": 6}}`, `"PBS": {"name": "Prepare bow springs", "turns": {"sk_base": 5, "times": 2}}`, `"PSS": {"name": "Prepare stern springs", "turns": {"sk_base": 6, "times": 2}}`, `"A": {"name": "Anchor", "turns": {"fixed": 1}}`, `"AX": {"name": "Cut anchor", "turns": {"fixed": 1}}`, `"VO": {"name": "Veer out", "turns": {"fixed": 1}}`, `"VI": {"name": "Veer in", "turns": {"fixed": 1}}`, `"HS": {"name": "Handle springs", "turns": {"fixed": 1}}`. Extend `_doc` with `{sk_base: n, times: k} = k × max(1, n + SK mod)`.
- `CombatTables.task_turns(code, cq)`: for `sk_base`, returns `int(turns.get("times", 1)) * maxi(1, sk_base + skill_modifier(cq))`.
- Validator: `{sk_base, times}` is an accepted shape; `times` must be a positive int.
- `CREW_TASK_NAMES`: PBA "prepare the bow anchor", PSA "prepare the stern anchor", PBS "prepare bow springs", PSS "prepare stern springs", A "anchor", AX "cut the cable", VO "veer out", VI "veer in", HS "handle the springs". `CREW_TASK_GERUNDS`: "preparing the bow anchor", "preparing the stern anchor", "preparing bow springs", "preparing stern springs", "anchoring", "cutting the cable", "veering out", "veering in", "handling the springs".

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchor_tasks.gd` (`before_all` loads `DataManager.combat_tables` as `test_combat_tables.gd` does):
  - `test_pba_two_or_three`: `task_turns("PBA", "A") == 2`, `"D" == 2`, `"E" == 3`, `"G" == 3`.
  - `test_psa_six_plus_sk`: `"C" == 5`, `"A" == 3`, `"G" == 9`.
  - `test_pbs_twice_five_plus_sk` (13.B.2 example): `"C" == 8`, `"A" == 4`, `"G" == 16`.
  - `test_pss_twice_six_plus_sk`: `"C" == 10`, `"A" == 6`, `"G" == 18`.
  - `test_one_turn_codes`: for each of A, AX, VO, VI, HS and every CQ A–G: `task_turns == 1`; `task_sections(code) == [1, 1]` for all nine codes.
  - `test_times_defaults_to_one`: `task_turns("RR", "C") == 5` (unchanged).
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** the rows, `task_turns`, the validator and the phase-event words.
- [ ] **Step 4: Run and confirm everything passes.** `python3 .claude/skills/validate-rule-table/scripts/validate_combat.py` (exit 0), `python3 .claude/skills/validate-rule-table/scripts/validate.py`, `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add data/rules/crew_tasks.json scripts/autoload/combat_tables.gd .claude/skills/validate-rule-table/scripts/validate_combat.py scripts/server/phase_events.gd test/unit/test_anchor_tasks.gd
git commit -m "feat: the nine anchoring crew task codes and the 2 x (n +/- SK) length form"
```

### Task 2: Anchor state on the ship

**Files:**
- Modify: `scripts/state/ship_state.gd`, `scripts/server/ship_state_controller.gd`, `scripts/server/default_course.gd` (`can_plot`), `scripts/server/movement_plotting_controller.gd` (`_plot_refusal`), `scripts/server/stub_ai.gd` (`LOCKED_ERROR_CODES`), `test/unit/test_server_authority.gd`.
- Test: create `test/unit/test_ship_state_anchor.gd`.

**Interfaces (Produces):**
- `ShipState`:
  - `@export var anchor: Dictionary = {}` — `{}` or `{"hex": Vector2i, "end": "bow"|"stern", "springs": bool, "cable": int, "veered": int, "swing_dir": int, "wind_dir": int, "turn": int}` (spec §1).
  - `@export var anchor_ready: String = ""`, `@export var springs_ready: bool = false`, `@export var anchorings_used: int = 0`, `@export var cable_cut_turn: int = -1`.
  - `func is_anchored() -> bool` (`not anchor.is_empty()`), `func has_springs() -> bool` (anchored and `anchor.springs`), `func anchored_end_hex() -> Vector2i` (bow when `anchor.end == "bow"`, else `stern_hex()`; `hex_position` when not anchored).
  - `serialize()` writes `"anchor"` with `hex` as `{"q", "r"}` (`{}` when not anchored) and the four other fields; `deserialize()` reads them back (`hex` to `Vector2i`).
- `ShipStateController` (server only, emit `ship_state_changed`, return `true` on success):
  - `func drop_anchor(ship_id: String, data: Dictionary) -> bool`: `anchor = data.duplicate(true)`; `anchor_ready = ""`; `springs_ready = false`; `anchorings_used += 1`; `speed = 0`; `irons_entry_turn = -1`; `cable_cut_turn = -1`.
  - `func update_anchor(ship_id: String, fields: Dictionary) -> bool`: merges into `anchor`; `push_error` and `false` when not anchored.
  - `func cut_cable(ship_id: String, turn: int) -> bool`: `anchor = {}`, `cable_cut_turn = turn`.
  - `func set_anchor_ready(ship_id: String, end: String) -> bool` (`""`, `"bow"`, `"stern"`; anything else `push_error`, `false`).
  - `func set_springs_ready(ship_id: String, on: bool) -> bool`.
  - `remove_from_map` also sets `anchor = {}`.
- `DefaultCourse.can_plot` is false for `is_anchored()`. `_plot_refusal` returns `["SHIP_ANCHORED", "Ship %s is anchored: cut the cable (AX) to get under way (13.C.3)"]` after the aground check, before dismasted. Update both docstrings' refusal lists. `StubAI.LOCKED_ERROR_CODES` gains `"SHIP_ANCHORED"`.
- `test_server_authority.gd` `FORBIDDEN` gains:
  - `["\\.(anchor|anchor_ready|springs_ready|anchorings_used|cable_cut_turn)\\s*(=|\\+=|-=)[^=]", "an anchor field written from view code"]`
  - `["\\.anchor\\[[^\\]]*\\]\\s*=[^=]", "an anchor field written from view code"]`
  - `["(?<!player_)\\b(drop_anchor|update_anchor|cut_cable|set_anchor_ready|set_springs_ready)\\(", "an anchor mutator called from view code"]`
  - `["\\banchor_controller\\.", "AnchorController used from view code"]`

- [ ] **Step 1: Write the failing tests** in `test/unit/test_ship_state_anchor.gd`:
  - `test_new_ship_not_anchored`: `not is_anchored()`, `anchor_ready == ""`, `anchorings_used == 0`, `cable_cut_turn == -1`, `anchored_end_hex() == hex_position`.
  - `test_drop_anchor_sets_state`: ship speed 3, `irons_entry_turn = 1`, `anchor_ready = "bow"`, `springs_ready = true` (set through the controller); `drop_anchor("a", {"hex": Vector2i(0, 0), "end": "bow", "springs": true, "cable": 0, "veered": 0, "swing_dir": 0, "wind_dir": 0, "turn": 2})` → `is_anchored()`, `has_springs()`, `anchorings_used == 1`, `speed == 0`, `irons_entry_turn == -1`, `anchor_ready == ""`, `springs_ready == false`.
  - `test_anchored_end_hex`: bow (0, 0) facing 3, stern anchor → `anchored_end_hex() == Vector2i(1, 0)`; bow anchor → `Vector2i(0, 0)`.
  - `test_update_and_cut`: `update_anchor("a", {"cable": 2})` → `anchor.cable == 2`; `cut_cable("a", 5)` → not anchored, `cable_cut_turn == 5`; `update_anchor` on a ship not anchored → `assert_push_error`, returns false.
  - `test_set_anchor_ready_rejects_unknown_end`: `"mast"` → `assert_push_error`, false.
  - `test_remove_from_map_clears_anchor`.
  - `test_serialize_round_trip_anchor`: every field, `anchor.hex == Vector2i(-2, 1)` after `ShipState.deserialize(s.serialize())`.
  - `test_anchored_ship_cannot_plot`: `DefaultCourse.can_plot(a) == false`; `DefaultCourse.for_ship(GameState, a)` empty at speed 3; `movement_plotting_controller.handle_start_plotting` gives a `PlottingErrorResponse` with `error_code == "SHIP_ANCHORED"`.
  - In `test_server_authority.gd`, `test_anchor_patterns_catch_mutations`: caught `"ship.anchor = {}"`, `"s.anchor[\"cable\"] = 2"`, `"ship.anchor_ready = \"bow\""`, `"GameState.ship_controller.drop_anchor(\"a\", {})"`, `"GameState.anchor_controller.cut_now(\"a\", 5)"`; allowed `"if ship.is_anchored():"`, `"var c: int = ship.anchor.get(\"cable\", 0)"`, `"label.anchor_left = 0.5"`, `"if ship.anchor_ready == \"bow\":"`.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/state/ship_state.gd scripts/server/ship_state_controller.gd scripts/server/default_course.gd scripts/server/movement_plotting_controller.gd scripts/server/stub_ai.gd test/unit/
git commit -m "feat: anchor state on the ship; an anchored ship cannot plot movement"
```

### Task 3: `AnchorRules` — legality, permission and geometry

**Files:**
- Create: `scripts/server/anchor_rules.gd`.
- Test: create `test/unit/test_anchor_rules.gd`.

**Interfaces (Produces):** `class_name AnchorRules extends RefCounted`, pure statics only (header `##` cites 13.A–F and spec §1, §3, §7):

```gdscript
const CODES: Array[String] = ["PBA", "PSA", "PBS", "PSS", "A", "AX", "VO", "VI", "HS"]
const PREP_CODES: Array[String] = ["PBA", "PSA", "PBS", "PSS"]
const ORDERS: Array[String] = ["", "prepare_bow", "prepare_stern", "prepare_springs", "anchor", "cut",
	"veer_out", "veer_in", "turn_port", "turn_starboard"]
const MAX_VEERED := 3
const MAX_ANCHORINGS := 2
const STATION := "anchor"
static func is_code(code: String) -> bool
static func permitted(scenario: Dictionary, hex: Vector2i) -> bool        # spec §7
static func scenario_errors(scenario: Dictionary) -> Array[String]       # spec §7; messages start "Anchoring: "
static func drop_hex(ship: ShipState) -> Vector2i                        # stern_hex() when anchor_ready == "stern", else hex_position
static func proper_facing(end: String, wind_dir: int) -> int
static func downwind(wind_dir: int) -> int                                # (wind_dir + 3) % 6
static func footprint(anchor_hex: Vector2i, end: String, cable: int, facing: int, wind_dir: int) -> Array[Vector2i]  # [bow, stern]
static func spring_turn(ship: ShipState, direction: int) -> Dictionary   # {"facing", "hexes": [bow, stern]}; AB pivots on the bow, AS on the stern
static func needs_swing_roll(facing: int, proper: int, swing_dir: int) -> bool  # opposite and swing_dir == 0
static func swing_step(facing: int, proper: int, swing_dir: int, roll: int) -> Dictionary  # {"facing", "swing_dir"}
static func forced_check(scenario: Dictionary, old_hexes: Array[Vector2i], new_hexes: Array[Vector2i], others: Dictionary) -> Dictionary
	# {"result": "clear"|"edge"|"land"|"ship", "blocker": id or "", "shallow_bow": bool}; priority edge (any new hex not
	# TerrainMap.in_bounds), land, ship (others: hex -> ship id), else clear; shallow_bow = new bow in a shallow area and not in old_hexes
static func order_task(ship: ShipState, order: String) -> Dictionary     # {} or {"code", "params"} (spec §3; prepare_springs -> PBS/PSS by the end ready or anchored)
static func refusal(ship: ShipState, code: String, params: Dictionary, ctx: Dictionary, plan_codes: Array) -> String
static func status_text(ship: ShipState) -> String                         # overlay note, e.g. "Anchored by the bow, 2 hexes of cable, springs rigged." / "Bow anchor ready." / ""
```

- `refusal` reads `ctx` keys `wind_speed` (int), `anchoring_here` (bool), `plotted_mps` (int), `final` (bool), and `plan_codes` (the other anchoring codes already accepted in the plan). Reasons, in check order (first that applies):
  - any code, `not ship.crew_can_act()`: `"The crew cannot handle the anchors (struck, or a prize)."`
  - `params` turn for HS not `"port"`/`"starboard"`: `"Handle springs needs a turn to port or starboard (13.D.2)."`
  - `plan_codes.has(code)`: `"One section is enough for %s." % code`.
  - PBA/PSA: anchored → `"Already anchored: cut the cable first (13.F)."`; `anchorings_used >= 2` → `"Anchored twice already (13.A.5)."`; `anchor_ready != ""` → `"An anchor is already ready (13.B.3)."`; a live PSA (for PBA) / PBA (for PSA) task, or the other code in `plan_codes` → `"Only one anchor at a time (13.B.3)."`.
  - PBS (PSS mirrors with stern): `springs_ready` or `has_springs()` → `"The springs are already ready (13.B.4)."`; not (`anchor_ready == "bow"` or anchored with `end == "bow"`) → `"Prepare the bow anchor first (13.B.3)."`; a live PSS task → `"Only one anchor at a time (13.B.3)."`.
  - A: anchored → already anchored; `anchor_ready == ""` → `"Prepare an anchor first (13.B.1)."`; `anchorings_used >= 2` → 13.A.5; not `anchoring_here` → `"The scenario does not allow anchoring here (Scenario Book V.B)."`; `final` and `plotted_mps > 0` → `"MPs plotted: the anchoring is erased (13.C.1)."`.
  - AX, VO, VI, HS not anchored → `"Not anchored."`.
  - AX: `plan_codes` has HS, VO or VI → `"No turn or veering on the g-t the cable is cut (13.F.2)."`.
  - VO: `wind_speed == 0` → `"No wind: a ship cannot veer out (13.E.3)."`; `veered >= 3` → `"Three VOs already (13.E.1c)."`; `is_linked()` → `"Fouled or grappled: cannot veer out."`; `plan_codes` has HS → `"Not on a g-t it turns (13.E.1d)."`; has AX → the 13.F.2 reason; has VI → `"Veer out or veer in, not both."`.
  - VI: `veered == 0` → `"Nothing to veer in (13.E.2)."`; `plan_codes` has HS → `"Not on a g-t it turns (13.E.2)."`; has AX or VO → as above.
  - HS: not `has_springs()` → `"Springs are not rigged (13.D)."`; `wind_speed == 0` → `"No wind: springs cannot be used (13.E.3)."`; `is_linked()` → `"Fouled or grappled ships cannot turn (13.D.2)."`; `plan_codes` has VO, VI or AX → the matching reason.
- `permitted`: absent/`false` → false; `true` → true; a Dictionary: `rows` `[a, b]` with `a <= TerrainMap.axial_to_offset(hex).y <= b`, or `areas` containing `TerrainMap.of(scenario).area_at(hex).name`; anything else false.
- `scenario_errors`: `anchoring` neither bool nor Dictionary (`"Anchoring: anchoring must be true, false or a zone"`); a zone with no `rows`/`areas`, `rows` not two ints a ≤ b (`"Anchoring: rows must be [first, last]"`), an unknown area (`"Anchoring: unknown area %s"`); per ship `anchor`: `end` not bow/stern (`"Anchoring: ship '%s' anchor end must be bow or stern"`), `cable` not 1–4 (`"Anchoring: ship '%s' cable must be 1-4"`), `hex` off the map (`"Anchoring: ship '%s' anchor is off the map"`).
- `swing_step`: `facing == proper` → `{facing, swing_dir: 0}`; direction = `swing_dir` if non-zero, else `diff = (proper - facing + 6) % 6`: 1–2 → +1, 4–5 → −1, 3 → −1 when `roll <= 3` else +1; new facing `(facing + dir + 6) % 6`; returned `swing_dir` is 0 when the new facing is proper, else `dir`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchor_rules.gd` (wind 0, so downwind 3 = W):
  - `test_proper_facing`: bow, wind 0 → 0; stern, wind 0 → 3; bow, wind 4 → 4.
  - `test_footprint_bow_anchor`: anchor (0, 0), bow, cable 1, facing 0, wind 0 → `[(-1, 0), (-2, 0)]`; cable 2 → `[(-2, 0), (-3, 0)]`; cable 0 → `[(0, 0), (-1, 0)]`.
  - `test_footprint_stern_anchor`: anchor (1, 0), stern, cable 1, facing 3, wind 0 → `[(-1, 0), (0, 0)]`.
  - `test_footprint_oblique_after_wind_shift` (13.C.6): anchor (0, 0), bow, cable 1, facing 1, wind 1 → `[(0, -1), (0, -2)]`.
  - `test_spring_turn_bow_pivots_on_bow`: ship bow (-1, 0) facing 0, anchored bow: direction −1 → facing 5, hexes `[(-1, 0), (-2, 1)]`; +1 → facing 1, `[(-1, 0), (-1, -1)]`.
  - `test_spring_turn_stern_pivots_on_stern` (13.D.2): ship bow (-1, 0) facing 3, anchored stern (stern (0, 0)): +1 → facing 4, `[(0, -1), (0, 0)]`; −1 → facing 2, `[(-1, 1), (0, 0)]`.
  - `test_swing_step`: (1 → 0) gives `{0, 0}`; facing 2 proper 0 swing 0 → `{1, -1}`; facing 3 proper 0 swing 0 roll 2 → `{2, -1}`; roll 5 → `{4, 1}`; facing 2 proper 0 swing +1 (already turning starboard) → `{3, 1}`; `needs_swing_roll(3, 0, 0)` true, `(3, 0, 1)` false, `(2, 0, 0)` false.
  - `test_permitted`: `{}` false; `{"anchoring": true}` true; `{"anchoring": {"rows": [-2, 2]}}`: (0, 2) true, (0, 3) false; areas: a scenario with shallow area "A" on `[[2, 0]]` and `"anchoring": {"areas": ["A"]}`: (2, 0) true, (3, 0) false.
  - `test_scenario_errors`: `"anchoring": 3` → 1 error; `{"rows": [3, 1]}` → 1; `{"areas": ["Q"]}` → 1; a ship `"anchor": {"end": "mast"}` → 1; `"cable": 5` → 1; a valid scenario → none.
  - `test_refusal_preparation` (13.B): fresh ship: PBA "" ; with `anchor_ready = "bow"`: PBA "An anchor is already ready (13.B.3).", PSA the same, PBS "", PSS "Prepare the stern anchor first (13.B.3)."; with a live PBA task: PSA "Only one anchor at a time (13.B.3)."; `anchorings_used = 2`: PBA "Anchored twice already (13.A.5)."
  - `test_refusal_anchor`: no anchor ready → "Prepare an anchor first (13.B.1)."; ready, `anchoring_here` false → the V.B reason; ready, here, `plotted_mps` 2, `final` false → ""; `final` true → "MPs plotted: the anchoring is erased (13.C.1)."
  - `test_refusal_while_anchored`: anchored bow with springs, `veered` 3: VO "Three VOs already (13.E.1c)."; VI ""; HS `{"turn": "port"}` ""; HS at wind 0 → 13.E.3; VO with `plan_codes ["HS"]` → 13.E.1d; AX with `["VO"]` → 13.F.2; HS with empty params → the 13.D.2 params reason; fouled (`fouled_with = "b"`) HS → "Fouled or grappled ships cannot turn (13.D.2)."; PBS while anchored by the bow with springs → "The springs are already ready (13.B.4)."; PBS anchored by the bow without springs → "".
  - `test_refusal_struck`: struck ship, any code → "The crew cannot handle the anchors (struck, or a prize)."
  - `test_order_task`: `"prepare_bow"` → `{"code": "PBA", "params": {}}`; `"prepare_springs"` with `anchor_ready == "stern"` → PSS; anchored by the bow → PBS; `"turn_port"` → `{"code": "HS", "params": {"turn": "port"}}`; `""` → `{}`; `"bogus"` → `{}`.
  - `test_forced_check`: 10 × 10 board, land (-3, 0): new hexes `[(-2, 0), (-3, 0)]` → land; `[(-6, 0), (-7, 0)]` → edge; others `{(-2, 0): "b"}` → ship, blocker "b"; shallow area on (-1, 0), old `[(0, 0), (-1, 0)]`, new `[(-1, 0), (-2, 0)]` → clear, `shallow_bow` false (bow was already in it); old `[(0, 0), (1, 0)]` → `shallow_bow` true.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Implement `scripts/server/anchor_rules.gd`.**
- [ ] **Step 4: Run and confirm everything passes.** `make import && make test`.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/anchor_rules.gd test/unit/test_anchor_rules.gd
git commit -m "feat: AnchorRules, the legality, permission and geometry of anchoring"
```

### Task 4: Anchoring in the crew plan (manual and Automatic) and the anchor station

**Files:**
- Modify: `scripts/server/crew_rules.gd` (`context`, `normalize`, `refusal`, `station_of`, `stations`, `task_name`), `scripts/server/crew_auto.gd` (`allocate`, rule A2c, header), `scripts/server/crew_task_controller.gd` (`plot_crew`), `data/ui/deck_layouts.json`.
- Test: create `test/unit/test_crew_anchoring.gd`.

**Interfaces:**
- Consumes Tasks 1–3.
- `CrewRules.context` adds `"wind_speed": int` (environment wind speed, 0 with no environment) and `"anchoring_here": AnchorRules.permitted(game_state.active_scenario, AnchorRules.drop_hex(ship))` (false with no game state).
- `CrewRules.normalize`, manual branch: before the per-section loop, sections are walked in ascending order; an entry with `AnchorRules.is_code(code)` gets `why = AnchorRules.refusal(ship, code, entry.params, ctx, accepted)` where `accepted` is the anchoring codes kept so far; when `why == ""` the code is appended to `accepted`, `entry["params"]` is `{}` except HS (`{"turn": params.turn}`); A kept with `plotted_mps > 0` and not `final` adds the warning `"%s: anchoring needs a plot of no MPs; erased at End Planning unless the course is cut (13.C.1)."`. A refused entry is dropped with the warning `"<section>: <why>"` as other codes are.
- `CrewAuto.allocate`, new rule **A2c** after A2b and before A3: `var wanted := AnchorRules.order_task(ship, str(orders.get("anchor", "")))`; if not empty, `accepted` = anchoring codes already in `taken`, and `AnchorRules.refusal(ship, wanted.code, wanted.params, ctx, accepted) == ""`, the first section of `CrewRules.worker_order(ship, ctx, taken)` (if any) gets `wanted`. Document A2c in the header list.
- `CrewTaskController.plot_crew`: `orders.anchor` not in `AnchorRules.ORDERS` → returns `"Unknown anchor order %s"`.
- `CrewRules.station_of`: any `AnchorRules.is_code(code)` → `AnchorRules.STATION` (`"anchor"`).
- `CrewRules.refusal(…, station_id == "anchor")` → `"Anchoring is ordered with the crew orders (anchor), not by placing sections here."`
- `CrewRules.stations`: after the repairs, an `"anchor"` station (`make.call("anchor", "", 0, 0, "none", AnchorRules.status_text(ship))`, label `"Anchor & cable"`, short `"Anc"`) when `ship.is_anchored()`, `anchor_ready != ""`, `springs_ready`, or a section is on it; its `disabled_reason` is the refusal text above. Add `"anchor"` to `STATION_LABELS` / `STATION_SHORT`.
- `CrewRules.task_name`: the nine codes named as in `PhaseEvents.CREW_TASK_NAMES` gerunds ("preparing the bow anchor", …).
- `deck_layouts.json` `stations` gains `"anchor": {"decks": ["upper"], "rect": [830, 252, 150, 90]}`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_crew_anchoring.gd` (a `GameState` fixture as Task 2's, scenario `{"anchoring": true}`, wind speed 3, one ship CQ C with `crew_auto` per test):
  - `test_auto_prepare_bow_takes_marines`: auto ship, order `{"anchor": "prepare_bow"}` → `CrewAuto.allocate(...)` assigns `{"code": "PBA", "params": {}}` to section 4 (marines, first in worker order) and nothing else anchoring.
  - `test_auto_anchor_refused_without_ready_anchor`: order `"anchor"`, `anchor_ready == ""` → no A assigned.
  - `test_auto_anchor_not_where_forbidden`: `anchoring` false, `anchor_ready = "bow"`, order `"anchor"` → no A.
  - `test_auto_turn_with_springs`: anchored bow with springs (via `drop_anchor`), order `"turn_starboard"` → HS `{"turn": "starboard"}` on section 4.
  - `test_prep_continues_as_task_in_progress`: a live PBA task on section 3 (`add_task` with `started_turn` the previous turn), no anchor order → `allocate` keeps section 3 on PBA (rule A2).
  - `test_manual_conflicts_dropped`: manual ship anchored with springs, `veered` 1; plan `{0: HS port, 1: VI, 2: VO}` → `normalize` keeps 0 (HS), drops 1 and 2 with warnings containing "13.E.2" and "13.E.1d".
  - `test_manual_anchor_with_course_kept_then_erased`: manual ship, `anchor_ready = "bow"`, stored movement of 2 steps; plan `{4: A}`: `ctx.final` false → kept with a warning containing "13.C.1"; `ctx.final` true → dropped.
  - `test_plot_crew_rejects_unknown_order`: `plot_crew(0, "a", {"assignments": {}, "orders": {"anchor": "drop"}})` in PLANNING → `"Unknown anchor order drop"`.
  - `test_anchor_order_lapses`: after `ShipStateController.clear_crew_plot("a")`, `plotted_actions.crew_orders.get("anchor", "") == ""`.
  - `test_anchor_station_read_only`: anchored ship with a section on HS → `stations()` has id `"anchor"` with `accepts == "none"`, that section in `occupants`, note from `status_text`; `refusal(..., 3, "anchor")` contains "crew orders"; no anchor state and no task → no `"anchor"` station.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green (`test_crew_auto.gd`, `test_crew_rules*.gd` unchanged).
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/crew_rules.gd scripts/server/crew_auto.gd scripts/server/crew_task_controller.gd data/ui/deck_layouts.json test/unit/test_crew_anchoring.gd
git commit -m "feat: anchoring tasks in the crew plan, Automatic rule A2c and a read-only anchor station"
```

### Task 5: `AnchorController` as the task handler

**Files:**
- Create: `scripts/server/anchor_controller.gd`.
- Modify: `scripts/autoload/game_state.gd` (`anchor_controller`, created in `_initialize_server_controllers` after `crew_task_controller` and `map_controller`, registered for every `AnchorRules.CODES` code).
- Test: create `test/unit/test_anchor_controller.gd`.

**Interfaces (Produces):** `class_name AnchorController extends CrewTaskHandler` (header cites 13.B–F, SoP V.A–B, spec §3–§5):

```gdscript
func _init(p_game_state: Node) -> void
func actual_steps(ship: ShipState) -> int   # stored movement size when plotted_actions.movement_plotted, else DefaultCourse.for_ship(game_state, ship).size()
func live_this_turn(ship: ShipState, code: String) -> Dictionary  # the live task with this code and started_turn == current_turn, or {}
# CrewTaskHandler overrides:
func prepare(ship: ShipState, candidate: Dictionary) -> String  # AnchorRules.refusal with CrewRules.context(...) + final true + plotted_mps = actual_steps(ship); plan_codes = []
func on_complete(ship: ShipState, task: Dictionary, phase: int) -> void
func cancel_reason(ship: ShipState, task: Dictionary) -> String
```

- `on_complete`: `super`, then PBA → `set_anchor_ready(id, "bow")`; PSA → `"stern"`; PBS → if anchored with `end == "bow"`: `update_anchor(id, {"springs": true})`, else `set_springs_ready(id, true)`; PSS mirrors with stern.
- `cancel_reason`: `super` first; PBA/PSA: anchored → `"anchored"`; PBS: not (`anchor_ready == "bow"` or anchored by the bow) → `"no bow anchor"`; PSS: `"no stern anchor"`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchor_controller.gd` (fixture: `GameState` with `current_turn = 3`, scenario `{"anchoring": true}`, `GameState.phase_controller.current_phase` set to PLANNING for `plot_crew`; drive the real engine: `crew_task_controller.plot_crew` / `begin_turn_tasks` / `advance_tasks`):
  - `test_handlers_registered`: `crew_task_controller.handler(code) == GameState.anchor_controller` for all nine codes.
  - `test_pba_two_turns_then_ready` (CQ C): plot `{4: PBA}` (manual crew) on turns 3 and 4 (each turn `begin_turn_tasks`, then `advance_tasks`) → after turn 3 `anchor_ready == ""`, after turn 4 `"bow"`; a CREW_TASK `completed` event for PBA.
  - `test_pbs_after_anchoring_rigs_springs` (13.B.2): ship anchored by the bow without springs, CQ A (PBS 4 turns): 4 turns of PBS → `anchor.springs == true`, `springs_ready == false`.
  - `test_pbs_before_anchoring_sets_springs_ready`: `anchor_ready = "bow"`, CQ A → after 4 turns `springs_ready == true`.
  - `test_anchor_with_mps_is_erased` (13.C.1): `anchor_ready = "bow"`, speed 2, stored movement of 2 forward steps, plan `{4: A}` stored before End Planning; `begin_turn_tasks` → no live A task; a CREW_TASK event with state `"refused"` and reason containing "13.C.1".
  - `test_anchor_with_default_course_is_erased`: as above, `movement_plotted` false and speed 2 (default course 2 steps) → refused.
  - `test_prep_cancelled_when_cable_cut`: anchored by the bow, live PBS task; `cut_cable` → next `advance_tasks` ends the task with reason `"no bow anchor"`.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make import && make test`.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/anchor_controller.gd scripts/autoload/game_state.gd test/unit/test_anchor_controller.gd
git commit -m "feat: AnchorController handles the anchoring crew tasks"
```

### Task 6: The anchoring step after drift (SoP V.A–B)

**Files:**
- Modify: `scripts/server/anchor_controller.gd`, `scripts/server/drift_resolver.gd` (`_holds_group`, public `leeward_first`), `scripts/server/turn_phase_controller.gd` (`_enter_drift_calculation_phase`), `scripts/server/phase_events.gd` (types `ANCHORED`, `ANCHOR_MOVE`, `CABLE_CUT` and their `to_text`), `scripts/server/map_controller.gd` (only if `ground` needs the `anchor` cause in its text).
- Test: create `test/unit/test_anchoring_drift.gd`.

**Interfaces:**
- `static func leeward_first(ships: Array[ShipState], downwind_dir: int) -> Array[ShipState]` on `DriftResolver` (the existing sort, moved; `resolve` uses it; no behaviour change).
- `DriftResolver._holds_group(ship)` → `ship.is_aground() or ship.is_anchored()`.
- `AnchorController.resolve_anchoring(phase: int) -> void` (server only): spec §4 exactly — part V.A for every ship of `game_state.ships_on_map()` that `is_anchored()`, not destroyed, `anchor.turn < current_turn`, in `DriftResolver.leeward_first` order, skipped entirely at wind speed 0; then part V.B by ship id: drop (live A started this turn: `drop_anchor(id, {"hex": AnchorRules.drop_hex(ship), "end": ship.anchor_ready, "springs": ship.springs_ready, "cable": 0, "veered": 0, "swing_dir": 0, "wind_dir": wind_direction, "turn": current_turn})`) and cut (live AX started this turn: `cut_cable(id, current_turn)`).
- V.A per ship: facing (normal: `needs_swing_roll` → `game_state.dice.d6()`, then `swing_step`; springs: `facing + delta` where `delta = ((wind_direction - anchor.wind_dir + 9) % 6) - 3`); `cable` (0 → 1, `settle`); live VO started this turn → +1 (`veer_out`); `causes` also gets `wind` when `wind_direction != anchor.wind_dir`, `swing` when the facing changes for a normal anchor; the footprint `AnchorRules.footprint(anchor.hex, end, cable, new_facing, wind_direction)`; if it equals `occupied_hexes()` only the anchor fields are stored (`cable`, `veered`, `swing_dir`, `wind_dir`), no event; if the ship `is_linked()`: hold, `blocked: "linked"`; else `AnchorRules.forced_check(scenario, occupied_hexes(), new, Occupancy.build(game_state.ships_on_map(), [id]))`:
  - clear: if `shallow_bow`, depth = area base + `game_state.dice.d6()`; depth ≤ `ship.ship.draft` → `map_controller.ground(id, {"cause": "anchor", "terrain": "shallow", "hex": {...}, "depth": depth, "draft": draft}, phase)` and hold (`blocked: "land"`); else move (`set_ship_position(new[0])`, `set_ship_facing`), `update_anchor` with the new `cable`, `veered`, `swing_dir`, `wind_dir`.
  - ship: `fouled = null` when either ship is fouled, dismasted or destroyed, else `game_state.movement_resolver.roll_fouling(ship, blocker, true)`, and on true `set_fouled_with` both ways; hold.
  - land: `map_controller.ground(id, {"cause": "anchor", "terrain": "land", "hex": {first land hex of new}, "depth": -1, "draft": draft}, phase)`; hold.
  - edge: hold.
  - hold: facing unchanged; `update_anchor(id, {"cable": 1 if the old cable was 0 else the old cable, "swing_dir": swing_dir})` (the 13.C.5 settle is kept and retried next g-t; a VO is lost; a rolled swing direction is kept); `veered` and `wind_dir` unchanged.
- `ANCHOR_MOVE` data: `{"causes": [...], "from_facing", "to_facing", "roll": d6 or -1, "from": {"q", "r"}, "to": {"q", "r"}, "cable", "blocked": "" | "ship" | "land" | "edge" | "linked", "fouled": bool or null}`, target the blocker. `ANCHORED` data `{"end", "springs", "hex": {"q", "r"}}`; `CABLE_CUT` data `{"hex": {"q", "r"}}`. `to_text` lines as spec §9.
- `_enter_drift_calculation_phase`: `game_state.drift_resolver.resolve(...)`, then `if game_state.get("anchor_controller") != null: game_state.anchor_controller.resolve_anchoring(GamePhase.DRIFT_CALCULATION)`, then `advance_phase()`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchoring_drift.gd` (wind 0, speed 3; 40 × 30 board unless the test needs none; `current_turn = 2`; anchors placed with `drop_anchor`):
  - `test_no_anchor_no_change`: two unanchored ships, a full `_enter_drift_calculation_phase`-equivalent (`drift_resolver.resolve` then `resolve_anchoring`) uses exactly the dice the drift alone uses (queue as for drift; `remaining() == 0`) and logs no anchoring event.
  - `test_settle_and_swing_after_anchoring` (13.C.4–5, Diagram 25 A→B): bow (0, 0) facing 1, anchor `{hex (0, 0), end bow, cable 0, turn 1}` → facing 0, `hex_position == (-1, 0)`, stern (-2, 0), `anchor.cable == 1`, `ANCHOR_MOVE.causes == ["swing", "settle"]`, no die.
  - `test_settled_ship_does_not_drift_again` (Diagram 25 C): anchor (0, 0), bow (-1, 0) facing 0, cable 1 → no event, no die, position unchanged.
  - `test_opposite_swing_rolls_d6` (13.C.4): bow anchor laid at WF=R: anchor (0, 0), bow (-1, 0) facing 3, cable 1; queue `[2]` → facing 2, `swing_dir == -1`, `roll == 2`; next turn (`current_turn = 3`, no die queued) → facing 1; next → facing 0, `swing_dir == 0`. With queue `[5]` the first step gives facing 4, `swing_dir == 1`.
  - `test_stern_anchor_settles` (Diagram 25 E→F): bow (0, 0) facing 3, anchor `{hex (1, 0), end stern, cable 0, turn 1}` → bow (-1, 0), stern (0, 0), facing 3.
  - `test_wind_shift_oblique` (13.C.6): anchor (0, 0), bow (-1, 0) facing 0, cable 1, `wind_dir` 0; set wind direction 1 → facing 1, bow (0, -1), causes contains `"wind"`.
  - `test_springs_keep_wind_facing` (13.D.1): as above with `springs: true` and facing 5 (WF=C), bow (-1, 0); wind to 1 → facing 0 (still WF=C), bow (0, -1).
  - `test_veer_out_moves_one_hex` (13.E.1): settled at cable 1, a live VO task started this turn → bow (-2, 0), `cable == 2`, `veered == 1`, cause `veer_out`.
  - `test_wind_zero_nothing_moves` (13.E.3): wind speed 0, anchor cable 0 → no move, `cable == 0`, no die; a live A task this turn still drops.
  - `test_blocked_by_ship_rolls_fouling_and_holds`: settling ship (bow (0, 0) facing 0, anchor (0, 0), cable 0, FS sail); blocker bow (-2, 0) facing 1 (FS); queue `[9]` → ship still at (0, 0) facing 0, fouled with the blocker, `ANCHOR_MOVE.blocked == "ship"`, `fouled == true`, `anchor.cable == 1`. Queue `[0]` → not fouled. Next turn with the blocker gone, the ship settles to (-1, 0).
  - `test_veer_out_lost_when_blocked`: settled at cable 1, VO this turn, blocker on (-3, 0) → `cable == 1`, `veered == 0`, position unchanged.
  - `test_forced_move_onto_land_grounds`: land at (-2, 0), settling ship as above → `is_aground()`, position unchanged, an `AGROUND` event with cause `anchor`, no rigging lost.
  - `test_forced_move_off_map_holds`: a 10 × 10 board, anchor (-5, 0) on the west column, bow (-5, 0) facing 0, cable 0 → `blocked == "edge"`, ship on the map, status ACTIVE (also with the W edge `none`).
  - `test_linked_anchored_ship_holds`: settling ship grappled to another → `blocked == "linked"`, no die.
  - `test_drop_after_drift` (13.C.2): ship at speed 0, `anchor_ready = "bow"`, a live A task started this turn, `moved_this_turn` false; queue the drift d10 so it drifts (MS at WS 3: see `drifting_table.json`) → the ship drifts one hex west first, then `is_anchored()`, `anchor.hex == hex_position` after the drift, `anchor.cable == 0`, `anchorings_used == 1`, `ANCHORED` logged after `DRIFT`.
  - `test_anchored_group_does_not_drift` (8.A.6): an anchored ship fouled with an unanchored stopped ship → `drift_resolver.resolve` rolls nothing for the group (`remaining() == 0`).
  - `test_cut_removes_anchor`: anchored ship with a live AX task this turn → not anchored, `cable_cut_turn == 2`, `CABLE_CUT` logged; it still rode to its anchor in V.A first (cable 0 → settled position) — assert the `ANCHOR_MOVE` precedes `CABLE_CUT`.
  - `test_drift_phase_runs_anchoring`: calling `GameState.phase_controller._enter_drift_calculation_phase()` directly (as other phase tests call phase entries; stub `advance_phase` side effects as they do), a settling ship ends settled.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green (`test_drift_resolver.gd`, `test_drift_terrain.gd` unchanged).
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/anchor_controller.gd scripts/server/drift_resolver.gd scripts/server/turn_phase_controller.gd scripts/server/phase_events.gd scripts/server/map_controller.gd test/unit/test_anchoring_drift.gd
git commit -m "feat: ride to the anchor after drift: swing, settle, wind shift, veer out, drop and cut"
```

### Task 7: The springs step and the in-irons exceptions

**Files:**
- Modify: `scripts/server/anchor_controller.gd`, `scripts/server/turn_phase_controller.gd` (`_enter_movement_resolution_phase`), `scripts/server/movement_resolver.gd` (`_is_in_irons`), `scripts/server/phase_events.gd` (types `SPRING_TURN`, `VEER_IN`, `to_text`).
- Test: create `test/unit/test_anchoring_movement.gd`.

**Interfaces:**
- `AnchorController.resolve_spring_step(phase: int) -> void` (server only), spec §5: for every anchored, not destroyed ship of `ships_on_map()` by id: a live HS started this turn → `AnchorRules.spring_turn(ship, -1 if port else 1)`; refused (`SPRING_TURN.refused`) at wind 0 (`"no wind (13.E.3)"`), without springs (`"springs not rigged (13.D)"`), linked (`"fouled or grappled (13.D.2)"`), or when `forced_check` against `Occupancy.build(ships_on_map(), [id])` is `ship` (`"%s holds the hex" % blocker name`), `land` (`"land"`), `edge` (`"the edge of the map"`); else `set_ship_position(hexes[0])`, `set_ship_facing`. Then a live VI started this turn → `footprint(anchor.hex, end, cable - 1, facing, wind_direction)`; clear → move, `update_anchor(id, {"cable": cable - 1, "veered": veered - 1})`; else `VEER_IN.refused` (same wording). `SPRING_TURN` data `{"direction", "pivot": end, "from_facing", "to_facing", "refused"}`; `VEER_IN` data `{"cable", "refused"}`. No dice.
- `_enter_movement_resolution_phase`: right after `begin_turn_tasks`, `if game_state.get("anchor_controller") != null: game_state.anchor_controller.resolve_spring_step(current_phase)`, before `_resolution_rng_state` is taken.
- `MovementResolver._is_in_irons`: returns false when `ship_state.is_anchored()` (5.D.4a) or `game_state and ship_state.cable_cut_turn >= 0 and ship_state.cable_cut_turn == game_state.current_turn - 1` (5.D.4b, 13.F.3); otherwise unchanged.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchoring_movement.gd`:
  - `test_spring_turn_bow`: anchored bow with springs at bow (-1, 0) facing 0 (anchor (0, 0), cable 1), live HS `{"turn": "starboard"}` this turn → facing 1, bow (-1, 0), stern (-1, -1); `SPRING_TURN.refused == ""`, `pivot == "bow"`.
  - `test_spring_turn_stern_pivot` (13.D.2): anchored stern with springs, stern (0, 0), bow (-1, 0), facing 3, HS port → facing 2, bow (-1, 1), stern (0, 0).
  - `test_spring_turn_refused_when_held`: another ship holding (-1, -1) → facing 0 unchanged, `refused` contains its name; no collision, no fouling (no die).
  - `test_spring_turn_refused_without_wind`: wind speed 0 → refused `"no wind (13.E.3)"`.
  - `test_veer_in` (13.E.2): anchor (0, 0), bow anchor, cable 2, veered 1, bow (-2, 0), stern (-3, 0), facing 0, VI this turn → bow (-1, 0), stern (-2, 0), `cable == 1`, `veered == 0`, `VEER_IN.refused == ""`.
  - `test_veer_in_blocked`: as above with another ship holding (-1, 0) → position unchanged, `cable == 2`, `VEER_IN.refused != ""`, no fouling, no die.
  - `test_spring_turn_before_movement`: a full `_enter_movement_resolution_phase` on a two-ship setup: anchored springs ship turning starboard and a second ship whose plotted course ends in (-1, -1) → the spring turn is made (logged in the turn log before any movement result) and the second ship meets the anchored ship's stern as a stationary ship in the resolver (collision or bear-off per the existing rules; assert it does not end in (-1, -1)).
  - `test_spring_turn_survives_bear_off_rerun`: with `bear_off_prompt_player_ids = [0]` and a prompted potential collision elsewhere, `player_submit_bear_off` re-runs the resolver; the anchored ship's facing stays turned and only one `SPRING_TURN` event is logged.
  - `test_anchored_never_in_irons` (5.D.4a): anchored bow ship at WF=L (facing == wind direction), speed 0, run the resolver → no IN_IRONS result for it, `immobilized` false.
  - `test_free_turn_after_cut` (5.D.4b, 13.F.3): unanchored ship at WF=L, speed 0, `cable_cut_turn = current_turn - 1`, plotted MA-0 turn: the Tacking roll's DRMs do not include the +1 for irons (compare against the same ship with `cable_cut_turn = -1`: DRM total one lower); with no turn plotted, no `remain in irons` event.
  - `test_in_irons_again_next_turn`: `cable_cut_turn = current_turn - 2` → in irons as usual.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, the movement resolver suites unchanged.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/anchor_controller.gd scripts/server/turn_phase_controller.gd scripts/server/movement_resolver.gd scripts/server/phase_events.gd test/unit/test_anchoring_movement.gd
git commit -m "feat: spring turns and veering in before movement; anchored and just-cut ships are not in irons"
```

### Task 8: Gunnery +1 when anchored; limited information

**Files:**
- Modify: `scripts/server/gunnery_calculator.gd` (`preview`), `scripts/server/phase_events.gd` (`MODIFIER_LABELS`), `scripts/server/player_view.gd` (`ship_for`, `events_for`).
- Test: create `test/unit/test_anchor_visibility.gd`.

**Interfaces:**
- `GunneryCalculator.preview`: after `wind_speed_4`, `if firer.is_anchored(): _add_modifier(p, "anchored", tables.flat_modifier("anchored"))` (7.C.12c). `MODIFIER_LABELS["anchored"] = "anchored"`.
- `PlayerView.ship_for`, for a reader who does not command the ship (with `limited()` on): drop `anchor_ready` and `springs_ready`; remove from `crew_tasks` every entry whose `code` is in `AnchorRules.PREP_CODES`. `anchor`, `anchorings_used`, `cable_cut_turn` stay.
- `PlayerView.events_for`: with `limited()` on, skip a `CREW_TASK` event whose `data.code` is in `AnchorRules.PREP_CODES` when the reader does not command `ev.ship_id`. Update the class header.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchor_visibility.gd`:
  - `test_anchored_firer_gets_plus_one` (7.C.12c): two identical firers against the same target at range 3, one anchored (bow anchor dropped earlier) → its `ShotPreview` has modifier `"anchored": 1` and an MGN exactly 1 higher; the other has no `"anchored"` key.
  - `test_no_bonus_on_anchoring_turn`: a ship with a live A task started this turn and `anchor_ready = "bow"`, not yet anchored → no `"anchored"` modifier.
  - `test_bonus_on_cut_turn`: an anchored ship with a live AX task this turn → `"anchored": 1`.
  - `test_preparation_hidden_from_enemy`: ship "a" (player 0) with `anchor_ready = "bow"`, `springs_ready = true` and a live PBS task; `ship_for(1, "a")` lacks `anchor_ready`, `springs_ready` and any PBS entry in `crew_tasks`; `ship_for(0, "a")` has them all.
  - `test_anchor_public`: anchored "a" → `ship_for(1, "a").anchor.cable` equals the ship's cable.
  - `test_prep_events_hidden`: a CREW_TASK event for PBA and one for A on "a" → `events_for(1, turn)` has the A event only; `events_for(0, turn)` both; with `"tournament": true`, player 1 sees both.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/gunnery_calculator.gd scripts/server/phase_events.gd scripts/server/player_view.gd test/unit/test_anchor_visibility.gd
git commit -m "feat: anchored ships fire with +1 (7.C.12c); anchor preparations are hidden from other players"
```

### Task 9: Scenario permission, starting anchors and Developer UI commands

**Files:**
- Modify: `scripts/server/anchor_controller.gd` (`place_scenario_anchors`, `drop_now`, `cut_now`), `scripts/autoload/game_state.gd` (`start_new_game`, `placement_errors`), `scripts/server/dev_commands.gd`, `scripts/ui/developer_ui.gd`.
- Test: create `test/unit/test_anchor_scenario.gd`.

**Interfaces:**
- `AnchorController.place_scenario_anchors() -> void` (server only): for each entry of `game_state.active_scenario.ships` with an `"anchor"` Dictionary, the ship of that `id`: `end` (required), `springs` (default false), `cable` (default 1), `hex` (`[q, r]`, default `anchored end hex + cable × HexGrid.DIRECTIONS[wind_direction]`, i.e. upwind) → `drop_anchor(id, {"hex", "end", "springs", "cable", "veered": cable - 1, "swing_dir": 0, "wind_dir": wind_direction, "turn": 0})`. The anchored end hex is the bow for `bow`, `HexGrid.stern_of(bow, facing)` for `stern`. No event.
- `GameState.start_new_game` calls it once the environment is initialized (after `environment.initialize_from_scenario`, before `game_started` is emitted). `placement_errors` appends `AnchorRules.scenario_errors(active_scenario)`.
- `AnchorController.drop_now(ship_id: String, end: String, springs: bool, phase: int) -> String` and `cut_now(ship_id: String, phase: int) -> String` (server only; "" or a reason: unknown ship, out of play, not on the map, already / not anchored, end not bow/stern): drop as in V.B at once (`anchor.turn = current_turn`, cable 0, logs `ANCHORED`), cut logs `CABLE_CUT`.
- `DevCommands.anchor_ship(ship_id: String, end: String = "bow", springs: bool = false) -> String` and `DevCommands.cut_anchor_cable(ship_id: String) -> String`: `_refusal()` first, then the controller calls; `Trace` a line.
- `developer_ui.gd`: beside "Start fire", buttons "Anchor" (`anchor_ship(sid)`) and "Cut cable" (`cut_anchor_cable(sid)`), each logging the result and emitting `ship_changed` on success, as `_on_start_fire_pressed` does.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchor_scenario.gd`:
  - `test_starting_anchor_upwind_of_bow`: scenario wind direction 0, ship bow (0, 0) facing 0 with `"anchor": {"end": "bow", "springs": true, "cable": 1}`, `start_new_game` → `anchor.hex == Vector2i(1, 0)`, `has_springs()`, `anchorings_used == 1`, `anchor.turn == 0`, `cable == 1`, `veered == 0`, ship position unchanged; then `resolve_anchoring` on turn 1 moves nothing (no die).
  - `test_starting_stern_anchor_cable_two`: bow (0, 0) facing 3, `{"end": "stern", "cable": 2}`, wind 0 → stern (1, 0), `anchor.hex == Vector2i(3, 0)`, `veered == 1`.
  - `test_explicit_anchor_hex`: `"hex": [2, 0]` is used as given.
  - `test_placement_errors_report_anchor_mistakes`: `"anchoring": "yes"` and a ship `"anchor": {"end": "bow", "cable": 7}` → two errors starting `"Anchoring: "`.
  - `test_dev_anchor_and_cut`: `dev_commands.anchor_ship("a")` → `""`, anchored by the bow at its bow hex, `ANCHORED` logged; again → a non-empty reason; `cut_anchor_cable("a")` → `""`, not anchored, `CABLE_CUT` logged.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, `test_server_authority.gd` included (the Developer UI calls only `dev_commands`).
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/anchor_controller.gd scripts/autoload/game_state.gd scripts/server/dev_commands.gd scripts/ui/developer_ui.gd test/unit/test_anchor_scenario.gd
git commit -m "feat: scenario anchoring permission and starting anchors; Developer UI anchor and cut"
```

### Task 10: Stub AI and the ANCHOR / CUT CABLES signals

**Files:**
- Modify: `scripts/server/stub_ai.gd` (`assign_crew`, `_get_strategy`, `_plot_ship`, new functions), `scripts/server/signal_orders.gd` (`parse`, header).
- Test: create `test/unit/test_stub_ai_anchoring.gd`; add to `test/unit/test_signal_orders.gd`.

**Interfaces:**
- `SignalOrders.parse`: `"ANCHOR"` → `{"order": "anchor"}`; `"CUT"` followed by `"CABLES"` or `"CABLE"` → `{"order": "cut"}` (both words consumed); a lone `"CUT"` is ignored.
- `StubAI`:

```gdscript
const MOVE_ORDERS: Array[String] = ["engage", "close", "follow", "line", "disengage"]
const DRIFT_DANGER_HEXES := 4
func anchor_order(ship_state: ShipState) -> String   # spec §11, one of AnchorRules.ORDERS
func drift_danger(ship_state: ShipState) -> bool      # spec §11
func haul_choice(ship_state: ShipState) -> String     # "", "turn_starboard" or "turn_port"
func wants_to_anchor(ship_state: ShipState) -> bool   # not anchored, may anchor here (AnchorRules.permitted at drop_hex), anchorings_used < 2, and standing order "anchor" or drift_danger
```

  - `assign_crew` sets `{"sail_target": "", "boarding": boarding_order(s), "anchor": anchor_order(s)}`.
  - `anchor_order`: out of play or `not crew_can_act()` → `""`. Anchored: `"cut"` if `ship.standing_order.get("order", "") == "cut"`, or it is in `MOVE_ORDERS` and no enemy in play on the map is within `FireRules.MAX_RANGE` (range between footprints, `fire_geometry.range_between`); else `"prepare_springs"` when `AnchorRules.refusal(ship, PBS-or-PSS, {}, ctx, []) == ""`; else, with springs, `haul_choice`; else `""`. Not anchored and `wants_to_anchor`: `"anchor"` when `anchor_ready != ""`, else `"prepare_bow"` unless a PBA or PSA task is live (then `""`). Otherwise `""`.
  - `haul_choice`: target = the ordered engage target (`order_of(id).target`) if an enemy in play, else `_nearest_enemy`; none or range > 15 → `""`. Score = `_bearing_batteries(hexes, facing, target.occupied_hexes(), occupied, friendly)` for: no turn (current hexes), starboard, port (`AnchorRules.spring_turn`, skipped unless `AnchorRules.forced_check` against the other ships is `clear`). The first candidate in that order with the strictly highest score wins.
  - `drift_danger`: on the map, not anchored, not aground, and (`is_dismasted()` or `ship_controller.get_movement_allowance(id) == 0`); shift `occupied_hexes()` one hex downwind up to `DRIFT_DANGER_HEXES` times; for each shift: any crossing `MapRules.crossing_outcome(...)` of kind LOST, or a new hex `TerrainMap.is_land`, or a new bow with `grounds(hex, draft) == "always"` → true; a BLOCKED crossing (an `open` edge) → false (stop).
  - `_get_strategy`: after the override and escape checks, `"anchor"` when `wants_to_anchor(ship)`; the order `"cut"` maps to `"engage"`. `_plot_ship` treats `"anchor"` like `"hold"` (nothing plotted before `_meet_deceleration_minimum`).

- [ ] **Step 1: Write the failing tests** in `test/unit/test_stub_ai_anchoring.gd` (AI ships of player 1; wind 0 speed 3; 40 × 30 board; `"anchoring": true` unless stated):
  - `test_start_anchored_stays_without_signal`: anchored bow with springs, no stored standing order, no enemy within 15 → `anchor_order != "cut"`.
  - `test_cut_when_signalled_move_and_no_enemy`: stored standing order `{"order": "engage"}` (`set_standing_order`), no enemy within 15 → `"cut"`; an enemy at range 10 → not `"cut"`.
  - `test_cut_cables_signal_cuts_at_once`: stored `{"order": "cut"}`, enemy at range 3 → `"cut"`.
  - `test_prepare_springs_when_anchored`: anchored bow without springs → `"prepare_springs"`; with a live PBS task → not `"prepare_springs"` (it continues by rule A2).
  - `test_haul_to_bear`: anchored bow with springs, bow (0, 0) facing 0, enemy dead ahead at bow (4, 0) facing 1 → `haul_choice` is `"turn_starboard"` or `"turn_port"` and the turned footprint has `_bearing_batteries > 0`; with the enemy on the beam (bow (0, 4)) → `""` when the current facing already bears.
  - `test_haul_skips_blocked_turn`: a friendly ship holding the hex the starboard turn swings into → the choice is not `"turn_starboard"`.
  - `test_emergency_anchoring`: dismasted ship, bow (0, 0) facing 0, land at (-3, 0) → `drift_danger` true; `anchor_order == "prepare_bow"`; with `anchor_ready = "bow"` → `"anchor"`; land at (-8, 0) → `drift_danger` false; a `none` W edge 3 hexes off → true; an `open` edge between the ship and the land → false.
  - `test_no_anchoring_without_permission`: as the emergency case with `"anchoring"` absent → `anchor_order == ""`.
  - `test_anchor_signal_slows_and_anchors`: unanchored AI ship at speed 2 (deceleration ≥ 2 for its type, else pick a speed equal to its deceleration), stored order `{"order": "anchor"}`, `anchor_ready = "bow"`: `plot_all_ai_ships` stores an empty course, the crew plan has A; running the turn's MOVEMENT_RESOLUTION and DRIFT_CALCULATION leaves it anchored.
  - `test_assign_crew_sets_anchor_order`: after `assign_crew`, `plotted_actions.crew_orders.anchor == anchor_order(ship)`.
  - In `test_signal_orders.gd`: `test_anchor_and_cut_cables`: `["ANCHOR"]` → `[{"order": "anchor"}]`; `["CUT", "CABLES"]` → `[{"order": "cut"}]`; `["CUT", "CABLE"]` → same; `["CUT"]` → `[]`; `["ENGAGE", "ANCHOR"]` → two orders, last `anchor`.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, `test_stub_ai.gd` and `test_stub_ai_terrain.gd` unchanged.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/stub_ai.gd scripts/server/signal_orders.gd test/unit/test_stub_ai_anchoring.gd test/unit/test_signal_orders.gd
git commit -m "feat: the stub AI rides at anchor, hauls on springs, cuts on orders and anchors in an emergency"
```

### Task 11: View — anchor markers, cable lines and the ANCHORED badge

**Files:**
- Create: `scripts/view/anchor_markers.gd`.
- Modify: `scripts/core/game_controller.gd` (`_sync_all_views`), `scripts/ui/planning_sail_ui.gd` (`status_badge`, `movement_block_reason`).
- Test: create `test/unit/test_anchor_view.gd`.

**Interfaces:**
- `class_name AnchorMarkers extends Node3D` (modelled on `GrappleLines`; presentation only, never changes state): `func refresh(ships: Array, grid: HexGrid) -> void` (frees its children, then for each marker a dark anchor mesh at the anchor hex and a hemp cable cylinder from it to the anchored end) and `static func markers(ships: Array, grid: HexGrid) -> Array` (`[{"ship_id", "anchor": Vector3, "end": Vector3}]` for every ship that `is_anchored()` and `is_on_map()`, by ship id; `anchor` = `grid.axial_to_world` of `anchor.hex` raised to the rope height, `end` = that of `anchored_end_hex()`).
- `GameController._sync_all_views` creates `anchor_markers` once (`AnchorMarkers.new()`, `add_child`) and calls `refresh(GameState.get_all_ships(), hex_map.get_hex_grid())`, next to `grapple_lines`.
- `PlanningSailUi.status_badge`: `"ANCHORED"` after `"AGROUND"`, before `"DISMASTED"`; `movement_block_reason`: `"ANCHORED": "Ship is anchored: cut the cable (AX) to get under way (13.C.3)."`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchor_view.gd`:
  - `test_markers_for_anchored_ships_only`: ships a (anchored, cable 1), b (not), c (anchored, removed from map) → one marker for a, `anchor` at `axial_to_world` of its anchor hex (x, z) and `end` at its bow.
  - `test_refresh_builds_children`: `refresh` with one anchored ship → at least 2 children; with none → 0.
  - `test_anchored_badge`: anchored ship → `status_badge == "ANCHORED"`, `can_plot_movement == false`, `movement_block_reason` contains "13.C.3"; anchored and aground → `"AGROUND"`.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make import && make test`. Expected: all green, `test_server_authority.gd` included.
- [ ] **Step 5: Check in the running game.** With the godot-mcp tools: `run_project`, start `test_anchorage` once Task 12 adds it (or a scratch copy of its JSON now), `game_screenshot`, confirm the anchor markers and cables, open the crew overlay on an anchored ship (C) and confirm the "Anchor & cable" station; `game_get_errors` returns zero.
- [ ] **Step 6: Commit.**

```bash
git add scripts/view/anchor_markers.gd scripts/core/game_controller.gd scripts/ui/planning_sail_ui.gd test/unit/test_anchor_view.gd
git commit -m "feat: draw anchors and cables, and the ANCHORED badge"
```

### Task 12: Test scenario, scenario schema and the docs

**Files:**
- Create: `data/scenarios/test_anchorage.json`, `test/unit/test_anchorage_scenario.gd`.
- Modify: `.claude/skills/scenario-creator/SKILL.md`, `docs/rules/feature_diff.md`, `CLAUDE.md`.

**Interfaces:**
- `test_anchorage.json`: 40 × 30, edges open; `"anchoring": true`; wind from the east (direction 0), speed 2; side 1 (French): `frigate_38` bow (2, 0) facing 0 with `"anchor": {"end": "bow", "springs": true, "cable": 1}`, `frigate_32` bow (2, 4) facing 3 with `"anchor": {"end": "stern", "cable": 1}`; side 0 (British): `ship_of_line_74` bow (16, -2) facing 3 and `frigate_38` bow (16, 3) facing 3, MS, speed 2; `turn_limit` 20; no ship or anchor off the map or overlapping.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_anchorage_scenario.gd` (whole-loop driving as `test_battle_to_victory.gd`, every player AI):
  - `test_anchorage_places_cleanly`: `placement_errors().is_empty()`; both French ships anchored at the start.
  - `test_anchorage_plays_twelve_turns_cleanly`: 12 turns (or to game over) with no `push_error`; at every END_TURN each French ship is anchored or out of play (no signal tells them to cut); at least one turn's log has a `FIRE` event fired by a French ship (the +1 itself is pinned in Task 8).
  - The existing `test_every_scenario_places_cleanly` (`test_map_scenarios.gd`) covers the new file.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail (file missing).
- [ ] **Step 3: Write the scenario file.**
- [ ] **Step 4: Update `.claude/skills/scenario-creator/SKILL.md`**: `anchoring` (`false` default, `true`, or `{"rows": [first, last]}` / `{"areas": [names]}`; odd-r rows); per-ship `anchor` (`end` required, `springs` false, `cable` 1–4 default 1, `hex` default `cable` hexes upwind of the anchored end; counts as one of the two anchorings); the new validation messages.
- [ ] **Step 5: Update `docs/rules/feature_diff.md`** (invoke `close-action-rules` for the conventions):
  - Header "Compared against": add this sub-project with `git rev-parse --short HEAD`.
  - §2.1: remove the "Anchoring (springs, veering, cutting)" row; in the "General crew-task plotting" row change "**Still missing:** anchoring, towing" to "**Still missing:** towing" and add the anchoring codes to the list of tasks in.
  - §2.2 "Exceptions to being in irons" row: **Fixed** — move to §5 with code `movement_resolver.gd` (`_is_in_irons`).
  - §5 rows ✔: anchoring preparation, anchoring, riding to the anchor (13.B–C, 8.A.7, SoP V.A–B: `anchor_controller.gd` (`resolve_anchoring`), `anchor_rules.gd`); springs (13.D: `resolve_spring_step`, `AnchorRules.spring_turn`); veering (13.E); cutting (13.F); anchored +1 (7.C.12c: `gunnery_calculator.gd` (`preview`)); anchored groups never drift (8.A.6: `drift_resolver.gd` (`_holds_group`)).
  - §4 rows: spring turns and veering in at the start of movement, refused (logged) by a held hex, land or the edge (13.D.2, 13.E.2; U); forced anchored moves never leave the map, land grounds, a ship blocks with a fouling roll, linked ships hold (13.C.4–6, 13.E.1; B); A with MPs erased at End Planning, the deceleration limit stands (13.C.1, 5.E.4; U); anchoring permission field and zones (Scenario Book V.B); a starting anchor counts as one anchoring (13.A.5); no new anchor prepared while anchored (13.B.3); the Automatic anchor order lapses each g-t; preparation hidden from other players (14.C); the AI's anchoring behaviour and drift-danger test.
- [ ] **Step 6: Update `CLAUDE.md`**: Turn Phase Cycle — MOVEMENT_RESOLUTION runs `anchor_controller.resolve_spring_step` after `begin_turn_tasks`; DRIFT_CALCULATION runs `anchor_controller.resolve_anchoring` after drift (V.A ride, V.B drop and cut); Server Objects: `anchor_controller` (`AnchorController`, the nine codes, the two steps, `place_scenario_anchors`, `drop_now`/`cut_now`) and `AnchorRules`; crew-task paragraph: the nine codes, `crew_orders.anchor` and rule A2c; `ShipState` fields (`anchor`, `anchor_ready`, `springs_ready`, `anchorings_used`, `cable_cut_turn`); Ship Status: ANCHORED (`SHIP_ANCHORED`, never drifts, never in irons, +1 BGN); `_is_in_irons` exceptions; Scenarios: `anchoring` and per-ship `anchor`; the event list gains the five types; `stub_ai` (anchor orders, haul, cut, emergency anchoring) and `SignalOrders` (ANCHOR, CUT CABLES); `PlayerView` hides anchor preparation; Developer UI: anchor and cut; Known Limitations: remove "anchoring" from the Milestone 3 list.
- [ ] **Step 7: Run and confirm everything passes.** `make test`. Expected: all green. Then run the `scv-reviewer` agent (CLAUDE.md "SCV Audit") and fix what it finds.
- [ ] **Step 8: Commit.**

```bash
git add data/scenarios/test_anchorage.json test/unit/test_anchorage_scenario.gd .claude/skills/scenario-creator/SKILL.md docs/rules/feature_diff.md CLAUDE.md
git commit -m "docs: anchorage scenario, scenario schema, feature_diff and CLAUDE.md for anchoring"
```
