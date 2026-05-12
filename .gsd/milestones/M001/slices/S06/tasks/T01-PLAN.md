---
estimated_steps: 16
estimated_files: 2
skills_used: []
---

# T01: Define ResolutionLog data classes and MovementResolver scaffold

Add ResolutionLog, ImpulseRecord, and ShipImpulseEvent data classes to movement_types.gd. Create scripts/server/movement_resolver.gd with the public API `resolve(ships_with_plots: Array[ShipState], game_state: Node) -> ResolutionLog`. The resolver reads each ship's plotted_actions.movement (Array of PlotStep dicts), reconstructs the PlotStep path, and walks it impulse-by-impulse (1 step per impulse). For this task, implement the basic impulse loop for normal (non-tacking, non-in-irons) movement only — each impulse advances the ship one PlotStep and records a ShipImpulseEvent in the ImpulseRecord. After all impulses, set the ship's final hex_position, facing, and speed on ShipState. Trace.trace_log every impulse advance and resolution start/complete.

ResolutionLog shape:
- impulses: Array[ImpulseRecord] — one per impulse tick
- ships_resolved: Array[String] — ship_ids
- total_impulses: int

ImpulseRecord shape:
- impulse_number: int
- events: Array[ShipImpulseEvent]

ShipImpulseEvent shape:
- ship_id: String
- event_type: String — 'move', 'tack_roll', 'in_irons_roll', 'immobilized', 'tack_success', 'tack_failure', 'in_irons_escape_success', 'in_irons_escape_failure'
- from_hex: Vector2i
- to_hex: Vector2i
- facing: int
- details: Dictionary — roll value, threshold, DRMs, etc.

The resolver must accept a game_state Node (for rng access) and use PlotStep.from_dict() to reconstruct steps from plotted_actions.movement.

## Inputs

- `scripts/server/movement_types.gd`
- `scripts/state/ship_state.gd`
- `scripts/autoload/game_state.gd`
- `scripts/autoload/trace.gd`

## Expected Output

- `scripts/server/movement_resolver.gd`
- `scripts/server/movement_types.gd`

## Verification

make test (all existing tests pass, no regressions) && grep -q 'class ResolutionLog' scripts/server/movement_types.gd && grep -q 'func resolve' scripts/server/movement_resolver.gd
