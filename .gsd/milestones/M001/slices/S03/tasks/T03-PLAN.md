---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T03: Implement turning rules: min-forward, pivot caps, no consecutive pivots

In calculate_valid_moves: (1) Check forward_hexes_since_last_pivot >= min from turning_table before offering port/starboard. Use DataManager.get_min_heading_change_movement_required(direction, ship_speed, maneuverability) where direction is same_direction if last_pivot_direction matches, opposite_direction otherwise. (2) Enforce max 2 pivots per turn (pivots_used < 2). (3) No consecutive pivots — if last step was a pivot, only offer forward. (4) Free pivot at MA=0: if remaining_ma == 0 and pivots_used == 0, offer one free pivot (cost 0). Trace.trace_log on each rule that blocks a move option.

## Inputs

- `scripts/server/movement_validator.gd`
- `data/rules/turning_table.json`

## Expected Output

- `scripts/server/movement_validator.gd`

## Verification

Fixture: ship at speed 5, maneuverability a → must move forward N hexes before turning (from turning table). Max 2 pivots per turn. No consecutive pivots. Free pivot at MA=0.
