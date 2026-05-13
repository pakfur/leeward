---
id: T03
parent: S02
milestone: M001
key_files:
  - test/unit/test_rng_determinism.gd
key_decisions:
  - Tests use standalone RNG + EnvironmentState rather than full GameState.start_new_game() to avoid deep controller dependencies
duration: 
verification_result: mixed
completed_at: 2026-05-12T16:05:05.463Z
blocker_discovered: false
---

# T03: Added determinism + integration tests: same-seed wind sequence, different-seed divergence, no private RNG on EnvironmentController

**Added determinism + integration tests: same-seed wind sequence, different-seed divergence, no private RNG on EnvironmentController**

## What Happened

Expanded test/unit/test_rng_determinism.gd with three integration tests: (1) test_tick_environment_deterministic_with_same_seed runs 10 ticks with seed 42 twice, asserts identical wind direction and speed. (2) test_tick_environment_diverges_with_different_seeds runs seed 42 vs 99 over 20 ticks. (3) test_environment_controller_has_no_private_rng instantiates EnvironmentController and asserts no rng property. Helper _run_tick_sequence() creates standalone RNG + EnvironmentState. All 8 tests in file pass. Full suite 196/199.

## Verification

make test-file F=test/unit/test_rng_determinism.gd: 8/8 passed; make test: 196/199

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test-file F=test/unit/test_rng_determinism.gd` | 0 | 8/8 passed | 1400ms |
| 2 | `make test` | 2 | 196/199; 3 pre-existing crew-count failures | 1400ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `test/unit/test_rng_determinism.gd`
