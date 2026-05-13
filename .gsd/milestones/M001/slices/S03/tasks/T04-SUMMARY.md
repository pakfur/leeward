---
id: T04
parent: S03
milestone: M001
key_files:
  - scripts/server/movement_validator.gd
  - scripts/server/movement_plotting_session.gd
key_decisions:
  - (none)
duration: 
verification_result: passed
completed_at: 2026-05-12T16:12:05.035Z
blocker_discovered: false
---

# T04: Implemented luffing (pivot into L ends movement), in-irons (speed 0 + facing L), tacking detection, fast-tack +1 MA bonus (C→B first pivot)

**Implemented luffing (pivot into L ends movement), in-irons (speed 0 + facing L), tacking detection, fast-tack +1 MA bonus (C→B first pivot)**

## What Happened

Luffing: during path replay, pivot into wind_facing=L sets luffing_ended=true; calculate_valid_moves returns empty result. In-irons: speed=0 + facing L + empty path = no moves (can_submit=true for no-movement submission). Tacking: pivot count >=2 and luffing occurred sets is_tacking_attempt. Fast-tack: first pivot from C to B adds +1 to max_ma. All conditions logged via Trace.

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
- `scripts/server/movement_plotting_session.gd`
