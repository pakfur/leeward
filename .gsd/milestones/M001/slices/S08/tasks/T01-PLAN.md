---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T01: StubAI class with plotting protocol integration

Implement StubAI class that identifies non-player ships (player_id != 0), calls handle_start_plotting/handle_select_hex/handle_submit_movement on MovementPlottingController for each, with forward and hold strategies.

## Inputs

- `MovementPlottingController API`
- `MovementTypes response classes`

## Expected Output

- `scripts/server/stub_ai.gd with plot_all_ai_ships(), _get_ai_ships(), _plot_ship(), _strategy_forward()`

## Verification

make test-file F=test/unit/test_stub_ai.gd passes all tests
