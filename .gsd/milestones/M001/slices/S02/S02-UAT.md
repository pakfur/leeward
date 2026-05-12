# S02: Shared seeded RNG on GameState; EnvironmentController migrated — UAT

**Milestone:** M001
**Written:** 2026-05-12T16:05:20.683Z

## UAT: S02 — Shared seeded RNG\n\n### Checks\n\n- [ ] `GameState.rng` property exists and is non-null after `start_new_game()`\n- [ ] Same scenario seed produces identical wind sequences across runs\n- [ ] Different seeds produce different sequences\n- [ ] EnvironmentController has no private RNG\n- [ ] All 8 tests in test_rng_determinism.gd pass\n- [ ] No regression in existing test suite
