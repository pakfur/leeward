# Leeward - Project Summary

**Last Updated:** December 3, 2025

## Overview

Leeward is a turn-based naval combat board game set in the Age of Sail, built with Godot 4.4. The game simulates realistic sailing mechanics including wind direction, sail states, and ship maneuverability based on historical naval warfare rules (inspired by Close Action tabletop game).

**Genre:** Turn-based Strategy / Naval Combat Simulation  
**Platform:** PC (Windows, macOS, Linux)  
**Engine:** Godot 4.4  
**Language:** GDScript  
**Current Phase:** Phase 1 - Core Foundation

---

## Tech Stack

### Engine & Runtime
- **Game Engine:** Godot 4.4
- **Rendering:** Forward+ renderer
- **3D Graphics:** Isometric camera view with hex-based grid
- **Physics:** Godot Physics 3D (for raycasting and collision detection)

### Languages & Scripting
- **Primary Language:** GDScript
- **Data Formats:** JSON (game rules, scenarios), CSV (data tables)
- **Shaders:** GLSL (Godot Shader Language) for water effects

### Development Tools
- **Version Control:** Git
- **IDE:** Godot Editor + external text editors (Sublime Text)
- **Asset Pipeline:** Python scripts for data conversion (csv_to_json.py)

### Key Dependencies
- **Godot MCP Plugin:** Model Context Protocol integration (addons/godot_mcp)
- **Custom Addons:** Test plugin (addons/test)

---

## Architecture

### Design Philosophy

Leeward follows a **data-driven, state-based architecture** with clear separation between:
- **State** (pure data, deterministic, serializable)
- **Controllers** (game logic, server-authoritative)
- **Views** (presentation layer, client-side rendering)

This architecture is designed to support future multiplayer functionality with server-authoritative gameplay.

### Core Architecture Patterns

#### 1. State-Controller-View Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                        GameState                             │
│                    (Autoload Singleton)                      │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  State Objects (Pure Data)                           │  │
│  │  - EnvironmentState (wind, weather, sea)             │  │
│  │  - ShipState[] (position, facing, damage, crew)      │  │
│  │  - State History (turn-by-turn snapshots)            │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Server Controllers (Game Logic)                     │  │
│  │  - TurnPhaseController (phase management)            │  │
│  │  - ShipStateController (movement, damage)            │  │
│  │  - EnvironmentController (wind, weather updates)     │  │
│  │  - CommandValidator (action validation)              │  │
│  │  - NetworkSync (state synchronization)               │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
							│
							│ State Updates
							▼
┌─────────────────────────────────────────────────────────────┐
│                     GameController                           │
│                   (Scene Controller)                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  View Objects (Presentation)                         │  │
│  │  - ShipView[] (3D models, animations)                │  │
│  │  - HexMap (terrain rendering)                        │  │
│  │  - UI Components (panels, HUD)                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

#### 2. Hex Grid System

- **Coordinate System:** Axial coordinates (q, r) for pointy-top hexagons
- **Grid Math:** HexGrid utility class handles all hex calculations
- **World Mapping:** Converts between hex coordinates and 3D world positions
- **Ship Sizes:** Supports 1-hex (corvettes) and 2-hex (frigates) ships

#### 3. Turn-Based Game Loop

The game operates in discrete phases per turn:

```
1. ENVIRONMENT       → Wind/weather updates
2. PLANNING          → Players plot actions
3. MOVEMENT_RESOLUTION → Execute movement
4. COMBAT_RESOLUTION → Resolve combat
5. DRIFT_CALCULATION → Handle drifting ships
6. STATUS_ADJUSTMENT → Apply repairs/damage
7. MORALE_CHECK      → Update crew morale
8. MESSAGE_DELIVERY  → Flag signals
9. POST_COMBAT       → Player actions
10. END_TURN         → Victory checks, advance turn
```

### Project Structure

```
Leeward/
├── scripts/
│   ├── autoload/              # Singleton managers
│   │   ├── game_state.gd      # Central game state (server-authoritative)
│   │   └── data_manager.gd    # JSON/CSV data loading
│   ├── core/                  # Core game systems
│   │   ├── hex_grid.gd        # Hex coordinate math
│   │   ├── hex_map.gd         # 3D hex map rendering
│   │   ├── isometric_camera.gd # Camera controls
│   │   ├── game_controller.gd # Main game logic
│   │   └── wave_calculator.gd # Water simulation
│   ├── state/                 # Pure data objects
│   │   ├── ship_state.gd      # Ship data (Resource)
│   │   └── environment_state.gd # Environment data (Resource)
│   ├── server/                # Server-side controllers
│   │   ├── turn_phase_controller.gd
│   │   ├── ship_state_controller.gd
│   │   ├── environment_controller.gd
│   │   ├── command_validator.gd
│   │   └── network_sync.gd
│   ├── view/                  # Presentation layer
│   │   └── ship_view.gd       # Ship 3D visualization
│   ├── ui/                    # User interface
│   │   ├── wind_compass.gd
│   │   ├── game_info_panel.gd
│   │   ├── ship_status_panel.gd
│   │   ├── planning_panel.gd
│   │   ├── minimap.gd
│   │   ├── context_panel.gd
│   │   └── developer_ui.gd
│   ├── entities/              # Legacy ship entity
│   │   └── ship.gd
│   ├── commands/              # Command pattern
│   │   ├── game_command.gd
│   │   └── move_command.gd
│   └── util/                  # Utilities
│       └── generate_compass_assets.gd
├── scenes/
│   ├── main.tscn              # Entry point
│   ├── main_game.tscn         # Main game scene
│   ├── ship.tscn              # Ship scene template
│   ├── splash_screen.tscn
│   ├── scenario_selection.tscn
│   └── ui/                    # UI scene components
│       ├── wind_compass.tscn
│       ├── minimap.tscn
│       ├── context_panel.tscn
│       └── developer_ui.tscn
├── data/
│   ├── rules/                 # Game rules data
│   │   ├── movement_allowance.json  # Movement lookup tables
│   │   └── ships.json         # Ship definitions
│   └── scenarios/             # Scenario definitions
│       └── test_basic.json
├── assets/
│   ├── textures/
│   │   ├── water/             # Water textures (normal maps, foam)
│   │   └── minimap/
│   ├── materials/
│   │   └── ocean_water.tres   # Water material
│   ├── shaders/
│   │   └── ocean_water.gdshader # Water shader
│   └── ui/
│       ├── compass/           # Compass UI assets
│       └── splash/
├── docs/                      # Design documentation
│   ├── 01-overview-and-design.md
│   ├── 02-game-rules.md
│   ├── 03-ai-system.md
│   ├── 04-ui-ux-design.md
│   ├── 05-technical-architecture.md
│   ├── 06-progression-rpg-systems.md
│   ├── 07-naval-combat-mechanics.md
│   ├── architecture_diagram.md
│   ├── compass_implementation.md
│   ├── developer_ui.md
│   └── environment_shader_integration.md
└── addons/
	├── godot_mcp/             # MCP server integration
	└── test/                  # Test plugin
```

---

## Key Systems

### 1. Hex Grid System (`scripts/core/hex_grid.gd`)

**Purpose:** Handles all hexagonal grid mathematics using axial coordinates.

**Key Features:**
- Axial coordinate system (q, r) for pointy-top hexagons
- Coordinate conversion (hex ↔ world position)
- Distance calculations
- Neighbor finding
- Line drawing (hex_line)
- Range queries (hex_range, hex_ring)
- Wind facing calculations (L/C/B/R categories)

**Coordinate System:**
```
	 NW(4)  NE(5)
		\  /
	W(3)─●─E(0)
		/  \
	 SW(2)  SE(1)
```

### 2. Game State Manager (`scripts/autoload/game_state.gd`)

**Purpose:** Central singleton managing all game state (server-authoritative).

**Responsibilities:**
- Turn and phase management
- Ship state tracking
- Environment state tracking
- State history (turn-by-turn snapshots)
- State serialization/deserialization
- Server controller initialization
- Network state synchronization

**Key Data:**
- `current_phase`: Current game phase (enum)
- `current_turn`: Turn number
- `environment`: EnvironmentState object
- `ships`: Dictionary of ShipState objects
- `environment_history`: Array of historical environment states
- `ship_history`: Dictionary of historical ship states

### 3. Data Manager (`scripts/autoload/data_manager.gd`)

**Purpose:** Loads and caches game data from JSON/CSV files.

**Responsibilities:**
- Load movement allowance tables
- Load ship definitions
- Load scenarios
- Provide data lookup functions

**Data Files:**
- `movement_allowance.json`: Movement points based on wind, sail state, rigging
- `ships.json`: Ship definitions (stats, capabilities)
- `scenarios/*.json`: Scenario configurations

### 4. Ship State (`scripts/state/ship_state.gd`)

**Purpose:** Pure data representation of a ship (no visuals).

**Key Properties:**
- Position: `hex_position` (Vector2i)
- Orientation: `facing` (0-5)
- Movement: `current_speed`, `last_speed`
- Sails: `sail_state` (FS/MS/PS/NS), `rigging_quality`, `rigging_damage`
- Hull: `hull_max_hp`, `hull_current_hp` (arrays per section)
- Crew: `crew_count`, `crew_quality`, `crew_morale`
- Actions: `plotted_actions` (movement, sail changes, combat)

**Methods:**
- `get_movement_allowance()`: Calculate MA from current state
- `serialize()` / `deserialize()`: State persistence
- `initialize_from_scenario()`: Load from scenario data

### 5. Environment State (`scripts/state/environment_state.gd`)

**Purpose:** Environmental conditions (wind, weather, sea state).

**Key Properties:**
- Wind: `wind_direction` (0-5), `wind_speed` (0-5), `wind_speed_change`
- Sea: `sea_state` (0-3)
- Weather: `visibility`, `precipitation`, `time_of_day`

**Methods:**
- `tick_environment()`: Update environment each turn
- `_update_wind_speed()`: Wind speed changes
- `_update_wind_direction()`: Wind direction shifts
- `serialize()` / `deserialize()`: State persistence

### 6. Ship View (`scripts/view/ship_view.gd`)

**Purpose:** Visual representation of a ship (3D model, animations).

**Responsibilities:**
- Render ship 3D model
- Sync visual position to state
- Handle selection highlighting
- Emit selection signals

**Key Methods:**
- `initialize()`: Set up from ShipState
- `sync_to_state()`: Update visuals from state
- `set_selected()`: Toggle selection highlight

### 7. Hex Map (`scripts/core/hex_map.gd`)

**Purpose:** Renders the 3D hex grid and water surface.

**Features:**
- 30x30 hex grid
- Swappable water textures
- Hex grid overlay (toggleable)
- Water shader integration
- Isometric projection

### 8. Isometric Camera (`scripts/core/isometric_camera.gd`)

**Purpose:** Camera controls for isometric view.

**Controls:**
- Mouse wheel: Zoom in/out
- Middle mouse + drag: Pan camera
- Keyboard: Center on ships (C key)

**Features:**
- Smooth zoom with limits
- Pan boundaries
- Auto-center on ships
- Isometric angle (45° elevation)

### 9. Turn Phase Controller (`scripts/server/turn_phase_controller.gd`)

**Purpose:** Manages turn phases and transitions (server-only).

**Responsibilities:**
- Phase state machine
- Phase advancement
- Player readiness tracking
- Turn counter

**Signals:**
- `phase_changed(new_phase)`
- `turn_changed(turn_number)`

### 10. Ship State Controller (`scripts/server/ship_state_controller.gd`)

**Purpose:** Handles ship state updates (server-only).

**Responsibilities:**
- Movement resolution
- Damage application
- Crew management
- State validation

**Key Methods:**
- `resolve_all_movement()`: Execute all ship movements
- `apply_damage()`: Apply damage to ships
- `update_crew_morale()`: Update morale

### 11. Environment Controller (`scripts/server/environment_controller.gd`)

**Purpose:** Updates environmental conditions (server-only).

**Responsibilities:**
- Wind changes
- Weather updates
- Sea state changes
- Shader synchronization

### 12. UI Components

#### Wind Compass (`scripts/ui/wind_compass.gd`)
- Visual compass showing wind direction
- Rotates to match wind
- Updates each turn

#### Game Info Panel (`scripts/ui/game_info_panel.gd`)
- Turn counter
- Phase indicator
- Wind speed display

#### Ship Status Panel (`scripts/ui/ship_status_panel.gd`)
- Detailed ship statistics
- Hull/rigging/crew status
- Movement allowance

#### Planning Panel (`scripts/ui/planning_panel.gd`)
- Plot movement commands
- Change sail state
- Submit action plans

#### Minimap (`scripts/ui/minimap.gd`)
- Top-down tactical view
- Ship positions
- Wind indicator

#### Developer UI (`scripts/ui/developer_ui.gd`)
- Debug information
- State inspection
- Manual phase control
- Toggle with F12

---

## Data-Driven Design

### Movement Allowance System

Movement is determined by a lookup table (`movement_allowance.json`) with ~1000+ entries:

**Lookup Keys:**
- `speed_type`: Ship speed classification (F/F, C/F, S/S, etc.)
- `wind_speed`: 0-5 (calm to gale)
- `wind_facing`: L/C/B/R (luffing/close hauled/broad reach/running)
- `sail_state`: FS/MS/PS/NS (full/main/plain/no sails)
- `rigging_quality`: 0-4 (damaged to pristine)

**Output:**
- `ma`: Movement allowance (hexes per turn)

### Ship Definitions

Ships are defined in `ships.json`:

```json
{
  "frigate_38": {
	"name": "38-gun Frigate",
	"nationality": "British",
	"rating": 38,
	"class": 4,
	"maneuverability": "B",
	"speed_type": "F/F",
	"type": "Frigate",
	"rigging_sections": 4,
	"rigging_quality": 4,
	"hull_sections": 3,
	"hull_max_hp": [8, 8, 8],
	"crew_count": 280
  }
}
```

### Scenarios

Scenarios define initial game setup:

```json
{
  "name": "Test Scenario",
  "wind_direction": 0,
  "wind_speed": 2,
  "sea_state": 1,
  "ships": [
	{
	  "id": "player_ship",
	  "player_id": 0,
	  "ship_type": "frigate_38",
	  "position": {"q": 5, "r": 15},
	  "facing": 0,
	  "sail_state": "MS"
	}
  ]
}
```

---

## Game Flow

### Startup Sequence

1. **Engine Init** → Godot loads autoload singletons (GameState, DataManager)
2. **Main Menu** → Player selects scenario
3. **Scene Load** → `main_game.tscn` loads
4. **GameController._ready()**:
   - Load data files (movement tables, ship definitions)
   - Load selected scenario
   - Initialize environment state
   - Spawn ships (create ShipState + ShipView)
   - Connect signals
   - Start game via `GameState.start_new_game()`

### Turn Execution

1. **ENVIRONMENT Phase**
   - EnvironmentController updates wind/weather
   - State history snapshot saved
   
2. **PLANNING Phase**
   - Planning UI shown to players
   - Players plot movement commands
   - AI plans actions
   - Players submit plans
   
3. **MOVEMENT_RESOLUTION Phase**
   - ShipStateController resolves all movement
   - Collision detection
   - Position updates
   - Views sync to state
   
4. **COMBAT_RESOLUTION Phase** (stubbed)
   - Gunnery resolution
   - Damage application
   - Boarding actions
   
5. **Remaining Phases** (stubbed)
   - Drift, status, morale, messages, post-combat
   
6. **END_TURN Phase**
   - Victory condition checks
   - Turn counter increment
   - Return to ENVIRONMENT phase

### Player Interaction

**Ship Selection:**
1. Player clicks on ship (raycast)
2. GameController finds ShipView
3. ShipView emits `selected` signal
4. GameController updates selection state
5. Ship Status Panel displays ship info

**Movement Planning:**
1. Planning Phase begins
2. Planning Panel shows for player ships
3. Player enters commands (F2 S F1 = Forward 2, Starboard, Forward 1)
4. Commands stored in ShipState.plotted_actions
5. Player clicks "Submit Plan"
6. Phase advances to Movement Resolution

---

## Rendering & Graphics

### 3D Rendering

- **Renderer:** Forward+ (Godot 4.4)
- **Camera:** Isometric perspective (45° elevation)
- **Lighting:** Directional light (sun)
- **Shadows:** Enabled for ships

### Water Shader

Custom ocean shader (`ocean_water.gdshader`):
- Normal mapping (2 layers)
- Foam effects
- Wave animation
- Caustics
- Reflections
- Configurable via material parameters

### Ship Models

Currently using placeholder 3D models:
- Capsule shapes for ship hulls
- Color-coded by player (blue/red)
- Selection highlighting (yellow outline)

### UI Rendering

- **Canvas Layer:** 2D UI overlay
- **Themes:** Custom UI theme
- **Fonts:** Default Godot fonts
- **Icons:** Custom compass assets

---

## Multiplayer Architecture (Planned)

### Server-Authoritative Design

The architecture is designed for future multiplayer:

**Server:**
- Runs all controllers (TurnPhaseController, ShipStateController, etc.)
- Maintains authoritative game state
- Validates all player actions
- Broadcasts state updates to clients

**Client:**
- Receives state updates from server
- Renders views based on state
- Sends player input to server
- Read-only access to GameState

**Network Sync:**
- Full state synchronization each turn
- Delta updates for efficiency (planned)
- Replay system for debugging

### Current State

- Single-player only (server mode always enabled)
- Network infrastructure stubbed
- State serialization/deserialization implemented
- Ready for multiplayer integration

---

## Development Status

### Phase 1 - Core Foundation (Current)

**Completed:**
- ✅ Hex grid system with axial coordinates
- ✅ Game state management (turn-based loop)
- ✅ Data-driven design (JSON loading)
- ✅ Isometric hex map rendering
- ✅ Camera controls (zoom, pan)
- ✅ Ship entities with full stats
- ✅ Ship selection and status display
- ✅ Wind compass UI
- ✅ Planning panel for movement
- ✅ State history tracking
- ✅ Water shader with effects
- ✅ Developer UI for debugging

**In Progress:**
- 🔄 Movement resolution (basic implementation)
- 🔄 Movement validation

**Not Started:**
- ❌ Combat system (gunnery, boarding)
- ❌ AI opponent
- ❌ Remaining game phases (drift, morale, etc.)
- ❌ Visual effects and animations
- ❌ Sound effects and music
- ❌ Save/load system
- ❌ Multiplayer networking

### Phase 2+ (Planned)

- Movement validation and collision detection
- Combat resolution (gunnery tables, damage)
- AI decision-making
- Visual effects (cannon fire, smoke, damage)
- Sound design
- Additional ship types
- More scenarios
- Campaign mode
- Multiplayer support

---

## Controls

### Mouse
- **Left Click:** Select ship
- **Middle Mouse + Drag:** Pan camera
- **Mouse Wheel:** Zoom in/out

### Keyboard
- **C:** Center camera on all ships
- **F12:** Toggle developer UI

### Planning Phase
- **Text Input:** Enter movement commands
  - `F#`: Forward # hexes
  - `S`: Starboard turn (60° right)
  - `P`: Port turn (60° left)
  - Example: `F2 S F1` = Forward 2, turn right, forward 1

---

## Performance Considerations

### Optimization Strategies

1. **State Separation:** Pure data objects (Resource) are lightweight
2. **View Pooling:** Ship views can be pooled/reused
3. **Hex Grid Caching:** Pre-calculated hex positions
4. **Shader Optimization:** Water shader uses efficient techniques
5. **LOD System:** Planned for larger battles

### Current Performance

- **Grid Size:** 30x30 hexes (900 hexes)
- **Ship Count:** Tested with 2-10 ships
- **Frame Rate:** 60 FPS on modern hardware
- **Memory:** ~200MB RAM usage

---

## Testing & Debugging

### Developer Tools

**Developer UI (F12):**
- State inspector
- Manual phase control
- Ship state viewer
- Environment controls
- Performance metrics

**Debug Features:**
- Console logging for all major events
- State history inspection
- Movement validation feedback
- Error reporting

### Test Scenarios

- `test_basic.json`: Two ships facing each other
- Additional scenarios planned

---

## Future Roadmap

### Short Term (Phase 2)
1. Complete movement resolution
2. Implement combat system
3. Add basic AI
4. Visual effects for combat
5. Sound effects

### Medium Term (Phase 3)
1. Additional ship types (ships of the line, brigs)
2. More scenarios
3. Campaign mode
4. Save/load system
5. Improved graphics (ship models, water)

### Long Term (Phase 4+)
1. Multiplayer networking
2. Scenario editor
3. Modding support
4. Mobile port
5. Steam release

---

## Known Issues & Limitations

### Current Limitations

1. **Movement Resolution:** Basic implementation, needs validation
2. **Combat System:** Not implemented
3. **AI:** Not implemented
4. **Multiplayer:** Infrastructure only, not functional
5. **Ship Models:** Placeholder capsules
6. **Sound:** No audio implementation
7. **Save/Load:** Not implemented

### Known Bugs

- None critical at this stage

---

## Contributing

### Code Style

- **Language:** GDScript
- **Naming:** snake_case for variables/functions, PascalCase for classes
- **Comments:** Doc comments for public APIs
- **Signals:** Document signal parameters
- **Type Hints:** Use static typing where possible

### Architecture Guidelines

1. **Separation of Concerns:** Keep state, logic, and views separate
2. **Server Authority:** All game logic in server controllers
3. **Data-Driven:** Use JSON for configuration
4. **Deterministic:** State updates must be reproducible
5. **Serializable:** All state must be serializable

---

## License

[License information not specified in project]

---

## Contact & Resources

**Project Location:** `/Users/jkline/gws/pakfur/leeward`

**Documentation:**
- Design docs in `docs/` folder
- Close Action rules reference in `docs/Close-Action-Rules-v6-1.pdf`

**External References:**
- Godot 4.4 Documentation: https://docs.godotengine.org/
- Close Action (tabletop game): Historical naval combat rules

---

## Appendix: Key Files Reference

### Critical Files

| File | Purpose |
|------|---------|
| `project.godot` | Godot project configuration |
| `scripts/autoload/game_state.gd` | Central game state singleton |
| `scripts/autoload/data_manager.gd` | Data loading singleton |
| `scripts/core/hex_grid.gd` | Hex math utilities |
| `scripts/core/game_controller.gd` | Main game logic |
| `scripts/state/ship_state.gd` | Ship data structure |
| `scripts/state/environment_state.gd` | Environment data structure |
| `data/rules/movement_allowance.json` | Movement lookup table |
| `data/rules/ships.json` | Ship definitions |
| `scenes/main_game.tscn` | Main game scene |

### Configuration Files

| File | Purpose |
|------|---------|
| `.gitignore` | Git ignore rules |
| `.gitattributes` | Git LFS configuration |
| `.editorconfig` | Editor settings |
| `csv_to_json.py` | Data conversion utility |

---

**End of Project Summary**
