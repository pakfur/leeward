---
estimated_steps: 1
estimated_files: 3
skills_used: []
---

# T01: Add bearing_off_table.json + DataManager wrapper + unit tests

Create `data/rules/bearing_off_table.json` keyed by crew_quality letter (A..G) → maneuverability letter (a..d) → float success probability (0.0..1.0). Probabilities derive from CA rules VI.D.2 (roll SK or more on d6 with class DRMs: -1 class 1, +0 class 2, +1 class 3, +2 class 4) using the mapping SK = numeric value of CQ letter (A=1..G=7) and maneuverability serving as a class proxy (a=class1..d=class4). Document the derivation in a top-level `_doc` field inside the JSON. Then in `scripts/autoload/data_manager.gd`: add `var bearing_off_table: Dictionary = {}`; add `func load_bearing_off_table(file_path: String = "res://data/rules/bearing_off_table.json") -> bool` mirroring the existing load_*_table funcs (push_warning + return false on missing, push_error on parse failure, store Dictionary on success); add `func get_bearing_off_probability(crew_quality: String, maneuverability: String) -> float` with assert() on both params (crew_quality A..G case-insensitive, maneuverability a..d case-insensitive), returning 0.0 on any missing key with a push_error. Create `test/unit/test_data_manager_bearing_off.gd` extending GutTest following the existing test_data_manager_speed_change.gd pattern: before_all loads the table; tests cover table-loads-successfully, has-all-crew-quality-grades, has-all-maneuverability-grades, at least 4 known-value lookups (regression anchors picked from the JSON), case-insensitivity for both params, and a sanity check that better crew quality (lower letter) yields >= probability than worse crew quality at the same maneuverability. Do NOT modify GameState — the autoload call to load_bearing_off_table() is deferred to its first real consumer.

## Inputs

- `scripts/autoload/data_manager.gd`
- `test/unit/test_data_manager_speed_change.gd`
- `test/unit/test_data_manager_tacking.gd`
- `docs/Close-Action-Rules-v6-1.txt`
- `Makefile`

## Expected Output

- `data/rules/bearing_off_table.json`
- `scripts/autoload/data_manager.gd`
- `test/unit/test_data_manager_bearing_off.gd`

## Verification

make test-file F=test/unit/test_data_manager_bearing_off.gd 2>&1 | grep -E 'Pass|Fail|Error' | tee /tmp/s01_t01_verify.log && grep -q 'Fail' /tmp/s01_t01_verify.log && exit 1 || true

## Observability Impact

Loader prints `Loaded bearing off table with N crew quality grades` on success (mirrors existing load_*_table functions). Bad-param asserts fail loudly via Godot assertion.
