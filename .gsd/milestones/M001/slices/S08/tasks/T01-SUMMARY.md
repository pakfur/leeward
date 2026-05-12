---
id: T01
parent: S08
milestone: M001
key_files:
  - scripts/server/stub_ai.gd
key_decisions:
  - Default strategy is 'forward' rather than 'hold' — more useful for testing and demos
  - AI ships identified by player_id != 0 (player 0 is the human player)
  - Uses real plotting protocol (handle_start_plotting/handle_select_hex/handle_submit_movement) rather than direct state writes
duration: 
verification_result: passed
completed_at: 2026-05-12T18:48:53.762Z
blocker_discovered: false
---

# T01: Implemented StubAI class that plots all non-player ships via the real MovementPlottingController protocol.

**Implemented StubAI class that plots all non-player ships via the real MovementPlottingController protocol.**

## What Happened

StubAI (110 lines) identifies non-player ships (player_id != 0), then for each: calls handle_start_plotting to open a session, executes a strategy (forward: iterates valid_next_hexes.forward consuming full MA; hold: submits immediately with empty path), and calls handle_submit_movement. All plots are rule-validated through the real plotting protocol — no direct writes to ShipState.plotted_actions. Error handling via push_error + Trace logging on start/submit failures. Default strategy is "forward" (more useful for testing than "hold"). Strategy hook _get_strategy() exists for future scenario-configurable strategies.

## Verification

All 13 StubAI tests pass within the full 259-test suite via make test.

## Verification Evidence

| # | Command | Exit Code | Verdict | Duration |
|---|---------|-----------|---------|----------|
| 1 | `make test` | 0 | 259 tests pass, 0 failures | 15000ms |

## Deviations

None.

## Known Issues

None.

## Files Created/Modified

- `scripts/server/stub_ai.gd`
