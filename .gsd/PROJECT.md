# Project

## What This Is

Leeward is a turn-based naval combat game in Godot 4, set in the Napoleonic era (1790–1814). Modeled on the *Close Action* family of tabletop wargames, it runs server-authoritative simultaneous-resolution tactical combat on an isometric hex grid. The current build has a State-Controller-View architecture, a 10-phase turn skeleton, JSON-driven rule tables (movement allowance, tacking, turning, speed change, ships, bearing-off), an ocean shader, a planning UI, and GUT-based unit tests for the data manager. The full game vision extends to career/progression (Naval Officer, Privateer, Pirate), scenarios beyond test fleets, AI opponents, and eventually networked multiplayer — but those are explicitly later milestones.

## Core Value

The tactical movement-plotting loop: a player working the weather gauge, managing MA economics, gambling on tacking, and contesting hexes with the enemy. Everything else in the game attaches to this core. If scope must shrink, this is what must survive.

## Project Shape

- **Complexity:** complex
- **Why:** Multi-milestone vision (combat, AI, career/progression, multiplayer); deep rules surface even in the first milestone; existing partial implementation with mock validators that must be replaced; server-authoritative architecture with future networking implications.

## Current State

- Scenes: splash → scenario selection → main game with a hex grid, ocean shader, ships, planning panel, minimap, wind compass, developer UI (F12).
- State layer: `Ship` (immutable identity + type), `ShipState` (mutable state), `EnvironmentState`.
- Controllers (server-authoritative): `TurnPhaseController`, `EnvironmentController`, `ShipStateController`, `CommandValidator`, `NetworkSync`, `MovementPlottingController` (protocol + sessions). `MovementValidator` is a **mock** — every rule is stub logic.
- Phases implemented: ENVIRONMENT (wind ticking with RNG), PLANNING (UI present but plotting flow incomplete), MOVEMENT_RESOLUTION (sets phase, does nothing). Other phases are stubs.
- Tests: `test/unit/test_data_manager_*` and `test_trace` via GUT 9.5.0; `make test` available.
- Two test scenarios (`test_basic.json`, `test_fleet.json`).
- `godot_mcp` addon for editor integration.

## Architecture / Key Patterns

- **State-Controller-View (SCV):** state is data; controllers own all mutations and guard with `if not is_server`; view is presentation only.
- **Autoload singletons:** `GameState` (state container + controller owner), `DataManager` (loads/caches JSON), `Trace` (structured logging).
- **Hex grid:** axial coordinates, pointy-top, direction 0=E.
- **Rule-table boundary:** every JSON rule lookup goes through a typed `DataManager.get_*` function with `assert()` parameter validation, modeled on `get_movement_allowance(...)`.
- **Movement plotting protocol:** session-based async with versioning, idempotency, and RPC scaffolding (see `docs/02.1-movement-protocol.md`). Sessions live server-side; client/UI is read-only on state and operates via protocol messages.
- **Server authority enforced:** every mutating function in `scripts/server/` checks `is_server` before acting.

## Capability Contract

See `.gsd/REQUIREMENTS.md` for the explicit capability contract, requirement status, and coverage mapping.

## Milestone Sequence

- [ ] M001: Movement Plotting (Complete) — Plot fleet movement under all documented rules; resolve impulse-by-impulse with contested-hex / bear-off / collision / fouling; visual playback; 5-turn sustained loop.
