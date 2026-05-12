---
id: T02
parent: S03
milestone: M001
key_files:
  - scripts/server/movement_validator.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T16:11:54.945Z
blocker_discovered: false
---

# T02: Replaced mock MA with real DataManager lookup, speed range from accel/decel tables, remaining MA tracks across path with recalculation on pivots

**Replaced mock MA with real DataManager lookup, speed range from accel/decel tables, remaining MA tracks across path with recalculation on pivots**

## What Happened

MovementValidator now uses DataManager.get_movement_allowance() with wind_facing computed via hex_grid.get_wind_facing(). Speed range: min_ma = max(speed_last_turn - decel, 0), max_ma = min(speed_last_turn + accel, base_ma). Internal PlottingState class holds all computed state. Path replay computes MA spent accounting for pivot costs and free-pivot-at-MA=0 rule. MA recalculates when facing changes.

## Verification

make test: 196/199 passing, no regression

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test` | 2 | 196/199 passing; 3 pre-existing | 1400ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/movement_validator.gd`
