---
estimated_steps: 1
estimated_files: 2
skills_used: []
---

# T01: Add skip_post_combat_delay flag and write multi-turn integration test

Add `var skip_post_combat_delay: bool = false` to GameController so the 2-second POST_COMBAT timer can be bypassed in tests. Write test_game_loop.gd with: (1) a 5-turn integration test that sets up a scenario with player+AI ships, drives the full phase cycle per turn, verifies ships move, state persists, turn counter increments, and no errors; (2) a determinism test that runs the same scenario twice with the same seed and asserts identical resolution logs.

## Inputs

- `GameController._enter_post_combat_phase() line 613-622`
- `TurnPhaseController phase cycle`
- `StubAI.plot_all_ai_ships()`
- `MovementResolver.run()`

## Expected Output

- `scripts/core/game_controller.gd modified (skip_post_combat_delay flag)`
- `test/unit/test_game_loop.gd created with multi-turn and determinism tests`

## Verification

make test passes with all existing + new tests green
