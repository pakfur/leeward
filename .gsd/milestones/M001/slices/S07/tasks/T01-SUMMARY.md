---
id: T01
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
completed_at: 2026-05-12T18:42:58.379Z
blocker_discovered: false
---

# T01: Contested hex detection with N-way DRM-based d6 resolution implemented and tested

**Contested hex detection with N-way DRM-based d6 resolution implemented and tested**

## What Happened

Implemented _resolve_contested_hex() in MovementResolver that detects when multiple ships target the same hex in the same impulse. Uses _roll_contest() for d6 rolls with DRM modifiers computed by _calculate_contest_drm_relative() — crew quality, ship class, and remaining MP all influence the roll. Supports N-way contests (3+ ships). CONTESTED_HEX_ROLL events logged to ResolutionLog. Losers are routed to bearing-off/collision resolution.

## Verification

6 contest-related tests pass: two-ship head-on, three-ship contested, and 3 DRM modifier tests (crew quality, class, MP advantage)

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test-file F=test/unit/test_movement_resolver.gd` | 0 | All 259 tests pass including 6 contested-hex tests | 4600ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/movement_resolver.gd`
- `scripts/server/movement_types.gd`
- `test/unit/test_movement_resolver.gd`
