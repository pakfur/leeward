# S09: Movement resolution playback (view layer animates ResolutionLog) — UAT

**Milestone:** M001
**Written:** 2026-05-12T18:52:59.242Z

## S09 UAT: Movement Resolution Playback

### Signal lifecycle
- [x] Empty ResolutionLog emits playback_completed
- [x] Single-move log emits playback_completed after animation
- [x] is_playing() returns true during playback, false before/after
- [x] Concurrent play() calls are guarded (second call returns immediately)

### Event type coverage
- [x] Multi-impulse logs complete successfully
- [x] Tacking roll events play in pre-movement phase
- [x] Collision events trigger 2x dramatic pause (800ms)
- [x] Contested hex events trigger standard pause (400ms)
- [x] Bearing off events with stopped event complete
- [x] Immobilized/skip_no_plot events handled
- [x] Fouling events trigger 2x dramatic pause

### Animation fidelity
- [x] ShipView.base_position matches target hex after move (±0.1)
- [x] ShipView.model_node facing angle matches target after turn (±1.0°)
- [x] Concurrent moves within impulse animate simultaneously

### Phase integration
- [x] TurnPhaseController emits resolution_log_ready on PLANNING→MOVEMENT_RESOLUTION
- [x] Phase advances past MOVEMENT_RESOLUTION after on_playback_completed()
