---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T01: Added GameState.rng property seeded from scenario_data["seed"], with Trace logging and a 5-test determinism test suite

Add a `rng: RandomNumberGenerator` property to GameState. In `start_new_game()`, create and seed it from `scenario_data["seed"]`. Trace-log the seed value. No behavior changes to EnvironmentController yet — this task just establishes the property.

## Inputs

- `scripts/autoload/game_state.gd`
- `data/scenarios/test_basic.json`

## Expected Output

- `scripts/autoload/game_state.gd`
- `test/unit/test_rng_determinism.gd`

## Verification

make test-file F=test/unit/test_rng_determinism.gd passes (seed-round-trip test); make test still 196/196
