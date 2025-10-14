# Developer UI

## Overview

The Developer UI is a floating, draggable window that provides real-time access to game state for testing and debugging. It allows developers to:
- View and edit all environment state (@export variables)
- View and edit ship state for all ships
- Advance phases and turns manually
- Reset to initial scenario state
- View a console log of all actions

## Usage

### Opening the Developer UI

Press **F12** to toggle the Developer UI on/off.

### Window Controls

- **Dragging**: Click and drag the title bar to reposition the window
- **Close**: Press F12 again or click the X button

## Tabs

### Environment Tab

Displays all @export fields from `EnvironmentState`:
- `wind_direction` (0-5): Current wind hex direction (0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE)
- `wind_speed` (0-5): Wind speed (0=calm, 5=gale)
- `wind_speed_change`: "steady" or "gusty"
- `environment`: "oceanic" or "coastal"
- `wind_direction_change`: "none", "veering", or "backing"
- `sea_state` (0-3): Sea conditions (0=calm, 3=storm)
- `visibility`: "clear", "hazy", "fog", or "storm"
- `time_of_day`: "dawn", "day", "dusk", or "night"
- `precipitation`: "none", "rain", "snow", or "storm"

**Behavior:**
- Changes are **immediate** to the state
- **Visual updates** (shader) apply at the beginning of the next turn
- Example: Change wind_speed to 5, advance turn, see storm waves

### Ships Tab

Select a ship from the dropdown, then view/edit:
- `ship_id` (read-only): Unique ship identifier
- `ship_name` (read-only): Display name
- `facing` (0-5): Current hex direction ship is facing
- `current_speed` (0-10): Current movement speed
- `last_speed` (0-10): Previous turn's speed
- `sail_state`: "FS", "MS", "PS", or "NS" (Full/Maneuvering/Plain/No Sail)

**Behavior:**
- Changes are **immediate** to the state
- Ship views update on next render frame
- Example: Change facing to 3, ship immediately rotates west

### Controls Tab

#### Turn & Phase Display
- **Turn**: Shows current turn number
- **Phase**: Shows current game phase (SETUP, ENVIRONMENT, PLANNING, etc.)

#### Control Buttons
- **Advance Phase**: Step through phases one at a time
  - ENVIRONMENT → PLANNING → MOVEMENT_RESOLUTION → etc.
  - Useful for testing individual phase logic

- **Advance Turn**: Skip to the next turn
  - Cycles through all phases automatically
  - Stops at the next turn's ENVIRONMENT phase
  - Useful for testing environment changes

- **Reset to Initial State**: Reload the original scenario
  - Resets turn to 1
  - Resets all environment and ship state to scenario defaults
  - Rebuilds all UI tabs
  - Useful for repeating tests

#### Console Output
A scrolling log of all Developer UI actions:
- Field changes with timestamps
- Phase/turn advances
- Reset operations
- Errors and warnings

Messages are also printed to the Godot console.

## Implementation Details

### Files

- **Script**: `scripts/ui/developer_ui.gd`
- **Scene**: `scenes/ui/developer_ui.tscn`
- **Integration**: `scenes/main_game.tscn` (DeveloperUI node)
- **Controller**: `scripts/core/game_controller.gd` (F12 toggle)

### Architecture

The Developer UI directly modifies state objects:
- **EnvironmentState**: `GameState.environment`
- **ShipState**: Individual ship objects from `GameState.ships`

Changes are **immediate** but visual effects depend on the game's update cycle:
- Environment visual changes (shader): Applied in ENVIRONMENT phase
- Ship visual changes: Applied on next frame or phase transition

### Server-Authoritative Mode

The Developer UI operates in "server-authoritative mode" by:
1. Directly modifying state on the "server" (GameState)
2. Bypassing validation (no CommandValidator checks)
3. Allowing impossible states (e.g., wind_speed=5 with wind_direction_change="backing")

This is intentional for testing edge cases and specific scenarios.

## Workflow Examples

### Testing Wind Changes

1. Open Developer UI (F12)
2. Go to **Environment** tab
3. Change `wind_direction` to 3 (West)
4. Change `wind_speed` to 4 (Strong)
5. Go to **Controls** tab
6. Click **Advance Turn**
7. Observe:
   - Water shader updates with westward waves
   - Compass wind indicator points west
   - Waves are taller and faster

### Testing Ship Movement

1. Open Developer UI (F12)
2. Go to **Ships** tab
3. Select a ship from dropdown
4. Change `facing` to 1 (Southeast)
5. Change `sail_state` to "FS" (Full Sail)
6. Observe ship rotates immediately
7. Go to **Controls** tab
8. Advance to PLANNING phase
9. Plot movement commands
10. Advance turn to see movement execute

### Testing Multi-Turn Scenarios

1. Open Developer UI (F12)
2. Set environment conditions:
   - `wind_direction_change` = "veering"
   - `wind_speed_change` = "steady"
3. Click **Advance Turn** multiple times
4. Watch wind direction rotate clockwise each turn
5. Observe waves shift direction gradually

### Resetting After Tests

1. Open Developer UI (F12)
2. Go to **Controls** tab
3. Click **Reset to Initial State**
4. All values return to scenario defaults
5. Turn resets to 1
6. Environment and ships restored

## Dynamic Field Generation

The Developer UI automatically generates input fields based on property types:

### Integer Fields
- Rendered as **SpinBox** (numeric up/down)
- Min/max values enforced
- Example: `wind_direction` (0-5)

### String Fields (with options)
- Rendered as **OptionButton** (dropdown)
- Limited to predefined values
- Example: `sail_state` ["FS", "MS", "PS", "NS"]

### Read-Only Fields
- Rendered as **Label** (gray text)
- No editing allowed
- Example: `ship_id`, `ship_name`

## Console Logging

All actions are logged with timestamps:
```
[14:23:45] Developer UI initialized. Press F12 to toggle.
[14:24:10] Environment.wind_speed = 4 (visual update on next turn)
[14:24:15] Advanced phase
[14:24:15] Phase changed to: PLANNING
[14:24:20] Ship ship_001.facing = 3
[14:24:25] Advanced to turn 2
```

The console auto-scrolls to show the latest messages.

## Troubleshooting

### Fields Not Updating
- Ensure game is running (not paused)
- Check console for error messages
- Try clicking **Refresh All** (close/reopen F12)

### Visual Changes Not Visible
- Environment changes: Wait for next turn's ENVIRONMENT phase
- Ship changes: Should be immediate (check console for errors)

### Window Not Draggable
- Click directly on the title bar area (top ~30 pixels)
- Don't click on tabs or controls

### F12 Not Working
- Check if another UI element has focus
- Click on the game viewport first
- Check Godot console for input handling errors

## Best Practices

### Testing Workflow
1. Set desired conditions in Environment/Ships tabs
2. Use **Advance Phase** to step through logic carefully
3. Use **Advance Turn** to test multi-turn behavior
4. Use **Reset** between test runs for consistency

### Console Usage
- Monitor console output to verify changes
- Look for error messages before assuming bugs
- Clear console (close/reopen) for fresh test runs

### State Validation
- Developer UI bypasses validation - be careful!
- Invalid states (e.g., facing=10) will cause errors
- Use Reset to recover from broken states

## Limitations

### What It Doesn't Do
- **Network sync**: Changes are local, not broadcast to clients
- **Validation**: No CommandValidator or rule enforcement
- **Undo**: No undo functionality (use Reset instead)
- **Save/Load**: Custom state presets not yet implemented
- **Performance profiling**: No built-in profiler

### Future Enhancements
- Save/load custom state presets
- Undo/redo functionality
- Network sync toggle
- Performance metrics
- Ship spawning/deletion
- Scenario editor integration

## Keyboard Shortcuts

- **F12**: Toggle Developer UI
- **C**: Center camera on all ships (game controller)

## Related Documentation

- [Environment-Shader Integration](environment_shader_integration.md) - How environment affects water shader
- [Compass Implementation](compass_implementation.md) - Wind direction indicator
- [Architecture Diagram](architecture_diagram.md) - Overall system design
