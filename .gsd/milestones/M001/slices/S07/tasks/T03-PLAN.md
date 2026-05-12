---
estimated_steps: 1
estimated_files: 2
skills_used: []
---

# T03: Collision mechanics and fouling roll

Implement _apply_collision() with rigging damage by sail state (FS=2R, MS=4R, PS=6R, NS=0R), 50% fouling roll excluding dismasted ships, and apply_results() to propagate collision/fouling state to ShipState.

## Inputs

- `ShipResolutionResult collision/fouling fields`

## Expected Output

- `_apply_collision() method`
- `_roll_fouling() method`
- `_is_dismasted() method`
- `COLLISION and FOULING events`
- `apply_results() propagation`

## Verification

Tests: test_collision_stops_both_ships, test_collision_rigging_loss_by_sail_state, test_dismasted_ships_cannot_foul, test_fouling_roll_50_percent, test_apply_results_sets_collision_flags, test_apply_results_applies_rigging_damage all pass
