# Leeward - Naval Combat Board Game

A turn-based naval combat board game set in the Age of Sail, built with Godot 4.4.

## Phase 1 - Core Foundation (Current)

This phase establishes the foundational systems for the game:

### Completed Features

#### Core Systems
- **Hex Grid System** - Axial coordinate system with hex math utilities (`scripts/core/hex_grid.gd`)
- **Game State Manager** - Turn-based game loop with phase management (`scripts/autoload/game_state.gd`)
- **Data Manager** - JSON/CSV data loading system for rules and scenarios (`scripts/autoload/data_manager.gd`)

#### Rendering & Camera
- **Isometric Hex Map** - 30x30 hex grid with swappable water textures (`scripts/core/hex_map.gd`)
- **Isometric Camera** - Mouse wheel zoom and middle-click pan (`scripts/core/isometric_camera.gd`)

#### Ship System
- **Ship Entity** - Placeholder 3D models with full ship stats (`scripts/entities/ship.gd`)
- **Ship Selection** - Click to select and view detailed status
- Ship attributes: position, facing, speed, sail state, hull, crew, rigging

#### User Interface
- **Wind Compass** - Visual compass showing wind direction (`scripts/ui/wind_compass.gd`)
- **Game Info Panel** - Turn counter, phase indicator, wind speed (`scripts/ui/game_info_panel.gd`)
- **Ship Status Panel** - Detailed ship statistics display (`scripts/ui/ship_status_panel.gd`)
- **Planning Panel** - Plot movement and sail changes (`scripts/ui/planning_panel.gd`)

#### Game Loop (Phases)
1. **ENVIRONMENT** - Wind updates (stubbed)
2. **PLANNING** - Players plot actions (implemented)
3. **MOVEMENT_RESOLUTION** - Execute movement (stubbed)
4. **COMBAT_RESOLUTION** - Resolve combat (stubbed)
5. **DRIFT_CALCULATION** - Handle drifting ships (stubbed)
6. **STATUS_ADJUSTMENT** - Apply repairs, damage (stubbed)
7. **MORALE_CHECK** - Update crew morale (stubbed)
8. **MESSAGE_DELIVERY** - Flag signals (stubbed)
9. **POST_COMBAT** - Player actions (stubbed)
10. **END_TURN** - Victory checks (stubbed)

#### Data-Driven Design
- **Movement Allowance Table** - `data/rules/movement_allowance.json`
- **Ship Definitions** - `data/rules/ships.json`
- **Scenarios** - `data/scenarios/test_basic.json`

### Controls

- **Mouse Wheel** - Zoom in/out
- **Middle Mouse Button + Drag** - Pan camera
- **Left Click** - Select ship
- **Planning Phase** - Enter movement commands (F2 S F1 = Forward 2, Starboard turn, Forward 1)

### Project Structure

```
Leeward/
├── scripts/
│   ├── autoload/          # Singleton managers
│   │   ├── game_state.gd
│   │   └── data_manager.gd
│   ├── core/              # Core game systems
│   │   ├── hex_grid.gd
│   │   ├── hex_map.gd
│   │   ├── isometric_camera.gd
│   │   └── game_controller.gd
│   ├── entities/          # Game entities
│   │   └── ship.gd
│   └── ui/                # User interface
│       ├── wind_compass.gd
│       ├── game_info_panel.gd
│       ├── ship_status_panel.gd
│       └── planning_panel.gd
├── scenes/
│   ├── main_game.tscn     # Main game scene
│   └── ship.tscn          # Ship scene
├── data/
│   ├── rules/             # Game rules data
│   │   ├── movement_allowance.json
│   │   └── ships.json
│   └── scenarios/         # Scenario definitions
│       └── test_basic.json
├── assets/
│   ├── textures/
│   ├── models/
│   └── ui/
└── docs/                  # Game design documents
	├── 01-overview-and-design.md
	└── 02-game-rules.md
```

### Running the Game

1. Open the project in Godot 4.4
2. Press F5 to run
3. The test scenario will load with 2 ships
4. Click a ship to view its status
5. When Planning Phase starts, plot movement for your ship
6. Click "Submit Plan" to execute

### Next Steps (Phase 2+)

- Implement actual movement resolution
- Add movement validation and collision detection
- Implement combat system (gunnery, boarding)
- Add AI opponent
- Implement remaining game phases
- Add visual effects and animations
- Expand movement allowance tables
- Add more ship types and scenarios

## Documentation

See `docs/` folder for complete game design and rules documentation.
