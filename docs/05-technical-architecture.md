# Leeward - Technical Architecture

## Project Structure

### Directory Organization
```
Leeward/
├── scenes/
│   ├── main/
│   │   ├── main_menu.tscn
│   │   └── game_board.tscn
│   ├── ships/
│   │   ├── base_ship.tscn
│   │   └── ship_types/
│   ├── ui/
│   │   ├── hud/
│   │   └── menus/
│   └── effects/
├── scripts/
│   ├── core/
│   │   ├── game_manager.gd
│   │   └── turn_manager.gd
│   ├── ships/
│   ├── ai/
│   ├── ui/
│   └── utils/
├── resources/
│   ├── ships/
│   ├── weapons/
│   └── upgrades/
├── assets/
│   ├── models/
│   ├── textures/
│   ├── audio/
│   └── fonts/
└── data/
	├── ships.json
	├── weapons.json
	└── scenarios.json
```

## Core Systems

### Game Manager
**Responsibilities:**
- Game state management
- Scene transitions
- Save/load system
- Global settings

**Key Components:**
```gdscript
- GameManager (Singleton)
- SaveManager
- SettingsManager
- SceneManager
```

### Turn System
**Components:**
- TurnManager
- PhaseController
- ActionQueue
- TurnValidator

**Turn Flow:**
1. Planning Phase
2. Movement Resolution
3. Combat Resolution
4. Maintenance Phase

### Board System
**Grid Implementation:**
- GridManager
- TileSystem
- PathfindingSystem
- TerrainManager

**Coordinate System:**
[Hex/Square grid implementation details]

## Ship Architecture

### Base Ship Class
```gdscript
class_name Ship
extends Node3D

# Core properties
var hull_points: int
var max_hull_points: int
var speed: int
var maneuverability: int

# Components
var movement_component: ShipMovement
var combat_component: ShipCombat
var ai_component: ShipAI
```

### Ship Components
- **Movement:** Handles pathfinding and movement
- **Combat:** Manages weapons and damage
- **Inventory:** Tracks resources and cargo
- **Crew:** Manages crew numbers and morale
- **Visual:** Controls model and effects

## Combat System

### Damage Calculation
```gdscript
func calculate_damage(attacker: Ship, target: Ship, weapon: Weapon) -> int:
	# Base damage
	# Range modifier
	# Angle modifier
	# Critical hit chance
	# Armor reduction
	return final_damage
```

### Combat Resolution
- DiceRoller class
- DamageResolver
- CriticalHitSystem
- BoardingResolver

## AI Architecture

### AI Framework
```
AIController
├── DecisionTree
├── BehaviorTree
├── UtilitySystem
└── Pathfinding
```

### AI Components
- StateEvaluator
- ActionPlanner
- TacticalAnalyzer
- TargetSelector

## Resource System

### Resource Types
```gdscript
class_name GameResource
extends Resource

@export var resource_name: String
@export var icon: Texture2D
@export var base_value: int
```

### Ship Resources (.tres files)
- ShipResource
- WeaponResource
- UpgradeResource
- CrewResource

## Save System

### Save Data Structure
```gdscript
var save_data = {
	"version": "1.0",
	"timestamp": OS.get_unix_time(),
	"game_state": {
		"turn": current_turn,
		"phase": current_phase
	},
	"ships": [],
	"resources": {},
	"progression": {}
}
```

### Persistence
- JSON for save files
- Binary for replay data
- Cloud save integration

## Networking (Multiplayer)

### Architecture
- Peer-to-peer or client-server
- Turn synchronization
- State validation
- Lag compensation

### Network Components
- NetworkManager
- TurnSynchronizer
- StateValidator
- ReplaySystem

## Performance Optimization

### Object Pooling
- Projectile pool
- Effect pool
- UI element pool

### LOD System
- Ship detail levels
- Terrain detail
- Effect quality

### Culling
- Frustum culling
- Occlusion culling
- Distance culling

## Data Management

### Data Files
**JSON Schemas:**
- Ships data
- Weapons data
- Scenarios data
- Localization data

### Data Loading
```gdscript
class_name DataManager
extends Node

func load_ship_data(path: String) -> Array:
	# Load and parse JSON
	# Validate schema
	# Create resources
	return ships
```

## Audio System

### Audio Manager
- Music controller
- SFX controller
- Ambient controller
- Voice controller

### Audio Buses
- Master
- Music
- SFX
- Voice
- Ambient

## Input System

### Input Mapping
```gdscript
# Project Settings Input Map
- move_camera
- select_ship
- confirm_action
- cancel_action
- zoom_in/out
```

### Input Handler
- MouseController
- KeyboardController
- TouchController (mobile)
- GamepadController

## Scene Management

### Scene Structure
```
MainMenu
├── MenuUI
└── Background

GameBoard
├── Board
├── Ships
├── Effects
└── UI
	├── HUD
	└── Dialogs
```

### Scene Transitions
- FadeTransition
- LoadingScreen
- AsyncLoading

## Testing Framework

### Unit Tests
- Test ship movement
- Test combat calculations
- Test AI decisions
- Test save/load

### Integration Tests
- Full turn execution
- Multiplayer sync
- Performance benchmarks

## Build Configuration

### Export Settings
**Windows:**
- Architecture: x86_64
- Renderer: Forward+

**Linux:**
- Architecture: x86_64
- Renderer: Forward+

**Mac:**
- Architecture: Universal
- Code signing required

### Build Pipeline
1. Run tests
2. Update version
3. Build for platforms
4. Package installers

## Debug Systems

### Debug Menu
- Ship stats overlay
- AI decision visualization
- Performance profiler
- Network debugger

### Logging System
```gdscript
enum LogLevel {
	DEBUG,
	INFO,
	WARNING,
	ERROR
}

func log_message(level: LogLevel, message: String):
	# Timestamp
	# Format
	# Output to console/file
```

## Dependencies

### Godot Addons
- [List any addons used]

### External Tools
- [Asset pipeline tools]
- [Build tools]

## Version Control

### Git Strategy
- Branch structure
- Commit conventions
- Asset handling (.gitattributes)
