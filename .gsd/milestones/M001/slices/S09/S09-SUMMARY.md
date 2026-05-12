---
id: S09
parent: M001
milestone: M001
provides:
  - MovementResolutionPlaybackController consuming ResolutionLog
  - playback_completed signal for phase advancement
  - TurnPhaseController.on_playback_completed() integration point
requires:
  - slice: S06
    provides: ResolutionLog, ResolutionEvent, ShipResolutionResult data classes
  - slice: S07
    provides: Final ResolutionLog schema with multi-ship events
affects:
  []
key_files:
  - scripts/view/movement_resolution_playback_controller.gd
  - test/unit/test_playback_controller.gd
key_decisions:
  - Resolver handles contests/bearing-off mechanically — no interactive modals needed for M001
  - Pre-movement events collected and played before impulse loop for clean sequencing
  - Concurrent Tween animation within impulses preserves simultaneous-resolution drama
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T18:52:59.242Z
blocker_discovered: false
---

# S09: Movement resolution playback (view layer animates ResolutionLog)

**View-layer playback controller animates ships hex-by-hex from ResolutionLog with event pauses and phase integration**

## What Happened

MovementResolutionPlaybackController bridges the gap between the server-side MovementResolver (pure logic) and the player's visual experience. It consumes a ResolutionLog and orchestrates: pre-movement events (tacking rolls, in-irons escapes), concurrent impulse-by-impulse ship animation via Tweens at ~200ms each with sine easing, dramatic pauses on special events (contests, collisions, fouling), and facing interpolation using shortest-angle math. On completion it emits playback_completed, which TurnPhaseController uses to advance past MOVEMENT_RESOLUTION through the remaining stubbed phases. The resolver handles contested hex and bearing off mechanically via dice rolls — no interactive surrender/bear-off modals are needed for M001 scope, consistent with S07/S08 decisions.

## Verification

make test — 259/259 pass. 16 playback-specific tests cover signals, all event types, real ShipView position/facing animation, and TurnPhaseController phase advancement integration.

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

None.

## Known Limitations

None.

## Follow-ups

None.

## Files Created/Modified

None.
