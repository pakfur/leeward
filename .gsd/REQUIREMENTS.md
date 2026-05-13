# Requirements

This file is the explicit capability and coverage contract for the project.

## Active

### R001 — Player can plot complete movement for every owned ship per turn
- Class: primary-user-loop
- Status: active
- Description: Player can plot complete movement for every owned ship per turn
- Why it matters: The fleet-level plotting workflow is the player's primary interaction in the tactical loop. Without it, the game has no PLANNING phase experience.
- Source: user
- Primary owning slice: M001/S04
- Validation: unmapped
- Notes: Per-ship session, per-ship submit, re-plot allowed before End Planning closes the phase.

### R002 — All docs/02-game-rules.md movement rules enforced at plot time
- Class: core-capability
- Status: active
- Description: All docs/02-game-rules.md movement rules enforced at plot time
- Why it matters: A plot that violates rules cannot be resolved correctly. Plot-time enforcement also drives the UI — valid next hexes, remaining MA, tacking probability — and gives the player accurate tactical information.
- Source: user
- Primary owning slice: M001/S03
- Validation: unmapped
- Notes: MA recalculation after every pivot; acceleration/deceleration bounds against last-turn speed; turning-table min-forward-hexes-between-pivots; pivot caps (max 2/turn, free pivot at MA=0); luffing rule (pivot to L ends forward movement); in-irons handling at plot start; fast-tack +1 MA bonus; map bounds.

### R003 — All docs/02.2 contested-hex / bear-off / collision / fouling rules enforced at resolution
- Class: core-capability
- Status: active
- Description: All docs/02.2 contested-hex / bear-off / collision / fouling rules enforced at resolution
- Why it matters: Simultaneous resolution is the core game premise. Without contested-hex math, fleet engagements have no real consequence and the tactical plotting loses meaning.
- Source: user
- Primary owning slice: M001/S07
- Validation: unmapped
- Notes: Contested-hex DRMs (crew quality, MPs used, ship class), surrender choice, bear-off attempt against bearing_off_table.json, collision stoppage, 50% fouling rule. Ramming damage values deferred.

### R004 — Impulse-by-impulse resolution model: 1 MP per ship per impulse, contests checked per impulse
- Class: core-capability
- Status: active
- Description: Impulse-by-impulse resolution model: 1 MP per ship per impulse, contests checked per impulse
- Why it matters: Only granularity that makes contested-hex rules work in fleet engagements. Full-plot-then-contest breaks pass-through semantics between adjacent ships.
- Source: user
- Primary owning slice: M001/S06
- Validation: unmapped
- Notes: Resolver advances every ship 1 MP at a time, resolves contests, applies bear-off/collision results, advances to next impulse.

### R005 — Stub-AI provides plotted moves for non-player ships through the real plotting protocol
- Class: core-capability
- Status: active
- Description: Stub-AI provides plotted moves for non-player ships through the real plotting protocol
- Why it matters: The resolver needs plots from every ship. Driving the AI through the real protocol rule-validates its plots and exercises the full plotting stack.
- Source: user
- Primary owning slice: M001/S08
- Validation: unmapped
- Notes: player_id==0 is human, others are stub-AI controlled. Strategies are scenario-configurable. Stub-AI also provides programmatic answers to mid-resolution prompts (no surrender, no bear-off).

### R006 — Visual playback animates the resolved movement hex-by-hex
- Class: primary-user-loop
- Status: active
- Description: Visual playback animates the resolved movement hex-by-hex
- Why it matters: Simultaneous-resolution drama is a primary game appeal. Players need to see the resolution unfold, not just see ships teleport to final positions.
- Source: user
- Primary owning slice: M001/S09
- Validation: unmapped
- Notes: Linear interpolation between hex centers, ~200ms per hex per ship, concurrent for ships in the same impulse. Functional-not-pretty in M001 (no easing, wakes, or sail animation).

### R007 — Tacking attempt detected at plot time; success probability shown live in UI
- Class: differentiator
- Status: active
- Description: Tacking attempt detected at plot time; success probability shown live in UI
- Why it matters: Tacking is a key tactical gamble in this game family. Showing the player the success probability while plotting (informed by current DRMs) is the UX moment that distinguishes a deep simulation from a clicker.
- Source: user
- Primary owning slice: M001/S05
- Validation: unmapped
- Notes: is_tacking_attempt flag lives on the plotting session and is recomputed on every step + undo. Probability from tacking_table.json + DRMs in docs/02-game-rules.md §2.1.

### R008 — Single seeded RNG on GameState; scenario requires int seed (-1 = generate fresh per game)
- Class: constraint
- Status: active
- Description: Single seeded RNG on GameState; scenario requires int seed (-1 = generate fresh per game)
- Why it matters: Deterministic replay is required for resolver tests (determinism test, fixture scenarios). A single seeded RNG converges existing fragmentation (EnvironmentController has its own today).
- Source: collaborative
- Primary owning slice: M001/S02
- Validation: unmapped
- Notes: Missing seed in scenario is a hard error. seed:-1 is the convention for "fresh seed each game"; the generated value is trace-logged. EnvironmentController migrates to consume GameState.rng.

### R009 — All JSON rule-table lookups go through DataManager.get_* with assert() parameter validation
- Class: constraint
- Status: active
- Description: All JSON rule-table lookups go through DataManager.get_* with assert() parameter validation
- Why it matters: Single source of truth for rule lookups, consistent style, catches bad parameters fast, makes tables testable in isolation under test/unit/test_data_manager_*.gd.
- Source: user
- Primary owning slice: M001/S01
- Validation: unmapped
- Notes: Pattern: load_<table>_table() + get_<table>(typed params with assert) + test_data_manager_<table>.gd. Modeled on load_movement_allowance_table() / get_movement_allowance(). Any missing wrapper must be added before the consumer is written. First identified gap: get_bearing_off_probability.

### R010 — Map bounds enforced — no off-map plotting
- Class: core-capability
- Status: active
- Description: Map bounds enforced — no off-map plotting
- Why it matters: Open water only in M001, but scenarios declare a finite map size. Plot-time enforcement prevents the resolver from ever seeing off-map paths.
- Source: user
- Primary owning slice: M001/S03
- Validation: unmapped
- Notes: Validator filters off-map options from valid_next_hexes. Bear-off direction options also filtered.

### R011 — Per-ship submit; explicit End Planning; re-plot allowed before phase closes
- Class: primary-user-loop
- Status: active
- Description: Per-ship submit; explicit End Planning; re-plot allowed before phase closes
- Why it matters: Matches the existing controller protocol and gives the player full control: they can iterate on plots until the whole fleet feels right, then commit.
- Source: user
- Primary owning slice: M001/S04
- Validation: unmapped
- Notes: End Planning enables only when every player-0 ship has a submitted plot. Submitted plots can be reopened and replaced before End Planning is pressed.

### R012 — Trace observability: validator rule-blocks and every resolver event logged
- Class: failure-visibility
- Status: active
- Description: Trace observability: validator rule-blocks and every resolver event logged
- Why it matters: Agent-first observability. When something goes wrong in a plotting session or a resolution, the logs must answer "which rule blocked which decision against which state."
- Source: inferred
- Primary owning slice: M001/S03
- Supporting slices: M001/S06, M001/S07
- Validation: unmapped
- Notes: No silent fallbacks. Every rule-blocking validator decision and every contest/tack/bear-off/collision resolver event goes through Trace with the relevant ship state and table inputs. ResolutionLog persisted on GameState for current turn; cleared at END_TURN. Stub-AI decisions logged.

### R013 — Deterministic resolution: same seed + same plots → identical ResolutionLog
- Class: quality-attribute
- Status: active
- Description: Deterministic resolution: same seed + same plots → identical ResolutionLog
- Why it matters: Tests must be reproducible. Determinism also enables future replay features and bug-reporting workflows.
- Source: collaborative
- Primary owning slice: M001/S06
- Validation: unmapped
- Notes: Validated by an explicit determinism test that runs the same fixture twice with the same seed and diffs the ResolutionLog.

### R014 — Game loop sustains 5+ turns of plotting + resolution without errors
- Class: quality-attribute
- Status: active
- Description: Game loop sustains 5+ turns of plotting + resolution without errors
- Why it matters: Single-turn correctness is necessary but not sufficient. The state, RNG, sessions, ResolutionLog, and ship snapshots must roll cleanly from turn to turn.
- Source: user
- Primary owning slice: M001/S10
- Validation: unmapped
- Notes: Manual playtest of test_fleet.json over 5 turns with no console errors and visible playback per turn.

### R015 — Plotting latency under 50ms per protocol request on local server
- Class: quality-attribute
- Status: active
- Description: Plotting latency under 50ms per protocol request on local server
- Why it matters: Plotting is iterative — every hex click, undo, and submit must feel instant. Sluggish plotting kills the tactical-thinking flow.
- Source: user
- Primary owning slice: M001/S04
- Validation: unmapped
- Notes: Measured for SELECT_HEX, UNDO, SUBMIT_MOVEMENT. Trace timing if needed.

### R016 — Test coverage: unit tests for rule math, 12-scenario integration fixtures, determinism test
- Class: quality-attribute
- Status: active
- Description: Test coverage: unit tests for rule math, 12-scenario integration fixtures, determinism test
- Why it matters: Without explicit coverage commitments, "complete movement plotting" silently regresses. Fixtures double as regression bedrock for subsequent milestones.
- Source: user
- Primary owning slice: M001/S03
- Supporting slices: M001/S07, M001/S06
- Validation: unmapped
- Notes: Unit tests: MA recalc after pivot, pivot cap, accel/decel bounds, contested-hex DRM math, bear-off probability lookup, tacking probability lookup. Integration fixtures (12): MA exhaustion, turn-then-forward, tack success, tack failure, fast-tack bonus, in-irons escape success/failure, two-ship head-on, three-ship contested, two-ship swap, off-map blocked, off-map bear-off filtered, legal stub-AI round-trip. All pass via `make test`.

## Validated

## Deferred

### R017 — 2-hex ship geometry restored (frigates and SOL positioned on hex edges)
- Class: core-capability
- Status: deferred
- Description: 2-hex ship geometry restored (frigates and SOL positioned on hex edges)
- Why it matters: Historical authenticity and visual fidelity; differentiator for the game family.
- Source: user
- Notes: M001 treats all ships as 1-hex. get_ship_size() is intentionally hardcoded to 1.

### R018 — Terrain support: shoals, reefs, land, ports
- Class: core-capability
- Status: deferred
- Description: Terrain support: shoals, reefs, land, ports
- Why it matters: Scenarios require terrain variation for tactical depth, mission objectives, and visual interest.
- Source: user
- Notes: M001 is open water only. Terrain becomes its own milestone because it touches pathfinding, scenario schema, art, and tile editing.

### R019 — Networked multiplayer for plotting and resolution
- Class: integration
- Status: deferred
- Description: Networked multiplayer for plotting and resolution
- Why it matters: Multiplayer is in the project vision. The plotting controller is already RPC-ready.
- Source: user
- Notes: M001 is single-machine. RPC scaffolding stays in place but isn't exercised.

### R020 — Hot-seat UI for two human players on one machine
- Class: primary-user-loop
- Status: deferred
- Description: Hot-seat UI for two human players on one machine
- Why it matters: Optional alternative to stub-AI for local 2-player play.
- Source: inferred
- Notes: M001 uses stub-AI; hot-seat would add player-handoff UI that doesn't advance the core proof.

### R021 — Anchoring action plotted and resolved
- Class: core-capability
- Status: deferred
- Description: Anchoring action plotted and resolved
- Why it matters: Per docs/02-game-rules.md §2.2.2, anchoring is part of the planning surface.
- Source: user
- Notes: Not required for the M001 movement-plotting demo.

### R022 — Towing mechanic
- Class: core-capability
- Status: deferred
- Description: Towing mechanic
- Why it matters: Per docs/02-game-rules.md §2.2.3, towing is part of the planning surface.
- Source: user
- Notes: Not required for the M001 movement-plotting demo. ShipState.towing flag exists but is unused in M001.

### R023 — Real AI with tactical decision-making
- Class: core-capability
- Status: deferred
- Description: Real AI with tactical decision-making
- Why it matters: Single-player skirmish and campaign modes require an AI that actually plays the game.
- Source: user
- Notes: M001 uses stub-AI with scripted strategies. Real AI is its own milestone.

### R024 — Save/load support mid-plot
- Class: continuity
- Status: deferred
- Description: Save/load support mid-plot
- Why it matters: A shipped game needs save/load. Mid-plot save is a power-user nicety.
- Source: inferred
- Notes: M001 does not persist plotting-session state across game restart.

## Out of Scope

### R025 — Combat resolution: gunnery, marine fire, boarding
- Class: core-capability
- Status: out-of-scope
- Description: Combat resolution: gunnery, marine fire, boarding
- Why it matters: Combat is the game's other half. Out of scope for M001, which is movement-only.
- Source: user
- Notes: Explicitly excluded from M001. Will become its own milestone (or multiple).

### R026 — All phases after MOVEMENT_RESOLUTION (drift, status, morale, message delivery, post-combat, striking, end-turn beyond loop closure)
- Class: core-capability
- Status: out-of-scope
- Description: All phases after MOVEMENT_RESOLUTION (drift, status, morale, message delivery, post-combat, striking, end-turn beyond loop closure)
- Why it matters: The turn-cycle is large; M001 deliberately stops at MOVEMENT_RESOLUTION and lets later phases pass through as stubs.
- Source: user
- Notes: END_TURN advances the turn counter so the loop closes, but no domain logic happens in these phases for M001.

### R027 — Ramming damage values applied to colliding ships
- Class: core-capability
- Status: out-of-scope
- Description: Ramming damage values applied to colliding ships
- Why it matters: Collisions stop both ships and set fouling state in M001, but the damage model is deferred with the rest of the combat system.
- Source: user
- Notes: Rigging-loss-on-collision (docs/02.2) is recognized in the ResolutionLog but does not yet mutate ship state; that lives with the combat-damage milestone.

### R028 — Unfouling mechanic
- Class: core-capability
- Status: out-of-scope
- Description: Unfouling mechanic
- Why it matters: Per docs/02.2, unfouling happens during the MAINTENANCE phase, which is out of scope for M001.
- Source: user
- Notes: M001 sets fouling state when collisions cause it but does not provide a path to clear it.

## Traceability

| ID | Class | Status | Primary owner | Supporting | Proof |
|---|---|---|---|---|---|
| R001 | primary-user-loop | active | M001/S04 | none | unmapped |
| R002 | core-capability | active | M001/S03 | none | unmapped |
| R003 | core-capability | active | M001/S07 | none | unmapped |
| R004 | core-capability | active | M001/S06 | none | unmapped |
| R005 | core-capability | active | M001/S08 | none | unmapped |
| R006 | primary-user-loop | active | M001/S09 | none | unmapped |
| R007 | differentiator | active | M001/S05 | none | unmapped |
| R008 | constraint | active | M001/S02 | none | unmapped |
| R009 | constraint | active | M001/S01 | none | unmapped |
| R010 | core-capability | active | M001/S03 | none | unmapped |
| R011 | primary-user-loop | active | M001/S04 | none | unmapped |
| R012 | failure-visibility | active | M001/S03 | M001/S06, M001/S07 | unmapped |
| R013 | quality-attribute | active | M001/S06 | none | unmapped |
| R014 | quality-attribute | active | M001/S10 | none | unmapped |
| R015 | quality-attribute | active | M001/S04 | none | unmapped |
| R016 | quality-attribute | active | M001/S03 | M001/S07, M001/S06 | unmapped |
| R017 | core-capability | deferred | none | none | unmapped |
| R018 | core-capability | deferred | none | none | unmapped |
| R019 | integration | deferred | none | none | unmapped |
| R020 | primary-user-loop | deferred | none | none | unmapped |
| R021 | core-capability | deferred | none | none | unmapped |
| R022 | core-capability | deferred | none | none | unmapped |
| R023 | core-capability | deferred | none | none | unmapped |
| R024 | continuity | deferred | none | none | unmapped |
| R025 | core-capability | out-of-scope | none | none | unmapped |
| R026 | core-capability | out-of-scope | none | none | unmapped |
| R027 | core-capability | out-of-scope | none | none | unmapped |
| R028 | core-capability | out-of-scope | none | none | unmapped |

## Coverage Summary

- Active requirements: 16
- Mapped to slices: 16
- Validated: 0
- Unmapped active requirements: 0
