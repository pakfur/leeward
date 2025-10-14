# Environment-Shader Integration

## Overview

The water shader is now dynamically responsive to server-authoritative environment state (wind direction, wind speed, and sea state). The shader parameters automatically update at the beginning of each turn's ENVIRONMENT phase to visually represent the current conditions.

## Architecture

### Components

1. **EnvironmentState** (`scripts/state/environment_state.gd`)
   - Pure data Resource
   - Server-authoritative
   - Contains: wind_direction (0-5), wind_speed (0-5), sea_state (0-3)
   - Deterministic `tick_environment()` method

2. **EnvironmentController** (`scripts/server/environment_controller.gd`)
   - Node that manages environment logic and visuals
   - Owns RandomNumberGenerator for any future random environment changes
   - Translates environment state to shader parameters
   - Listens for phase changes

3. **Ocean Shader** (`assets/shaders/ocean_water.gdshader`)
   - Gerstner wave-based water rendering
   - 8 wave parameters (direction, amplitude, frequency)
   - time_factor (wave animation speed)
   - noise_amp (surface roughness)

4. **HexMap** (`scripts/core/hex_map.gd`)
   - Owns the ocean_material (ShaderMaterial)
   - Provides access to shader parameters

### Data Flow

```
Turn Phase Controller (ENVIRONMENT phase) 		res://scripts/server/turn_phase_controller.gd
    ↓
EnvironmentController.tick_environment() 		res://scripts/server/environment_controller.gd
    ↓
EnvironmentState.tick_environment(turn_number)	res://scripts/state/environment_state.gd
    ↓
EnvironmentController.update_water_shader()		res://scripts/server/environment_controller.gd
    ↓
HexMap.ocean_material shader parameters updated
    ↓
Visual changes reflected in water rendering
```

## Shader Parameter Mapping

### Wind Direction → Wave Direction

Wind direction (hex facing 0-5) is converted to a 2D vector:
- 0 (E):  (1.0, 0.0)
- 1 (SE): (0.5, 0.866)
- 2 (SW): (-0.5, 0.866)
- 3 (W):  (-1.0, 0.0)
- 4 (NW): (-0.5, -0.866)
- 5 (NE): (0.5, -0.866)

Primary waves (wave_1, wave_3, wave_5, wave_7) are oriented based on this vector, with slight angular offsets for natural variation.

### Wind Speed + Sea State → Wave Amplitude

```
base_amplitude = 0.05 + (wind_speed * 0.03) + (sea_state * 0.05)
```

**Range:**
- Minimum (calm, speed=0, sea=0): 0.05
- Maximum (gale, speed=5, sea=3): 0.35

Different waves receive scaled versions of this base amplitude:
- wave_1: 20% of base (primary swell)
- wave_3: 15% of base (secondary)
- wave_5: 10% of base (cross waves)
- wave_7: 18% of base (larger swell)
- waves 2, 4, 6, 8: 2-12% of base (detail waves)

### Wind Speed + Sea State → Wave Speed

```
time_factor = 3.5 - (wind_speed * 0.25) - (sea_state * 0.15)
Clamped to [1.5, 3.5]
```

**Effect:**
- Higher wind_speed = lower time_factor = faster waves
- Calm (speed=0, sea=0): time_factor = 3.5 (slow animation)
- Gale (speed=5, sea=3): time_factor = 1.5 (fast animation)

### Sea State → Surface Roughness

```
noise_amp = 0.05 + (sea_state * 0.03)
```

**Range:**
- Calm (sea=0): 0.05
- Storm (sea=3): 0.14

## Implementation Files

### Modified Files

1. **`scripts/server/environment_controller.gd`**
   - Added shader update logic
   - Maps environment state to shader parameters
   - Listens for phase changes

2. **`scripts/autoload/game_state.gd`**
   - Added `environment_controller` reference
   - Instantiates controller in `_initialize_server_controllers()`

3. **`scripts/core/game_controller.gd`**
   - Sets hex_map reference on environment_controller
   - Triggers initial shader update on game start

4. **`scripts/server/turn_phase_controller.gd`**
   - Updated `_enter_environment_phase()` to use EnvironmentController
   - Ensures shader updates happen with environment state changes

5. **`assets/materials/ocean_water.tres`**
   - Added texture assignments for normal maps and foam

## How It Works

### At Game Start

1. GameController calls `GameState.start_new_game(scenario)`
2. GameState creates EnvironmentState from scenario data
3. GameController sets hex_map reference on EnvironmentController
4. EnvironmentController.force_update() triggers initial shader update
5. Water renders with initial environment conditions

### Each Turn (ENVIRONMENT Phase)

1. TurnPhaseController enters ENVIRONMENT phase
2. Calls `EnvironmentController.tick_environment(env_state, turn_number)`
3. EnvironmentState.tick_environment() updates wind/sea state deterministically
4. EnvironmentController.update_water_shader() translates new state to shader params
5. Shader parameters updated via `material.set_shader_parameter()`
6. Water visual appearance changes to match new conditions

### Signal Flow

```
TurnPhaseController._enter_environment_phase()
    ↓ emits
phase_changed(ENVIRONMENT)
    ↓ received by
EnvironmentController._on_phase_changed()
    ↓ triggers
update_water_shader()
```

## Testing the Integration

### Manual Testing

1. **Start the game** - Water should reflect initial environment
   - Check console for: "EnvironmentController: Updated water shader"

2. **Advance turns** - Watch water change each turn
   - Wind direction changes = wave direction shifts
   - Wind speed increases = waves get taller and faster
   - Sea state increases = rougher surface texture

3. **Observe the compass** - Wind direction indicator should match wave direction

### Console Output

Look for these messages:
```
EnvironmentController initialized (server: true)
EnvironmentController RNG seed: <number>
EnvironmentController: Updated water shader - Wind: E (0), Speed: Moderate (2), Sea: Moderate (1)
```

### Visual Indicators

- **Wave Direction**: Primary waves should flow in the current wind direction
- **Wave Height**: Higher wind speed + sea state = taller waves
- **Wave Speed**: Stormy conditions = faster wave animation
- **Surface Detail**: Rougher seas = more surface texture variation

## Future Enhancements

### Potential Improvements

1. **Smooth Transitions**: Add lerp/tween for gradual shader parameter changes
2. **Wave Period Variation**: More complex frequency patterns based on wind history
3. **Whitecaps**: Enhance foam rendering at high wind speeds
4. **Depth-Based Effects**: Shallow water appearance in coastal environments
5. **Time of Day Integration**: Link shader colors to environment.time_of_day
6. **Weather Effects**: Rain/storm visual effects based on environment.precipitation

### Advanced Features

1. **Wind Gusts**: Temporary wave amplitude spikes
2. **Fetch Distance**: Waves build over distance (environment tracking)
3. **Current Visualization**: Show ocean currents independent of wind
4. **Wake Effects**: Ship-generated waves that interact with environment waves

## Debugging

### Common Issues

**Shader not updating:**
- Check console for warning: "Cannot update shader - missing references"
- Verify hex_map reference is set in GameController._ready()
- Verify environment_controller exists in GameState

**Wrong wave direction:**
- Check wind_direction value (0-5)
- Verify HEX_DIRECTIONS mapping in environment_controller.gd
- Check camera angle (visual perception vs actual wave direction)

**No visual change:**
- Environment values might not be changing each turn
- Check EnvironmentState.tick_environment() logic
- Verify wind_direction_change and wind_speed_change are set in scenario

### Debug Commands

Add to EnvironmentController for manual testing:
```gdscript
func set_test_conditions(wind_dir: int, wind_spd: int, sea: int) -> void:
    var test_env = EnvironmentState.new()
    test_env.wind_direction = wind_dir
    test_env.wind_speed = wind_spd
    test_env.sea_state = sea
    game_state.environment = test_env
    update_water_shader()
```

## Performance

- Shader parameter updates are negligible cost (happens once per turn)
- Gerstner wave calculations run on GPU (no CPU impact)
- RNG operations minimal (only for random environment changes)
- No per-frame updates (only on phase changes)

## Conclusion

The environment-shader integration provides a dynamic, responsive water surface that reflects game state conditions. The system is:
- **Server-authoritative**: Environment changes controlled by server
- **Deterministic**: Same inputs always produce same shader state
- **Performant**: Updates only when needed
- **Extensible**: Easy to add new environment→shader mappings
- **Maintainable**: Clear separation of concerns (state, logic, visuals)
