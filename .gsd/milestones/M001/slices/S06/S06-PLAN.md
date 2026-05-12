# S06: MovementResolver single-ship: impulse loop + tacking roll + in-irons escape

**Goal:** Build MovementResolver for single-ship resolution: impulse-by-impulse loop consuming submitted plots, tacking roll (success → continue, failure → immobilized at L), in-irons escape roll, ResolutionLog output, and determinism test. After this slice, the resolver is a standalone pure-logic class with full test coverage that S07 extends to multi-ship contests.
**Demo:** Fixtures: tack success (ship continues plot), tack failure (ship immobilized facing L), in-irons escape success/failure. Determinism test passes for single-ship plots.

## Must-Haves

- 1. `MovementResolver.resolve(ships_with_plots: Array[ShipState]) -> ResolutionLog` exists and processes single-ship plots impulse-by-impulse (1 MP per impulse).
- 2. ResolutionLog data classes defined in movement_types.gd: ResolutionLog, ImpulseRecord, ShipImpulseEvent (move, tack_roll, in_irons_roll, immobilized).
- 3. Tacking roll: when is_tacking_attempt is true on submitted plot, resolver rolls via GameState.rng against DataManager.get_tacking_percent + DRM. Success → ship continues plotted path past the tack. Failure → ship stops at L facing, immobilized for this turn.
- 4. In-irons escape: ship at speed=0 facing L at start of resolution gets a roll. Success → ship may proceed. Failure → remains immobilized.
- 5. Fixture tests: tack success, tack failure, in-irons escape success, in-irons escape failure, normal movement (no tack), MA exhaustion mid-path.
- 6. Determinism test: same seed + same plots → identical ResolutionLog (run twice, diff).
- 7. All existing tests still pass (`make test` green).
- 8. Trace.trace_log on every resolver event (tack roll, in-irons roll, impulse advance, immobilization).

## Proof Level

- This slice proves: contract — tests exercise the resolver with mock game state and seeded RNG; no runtime scene required

## Integration Closure

Upstream: consumes ShipState.plotted_actions.movement (Array of PlotStep dicts from MovementPlottingController), MovementPlottingSession.is_tacking_attempt flag (stored on ShipState.tacking), GameState.rng, DataManager.get_tacking_percent. New wiring: none in this slice — MovementResolver is standalone. S07 extends to multi-ship, S09 wires to playback controller, S10 wires into turn phase controller.

## Verification

- Trace.trace_log("MovementResolver", ...) on: impulse start, ship advance, tack roll (inputs + result), in-irons roll (inputs + result), immobilization, resolution complete. ResolutionLog persisted on GameState for current turn (cleared at END_TURN per R012).

## Tasks

- [x] **T01: Define ResolutionLog data classes and MovementResolver scaffold** `est:1h30m`
  Add ResolutionLog, ImpulseRecord, and ShipImpulseEvent data classes to movement_types.gd. Create scripts/server/movement_resolver.gd with the public API `resolve(ships_with_plots: Array[ShipState], game_state: Node) -> ResolutionLog`. The resolver reads each ship's plotted_actions.movement (Array of PlotStep dicts), reconstructs the PlotStep path, and walks it impulse-by-impulse (1 step per impulse). For this task, implement the basic impulse loop for normal (non-tacking, non-in-irons) movement only — each impulse advances the ship one PlotStep and records a ShipImpulseEvent in the ImpulseRecord. After all impulses, set the ship's final hex_position, facing, and speed on ShipState. Trace.trace_log every impulse advance and resolution start/complete.
  - Files: `scripts/server/movement_types.gd`, `scripts/server/movement_resolver.gd`
  - Verify: make test (all existing tests pass, no regressions) && grep -q 'class ResolutionLog' scripts/server/movement_types.gd && grep -q 'func resolve' scripts/server/movement_resolver.gd

- [x] **T02: Implement tacking roll and in-irons escape in MovementResolver** `est:1h30m`
  Extend MovementResolver to handle tacking and in-irons cases before the impulse loop.
  - Files: `scripts/server/movement_resolver.gd`
  - Verify: make test (all existing tests pass) && grep -q 'tack_roll\|tack_success\|tack_failure' scripts/server/movement_resolver.gd && grep -q 'in_irons' scripts/server/movement_resolver.gd

- [x] **T03: Add fixture tests for MovementResolver: tacking, in-irons, normal movement, determinism** `est:2h`
  Create test/unit/test_movement_resolver.gd with fixture-driven tests covering all single-ship resolution paths. Use MockGameState with seeded rng (RandomNumberGenerator) to control roll outcomes.
  - Files: `test/unit/test_movement_resolver.gd`
  - Verify: make test-file F=test/unit/test_movement_resolver.gd && make test

## Files Likely Touched

- scripts/server/movement_types.gd
- scripts/server/movement_resolver.gd
- test/unit/test_movement_resolver.gd
