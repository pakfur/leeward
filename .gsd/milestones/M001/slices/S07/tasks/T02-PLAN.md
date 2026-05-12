---
estimated_steps: 1
estimated_files: 2
skills_used: []
---

# T02: Bearing off with pivot legality and collision fallback

Implement _resolve_collision_or_bearoff() for contest losers: check bearing-off probability from DataManager, verify pivot legality via min-forward-hexes rule, fall back to collision on denied pivot or failed roll.

## Inputs

- `bearing_off_table.json`
- `DataManager.get_bearing_off_probability()`

## Expected Output

- `_resolve_collision_or_bearoff() method`
- `_is_bearing_off_pivot_legal() method`
- `_get_min_forward_for_pivot() method`
- `BEARING_OFF_ROLL and BEARING_OFF_PIVOT_DENIED events`

## Verification

Tests: test_bearing_off_uses_crew_quality_and_maneuverability, test_bearing_off_pivot_denied_no_forward_hexes, test_bearing_off_pivot_legal_with_enough_forward_hexes, test_bearing_off_pivot_legal_roll_fails_causes_collision all pass
