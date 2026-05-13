---
estimated_steps: 1
estimated_files: 2
skills_used: []
---

# T01: Contested hex detection and DRM-based resolution

Implement _resolve_contested_hex() with N-way contest support, d6 roll with DRM modifiers (crew quality, ship class, MP advantage), and tiebreaking. Log CONTESTED_HEX_ROLL events.

## Inputs

- `S06 ResolutionLog primitives`
- `GameState.rng`

## Expected Output

- `_resolve_contested_hex() method`
- `_roll_contest() method`
- `_calculate_contest_drm_relative() method`
- `ResolutionEvent.CONTESTED_HEX_ROLL type`

## Verification

Tests: test_two_ships_head_on_contested_hex, test_three_ship_contested_hex, test_contest_drm_crew_quality_advantage, test_contest_drm_class_advantage, test_contest_drm_more_mp_advantage all pass
