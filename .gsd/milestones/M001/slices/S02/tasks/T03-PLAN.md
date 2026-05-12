---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T03: Write determinism + integration tests for seeded RNG

Expand the test file from T01 with: (1) determinism test — create GameState, call start_new_game with seed 42, run tick_environment 10 times, record wind values; repeat with same seed and assert identical sequence. (2) Different-seed test — seed 42 vs seed 99 produce different sequences. (3) Verify EnvironmentController has no private RNG field. Run full suite to confirm no regressions.

## Inputs

- `scripts/autoload/game_state.gd`
- `scripts/server/environment_controller.gd`
- `scripts/state/environment_state.gd`

## Expected Output

- `test/unit/test_rng_determinism.gd`

## Verification

make test-file F=test/unit/test_rng_determinism.gd passes all tests; make test full suite green
