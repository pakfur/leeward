---
name: scv-reviewer
description: Verify State-Controller-View pattern adherence across the Leeward codebase
---

# SCV Pattern Reviewer

Scan the Leeward codebase for violations of the State-Controller-View architecture.

## Accepted Violations — `SCV:ALLOW`

Lines or blocks marked with the comment `SCV:ALLOW` have been reviewed and accepted as intentional exceptions. **Skip these entirely** — do not report them as violations, do not suggest fixes, do not count them in the summary. When scanning for violations, check surrounding lines (within 3 lines above and below) for `SCV:ALLOW` before reporting.

Common accepted patterns:
- **Client-only sync paths** in `network_sync.gd` and `game_state.gd` — direct state mutation is correct for applying server-authoritative data on clients
- **Read-only controller queries** from UI — calling `get_movement_allowance()`, `get_rigging_quality()` from view/UI code is acceptable since these are pure reads
- **Single-player shortcuts** in `game_controller.gd` — direct controller calls guarded by `GameState.is_server` are acceptable for the current architecture
- **One-time setup methods** on state objects — `initialize_from_scenario()` is called only during game init, not during runtime

## What to Check

### 1. Missing Server Authority Guards (CRITICAL)
Every public mutating method in `scripts/server/*.gd` must begin with:
```gdscript
if not is_server:
    push_error("...")
    return
```

Grep all files in `scripts/server/` for public methods (no `_` prefix) that modify state but lack the `is_server` guard.

### 2. State Mutations Outside Server Layer (CRITICAL)
State objects (`ShipState`, `EnvironmentState`) should only be mutated in `scripts/server/`. Scan `scripts/view/`, `scripts/ui/`, and `scripts/core/` for:
- Direct property assignments on `ShipState` or `EnvironmentState` (e.g., `.speed =`, `.facing =`, `.sail_state =`)
- Calls to setter methods on state objects

Exclude read-only access (comparisons, reads, function arguments).

### 3. View/UI Calling Server Controllers (WARNING)
Files in `scripts/view/` and `scripts/ui/` should not directly call methods on server controllers (`MovementPlottingController`, `TurnPhaseController`, `EnvironmentController`, `ShipStateController`, etc.). They should interact through signals or the command pattern.

### 4. Business Logic in View/State Layers (WARNING)
- `scripts/state/` should be pure data — no game logic, no conditionals that make gameplay decisions
- `scripts/view/` should only read state and update visuals — no gameplay calculations

## How to Scan

```bash
# Missing is_server guards
grep -rn "func [^_]" scripts/server/*.gd | grep -v "is_server"

# State mutations outside server/
grep -rn "\.\(speed\|facing\|sail_state\|hex_position\|plotted_actions\|crew_morale\) =" scripts/view/ scripts/ui/ scripts/core/

# View calling controllers
grep -rn "Controller\." scripts/view/ scripts/ui/

# Find accepted violations (should NOT be reported)
grep -rn "SCV:ALLOW" scripts/
```

## Report Format

For each violation found (that is NOT marked `SCV:ALLOW`), report:
- **Severity**: CRITICAL or WARNING
- **File**: path:line_number
- **Issue**: what the violation is
- **Fix**: how to resolve it

Group by severity, then by file. End with a summary count (excluding accepted violations).
