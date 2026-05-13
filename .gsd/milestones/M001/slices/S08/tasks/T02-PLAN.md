---
estimated_steps: 1
estimated_files: 1
skills_used: []
---

# T02: StubAI test suite

Comprehensive tests: AI ship detection (no-AI no-error, only non-player-zero, multiple AI ships), forward strategy (straight line, respects MA, different facings), session cleanup, integration with plotting protocol and resolver, edge cases (zero MA/luffing, idempotency).

## Inputs

- `StubAI class`
- `GameState test harness`

## Expected Output

- `test/unit/test_stub_ai.gd with 13 test methods`

## Verification

make test-file F=test/unit/test_stub_ai.gd — all 13 tests pass
