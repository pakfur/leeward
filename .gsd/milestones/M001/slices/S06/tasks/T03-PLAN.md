---
estimated_steps: 14
estimated_files: 1
skills_used: []
---

# T03: Add fixture tests for MovementResolver: tacking, in-irons, normal movement, determinism

Create test/unit/test_movement_resolver.gd with fixture-driven tests covering all single-ship resolution paths. Use MockGameState with seeded rng (RandomNumberGenerator) to control roll outcomes.

Required tests:
1. **test_normal_movement_resolves_full_path** — ship with 3-step forward path resolves all 3 impulses, final position updated.
2. **test_normal_movement_updates_ship_state** — after resolve, ship_state.hex_position, facing, and speed reflect final path position.
3. **test_tack_success_continues_path** — seed rng so roll < threshold. Ship with tacking path completes full plotted path past L.
4. **test_tack_failure_immobilizes_at_L** — seed rng so roll > threshold. Ship stops at L-facing hex, immobilized=true, speed=0.
5. **test_in_irons_escape_success** — ship at speed=0, facing L, seeded roll succeeds. Ship proceeds with plotted path.
6. **test_in_irons_escape_failure** — ship at speed=0, facing L, seeded roll fails. Ship remains at same hex, immobilized.
7. **test_ma_exhaustion_stops_at_last_step** — path with exactly MA steps, resolver walks all and stops.
8. **test_resolution_log_structure** — verify ResolutionLog has correct impulse count, ship_ids, event types.
9. **test_tack_drm_rigging_damage** — ship with damaged rigging gets lower effective threshold.
10. **test_determinism_same_seed_same_log** — run resolve twice with same seed + same plots, assert ResolutionLog equality.

MockGameState pattern: same as test_movement_tacking.gd — extends Node, has environment and rng properties. Ships created via Ship.from_dict + ShipState with plotted_actions.movement populated as Array of PlotStep.to_dict().

All tests run via `make test`.

## Inputs

- `scripts/server/movement_resolver.gd`
- `scripts/server/movement_types.gd`
- `scripts/state/ship_state.gd`
- `scripts/autoload/data_manager.gd`
- `test/unit/test_movement_tacking.gd`
- `test/unit/test_movement_validator.gd`

## Expected Output

- `test/unit/test_movement_resolver.gd`

## Verification

make test-file F=test/unit/test_movement_resolver.gd && make test
