# CLAUDE.md

Guidance for Claude Code working on the Leeward project.

For human-facing developer setup (prerequisites, Godot MCP bridge, contribution flow), see `CONTRIBUTING.md`. This file is Claude-facing.

## Project Overview

Leeward is a Godot 4.6 naval sailing game (Age of Sail) using the Forward Plus renderer. It's a turn-based tactical game where players command ships on a hex grid, plotting movement and combat across a 10-phase turn cycle. Architecture is server-authoritative with a State-Controller-View pattern.

## Tooling (MCP Servers)

**Prefer the `godot-mcp` MCP server for Godot interactions whenever possible**, instead of ad-hoc shell commands. It is the most reliable way to drive the editor and a running game. Use it for:
- Running/stopping the project (`run_project`, `stop_project`) and reading output (`get_debug_output`).
- Checking the running game for problems: `game_get_errors` (push_error/push_warning + parser warnings) and `game_get_logs` (print output). After editing GDScript, relaunch and confirm `game_get_errors` returns zero — this is the canonical way to verify a clean build.
- Inspecting/driving the live game (scene tree, nodes, input, screenshots) via the `game_*` tools, and project/scene/script management (`read_scene`, `read_project_settings`, `list_project_files`, etc.).
- Note the in-game interaction server (`scripts/mcp_interaction_server.gd`) binds `127.0.0.1:9090`; the `game_*` tools connect to it. If `game_get_errors`/`game_get_logs` returns "No active Godot process" right after launch, it's a startup race — wait ~1s and retry.
- **Clicking the UI**: `game_click(x, y)` takes **window pixels**, not UI coordinates. Multiply a control's `get_global_rect()` position (or `Camera3D.unproject_position()` for a hex or ship) by the root viewport scale, `get_tree().root.get_final_transform().get_scale()` (about 1.89 on a Retina display), before clicking. Unscaled coordinates land on the wrong spot and look like ignored clicks. Drive the UI with real clicks rather than by emitting control signals.
- A script error inside `game_eval` freezes the running game; stop and relaunch it.

**For Godot API docs, use the `context7` MCP server with library `/godotengine/godot-docs`.** Call `context7` (`query-docs` against `/godotengine/godot-docs`) before relying on memory for engine/class/method APIs — training data may lag the 4.6 API. Skip the `resolve-library-id` step; this project's library ID is fixed.

## Commands

```bash
make help                         # Show all available targets
make run                          # Run project (starts at main.tscn → splash screen)
make play                         # Run directly into gameplay (skip menus)
make editor                       # Open in Godot Editor
make import                       # Rebuild Godot import cache
make clean                        # Remove .godot cache (forces full reimport)
```

### Testing

Uses [GUT](https://github.com/bitwes/Gut) v9.5.0 (`addons/gut/`). Tests live in `test/unit/` and extend `GutTest`.

```bash
make test                         # Run all tests (headless)
make test-verbose                 # Run all tests with detailed output
make test-file F=test/unit/test_data_manager_ships.gd  # Run a single test file
```

Test naming: files prefixed `test_`, methods prefixed `test_`. Use `before_all()` / `before_each()` for setup.

Manual testing also available via scenarios and the Developer UI (F12 in-game).

## Project Structure

```
scripts/
  autoload/       # Singletons: Trace, GameState, DataManager (see project.godot [autoload]); CombatTables (class, owned by DataManager)
  core/           # Game controller, hex grid, hex map, camera, wave calc, fire_geometry (arcs, rake, line of sight)
  state/          # Pure data objects: Ship (immutable), ShipState (mutable), EnvironmentState
  server/         # Server-authoritative controllers (mutations, validation, phases, gunnery, damage, drift, morale, victory, AI)
  view/           # 3D presentation (ShipView, HexOverlay)
  ui/             # All UI scripts
  commands/       # Command pattern (GameCommand, MoveCommand)
  util/, utils/   # Asset-generation helpers (compass, water texture) — not runtime code
scenes/
  main.tscn       # Entry point (scene navigation controller)
  splash_screen.tscn → scenario_selection.tscn → main_game.tscn
  ui/             # UI subscenes (planning, minimap, compass, dev UI)
data/
  rules/          # movement_allowance, ships, bearing_off_table, speed_change_table,
                  #   tacking_table, turning_table + the 1997 combat tables (see Key Data Formats) (all .json)
  scenarios/      # Scenario definitions (test_basic.json, test_fleet.json)
docs/             # Design docs, game rules, architecture diagrams
assets/           # Models, textures, shaders, UI art
test/
  unit/            # GUT unit tests (test_*.gd); scripted_dice.gd = ScriptedDice
addons/           # godot_mcp (MCP server addon), GUT testing framework
```

## Architecture

### State-Controller-View (SCV)

- **State layer** (`scripts/state/`): `Ship` (immutable identity + type data), `ShipState` (mutable game state, references `Ship`), `EnvironmentState`. Serializable, deterministic. No logic.
- **Controller layer** (`scripts/server/`): Server-authoritative game logic. All state mutations happen here. Controllers check `is_server` before mutating. Clients are read-only.
- **View layer** (`scripts/view/`, `scripts/ui/`): Presentation only. Reads state, renders visuals. Never mutates game state.

### Autoload Singletons

- **GameState** (`scripts/autoload/game_state.gd`): Central state container. Holds all ships, environment, turn/phase, state history. Creates and owns all server controllers in `_ready()`.
- **DataManager** (`scripts/autoload/data_manager.gd`): Loads and caches JSON data (movement tables, ship definitions, scenarios). Provides lookup methods. `DataManager.combat_tables` is the `CombatTables` instance holding the 1997 combat charts.
- **Trace** (`scripts/autoload/trace.gd`): Lightweight tracing/logging autoload. **Required** in runtime code — `.claude/hooks/block_raw_print.py` blocks raw `print()` at Edit/Write time. Exempt: `scripts/util/`, `scripts/utils/`, `scripts/autoload/trace.gd`, `scripts/autoload/mcp_server.gd`, `addons/`. Per-line bypass: trailing `# allow-print`. Covered by `test_trace.gd`.

**Auto-test hook**: `.claude/hooks/run_related_tests.py` runs `make test` automatically after editing files in `scripts/server/`, `scripts/state/`, `scripts/core/`, `scripts/autoload/`, or `test/unit/`. Configured as a `PostToolUse` hook in `.claude/settings.json`.

Note: `scripts/autoload/mcp_server.gd` lives in this folder but is **not** an autoload — it's wired through the `godot_mcp` editor plugin.

### Turn Phase Cycle (10 phases)

SETUP → ENVIRONMENT → PLANNING → MOVEMENT_RESOLUTION → COMBAT_RESOLUTION → DRIFT_CALCULATION → STATUS_ADJUSTMENT → MORALE_CHECK → MESSAGE_DELIVERY → POST_COMBAT → END_TURN → (back to ENVIRONMENT)

Managed by `TurnPhaseController`. All phases do real work except MESSAGE_DELIVERY (stub, auto-advances). The `GamePhase` enum is unchanged; combat's two steps are `TurnPhaseController.CombatStep` (`NONE`, `DECLARE`, `RESOLVE`).

- **ENVIRONMENT**: `EnvironmentController.tick_environment` (wind/sea rolls via `Dice`).
- **PLANNING**: AI ships plot (`StubAI.plot_all_ai_ships`); the player plots movement and optional sail-change orders; waits for `player_submit_plan(0)`.
- **MOVEMENT_RESOLUTION**: `SailController.begin_plotted_changes()` starts plotted sail changes, then the movement resolver runs (sets `moved_this_turn`). Waits for the view to call `on_playback_completed()`, which applies results.
- **COMBAT_RESOLUTION**: fire declaration is a step inside this phase (targets are chosen after movement). If `gunnery_calculator.any_eligible_shot()` is false the phase is skipped (`combat_step` stays `NONE`). Otherwise `DECLARE`: emits `fire_declaration_requested`, the AI submits via `StubAI.submit_fire_orders()`, the player via `player_submit_fire_orders(player_id, orders)` (returns "" or a rejection reason; orders are hidden until both are in). Then `RESOLVE`: `gunnery_resolver.resolve()` computes all shots against start-of-step state, applies damage, emits `combat_log_ready`; waits for the view to call `on_combat_playback_completed()`.
- **DRIFT_CALCULATION**: `drift_resolver.resolve()` for stopped ships.
- **STATUS_ADJUSTMENT**: `fouling_controller.resolve_unfouling()`, then `sail_controller.advance_changes()` (sail changes complete here).
- **MORALE_CHECK**: `morale_controller.resolve_checks()` rolls the checks noted during the turn; failures lower crew quality or strike the ship.
- **POST_COMBAT**: waits for the player to press End Turn (`player_end_turn(0)`); `advance_phase()` is ignored here. No timer.
- **END_TURN**: `victory_controller.check(turn)`. A non-empty result is stored in `phase_controller.game_result`, `game_over` is emitted, and the loop stops (phase stays END_TURN, `advance_phase`/submits are refused). Otherwise flags are cleared and the next turn begins.

The gunnery resolver, damage, drift, fouling, morale and sail controllers append typed events to `GameState.turn_log` (`PhaseEvents.PhaseLog`), and `TurnPhaseController` adds the VICTORY event at END_TURN; environment, planning and movement log no events; finished turns are kept in `GameState.turn_logs[turn]`. The UI renders these as the combat log.

When changing a phase method, invoke the `phase-implementer` skill (`.claude/skills/phase-implementer/`). It codifies the SCV pattern (server-authority guard, `game_state.dice`, automatic state-history snapshots, GUT test template).

Other project skills: `scenario-creator` (create scenario JSONs), `gen-test` (scaffold GUT test files). The `scv-reviewer` agent (`.claude/agents/scv-reviewer.md`) audits State-Controller-View pattern adherence across the codebase.

### Server Objects on GameState (created in `_initialize_server_controllers()`)

All except `dice` (takes the RNG) and `fire_geometry` (takes a `HexGrid`) take `game_state` in `_init` and reach collaborators through it. Names are exact. `stub_ai` predates the turn-loop work (it now also submits fire orders):

- `dice` (`Dice`): the default source of randomness for game logic (see Dice below).
- `fire_geometry` (`FireGeometry`, `scripts/core/`): pure geometry — `bearing_side` (which broadside covers a hex from a battery hex, or -1), `range_between` (closest hexes), `battery_bears`/`in_battery_arc` (per-battery arc and LOS), `rake_type_ships`, `has_line_of_sight`, `broadside_hexes` (per battery hex; callers draw bow ∪ stern).
- `gunnery_calculator` (`GunneryCalculator`): pure queries, no dice, no mutation — `preview(order, two_targets)` gives a `ShotPreview` (modified gunfire number + modifier breakdown), `eligible_shots`, `any_eligible_shot`, `validate_orders`. Types in `gunnery_types.gd` (`FireOrder`, `ShotPreview`; aims `low`/`high`, ammo `round`/`dismantling`).
- `gunnery_resolver` (`GunneryResolver`): rolls and applies a set of `FireOrder`s simultaneously, logging each shot.
- `damage_controller` (`DamageController`): applies rigging/hull/crew boxes (lowest section first), dismounts guns on hull-section loss, notes morale checks, strikes ships.
- `sail_controller` (`SailController`): plots, progresses and cancels sail changes (`plot_sail_change`, `begin_plotted_changes`, `advance_changes`).
- `drift_resolver` (`DriftResolver`): drift of stopped ships, collision/fouling on blocked drift.
- `fouling_controller` (`FoulingController`): unfouling rolls for fouled pairs.
- `morale_controller` (`MoraleController`): rolls noted morale checks, lowers crew quality, strikes at quality G.
- `victory_controller` (`VictoryController`): `check(turn)` returns `{}` or `{winner, reason, points, turn}`; optional scenario `turn_limit`.
- `stub_ai` (`StubAI`): drives the real plotting protocol (default strategy `engage`: close, present a broadside within `FIRING_RANGE`) and submits fire orders (best modified number per broadside; low inside range 10).
- `turn_log` / `turn_logs`: current and past `PhaseEvents.PhaseLog` (events: FIRE, DAMAGE, GUNS_DISMOUNTED, MORALE_NOTED, MORALE_CHECK, STRIKE, DRIFT, FOULED, UNFOUL, SAIL_CHANGE, VICTORY).

### Dice

`Dice` (`scripts/server/dice.gd`) wraps `GameState.rng`: `d6()` is 1–6, `d10()` is **0–9** (as on the 1997 charts), `two_d6()`, `two_d10()` is **0–18**. **New game logic must roll through `game_state.dice`** — never call `randi()` or `rng` directly. Known, accepted exception: `MovementResolver` still rolls directly from its `rng` property (`rng.randi_range`/`rng.randf`; it uses `game_state.rng` unless an explicit RNG is set), and `EnvironmentController` still passes `game_state.rng` into `_update_weather`. `ScriptedDice` (`test/unit/scripted_dice.gd`, a `Dice` subclass) returns queued values (`queue([...])`; `two_*` pop two) so tests can fix rolls.

### Movement Plotting Protocol

Session-based async system in `MovementPlottingController`/`MovementPlottingSession`:
- Requests: START_PLOTTING, SELECT_HEX, UNDO, SUBMIT_MOVEMENT, CANCEL_PLOTTING
- Typed response classes in `movement_types.gd` (PlottingStartedResponse, HexSelectedResponse, etc.)
- Sessions auto-expire after 5 minutes; version number increments on each change for conflict resolution
- Valid moves stored in `ShipState.plotted_actions`

## Key Data Formats

### Movement Allowance Table (`data/rules/movement_allowance.json`)

5-level nested lookup: `speed_type → wind_facing → wind_speed → rigging_quality → sail_state → MA`

- Speed types: `L/F`, `L/S`, `L/VS`, `F/F`, `F/S`, `F/VS`, `C/F`, `C/S`, `C/VS`
- Wind facings: `C` (close-hauled), `B` (broad reach), `R` (reach), `L` (luffing — always returns 0)
- Wind speed: `1`–`4` (string keys). Wind speed 0 (calm) is not in the table: `ShipStateController.get_movement_allowance` and `MovementValidator._lookup_ma` return 0 before the lookup.
- Rigging level: `1`–`4` = number of rigging sections that still have boxes (see Rigging level rule)
- Sail states: `fs` (fighting), `ms` (maneuvering), `ps` (plain), `ns` (no sail)

Access via `DataManager.get_movement_allowance(speed_type: String, wind_speed: int, wind_facing: String, sail_state: String, rigging_quality: int)`. Note the argument order does **not** match the JSON nesting order, and `wind_speed`/`rigging_quality` are `int` at the API even though the JSON keys are strings. The `rigging_quality` argument is the **rigging level** (1–4, asserted); level 0 (dismasted) must never reach the table — `ShipStateController.get_movement_allowance` returns 0 first. Callers pass `ShipState.movement_sail_state()`, not the raw `sail_state`.

**Rigging level rule** (Close Action 5.F): rigging level = number of rigging sections with at least one box (`ShipState.rigging_level()`, 0–4). Plain sail (PS) only at level 4; manoeuvring sail (MS) at levels 4–3; fighting sail (FS) until dismasted (level 0). `max_sail_state()` gives the cap; `movement_sail_state()` = lower of carried `sail_state` and the cap. A ship carrying more sail than its rigging allows is not forced down: it moves at the capped state but takes damage at the state it carries. Low-level rows in `movement_allowance.json` are keyed `fs` accordingly.

Validate after edits: `python3 .claude/skills/validate-rule-table/scripts/validate.py`. Catches typos (e.g. `"FS"` vs `"fs"`) that would silently return 0 at lookup time instead of erroring.

### Combat Tables (`data/rules/`, transcribed from the 1997 chart scans `docs/*.jpeg`)

Loaded by `CombatTables` (`DataManager.combat_tables`). Never take numbers from `docs/Close-Action-Rules-v6-1.txt` or `docs/07-naval-combat-mechanics.md` (non-canonical). Where rule text and chart disagree the chart wins (two-target modifier is −12).

- `gunnery_factor_table.json`: LG/MG/CR multiplier by range 1–15 → `gunnery_multiplier(gun_type, range)`.
- `basic_gunfire_number_table.json`: total gunnery factor (TGF band) × range → BGN; second value for French guns at range 11–15; blank = cannot fire → `basic_gunfire_number(tgf, range, french)`.
- `gunfire_results_table.json`: final gunfire number 1–52+ → FS/+MS/+PS columns for aim low/high, plus CH# → `gunfire_result(fgn, aim, column)`, `critical_hit_number(fgn)`. Slashed results (`r/c`) are resolved with a d6.
- `gunfire_modifiers.json`: range bonuses and flat modifiers → `range_bonus(kind, range)`, `flat_modifier(name)`, `sections_firing_modifier(n)`.
- `crew_loss_table.json`: sailor/marine split by cause → `crew_loss_is_sailor(cause, d6)`.
- `drifting_table.json`: sail state × wind speed number, class DRMs → `drift_number`, `drift_class_drm`.
- `unfouling_table.json`: success threshold by attempt → `unfouling_success_max(attempt)`.
- `crew_quality_table.json`: gunnery and SK modifiers by quality letter → `crew_quality_modifier`, `skill_modifier`.
- `tacking_table.json` and `bearing_off_table.json` (loaded by `DataManager`, not `CombatTables`): the TACKING and BEARING OFF d10 charts, stored as the chart's "roll ≤ n" numbers. `MovementResolver` applies the chart DRMs.

Validate after edits: `python3 .claude/skills/validate-rule-table/scripts/validate_combat.py` (row counts, BGN band gaps/order, result-string syntax, unexpected damage dips; exit 1 on error). Run both validators; `make test` covers spot-checked cells (`test_combat_tables.gd`).

Other rule lookups on `DataManager`: `get_speed_change(change_type, maneuverability)`, `get_tacking_number(maneuverability, wind_speed)` (d10 ≤ n succeeds; -1 at WS 0; `get_tacking_percent` is the base chance for display), `get_bearing_off_number(crew_quality, maneuverability)` (d10 ≤ n; -1 = NA), `get_min_heading_change_movement_required(direction, ship_speed, maneuverability)`.

### Ship Definitions (`data/rules/ships.json`)

Ship ids: `frigate_38`, `frigate_32`, `ship_of_line_74` (`corvette_24` was removed — no chart row). Each has: name, nationality, rating, class (2–3), maneuverability, speed_type, draft, `freeboard`, `rigging_hp[4]`, `hull_hp[4]`, `crew_count[4]`, `marine_count`, `gun_factors` (`{"lg","mg","cr"}`: gun factors **per side**, long guns / medium / carronades), `ch_modifier` (critical-hit modifier, stored, unused until Milestone 2), `lower_deck_modifier` (stored, unused), `point_costs` (victory-point cost keyed `"<crew quality><morale rating>"`, e.g. `"B3"`). `armament` is display-only history. French-gunned ships use the second BGN value at ranges 11–15 (`Ship.is_french_gunned()`).

`ShipState` combat/turn-loop fields (all mutated only via `ShipStateController`): `status` (`ACTIVE`/`STRUCK`), `guns_dismounted[2]` and `initial_broadside_fired[2]` (per side), `sail_change` (`{}` or `{target, turns_left, sections}`), `moved_this_turn`, `pending_morale_checks` + `morale_triggers_used`, `unfoul_attempts`, `starting_crew_quality`. `crew_count` is four sailor sections, `marine_count` separate, both initialised from the ship definition; `morale_rating` is 2–6 (higher is worse) and never changes; `crew_quality` is a letter A–G and falls on failed morale checks.

### Scenarios (`data/scenarios/*.json`)

Wind conditions, map config, ship placements with position (q,r), facing, sail state, crew quality/morale.

## Conventions and Gotchas

### Hex Grid
- **Axial coordinates** (q, r) with **pointy-top** orientation
- **Direction numbering**: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
- **World/screen orientation**: world +X is east, −Z is north. `IsometricCamera` builds a right-handed basis (covered by `test_isometric_camera.gd`); `camera_rotation_y = 90` is north-up/east-right and only the player's camera controls change it. Selecting a ship never rotates or zooms the camera (`pan_to_if_needed` pans only when the ship is near the screen edge).
- **Owner colours**: green = human player's ships, red = enemy (`ShipView.owner_color`, shared by the map ring/pennant and the minimap).
- **All ships are 2-hex** (`ShipState.get_ship_size()` = 2). `ShipState.hex_position` is the **bow**; the stern is derived, never stored: `HexGrid.stern_of(bow, facing)` = neighbour in `(facing + 3) % 6`, or `ShipState.stern_hex()` / `occupied_hexes()` (`[bow, stern]`). A ship always sits on two hexes, never along a hex spine (5.A.2c). Position the model with `HexGrid.ship_center_world(bow, facing)`, not `axial_to_world()`. (`HexGrid.axial_to_edge_world()` is live — `ShipIndicatorModel` uses it to compute hex-face midpoints for the selection indicators.)
- **Occupancy** (`scripts/server/occupancy.gd`, `Occupancy`): `build(ships, exclude_ids)` and `from_positions(bows, facings, exclude_ids)` map every occupied hex to a ship id; `overlapping_ids`; `in_bounds(hex, scenario)` (both hexes must be on the map). `GameState.placement_errors()` checks scenario placements. `GameController.ship_at_hex(hex, ships)` (static) picks a ship by either hex.
- **Turns pivot on the bow**: the stern swings. A plot step's `hex` is the resulting bow (unchanged for a turn, new facing); `ValidMove.hex` is the click target (for a turn, the bow's neighbour in the new facing). A turn whose new stern is out of bounds is refused. In resolution each step enters one hex (ahead → new bow, turn → new stern); a stern may swing into a hex another ship holds or a bow enters (`OVERLAP`, 6.B.2) if the two ships no longer share a hex at the end of the next segment; otherwise the turn is rolled back (`OVERLAP_ROLLBACK`, "already occupied" or "bow precedence"): the turning ship's plot is amended to the steps before the turn plus any ahead steps its deceleration minimum needs, and the whole resolution is re-run from the same RNG state. Two sterns swinging into one hex with no further MPs plotted (6.C.1b), or two ships swinging onto each other's bows (complete overlap, 6.B.5), contest it with the 6.C.2 roll (`CONTESTED_HEX_ROLL`): the winner turns (stub: the winner always chooses itself), the loser's turn is cancelled (`STERN_BLOCKED` "lost stern contest to <id>", stop cause `stern_contest`), never a collision; a loser that must still meet its deceleration minimum has its plot amended with ahead steps and the resolution replayed, with the rolls put back into the final log. If either stern ship has further MPs it is a 6.B overlap instead ("sterns together" if not cleared).
- **Speed** counts executed steps, turns included, if the ship moved ahead at least once, else 0; `moved_this_turn` means moved ahead at least once (5.E.2).

### Sides, Arcs and Rake
- Side indices: `ShipState.PORT = 0`, `ShipState.STARBOARD = 1`. Starboard is `facing + 1` / `facing + 2`; port is `facing − 1` / `facing − 2` (mod 6).
- **Batteries**: each side has two batteries, one at the bow hex and one at the stern hex. **Broadside arc** (per battery): the 60° wedge centred on the beam out to range 15. `FireGeometry.bearing_side` is an angle test (60°–120° off the bow, with a 0.5° tolerance), which corresponds to the hex rows of directions `facing ± 1` and `facing ± 2`. Ahead/astern are blind; no chase guns. A battery bears if at least one target hex is in its arc and every target hex in its arc has line of sight (target hexes outside the arc are ignored, 7.B.6); the ship's own hexes and the target's do not block. Range is measured to the closest hexes (7.C.4).
- **Battery orders** (7.B.1): `FireOrder.battery` is `full` (both batteries of the side must bear), `bow` or `stern`. A single battery is a half broadside: `half_broadside` (−8), except when the ship names two targets (only the −12 two-target modifier applies, 7.C.12g). `validate_orders` refuses a battery fired twice, more than two targets per ship, and bow+stern of one side at one target (declare a full broadside). A side may split (bow at one target, stern at another).
- **Previews**: `GunneryCalculator.preview_orders(orders)` previews a whole order set as it will resolve (two targets per ship; the initial-broadside bonus once per broadside, 7.C.10: the larger bonus, bow on a tie). The resolver and the fire panel both use it, so displayed numbers equal rolled ones; single `preview()` cannot know the rest of the set.
- **Fire panel** (`fire_declaration_panel.gd`): each target row offers "Full broadside" when both batteries bear, else "Bow battery"/"Stern battery"; a full-broadside target offers the free battery while the other fires elsewhere. The map highlights the chosen battery's arc (`GameController.battery_arc`). The no-shot reason comes from the bearing battery's preview.
- **Rake** (`rake_type_ships`, 7.E.2): range (closest hexes) ≤ 5 and the firer is outside all four of the target's battery arcs, or directly ahead of its bow / astern of its stern and adjacent. Stern rake (firer aft of the target's beam line) doubles crew hits.
- Fire orders: per battery one target, aim `low`/`high`, ammo `round` (range 15) or `dismantling` (range 7). Ranges 10–15 are high only. Two targets = −12 on each shot.

### Ship Status
- A STRUCK ship cannot move, fire, change sail or unfoul and is not a valid target, but it still drifts and blocks line of sight and hexes.
- A fouled ship (`fouled_with != ""`) cannot plot or execute movement (plotting returns `SHIP_FOULED`); it can still fire and be fired on. Dismasted and struck ships also refuse plots (`SHIP_DISMASTED`, `SHIP_STRUCK`).
- A `ShipState` whose `rigging_current_hp` is all zeros is **dismasted** (level 0, movement allowance 0). Test fixtures must set rigging explicitly.

### Tests and RNG
- Any code or test that assigns `GameState.rng` **must also assign `GameState.dice`** (`GameState.dice = Dice.new(GameState.rng)`); otherwise dice keep using the old RNG. `GameState.start_new_game` does both.
- `make test-file F=...` currently runs the **whole suite** (the GUT CLI picks up all of `test/unit`).
- `addons/gut/gut_loader.gd` carries a one-line local patch (`get_setting(..., true)` instead of `get()` for `exclude_addons`, absent in Godot 4.6). Keep it when updating GUT. `make import` prints `SCRIPT ERROR`s from the GUT editor plugin; they are noise.

### Server Authority
- All mutations guard with `if not is_server: push_error()` — never bypass this
- Controllers in `scripts/server/` are server-only; clients are read-only observers

### State History
- Indexed by turn number: `environment_history[turn]`, `ship_history[ship_id][turn]`
- Snapshots saved AFTER turn completes, before advancing

### Environment RNG
- `EnvironmentController` manages RNG seed for determinism
- Wind changes use 2d10 rolls; a 16+ steps the wind one step back toward the scenario's starting speed and direction (`EnvironmentState.original_wind_speed` / `original_wind_direction`, set in `initialize_from_scenario`; direction the shorter way round)

### Movement Allowance Lookup
- All keys are **strings** (including wind_speed and rigging_quality)
- Wind-facing `"L"` (luffing/into wind) is a special case that always returns 0
- Uses `assert()` for parameter validation — fails fast on bad input

### Legacy Code
- `scripts/ui/planning_panel.gd` is legacy; `planning_phase_ui.gd` is the current version

### SCV Audit
Run the `scv-reviewer` agent as a **final step** before reporting any planned work as complete. Do not run it after each individual task or phase — only once at the very end, after all code changes are made and tests pass. Fix any violations it finds before finishing.

### Known Limitations
- Nothing constrains plotted movement to the map bounds; drift treats the map edge as blocked.
- The stub AI stalls instead of tacking when the wind blows straight against its approach.
- Not implemented (Milestone 2): critical hits (CH# is stored only), fire, sinking, boarding, marine fire, repairs, grappling, manual crew tasks. Milestone 3 items (anchoring, lower-deck guns, chase guns, medium guns, class 4 ships) are also absent.

### Developer UI
- Press **F12** in-game to toggle the debug inspection panel
- Shows ship state details, turn info, and environment data
