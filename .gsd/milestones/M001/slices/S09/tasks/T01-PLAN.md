---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T01: Playback controller core: impulse loop, animation, event pauses

Implement MovementResolutionPlaybackController that consumes ResolutionLog, groups events by impulse, animates ship positions via Tweens at ~200ms/impulse, handles facing interpolation, pauses on dramatic events (collision 2x, contested/bearing-off 1x), emits playback_completed signal

## Inputs

- `S06/S07: ResolutionLog, ResolutionEvent, ShipResolutionResult data classes in movement_types.gd`
- `HexGrid.axial_to_world for position conversion`
- `ShipView with base_position and model_node for Tween targets`

## Expected Output

- `scripts/view/movement_resolution_playback_controller.gd (210 lines)`
- `Signal: playback_completed`
- `Constants: IMPULSE_DURATION_MS=200, IMPULSE_GAP_MS=50, EVENT_PAUSE_MS=400`

## Verification

make test passes; playback controller tests for signals, event types, animation positioning all green
