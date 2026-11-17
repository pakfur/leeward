# Environment, Sea Model and Water Shader

## Overview

The water and the ships' motion follow the server's environment (wind direction, wind speed, sea state 0-5) through one shared presentation object, `SeaModel`. Everything here is view only: the model reads the environment and never writes `EnvironmentState` (server authority). Design: `docs/superpowers/specs/2026-11-16-sea-state-design.md`.

Sea state: 0 calm (an extension with no rule effect), 1 slight, 2 moderate, 3 rough, 4 very rough, 5 high (1-5 as rule 3.B.5).

## Components

1. **EnvironmentState** (`scripts/state/environment_state.gd`): server data, `wind_direction` 0-5, `wind_speed`, `sea_state` 0-5 (`SEA_STATE_MAX`).
2. **EnvironmentController** (`scripts/server/environment_controller.gd`): rolls the changes and emits `environment_updated`.
3. **OceanView** (`scripts/view/ocean_view.gd`): on `environment_updated` and at game start, calls `SeaModel.set_environment(wind_direction, wind_speed, sea_state)`.
4. **SeaModel** (`scripts/view/sea_model.gd`, `SeaModel.instance`): the one sea. Owns the sea clock, three Gerstner swell components running downwind, the zoom intensity, the grid opacity, the look presets and the shader uniforms. Created in `GameController` with the HexMap's `ocean_material`.
5. **Ocean shader** (`assets/shaders/ocean_water.gdshader`): the swell (vertex and normals), the chop (surface detail), the plain grid and whitecaps, driven by the model's uniforms.
6. **ShipMotion** (`scripts/view/ship_motion.gd`) and **ShipView**: ships ride the same swell (heave, pitch, roll, heel to leeward).
7. **Playback** (`scripts/view/movement_resolution_playback_controller.gd`): ships glide through their steps instead of stepping hex by hex.

## Data flow

```
EnvironmentController (server)  --environment_updated-->  OceanView
    OceanView -> SeaModel.set_environment(wind_dir, wind_speed, sea_state)
    SeaModel (each frame: clock, camera distance -> zoom intensity)
        -> ocean shader uniforms (swell, chop, whitecaps, grid_opacity, zoom_intensity)
        -> ShipMotion.targets()/rendered() for each ShipView (view only)
```

## Presets (`data/ui/sea_presets.json`)

One preset per sea state 0-5 plus a `globals` block, loaded whenever the effective sea state changes (`SeaModel.apply_preset_if_changed`). Preset fields: `swell_height_mult`, `swell_wavelength`, `swell_speed`, `swell_shading`, `chop_strength`, `inertia_mult` (ship slowness), `heel_mult`, `glide_seconds` (playback seconds per moving segment), `whitecap_threshold`, `whitecap_strength`. Globals: `flat_distance`, `full_distance`, `grid_fade_start`, `grid_fade_end`, `whitecap_min_sea`. The Developer UI Sea tab (F12) edits them live and logs the values in this file's format; the sea-state override there changes the look only.

Fixed in code (`SeaModel`): `SWELL_AMP_BY_SEA` (swell amplitude by sea state), `WHITECAP_BY_SEA`, `HEEL_BY_WIND` (heel at a beam wind by wind speed), `COMPONENTS` (the three swell directions, shares, wavelengths and phases), `SWELL_Q` (crest sharpening), `G_MAP` (deep-water phase speed at map scale).

## Zoom bands

The camera distance gives the zoom `intensity` (smoothstep): 0 at `flat_distance` and beyond (the flat, readable game board: no swell, no ship motion, plain hex grid), 1 at `full_distance` and closer (full swell and motion). In between everything fades together, so a ship is exactly level and on the board's plane when zoomed out. `grid_opacity()` is 1 up to intensity `grid_fade_start` and 0 from `grid_fade_end` (a step when the two meet); whitecaps keep 15 % at intensity 0.

## Chop and whitecaps

The chop (fine surface detail ships do not ride) grows with the wind speed; its base is always sized for sea state 1 (`CHOP_BASE_SEA`), because the presets were tuned there, and each preset's `chop_strength` carries the difference between sea states. Whitecaps appear from sea state `whitecap_min_sea` (default 1), scaled by `WHITECAP_BY_SEA` inside the preset's `whitecap_strength` and threshold.

## Ship motion

`ShipMotion.targets` samples the swell at bow, stern and both beams for heave, pitch and roll. `ShipView` low-passes each toward its target with a time constant by ship class (a 74 is about 1.45 times slower than a frigate) times the preset's `inertia_mult`, then scales by zoom intensity (`ShipMotion.rendered`). The steady heel to leeward (the side `FireGeometry.leeward_side`) is `HEEL_BY_WIND` times `heel_mult`, times the beam component of the wind, times the sail carried (`SAIL_HEEL`: FS 0.6, MS 0.8, PS 1.0, bare poles 0.1); a dismasted or destroyed ship does not heel.

## Playback

Movement playback is split into stretches at every segment with an event (collision, contested hex, rollback, bear-off roll). Within a stretch each ship accelerates and decelerates along its steps and arrives exactly on its resolved pose; one clock covers all ships and counts only segments in which some ship moves, at `glide_seconds` each. After a bear-off pause the resumed log starts from the paused poses.

## Debugging

- Water not following the environment: check that `OceanView` is connected (`GameController`) and that `SeaModel.instance` exists.
- Ships level or the board flat: the camera is beyond `flat_distance` (intensity 0), by design.
- Tuning: F12, Sea tab; copy the logged preset line into `data/ui/sea_presets.json`.
- Tests: `test_sea_model.gd`, `test_ship_motion.gd`, `test_playback_glide.gd`.
