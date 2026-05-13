# S07: MovementResolver contested hexes, bear-off, collisions, fouling

**Goal:** Implement multi-ship resolution in MovementResolver: contested hexes with DRM, bearing off with pivot checks, collisions that stop both ships, and 50% fouling roll (seeded).
**Demo:** Fixtures: two-ship head-on contested, three-ship contested, two-ship swap, off-map bear-off filtered. Collisions stop both ships; fouling state set per 50% rule (seeded).

## Must-Haves

- Fixtures: two-ship head-on contested, three-ship contested, two-ship swap, off-map bear-off filtered. Collisions stop both ships; fouling state set per 50% rule (seeded). All 259 tests pass.

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: Contested hex detection and DRM-based resolution** `est:2h`
  Implement _resolve_contested_hex() with N-way contest support, d6 roll with DRM modifiers (crew quality, ship class, MP advantage), and tiebreaking. Log CONTESTED_HEX_ROLL events.
  - Files: `scripts/server/movement_resolver.gd`, `scripts/server/movement_types.gd`
  - Verify: Tests: test_two_ships_head_on_contested_hex, test_three_ship_contested_hex, test_contest_drm_crew_quality_advantage, test_contest_drm_class_advantage, test_contest_drm_more_mp_advantage all pass

- [x] **T02: Bearing off with pivot legality and collision fallback** `est:2h`
  Implement _resolve_collision_or_bearoff() for contest losers: check bearing-off probability from DataManager, verify pivot legality via min-forward-hexes rule, fall back to collision on denied pivot or failed roll.
  - Files: `scripts/server/movement_resolver.gd`, `data/rules/bearing_off_table.json`
  - Verify: Tests: test_bearing_off_uses_crew_quality_and_maneuverability, test_bearing_off_pivot_denied_no_forward_hexes, test_bearing_off_pivot_legal_with_enough_forward_hexes, test_bearing_off_pivot_legal_roll_fails_causes_collision all pass

- [x] **T03: Collision mechanics and fouling roll** `est:1h`
  Implement _apply_collision() with rigging damage by sail state (FS=2R, MS=4R, PS=6R, NS=0R), 50% fouling roll excluding dismasted ships, and apply_results() to propagate collision/fouling state to ShipState.
  - Files: `scripts/server/movement_resolver.gd`, `scripts/server/movement_types.gd`
  - Verify: Tests: test_collision_stops_both_ships, test_collision_rigging_loss_by_sail_state, test_dismasted_ships_cannot_foul, test_fouling_roll_50_percent, test_apply_results_sets_collision_flags, test_apply_results_applies_rigging_damage all pass

## Files Likely Touched

- scripts/server/movement_resolver.gd
- scripts/server/movement_types.gd
- data/rules/bearing_off_table.json
