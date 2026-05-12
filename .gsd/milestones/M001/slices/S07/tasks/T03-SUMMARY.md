---
id: T03
parent: S07
milestone: M001
key_files:
  - scripts/server/movement_resolver.gd
  - scripts/server/movement_types.gd
  - test/unit/test_movement_resolver.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T18:43:07.909Z
blocker_discovered: false
---

# T03: Collision mechanics with rigging damage and 50% seeded fouling roll implemented and tested

**Collision mechanics with rigging damage and 50% seeded fouling roll implemented and tested**

## What Happened

Implemented _apply_collision() with sail-state-dependent rigging damage (FS=2R, MS=4R, PS=6R, NS=0R). _roll_fouling() applies 50% chance using GameState.rng, with _is_dismasted() exempting ships with all rigging sections destroyed. apply_results() propagates collision_this_turn, fouled_with, and rigging damage to ShipState after resolution. COLLISION, COLLISION_RIGGING_LOSS, and FOULING events logged to ResolutionLog.

## Verification

6 collision/fouling tests pass: collision stops both ships, rigging loss by sail state, dismasted cannot foul, 50% fouling statistical test, apply_results collision flags, apply_results rigging damage

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test-file F=test/unit/test_movement_resolver.gd` | 0 | All 259 tests pass including 6 collision/fouling tests | 4600ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/movement_resolver.gd`
- `scripts/server/movement_types.gd`
- `test/unit/test_movement_resolver.gd`
