# S09: Movement resolution playback (view layer animates ResolutionLog)

**Goal:** View-layer playback controller that consumes ResolutionLog and animates ships hex-by-hex with event pauses and phase advancement integration
**Demo:** Watch ships glide hex-by-hex per impulse at ~200ms each; contested-hex surrender prompt pauses playback; bear-off prompt pauses; after playback ships at resolved positions with updated facing + speed.

## Must-Haves

- MovementResolutionPlaybackController animates ships at ~200ms/impulse, pauses on dramatic events, emits playback_completed, integrates with TurnPhaseController phase advancement; 16 tests pass covering signals, events, animation, and integration

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: Playback controller core: impulse loop, animation, event pauses** `est:2h`
  Implement MovementResolutionPlaybackController that consumes ResolutionLog, groups events by impulse, animates ship positions via Tweens at ~200ms/impulse, handles facing interpolation, pauses on dramatic events (collision 2x, contested/bearing-off 1x), emits playback_completed signal
  - Files: `scripts/view/movement_resolution_playback_controller.gd`
  - Verify: make test passes; playback controller tests for signals, event types, animation positioning all green

- [x] **T02: Playback controller tests: signals, events, ShipView animation, phase integration** `est:2h`
  Comprehensive test suite covering: empty log completion, single/multi-impulse playback, concurrent playback guard, all event types (tacking, collision, contested hex, bearing off, immobilized, fouling), real ShipView position/facing animation verification, TurnPhaseController integration (resolution_log_ready signal, phase advancement after playback)
  - Files: `test/unit/test_playback_controller.gd`
  - Verify: make test passes with all 16 playback tests green (259/259 total)

## Files Likely Touched

- scripts/view/movement_resolution_playback_controller.gd
- test/unit/test_playback_controller.gd
