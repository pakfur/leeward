# Map and Scenario Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Leeward a rectangular board with typed edges, land and shallow water, running aground, casting the lead, escape and reinforcements, all through one general terrain model, played by the stub AI and drawn by a view-only minimum.

**Architecture:**
- A pure `TerrainMap` (state layer) holds the rectangle, typed hexes (land, shallow areas) and typed boundaries; the four map edges are generated boundaries (Task 1).
- A pure `MapRules` holds every rule callers share: what crossing a side means, the forced move, escape permission and the D.1 conditions (Tasks 3, 7, 9).
- A server `MapController` performs the map's state changes: grounding, escaping, losing a ship off the map, arrivals, the END_TURN escape check (Tasks 3, 9, 10).
- The validator, the movement resolver (per segment, under proportional movement), drift, gunnery, victory and the stub AI ask those two (Tasks 4–8, 11, 12). The view draws the result (Task 13). Scenarios and docs close it (Task 14).

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5. `make test` runs the whole suite. Run `make import` before `make test` whenever a task adds a `class_name`.

**Spec:** `docs/superpowers/specs/2026-11-17-map-and-scenario-design.md`. Executors read it alongside this plan; section numbers below (§n) are the spec's. Binding requirements: `docs/superpowers/specs/2026-11-17-subprojects-3-7-decisions.md` §0 and §2. Rules: `docs/rules/close_action.md` 13.G, 7.B.7–9, 2.B.1, 3.A, 6.E.3, 8.A.1, 8.A.5–6, 8.G.1f, Scenario Book III.B–C, V.D, VI.A–B. Invoke the `close-action-rules` skill before game-logic work.

## Global Constraints

- Hexes in JSON are `[q, r]` axial pairs. The board is `map_bounds.height` rows × `map_bounds.width` hexes in odd-r offset: `col = q + (r - (r & 1)) / 2`, rows `-height / 2 … -height / 2 + height - 1`, columns `-width / 2 … -width / 2 + width - 1` (integer division). No `map_bounds` = unbounded, no edges.
- Edge names `N` (above the first row), `S` (below the last), `W`, `E`; at a corner the row edge wins. Kinds: `open`, `none`, `escape`; default `open`.
- Depth in a shallow hex is `base + d6`; a ship runs aground when depth ≤ draft (13.G.2a). Land: bow or stern entering (13.G.2b). Drafts: `frigate_38` 18, `frigate_32` 16, `ship_of_line_74` 22.
- Movement dice (depth d6, the lead's PM d10, aground rigging dice) come from the resolver's `rng` (the accepted Dice exception). Drift depth dice come from `game_state.dice`. Never `randi()`.
- Aground rigging loss is the collision loss (6.E.3): d6−1 at FS, d6+1 at MS, 2d6 at PS, 0 at NS; none when drifting aground.
- Casting the lead needs a course of at most 2 steps (13.G.4a).
- Escape D.1: b at ≥ 31 hexes (`MapRules.ESCAPE_DISTANCE`); c at 20–30 hexes (`SPEED_RANGE_MIN`, `SPEED_RANGE_MAX`).
- VP shares (VI.B.5) are unchanged; struck, destroyed, captured and (by default) aground ships yield 100 %.
- `ShipState.Status.ESCAPED` is appended after `CAPTURED`. New `PhaseEvents.Type` values are appended after `END_OFFER`; new `MovementTypes.ResolutionEventType` values after `BEAR_OFF_ORDER`. Never renumber.
- Every ShipState mutation goes through `ShipStateController`; every server method checks `is_server` and `push_error`s on a client. View code (`scripts/ui`, `scripts/view`, `scripts/core`, `scripts/commands`) only reads (`test_server_authority.gd` must stay green).
- Use `Trace`, never `print()`.
- `make test` is green at the end of every task. A test that encoded the old parallelogram board is updated in Task 1 with a `# rectangle board: …` comment giving the offset column. No other existing test may change its expected values unless the task says so.
- The PostToolUse hook runs the full `make test` after edits under `scripts/server/`, `scripts/state/`, `scripts/core/`, `scripts/autoload/` and `test/unit/`.
- `docs/rules/feature_diff.md`, `CLAUDE.md` and the scenario-creator skill are updated in Task 14 only.

## Review Focus

1. **A step no plot contains, forced across an edge** (a bear-off amendment's steps ahead, a poor-maneuvering "one hex ahead", a 6.B rollback's padding): it must stop at an `open` edge and be lost at a `none` edge, never sail off the board. Pinned by Task 5 `test_open_edge_stops_forced_step` and `test_bear_off_amendment_stops_at_open_edge`.
2. **A bear-off re-run or rollback after a depth roll** must repeat the die and the grounding. Pinned by Task 5 `test_depth_roll_repeats_on_bear_off_rerun` and Task 6 `test_lead_rerun_is_deterministic`.
3. **A reinforcement that has not arrived** must take no part in anything (plotting, crew tasks, drift, morale, signals, gunfire, readiness) yet keep its side alive. Pinned by Task 10 `test_waiting_ship_takes_no_part` and Task 11 `test_waiting_reinforcement_keeps_its_side_alive`.
4. **Every existing scenario and terrain-free test must resolve exactly as before**: no extra dice, no edge where there was none in play. Pinned by Task 5 `test_terrain_free_run_is_unchanged` and Task 14 `test_every_scenario_places_cleanly`.
5. **An escaped ship is neither lost nor alive**: it yields only its damaged sections, gives its side its share, and does not keep its side in the game. Pinned by Task 11 `test_escaped_ship_yields_only_damaged_sections`, `test_escape_share_goes_to_own_side` and `test_side_all_struck_or_escaped_is_done`.

---

### Task 1: `TerrainMap` and the rectangular board

**Files:**
- Create: `scripts/state/terrain_map.gd`.
- Modify: `scripts/server/occupancy.gd` (`in_bounds`), `scripts/autoload/game_state.gd` (`placement_errors`).
- Test: create `test/unit/test_terrain_map.gd`; modify `test/unit/test_movement_validator.gd` (`test_turn_refused_when_stern_off_map`) and any other test that fails only because it placed a ship by the parallelogram's q range; add to `test/unit/test_data_manager_scenarios.gd`.

**Interfaces (Produces):**

```gdscript
class_name TerrainMap
extends RefCounted
const OPEN := "open"
const NONE := "none"
const ESCAPE := "escape"
const KINDS: Array[String] = ["open", "none", "escape"]
const EDGE_NAMES: Array[String] = ["N", "E", "S", "W"]
const DEPTH_DIE := 6
class Boundary extends RefCounted:
	var name: String = ""
	var kind: String = "open"
	var sides: Dictionary = {}            # side_key(a, b) -> true
	var outside: Array[Vector2i] = []     # map edge: the off-map hexes; custom: both hexes of every side
class ShallowArea extends RefCounted:
	var name: String = ""
	var base: int = 0
	var hexes: Array[Vector2i] = []
var bounded: bool = false
var width: int = 0
var height: int = 0
var col_min: int = 0
var row_min: int = 0
var land: Dictionary = {}                 # Vector2i -> true
var areas: Array[ShallowArea] = []
var boundaries: Array[Boundary] = []      # N, E, S, W first (bounded maps), then terrain.boundaries in order
var errors: Array[String] = []
static func of(scenario: Dictionary) -> TerrainMap          # cached: same dictionary (is_same) -> same map
static func from_scenario(scenario: Dictionary) -> TerrainMap
static func side_key(a: Vector2i, b: Vector2i) -> Vector4i  # smaller hex (x, then y) first
static func axial_to_offset(hex: Vector2i) -> Vector2i      # (col, row)
static func offset_to_axial(col: int, row: int) -> Vector2i
static func rect_hexes(width: int, height: int) -> Array[Vector2i]  # every hex of the rectangle, row by row
func in_bounds(hex: Vector2i) -> bool
func crossing(from: Vector2i, to: Vector2i) -> Boundary     # null when the side is in no boundary
func boundary(name: String) -> Boundary                     # null when unknown
func is_land(hex: Vector2i) -> bool
func area_at(hex: Vector2i) -> ShallowArea                  # null when not shallow
func depth_range(hex: Vector2i) -> Vector2i                 # (base+1, base+6) shallow; (0, 0) land; (-1, -1) deep
func grounds(hex: Vector2i, draft: int) -> String            # "never" | "maybe" | "always"
func distance_to_boundary(hex: Vector2i, name: String) -> int  # hex distance to the nearest `outside` hex; -1 unknown name
```

Scenario keys read: `map_bounds.width/height`; `terrain.edges` (`{"N": kind, …}`), `terrain.land` (`[[q, r], …]`), `terrain.shallow` (`[{"name", "base", "hexes"}]`), `terrain.boundaries` (`[{"name", "kind", "sides": [[[q, r], [q, r]], …]}]`). Error messages start with `"Terrain: "`.

`Occupancy.in_bounds(hex, scenario)` keeps its signature and returns `TerrainMap.of(scenario).in_bounds(hex)`.

`GameState.placement_errors()` also returns every `TerrainMap.of(active_scenario).errors` entry, and `"GameState: ship '%s' occupies %s, which is land"` for a ship hex on land.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_terrain_map.gd` (`extends GutTest`):
  - `test_offset_round_trip`: `axial_to_offset(Vector2i(3, 0)) == Vector2i(3, 0)`, `axial_to_offset(Vector2i(0, 2)) == Vector2i(1, 2)`, `axial_to_offset(Vector2i(0, -1)) == Vector2i(-1, -1)`, `offset_to_axial(-1, -1) == Vector2i(0, -1)`; for every `h` in `rect_hexes(6, 4)`, `offset_to_axial(axial_to_offset(h).x, axial_to_offset(h).y) == h`; `rect_hexes(10, 10).size() == 100`.
  - `test_rectangle_bounds` (`{"map_bounds": {"width": 10, "height": 10}}`): in bounds `(4, 0)`, `(2, 4)`, `(-7, 4)`, `(7, -5)`, `(-2, -5)`; out `(5, 0)`, `(3, 4)`, `(-8, 4)`, `(8, -5)`, `(0, 5)`, `(0, -6)`.
  - `test_no_map_bounds_is_unbounded`: `from_scenario({})`: `bounded == false`, `in_bounds(Vector2i(10000, -10000))`, `boundaries.is_empty()`, `crossing(Vector2i(0, 0), Vector2i(1, 0)) == null`.
  - `test_edges_default_open` (10 × 10): every `boundary(n).kind == "open"` for N, E, S, W; `crossing((0, -5), (0, -6)).name == "N"`, `crossing((4, 0), (5, 0)).name == "E"`, `crossing((-5, 0), (-6, 0)).name == "W"`, `crossing((2, 4), (2, 5)).name == "S"`, `crossing((5, 0), (4, 0)).name == "E"` (order-insensitive), `crossing((0, 0), (1, 0)) == null`.
  - `test_corner_side_belongs_to_row_edge` (10 × 10): `crossing((7, -5), (8, -6)).name == "N"`, `crossing((7, -5), (8, -5)).name == "E"`.
  - `test_edge_kinds_from_scenario`: `"terrain": {"edges": {"W": "escape", "E": "none"}}` gives W escape, E none, N and S open.
  - `test_land_and_shallow_queries`: `land [[1, 0]]`, `shallow [{"name": "A", "base": 15, "hexes": [[2, 0], [3, 0]]}]`: `is_land((1, 0))`; `area_at((2, 0)).name == "A"`; `area_at((0, 0)) == null`; `depth_range((2, 0)) == Vector2i(16, 21)`, `depth_range((1, 0)) == Vector2i(0, 0)`, `depth_range((0, 0)) == Vector2i(-1, -1)`; `grounds((2, 0), 16) == "maybe"`, `grounds((2, 0), 15) == "never"`, `grounds((2, 0), 21) == "always"`, `grounds((1, 0), 1) == "always"`, `grounds((0, 0), 30) == "never"`.
  - `test_custom_boundary`: `"boundaries": [{"name": "boom", "kind": "open", "sides": [[[0, 0], [1, 0]]]}]` (unbounded map): `crossing((1, 0), (0, 0)).name == "boom"`, `.kind == "open"`; `distance_to_boundary((3, 0), "boom") == 2`.
  - `test_validation_errors` (10 × 10): land `[[9, 0]]` (off map), land and shallow both on `[1, 0]`, edge `"X": "open"`, edge `"N": "wall"`, an area with `"base": -1`, a boundary side `[[0, 0], [2, 0]]`: `errors.size() == 6`; the messages contain, in turn, `"off the map"`, `"both land and shallow"`, `"unknown edge X"`, `"unknown kind wall"`, `"base"`, `"not neighbours"`.
  - `test_of_caches_by_reference`: `var s := {"map_bounds": {"width": 10, "height": 10}}`; `assert_same(TerrainMap.of(s), TerrainMap.of(s))`; `assert_not_same(TerrainMap.of(s), TerrainMap.of(s.duplicate(true)))`.
  - `test_distance_to_boundary` (10 × 10): `distance_to_boundary((0, 0), "W") == 6`, `distance_to_boundary((-5, 0), "W") == 1`, `distance_to_boundary((0, 0), "Q") == -1`.
  - `test_existing_scenarios_fit_the_rectangle`: for every JSON in `res://data/scenarios/`, both hexes of every ship (`HexGrid.stern_of(bow, facing)`) are `in_bounds` of that scenario's `TerrainMap`.
  - In `test_data_manager_scenarios.gd`, `test_ship_on_land_reported`: a scenario whose ship's stern stands on a land hex: `assert_push_error("which is land")`, `placement_errors().size() == 1`.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`. Expected: failures in `test_terrain_map.gd` and the new scenario test only.
- [ ] **Step 3: Implement `scripts/state/terrain_map.gd`** as above. Generate each edge boundary by walking every on-map hex and each of the 6 `HexGrid.DIRECTIONS`; for an off-map neighbour, the edge is N/S by its row when the row is outside, else W/E by its column. Keep `of()`'s cache in two `static var`s (last source dictionary, last map). A `##` header says it is pure, built once, and that mutating a scenario dictionary in place after a query is unsupported.
- [ ] **Step 4: Point `Occupancy.in_bounds` at it and extend `GameState.placement_errors`.**
- [ ] **Step 5: Re-place tests that relied on the parallelogram.** Run `make test`; for each failure caused only by a ship standing outside the new rectangle (e.g. `test_turn_refused_when_stern_off_map`, bow `(4, 4)` is column 6), move the ship so the same rule is exercised (row 0 keeps q as the column) and add the `# rectangle board:` comment. Do not change assertions.
- [ ] **Step 6: Run and confirm everything passes.** `make import && make test`. Expected: all green.
- [ ] **Step 7: Commit.**

```bash
git add scripts/state/terrain_map.gd scripts/server/occupancy.gd scripts/autoload/game_state.gd test/unit/
git commit -m "feat: TerrainMap, a rectangular board with typed boundaries, land and shallows"
```

### Task 2: Ship state for terrain, escape and arrival

**Files:**
- Modify: `scripts/state/ship_state.gd`, `scripts/server/ship_state_controller.gd`, `scripts/server/default_course.gd` (`can_plot`), `scripts/server/movement_plotting_controller.gd` (`_plot_refusal`), `scripts/server/stub_ai.gd` (`LOCKED_ERROR_CODES`), `scripts/autoload/game_state.gd` (`placement_errors`).
- Test: create `test/unit/test_ship_state_terrain.gd`; modify `test/unit/test_server_authority.gd`.

**Interfaces:**
- Consumes `TerrainMap` (Task 1).
- Produces in `ShipState`:
  - `enum Status { ACTIVE, STRUCK, DESTROYED, CAPTURED, ESCAPED }`.
  - `@export var aground: bool = false`, `@export var aground_turn: int = -1`, `@export var escape_declared: bool = false`, `@export var awaiting_arrival: bool = false`, `@export var arrives_turn: int = 1`. All five in `serialize()` / `deserialize()`.
  - `func is_escaped() -> bool`, `func is_aground() -> bool`, `func is_awaiting_arrival() -> bool`, `func casts_lead() -> bool` (`plotted_actions.get("cast_lead", false)`).
  - `is_on_map()` is `not removed_from_map and not awaiting_arrival`. `is_out_of_play()` is `status != Status.ACTIVE or awaiting_arrival` (spec §7, B refined). Update both docstrings.
  - `empty_plot()` gains `"cast_lead": false`.
  - `initialize_from_scenario`: `arrives_turn = int(data.get("arrives", 1))`; `awaiting_arrival = arrives_turn >= 2`; a waiting ship whose entry has no `"sail_state"` gets `"PS"`.
- Produces in `ShipStateController` (server only, `ship_state_changed` emitted, `true` on success):
  - `func set_aground(ship_id: String, turn: int) -> bool` (aground true, aground_turn = turn).
  - `func set_escape_declared(ship_id: String, on: bool) -> bool`.
  - `func set_cast_lead(ship_id: String, on: bool) -> bool` (writes `plotted_actions["cast_lead"]`).
  - `func place_arrival(ship_id: String, speed: int) -> bool` (awaiting_arrival false, speed set).
  - `func delay_arrival(ship_id: String, turn: int) -> bool` (arrives_turn = turn).
- `DefaultCourse.can_plot` is also false for `is_aground()`, `not is_on_map()` and `is_escaped()`. `_plot_refusal` returns `["SHIP_OFF_MAP", "Ship %s is not on the map"]` first (not on the map, or escaped), and `["SHIP_AGROUND", "Ship %s is aground and cannot move (13.G.3)"]` after the struck check, before dismasted. `StubAI.LOCKED_ERROR_CODES` gains `"SHIP_AGROUND"` and `"SHIP_OFF_MAP"`.
- `placement_errors` leaves waiting ships out of the overlap check, but checks their entry footprint against bounds and land.
- `test_server_authority.gd` `FORBIDDEN` gains:
  - `["\\.(aground|aground_turn|escape_declared|awaiting_arrival|arrives_turn)\\s*(=|\\+=|-=)[^=]", "a terrain, escape or arrival field written from view code"]`
  - `["(?<!player_)\\b(set_aground|set_escape_declared|set_cast_lead|place_arrival|delay_arrival)\\(", "a terrain, escape or arrival mutator called from view code"]`

- [ ] **Step 1: Write the failing tests** in `test/unit/test_ship_state_terrain.gd`:
  - `test_escaped_is_out_of_play_and_not_targetable`: status ESCAPED → `is_escaped()`, `is_out_of_play()`, `not is_targetable()`, `not can_be_boarded()`, `not crew_can_act()`.
  - `test_awaiting_ship_is_off_map_and_out_of_play`: `awaiting_arrival = true` (set through `initialize_from_scenario` with `"arrives": 3`) → `not is_on_map()`, `is_out_of_play()`, `Occupancy.build([ship])` empty.
  - `test_scenario_arrives_sets_awaiting_and_plain_sail`: `{"arrives": 3}` (no sail_state) → `awaiting_arrival`, `arrives_turn == 3`, `sail_state == "PS"`; `{"arrives": 3, "sail_state": "MS"}` → `"MS"`; `{"arrives": 1}` → not awaiting; no key → not awaiting, `arrives_turn == 1`.
  - `test_aground_ship_stays_in_play_but_cannot_plot`: `set_aground("a", 4)` → `is_aground()`, `aground_turn == 4`, `not is_out_of_play()`, `is_targetable()`, `DefaultCourse.can_plot(a) == false`, `movement_plotting_controller.handle_start_plotting` returns a `PlottingErrorResponse` with `error_code == "SHIP_AGROUND"`.
  - `test_waiting_ship_refused_off_map`: start plotting a waiting ship → `"SHIP_OFF_MAP"`.
  - `test_cast_lead_lives_in_the_plot`: `set_cast_lead("a", true)` → `casts_lead()`; `clear_plotted_actions("a")` → `not casts_lead()`.
  - `test_serialize_round_trip_terrain_fields`: all five fields and status ESCAPED survive `ShipState.deserialize(s.serialize())`.
  - `test_placement_skips_overlap_for_waiting_ship`: a waiting ship whose entry overlaps a starting ship → no overlap error; a waiting ship whose entry is on land → one "which is land" error.
  - In `test_server_authority.gd`, `test_terrain_patterns_catch_mutations`: caught `"ship.aground = true"`, `"s.escape_declared = false"`, `"GameState.ship_controller.set_aground(\"a\", 2)"`, `"place_arrival(id, 5)"`; allowed `"if ship.is_aground():"`, `"GameState.phase_controller.player_set_cast_lead(0, \"a\", true)"`, `"if ship.aground == true:"`.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** the fields, helpers, mutators, refusals and patterns above.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green (the 58 `is_out_of_play()` callers are unchanged for every ship that is not waiting).
- [ ] **Step 5: Commit.**

```bash
git add scripts/state/ship_state.gd scripts/server/ship_state_controller.gd scripts/server/default_course.gd scripts/server/movement_plotting_controller.gd scripts/server/stub_ai.gd scripts/autoload/game_state.gd test/unit/
git commit -m "feat: ship state for aground, escape, the lead and reinforcements"
```

### Task 3: `MapRules`, `MapController` and the new events

**Files:**
- Create: `scripts/server/map_rules.gd`, `scripts/server/map_controller.gd`.
- Modify: `scripts/server/phase_events.gd`, `scripts/autoload/game_state.gd` (`map_controller`, created in `_initialize_server_controllers`), `test/unit/test_server_authority.gd`.
- Test: create `test/unit/test_map_controller.gd`.

**Interfaces:**
- Consumes Tasks 1–2.
- Produces `class_name MapRules` (pure statics):

```gdscript
const CLEAR := "clear"
const BLOCKED := "blocked"
const LOST := "lost"
const ESCAPE := "escape"
static func permission(scenario: Dictionary, side: int) -> Dictionary  # {} none; else {from_turn: int, edges: Array[String] ([] = every escape boundary), share: float}
static func declare_error(scenario: Dictionary, side: int, turn: int) -> String  # "" or "side %d may not escape" / "escape is allowed from turn %d"
static func may_declare(scenario: Dictionary, side: int, turn: int) -> bool
static func may_cross(scenario: Dictionary, ship: ShipState, boundary: TerrainMap.Boundary, turn: int) -> bool
static func share(scenario: Dictionary, side: int) -> float
static func crossing_outcome(scenario: Dictionary, ship: ShipState, from: Vector2i, to: Vector2i, turn: int) -> Dictionary
	# {"outcome": CLEAR|BLOCKED|LOST|ESCAPE, "edge": boundary name or ""}: no boundary -> CLEAR; open -> BLOCKED;
	# none -> LOST; escape -> ESCAPE if may_cross else BLOCKED
```

- `may_cross`: boundary kind `escape`, `permission(scenario, ship.side)` not empty, `turn >= from_turn`, `edges` empty or containing `boundary.name`, and `ship.escape_declared`.
- Produces `PhaseEvents.Type` values `AGROUND, LEAD_CAST, ESCAPE_DECLARED, ESCAPED, ARRIVED, ARRIVAL_DELAYED` (appended), their `to_text` lines (spec §13 table, exact wording there), and `static func edge_label(name: String) -> String` (`"N"` → `"north"`, `"E"` → `"east"`, `"S"` → `"south"`, `"W"` → `"west"`, any other name as given). Also: `STOPPED_SHORT` with `cause == "map_edge"` reads "stops at the edge of the map"; `DESTROYED` with `reason == "no_sea_room"` reads "%s leaves the map where there is no sea room and is lost"; `DRIFT` with `blocked == "aground"` reads "%s drifts aground".
- Produces `class_name MapController extends RefCounted`, `func _init(p_game_state: Node)`, `var is_server := true`:
  - `func ground(ship_id: String, data: Dictionary, phase: int) -> void`: `set_aground(ship_id, game_state.current_turn)`, then logs `AGROUND` with `data` (`{cause, terrain, hex: {q, r}, depth, draft}`).
  - `func escape(ship_id: String, data: Dictionary, phase: int) -> void`: `set_status(ESCAPED)`, `crew_task_controller.drop_all(ship_id, "escaped")` (when present), `clear_pending_morale_checks`, `remove_from_map`, logs `ESCAPED` with `data` (`{how, edge}` or `{how, range}`). No-op for a ship already out of play.
  - `func lose_off_map(ship_id: String, edge: String, phase: int) -> void`: `damage_controller.destroy(ship_id, "no_sea_room", phase, {"edge": edge})` then `remove_from_map(ship_id)`. `DamageController.destroy` gains a last parameter `extra: Dictionary = {}`, merged into the DESTROYED event's data (existing callers unchanged).
- `PhaseEvents.CREW_TASK_REASONS` gains `"escaped": "the ship has escaped"`.
- `test_server_authority.gd` `FORBIDDEN` gains `["\\bmap_controller\\.(?!arrival_speed\\(|pursuers\\()", "a MapController call from view code"]` and `["\\bMapController\\.new\\b", "a MapController made in view code"]`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_map_controller.gd` (ships built as in `test_victory_controller.gd`, `GameState.turn_log` saved and restored):
  - `test_ground_sets_aground_and_logs`: `ground("a", {"cause": "movement", "terrain": "shallow", "hex": {"q": 2, "r": 0}, "depth": 16, "draft": 16}, phase)` → `a.is_aground()`, `a.aground_turn == GameState.current_turn`, one AGROUND event; its text contains `"runs aground"` and `"16 ft"`.
  - `test_escape_removes_and_frees_partner`: `a` fouled with `b`; `escape("a", {"how": "edge", "edge": "W"}, phase)` → `a.status == ESCAPED`, `not a.is_on_map()`, `b.fouled_with == ""`, ESCAPED text contains `"escapes off the west edge"`.
  - `test_lose_off_map_destroys_and_removes`: → `a.is_destroyed()`, `not a.is_on_map()`, DESTROYED data `reason == "no_sea_room"`, `edge == "E"`, text contains `"no sea room"`.
  - `test_permission_defaults_and_values`: `{"escape": {"1": {"from_turn": 5, "edges": ["W"], "share": 0.9}}}` → `permission(s, 1) == {"from_turn": 5, "edges": ["W"], "share": 0.9}`, `permission(s, 0) == {}`; `may_declare(s, 1, 4) == false`, `may_declare(s, 1, 5) == true`; `declare_error(s, 0, 9)` contains `"may not escape"`; `declare_error(s, 1, 4)` contains `"from turn 5"`; `share(s, 1) == 0.9`, `share(s, 0) == 0.0`; `{"escape": {"1": {}}}` → `{"from_turn": 1, "edges": [], "share": 0.0}`.
  - `test_crossing_outcome_table` (10 × 10, edges W escape, E none; `escape: {"1": {}}`; a side-1 ship): `(0, 0)→(1, 0)` CLEAR; `(0, -5)→(0, -6)` BLOCKED edge `"N"`; `(4, 0)→(5, 0)` LOST edge `"E"`; `(-5, 0)→(-6, 0)` BLOCKED while undeclared, ESCAPE once `escape_declared`; a side-0 declared ship: BLOCKED.
  - `test_new_event_texts`: one event of each new type renders its spec §13 line (substring checks: `"casts the lead"`, `"is trying to escape"`, `"31 hexes"`, `"arrives at"`, `"will try next turn"`).
- [ ] **Step 2: Run and confirm failure.** `make import && make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** `MapRules`, `MapController`, the events and texts, the `destroy` extra, the controller's creation in `GameState._initialize_server_controllers` (after `damage_controller`), and the authority patterns.
- [ ] **Step 4: Run and confirm everything passes.** `make import && make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/map_rules.gd scripts/server/map_controller.gd scripts/server/phase_events.gd scripts/server/damage_controller.gd scripts/autoload/game_state.gd test/unit/
git commit -m "feat: MapRules, MapController and the map events"
```

### Task 4: Plotting at the edges; the escape and lead requests

**Files:**
- Modify: `scripts/server/movement_validator.gd`, `scripts/server/turn_phase_controller.gd`.
- Test: create `test/unit/test_map_plotting.gd`.

**Interfaces:**
- Consumes `MapRules.crossing_outcome`, `MapRules.declare_error`, `ShipStateController.set_escape_declared`, `set_cast_lead` (Tasks 2–3).
- `MovementValidator`: `func _crossing_allowed(ship_state: ShipState, from_hex: Vector2i, to_hex: Vector2i) -> bool` (outcome CLEAR or ESCAPE; the turn is `int(game_state.get("current_turn"))` if present, else 1). The forward option is offered only if `_crossing_allowed(ship, current_hex, forward_hex)`; a turn only if `_crossing_allowed(ship, HexGrid.stern_of(current_hex, current_facing), HexGrid.stern_of(current_hex, new_facing))`. `_stern_in_bounds` is deleted. When the plot's current bow or stern is off the map (`TerrainMap.of(game_state.active_scenario).in_bounds` false), `_calculate_real_valid_hexes` returns no moves.
- `TurnPhaseController`:
  - `func player_declare_escape(player_id: int, ship_id: String, on: bool) -> String`. Checks in order: server; game not over; PLANNING (`"escape is declared in the planning phase"`); a valid player whose plan is not in; the ship exists and the player commands it (`"%s is not this player's ship"`); in play and on the map (`"%s is not in play"`); for `on`, `MapRules.declare_error(scenario, ship.side, current_turn)`. Then `set_escape_declared`.
  - `func player_set_cast_lead(player_id: int, ship_id: String, on: bool) -> String`: `_course_request_error`, then `set_cast_lead`.
  - `plan_errors(player_id)` adds, per ship: `"casting the lead needs a course of at most 2 MPs (13.G.4a)"` when `casts_lead()` and `stored_course(ship).size() > 2`; `"the course leaves the map at the %s edge: declare escape first (V.D.2)"` when a stored step crosses an escape boundary whose `crossing_outcome` is BLOCKED.
  - `player_reset_planning` also clears the lead order of the player's ships.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_map_plotting.gd` (validator fixtures as `test_movement_validator.gd`; phase requests as `test_server_authority.gd`'s `test_plotting_refused_after_submit_or_outside_planning`):
  - `test_forward_off_open_edge_not_offered`: 10 × 10, bow `(4, 0)` facing 0 → `valid_hexes.forward` empty; from `(3, 0)` it holds `(4, 0)`.
  - `test_none_edge_refused_too`: E `none`, same position → forward empty.
  - `test_escape_edge_offered_only_when_declared_and_permitted`: W `escape`, `escape: {"1": {}}`, side-1 ship bow `(-5, 0)` facing 3: undeclared → forward empty; declared → forward holds `(-6, 0)`; from `(-6, 0)` with that step in the path, `has_any_moves() == false` and `deceleration_shortfall == 0`.
  - `test_land_and_shallow_not_refused`: land at `(1, 0)`, bow `(0, 0)` facing 0 → forward holds `(1, 0)`.
  - `test_declare_escape_checks`: refused outside PLANNING (contains `"planning"`), for another player's ship, for a side with no permission (`"may not escape"`), before `from_turn` (`"from turn"`); accepted → `escape_declared == true`; `on = false` accepted → false.
  - `test_cast_lead_plan_error`: lead on, stored course of 3 steps → `plan_errors(0)` names the ship with `"13.G.4a"` and `player_submit_plan(0) == false`; a 2-step course → no error.
  - `test_course_over_escape_edge_needs_declaration`: declared, course plotted off the W edge, declaration withdrawn → `plan_errors(0)` contains `"declare escape first"`.
  - `test_reset_planning_clears_the_lead`.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** the validator change and the two requests.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/movement_validator.gd scripts/server/turn_phase_controller.gd test/unit/test_map_plotting.gd
git commit -m "feat: typed edges in plotting; escape and cast-the-lead requests"
```

### Task 5: Resolver — edges and running aground

All checks run per segment under proportional movement (`MoveSchedule`), before the segment's hexes held and conflict groups are built (spec §3–§4).

**Files:**
- Modify: `scripts/server/movement_types.gd`, `scripts/server/movement_resolver.gd`.
- Test: create `test/unit/test_movement_terrain.gd`.

**Interfaces:**
- Consumes `TerrainMap`, `MapRules.crossing_outcome`, `MapController.ground/escape/lose_off_map` (Tasks 1–3).
- `MovementTypes.ResolutionEventType` gains `EDGE_BLOCKED, LEFT_MAP, AGROUND, LEAD_SOUNDING`.
- `ShipResolutionResult` gains `var aground: bool = false`, `var aground_data: Dictionary = {}` (`{terrain, hex: {q, r}, depth, draft}`; depth −1 for land), `var left_map: String = ""` (`""`, `"none"`, `"escape"`), `var left_edge: String = ""`; all in `to_dict()` when set.
- `MovementResolver`:
  - `var _terrain: TerrainMap = null`, set at the top of `run()` from `TerrainMap.of(game_state.active_scenario)`.
  - `func _settle_terrain(p: ResolutionPass, seg: Segment, ships: Array[ShipState]) -> void`, called in `_resolve_impulse` right after `seg.intended_moves` is filled. For each ship with an intended move, in `ships` order: entered hex `_entered_hex(…)`; from hex = old stern on a stern entry, else the bow; then
    1. `crossing_outcome` BLOCKED → remove the move, `p.stopped`, `stopped_at_impulse`, event `EDGE_BLOCKED` (detail = edge name);
    2. entered hex land → `_run_aground(p, seg, sid, {"terrain": "land", "hex": …, "depth": -1})`;
    3. ahead step, entered hex shallow → `var depth := _roll_depth(area)`; event `AGROUND` only if `depth <= draft` (via `_run_aground`, `"terrain": "shallow"`).
  - `func _roll_depth(area: TerrainMap.ShallowArea) -> int`: `area.base + rng.randi_range(1, 6)`.
  - `func _run_aground(p: ResolutionPass, seg: Segment, sid: String, data: Dictionary) -> void`: removes the intended move, stops the ship, `result.aground = true`, `result.aground_data = data` (+ `draft`), `result.rigging_damage += _roll_collision_rigging_loss(ship)`, event `AGROUND` on the segment.
  - `func _note_left_map(p: ResolutionPass, seg: Segment) -> void`, called at the end of `_resolve_impulse`: every ship whose step was made this segment (`seg.moves`) and whose bow or stern is now off the map gets `LEFT_MAP`, `result.left_map` (`"none"` for LOST, `"escape"` for ESCAPE, from that step's `crossing_outcome`), `left_edge`, and is stopped.
  - `stop_cause` returns `{"cause": "map_edge", "edge": name}` for a result whose movement ended with `EDGE_BLOCKED`; `log_outcomes` puts `edge` in that STOPPED_SHORT's data and logs no STOPPED_SHORT for an aground ship or one that left the map.
  - `apply_results`: an aground ship's speed is 0 and `map_controller.ground(sid, {"cause": "movement"} + aground_data, phase)` is called before its rigging damage is applied; `left_map == "none"` → `lose_off_map(sid, left_edge, phase)`; `"escape"` → `escape(sid, {"how": "edge", "edge": left_edge}, phase)`; both after the position is set.
- Dice order per ship within a segment: its depth d6, then its rigging dice. A test reads expected dice from a probe: `var probe := RandomNumberGenerator.new(); probe.state = rng.state` taken before `run()`, then `probe.randi_range(1, 6)` in the order above.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_movement_terrain.gd`. Fixtures as `test_movement_resolver.gd`, with `"draft": 16` in `_make_ship_def`, sail MS, `GameState.active_scenario` set per test (saved and restored), `GameState.current_turn` set:
  - `test_ahead_into_land_runs_aground_in_place`: bow `(0, 0)` facing 0, 3 steps ahead, land `(2, 0)` → `final_hex == (1, 0)`, `aground`, `aground_data.terrain == "land"`, `rigging_damage == probe d6 + 1` (no depth die for land), one AGROUND event.
  - `test_turn_swinging_stern_onto_land_runs_aground`: a starboard turn whose new stern is land → facing unchanged, `aground`.
  - `test_certain_shoal_grounds`: area base 10 on `(2, 0)` → `final_hex == (1, 0)`, `aground`, `aground_data.depth == 10 + probe first d6`, `rigging_damage == probe second d6 + 1`.
  - `test_deep_enough_shoal_is_entered`: base 16 → `final_hex == (3, 0)`, not aground.
  - `test_doubtful_shoal_uses_the_resolver_rng`: base 15 → `aground == (probe first d6 == 1)`.
  - `test_stern_entry_into_shoal_never_rolls`: a turn whose new stern is in a base-10 area → not aground, and the log equals (`to_dict()`) the same run with no terrain.
  - `test_open_edge_stops_forced_step`: 10 × 10, bow `(3, 0)` facing 0, a raw 3-step plot written into `plotted_actions` → `final_hex == (4, 0)`, an `EDGE_BLOCKED` event; after `apply_results` the turn log's STOPPED_SHORT has `cause == "map_edge"`, `edge == "E"`.
  - `test_bear_off_amendment_stops_at_open_edge`: an AI ship bears off near the E edge (a blocker ahead, the amendment's steps ahead lead off the map) → the amended steps stop at the edge with `EDGE_BLOCKED`, the ship stays on the map.
  - `test_none_edge_loses_the_ship`: E `none`, a raw plot off the map → `left_map == "none"`; after `apply_results`: `is_destroyed()`, `not is_on_map()`, DESTROYED `reason == "no_sea_room"`.
  - `test_declared_ship_escapes_off_escape_edge`: W `escape`, side 1 permitted and declared → `left_map == "escape"`; after `apply_results`: `status == ESCAPED`, `not is_on_map()`. Undeclared, same plot → `EDGE_BLOCKED`, on the map.
  - `test_aground_ship_is_an_obstacle`: `a` grounds on segment 0; `b`, plotted later into `a`'s hex, has `blocked_by == "a"`.
  - `test_depth_roll_repeats_on_bear_off_rerun`: `a` crosses a base-15 area on its first step; prompted ship `b` meets a potential collision with `c` on a later segment. `run()` once (incomplete), then again with `b`'s decision from the same `rng.state` → `a`'s result `to_dict()` is equal in both logs.
  - `test_terrain_free_run_is_unchanged`: a scenario whose land and shoals lie 20 hexes from every ship resolves (seeded) to a log whose `to_dict()` equals the run with no `terrain` key.
  - `test_aground_applied`: after `apply_results`, `a.speed == 0`, `a.is_aground()`, an AGROUND event with `cause == "movement"` precedes the DAMAGE event.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** the result fields, the events, `_settle_terrain`, `_roll_depth`, `_run_aground`, `_note_left_map`, `stop_cause`, `log_outcomes` and `apply_results` changes.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green; no existing resolver test changes.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/movement_types.gd scripts/server/movement_resolver.gd test/unit/test_movement_terrain.gd
git commit -m "feat: movement stops at open edges, leaves by none and escape edges, runs aground (13.G.2)"
```

### Task 6: Resolver — casting the lead (13.G.4)

**Files:**
- Modify: `scripts/server/movement_resolver.gd`.
- Test: create `test/unit/test_cast_lead.gd`.

**Interfaces:**
- Consumes Task 5 (`_settle_terrain`, `_roll_depth`, `_run_aground`, `LEAD_SOUNDING`) and `ShipState.casts_lead()`.
- A step is sounded when `ship.casts_lead()`, the ship's plot at `run()` start has ≤ 2 steps (`plotted[sid].size()`), and it is an ahead step whose entered hex is land or shallow. Sounding replaces Task 5's steps 2–3 for that step.
- `func _eligible_turns(p: ResolutionPass, sid: String, impulse: int) -> Array[String]`: extracted from `bear_off_situation` (the path made so far and the validator's port/starboard; `bear_off_situation` now calls it).
- `func _lead_side(p: ResolutionPass, sid: String, impulse: int) -> String`: `""` or `MovementTypes.BEAR_OFF_PORT` / `BEAR_OFF_STARBOARD`. Of `_eligible_turns` whose new stern is not land, rank by the hex ahead after the turn: `grounds` never (0) < maybe (1) < always (2), off the map or BLOCKED 3; then the larger area base (deep water ranks as 1000); then starboard.
- Too shallow (land, or depth ≤ draft):
  - `ship.is_poor_maneuvering()`: one `rng.randi_range(0, 9)` ≤ `poor_maneuvering_number(ship)` to turn; a failure means it sails on into the shoal: `_run_aground` (it stays in the hexes it held, spec §4; outcome `"pm_failed"`).
  - `_lead_side == ""` → the move is removed and the ship stopped, not aground (outcome `"held"`).
  - Else an amendment `{"kind": "lead", "ship_id", "segment", "step": _schedule_of(p).step_at(sid, impulse), "pre_bow", "pre_facing", "facing": new facing, "other_id": "", "reason": "cast the lead", "events": [sounding, pm roll if any]}` is appended to `p.bear_off_amendments`, the ship stopped (outcome `"bore_off"`).
- Deep enough → the step is made (outcome `"entered"`).
- `_amended_steps` treats `"lead"` exactly as `"bear_off"`. In `run()`, a `"lead"` rollback does not enter `settled_bear_offs` and is appended to `var lead_records: Array` (not `rollbacks[sid]`); after the passes `func _record_lead(results: Dictionary, record: Dictionary) -> void` inserts its events at its segment start when `_reached_segment` holds.
- `LEAD_SOUNDING` event: `roll` = the d6 (−1 for land), `threshold` = draft, `detail` = `"outcome=<o> side=<port|starboard|> depth=<n>"`. `log_outcomes` logs `PhaseEvents.Type.LEAD_CAST {hex, depth, draft, outcome, side}`.
- Dice order: depth d6, then the PM d10, then rigging dice if aground.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_cast_lead.gd` (fixtures as Task 5, `speed = 2`, a 2-step plot ahead from bow `(0, 0)` facing 0, `set_cast_lead` on):
  - `test_lead_bears_off_from_certain_shoal_to_the_deeper_side`: base-10 area on `(1, 0)`; the hex ahead after a port turn is land, after a starboard turn deep → `final_facing == 1`, not aground, `rigging_damage == 0`, a `LEAD_SOUNDING` with `"outcome=bore_off side=starboard"`, no `BEARING_OFF_ROLL`; the turn log has LEAD_CAST `outcome == "bore_off"`.
  - `test_lead_bears_off_from_land`: land on `(1, 0)` → bears off, `roll == -1` on the sounding.
  - `test_lead_enters_when_deep_enough`: base 16 → `final_hex == (2, 0)`, outcome `entered`.
  - `test_lead_ignored_over_two_mps`: a 3-step plot through a base-10 area → no `LEAD_SOUNDING`, aground.
  - `test_lead_with_no_legal_turn_holds`: both turns put the new stern on land → `final_hex == (0, 0)`, not aground, outcome `held`.
  - `test_poor_maneuvering_lead_can_fail`: `rudder_destroyed = true`, a base-10 area on `(1, 0)`; probe: the first d6 is the depth, the next d10 the PM roll → if `d10 <= poor_maneuvering_number(ship)` it bore off (outcome `bore_off`); else `final_hex == (0, 0)`, `aground`, outcome `pm_failed`.
  - `test_lead_bear_off_does_not_use_the_6_d_5_bear_off`: after the lead bear-off, a ship in the way on the amended course still gets a normal Bearing Off roll (not "already bore off this turn").
  - `test_lead_rerun_is_deterministic`: two `run()`s from the same `rng.state` give equal `to_dict()` logs.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** the sounding, `_eligible_turns`, `_lead_side`, the `"lead"` amendment, `lead_records`, `_record_lead` and the LEAD_CAST log line.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/movement_resolver.gd test/unit/test_cast_lead.gd
git commit -m "feat: casting the lead bears off from shoals and land (13.G.4)"
```

### Task 7: Drift — aground, terrain and edges

**Files:**
- Modify: `scripts/server/map_rules.gd`, `scripts/server/drift_resolver.gd`.
- Test: create `test/unit/test_drift_terrain.gd`.

**Interfaces:**
- Consumes `MapRules.crossing_outcome`, `MapController` (Tasks 3, 5).
- `MapRules`:

```gdscript
static func forced_move(scenario: Dictionary, ship: ShipState, old_hexes: Array[Vector2i],
		new_hexes: Array[Vector2i], others: Dictionary, turn: int) -> Dictionary
	# {"result": "edge"|"lost"|"escape"|"land"|"ship"|"clear", "edge": String, "blocker": String,
	#  "shallow_bow": bool (clear only: new_hexes[0] is in a shallow area)}
	# priority: any BLOCKED crossing -> edge; any LOST -> lost; any ESCAPE -> escape; any new hex land -> land;
	# a new hex in `others` -> ship (bow first, then stern); else clear
```

- `DriftResolver`:
  - `func _holds_group(ship: ShipState) -> bool` (aground; a `##` note that anchoring extends it). `_is_eligible` returns false when any member holds.
  - `_first_block` is replaced by `forced_move`. Per group after the drift d10: any member `edge` → blocked `"map edge"` (as today); any `land` → those members `map_controller.ground(id, {"cause": "drift", "terrain": "land", "hex", "depth": -1, "draft"}, phase)`, the group stays, DRIFT `blocked: "aground"`; any `ship` → as today; otherwise one `game_state.dice.d6()` per member whose `shallow_bow`, in group order: any with `base + d6 <= draft` grounds (`"terrain": "shallow"`, `depth`) and the group stays; else the group drifts, then a member whose result was `lost` → `lose_off_map`, `escape` → `map_controller.escape(id, {"how": "edge", "edge": …}, phase)`.
  - Partial drift (8.A.5): the moving end is checked with `forced_move` on its own hex: land or a too-shallow bow (one d6, after the fouling roll) → aground in place; an edge → no partial drift.
- Dice order: drift d10; fouling d10 (only when a ship blocks); depth d6s.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_drift_terrain.gd` (fixtures and `ScriptedDice` as `test_drift_resolver.gd`; wind so that downwind is known, `_downwind(hex)`):
  - `test_forced_move_priorities`: pure calls of `MapRules.forced_move` — an open crossing and a ship both in the way → `edge`; land and a ship → `land`; a ship only → `ship` with its id; clear into a shoal → `clear`, `shallow_bow == true`.
  - `test_aground_ship_never_drifts_and_holds_its_group`: `a` aground, fouled with `b` → no DRIFT event, no die drawn (an empty `ScriptedDice` queue does not error), both positions unchanged.
  - `test_drift_onto_land_runs_aground_without_rigging_loss`: land downwind, dice `[9]` → `a.is_aground()`, rigging unchanged, DRIFT `blocked == "aground"`, AGROUND `cause == "drift"`, `terrain == "land"`.
  - `test_drift_into_shallow_rolls_depth_with_dice`: base 15, draft 16: dice `[9, 1]` → aground in place; dice `[9, 2]` → drifted.
  - `test_drift_off_none_edge_loses_the_ship`: dice `[9]` → `is_destroyed()`, `not is_on_map()`.
  - `test_drift_off_escape_edge_escapes_declared_ship`: declared and permitted → ESCAPED; undeclared → DRIFT `blocked == "map edge"`.
  - `test_group_member_lost_off_none_edge_others_drift`: two grappled ships, one crossing a `none` edge → that one lost, the other moved one hex downwind and no longer grappled.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement** `forced_move`, `_holds_group` and the drift outcomes.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, including `test_drift_blocked_at_map_edge`.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/map_rules.gd scripts/server/drift_resolver.gd test/unit/test_drift_terrain.gd
git commit -m "feat: drift runs aground, holds aground groups and respects typed edges (8.A.1, 13.G.2)"
```

### Task 8: Combat — land blocks line of sight; aground ships hold their guns

**Files:**
- Modify: `scripts/server/gunnery_calculator.gd` (`_occupied_hexes`, `preview`), `scripts/server/stub_ai.gd` (`_occupied_except`).
- Test: create `test/unit/test_terrain_gunnery.gd`.

**Interfaces:**
- `GunneryCalculator._occupied_hexes(exclude_ids)` also maps every `TerrainMap.of(game_state.active_scenario).land` hex to `"land"`. `preview` refuses a firer that `is_aground()` with `"an aground ship cannot fire its guns (13.G.3)"` (after the captured check).
- `StubAI._occupied_except` adds the same land entries, so `_score_position` sees land LOS.
- `FireGeometry` is unchanged (7.B.8 spines, 7.B.9 vertices already apply to any hex in `occupied`).

- [ ] **Step 1: Write the failing tests** in `test/unit/test_terrain_gunnery.gd` (fixtures as `test_gunnery_calculator.gd` or the nearest preview test):
  - `test_land_blocks_gunfire_line_of_sight`: a firer and a target at range 4 whose preview is accepted with no terrain; land on every hex between them on both batteries' lines → preview refused with `"no line of sight to target"`.
  - `test_shallow_does_not_block_line_of_sight`: the same hexes as a shoal → accepted.
  - `test_aground_ship_cannot_fire_guns`: firer aground → refused with `"13.G.3"`; `eligible_shots` for it empty.
  - `test_aground_ship_can_be_fired_on_and_use_marines`: an aground target is accepted as a gun target; an aground firer's `marine_fire_resolver.preview` at an adjacent enemy is allowed.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/gunnery_calculator.gd scripts/server/stub_ai.gd test/unit/test_terrain_gunnery.gd
git commit -m "feat: land blocks line of sight (7.B.7); aground ships cannot fire guns (13.G.3)"
```

### Task 9: Escape at the end of the turn (V.D.1–4)

**Files:**
- Modify: `scripts/server/map_rules.gd`, `scripts/server/map_controller.gd`, `scripts/server/turn_phase_controller.gd` (`_enter_end_turn_phase`), `scripts/server/player_view.gd` (`ship_for`).
- Test: create `test/unit/test_escape.gd`.

**Interfaces:**
- `MapRules`:

```gdscript
const ESCAPE_DISTANCE := 31
const SPEED_RANGE_MIN := 20
const SPEED_RANGE_MAX := 30
static func footprint_range(a: Array[Vector2i], b: Array[Vector2i]) -> int   # closest hexes, axial distance
static func max_ma(ship: ShipState, wind_facing: String, wind_speed: int) -> int
	# 0 at WS 0, WF "L" or rigging level 0; else DataManager.get_movement_allowance(ship.ship.speed_type,
	# wind_speed, wind_facing, ship.max_sail_state().to_lower(), ship.rigging_level())
static func condition(ship: ShipState, pursuers: Array[ShipState], wind_direction: int, wind_speed: int) -> Dictionary
	# {} or {"how": "distance", "range": r} (r >= 31, or no pursuers: range -1) or {"how": "speed", "range": r}
	# speed: 20 <= nearest <= 30, own max_ma > 0, own max_ma >= max_ma of every pursuer with 20 <= range <= 30
	# and ship_class <= own ship_class, all at the escaping ship's wind facing
```

- `MapController`:
  - `func pursuers(ship: ShipState) -> Array[ShipState]`: ships of another side, not out of play, on the map, not aground.
  - `func resolve_escapes(turn: int, phase: int) -> void`: first an `ESCAPE_DECLARED` event for every declared ship in play (ship id order); then, from a snapshot of the positions, every declared ship in play, on the map, not linked, of a side with `may_declare(scenario, side, turn)`, whose `condition` is not empty → `escape(id, condition, phase)`.
- `_enter_end_turn_phase`: right after the 8.G.1f removal loop and before `victory_controller.check`: `game_state.map_controller.resolve_escapes(current_turn, current_phase)`.
- `PlayerView.ship_for` erases `"escape_declared"` for a reader of another side (beside `standing_order`); update its docstring.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_escape.gd` (scenario with `escape: {"1": {}}`, 100 × 100; ships placed in row 0 at chosen distances):
  - `test_distance_31_escapes_30_does_not`: a declared side-1 frigate_32 31 hexes from the only pursuer → ESCAPED `how == "distance"`; at 30 hexes with a faster pursuer of the same class → still on the map.
  - `test_speed_condition_counts_same_or_larger_class`: at 25 hexes, an escaper of class 3 against a class-3 pursuer whose `max_ma` is lower → escapes, `how == "speed"`; empty the escaper's rigging sections until its `max_ma` is below the pursuer's → stays; the same faster pursuer with `ship_class = 4` in its fixture (a smaller class) does not count → escapes. A class-2 faster pursuer counts → stays. Take every expected `max_ma` from `DataManager.get_movement_allowance`.
  - `test_max_ma_values`: `max_ma` equals `DataManager.get_movement_allowance(type, ws, wf, "ps", 4)` for a full-rigged ship, 0 at `"L"`, 0 dismasted, 0 at WS 0.
  - `test_no_pursuer_escapes_by_distance`: the only enemy struck → escapes, `range == -1`.
  - `test_aground_enemy_is_not_a_pursuer`.
  - `test_undeclared_unpermitted_or_early_never_escapes`: undeclared; side 0 (no permission); `from_turn` after the turn → all stay.
  - `test_linked_ship_does_not_escape`: grappled at 31+ hexes from the nearest pursuer → stays.
  - `test_escape_declared_reported_at_end_turn_only`: during PLANNING, `player_view.ship_for(enemy_player, id)` has no `escape_declared`, `ship_for(own_player, id)` has it true, and `events_for(enemy_player, turn)` has no ESCAPE_DECLARED; after END_TURN it has one.
  - `test_end_turn_order`: a destroyed ship is removed before the check, ESCAPE_DECLARED precedes ESCAPED in the turn log, and the victory check runs after (with the escaped ship off the map).
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/map_rules.gd scripts/server/map_controller.gd scripts/server/turn_phase_controller.gd scripts/server/player_view.gd test/unit/test_escape.gd
git commit -m "feat: escape by distance and speed at the end of the turn, reported to the enemy (V.D)"
```

### Task 10: Reinforcements (2.B.1, 3.A)

**Files:**
- Modify: `scripts/server/map_controller.gd`, `scripts/server/turn_phase_controller.gd` (`_enter_environment_phase`).
- Test: create `test/unit/test_reinforcements.gd`.

**Interfaces:**
- `MapController`:
  - `func arrival_speed(ship: ShipState) -> int`: 0 at WS 0 or WF L; else `DataManager.get_movement_allowance(ship.ship.speed_type, env.wind_speed, wf, ship.movement_sail_state().to_lower(), ship.rigging_level())` (rigging level 0 → 0), `wf` from the ship's facing and `env.wind_direction`.
  - `func place_arrivals(turn: int, phase: int) -> void`: every waiting ship with `arrives_turn <= turn`, by ship id. Free entry (no ship in `GameState.ships_on_map()` holds the bow or stern hex) → `place_arrival(id, arrival_speed(ship))`, event `ARRIVED {hex: {q, r}, facing, sail_state, speed}`; else `delay_arrival(id, turn + 1)`, event `ARRIVAL_DELAYED {}` with target the holder.
- `_enter_environment_phase` calls `game_state.map_controller.place_arrivals(current_turn, current_phase)` after `phase_changed` and before `tick_environment`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_reinforcements.gd` (a game started with `GameState.start_scenario` and a scenario whose side-1 frigate_32 has `"arrives": 3`, no sail_state; both sides AI or headless as `test_battle_to_victory.gd`):
  - `test_waiting_ship_is_placed_at_its_turn_with_plain_sail_speed`: after turn 2's ENVIRONMENT, still waiting; at turn 3's, `is_on_map()`, `speed == DataManager.get_movement_allowance("F/S", ws, wf, "ps", 4)`, one ARRIVED event in turn 3's log.
  - `test_entry_speed_uses_the_wind_before_this_turns_change`: a pending wind-speed change for turn 3 (`EnvironmentState.pending_wind_speed`) → `speed` from the old wind speed.
  - `test_held_entry_waits_a_turn`: a ship on the entry hex at turn 3 → ARRIVAL_DELAYED with `target_id` the holder, `arrives_turn == 4`; placed at turn 4 once the hex is clear.
  - `test_waiting_ship_takes_no_part`: run turns 1–2 through the whole phase loop: no turn-log event names the waiting ship as `ship_id` or `target_id`; `stub_ai.refusals` does not name it as an error; `in_play_ships_of_player` excludes it; a player commanding only it is auto-ready in PLANNING.
  - `test_default_course_and_deceleration_after_arrival`: a human-commanded reinforcement: in turn 3's PLANNING its stored default course has `min(speed, MA)` steps, and a stored course shorter than `speed − decel` is refused by `plan_errors` (5.E.4).
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement.** If a test shows a controller acting on a waiting ship despite `is_out_of_play()`, add the `is_on_map()` guard there and note it in the commit message.
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/map_controller.gd scripts/server/turn_phase_controller.gd test/unit/test_reinforcements.gd
git commit -m "feat: reinforcements arrive at the start of their turn at plain-sail speed (2.B.1, 3.A)"
```

### Task 11: Victory — escaped, aground, waiting ships and any number of sides

**Files:**
- Modify: `scripts/server/victory_controller.gd`.
- Test: create `test/unit/test_victory_terrain.gd`.

**Interfaces:**
- Consumes `MapRules.share`, the ship helpers (Task 2).
- `VictoryController`:

```gdscript
func is_lost(ship: ShipState) -> bool         # struck, destroyed, captured; aground when aground_counts_lost (default true)
func points_lost(ship: ShipState) -> float    # 0 waiting; full value when lost; else the section shares (escaped included)
func escape_points(ship: ShipState) -> float  # MapRules.share(scenario, ship.original_side) * value when escaped; else 0
func can_move_or_fight(ship: ShipState) -> bool  # true waiting; false escaped or aground; else as today
func _sides() -> Array[int]                   # distinct original sides of every ship, ascending ([0, 1] when none)
func _points_scored(side: int) -> float       # sum of points_lost over ships of other original sides + escape_points of its own
func _is_defeated(side: int) -> bool          # no ship it controls is (in play and not lost) or waiting
func check(turn: int) -> Dictionary           # as today; points = {side: float} for every side; winner = unique max, else -1
```

- Value is `ship.ship.point_value(ship.starting_crew_quality, ship.original_morale_rating())` as today. Update the class docstring.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_victory_terrain.gd` (fixtures as `test_victory_controller.gd`: a quality-D, rating-4 frigate worth 38):
  - `test_escaped_ship_yields_only_damaged_sections`: escaped, rigging section 1 empty → `points_lost == 1.9`; undamaged → 0.0.
  - `test_escape_share_goes_to_own_side`: `escape: {"1": {"share": 0.5}}` → `escape_points == 19.0`, and `check` (game ended by turn limit) has `points[1] == 19.0`, `points[0] == 0.0`.
  - `test_aground_counts_lost_by_default`: aground → `points_lost == 38.0`, `can_move_or_fight == false`; a side whose only ship is aground → reason `"all struck"`.
  - `test_aground_flag_off_scores_sections`: `aground_counts_lost: false`, aground with hull section 1 empty → `points_lost == 3.8`, `can_move_or_fight == false`, reason `"no ship able to move or fight"` for a side whose only ship is aground.
  - `test_waiting_reinforcement_keeps_its_side_alive`: side 1's only on-map ship struck, another waiting → `check(1) == {}`; `points_lost(waiting) == 0.0`; `can_move_or_fight(waiting) == true`.
  - `test_side_all_struck_or_escaped_is_done`: side 1 has one struck and one escaped ship → reason `"all struck"`.
  - `test_three_sides_score_every_other_side`: ships of sides 0, 1, 2; side 2's ship struck → `points[0] == 38.0`, `points[1] == 38.0`, `points[2] == 0.0`, `winner == -1`.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, `test_victory_controller.gd`, `test_boarding.gd`, `test_prizes.gd` and `test_end_by_agreement.gd` unchanged.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/victory_controller.gd test/unit/test_victory_terrain.gd
git commit -m "feat: victory points for escaped, aground and arriving ships, any number of sides (VI.A-B)"
```

### Task 12: Stub AI — safe water, the lead and escape

**Files:**
- Modify: `scripts/server/stub_ai.gd`.
- Test: create `test/unit/test_stub_ai_terrain.gd`.

**Interfaces:**
- Consumes `TerrainMap.grounds`, `distance_to_boundary`, `MapRules.crossing_outcome`, `may_declare`, `permission`, `TurnPhaseController.player_declare_escape`, `player_set_cast_lead`.
- `func _move_safe(ship_state: ShipState, move: MovementTypes.ValidMove) -> bool`: the crossing of the move (bow on an ahead step, stern on a turn, from the session's current pose) is CLEAR or ESCAPE; neither the resulting bow nor stern is land; an in-bounds resulting bow `grounds(…, draft) == "never"`.
- `BOUNDED_STRATEGIES` and `_move_in_bounds` are deleted. New signatures: `_steer(ship_state, controller, session_id, version, started, score, hold, avoid_bows) -> int` (always filters by `_move_safe`); `_clear_move(ship_state, moves, here, avoid) -> MovementTypes.ValidMove`; `_meet_deceleration_minimum(ship_id, controller, session_id, version, avoid := {}) -> int` (always prefers `_move_safe` moves, falling back as today).
- `func _escape_posture(ship_state: ShipState) -> bool`: `MapRules.may_declare(scenario, ship.side, turn)` and (`scenario.ai[str(side)] == "escape"` or `game_state.order_of(id).order == "disengage"`). `_get_strategy` returns `"escape"` for it (after `strategy_override`).
- In `_plot_ship`, an escaping ship calls `player_declare_escape(player_id, id, true)` before starting the session.
- `const ESCAPE_EXIT_SCORE := 10000`; `func _score_escape(bow: Vector2i, facing: int, ship_state: ShipState) -> int`: `ESCAPE_EXIT_SCORE` for a bow off the map; with permitted escape boundaries `-10 * min(distance_to_boundary(bow, name))`; else `_score_disengage` against `_nearest_enemy`. `_strategy_escape` steers with it (`hold = false`).
- `func _maybe_cast_lead(ship_state: ShipState) -> void`, after a successful submit: a plot of ≤ 2 steps with an ahead step whose bow `grounds` "maybe" or "always" → `player_set_cast_lead(player_id, id, true)`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_stub_ai_terrain.gd` (fixtures as `test_stub_ai.gd`):
  - `test_ai_never_plots_into_land`: a line of land across the engage course → no plotted step's bow or stern is land, for strategies engage, close and disengage.
  - `test_ai_steers_clear_of_doubtful_shoals`: a base-15 area (frigate_32, draft 16) on the direct course with deep water beside it → no plotted bow in the area.
  - `test_ai_casts_lead_on_short_course_through_shoal`: speed 2, every move but one ahead blocked so the course must enter a base-15 hex → `plotted_actions.cast_lead == true`; a 3-step course through it → false.
  - `test_ai_escape_posture_declares_and_runs_for_the_edge`: `escape: {"1": {}}`, W `escape`, `ai: {"1": "escape"}` → `escape_declared == true` and the end bow's `distance_to_boundary(…, "W")` is below the start's.
  - `test_ai_leaves_across_the_escape_edge`: bow on the W edge facing W → the first plotted step is off the map.
  - `test_disengage_order_escapes_only_when_permitted`: a disengage order with no `escape` entry → `escape_declared == false`, strategy disengage.
  - `test_aground_and_waiting_ships_are_skipped`: neither appears in `stub_ai.refusals` and neither gets a plot.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, `test_stub_ai.gd` unchanged.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/stub_ai.gd test/unit/test_stub_ai_terrain.gd
git commit -m "feat: the stub AI keeps to safe water, casts the lead and escapes"
```

### Task 13: View — the board, terrain, edges, arrivals and badges

**Files:**
- Modify: `scripts/core/hex_map.gd` (`_initialize_hex_tracking`, `_create_grid_overlay`), `scripts/view/hex_overlay.gd`, `scripts/core/game_controller.gd` (`_on_game_started`, `_sync_all_views`), `scripts/view/ship_view.gd`, `scripts/ui/planning_sail_ui.gd`.
- Test: create `test/unit/test_map_view.gd`.

**Interfaces:**
- `HexMap` iterates `TerrainMap.rect_hexes(grid_width, grid_height)` in both loops.
- `HexOverlay`: `var terrain_node: Node3D`; `func show_terrain(terrain: TerrainMap, hex_grid: HexGrid) -> void` and `func clear_terrain() -> void`. Children: `"Land_%d_%d"` and `"Shallow_%d_%d"` hex meshes (sand `Color(0.76, 0.66, 0.45, 0.85)`, pale green `Color(0.55, 0.80, 0.70, 0.55)`), one `Label3D` `"DepthLabel_<area>"` with text `"<name> <base+1>–<base+6> ft"` on the area hex nearest its centroid, and `"Edge_<boundary>_<i>"` strips along each side of `escape` (green) and `none` (red) boundaries.
- `GameController`: `_on_game_started` calls `hex_overlay.show_terrain(TerrainMap.of(GameState.active_scenario), hex_map.get_hex_grid())`; `static func views_to_spawn(view_ids: Array, ships: Array[ShipState]) -> Array[String]` (ids of on-map ships with no view, sorted); `_sync_all_views` spawns those first.
- `ShipView`: `static func explodes_on_sync(seen_afloat: bool, wrecked: bool, ship_state: ShipState) -> bool` (`seen_afloat and not wrecked and ship_state.is_on_map()`), used where `_play_explosion` is called.
- `PlanningSailUi.status_badge`: `"ESCAPED"` after `"DESTROYED"`, `"AGROUND"` after `"PRIZE"`; `movement_block_reason`: `"Ship has escaped."`, `"Ship is aground and cannot move (13.G.3)."`; `static func escape_badge(ship: ShipState) -> String` (`"ESCAPING"` for an in-play ship with `escape_declared`, else `""`), joined into `card_badge` after the fire badge.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_map_view.gd`:
  - `test_hex_map_tracks_the_rectangle`: a `HexMap` with `grid_width = 10`, `grid_height = 10` after `_initialize_hex_tracking()` has exactly the keys of `TerrainMap.rect_hexes(10, 10)` (has `(2, 4)`, lacks `(3, 4)`).
  - `test_show_terrain_tints_labels_and_edges`: land `[[0, 0], [1, 0]]`, area A base 15 on 3 hexes, W `escape` on 10 × 10 → `terrain_node` has 2 `Land_*`, 3 `Shallow_*`, a `DepthLabel_A` with text `"A 16–21 ft"`, ≥ 1 `Edge_W_*`, no `Edge_N_*`; `clear_terrain()` leaves no children.
  - `test_views_to_spawn`: views for `["a"]`, ships `a`, `b` (on the map), `c` (waiting), `d` (removed) → `["b"]`.
  - `test_no_explosion_off_the_map`: `explodes_on_sync(true, false, ship)` false for a destroyed ship removed from the map, true for one still on it.
  - `test_badges`: aground → `status_badge == "AGROUND"`, `can_plot_movement == false`; escaped → `"ESCAPED"`; declared → `escape_badge == "ESCAPING"` and `card_badge` contains it.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run and confirm everything passes.** `make test`. Expected: all green, `test_server_authority.gd` included.
- [ ] **Step 5: Check in the running game.** With the godot-mcp tools: `run_project` on `test_coastal` once Task 14 adds it (or a scratch copy of its JSON now), `game_screenshot`, and `game_get_errors` returns zero. Confirm the tints, the depth labels and the W edge strip are visible.
- [ ] **Step 6: Commit.**

```bash
git add scripts/core/hex_map.gd scripts/view/hex_overlay.gd scripts/core/game_controller.gd scripts/view/ship_view.gd scripts/ui/planning_sail_ui.gd test/unit/test_map_view.gd
git commit -m "feat: draw the rectangular board, terrain, edges, arriving ships and the new badges"
```

### Task 14: Test scenarios, scenario schema and the docs

**Files:**
- Create: `data/scenarios/test_coastal.json`, `data/scenarios/test_reinforcements.json`, `test/unit/test_map_scenarios.gd`.
- Modify: `.claude/skills/scenario-creator/SKILL.md`, `docs/rules/feature_diff.md`, `CLAUDE.md`.

**Interfaces:**
- `test_coastal.json`: 40 × 30; edges N `open`, E `none`, S `open`, W `escape`; a coast of land along part of the southern rows; shallow area A (base 15) and B (base 19) off it; `escape: {"1": {"from_turn": 1, "edges": ["W"], "share": 0.5}}`; `ai: {"1": "escape"}`; side 0 `frigate_38`, side 1 `frigate_32`; `turn_limit` 30; no ship on terrain.
- `test_reinforcements.json`: 100 × 100, no terrain; side 0 two ships, side 1 one ship at the start; side 1 `frigate_32` with `"arrives": 3`, side 0 `frigate_38` with `"arrives": 5` and `"sail_state": "MS"`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_map_scenarios.gd` (whole-loop driving as `test_battle_to_victory.gd`, every player AI):
  - `test_every_scenario_places_cleanly`: for every file in `res://data/scenarios/`, `DataManager.load_scenario` then `start_scenario` gives `placement_errors().is_empty()`.
  - `test_coastal_plays_twenty_turns_cleanly`: 20 turns (or to game over) with no `push_error`; at every END_TURN no on-map ship has a hex on land or off the map; by the end the side-1 ship has `escape_declared` or is ESCAPED.
  - `test_reinforcements_arrive_on_their_turns`: ARRIVED for the side-1 ship in turn 3's log and the side-0 ship in turn 5's, the latter with `sail_state == "MS"`.
- [ ] **Step 2: Run and confirm failure.** `make test`. Expected: the two scenario tests fail (files missing).
- [ ] **Step 3: Write the two scenario files.**
- [ ] **Step 4: Update `.claude/skills/scenario-creator/SKILL.md`**: `map_bounds` as rows × hexes in odd-r offset (the column formula); `terrain` (`edges`, `land`, `shallow`, `boundaries`), `escape`, `aground_counts_lost`, `ai`, ship `arrives` with the entry `sail_state` (default PS); validation rules (no ship on land or off the map, the TerrainMap errors).
- [ ] **Step 5: Update `docs/rules/feature_diff.md`** (invoke `close-action-rules` for the conventions):
  - Header "Compared against": add this sub-project with `git rev-parse --short HEAD`.
  - Remove the §2.2 rows "Reinforcements", "Escape and exit from the map…" and "Shallow water, land, running aground, casting the lead"; add one §2.2 row "Scattering (Scenario Book V.C), variable reinforcement entry (Scenario 12), special victory conditions (VI.C)" as Missing.
  - §5 rows ✔ (code columns by file and function): reinforcements (2.B.1, 3.A: `map_controller.gd` (`place_arrivals`, `arrival_speed`)); running aground and its consequences (13.G.1–3, 8.A.1: `movement_resolver.gd` (`_settle_terrain`), `drift_resolver.gd`, `gunnery_calculator.gd` (`preview`)); casting the lead (13.G.4: `movement_resolver.gd` (`_lead_side`)); escape (V.D.1–4, 8.G.1f, VI.A.1c, VI.B.6: `map_controller.gd` (`resolve_escapes`, `escape`), `map_rules.gd` (`condition`), `victory_controller.gd`); no sea room (III.C: `map_rules.gd` (`crossing_outcome`), `map_controller.gd` (`lose_off_map`)); land blocks LOS (7.B.7–9).
  - §4 rows: open edges are walls, no re-centring (III.B, U); an aground ship stays in the hexes before the step (13.G.2); a ship off the map is removed at once (III.C, V.D.2); an escape edge is a wall for an undeclared or unpermitted ship; the escape declaration stands until withdrawn (V.D.2); D.1 pursuers, `max_ma` and the linked-ship rule (V.D.1); the lead's deeper side, PM failure and no-turn hold, and it is not the 6.D.5 bear-off (13.G.4); arrival speed from the table only and the delayed entry (3.A); aground counts as lost unless `aground_counts_lost: false` (13.G.3); N-side scoring (VI.B.7).
- [ ] **Step 6: Update `CLAUDE.md`**: delete "Moves ahead are not limited to the map bounds (a bow may be plotted off the map), but a turn whose stern would leave the map is refused; drift treats the map edge as blocked." from Known Limitations and add the out-of-scope items; Turn Phase Cycle: ENVIRONMENT places arrivals first, DRIFT holds aground groups and grounds, END_TURN runs `resolve_escapes` after the 8.G.1f removal; Server Objects: `map_controller` and `MapRules`; `scripts/state/` lists `TerrainMap`; Hex Grid: the rectangle and typed boundaries; Ship Status: AGROUND, ESCAPED, waiting reinforcements (`is_out_of_play()` true while waiting); `ShipState` fields; Scenarios: the new keys; the event list; `stub_ai` (`_move_safe` for every strategy, the lead, the escape posture); the server requests list gains `player_declare_escape` and `player_set_cast_lead`.
- [ ] **Step 7: Run and confirm everything passes.** `make test`. Expected: all green. Then run the `scv-reviewer` agent (CLAUDE.md "SCV Audit") and fix what it finds.
- [ ] **Step 8: Commit.**

```bash
git add data/scenarios/test_coastal.json data/scenarios/test_reinforcements.json test/unit/test_map_scenarios.gd .claude/skills/scenario-creator/SKILL.md docs/rules/feature_diff.md CLAUDE.md
git commit -m "docs: coastal and reinforcement scenarios, scenario schema, feature_diff and CLAUDE.md for map and scenario"
```
