# S01: DataManager Rule Tables + Scenario Hardening — UAT

**Milestone:** M001
**Written:** 2026-05-12T14:55:51.047Z

## UAT: S01 — DataManager Rule Tables + Scenario Hardening

### Bearing Off Table
- [ ] `make test-file F=test/unit/test_data_manager_bearing_off.gd` — 11/11 pass
- [ ] `DataManager.get_bearing_off_probability("A", "a")` returns ~0.833 (5/6)
- [ ] Case insensitive: `get_bearing_off_probability("a", "A")` works

### Scenario Seed Validation
- [ ] Loading test_basic.json returns seed=42
- [ ] Scenario with seed=-1 generates a positive fresh seed
- [ ] Scenario missing seed field returns empty dict + push_error

### Crew Quality Normalization
- [ ] "Trained" in scenario JSON normalizes to "D" in loaded dict
- [ ] Single-letter grades (A-G) pass through unchanged

### Preexisting Test Fixes
- [ ] `make test` — all 196 tests pass with 0 failures
- [ ] `make clean && make import && make test` — same result (clean-room)

### Key Data Files
- [ ] ships.json: crew_count arrays have 4 elements each
- [ ] speed_change_table.json: lowercase a/b/c/d keys, no "readme"
- [ ] tacking_table.json: lowercase a/b/c/d keys, no "readme"
- [ ] turning_table.json: no "readme" key
