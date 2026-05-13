---
estimated_steps: 1
estimated_files: 4
skills_used: []
---

# T02: Add seed validation, fresh-seed generation, and crew_quality normalization to load_scenario

Modify `scripts/autoload/data_manager.gd::load_scenario(scenario_name)` so that after JSON parsing succeeds it (a) validates that the dict contains an integer `seed` field — missing or non-int field → `push_error("Scenario %s missing required 'seed' field" % scenario_name)` + return `{}`; (b) if `seed == -1`, generate a fresh seed via `int(Time.get_unix_time_from_system())` (cast to int from float; ensure non-negative), write it back into the returned dict, and `Trace.trace_log("ScenarioLoad", "Generated fresh seed for scenario %s" % scenario_name, fresh_seed)`; (c) otherwise `Trace.trace_log("ScenarioLoad", "Loaded scenario %s with seed" % scenario_name, scenario_dict["seed"])`. Add private helper `func _normalize_crew_quality(text: String) -> String` that maps the words used in existing scenarios to letters: "Elite" → "A", "Veteran" → "B", "Crack" → "C", "Trained" → "D", "Green" → "E", "Poor" → "F", "Demoralized" → "G". Pass-through any already-letter value (A..G, upper-cased). Push_warning for any unknown value and pass it through unchanged. After seed resolution, iterate `scenario_dict["ships"]` and replace each ship's `crew_quality` with the normalized letter form. Update `_create_default_scenario()` to include `"seed": -1` (so the fallback path still works). Update `data/scenarios/test_basic.json` and `data/scenarios/test_fleet.json` to add `"seed": 42` at the top level (concrete deterministic value for tests). Expand `test/unit/test_data_manager_scenarios.gd`: (a) new test `test_scenario_has_seed_field` asserting the loaded test_basic dict has `seed` as a positive int (42); (b) new test `test_seed_minus_one_generates_fresh_seed` that loads a transient scenario via a small temp-file helper (or by mutating a duplicated dict and re-saving to a `user://` path) and asserts the returned seed is > 0 and not -1; (c) new test `test_missing_seed_hard_errors` that writes a minimal scenario without a seed to `user://test_scenario_no_seed.json`, calls a helper that mirrors `load_scenario` reading from that path (or reuses load_scenario with a path override added in this task — preferred), and asserts the result is an empty Dictionary plus `assert_engine_error("missing required 'seed' field")`; (d) new test `test_crew_quality_normalized_to_letters` loading test_basic and asserting the player ship's `crew_quality` is exactly one uppercase letter in A..G (not "Trained"); (e) update the existing `test_nonexistent_scenario_returns_default` so it tolerates the new ScenarioLoad trace line. To support the temp-file tests cleanly, add an optional `file_path` override parameter to `load_scenario` (signature: `func load_scenario(scenario_name: String, file_path: String = "") -> Dictionary`) where empty `file_path` keeps the existing behavior (build from name). This keeps the surface backward-compatible.

## Inputs

- `scripts/autoload/data_manager.gd`
- `scripts/autoload/trace.gd`
- `test/unit/test_data_manager_scenarios.gd`
- `data/scenarios/test_basic.json`
- `data/scenarios/test_fleet.json`
- `.gsd/milestones/M001/M001-CONTEXT.md`

## Expected Output

- `scripts/autoload/data_manager.gd`
- `data/scenarios/test_basic.json`
- `data/scenarios/test_fleet.json`
- `test/unit/test_data_manager_scenarios.gd`

## Verification

make test-file F=test/unit/test_data_manager_scenarios.gd 2>&1 | tee /tmp/s01_t02_verify.log && ! grep -qE 'Failures|Errors' /tmp/s01_t02_verify.log

## Observability Impact

Adds a new `ScenarioLoad` Trace category visible in the F12 dev UI. Every scenario load now produces a trace line carrying the resolved seed and whether it was generated. Missing-seed failure produces a push_error with the scenario name.
