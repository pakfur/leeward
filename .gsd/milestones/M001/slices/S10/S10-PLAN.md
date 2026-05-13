# S10: Integration slice: full loop, 5-turn sustained playtest, all fixtures green

**Goal:** Integration: full 5-turn game loop with skip_post_combat_delay flag, determinism verification, and full regression green
**Demo:** Open test_fleet.json, play 5 turns through PLANNING and MOVEMENT_RESOLUTION with stub-AI opposition; no console errors; `make test` all green; determinism test green.

## Must-Haves

- 1. Multi-turn integration test drives 5 turns through the complete phase cycle (ENVIRONMENT→PLANNING→MOVEMENT_RESOLUTION→...→END_TURN) with stub-AI opposition, no errors. 2. Determinism test: same seed produces identical resolution logs across two runs. 3. `make test` all green (259+ tests).

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: Add skip_post_combat_delay flag and write multi-turn integration test** `est:30m`
  Add `var skip_post_combat_delay: bool = false` to GameController so the 2-second POST_COMBAT timer can be bypassed in tests. Write test_game_loop.gd with: (1) a 5-turn integration test that sets up a scenario with player+AI ships, drives the full phase cycle per turn, verifies ships move, state persists, turn counter increments, and no errors; (2) a determinism test that runs the same scenario twice with the same seed and asserts identical resolution logs.
  - Files: `scripts/core/game_controller.gd`, `test/unit/test_game_loop.gd`
  - Verify: make test passes with all existing + new tests green

## Files Likely Touched

- scripts/core/game_controller.gd
- test/unit/test_game_loop.gd
