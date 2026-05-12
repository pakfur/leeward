# S08: StubAI drives plotting protocol for non-player ships

**Goal:** StubAI drives the plotting protocol for non-player ships so AI ships have valid plotted movements before resolution.
**Demo:** Player-1 ships get plotted via real protocol before PLANNING UI is interactive; trace logs show stub strategy + per-ship plot. Stub-AI prompt answers (no-surrender, no-bear-off) injected at resolution.

## Must-Haves

- StubAI plots all non-player ships via MovementPlottingController; plots are rule-validated; sessions cleaned up after plotting; 13+ tests pass covering AI detection, forward strategy, session cleanup, integration with resolver, and edge cases.

## Verification

- Run the task and slice verification checks for this slice.

## Tasks

- [x] **T01: StubAI class with plotting protocol integration** `est:30m`
  Implement StubAI class that identifies non-player ships (player_id != 0), calls handle_start_plotting/handle_select_hex/handle_submit_movement on MovementPlottingController for each, with forward and hold strategies.
  - Files: `scripts/server/stub_ai.gd`
  - Verify: make test-file F=test/unit/test_stub_ai.gd passes all tests

- [x] **T02: StubAI test suite** `est:30m`
  Comprehensive tests: AI ship detection (no-AI no-error, only non-player-zero, multiple AI ships), forward strategy (straight line, respects MA, different facings), session cleanup, integration with plotting protocol and resolver, edge cases (zero MA/luffing, idempotency).
  - Files: `test/unit/test_stub_ai.gd`
  - Verify: make test-file F=test/unit/test_stub_ai.gd — all 13 tests pass

## Files Likely Touched

- scripts/server/stub_ai.gd
- test/unit/test_stub_ai.gd
