# S06: MovementResolver single-ship: impulse loop + tacking roll + in-irons escape — UAT

**Milestone:** M001
**Written:** 2026-05-12T18:38:49.665Z

## UAT: S06 — MovementResolver single-ship

### Prerequisites
- Godot 4.6 installed, project imports clean

### Test 1: Full test suite passes
```bash
make test
```
**Expected:** 259/259 tests pass, no failures

### Test 2: Resolver test file passes
```bash
make test-file F=test/unit/test_movement_resolver.gd
```
**Expected:** All resolver tests pass (normal movement, tacking success/failure, in-irons escape, DRMs, determinism, multi-ship)

### Test 3: Key code artifacts exist
```bash
grep -q 'class ResolutionLog' scripts/server/movement_types.gd && echo OK
grep -q 'func run' scripts/server/movement_resolver.gd && echo OK
grep -q '_roll_tacking' scripts/server/movement_resolver.gd && echo OK
grep -q '_resolve_in_irons_escape' scripts/server/movement_resolver.gd && echo OK
```
**Expected:** All four print OK
