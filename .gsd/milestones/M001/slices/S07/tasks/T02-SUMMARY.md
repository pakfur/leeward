---
id: T02
parent: S07
milestone: M001
key_files:
  - scripts/server/movement_resolver.gd
  - data/rules/bearing_off_table.json
  - test/unit/test_movement_resolver.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T18:43:03.038Z
blocker_discovered: false
---

# T02: Bearing off with pivot legality checks and collision fallback implemented and tested

**Bearing off with pivot legality checks and collision fallback implemented and tested**

## What Happened

Implemented _resolve_collision_or_bearoff() for contest losers and ships moving into occupied hexes. Checks bearing-off probability from DataManager via bearing_off_table.json (crew quality x maneuverability). _is_bearing_off_pivot_legal() enforces minimum forward hexes before a pivot is allowed, consulting _get_min_forward_for_pivot(). Failed pivot or failed roll falls through to collision. BEARING_OFF_ROLL and BEARING_OFF_PIVOT_DENIED events logged.

## Verification

4 bearing-off tests pass: crew quality/maneuverability lookup, pivot denied without forward hexes, pivot legal with enough forward hexes, and failed roll causing collision

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test-file F=test/unit/test_movement_resolver.gd` | 0 | All 259 tests pass including 4 bearing-off tests | 4600ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/movement_resolver.gd`
- `data/rules/bearing_off_table.json`
- `test/unit/test_movement_resolver.gd`
