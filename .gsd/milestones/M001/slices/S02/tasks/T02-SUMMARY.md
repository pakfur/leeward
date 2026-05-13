---
id: T02
parent: S02
milestone: M001
key_files:
  - scripts/server/environment_controller.gd
key_decisions:
  - EnvironmentController never had a stored RNG field — migration was ensuring tick_environment passes game_state.rng consistently
duration: 
verification_result: passed
completed_at: 2026-05-12T16:05:01.381Z
blocker_discovered: false
---

# T02: Migrated EnvironmentController to consume GameState.rng — tick_environment passes game_state.rng to env_state

**Migrated EnvironmentController to consume GameState.rng — tick_environment passes game_state.rng to env_state**

## What Happened

EnvironmentController had no private RNG field to remove — it was already stateless with respect to RNG. The key change was ensuring `tick_environment()` passes `game_state.rng` to `env_state.tick_environment(turn_number, rng, history)`. The constructor stores a `game_state` reference. grep confirms zero instances of `RandomNumberGenerator.new()` in environment_controller.gd. Full test suite: 196/199 (3 pre-existing crew-count failures unrelated to this work).

## Verification

grep confirms no RandomNumberGenerator.new() in environment_controller.gd; make test 196/199 passing

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `grep RandomNumberGenerator.new() scripts/server/environment_controller.gd` | 1 | pass | 50ms |
| 2 | `make test` | 2 | 196/199 passing; 3 pre-existing crew-count failures | 1400ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/environment_controller.gd`
