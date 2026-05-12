---
id: M001
title: "Movement Plotting (Complete)"
status: complete
completed_at: 2026-05-12T19:32:03.145Z
key_decisions:
  - Single MovementValidator class with broken-out private methods over composable rule engine
  - Impulse-by-impulse resolution granularity for correct contested-hex semantics
  - Resolver emits ResolutionLog consumed by view-side PlaybackController (pure logic separated from animation)
  - StubAI drives real plotting protocol rather than writing plotted_actions directly
  - Single seeded RNG on GameState for deterministic replay
  - Async/await on Godot signals for mid-resolution player prompts
key_files:
  - scripts/server/movement_validator.gd
  - scripts/server/movement_resolver.gd
  - scripts/server/movement_types.gd
  - scripts/server/movement_plotting_controller.gd
  - scripts/server/movement_plotting_session.gd
  - scripts/server/stub_ai.gd
  - scripts/view/movement_resolution_playback_controller.gd
  - scripts/ui/planning_phase_ui.gd
  - scripts/core/game_controller.gd
  - test/unit/test_movement_resolver.gd
  - test/unit/test_game_loop.gd
lessons_learned:
  - Multi-slice commits that touch the same files need careful merge — the S06-S10 batch overwrote S04/S05 additions to game_controller.gd and planning_phase_ui.gd
  - Integration tests (test_game_loop) that exercise the full turn cycle are essential for catching cross-slice regressions
  - GDScript print() calls should use Trace.trace_log() from the start to avoid cleanup passes
---

# M001: Movement Plotting (Complete)

**Delivered the complete movement plotting and resolution loop — UI, server rules, AI opposition, and visual playback — for turn-based naval combat on a hex grid.**

## What Happened

M001 implemented the full movement system across 10 slices and 27 tasks. Starting from data table loaders and RNG determinism (S01-S02), it built the MovementValidator with all documented sailing rules — MA recalculation per pivot, acceleration/deceleration bounds, turning-table minimums, pivot caps, luffing, in-irons, and fast-tack bonuses (S03). The planning UI enables per-ship plotting with live MA display, path visualization, tacking probability, and End Planning gating (S04-S05). MovementResolver runs impulse-by-impulse simulation handling contested hexes, collisions, fouling, tacking rolls, and bear-off decisions (S06-S07). StubAI drives non-player ships through the real plotting protocol (S08). MovementResolutionPlaybackController animates resolution hex-by-hex with prompt pausing (S09). The 5-turn integration test proves the loop sustains indefinite play (S10). A regression where S06-S10 overwrote S04/S05 features was caught during final validation and fixed.

## Success Criteria Results

All 7 success criteria met. 264/264 tests pass. 5-turn integration loop completes without errors.

## Definition of Done Results

Not provided.

## Requirement Outcomes

Not provided.

## Deviations

None.

## Follow-ups

Combat resolution phase (guns, damage, crew effects), real AI replacing StubAI, network multiplayer, save/load, scenario editor
