---
estimated_steps: 13
estimated_files: 1
skills_used: []
---

# T02: Implement tacking roll and in-irons escape in MovementResolver

Extend MovementResolver to handle tacking and in-irons cases before the impulse loop.

**Tacking roll** (when ShipState.tacking == true AND plot contains a tack — is_tacking_attempt):
1. Look up base probability: DataManager.get_tacking_percent(ship.maneuverability, wind_speed)
2. Calculate DRMs per docs/02-game-rules.md section 2.1: +0.2 per rigging section lost, +0.1 if facing L, +0.1 if towing, +0.3 if reversing tack, +0.3 if rudder_health <= 0 (skip rudder for M001 — not tracked yet). The DRM is a penalty subtracted from the success threshold.
3. Roll: game_state.rng.randf(). If roll <= (base_probability - total_drm), tack succeeds.
4. Success: ship continues plotted path from the post-tack facing (past the L pivot). Emit tack_success event.
5. Failure: ship stops at the L-facing hex, immobilized=true for this turn, speed=0. Emit tack_failure event. No further impulses for this ship.

**In-irons escape** (ship at speed=0, facing L, no tacking attempt — was already in irons from prior turn):
1. Same tacking_table probability lookup.
2. Roll: game_state.rng.randf(). If roll <= probability, ship escapes — may execute plotted path.
3. Failure: ship remains immobilized, no movement. Emit in_irons_escape_failure.

Note: The is_tacking_attempt flag is set during plotting (S05) and stored on ShipState.tacking. The plotted path for a tacking ship includes the two consecutive pivots through L. On tack success, the resolver walks the full path. On tack failure, the resolver finds the L-facing step and stops there.

Trace.trace_log all roll inputs, thresholds, DRMs, and outcomes.

## Inputs

- `scripts/server/movement_resolver.gd`
- `scripts/server/movement_types.gd`
- `scripts/autoload/data_manager.gd`
- `scripts/state/ship_state.gd`
- `docs/02-game-rules.md`

## Expected Output

- `scripts/server/movement_resolver.gd`

## Verification

make test (all existing tests pass) && grep -q 'tack_roll\|tack_success\|tack_failure' scripts/server/movement_resolver.gd && grep -q 'in_irons' scripts/server/movement_resolver.gd
