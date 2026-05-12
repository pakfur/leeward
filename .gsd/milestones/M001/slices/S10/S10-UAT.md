# S10: Integration: full loop, 5-turn sustained playtest, all fixtures green — UAT

**Milestone:** M001
**Written:** 2026-05-12T19:11:55.068Z

## S10 UAT: Integration — Full Game Loop

### Test Results
- `make test` → 264/264 pass, 970 assertions

### Integration Tests (test_game_loop.gd)
- [x] **test_five_turn_game_loop** — 5 turns through full phase cycle, ships move, turn counter reaches 6
- [x] **test_ships_move_each_turn** — Ship position changes every turn across 3 turns
- [x] **test_plotted_actions_cleared_after_resolution** — Both player and AI plots cleared after resolution
- [x] **test_turn_counter_increments** — Turn counter correctly increments from 1→2→3
- [x] **test_deterministic_resolution_with_same_seed** — Same seeds produce identical resolution logs across 2 runs of 3 turns each

### Phase Cycle Verified Per Turn
SETUP → ENVIRONMENT → PLANNING → MOVEMENT_RESOLUTION → COMBAT_RESOLUTION → DRIFT_CALCULATION → STATUS_ADJUSTMENT → MORALE_CHECK → MESSAGE_DELIVERY → POST_COMBAT → END_TURN → (next turn)

### Known Limitations
- Visual playtest not possible in headless mode — integration tests drive controller level only
- POST_COMBAT and END_TURN require manual advance_phase() calls (view layer handles this in-game via timer/button)
