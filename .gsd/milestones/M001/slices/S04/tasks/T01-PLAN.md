---
estimated_steps: 1
estimated_files: 5
skills_used: []
---

# T01: End Planning button, submission tracking, re-plot support

Add EndPlanningButton with N/M counter, track submitted ships with visual feedback (green tint + [OK]), support re-plotting submitted ships, wire End Planning to phase controller, replace print() with Trace.trace_log(), fix 3 pre-existing crew_count test assertions.

## Inputs

- `S03 MovementValidator + plotting session`
- `planning_phase_ui.tscn scene`
- `ship_list_item.gd component`

## Expected Output

- `EndPlanningButton in scene tree`
- `submitted_ships tracking in PlanningPhaseUI`
- `re-plot clears old submission`
- `Trace.trace_log replaces print`

## Verification

make test passes all 214 tests
