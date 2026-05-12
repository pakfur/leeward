---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T02: Migrate EnvironmentController to consume GameState.rng

Remove EnvironmentController's private `rng` property and `_ready()` RNG creation. In `tick_environment()`, use `game_state.rng` instead of `self.rng`. Update `_init()` to no longer create an RNG. The `EnvironmentState.tick_environment()` method already accepts an RNG parameter — just pass the right one.

## Inputs

- `scripts/server/environment_controller.gd`
- `scripts/autoload/game_state.gd`

## Expected Output

- `scripts/server/environment_controller.gd`

## Verification

make test passes (no regression); grep confirms no `RandomNumberGenerator.new()` in environment_controller.gd
