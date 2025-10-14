# Compass Implementation Guide

## Overview
The compass UI has been updated to use an asset-based approach with real-time camera tracking. The compass now includes:
- A static compass base with cardinal direction markings
- A north needle that always points north (compensates for camera rotation)
- A wind direction icon that shows the current wind direction relative to north (server-authoritative)

## Setup Instructions

### 1. Generate Placeholder Assets

First, you need to generate the placeholder compass images:

1. Open the Godot Editor
2. Open the scene: `res://scenes/util/compass_asset_generator.tscn`
3. Run the scene (F6 or click the "Play Scene" button)
4. Check the console output - you should see:
   ```
   Generating compass placeholder assets...
   ✓ Generated compass_base.png
   ✓ Generated north_needle.png
   ✓ Generated wind_icon.png
   Compass assets generated in: res://assets/ui/compass/
   ```
5. The assets will be created in `assets/ui/compass/`

**Note:** You can delete the generator scene and script after running it once, or keep it for regenerating assets.

### 2. Replace with Custom Assets (Optional)

If you want to use custom-designed compass graphics instead of the placeholders:

1. Create three PNG images with transparency:
   - `compass_base.png` - Background circle with cardinal markings (256x256 recommended)
   - `north_needle.png` - Arrow/needle pointing up (north) (256x256 recommended)
   - `wind_icon.png` - Wind indicator icon pointing up (256x256 recommended)

2. All images should be designed pointing "up" (0 degrees) as they will be rotated programmatically

3. Save them to: `assets/ui/compass/`

4. Restart the editor or reimport the assets

### 3. Test the Implementation

Run the main game scene and test the compass:

**North Needle Test:**
1. Right-click and drag to rotate the camera around the scene
2. The red north needle should always point in the same world direction (north) regardless of camera rotation

**Wind Direction Test:**
1. The yellow wind icon should show the current wind direction relative to north
2. It should also compensate for camera rotation, staying fixed relative to the world
3. Wind direction is server-authoritative and updates each turn via `GameState.wind_direction`

**Camera Controls (for testing):**
- Right mouse drag: Rotate camera horizontally
- Mouse wheel: Zoom in/out
- Left mouse drag: Pan camera
- Trackpad: Two-finger pinch to zoom, two-finger scroll to pan

## Implementation Details

### File Structure
```
scripts/ui/wind_compass.gd          - Main compass logic
scenes/ui/wind_compass.tscn         - Compass scene with layered TextureRects
scenes/main_game.tscn               - References compass scene, connects to camera
assets/ui/compass/                  - Compass image assets
  ├── compass_base.png
  ├── north_needle.png
  └── wind_icon.png
```

### How It Works

1. **Camera Tracking** (`wind_compass.gd:35-39`)
   - The compass reads `camera_rotation_y` from the IsometricCamera every frame
   - This value represents the horizontal rotation of the camera around the scene

2. **North Needle Rotation** (`wind_compass.gd:62-63`)
   - Rotates opposite to the camera rotation to stay fixed in world space
   - Formula: `needle.rotation = -camera_rotation_y`

3. **Wind Direction Rotation** (`wind_compass.gd:66-78`)
   - Converts hex direction (0-5) to world angle
   - Adjusts for coordinate system (E-based to N-based)
   - Compensates for camera rotation
   - Formula: `wind_icon.rotation = (wind_direction * 60° - 90°) - camera_rotation_y`

4. **Server-Authoritative Updates** (`wind_compass.gd:95-97`)
   - Wind direction comes from `GameState.wind_direction`
   - Updates when `GameState.phase_changed` signal fires
   - Rotation recalculated immediately when wind changes

### Rotation Math Explained

**Hex Direction to Angle:**
- Hex directions: 0=E, 1=SE, 2=SW, 3=W, 4=NW, 5=NE
- Each hex face = 60° apart
- Base angle = `direction * 60°`

**Coordinate System Adjustment:**
- Hex system is E-based (0° = East)
- Compass display is N-based (0° = North)
- Adjustment: subtract 90° to convert

**Camera Compensation:**
- Subtract camera rotation to keep icon fixed in world space
- Both needle and wind icon use this compensation

### Performance

- `_process()` runs every frame (~60 FPS)
- Simple rotation updates are very lightweight
- TextureRect rotation is GPU-accelerated
- No redrawing or complex calculations

### Troubleshooting

**Compass not visible:**
- Check that assets were generated in `res://assets/ui/compass/`
- Look for error messages in the console about missing textures
- Verify the WindCompass node is visible in the scene tree

**Needle/wind icon not rotating:**
- Check that camera reference is set (should be `NodePath("../../Camera")`)
- Verify camera is of type IsometricCamera with `camera_rotation_y` property
- Check console for "Auto-found camera" message

**Wind direction wrong:**
- Verify `GameState.wind_direction` contains correct value (0-5)
- Check coordinate system - hex 0 = East, compass shows relative to North
- Wind updates only when `GameState.phase_changed` fires

## Future Enhancements

- Add smooth rotation transitions (lerp/tween) instead of instant updates
- Add tooltip showing cardinal direction names when hovering
- Animate wind icon to show gusts or speed variations
- Add visual indication when wind changes (flash, particle effect)
- Support for dynamic wind changes mid-turn (if game design requires)
