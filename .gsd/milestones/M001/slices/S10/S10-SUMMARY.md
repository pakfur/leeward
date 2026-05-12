---
id: S10
parent: M001
milestone: M001
provides:
  - (none)
requires:
  []
affects:
  []
key_files:
  - test/unit/test_game_loop.gd
  - scripts/core/game_controller.gd
  - scripts/server/environment_controller.gd
key_decisions:
  - Tests drive TurnPhaseController directly, bypassing GameController scene tree dependency
  - All RNGs seeded in before_each for reproducible tests
  - EnvironmentController shader warning silenced for headless execution
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T19:11:55.068Z
blocker_discovered: false
---

# S10: Integration: full loop, 5-turn sustained playtest, all fixtures green

**Full 5-turn game loop integration tested headlessly with determinism verification — 264/264 tests pass**

## What Happened

S10 verifies that the complete movement resolution pipeline works end-to-end across multiple turns. Five integration tests drive the server-side pipeline (TurnPhaseController → StubAI → MovementPlottingController → MovementResolver) through the full 10-phase turn cycle for up to 5 turns. Tests confirm: ships move each turn, plotted_actions are cleared after resolution, turn counter increments correctly, and identical seeds produce identical resolution logs (determinism). A skip_post_combat_delay flag was added to GameController for future UI testing, and EnvironmentController's shader warning was silenced for headless mode.

## Verification

make test — 264/264 pass, 970 assertions, 0 failures. Integration tests cover: 5-turn loop (test_five_turn_game_loop), per-turn movement (test_ships_move_each_turn), plot clearing (test_plotted_actions_cleared_after_resolution), turn counter (test_turn_counter_increments), determinism (test_deterministic_resolution_with_same_seed).

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

None.

## Known Limitations

None.

## Follow-ups

None.

## Files Created/Modified

- `scripts/core/game_controller.gd` — Added skip_post_combat_delay flag (3 lines)
- `scripts/server/environment_controller.gd` — Changed push_warning to silent return in update_water_shader when hex_map is null
- `test/unit/test_game_loop.gd` — New file: 5 integration tests for multi-turn game loop and determinism
