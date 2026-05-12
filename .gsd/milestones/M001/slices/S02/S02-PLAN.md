# S02: Shared seeded RNG on GameState; EnvironmentController migrated

**Goal:** GameState owns a single seeded RandomNumberGenerator; EnvironmentController migrated to consume it; same scenario seed reproduces same wind sequence.
**Demo:** GameState.rng exists, seeded from scenario; EnvironmentController consumes it; existing env tests pass; same seed reproduces same wind sequence in a manual run.

## Must-Haves

- `GameState.rng` exists and is seeded from `scenario_data.seed` in `start_new_game()`
- `EnvironmentController` has no private RNG; uses `GameState.rng` via `game_state.rng`
- Determinism test: same seed → same 10-turn wind sequence
- All 196 existing tests still pass
- Trace log confirms seed value on game start

## Proof Level

- This slice proves: contract + integration — determinism proven by repeating wind sequence with fixed seed; integration proven by existing env code still working through the new RNG path

## Integration Closure

- Upstream: S01's validated `scenario_data.seed` integer feeds into `GameState.rng`
- New wiring: `GameState.rng` created in `start_new_game()`; `EnvironmentController.tick_environment()` passes `game_state.rng` to `env_state.tick_environment()`
- Remaining: S03+ will consume `GameState.rng` for tacking rolls, collision rolls, etc.

## Verification

- Trace log on game start: seed value used
- GameState.rng accessible for downstream controllers to share

## Tasks

- [ ] **T01: Add GameState.rng seeded from scenario** `est:20m`
  Add a `rng: RandomNumberGenerator` property to GameState. In `start_new_game()`, create and seed it from `scenario_data["seed"]`. Trace-log the seed value. No behavior changes to EnvironmentController yet — this task just establishes the property.
  - Files: `scripts/autoload/game_state.gd`
  - Verify: make test-file F=test/unit/test_rng_determinism.gd passes (seed-round-trip test); make test still 196/196

- [ ] **T02: Migrate EnvironmentController to consume GameState.rng** `est:25m`
  Remove EnvironmentController's private `rng` property and `_ready()` RNG creation. In `tick_environment()`, use `game_state.rng` instead of `self.rng`. Update `_init()` to no longer create an RNG. The `EnvironmentState.tick_environment()` method already accepts an RNG parameter — just pass the right one.
  - Files: `scripts/server/environment_controller.gd`
  - Verify: make test passes (no regression); grep confirms no `RandomNumberGenerator.new()` in environment_controller.gd

- [ ] **T03: Write determinism + integration tests for seeded RNG** `est:30m`
  Expand the test file from T01 with: (1) determinism test — create GameState, call start_new_game with seed 42, run tick_environment 10 times, record wind values; repeat with same seed and assert identical sequence. (2) Different-seed test — seed 42 vs seed 99 produce different sequences. (3) Verify EnvironmentController has no private RNG field. Run full suite to confirm no regressions.
  - Files: `test/unit/test_rng_determinism.gd`
  - Verify: make test-file F=test/unit/test_rng_determinism.gd passes all tests; make test full suite green

## Files Likely Touched

- scripts/autoload/game_state.gd
- scripts/server/environment_controller.gd
- test/unit/test_rng_determinism.gd
