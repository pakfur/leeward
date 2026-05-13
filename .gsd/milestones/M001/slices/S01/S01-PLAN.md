# S01: DataManager rule wrappers + scenario seed validation

**Goal:** Add the DataManager bearing-off probability wrapper (with its data file + unit tests) and harden scenario loading: scenario `seed` becomes mandatory with `-1` meaning "generate fresh", crew_quality words normalize to letters on load, and the existing scenario fixtures gain the required fields. This closes the slice's boundary contract to S02 (validated scenario dict carrying `seed: int`) and to S03+ (typed `get_bearing_off_probability(crew_quality, maneuverability) -> float` lookup with assert() validation).
**Demo:** make test-file F=test/unit/test_data_manager_bearing_off.gd passes; loading a scenario without `seed` hard-errors; seed:-1 logs fresh-seed generation; crew_quality letter normalization complete.

## Must-Haves

- `make test-file F=test/unit/test_data_manager_bearing_off.gd` passes (new file).
- `make test-file F=test/unit/test_data_manager_scenarios.gd` passes with new tests covering: seed honored, seed:-1 generates a fresh non-negative seed, missing seed hard-errors via push_error + zero-size return, crew_quality "Trained"/"Veteran"/"Elite"/"Green" all normalize to single letters in the returned dict.
- `make test` passes overall with no regression in the other test_data_manager_*, test_trace, test_data_manager_ships, etc.
- `data/scenarios/test_basic.json` and `data/scenarios/test_fleet.json` both contain a top-level integer `seed` field; default-scenario fallback sets `seed: -1`.
- `data/rules/bearing_off_table.json` exists, parses cleanly, and exercises every (crew_quality, maneuverability) cell tested by the unit test.

## Proof Level

- This slice proves: contract — this slice proves DataManager rule-lookup boundary contracts and the scenario seed contract via unit tests on the real JSON tables. No runtime/UI integration in this slice.

## Integration Closure

Upstream surfaces consumed: `scripts/autoload/data_manager.gd` (existing load_*_table / get_* pattern), `scripts/autoload/trace.gd` (used for seed:-1 log line). New wiring introduced: `bearing_off_table` loaded from a new JSON file; `load_scenario` now mutates the returned dict (seed resolution + crew_quality normalization). What remains before M001 is usable end-to-end: GameState must actually call `load_bearing_off_table()` at startup (deferred — first consumer in S06 will add the autoload line); GameState.rng seeded from the validated seed (S02); the validator + resolver themselves (S03/S06/S07).

## Verification

- Runtime signals: `Trace.trace_log("ScenarioLoad", ...)` on each scenario load — logs the scenario name, the resolved seed value, and whether it came from JSON or was generated from `-1`. Failure visibility: missing-seed scenarios produce a `push_error` with the scenario name and the offending dict keys; the function returns `{}` so callers see a zero-size dict (matches existing failure shape). Inspection surfaces: F12 dev UI already surfaces Trace categories — ScenarioLoad will appear there automatically. Redaction constraints: none (no PII / secrets in scenario data).

## Tasks

- [ ] **T01: Add bearing_off_table.json + DataManager wrapper + unit tests** `est:1h30m`
  Create `data/rules/bearing_off_table.json` keyed by crew_quality letter (A..G) → maneuverability letter (a..d) → float success probability (0.0..1.0). Probabilities derive from CA rules VI.D.2 (roll SK or more on d6 with class DRMs: -1 class 1, +0 class 2, +1 class 3, +2 class 4) using the mapping SK = numeric value of CQ letter (A=1..G=7) and maneuverability serving as a class proxy (a=class1..d=class4). Document the derivation in a top-level `_doc` field inside the JSON. Then in `scripts/autoload/data_manager.gd`: add `var bearing_off_table: Dictionary = {}`; add `func load_bearing_off_table(file_path: String = "res://data/rules/bearing_off_table.json") -> bool` mirroring the existing load_*_table funcs (push_warning + return false on missing, push_error on parse failure, store Dictionary on success); add `func get_bearing_off_probability(crew_quality: String, maneuverability: String) -> float` with assert() on both params (crew_quality A..G case-insensitive, maneuverability a..d case-insensitive), returning 0.0 on any missing key with a push_error. Create `test/unit/test_data_manager_bearing_off.gd` extending GutTest following the existing test_data_manager_speed_change.gd pattern: before_all loads the table; tests cover table-loads-successfully, has-all-crew-quality-grades, has-all-maneuverability-grades, at least 4 known-value lookups (regression anchors picked from the JSON), case-insensitivity for both params, and a sanity check that better crew quality (lower letter) yields >= probability than worse crew quality at the same maneuverability. Do NOT modify GameState — the autoload call to load_bearing_off_table() is deferred to its first real consumer.
  - Files: `data/rules/bearing_off_table.json`, `scripts/autoload/data_manager.gd`, `test/unit/test_data_manager_bearing_off.gd`
  - Verify: make test-file F=test/unit/test_data_manager_bearing_off.gd 2>&1 | grep -E 'Pass|Fail|Error' | tee /tmp/s01_t01_verify.log && grep -q 'Fail' /tmp/s01_t01_verify.log && exit 1 || true

- [ ] **T02: Add seed validation, fresh-seed generation, and crew_quality normalization to load_scenario** `est:2h`
  Modify `scripts/autoload/data_manager.gd::load_scenario(scenario_name)` so that after JSON parsing succeeds it (a) validates that the dict contains an integer `seed` field — missing or non-int field → `push_error("Scenario %s missing required 'seed' field" % scenario_name)` + return `{}`; (b) if `seed == -1`, generate a fresh seed via `int(Time.get_unix_time_from_system())` (cast to int from float; ensure non-negative), write it back into the returned dict, and `Trace.trace_log("ScenarioLoad", "Generated fresh seed for scenario %s" % scenario_name, fresh_seed)`; (c) otherwise `Trace.trace_log("ScenarioLoad", "Loaded scenario %s with seed" % scenario_name, scenario_dict["seed"])`. Add private helper `func _normalize_crew_quality(text: String) -> String` that maps the words used in existing scenarios to letters: "Elite" → "A", "Veteran" → "B", "Crack" → "C", "Trained" → "D", "Green" → "E", "Poor" → "F", "Demoralized" → "G". Pass-through any already-letter value (A..G, upper-cased). Push_warning for any unknown value and pass it through unchanged. After seed resolution, iterate `scenario_dict["ships"]` and replace each ship's `crew_quality` with the normalized letter form. Update `_create_default_scenario()` to include `"seed": -1` (so the fallback path still works). Update `data/scenarios/test_basic.json` and `data/scenarios/test_fleet.json` to add `"seed": 42` at the top level (concrete deterministic value for tests). Expand `test/unit/test_data_manager_scenarios.gd`: (a) new test `test_scenario_has_seed_field` asserting the loaded test_basic dict has `seed` as a positive int (42); (b) new test `test_seed_minus_one_generates_fresh_seed` that loads a transient scenario via a small temp-file helper (or by mutating a duplicated dict and re-saving to a `user://` path) and asserts the returned seed is > 0 and not -1; (c) new test `test_missing_seed_hard_errors` that writes a minimal scenario without a seed to `user://test_scenario_no_seed.json`, calls a helper that mirrors `load_scenario` reading from that path (or reuses load_scenario with a path override added in this task — preferred), and asserts the result is an empty Dictionary plus `assert_engine_error("missing required 'seed' field")`; (d) new test `test_crew_quality_normalized_to_letters` loading test_basic and asserting the player ship's `crew_quality` is exactly one uppercase letter in A..G (not "Trained"); (e) update the existing `test_nonexistent_scenario_returns_default` so it tolerates the new ScenarioLoad trace line. To support the temp-file tests cleanly, add an optional `file_path` override parameter to `load_scenario` (signature: `func load_scenario(scenario_name: String, file_path: String = "") -> Dictionary`) where empty `file_path` keeps the existing behavior (build from name). This keeps the surface backward-compatible.
  - Files: `scripts/autoload/data_manager.gd`, `data/scenarios/test_basic.json`, `data/scenarios/test_fleet.json`, `test/unit/test_data_manager_scenarios.gd`
  - Verify: make test-file F=test/unit/test_data_manager_scenarios.gd 2>&1 | tee /tmp/s01_t02_verify.log && ! grep -qE 'Failures|Errors' /tmp/s01_t02_verify.log

- [ ] **T03: Run full test suite and confirm no regressions** `est:20m`
  Run `make test` and verify all tests are green. If any pre-existing test fails because of the new seed requirement or the crew_quality normalization, the fix lives here — but the intended outcome is no regressions, since T02 already updated both scenario JSON files and the default-fallback scenario. Capture the full test output to `/tmp/s01_t03_make_test.log` and confirm: (a) the bearing-off test file is in the run, (b) no Failures/Errors lines appear, (c) the existing test_data_manager_movement, test_data_manager_ships, test_data_manager_speed_change, test_data_manager_tacking, test_data_manager_turning, test_data_manager_scenarios, and test_trace all still pass. This task creates no new code; it is the verification gate for the slice.
  - Verify: make test 2>&1 | tee /tmp/s01_t03_make_test.log && ! grep -qE 'Failures|Errors|FAIL' /tmp/s01_t03_make_test.log

## Files Likely Touched

- data/rules/bearing_off_table.json
- scripts/autoload/data_manager.gd
- test/unit/test_data_manager_bearing_off.gd
- data/scenarios/test_basic.json
- data/scenarios/test_fleet.json
- test/unit/test_data_manager_scenarios.gd
