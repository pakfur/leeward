# M001: Movement Plotting (Complete)

**Gathered:** 2026-05-11
**Status:** Ready for planning

## Project Description

Leeward is a turn-based naval combat game in Godot 4, set in the Napoleonic era (1790–1814), modeled on the *Close Action* tabletop family. The first milestone delivers the complete movement plotting and resolution loop for a single fixed scenario (`test_fleet.json`), with all documented movement rules enforced server-side, full-fleet plotting UI for the human player, a stub-AI opponent, and visual playback of impulse-by-impulse simultaneous resolution.

## Why This Milestone

Movement plotting is the irreducible tactical core of the game. Every later capability — combat, damage, careers, AI, networking — attaches to a working plotting loop. The current code has the protocol scaffolding, JSON rule tables, and view layer in place, but the `MovementValidator` is a mock and there is no `MovementResolver` at all. Until the real rules land, the game has no demonstrable tactical play. M001 retires that risk in one shippable milestone.

## User-Visible Outcome

### When this milestone is complete, the user can:

- Launch the game, pick `test_fleet.json` from scenario selection, and see ships placed at their scenario positions and facings.
- During PLANNING, click a ship in the ship list, press the existing **"Movement"** button on the selected ship to start a plotting session, then click hexes on the map to extend the plot.
- See remaining MA, the plotted path with move types, and (when applicable) the live tacking-attempt success probability as they plot.
- Undo individual steps, cancel the session, or submit the plot per ship.
- Re-open a submitted plot and re-plot any ship until "End Planning" is pressed.
- Press "End Planning" (which only enables when every player-0 ship has submitted) to trigger MOVEMENT_RESOLUTION.
- Watch impulse-by-impulse playback of all ships moving simultaneously, with contested-hex surrender prompts and bear-off prompts pausing the action for player decisions.
- See ships at their resolved hex positions and facings after playback, with updated speed for next turn.
- Repeat the cycle for 5+ turns without errors.

### Entry point / environment

- Entry point: launching the game via `make run` (or `make play`), choosing `test_fleet.json` from the scenario selection screen.
- Environment: local Godot 4.4 build, no networking, no external services.
- Live dependencies involved: none. All in-engine, all data files local.

## Completion Class

- **Contract complete means:** all `test/unit/test_data_manager_*` and `test/unit/test_movement_*` pass; all 12 scenario-driven integration fixtures pass; the determinism test passes — all via `make test`.
- **Integration complete means:** loading `test_fleet.json`, plotting the fleet, ending planning, resolving with stub-AI opposition, and watching playback all work end-to-end in the running game.
- **Operational complete means:** 5-turn sustained loop of PLANNING → MOVEMENT_RESOLUTION → next turn with no console errors, no state drift, and no stale UI.

## Final Integrated Acceptance

To call this milestone complete, we must prove:

- A player can fight `test_fleet.json` for at least 5 turns through the PLANNING → MOVEMENT_RESOLUTION → next-turn loop without seeing a single console error.
- Every documented movement rule from `docs/02-game-rules.md` is enforced at plot time, and every contested-hex / bear-off / collision / fouling rule from `docs/02.2 - contexted-hex-rules.md` is enforced at resolution.
- Trace logs show validator rule-blocks and resolver events with enough detail to diagnose any anomaly without re-running.
- With a fixed scenario seed, identical fleet plots produce identical `ResolutionLog` across runs.

## Architectural Decisions

### Validator shape

**Decision:** Single `MovementValidator` class with broken-out private methods and an internal `PlottingState` snapshot.

**Rationale:** All rules consult data already in JSON tables (`movement_allowance`, `speed_change`, `tacking`, `turning`, `bearing_off`). GDScript favors clear procedural code over plugin-style rule engines, and debugging interlocking rule failures is much easier when they live in one class with explicit method names.

**Alternatives Considered:**
- Rule-engine of composable rule classes (each rule implementing a common interface) — premature abstraction without a real need for scenario-specific rule overrides.

---

### Resolver placement

**Decision:** New `MovementResolver` class under `scripts/server/`, symmetric with `MovementValidator`.

**Rationale:** Clean separation between "plotter says what's legal" and "resolver executes plots under simultaneity rules." `ShipStateController` already mutates state but mixing it with multi-ship simulation would bloat one class.

**Alternatives Considered:**
- Extend `ShipStateController` — wrong concern.
- Method on `MovementPlottingController` — that controller is a session manager, not a simulator.

---

### Mid-resolution user input

**Decision:** Async/await on Godot signals for contested-hex surrender prompts and bear-off prompts.

**Rationale:** Godot-idiomatic, single execution context, no need for a new mini-protocol. Stub-AI ships have programmatic answers injected directly, so deadlock is impossible in M001 (single-machine).

**Alternatives Considered:**
- Mini-session protocol like plotting — too heavy for yes/no.
- Explicit state machine with observed state — too verbose.

---

### Plot step payload

**Decision:** `PlotStep` carries `move_type: FORWARD | PORT | STARBOARD` in addition to `hex` and `facing`.

**Rationale:** Validator and resolver both need to know what kind of move each step represents (pivot caps, fast-tack detection, turning-table consultation). `MoveMetadata` already carries it; we lift it into the persisted step.

**Alternatives Considered:**
- Derive from hex+facing transitions — fragile, spreads recomputation everywhere.

---

### Tacking lifecycle

**Decision:** Validator detects tack pattern at plot time and sets `is_tacking_attempt: bool` on the `MovementPlottingSession`. UI shows live success probability from `tacking_table.json` + DRMs while the flag is true. Resolver makes the actual roll.

**Rationale:** Tacking is a key tactical gamble. Showing the player the success probability while plotting is the UX moment that distinguishes this from a clicker game. The flag is also useful for the contested-hex logic if a tacking ship is contested.

**Alternatives Considered:**
- Implicit detection at resolution time — loses the UX moment.

---

### Resolver granularity

**Decision:** Impulse-by-impulse. The resolver advances every ship 1 MP at a time, resolves any contests, applies bear-off/collision outcomes, then moves to the next impulse.

**Rationale:** Only granularity that makes contested-hex rules work in fleet engagements. Full-plot-then-contest breaks pass-through semantics (two ships swapping positions would never collide). Matches the *Close Action* mechanics in the reference docs.

**Alternatives Considered:**
- Full-plot then contest — breaks intended game semantics.

---

### Stub-AI plotting

**Decision:** Stub-AI drives the real plotting protocol (`handle_start_plotting`, `handle_select_hex`, `handle_submit_movement`) just like a remote human client would.

**Rationale:** AI plots get rule-validated. Bug-finding cross-coverage: any bug in the validator that crashes a human plot will also crash AI plots, surfacing it under test. Player and AI travel the same code path.

**Alternatives Considered:**
- Direct writes to `ShipState.plotted_actions` — bypasses validation and would silently accept illegal AI plots.

---

### Player-vs-AI ownership

**Decision:** `player_id == 0` is the human player; all other player IDs are stub-AI controlled. No new scenario schema in M001.

**Rationale:** Matches existing scenarios. No premature schema. Will evolve to an explicit per-player `controller` field when real AI or networked humans land.

**Alternatives Considered:**
- Add explicit per-player `controller` field in scenario JSON — premature for M001 needs.

---

### RNG

**Decision:** Single `RandomNumberGenerator` on `GameState`. Scenario JSON requires integer `seed` field; `-1` means generate a fresh seed at game start (trace-logged). `EnvironmentController` migrates to consume `GameState.rng` as part of M001.

**Rationale:** Deterministic replay for tests, debugging, and (later) replay features. A single source converges the existing RNG fragmentation. Required seed in scenarios makes scenarios reproducible by default; `-1` sentinel preserves play-variability when authors want it.

**Alternatives Considered:**
- Per-controller seeded RNGs from a master seed — over-engineered for a single project-scoped RNG need.
- No seed control — flaky tests.

---

### Resolution playback

**Decision:** Resolver produces a `ResolutionLog` (per-impulse events per ship + pause-points for player input). View layer (`MovementResolutionPlaybackController`) consumes the log, animates ships hex-by-hex, surfaces prompts via signals, then signals the phase controller to advance.

**Rationale:** Resolver stays pure-logic and fully testable. Player still gets the simultaneous-resolution drama. Animation timing decoupled from rule logic.

**Alternatives Considered:**
- Live-animate as resolver steps — entangles rule logic with view timing.
- Instant resolution, no animation — kills the drama.

---

### Tests

**Decision:** Unit tests for rule math + table lookups (existing `test_data_manager_*` style) plus scenario-driven integration tests under `test/fixtures/scenarios/` driving the full validator → resolver → state-update path. Determinism test runs the same fixture twice with the same seed and diffs the `ResolutionLog`.

**Rationale:** Catches both math errors and wiring bugs. Fixtures double as regression coverage for subsequent milestones. The 12-fixture suite covers all M001 risk areas.

**Alternatives Considered:**
- Unit tests only — misses wiring errors.
- CLI test harness — premature scaffolding for M001 needs.

---

### DataManager rule boundary

**Decision:** Every JSON rule-table lookup goes through a typed `DataManager.get_*` function with `assert()` parameter validation, modeled on the existing `load_movement_allowance_table()` / `get_movement_allowance()` pattern. Any missing wrapper is added before the consumer code is written.

**Rationale:** Single source of truth for rule lookups; consistent style; catches bad parameters fast; tables are independently testable under `test/unit/test_data_manager_<table>.gd`.

**Alternatives Considered:** None — this is the established codebase convention.

---

> See `.gsd/DECISIONS.md` for the append-only register of all project decisions.

## Error Handling Strategy

### Plotting-time

Illegal hex selections return structured protocol errors (`ILLEGAL_HEX`, `SESSION_NOT_FOUND`, `VERSION_CONFLICT`, etc.) which the UI surfaces as inline messages near the offending hex; the path is unchanged. Submit-with-invalid-path disables the submit button with a reason — submit never goes green if `can_submit == false`. MA=0 with no legal moves returns an empty `ValidNextHexes` with `can_submit: true`; the ship sits. In-irons at plot start: the player may plot the escape pivot, but the resolver makes the actual roll. The `is_tacking_attempt` flag is recomputed on every step and every undo so the UI probability indicator stays truthful.

### Scenario load (via DataManager)

Missing `seed` is a hard error at scenario load. `seed: -1` generates a fresh seed from `Time.get_unix_time_from_system()` and trace-logs the value. Unknown ship_type, ship off-map at scenario start, ships overlapping at scenario start, and an empty fleet for player 0 are all hard errors at scenario load. Silent fallbacks defeat the deterministic-replay contract.

### Resolver-time

If a stub-AI plot is somehow illegal at resolution time (defense in depth — shouldn't happen with H2), the resolver logs to Trace, truncates that ship's plot at the illegal step, and continues. Contested-hex re-rolls are capped at 10 to guarantee termination; if hit, both ships stop in current hexes and the event is logged as anomalous (practically impossible with the DRMs in the table). Bear-off direction options are pre-filtered to legal hexes; if none, the bear-off prompt is skipped and collision applies. All-ships-immobilized produces an empty `ResolutionLog` and the phase advances cleanly.

### Mid-resolution UI prompts

No timeouts in M001 (single-machine, no networking). Resolver awaits indefinitely. Stub-AI ships never surrender and never bear off — the resolver injects those answers without a UI roundtrip.

### Lifecycle

"End Planning" with any player-0 ship lacking a submitted plot is blocked; the UI lists the offending ships. Stub-AI plots synchronously at the start of PLANNING so it never blocks phase advance. Phase advance during MOVEMENT_RESOLUTION is blocked until the playback controller signals completion.

### Observability

`Trace.trace_log("MovementValidator", ...)` on every rule-blocking decision with the relevant ship state and table inputs. `Trace.trace_log("MovementResolver", ...)` on every contested-hex / tacking / bear-off / collision / fouling event. The active turn's `ResolutionLog` lives on `GameState` and is surfaceable in the developer UI (F12); cleared at END_TURN. Stub-AI strategy and per-ship plot decisions are logged. No silent fallbacks anywhere.

### Intentionally unhandled

Save/load mid-plot (out of scope; quitting during PLANNING loses sessions). Network errors / RPC retries beyond what the existing protocol already handles (M001 is single-machine).

## Risks and Unknowns

- **Mock validator full rewrite.** All `MovementValidator` logic is currently mock; the real implementation has 12+ interlocking rules over five rule tables plus per-step state (MA recalc, pivot count, since-last-pivot count, tacking flag, fast-tack detection). Rule interactions surface bugs only in real play. *Mitigation:* 12-scenario fixture suite + interactive playtesting at S10.
- **Impulse-by-impulse contested-hex correctness.** Three-ship contests, bear-off into off-map, simultaneous collisions where ships are also contesting — these stack. *Mitigation:* explicit fixture scenarios cover each case.
- **Async/await on UI prompts during simulation.** New pattern in this codebase. *Mitigation:* no timeouts needed in single-machine M001; stub-AI prompt answers are injected programmatically.
- **`is_tacking_attempt` flag authoritativeness.** Must stay correct across every plot edit and undo. *Mitigation:* validator recomputes on every step; flag lives on the session, not in UI.
- **`GameState.rng` migration.** `EnvironmentController` has its own RNG today. *Mitigation:* migration is its own slice (S02) with explicit env-test regression check.
- **Stub-AI runs synchronously at PLANNING start.** Controller must accept those calls before player UI gets focus. *Mitigation:* explicit phase-controller hook in S08.
- **crew_quality scale normalization.** Today: `"B"` (Veteran) in Ship defaults vs `"Trained"` in scenarios; bearing-off table uses A–G letters. *Mitigation:* normalize to letters as part of S01.

## Existing Codebase / Prior Art

- `scripts/server/movement_plotting_controller.gd` — session-based plotting protocol, complete and correct
- `scripts/server/movement_plotting_session.gd` — session state with versioning + idempotency cache
- `scripts/server/movement_types.gd` — typed data classes for protocol and validation
- `scripts/server/movement_validator.gd` — **mock**, to be replaced
- `scripts/autoload/data_manager.gd` — rule-table wrappers for movement_allowance, ships, scenarios, speed_change, tacking, turning. Missing: `bearing_off_probability`, seed validation.
- `scripts/autoload/game_state.gd` — server-authoritative state container; owns controllers, ship registry, environment, state history.
- `scripts/server/turn_phase_controller.gd` — 10-phase state machine; MOVEMENT_RESOLUTION sets phase, does nothing else.
- `scripts/server/environment_controller.gd` — has its own RNG (to be migrated).
- `scripts/state/ship_state.gd` — mutable ship state with plotted_actions dictionary.
- `scripts/state/ship.gd` — immutable identity + type data.
- `scripts/view/ship_view.gd` — `sync_to_state` already syncs position+facing.
- `scripts/ui/planning_phase_ui.gd` — current planning UI (legacy `planning_panel.gd` not used).
- `scripts/ui/ship_list_item.gd` and `scenes/ui/ship_list_item.tscn` — existing **"Movement" button** is the entry point for plotting.
- `data/rules/*.json` — all rule tables present including `bearing_off_table.json`.
- `data/scenarios/test_fleet.json` — 2v2 fleet scenario used as M001 acceptance target.
- `test/unit/test_data_manager_*` — established test pattern.

## Relevant Requirements

- **R001** — Primary plotting workflow; advanced by S04, S05.
- **R002** — All `docs/02-game-rules.md` movement rules at plot time; advanced by S03.
- **R003** — All `docs/02.2` contested-hex rules at resolution; advanced by S07.
- **R004** — Impulse-by-impulse resolution model; advanced by S06.
- **R005** — Stub-AI through real protocol; advanced by S08.
- **R006** — Visual playback; advanced by S09.
- **R007** — Tacking UX with live probability; advanced by S05.
- **R008** — Single seeded RNG with scenario seed contract; advanced by S02.
- **R009** — DataManager rule-lookup boundary; advanced by S01.
- **R010** — Map bounds enforced; advanced by S03.
- **R011** — Per-ship submit + End Planning gating; advanced by S04.
- **R012** — Trace observability; supported by S03/S06/S07.
- **R013** — Deterministic resolution; advanced by S06.
- **R014** — 5+ turn sustained loop; advanced by S10.
- **R015** — <50ms plotting latency; advanced by S04.
- **R016** — Test coverage commitments; advanced by S03/S06/S07.

## Scope

### In Scope

- PLANNING-phase plotting UI and server rules: full coverage of MA, accel/decel, turning, pivot caps, pivot-at-MA=0, luffing, tacking, fast-tack, in-irons, map bounds.
- MOVEMENT_RESOLUTION resolver: impulse-by-impulse simultaneous execution; tacking success roll; in-irons escape roll; contested-hex resolution; bear-off; collisions; 50% fouling rule.
- Full-fleet plotting per player; per-ship submit; explicit End Planning; re-plot allowed before End Planning.
- Map bounds enforced; open water only.
- Stub-AI drives non-player ships through the real plotting protocol; programmatic prompt answers at resolution.
- Visual playback animates the `ResolutionLog` hex-by-hex.
- Ships at resolved positions with updated facing and speed after playback; 5+ turn sustained loop.
- All ships 1-hex.

### Out of Scope / Non-Goals

- 2-hex ship geometry. Terrain. Networked multiplayer. Hot-seat UI. Anchoring. Towing. All phases after MOVEMENT_RESOLUTION (combat, drift, status, morale, message delivery, post-combat, striking, end-turn beyond loop closure). Real AI. Ramming damage values. Unfouling. Save/load mid-plot.

## Technical Constraints

- Godot 4.4 / GDScript only. No new addons.
- Server-authoritative architecture preserved: every mutating function guards with `if not is_server`.
- All JSON rule-table lookups must go through `DataManager.get_*` with `assert()` validation.
- All observability via the existing `Trace` autoload.
- No regression in `test_data_manager_*` or `test_trace`.
- Tests run via `make test`.

## Integration Points

- **`MovementPlottingController`** — protocol orchestration, unchanged; consumes the new validator.
- **`TurnPhaseController`** — extended at MOVEMENT_RESOLUTION to invoke the resolver and await playback completion before advancing.
- **`GameState.rng`** — new shared seeded RNG; consumed by `EnvironmentController` (migrated), `MovementResolver`, and any future stochastic system.
- **`DataManager`** — new `get_bearing_off_probability`, seed validation on scenario load; existing wrappers unchanged.
- **`ShipView.sync_to_state`** — existing path consumed by the new playback controller.
- **Trace autoload** — categories: `MovementValidator`, `MovementResolver`, `StubAI`.

## Testing Requirements

- Unit tests under `test/unit/`:
  - `test_data_manager_bearing_off.gd` (new) — bearing-off table lookups and parameter validation.
  - `test_movement_validator_*.gd` (new) — rule math: MA recalc after pivot, pivot cap, accel/decel bounds, fast-tack bonus, luffing, in-irons handling.
  - `test_movement_resolver_*.gd` (new) — contested-hex DRM math, bear-off probability lookup, tacking probability lookup.
- Integration tests under `test/fixtures/scenarios/` (12 fixtures): MA exhaustion, turn-then-forward, tack success, tack failure, fast-tack bonus, in-irons escape success, in-irons escape failure, two-ship head-on contested, three-ship contested, two-ship swap, off-map blocked, off-map bear-off filtered, legal stub-AI round-trip.
- Determinism test: run a fixture twice with the same seed and diff the `ResolutionLog`.
- All run via `make test`.
- No regression in existing tests.

## Acceptance Criteria

1. Loading `test_fleet.json` places ships at their scenario positions and facings with the declared seed honored.
2. PLANNING UI shows the player's ship list. Selecting a ship highlights it. Pressing the existing **"Movement" button** on the selected ship initiates a plotting session. Valid next hexes appear on the map. Clicking a valid hex extends the plot with correct `facing` and `move_type`. Undo, cancel, and submit per ship work.
3. UI shows remaining MA, the plotted path, and the tacking-attempt indicator with success probability (when applicable) live as the player plots.
4. "End Planning" enables only when every player-0 ship has a submitted plot. Submitted plots are reopenable until End Planning is pressed.
5. Before MOVEMENT_RESOLUTION begins, stub-AI has plotted every non-player ship through the real protocol; Trace logs confirm the strategy and per-ship plot decisions.
6. MOVEMENT_RESOLUTION runs impulse-by-impulse via `MovementResolver`, producing a complete `ResolutionLog`.
7. Playback animates ships hex-by-hex (~200ms each, concurrent within an impulse). Contested-hex surrender prompts pause playback and accept the player's choice. Bear-off prompts pause and accept attempt/no-attempt. Tacking failures visibly stop a ship facing L. Collisions stop both ships at the appropriate hexes and set fouling state per the 50% rule.
8. After playback, ships are at their resolved hex positions with updated facing and `speed` reflecting MP actually expended. `plotted_actions.movement` is cleared.
9. The next turn's ENVIRONMENT → PLANNING cycle runs without errors. A 5-turn sustained playtest produces no console errors, no state drift, no stale UI.

## Open Questions

- Exact UI shape of the contested-hex surrender prompt and bear-off prompt — start with simplest functional modal; iterate after seeing it in playback (resolved at S09).
- Whether playback animation needs Tween chains or a simple per-impulse synchronous loop — resolved when the playback controller is prototyped (resolved at S09).
- Whether the existing "Movement" button on `ship_list_item.tscn` is already wired to the plotting controller or needs to be hooked up — resolved as the first step of S04.
- Exact API for the stub-AI strategy registry — defaults to per-ship strategy on scenario; resolved at S08 once a concrete fixture scenario forces the decision.
