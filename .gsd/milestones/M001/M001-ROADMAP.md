# M001: Movement Plotting (Complete)

**Vision:** Deliver the complete movement plotting and resolution loop — UI, server rules, and visual playback — so a player can fight test_fleet.json indefinitely with every documented movement rule enforced.

## Success Criteria

- Player can load test_fleet.json, plot every player-0 ship via the Movement button, see MA / path / tacking probability live, and submit per-ship plots
- End Planning advances the phase only when every player-0 ship has a submitted plot; re-plotting allowed before End Planning is pressed
- Stub-AI plots all non-player ships through the real plotting protocol before MOVEMENT_RESOLUTION begins, with Trace logs confirming strategy and decisions
- MOVEMENT_RESOLUTION runs impulse-by-impulse via MovementResolver and produces a complete ResolutionLog
- Playback animates ships hex-by-hex; contested-hex and bear-off prompts pause playback and accept the player's choice; tacking failures, collisions, and fouling all observable
- After playback, ships are at resolved positions with updated facing and speed; plotted_actions.movement cleared; loop sustains 5+ turns with no console errors
- All unit tests, 12 scenario integration fixtures, and the determinism test pass via `make test`; no regression in existing tests

## Slices

- [ ] **S01: DataManager rule wrappers + scenario seed validation** `risk:low` `depends:[]`
  > After this: make test-file F=test/unit/test_data_manager_bearing_off.gd passes; loading a scenario without `seed` hard-errors; seed:-1 logs fresh-seed generation; crew_quality letter normalization complete.

- [ ] **S02: Shared seeded RNG on GameState; EnvironmentController migrated** `risk:medium` `depends:[S01]`
  > After this: GameState.rng exists, seeded from scenario; EnvironmentController consumes it; existing env tests pass; same seed reproduces same wind sequence in a manual run.

- [ ] **S03: MovementValidator real rules (single-ship, no contests)** `risk:high` `depends:[S02]`
  > After this: All single-ship fixture scenarios pass: MA exhaustion, turn-then-forward, fast-tack bonus, pivot caps, luffing, in-irons plot. PlotStep carries move_type. Trace logs every rule-block.

- [ ] **S04: Planning UI fleet workflow: Movement button, plot display, End Planning** `risk:medium` `depends:[S03]`
  > After this: Manual playtest: load test_fleet.json, plot all player-0 ships through the Movement button, see MA / path live, undo/cancel/submit per ship, End Planning gates on completion, all protocol responses under 50ms.

- [ ] **S05: Tacking attempt detection and live probability UX** `risk:medium` `depends:[S03,S04]`
  > After this: Plot pivot-to-L then pivot-same-direction; session.is_tacking_attempt flips true; UI shows tacking-success % from tacking_table.json + DRMs. Undoing past the trigger flips it back to false.

- [ ] **S06: MovementResolver single-ship: impulse loop + tacking roll + in-irons escape** `risk:high` `depends:[S03,S05]`
  > After this: Fixtures: tack success (ship continues plot), tack failure (ship immobilized facing L), in-irons escape success/failure. Determinism test passes for single-ship plots.

- [ ] **S07: MovementResolver contested hexes, bear-off, collisions, fouling** `risk:high` `depends:[S06]`
  > After this: Fixtures: two-ship head-on contested, three-ship contested, two-ship swap, off-map bear-off filtered. Collisions stop both ships; fouling state set per 50% rule (seeded).

- [ ] **S08: StubAI drives plotting protocol for non-player ships** `risk:medium` `depends:[S03,S06]`
  > After this: Player-1 ships get plotted via real protocol before PLANNING UI is interactive; trace logs show stub strategy + per-ship plot. Stub-AI prompt answers (no-surrender, no-bear-off) injected at resolution.

- [ ] **S09: Movement resolution playback (view layer animates ResolutionLog)** `risk:medium` `depends:[S06,S07]`
  > After this: Watch ships glide hex-by-hex per impulse at ~200ms each; contested-hex surrender prompt pauses playback; bear-off prompt pauses; after playback ships at resolved positions with updated facing + speed.

- [ ] **S10: Integration slice: full loop, 5-turn sustained playtest, all fixtures green** `risk:medium` `depends:[S04,S07,S08,S09]`
  > After this: Open test_fleet.json, play 5 turns through PLANNING and MOVEMENT_RESOLUTION with stub-AI opposition; no console errors; `make test` all green; determinism test green.

## Boundary Map

### S01 → S02

Produces:
- `DataManager.get_bearing_off_probability(crew_quality: String, maneuverability: String) -> float` with assert() validation
- `DataManager.load_scenario(...)` hard-errors on missing `seed` field; `seed:-1` → fresh seed (trace-logged)
- Loaded scenario dict carries validated `seed: int`
- crew_quality normalization: scenarios that say `"Trained"` map to a letter on load (or scenarios updated to use letters directly)
- `test/unit/test_data_manager_bearing_off.gd` exists and passes

Consumes:
- nothing (first slice)

### S02 → S03

Produces:
- `GameState.rng: RandomNumberGenerator` is the single seeded RNG
- `GameState.start_new_game(scenario_data)` seeds rng from scenario_data.seed
- `EnvironmentController` consumes `GameState.rng`; its own RNG removed
- Existing env tests still pass; same seed reproduces same wind sequence

Consumes:
- S01: validated scenario dict with `seed`

### S03 → S04

Produces:
- `MovementValidator` real rules (single-ship only): MA recalc per pivot, accel/decel bounds against last-turn speed, turning-table min-forward rule, pivot caps (max 2/turn + free pivot at MA=0), luffing, in-irons at plot start, fast-tack +1 MA bonus, map bounds
- `MovementPlottingSession` carries `pivots_used: int`, `forward_hexes_since_last_pivot: int`
- `PlotStep.move_type` populated by validator
- `Trace.trace_log("MovementValidator", ...)` on every rule-block
- Unit tests for the math + scenario fixtures for single-ship rules pass

Consumes:
- S02: `GameState.rng` available
- S01: `DataManager` wrappers and seed contract

### S03 → S05

Produces (hook into S05 work):
- Validator exposes `is_tacking_attempt(session_state) -> bool` (or equivalent computation hook)
- Session has `is_tacking_attempt: bool` field updated on every select_hex / undo

### S04 → S10

Produces:
- PLANNING UI fleet workflow: ship list, Movement button initiates plotting, valid-hex display, MA display, plotted-path display, undo/cancel/submit per ship
- End Planning button enabled only when all player-0 ships submitted
- Re-plotting allowed before End Planning
- Protocol responses < 50ms on local server

Consumes:
- S03: validator returns correct ValidNextHexes

### S05 → S06

Produces:
- `MovementPlottingSession.is_tacking_attempt` is authoritative across edits/undos
- UI shows live tacking probability from `tacking_table.json` + DRMs
- Validator marks session for tacking attempt; resolver reads the flag

Consumes:
- S03: validator hook + session fields
- S04: UI surface for the probability display

### S06 → S07

Produces:
- `MovementResolver.run(plotted_ships) -> ResolutionLog` for single-ship plots
- `ResolutionLog` data classes (per-impulse, per-ship event types) in MovementTypes
- Tacking success roll (from `tacking_table.json` + DRMs) made by resolver
- In-irons escape roll made by resolver
- Determinism test passes for single-ship plots

Consumes:
- S05: `is_tacking_attempt` flag on submitted plot
- S02: `GameState.rng`

### S07 → S09

Produces:
- `MovementResolver` multi-ship: impulse-by-impulse loop, contested-hex DRM math, surrender prompt event in log, bear-off prompt event in log, collisions, 50% fouling rule
- `ResolutionLog` schema final
- Multi-ship integration fixtures pass

Consumes:
- S06: single-ship resolver + ResolutionLog primitives

### S08 → S10

Produces:
- `StubAI` (scripts/server/stub_ai.gd) drives the plotting protocol for every non-player ship at PLANNING start
- Scenario-configurable strategies (default: hold position; per-ship overrides possible)
- Resolver injects no-surrender / no-bear-off answers for stub-AI ships

Consumes:
- S03: validator (stub-AI plots are rule-validated)
- S06: resolver knows which ships are stub-AI (via player_id != 0)

### S09 → S10

Produces:
- `MovementResolutionPlaybackController` consumes a `ResolutionLog` and animates ships hex-by-hex (~200ms each, concurrent within impulse)
- Surrender prompt and bear-off prompt UI modals (functional, not pretty)
- Playback completion signal advances the phase

Consumes:
- S07: final `ResolutionLog` schema
- S04: existing UI scenes ready to host prompt modals
