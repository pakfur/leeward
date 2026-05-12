---
id: S08
parent: M001
milestone: M001
provides:
  - StubAI.plot_all_ai_ships() for TurnPhaseController to call before resolution
requires:
  []
affects:
  []
key_files:
  - scripts/server/stub_ai.gd
  - test/unit/test_stub_ai.gd
key_decisions:
  - AI ships use real plotting protocol (not direct state writes) — same code path as player/remote clients
  - Default strategy is 'forward' rather than roadmap's 'hold' — more useful for testing
  - Contests and bearing-off resolved mechanically via dice rolls in resolver, not interactive AI prompts
patterns_established:
  - (none)
observability_surfaces:
  - none
drill_down_paths:
  []
duration: ""
verification_result: passed
completed_at: 2026-05-12T18:49:19.469Z
blocker_discovered: false
---

# S08: StubAI drives plotting protocol for non-player ships

**StubAI plots all non-player ships through the real MovementPlottingController protocol with full rule validation and 13 passing tests.**

## What Happened

StubAI (scripts/server/stub_ai.gd, 110 lines) identifies non-player ships (player_id != 0) and plots each one through the real MovementPlottingController — handle_start_plotting, handle_select_hex (for forward strategy), handle_submit_movement. This ensures AI plots are rule-validated identically to player plots. The default "forward" strategy consumes full MA by iterating valid_next_hexes.forward; the "hold" strategy submits immediately with an empty path. Sessions are properly cleaned up after each ship. A _get_strategy() hook exists for future scenario-configurable strategies. 13 tests cover AI ship detection, forward strategy mechanics, session cleanup, integration with the resolver, and edge cases (zero MA luffing, idempotent re-plotting).

## Verification

All 259 tests pass (make test), including 13 StubAI-specific tests covering AI detection, forward strategy, session cleanup, resolver integration, and edge cases.

## Requirements Advanced

None.

## Requirements Validated

None.

## New Requirements Surfaced

None.

## Requirements Invalidated or Re-scoped

None.

## Operational Readiness

None.

## Deviations

None.

## Known Limitations

None.

## Follow-ups

None.

## Files Created/Modified

- `scripts/server/stub_ai.gd` — StubAI class — plots non-player ships via real plotting protocol
- `test/unit/test_stub_ai.gd` — 13 tests for StubAI covering all categories
