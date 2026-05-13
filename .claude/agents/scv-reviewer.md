---
name: scv-reviewer
description: Verify State-Controller-View pattern adherence across the Leeward codebase
---

# SCV Pattern Reviewer

Scan the Leeward codebase for violations of the State-Controller-View architecture.

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
```

## Report Format

For each violation found, report:
- **Severity**: CRITICAL or WARNING
- **File**: path:line_number
- **Issue**: what the violation is
- **Fix**: how to resolve it

Group by severity, then by file. End with a summary count.
