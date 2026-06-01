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
  autoload/       # Singletons: Trace, GameState, DataManager (see project.godot [autoload])
  core/           # Game controller, hex grid, hex map, camera, wave calc
  state/          # Pure data objects: Ship (immutable), ShipState (mutable), EnvironmentState
  server/         # Server-authoritative controllers (mutations, validation, phases)
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
                  #   tacking_table, turning_table (all .json)
  scenarios/      # Scenario definitions (test_basic.json, test_fleet.json)
docs/             # Design docs, game rules, architecture diagrams
assets/           # Models, textures, shaders, UI art
test/
  unit/            # GUT unit tests (test_*.gd)
addons/           # godot_mcp (MCP server addon), GUT testing framework
```

## Architecture

### State-Controller-View (SCV)

- **State layer** (`scripts/state/`): `Ship` (immutable identity + type data), `ShipState` (mutable game state, references `Ship`), `EnvironmentState`. Serializable, deterministic. No logic.
- **Controller layer** (`scripts/server/`): Server-authoritative game logic. All state mutations happen here. Controllers check `is_server` before mutating. Clients are read-only.
- **View layer** (`scripts/view/`, `scripts/ui/`): Presentation only. Reads state, renders visuals. Never mutates game state.

### Autoload Singletons

- **GameState** (`scripts/autoload/game_state.gd`): Central state container. Holds all ships, environment, turn/phase, state history. Creates and owns all server controllers in `_ready()`.
- **DataManager** (`scripts/autoload/data_manager.gd`): Loads and caches JSON data (movement tables, ship definitions, scenarios). Provides lookup methods.
- **Trace** (`scripts/autoload/trace.gd`): Lightweight tracing/logging autoload. **Required** in runtime code — `.claude/hooks/block_raw_print.py` blocks raw `print()` at Edit/Write time. Exempt: `scripts/util/`, `scripts/utils/`, `scripts/autoload/trace.gd`, `scripts/autoload/mcp_server.gd`, `addons/`. Per-line bypass: trailing `# allow-print`. Covered by `test_trace.gd`.

**Auto-test hook**: `.claude/hooks/run_related_tests.py` runs `make test` automatically after editing files in `scripts/server/`, `scripts/state/`, `scripts/core/`, `scripts/autoload/`, or `test/unit/`. Configured as a `PostToolUse` hook in `.claude/settings.json`.

Note: `scripts/autoload/mcp_server.gd` lives in this folder but is **not** an autoload — it's wired through the `godot_mcp` editor plugin.

### Turn Phase Cycle (10 phases)

SETUP → ENVIRONMENT → PLANNING → MOVEMENT_RESOLUTION → COMBAT_RESOLUTION → DRIFT_CALCULATION → STATUS_ADJUSTMENT → MORALE_CHECK → MESSAGE_DELIVERY → POST_COMBAT → END_TURN → (back to ENVIRONMENT)

Managed by `TurnPhaseController`. Currently ENVIRONMENT, PLANNING, and MOVEMENT_RESOLUTION are implemented; others are stubbed.

When implementing a stubbed phase, invoke the `phase-implementer` skill (`.claude/skills/phase-implementer/`). It codifies the SCV pattern (server-authority guard, `game_state.rng`, automatic state-history snapshots, GUT test template) grounded in the three implemented phases.

Other project skills: `scenario-creator` (create scenario JSONs), `gen-test` (scaffold GUT test files). The `scv-reviewer` agent (`.claude/agents/scv-reviewer.md`) audits State-Controller-View pattern adherence across the codebase.

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
- Wind speed: `1`–`4` (string keys)
- Rigging quality: `1`–`4` (calculated from HP percentage)
- Sail states: `fs` (fighting), `ms` (maneuvering), `ps` (plain), `ns` (no sail)

Access via `DataManager.get_movement_allowance(speed_type: String, wind_speed: int, wind_facing: String, sail_state: String, rigging_quality: int)`. Note the argument order does **not** match the JSON nesting order, and `wind_speed`/`rigging_quality` are `int` at the API even though the JSON keys are strings.

Validate after edits: `python3 .claude/skills/validate-rule-table/scripts/validate.py`. Catches typos (e.g. `"FS"` vs `"fs"`) that would silently return 0 at lookup time instead of erroring.

Other rule lookups on `DataManager`: `get_speed_change(change_type, maneuverability)`, `get_tacking_percent(maneuverability, wind_speed)`, `get_min_heading_change_movement_required(direction, ship_speed, maneuverability)`.

### Ship Definitions (`data/rules/ships.json`)

Ship types with: name, nationality, rating, class, maneuverability, speed_type, draft, freeboard, rigging_hp[], hull_hp[], crew/marine counts, guns.

### Scenarios (`data/scenarios/*.json`)

Wind conditions, map config, ship placements with position (q,r), facing, sail state, crew quality/morale.

## Conventions and Gotchas

### Hex Grid
- **Axial coordinates** (q, r) with **pointy-top** orientation
- **Direction numbering**: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
- **All ships are 1-hex.** `ShipState.get_ship_size()` is deprecated and hardcoded to return 1; use `HexGrid.axial_to_world()` for positioning. The `size == 2` branches in `ShipView` are dead code kept for possible future revival. (`HexGrid.axial_to_edge_world()` is live — `ShipIndicatorModel` uses it to compute hex-face midpoints for the selection indicators.)

### Server Authority
- All mutations guard with `if not is_server: push_error()` — never bypass this
- Controllers in `scripts/server/` are server-only; clients are read-only observers

### State History
- Indexed by turn number: `environment_history[turn]`, `ship_history[ship_id][turn]`
- Snapshots saved AFTER turn completes, before advancing

### Environment RNG
- `EnvironmentController` manages RNG seed for determinism
- Wind changes use 2d10 rolls; high rolls revert wind toward original direction

### Movement Allowance Lookup
- All keys are **strings** (including wind_speed and rigging_quality)
- Wind-facing `"L"` (luffing/into wind) is a special case that always returns 0
- Uses `assert()` for parameter validation — fails fast on bad input

### Legacy Code
- `scripts/ui/planning_panel.gd` is legacy; `planning_phase_ui.gd` is the current version
- The `size == 2` branch in `ShipView._update_position_from_state` is unused (all ships are 1-hex). Note: `HexGrid.axial_to_edge_world()` is now used by `ShipIndicatorModel` and is no longer dead (see Hex Grid note).

### SCV Audit
Run the `scv-reviewer` agent as a **final step** before reporting any planned work as complete. Do not run it after each individual task or phase — only once at the very end, after all code changes are made and tests pass. Fix any violations it finds before finishing.

### Developer UI
- Press **F12** in-game to toggle the debug inspection panel
- Shows ship state details, turn info, and environment data
