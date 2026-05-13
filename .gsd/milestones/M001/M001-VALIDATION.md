---
verdict: pass
remediation_round: 0
---

# Milestone Validation: M001

## Success Criteria Checklist
- [x] Player can load test_fleet.json, plot every player-0 ship via Movement button, see MA/path/tacking probability live, and submit per-ship plots — **Verified**: planning_phase_ui.gd has show_plotting_controls(), update_plotting_state(), update_tacking_state(), mark_ship_submitted()
- [x] End Planning advances phase only when every player-0 ship has a submitted plot; re-plotting allowed before End Planning — **Verified**: _update_end_planning_state() gates on are_all_ships_submitted(); game_controller.gd re-plot clearing logic in _on_planning_action_toggled()
- [x] Stub-AI plots all non-player ships through real plotting protocol before MOVEMENT_RESOLUTION begins — **Verified**: stub_ai.gd plot_all_ai_ships() drives MovementPlottingController; 13 unit tests pass
- [x] MOVEMENT_RESOLUTION runs impulse-by-impulse via MovementResolver and produces complete ResolutionLog — **Verified**: movement_resolver.gd run() method; 35 resolver unit tests including contested hex, collisions, fouling, tacking, bear-off
- [x] Playback animates ships hex-by-hex; contested-hex and bear-off prompts pause playback — **Verified**: movement_resolution_playback_controller.gd play() with _animate_impulse(); 15 playback tests pass
- [x] After playback, ships at resolved positions with updated facing/speed; plotted_actions.movement cleared; loop sustains 5+ turns — **Verified**: test_game_loop.gd test_multi_turn_loop() runs 5 turns with no errors
- [x] All unit tests pass via `make test`; no regression — **Verified**: 264/264 tests pass, 970 asserts, 12 test files

## Slice Delivery Audit
- **S01** (Data tables + seed): Delivered bearing_off_table loader, scenario seed validation, crew_quality normalization. 11 tests.
- **S02** (RNG determinism): Delivered GameState.rng seeded from scenario, EnvironmentController migrated to consume it.
- **S03** (Movement validator): Delivered MovementValidator with MA recalc, turning rules, pivot caps, luffing, in-irons, fast-tack bonus. PlotStep.move_type populated.
- **S04** (Planning UI fleet workflow): Delivered ship list, Movement button, valid-hex overlay, MA/path display, undo/cancel/submit per ship, End Planning gating.
- **S05** (Tacking UI): Delivered is_tacking_attempt tracking, live tacking probability display from tacking_table.json.
- **S06** (Single-ship resolver): Delivered MovementResolver.run() for single ships, tacking success/failure rolls, in-irons escape, ResolutionLog data classes.
- **S07** (Multi-ship resolver): Delivered impulse-by-impulse multi-ship resolution, contested hex DRM, surrender/bear-off prompt events, collision + 50% fouling rule.
- **S08** (Stub AI): Delivered StubAI driving real plotting protocol for player-1 ships, forward strategy, no-surrender/no-bear-off injection.
- **S09** (Playback controller): Delivered MovementResolutionPlaybackController animating hex-by-hex, prompt pausing, playback_completed signal.
- **S10** (Integration test): Delivered test_multi_turn_loop 5-turn integration test, skip_post_combat_delay flag, regression fix restoring S04/S05 features.

## Cross-Slice Integration
All cross-slice boundaries clean:
- S01→S02: Scenario seed flows through GameState.rng correctly
- S03→S04: Validator ValidNextHexes consumed by planning UI overlay
- S05→S06: is_tacking_attempt flag read by resolver for tacking rolls
- S06→S07: Single-ship ResolutionLog extended cleanly for multi-ship
- S07→S09: Playback controller consumes final ResolutionLog schema without issues
- S08→S10: StubAI integrates with plotting protocol and resolver prompt injection

One regression occurred: S06-S10 commit lost S04/S05 features (EndPlanningButton, tacking UI, submitted-ship tracking). Fixed in commit 0281a13 — root cause was a merge that overwrote the files rather than merging incremental changes.

## Requirement Coverage
M001 covers the complete movement plotting and resolution loop:
- Movement plotting with full rule enforcement (MA, turning, pivots, tacking, luffing, in-irons)
- Fleet planning UI with per-ship workflow
- Server-authoritative resolution with simultaneity rules
- Visual playback with prompt support
- AI opposition via stub protocol
- Deterministic replay via seeded RNG
- 264 automated tests providing regression safety


## Verdict Rationale
All 7 success criteria met with evidence. 264/264 tests pass. All 10 slices delivered their claimed outputs. One regression was caught and fixed before validation. The movement loop is functional end-to-end.
