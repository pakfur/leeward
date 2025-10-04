# Quick Start Guide

## Initial Setup

1. **Open Project in Godot**
   ```bash
   cd /Users/jk/gws/Leeward
   godot --editor
   ```

2. **Generate Water Texture** (Optional - will use default blue color if skipped)
   - In Godot Editor: File > Run
   - Select `scripts/utils/create_water_texture.gd`
   - This creates `assets/textures/water_default.png`

3. **Run the Game**
   - Press F5 or click the Play button
   - The test scenario will load automatically

## Testing the Game

### What You Should See
- A 30x30 hex grid with ocean tiles
- Two ships: a British frigate (left) and a corvette (right)
- Wind compass in the top-right showing wind direction
- Game info panel in the bottom-left showing turn and phase
- Console output showing phase transitions

### Basic Interactions

**Camera Controls:**
- Scroll wheel: Zoom in/out
- Middle mouse + drag: Pan camera

**Ship Selection:**
- Left-click on a ship to select it
- Ship status panel appears on the right
- Yellow selection ring appears around the ship

**Planning Phase:**
- When "Phase: PLANNING" appears, a dialog opens
- Select your ship from the dropdown
- Enter movement commands in the text field:
  - `F2` - Move forward 2 hexes
  - `S` - Turn starboard (right)
  - `P` - Turn port (left)
  - Example: `F2 S F1` = Forward 2, turn right, forward 1
- Change sail state if desired
- Click "Submit Plan"
- The phase will advance automatically

### Understanding the Display

**Wind Compass:**
- Shows wind direction as one of 6 hex faces
- E = East, SE = Southeast, etc.
- Yellow arrow points in wind direction

**Game Info Panel:**
- Turn: Current turn number
- Phase: Current game phase
- Wind: Wind speed (Calm, Light, Moderate, Strong, Gale, Storm)

**Ship Status Panel:**
- Name and type
- Position (hex coordinates)
- Facing direction
- Current speed
- Sail state (FS/MS/PS/NS)
- Hull integrity (3 sections)
- Crew count and quality
- Morale level
- Rigging condition
- Movement Allowance for current turn

## Game Loop Flow

1. **ENVIRONMENT** - Wind updates (auto)
2. **PLANNING** - Plot actions for your ships (manual)
3. **MOVEMENT_RESOLUTION** - Ships move (auto, currently stubbed)
4. **COMBAT_RESOLUTION** - Combat resolved (auto, currently stubbed)
5. **DRIFT_CALCULATION** - Drift calculated (auto, currently stubbed)
6. **STATUS_ADJUSTMENT** - Status updated (auto, currently stubbed)
7. **MORALE_CHECK** - Morale checked (auto, currently stubbed)
8. **MESSAGE_DELIVERY** - Messages delivered (auto, currently stubbed)
9. **POST_COMBAT** - Final actions (auto-advances after 2s)
10. **END_TURN** - Turn ends, new turn begins

## Troubleshooting

**Water texture is missing:**
- The hex map will use a default blue color
- Run `scripts/utils/create_water_texture.gd` to generate a texture
- Or provide your own PNG at `assets/textures/water_default.png`

**Ships not visible:**
- Check that the scenario loaded (console should show "Spawned ship...")
- Try zooming out with the mouse wheel

**Planning panel doesn't appear:**
- Check console for "Phase: PLANNING" message
- The panel only appears during the PLANNING phase

**Movement doesn't execute:**
- Movement resolution is currently stubbed (Phase 1)
- Ships will remain in their starting positions
- This will be implemented in Phase 2

## Console Output

The game provides extensive console logging:
- Phase transitions
- Ship spawning
- Movement plotting
- Data loading
- Error messages

Check the console (bottom panel in Godot) for debugging information.

## Modifying the Test Scenario

Edit `data/scenarios/test_basic.json` to:
- Change ship starting positions
- Modify wind direction and speed
- Adjust ship configurations

Edit `data/rules/ships.json` to:
- Add new ship types
- Modify ship statistics

Edit `data/rules/movement_allowance.json` to:
- Adjust movement allowance values
- Add entries for different conditions

## Next Development Steps

For Phase 2, you'll want to implement:
1. Actual movement resolution in `game_controller.gd:_resolve_movement()`
2. Movement validation and collision detection
3. Ship rotation and positioning updates
4. Visual feedback for movement execution
5. AI opponent planning
6. Combat system basics
