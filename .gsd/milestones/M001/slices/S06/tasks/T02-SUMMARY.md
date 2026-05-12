---
id: T02
parent: S06
milestone: M001
key_files:
  - scripts/server/movement_resolver.gd
key_decisions:
  - DRM calculation follows docs/02-game-rules.md section 2.1 — rudder DRM skipped for M001 since rudder health is not yet tracked
duration: 
verification_result: passed
completed_at: 2026-05-12T18:38:20.818Z
blocker_discovered: false
---

# T02: Implemented tacking roll with DRMs and in-irons escape logic in MovementResolver

**Implemented tacking roll with DRMs and in-irons escape logic in MovementResolver**

## What Happened

Extended MovementResolver with _roll_tacking() and _resolve_in_irons_escape() methods. Tacking roll looks up base probability via DataManager.get_tacking_percent(), calculates DRMs (_calculate_tacking_drm: +0.2 per rigging section lost, other modifiers), and rolls against game_state.rng. On success, ship continues full plotted path past L-facing pivot. On failure, ship stops at L-facing hex, immobilized with speed=0. In-irons escape uses same tacking table lookup — success allows plotted movement, failure keeps ship immobilized at current hex. All roll inputs, thresholds, DRMs, and outcomes are Trace.trace_log'd. Events emitted: tack_success, tack_failure, in_irons_escape_success, in_irons_escape_failure.

## Verification

grep confirms tacking and in-irons code in movement_resolver.gd. make test passes 259/259.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `grep -q 'tack_success\|tack_failure' scripts/server/movement_resolver.gd` | 0 | pass | 50ms |
| 2 | `grep -q 'in_irons' scripts/server/movement_resolver.gd` | 0 | pass | 50ms |
| 3 | `make test` | 0 | 259/259 tests pass | 4577ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/movement_resolver.gd`
