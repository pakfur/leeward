# CLAUDE.md

Guidance for Claude Code working on the Leeward project.

## Project Overview

Leeward is a Godot 4.4 naval sailing game (Age of Sail) using the Forward Plus renderer. It's a turn-based tactical game where players command ships on a hex grid, plotting movement and combat across a 10-phase turn cycle. Architecture is server-authoritative with a State-Controller-View pattern.

## Commands

```bash
godot --editor                    # Open in Godot Editor
godot                             # Run project (starts at main.tscn → splash screen)
godot res://scenes/main_game.tscn # Run directly into gameplay
godot --verbose                   # Run with verbose output
```

No automated test framework. Manual testing via scenarios and the Developer UI (F12 in-game).

## Project Structure

```
scripts/
  autoload/       # Singletons: GameState, DataManager
  core/           # Game controller, hex grid, hex map, camera, wave calc
  state/          # Pure data objects: ShipState, ShipDefinition, EnvironmentState
  server/         # Server-authoritative controllers (mutations, validation, phases)
  view/           # 3D presentation (ShipView)
  ui/             # All UI scripts
  commands/       # Command pattern (GameCommand, MoveCommand)
  entities/       # Legacy Ship entity (being replaced by ShipState+ShipView)
scenes/
  main.tscn       # Entry point (scene navigation controller)
  splash_screen.tscn → scenario_selection.tscn → main_game.tscn
  ui/             # UI subscenes (planning, minimap, compass, dev UI)
  ship.tscn       # Ship prefab
data/
  rules/          # movement_allowance.json, ships.json
  scenarios/      # Scenario definitions (test_basic.json)
docs/             # Design docs, game rules, architecture diagrams
assets/           # Models, textures, shaders, UI art
addons/           # godot_mcp (MCP server addon), test addon
```

## Architecture

### State-Controller-View (SCV)

- **State layer** (`scripts/state/`): Pure data Resources. `ShipState`, `ShipDefinition`, `EnvironmentState`. Serializable, deterministic. No logic.
- **Controller layer** (`scripts/server/`): Server-authoritative game logic. All state mutations happen here. Controllers check `is_server` before mutating. Clients are read-only.
- **View layer** (`scripts/view/`, `scripts/ui/`): Presentation only. Reads state, renders visuals. Never mutates game state.

### Autoload Singletons

- **GameState** (`scripts/autoload/game_state.gd`): Central state container. Holds all ships, environment, turn/phase, state history. Creates and owns all server controllers in `_ready()`.
- **DataManager** (`scripts/autoload/data_manager.gd`): Loads and caches JSON data (movement tables, ship definitions, scenarios). Provides lookup methods.

### Turn Phase Cycle (10 phases)

SETUP → ENVIRONMENT → PLANNING → MOVEMENT_RESOLUTION → COMBAT_RESOLUTION → DRIFT_CALCULATION → STATUS_ADJUSTMENT → MORALE_CHECK → MESSAGE_DELIVERY → POST_COMBAT → END_TURN → (back to ENVIRONMENT)

Managed by `TurnPhaseController`. Currently ENVIRONMENT, PLANNING, and MOVEMENT_RESOLUTION are implemented; others are stubbed.

### Movement Plotting Protocol

Session-based async system in `MovementPlottingController`/`MovementPlottingSession`:
- Requests: START_PLOTTING, SELECT_HEX, UNDO, SUBMIT_MOVEMENT, CANCEL_PLOTTING
- Typed response classes in `movement_types.gd` (PlottingStartedResponse, HexSelectedResponse, etc.)
- Sessions auto-expire after 5 minutes; version number increments on each change for conflict resolution
- Valid moves stored in `ShipState.plotted_actions`

## Key Data Formats

### Movement Allowance Table (`data/rules/movement_allowance.json`)

5-level nested lookup: `speed_type → wind_facing → wind_speed → rigging_quality → sail_state → MA`

- Speed types: `L/F`, `L/S`, `L/VS`, `F/F`, `F/S`, `F/VS`, `C-F`, `C/S`, `C/VS`
- Wind facings: `C` (close-hauled), `B` (broad reach), `R` (reach), `L` (luffing — always returns 0)
- Wind speed: `1`–`4` (string keys)
- Rigging quality: `1`–`4` (calculated from HP percentage)
- Sail states: `fs` (fighting), `ms` (maneuvering), `ps` (plain), `ns` (no sail)

Access via `DataManager.get_movement_allowance(speed_type, wind_facing, wind_speed, rigging_quality, sail_state)`.

### Ship Definitions (`data/rules/ships.json`)

Ship types with: name, nationality, rating, class, maneuverability, speed_type, draft, freeboard, rigging_hp[], hull_hp[], crew/marine counts, guns.

### Scenarios (`data/scenarios/*.json`)

Wind conditions, map config, ship placements with position (q,r), facing, sail state, crew quality/morale.

## Conventions and Gotchas

### Hex Grid
- **Axial coordinates** (q, r) with **pointy-top** orientation
- **Direction numbering**: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
- Ship size matters: 1-hex ships (corvettes) center in a hex; 2-hex ships (frigates, SOL) position on the edge between two hexes based on facing — use `axial_to_edge_world()`

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
- `scripts/entities/ship.gd` is the old Ship entity, being replaced by ShipState + ShipView split
- `scripts/ui/planning_panel.gd` is legacy; `planning_phase_ui.gd` is the current version

### Developer UI
- Press **F12** in-game to toggle the debug inspection panel
- Shows ship state details, turn info, and environment data
