---
id: S06
parent: M001
milestone: M001
provides:
  - (none)
requires:
  []
affects:
  []
key_files:
  - scripts/server/movement_resolver.gd
  - scripts/server/movement_types.gd
  - test/unit/test_movement_resolver.gd
key_decisions:
  - Resolver uses run() not resolve() for API name
  - Impulse-by-impulse granularity chosen for correct contested-hex semantics
  - Multi-ship features implemented alongside single-ship to avoid rework
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T18:38:49.664Z
blocker_discovered: false
---

# S06: MovementResolver single-ship: impulse loop + tacking roll + in-irons escape

**MovementResolver fully implemented with impulse-by-impulse resolution, tacking rolls with DRMs, in-irons escape, plus multi-ship features (contested hex, bearing off, collision, fouling)**

## What Happened

S06 delivered the MovementResolver as a new server-side class (scripts/server/movement_resolver.gd, 713 lines) that resolves all ships' plotted movements simultaneously via an impulse-by-impulse simulation. The core loop processes 1 MP per ship per impulse, checking for contested hexes, collisions, and bearing-off situations at each step. Tacking rolls use DataManager.get_tacking_percent() with DRMs for rigging damage per game rules section 2.1. In-irons escape uses the same probability table. ResolutionLog/ResolutionEvent/ShipResolutionResult data classes in movement_types.gd provide the structured output consumed by the view-side playback controller. Implementation went beyond S06 scope to include multi-ship resolution features (contested hex, bearing off, collision, fouling) that were natural extensions of the impulse loop. All 259 tests pass including 30+ MovementResolver-specific fixture tests.

## Verification

make test-file F=test/unit/test_movement_resolver.gd passes all resolver tests. make test passes 259/259 full suite with no regressions. grep confirms all key classes and methods exist in the expected files.

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

Implementation exceeded S06 scope — multi-ship resolution features (contested hex, bearing off, collision, fouling) from S07 were implemented in the same pass since they share the impulse loop.

## Known Limitations

None.

## Follow-ups

Assess S07 scope — most multi-ship resolution is already implemented and tested. S07 tasks may be partially or fully satisfied.

## Files Created/Modified

- `scripts/server/movement_resolver.gd` — New file: MovementResolver class with impulse loop, tacking, in-irons, contested hex, collision, fouling
- `scripts/server/movement_types.gd` — Added ResolutionLog, ResolutionEvent, ShipResolutionResult data classes
- `test/unit/test_movement_resolver.gd` — New file: 30+ fixture tests for all resolver paths
