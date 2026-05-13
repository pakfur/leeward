---
id: S07
parent: M001
milestone: M001
provides:
  - MovementResolver multi-ship: impulse-by-impulse contested hex, bearing off, collision, fouling
  - ResolutionLog schema final with all event types
  - apply_results() propagates resolution outcomes to ShipState
requires:
  - slice: S06
    provides: Single-ship resolver + ResolutionLog primitives
affects:
  []
key_files:
  - scripts/server/movement_resolver.gd
  - scripts/server/movement_types.gd
  - data/rules/bearing_off_table.json
  - test/unit/test_movement_resolver.gd
key_decisions:
  - Impulse-by-impulse contest detection per hex (not full-plot-then-contest)
  - DRM formula: crew quality diff + class diff + MP advantage, each ±1
  - Bearing-off pivot legality gates on min-forward-hexes from turning table
  - Collision rigging damage scales with sail exposure (fighting > plain > none)
  - Dismasted exemption from fouling prevents double-penalty
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T18:43:28.399Z
blocker_discovered: false
---

# S07: MovementResolver contested hexes, bear-off, collisions, fouling

**Multi-ship resolution with contested hexes, bearing off, collisions, and fouling fully implemented and tested (11 dedicated tests)**

## What Happened

S07 delivers multi-ship resolution capabilities in MovementResolver. The impulse-by-impulse loop detects when multiple ships target the same hex and runs DRM-modified d6 contests (crew quality, ship class, MP advantage). Contest losers attempt bearing off — checked against pivot legality (minimum forward hexes) and bearing-off probability from bearing_off_table.json. Failed bearing off causes collision with sail-state-dependent rigging damage (FS=2R through NS=0R). Collisions trigger a seeded 50% fouling roll (dismasted ships exempt). All results propagated to ShipState via apply_results(). ResolutionLog schema includes CONTESTED_HEX_ROLL, BEARING_OFF_ROLL, BEARING_OFF_PIVOT_DENIED, COLLISION, COLLISION_RIGGING_LOSS, and FOULING event types.

## Verification

All 259 tests pass via make test. 11 dedicated multi-ship tests cover: two-ship head-on contest, three-ship contest, 3 DRM modifier tests, 4 bearing-off scenarios (crew/maneuverability, pivot denied, pivot legal, failed roll), collision stops both ships, rigging loss by sail state, dismasted cannot foul, 50% fouling statistical test, apply_results collision flags, apply_results rigging damage.

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
