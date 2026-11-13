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
- `fire_geometry` (`FireGeometry`, `scripts/core/`): pure geometry — `bearing_side` (which broadside covers a hex, or -1), `rake_type`, `has_line_of_sight`, `broadside_hexes`.
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

Validate after edits: `python3 .claude/skills/validate-rule-table/scripts/validate_combat.py` (row counts, BGN band gaps/order, result-string syntax, unexpected damage dips; exit 1 on error). Run both validators; `make test` covers spot-checked cells (`test_combat_tables.gd`).

Other rule lookups on `DataManager`: `get_speed_change(change_type, maneuverability)`, `get_tacking_percent(maneuverability, wind_speed)`, `get_min_heading_change_movement_required(direction, ship_speed, maneuverability)`.

### Ship Definitions (`data/rules/ships.json`)

Ship ids: `frigate_38`, `frigate_32`, `ship_of_line_74` (`corvette_24` was removed — no chart row). Each has: name, nationality, rating, class (2–3), maneuverability, speed_type, draft, `freeboard`, `rigging_hp[4]`, `hull_hp[4]`, `crew_count[4]`, `marine_count`, `gun_factors` (`{"lg","mg","cr"}`: gun factors **per side**, long guns / medium / carronades), `ch_modifier` (critical-hit modifier, stored, unused until Milestone 2), `lower_deck_modifier` (stored, unused), `point_costs` (victory-point cost keyed `"<crew quality><morale rating>"`, e.g. `"B3"`). `armament` is display-only history. French-gunned ships use the second BGN value at ranges 11–15 (`Ship.is_french_gunned()`).

`ShipState` combat/turn-loop fields (all mutated only via `ShipStateController`): `status` (`ACTIVE`/`STRUCK`), `guns_dismounted[2]` and `initial_broadside_fired[2]` (per side), `sail_change` (`{}` or `{target, turns_left, sections}`), `moved_this_turn`, `pending_morale_checks` + `morale_triggers_used`, `unfoul_attempts`, `starting_crew_quality`. `crew_count` is four sailor sections, `marine_count` separate, both initialised from the ship definition; `morale_rating` is 2–6 (higher is worse) and never changes; `crew_quality` is a letter A–G and falls on failed morale checks.

### Scenarios (`data/scenarios/*.json`)

Wind conditions, map config, ship placements with position (q,r), facing, sail state, crew quality/morale.

## Conventions and Gotchas

### Hex Grid
- **Axial coordinates** (q, r) with **pointy-top** orientation
- **Direction numbering**: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
- **All ships are 1-hex.** `ShipState.get_ship_size()` is deprecated and hardcoded to return 1; use `HexGrid.axial_to_world()` for positioning. The `size == 2` branches in `ShipView` are dead code kept for possible future revival. (`HexGrid.axial_to_edge_world()` is live — `ShipIndicatorModel` uses it to compute hex-face midpoints for the selection indicators.)

### Sides, Arcs and Rake
- Side indices: `ShipState.PORT = 0`, `ShipState.STARBOARD = 1`. Starboard is `facing + 1` / `facing + 2`; port is `facing − 1` / `facing − 2` (mod 6).
- **Broadside arc**: the 60° wedge centred on the beam, out to range 15. `FireGeometry.bearing_side` is an angle test (60°–120° off the bow, with a 0.5° tolerance), which corresponds to the hex rows of directions `facing ± 1` and `facing ± 2`. Ahead/astern are blind; no chase guns.
- **Rake**: target within 5 hexes and the firer strictly inside the target's bow or stern 60° wedge (within 30° of the line ahead/astern; the boundary does not count). Stern rake doubles crew hits.
- Fire orders: per broadside one target, aim `low`/`high`, ammo `round` (range 15) or `dismantling` (range 7). Ranges 10–15 are high only. Two targets (one per side) = −12 on each shot.

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
- The `size == 2` branch in `ShipView._update_position_from_state` is unused (all ships are 1-hex). Note: `HexGrid.axial_to_edge_world()` is now used by `ShipIndicatorModel` and is no longer dead (see Hex Grid note).

### SCV Audit
Run the `scv-reviewer` agent as a **final step** before reporting any planned work as complete. Do not run it after each individual task or phase — only once at the very end, after all code changes are made and tests pass. Fix any violations it finds before finishing.

### Known Limitations
- The camera renders the map mirrored (`scripts/core/isometric_camera.gd` builds a left-handed basis), so "starboard" appears on a ship's left on screen.
- Nothing constrains plotted movement to the map bounds; drift treats the map edge as blocked.
- The stub AI stalls instead of tacking when the wind blows straight against its approach.
- Not implemented (Milestone 2): critical hits (CH# is stored only), fire, sinking, boarding, marine fire, repairs, grappling, manual crew tasks. Milestone 3 items (anchoring, lower-deck guns, chase guns, medium guns, class 4 ships) are also absent.
- Mouse clicks could not be injected through godot-mcp during verification (window unfocused); UI was driven by emitting control signals.

### Developer UI
- Press **F12** in-game to toggle the debug inspection panel
- Shows ship state details, turn info, and environment data
