---
name: phase-implementer
description: Use whenever the user asks to implement, fill in, wire up, or finish one of the stubbed turn phases in TurnPhaseController — including any mention of COMBAT_RESOLUTION, DRIFT_CALCULATION, STATUS_ADJUSTMENT, MORALE_CHECK, MESSAGE_DELIVERY, POST_COMBAT, or END_TURN by name. Also triggers on phrases like "implement the morale check", "add the combat phase", "finish the drift calculation", or anything that means turning a stubbed `_enter_*_phase()` into real logic. Codifies the server-authoritative State-Controller-View pattern this project uses: where the phase method goes, when to extract a dedicated controller, how to wire signals, how state-history snapshots get captured automatically, and how to test it. Use this even when the user only describes the goal ("ships should check morale at the end of combat") and doesn't mention the pattern.
---

# phase-implementer

This skill codifies how a new turn phase is implemented in this codebase. It's based on the existing implemented phases (`ENVIRONMENT`, `PLANNING`, `MOVEMENT_RESOLUTION`) — follow their precedent rather than inventing new patterns.

## The 10-phase cycle and current status

| Phase | Status | Pattern used |
|-------|--------|--------------|
| `SETUP` | implemented | inline (init only) |
| `ENVIRONMENT` | implemented | controller (`EnvironmentController`) |
| `PLANNING` | implemented | controller (`MovementPlottingController`) + waits for player input |
| `MOVEMENT_RESOLUTION` | implemented | controller (`MovementResolver`) + async (waits for view playback) |
| `COMBAT_RESOLUTION` | **stub** | — |
| `DRIFT_CALCULATION` | **stub** | — |
| `STATUS_ADJUSTMENT` | **stub** | — |
| `MORALE_CHECK` | **stub** | — |
| `MESSAGE_DELIVERY` | **stub** | — |
| `POST_COMBAT` | **stub** | — |
| `END_TURN` | **stub** | — |

The phase you're implementing is already in the `GamePhase` enum (`scripts/server/turn_phase_controller.gd:10-22`) and already has a `_enter_<phase>_phase()` stub. You're filling the stub in, not adding a phase.

## Decision: inline logic or dedicated controller?

| Use inline (in `TurnPhaseController._enter_<phase>_phase()`) | Use a dedicated `<Phase>Controller` in `scripts/server/` |
|---|---|
| One or two state mutations | Multi-step resolution with helper methods |
| No RNG | Uses RNG |
| No new persistent state | Holds intermediate state across method calls |
| `END_TURN` victory check | `COMBAT_RESOLUTION`, `DRIFT_CALCULATION`, `MORALE_CHECK` |

If unsure, start inline. Extract a controller when the inline method exceeds ~30 lines or you need test seams.

## Anatomy of a phase

### 1. The phase method in `TurnPhaseController`

The skeleton already exists (e.g. `_enter_morale_check_phase()` at `scripts/server/turn_phase_controller.gd:194`). Replace the `# TODO` and the trailing `advance_phase()` with real logic:

```gdscript
func _enter_morale_check_phase() -> void:
    """SERVER ONLY: Enter morale check phase"""
    current_phase = GamePhase.MORALE_CHECK
    phase_changed.emit(current_phase)
    Trace.trace_log("TurnPhase", "Phase: MORALE_CHECK")

    # --- real logic goes here (inline OR delegate to controller) ---
    if game_state.morale_controller:
        game_state.morale_controller.run_morale_checks(game_state.get_all_ships())

    advance_phase()
```

Three invariants every phase method must preserve:
- **`current_phase = GamePhase.<NAME>`** before doing work — UIs and state-history snapshots depend on this being set first.
- **`phase_changed.emit(current_phase)`** so listeners (UI, view controllers, `EnvironmentController._on_phase_changed`) react.
- **`Trace.trace_log("TurnPhase", "Phase: <NAME>")`** — never raw `print()` (a hook blocks it).

### 2. Auto-advance vs. async completion

Two completion shapes:

- **Synchronous**: do the work, call `advance_phase()` at the bottom of the method. Used by `_enter_environment_phase()`.
- **Asynchronous**: do not call `advance_phase()`; emit a signal (e.g. `resolution_log_ready`) and wait for an external callback. The view layer calls back into `TurnPhaseController` when ready. `_enter_movement_resolution_phase()` + `on_playback_completed()` is the reference (`scripts/server/turn_phase_controller.gd:139-168`).

Pick async only if the phase needs the view to animate before mutations finalize. Combat resolution likely needs async (gunfire animations); morale checks don't.

### 3. The dedicated controller pattern (if needed)

Mirror `EnvironmentController` (`scripts/server/environment_controller.gd`):

```gdscript
class_name MoraleController
extends Node
## Resolves morale checks for all ships at the MORALE_CHECK phase.

signal morale_resolved()

var is_server: bool = true
var game_state: Node = null

func _init(state: Node = null) -> void:
    game_state = state if state else GameState

func run_morale_checks(ships: Array[ShipState]) -> void:
    """SERVER ONLY: Mutate each ship's morale based on current state."""
    if not is_server:
        return

    for ship in ships:
        # ... compute new morale, possibly using game_state.rng for determinism
        pass

    morale_resolved.emit()
```

Then wire it into `GameState._initialize_server_controllers()` (`scripts/autoload/game_state.gd:69-103`) — instantiate, `add_child()`, and store on `game_state` so the phase method can reach it.

### 4. Server-authority guard

Every mutating method on the controller must early-return on the client:

```gdscript
if not is_server:
    return  # or push_error() + return, matching neighbouring code
```

This is non-negotiable. Clients are read-only observers; mutations on clients diverge from the server's authoritative state.

### 5. RNG — always go through `game_state.rng`

If the phase uses randomness, use `game_state.rng` (a scenario-seeded `RandomNumberGenerator` shared across all controllers). Never create a fresh RNG — that breaks determinism and replay/test seeds. `EnvironmentController.tick_environment()` is the model.

### 6. State-history snapshots are automatic — don't do them yourself

`GameState._on_server_turn_changed` (`scripts/autoload/game_state.gd:142-153`) snapshots environment + every ship's state on each turn rollover. Phase methods do **not** call `save_*_snapshot()` themselves. If a phase needs to read a previous turn's state, use `game_state.get_environment_at_turn(n)` or `game_state.get_ship_at_turn(ship_id, n)`.

## The test

Mirror `test/unit/test_data_manager_movement.gd` style. New file at `test/unit/test_<phase_or_controller>.gd`:

```gdscript
extends GutTest
## Tests for MoraleController phase logic.

var morale: MoraleController
var state: Node

func before_each() -> void:
    state = autofree(Node.new())
    state.rng = RandomNumberGenerator.new()
    state.rng.seed = 42
    morale = autofree(MoraleController.new(state))

func test_low_hull_lowers_morale() -> void:
    var ship = _make_ship(hull_pct = 0.2, current_morale = 5)
    morale.run_morale_checks([ship])
    assert_lt(ship.crew_morale, 5, "Low hull integrity should drop morale")

func test_is_server_false_skips_mutations() -> void:
    morale.is_server = false
    var ship = _make_ship(hull_pct = 0.2, current_morale = 5)
    morale.run_morale_checks([ship])
    assert_eq(ship.crew_morale, 5, "Client-side controller must not mutate")
```

Run with `make test-file F=test/unit/test_<name>.gd` while iterating, then `make test` before committing.

Always include the `is_server = false` test — the guard is easy to forget and silently dangerous.

## Checklist before declaring done

- [ ] `_enter_<phase>_phase()` sets `current_phase`, emits `phase_changed`, logs via `Trace`, and either calls `advance_phase()` or sets up an async completion path
- [ ] Mutation happens server-side only (inline `if not is_server: return` guard, or via a controller that has one)
- [ ] RNG (if used) goes through `game_state.rng`
- [ ] If a new controller was added: instantiated and added to the tree in `GameState._initialize_server_controllers()`, exposed as a field on `game_state`
- [ ] New tests under `test/unit/test_*.gd`, including the `is_server = false` regression
- [ ] `make test` passes
- [ ] No raw `print()` introduced (the print-guard hook will block it anyway)
