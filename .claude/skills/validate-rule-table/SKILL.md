---
name: validate-rule-table
description: Validate that data/rules/movement_allowance.json conforms to the project's 5-level lookup schema (speed_type → wind_facing → wind_speed → rigging_quality → sail_state → MA). Catches typos, missing speed_types, illegal keys, and non-integer leaves that would silently return 0 at lookup time. Run after editing the table and before committing rule changes.
disable-model-invocation: true
---

# validate-rule-table

Run the validator before committing any change to `data/rules/movement_allowance.json`. The file is a 5-level nested lookup where every key is a string — typos turn into silent zeros at `DataManager.get_movement_allowance()` call sites, with no error.

## Usage

```bash
python3 .claude/skills/validate-rule-table/scripts/validate.py
```

Optional path argument (defaults to `data/rules/movement_allowance.json`):

```bash
python3 .claude/skills/validate-rule-table/scripts/validate.py path/to/some_table.json
```

Exit codes: `0` clean (or warnings only), `1` schema errors, `2` file missing or invalid JSON.

## What gets checked

| Level | Valid keys | On violation |
|-------|------------|--------------|
| 1 — speed_type | `L/F`, `L/S`, `L/VS`, `F/F`, `F/S`, `F/VS`, `C/F`, `C/S`, `C/VS` | error if extra/missing |
| 2 — wind_facing | `C`, `B`, `R` | error if extra/missing; `L` is **forbidden** (DataManager handles luffing in code, returning 0 without consulting the table) |
| 3 — wind_speed | `"1"`, `"2"`, `"3"`, `"4"` (strings) | error if extra; warning if missing |
| 4 — rigging_quality | `"1"`, `"2"`, `"3"`, `"4"` (strings) | error if extra; warning if missing |
| 5 — sail_state | `fs`, `ms`, `ps`, `ns` (lowercase) | error if extra |
| Leaf — MA value | non-negative integer | error otherwise |

## Errors vs warnings

**Errors** are unambiguous bugs (wrong key, wrong type, negative value, the forbidden `L` facing). Fix before committing.

**Warnings** flag sparseness — a missing wind_speed or rigging_quality entry. The lookup will return 0 for those paths, which is sometimes intentional (low rigging quality with no usable sail) and sometimes an oversight. Read each warning and decide; warnings alone do not fail the run.

## Example: clean run

```
$ python3 .claude/skills/validate-rule-table/scripts/validate.py
Validating data/rules/movement_allowance.json...
OK: no errors, no warnings.
```

## Example: catching a bug

A common mistake is typing `"FS"` instead of `"fs"`:

```
ERRORS (1):
  F/F.B.2.4.FS: sail_state key must be one of 'fs','ms','ps','ns' (lowercase)
```

Without the validator, `DataManager.get_movement_allowance("F/F", 2, "B", "fs", 4)` would return `0` silently (the `fs` key isn't there — `FS` is), and the ship would sit in the harbor wondering why it can't move.

## Extending to other rule tables

`bearing_off_table.json`, `speed_change_table.json`, `tacking_table.json`, and `turning_table.json` have their own shapes — the script only validates `movement_allowance.json` today. If you add validation for another table, add a `validate_<table_name>()` function alongside `validate_movement_allowance()` and dispatch on the filename in `main()`.
