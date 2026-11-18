# Proportional Movement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve movement at proportional pace. Step k of an N-step plot happens at time k/N, so faster ships reach contested hexes first. This replaces front-loaded movement (6.A.2) and 14.A.

**Architecture:**
- A pure `MoveSchedule` turns each ship's plot size into exact rational step times. The distinct times are the resolver's segments.
- The resolver first learns to ask the schedule for "which step on which segment", under a temporary front-loaded mode that changes nothing (Task 2).
- Then the mode is flipped to proportional, with the 6.B overlap window redefined (Task 3).
- The movement log gains per-segment and per-event times (Task 4). The view plays each ship at its own pace on one clock (Task 5).

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5. `make test` runs the whole suite. Run `make import` first whenever a new `class_name` is added.

**Spec:** `docs/superpowers/specs/2026-11-17-proportional-movement-design.md`. Executors read it alongside this plan. The binding requirements are in `docs/superpowers/specs/2026-11-17-subprojects-3-7-decisions.md` §0–§1. The rules are in `docs/rules/close_action.md` 6.A–6.F and 14.A.

## Global Constraints

- A time is a reduced `Vector2i(num, den)`. Compare times only by integer cross-multiplication (`MoveSchedule.compare`), never as floats. Floats are allowed only in the view's clock.
- Step j (0-based) of an N-step plot is at time (j + 1)/N. Turns count as steps.
- The schedule is built once per `MovementResolver.run()`, from each ship's plot after poor maneuvering. Amended plots never rebuild it.
- An amended plot's m-th step beyond its N is at time 1 + m: a trailing segment shared by every ship's m-th extra step.
- Every die is drawn from the resolver's `rng` (the accepted Dice exception). Dice order per pass:
  1. the PM rolls (once, before the passes);
  2. the MA-0 tacking rolls and dropped-tack redraws, in ship order, before the first segment;
  3. then the segment dice.
- Gunfire stays after movement. Exact ties keep today's simultaneous rules (6.C contests, potential collisions, 6.D.3c order).
- `ResolutionEvent.impulse` keeps its name and means the segment index. Segment indices, `BearOffSituation.segment`, `resume_impulse` and the `{choice, segment}` decisions keep their types. `TurnPhaseController` does not change.
- Use `Trace`, never `print()`. Nothing in `scripts/view`, `scripts/ui` or `scripts/core` writes game state (`test_server_authority.gd` must stay green).
- `make test` is green at the end of every task. A test that encoded front-loaded timing is updated in the task that changes the timing. Its expected values are re-derived from the new times, and a one-line `# proportional movement: …` comment gives the times.
- The PostToolUse hook runs the full `make test` after edits under `scripts/server/`, `scripts/state/`, `scripts/core/`, `scripts/autoload/` and `test/unit/`. Expect that run after every such edit.

## Review Focus

1. **Fleets that plot equal step counts must resolve exactly as before.** Task 3 may change only tests whose interacting ships plot different step counts, or that pair an MA-0 turn with a longer plot. Pinned by Task 1 `test_equal_plots_keep_step_per_segment` and Task 3 `test_equal_plots_resolve_step_per_segment`.
2. **A bear-off re-run with unequal paces must repeat everything before the paused segment.** Pinned by Task 3 `test_bear_off_rerun_repeats_the_prefix_with_unequal_paces`.
3. **An amended plot longer than the plot** (deceleration minimum at a new heading) trails after every ship's last step, at a stable index. Pinned by Task 1 `test_trailing_steps_follow_every_scheduled_time` and Task 3 `test_bear_off_amendment_trails_after_the_last_segment`.
4. **An overlap whose next segment index belongs to a third ship** must not be judged there. Pinned by Task 3 `test_overlap_waits_for_the_next_segment_either_ship_moves`.
5. **Resuming after a bear-off pause must not jump a slow ship that rests between steps.** Pinned by Task 5 `test_resumed_glide_starts_at_the_resume_clock`.

---

### Task 1: `MoveSchedule`, exact step times

**Files:**
- Create: `scripts/server/move_schedule.gd`.
- Test: create `test/unit/test_move_schedule.gd`.

**Interfaces (Produces):**

```gdscript
class_name MoveSchedule
extends RefCounted
const START := Vector2i(0, 1)   # pre-movement events
const END := Vector2i(1, 0)     # the end check after the last segment; greater than every time
static func reduce(num: int, den: int) -> Vector2i
static func compare(a: Vector2i, b: Vector2i) -> int   # -1, 0, 1; den 0 (END) is greatest
static func step_time(step: int, steps: int) -> Vector2i   # (step+1)/steps for step < steps, else (step - steps + 2, 1)
var plot_steps: Dictionary   # ship_id -> N (plot size this run)
var times: Array[Vector2i]   # distinct step times <= 1 over all ships, ascending
var front_loaded: bool       # TEMPORARY (Task 2 only; Task 3 deletes it)
func _init(p_plot_steps: Dictionary, p_front_loaded: bool = false) -> void
func segment_of(ship_id: String, step: int) -> int
func step_at(ship_id: String, segment: int) -> int        # -1 when the ship has no step there (N == 0: always -1)
func steps_before(ship_id: String, segment: int) -> int   # the ship's scheduled steps on segments < segment
func segment_count(steps_by_ship: Dictionary) -> int      # ship_id -> Array of steps; times.size() + the most extra steps
func time_of(segment: int) -> Vector2i                     # times[i]; trailing i -> (2 + i - times.size(), 1)
func next_segment(ship_ids: Array, after: int, steps_by_ship: Dictionary) -> int
	# first segment > after on which any of ship_ids has a step j < steps_by_ship[id].size(); else segment_count(steps_by_ship)
```

How each query is computed:
- Proportional. `segment_of(sid, j)` is the index of `step_time(j, N)` in `times` for j < N, and `times.size() + (j - N)` beyond. `step_at` is its inverse. For trailing segments (index ≥ `times.size()`) it returns `N + (segment - times.size())` when N > 0.
- Front-loaded (temporary). `times` is empty, `segment_of(sid, j) == j`, `step_at(sid, s) == s` (−1 when N == 0), `steps_before(sid, s) == s`, `segment_count` is the largest step count, and `time_of(i) == Vector2i(i + 1, 1)`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_move_schedule.gd` (`extends GutTest`). Use `var s := MoveSchedule.new({"a": 8, "b": 3})`:
  - `test_times_are_the_distinct_step_times_in_order`: `s.times == [Vector2i(1,8), Vector2i(1,4), Vector2i(1,3), Vector2i(3,8), Vector2i(1,2), Vector2i(5,8), Vector2i(2,3), Vector2i(3,4), Vector2i(7,8), Vector2i(1,1)]`.
  - `test_segment_of_and_step_at`:
    - `s.segment_of("a", 3) == 4` (4/8 = 1/2), `s.segment_of("b", 1) == 6`, `s.segment_of("b", 2) == 9` and `s.segment_of("a", 7) == 9`.
    - `s.step_at("b", 6) == 1`, `s.step_at("b", 5) == -1` and `s.step_at("a", 2) == -1`.
  - `test_steps_before`: `s.steps_before("b", 6) == 1`, `s.steps_before("b", 7) == 2`, `s.steps_before("a", 4) == 3` and `s.steps_before("b", 10) == 3`.
  - `test_reduce_and_compare`:
    - `MoveSchedule.reduce(2, 6) == Vector2i(1, 3)`.
    - `MoveSchedule.compare(Vector2i(1,3), Vector2i(3,8)) == -1`, `compare(Vector2i(2,3), Vector2i(2,3)) == 0`, `compare(MoveSchedule.END, Vector2i(5,1)) == 1` and `compare(Vector2i(1,1), Vector2i(2,1)) == -1`.
  - `test_trailing_steps_follow_every_scheduled_time`:
    - `s.segment_of("b", 3) == 10` and `s.segment_of("b", 4) == 11`.
    - `s.time_of(10) == Vector2i(2, 1)` and `s.time_of(11) == Vector2i(3, 1)`.
    - `s.segment_count({"a": [8 dummy steps], "b": [5 dummy steps]}) == 12` and `s.segment_count({"a": [8], "b": [3]}) == 10` (arrays of that length).
    - `MoveSchedule.step_time(4, 3) == Vector2i(3, 1)`.
  - `test_next_segment`:
    - `s.next_segment(["b"], 2, steps) == 6` with steps of sizes a = 8, b = 3.
    - `s.next_segment(["a", "b"], 4, steps) == 5`.
    - `s.next_segment(["b"], 9, steps) == 10` (the end check).
  - `test_equal_plots_keep_step_per_segment`: `MoveSchedule.new({"x": 4, "y": 4})` has `times == [Vector2i(1,4), Vector2i(1,2), Vector2i(3,4), Vector2i(1,1)]`, and `segment_of(id, j) == j` for both ids and j in 0..3.
  - `test_empty_plot_has_no_times`: `MoveSchedule.new({"z": 0, "a": 2})` has `times == [Vector2i(1,2), Vector2i(1,1)]` and `step_at("z", 0) == -1`.
  - `test_ma0_turn_is_at_the_end`: `MoveSchedule.new({"t": 1, "a": 4}).segment_of("t", 0) == 3`.
  - `test_front_loaded_mode_is_step_per_segment`: `MoveSchedule.new({"a": 8, "b": 3}, true)` has `segment_of("b", 2) == 2`, `step_at("b", 2) == 2`, `step_at("b", 5) == 5` (unbounded; callers bound by step count), `steps_before("a", 4) == 4` and `segment_count({"a": [8], "b": [3]}) == 8`.
- [ ] **Step 2: Run and confirm failure.** Run `make import && make test`. Expected: failures (parse error) in `test_move_schedule.gd` only.
- [ ] **Step 3: Implement `scripts/server/move_schedule.gd`** with the interface above. Build `times` with `compare` and a sorted insert, no floats. Add a `##` header saying it is pure and that the front-loaded mode is a temporary refactoring aid.
- [ ] **Step 4: Run and confirm everything passes.** Run `make import && make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/move_schedule.gd test/unit/test_move_schedule.gd
git commit -m "feat: MoveSchedule, exact proportional step times"
```

### Task 2: The resolver reads the schedule (no behaviour change)

Every place in `scripts/server/movement_resolver.gd` that treats a segment number as a step number now asks `MoveSchedule`. The schedule is built front-loaded, so **every existing test passes unchanged**. That is this task's gate: no file under `test/` is edited.

**Files:**
- Modify: `scripts/server/movement_resolver.gd`.

**Interfaces:**
- Consumes `MoveSchedule` (Task 1).
- Produces, all in `movement_resolver.gd`:
  - `var _schedule: MoveSchedule = null`, set in `run()` right after the poor-maneuvering loop: `MoveSchedule.new(plot_sizes, true)`, where `plot_sizes[sid] = plotted[sid].size()`.
  - `func _roll_pre_movement(p: ResolutionPass, ships: Array[ShipState]) -> void`. It is called in `_resolve_pass` after the per-ship result setup and before the segment loop. For each ship in order:
    - if `p.tacks_dropped.has(sid)`: `_redraw_dropped_tack`;
    - elif it is not stopped and `_find_tacking_impulse(ship, steps) == 0`: today's tacking block (`_roll_tacking` with impulse 0, the 6.F.5 IMMOBILIZED "poor maneuvering failed" event, and on failure `final_hex`/`final_facing`/`immobilized`/`tacking_failed` and `p.stopped`).
    - The tacking block and the `impulse == 0` redraw leave `_resolve_impulse`.
  - Every rollback, lost-contest and bear-off record (`p.pending_overlaps` entries, `p.contest_amendments`, `p.bear_off_amendments`) gains `"step": int`, the turning or blocked ship's step index on that segment (`_schedule.step_at(sid, segment)`). `Segment.swings[sid]` gains `"step"` too.
  - `_all_on_last_step(p: ResolutionPass, ids: Array, segment: int) -> bool`: true when `_schedule.step_at(sid, segment) == p.steps_by_ship[sid].size() - 1` for every id.

- [ ] **Step 1: Confirm the baseline.** Run `make test` and note the pass count.
- [ ] **Step 2: Rewrite the step lookups.**
  - `_resolve_pass` loops `for impulse in range(_schedule.segment_count(p.steps_by_ship) + 1)`. Its `max_impulses` is `_schedule.segment_count(p.steps_by_ship)`.
  - `_resolve_impulse`, for each ship that is not stopped, with `var steps: Array = p.steps_by_ship[sid]`:
    - if `_schedule.steps_before(sid, impulse) >= steps.size()`, set `p.stopped[sid] = true` and continue;
    - `var j := _schedule.step_at(sid, impulse)`; if `j < 0 or j >= steps.size()`, continue (idle);
    - otherwise the step is `steps[j]`.
  - `_amended_steps` keeps `steps.slice(0, rollback.step)`.
  - `_stern_contest` gives the loser's deceleration test `<= loser_step`.
  - `bear_off_situation` builds its path from `slice(0, _schedule.step_at(sid, impulse))`. `other_plots` lists the steps j with `_schedule.segment_of(other_id, j) >= impulse`.
  - `_reached_segment(result, segment)` compares the MOVEs before `segment` with `_schedule.steps_before(result.ship_id, segment)` (and keeps the `stopped_at_impulse` test).
  - `_record_rollback` and `_record_contest` use `steps_resolved <= rollback.step` / `contest.step`.
  - `_record_steering`:
    - before the reached test, a PM event that is not the MA-0 roll (`pm.tack_rolled` false) gets `ev.impulse = _schedule.segment_of(sid, ev.impulse)`;
    - the "sailed the whole plot" test becomes `_reached_segment(result, _schedule.segment_of(ship_state.ship_id, steps.size()))`.
  - Leave `_check_overlaps` (`segment != impulse - 1`) and `_record_rollback`'s `segment + 1` as they are. Task 3 changes them.
- [ ] **Step 3: Run the suite.** Run `make test`. Expected: the same pass count as Step 1, zero failures, and no test file changed (`git status --short test/` is empty).
- [ ] **Step 4: Commit.**

```bash
git add scripts/server/movement_resolver.gd
git commit -m "refactor: movement resolver reads step times from MoveSchedule (front-loaded, no behaviour change)"
```

### Task 3: Proportional pace on

**Files:**
- Modify: `scripts/server/move_schedule.gd` (delete `front_loaded`), `scripts/server/movement_resolver.gd`.
- Modify: `test/unit/test_move_schedule.gd` (delete `test_front_loaded_mode_is_step_per_segment`).
- Modify: the existing tests that encode front-loaded timing, wherever they fail. Expected in `test/unit/test_movement_resolver.gd`, `test_bear_off_order.gd`, `test_deceleration.gd`, `test_critical_steering.gd`, `test_bear_off_phase.gd`, and possibly `test_game_loop.gd`, `test_battle_to_victory.gd` and `test_stub_ai.gd`.
- Test: add a section `# Proportional movement (6.A.2 replaced, 14.A)` to `test/unit/test_movement_resolver.gd`. It reuses `_make_ship_state`, `_plot_straight`, `_plot_turn`, `_events_of` and `_bear_off_setup`.

**Interfaces:**
- `MoveSchedule._init(p_plot_steps: Dictionary)`: the front-loaded mode and every branch for it are gone.
- `run()` builds `MoveSchedule.new(plot_sizes)`.
- Overlap records gain `"check_segment": int` = `_schedule.next_segment([sid] + other_ids, seg.impulse, p.steps_by_ship)`, set in `_note_overlaps`.
- `_check_overlaps(p, impulse)` checks the records whose `check_segment == impulse`.
- `_record_rollback` logs OVERLAP_ROLLBACK on `rollback.check_segment`. `run()` raises `log.max_impulses` to `rollbacks[sid].check_segment + 1`.
- `static func _undone_turn_segment(result: MovementTypes.ShipResolutionResult, event_type: int) -> int` replaces the `lag` arithmetic in `_undone_turn_ended_movement`. For STERN_BLOCKED it is that event's impulse. For OVERLAP_ROLLBACK it is the impulse of the last OVERLAP event before it in `result.events`. It returns −1 if there is none.

Shared setup for the new tests. Wind direction 0 (from E). The resolver checks no MA except for MA-0 turns, so store plots directly.
- `fast`: `_make_ship_state(Vector2i(0, 5), 0, 3, "C", "fast")`, `_plot_straight(fast, 8)`.
- `slow`: `_make_ship_state(Vector2i(4, 3), 1, 3, "C", "slow")`, `_plot_straight(slow, 3)`. It enters (4,4), (4,5), (4,6).
- The segments are then 1/8, 1/4, 1/3, 3/8, 1/2, 5/8, 2/3, 3/4, 7/8, 1 (indices 0–9).

- [ ] **Step 1: Write the failing tests:**
  - `test_fast_ship_takes_the_hex_first`: run with `{"slow": {"choice": MovementTypes.BEAR_OFF_COLLIDE, "segment": 6}}`. Assert:
    - `fast`'s MOVE with impulse 4 has `to_hex == Vector2i(4, 5)`;
    - `slow`'s `collided_with == "fast"`, its COLLISION event impulse is 6, and `slow.final_hex == Vector2i(4, 4)`;
    - `fast.final_hex == Vector2i(5, 5)` (6.E.2: both stop).
  - `test_slow_ship_passes_astern_of_the_fast_one`: `slow` starts at `Vector2i(4, 2)`, facing 1, 3 straight (it enters (4,5) at time 1). Assert neither result has a collision, `slow.final_hex == Vector2i(4, 5)` and `fast.final_hex == Vector2i(8, 5)`.
  - `test_equal_times_contest_the_hex`: `fast` plots 6 straight (its 4th step, into (4,5), is at 2/3, segment 3). Run with both ships deciding `collide` at segment 3. Assert:
    - both have a CONTESTED_HEX_ROLL with impulse 3;
    - `fast`'s first roll has `threshold == 1.0` (6.C.2b) and `slow`'s has `threshold == 0.0`;
    - exactly one of them has a MOVE at impulse 3 to (4,5).
  - `test_equal_plots_resolve_step_per_segment`: two ships 4 straight, far apart (bows (0,5) facing 0 and (12,12) facing 3). Assert each one's MOVE impulses are `[0, 1, 2, 3]` and `log.max_impulses == 4`.
  - `test_overlap_waits_for_the_next_segment_either_ship_moves`:
    - `S = _make_ship_state(Vector2i(5,5), 3, 3, "C", "s")` with plot `[{(5,5), facing 4}, {(5,4), 4}, {(5,3), 4}]`: a starboard turn swinging the stern into (5,6), then two steps ahead.
    - `F = _make_ship_state(Vector2i(4,6), 3, 3, "C", "f")` with 2 straight. Its stern (5,6) is vacated at 1/2.
    - `G = _make_ship_state(Vector2i(12,12), 3, 3, "C", "g")` with 8 straight.
    - Assert `s` has no OVERLAP_ROLLBACK, `s.final_facing == 4` and `s.final_hex == Vector2i(5, 3)`. The overlap is made on segment 2 (1/3), and segment 3 (3/8) is G's alone.
  - `test_bear_off_amendment_trails_after_the_last_segment`:
    - `_bear_off_setup()`, but `_plot_straight(mover, 2)`, plus `g = _make_ship_state(Vector2i(12,12), 3, 3, "C", "g")` with 4 straight. The segments are 1/4, 1/2, 3/4, 1, and the mover's blocked 2nd step is on segment 3.
    - Loop the seeds 1..40 with `_decide("starboard", 3)` until the BEARING_OFF_ROLL succeeds.
    - Assert the mover's MOVE impulses are `[1, 3, 4]`, `g`'s are `[0, 1, 2, 3]`, `mover.final_facing == 1` and `mover.final_hex == Vector2i(6, 6)`.
  - `test_bear_off_rerun_repeats_the_prefix_with_unequal_paces`:
    - The same three ships. `rng.seed = 7`, and run with prompt `["mover"]`. Assert `pending_bear_off.segment == 3`.
    - `rng.seed = 7`, and run with `_decide("collide", 3)`.
    - For each of the three ships, the `to_dict()`s of the events with impulse < 3 are equal in both logs.
  - `test_ma0_turn_happens_at_time_one`:
    - `t = _make_ship_state(Vector2i(5,5), 0, 0, "C", "t")` (head to wind, stopped, in irons), with `_plot_turn(t, 1)`.
    - A second ship at `Vector2i(12,12)`, facing 3, plots 4 straight.
    - Loop the seeds until `t`'s TACKING_ROLL succeeds. Assert that roll's impulse is 0 and `t`'s single MOVE has impulse 3.
- [ ] **Step 2: Run and confirm the new tests fail.** Run `make test`. Expected: the new tests fail, and so do some existing ones.
- [ ] **Step 3: Implement** the interfaces above. Delete `front_loaded` from `MoveSchedule` and from its test file.
- [ ] **Step 4: Fix the existing failures.** Run `make test`. For each failure, decide which kind it is:
  - (a) It encodes front-loaded timing: interacting ships with different step counts, or an MA-0 turn beside a longer plot. Re-derive the expected values from the new times. Add a `# proportional movement: <times>` comment and change nothing else.
  - (b) Anything else is a regression. Fix the code, not the test.
  - Equal-step-count tests must not change (Review Focus 1).
  - A whole-game test (`test_battle_to_victory`, `test_game_loop`, `test_stub_ai`) whose winner or turn count changes: update it, and state why in the commit body.
  - List every edited test in the commit body.
  - Likely sites (from `grep -n "impulse\|\"segment\"" test/unit`): `test_movement_resolver.gd` around the overlap, stern-contest, cascade, ring and bear-off sections (the `assert_eq(….impulse, n)` lines near 1985, 2256–2266, 2469, 2782 and 2988–3009), `test_bear_off_order.gd:174`, `test_bear_off_phase.gd:95,123` and `test_critical_steering.gd:420`. Check each against the new times; many will not change.
- [ ] **Step 5: Run the suite.** Run `make test`. Expected: all green.
- [ ] **Step 6: Commit.**

```bash
git add -A scripts/server test/unit
git commit -m "feat: proportional movement, step k of N at time k/N (replaces front-loaded 6.A.2 and 14.A)"
```

### Task 4: The movement log carries times

**Files:**
- Modify: `scripts/server/movement_types.gd`, `scripts/server/movement_resolver.gd`.
- Test: add to the "Proportional movement" section of `test/unit/test_movement_resolver.gd`, and extend `test/unit/test_movement_log.gd` for `to_dict`.

**Interfaces (Produces):**
- `ResolutionEvent.time: Vector2i = Vector2i.ZERO` (unstamped). `to_dict()` adds `"time"`: `"%d/%d"`, or `"end"` for `MoveSchedule.END`.
- `ResolutionLog`:
  - `segment_times: Array[Vector2i]`, one per index in `range(log.max_impulses)`: `_schedule.time_of(i)` for i below the final pass's `segment_count` (real and trailing segments), and `MoveSchedule.END` for every index at or above it (the end check, including a stale check index from an earlier pass);
  - `plot_steps: Dictionary` (ship_id → N);
  - `longest_plot: int`.
  - `to_dict()` adds `"segment_times"` (the strings as above), `"plot_steps"` and `"longest_plot"`.
- In `movement_resolver.gd`:
  - the pre-movement events (made in `_roll_pre_movement`, and the MA-0 PM roll) are created with `time = MoveSchedule.START`;
  - `func _stamp_times(log: MovementTypes.ResolutionLog) -> void`, called last in `run()`, fills `segment_times` for `range(log.max_impulses)` and sets every event whose `time == Vector2i.ZERO` to `log.segment_times[ev.impulse]`.

- [ ] **Step 1: Write the failing tests.**
  - `test_log_lists_every_segment_time`: the race setup of Task 3 (`collide` at 6). Assert:
    - `log.segment_times == [Vector2i(1,8), Vector2i(1,4), Vector2i(1,3), Vector2i(3,8), Vector2i(1,2), Vector2i(5,8), Vector2i(2,3), Vector2i(3,4), Vector2i(7,8), Vector2i(1,1)]`;
    - `log.plot_steps == {"fast": 8, "slow": 3}` and `log.longest_plot == 8`.
  - `test_every_event_carries_its_time`: in the same log, every event of both ships has `time == log.segment_times[ev.impulse]`, and `fast`'s MOVE to (4,5) has `time == Vector2i(1, 2)`.
  - `test_pre_movement_events_are_at_start`: in the Task 3 MA-0 setup, `t`'s TACKING_ROLL has `time == MoveSchedule.START`.
  - `test_rollback_on_the_end_check_is_at_end`:
    - `t = _make_ship_state(Vector2i(5,5), 3, 0, "C", "t")` with the plot `[{(5,5), facing 4}]`: one starboard turn, its stern into (5,6).
    - `f = _make_ship_state(Vector2i(4,6), 3, 0, "C", "f")` with `set_plotted_movement("f", [])`.
    - Assert:
      - `t` has an OVERLAP at impulse 0 and an OVERLAP_ROLLBACK at impulse 1, with time `MoveSchedule.END`;
      - `log.segment_times == [Vector2i(1,1), MoveSchedule.END]`;
      - `log.max_impulses == 2`.
  - In `test_movement_log.gd`, `test_log_to_dict_writes_times`: a hand-built log with `segment_times = [Vector2i(1,2), Vector2i(1,1)]`, `longest_plot = 2`, `plot_steps = {"a": 2}` and one MOVE event with `time = Vector2i(1,2)`. Its `to_dict()` has `"segment_times" == ["1/2", "1/1"]`, `"longest_plot" == 2`, and the event dict has `"time" == "1/2"`.
- [ ] **Step 2: Run and confirm they fail.** Run `make test`. Expected: only the new tests fail.
- [ ] **Step 3: Implement** the interfaces above.
- [ ] **Step 4: Run the suite.** Run `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/movement_types.gd scripts/server/movement_resolver.gd test/unit/test_movement_resolver.gd test/unit/test_movement_log.gd
git commit -m "feat: movement log carries segment and event times"
```

### Task 5: Playback at each ship's own pace

**Files:**
- Modify: `scripts/view/movement_resolution_playback_controller.gd`.
- Modify: `scripts/ui/developer_ui.gd:302`. The slider label "Glide s / segment" becomes "Glide s / MP of the fastest ship".
- Modify: `scripts/view/sea_model.gd:66`, the comment only: seconds per clock unit (one MP of the longest plot).
- Test: `test/unit/test_playback_controller.gd`. Rewrite the tests of the removed helpers, and set `segment_times`, `plot_steps` and `longest_plot` on its hand-built logs (helper: give each log `segment_times` of `Vector2i(i + 1, n)` for n = `max_impulses`, with `longest_plot = n`).

**Interfaces:**
- Consumes `ResolutionLog.segment_times`, `plot_steps`, `longest_plot` and `resume_impulse` (Task 4).
- Produces, all static on `MovementResolutionPlaybackController`:
  - `segment_clocks(segment_times: Array, longest_plot: int) -> Array[float]`:
    - times ≤ 1 give `float(t.x) / t.y * longest_plot`;
    - trailing `(k, 1)` with k ≥ 2 gives `longest_plot + (k - 1)`;
    - `END` gives the previous entry + 1 (0 + 1 if first).
  - `GlideTrack` gains `spans: Array` (one `[start_clock, end_clock]` per glide; `keys.size() == spans.size() + 1`). `t0` and `t1` are removed.
  - `track_for(events: Array, hex_grid: HexGrid, start_angle: float, clocks: Array, longest_plot: int, plot_steps: int, start_clock: float = 0.0) -> GlideTrack`. Glide i ends at `clocks[events[i].impulse]` and starts at `max(previous end (or start_clock for the first), end - unit, start_clock)`. `unit` is `float(longest_plot) / plot_steps` for a segment whose time is ≤ 1, and 1.0 otherwise.
  - `pose_at(track: GlideTrack, t: float) -> Array`:
    - before the first span: `keys[0]`; after the last: the last key;
    - inside span i: linear between `keys[i]` and `keys[i + 1]` (smoothstep on the first and last span);
    - between spans: `keys[i + 1]` of the last finished span.
  - `end_clock(log: MovementTypes.ResolutionLog) -> float`: the largest clock of a posed event (0.0 if none).
  - `glide_stretches` and `moving_clock` are removed.
- Playback behaviour (spec §6):
  - Play the pre-movement events first (only when `resume_impulse == 0`).
  - Then run one tween clock from the resume clock (`clocks[resume_impulse - 1]`, or 0.0) to the stop clock: `end_clock(log)` for a complete log, or `clocks[pending_bear_off.segment - 1]` (0.0 if that segment is 0) for a paused one.
  - The clock halts at the clock of every segment with special events (selection as today, `_special_events`) for `_play_event_batch`, then goes on.
  - Duration is clock span × `glide_seconds()`.
  - A paused log's tracks hold only events before `pending_bear_off.segment`.

- [ ] **Step 1: Write the failing tests** in `test_playback_controller.gd`:
  - `test_segment_clocks_scale_times_by_the_longest_plot`:
    - `segment_clocks([Vector2i(1,4), Vector2i(1,2), Vector2i(3,4), Vector2i(1,1)], 4) == [1.0, 2.0, 3.0, 4.0]`;
    - `segment_clocks([Vector2i(1,2), Vector2i(1,1), Vector2i(2,1)], 2) == [1.0, 2.0, 3.0]`;
    - `segment_clocks([Vector2i(1,1), MoveSchedule.END], 3) == [3.0, 4.0]`.
  - `test_slow_ship_glides_at_its_own_pace`: clocks `[1.0, 2.0, 3.0, 4.0]`, `longest_plot` 4. A 2-MP ship's MOVEs on segments 1 and 3 give `spans == [[0.0, 2.0], [2.0, 4.0]]`. A 4-MP ship's on 0–3 give `[[0.0, 1.0], [1.0, 2.0], [2.0, 3.0], [3.0, 4.0]]`.
  - `test_resumed_glide_starts_at_the_resume_clock`: the 2-MP ship with only its segment-3 MOVE and `start_clock = 3.0` gives `spans == [[3.0, 4.0]]`, and `pose_at(track, 3.0) == track.keys[0]`.
  - `test_pose_mid_glide_is_interpolated`: for a 3-step track, `pose_at` at the middle of the second span is the midpoint of `keys[1]` and `keys[2]` (position within 0.001). `pose_at` at each span end equals the key.
  - `test_playback_total_clock_is_the_longest_plot`: a complete log with `plot_steps {"a": 2, "b": 4}` and `segment_times [1/4, 1/2, 3/4, 1]`, where a moves on 1 and 3 and b on 0–3, has `end_clock(log) == 4.0`.
  - Rewrite `test_playback_rolled_back_turn_ends_in_the_old_pose`, `test_mid_swing_the_stern_orbits_a_fixed_bow` and `test_ahead_step_slides_along_the_keel` to call the new `track_for` / `pose_at`. Their assertions on poses stay the same.
- [ ] **Step 2: Run and confirm failure.** Run `make test`. Expected: the new and rewritten tests fail.
- [ ] **Step 3: Implement** the interfaces and the playback behaviour above.
- [ ] **Step 4: Run the suite.** Run `make test`. Expected: all green, including `test_incomplete_log_plays_up_to_the_decision_and_pauses` and `test_resumed_log_plays_from_its_resume_impulse`.
- [ ] **Step 5: Check it in the running game.**
  - Launch with the godot-mcp `run_project`, start `test_fleet.json` and End Planning.
  - Confirm `game_get_errors` returns zero.
  - Take a `game_screenshot` mid-movement and confirm that ships with fewer MPs are visibly part-way through their glides while the faster ones move on, and that all ships stop together.
- [ ] **Step 6: Commit.**

```bash
git add scripts/view/movement_resolution_playback_controller.gd scripts/ui/developer_ui.gd scripts/view/sea_model.gd test/unit/test_playback_controller.gd
git commit -m "feat: movement playback at each ship's own pace"
```

### Task 6: Rules record, CLAUDE.md and the SCV audit

**Files:**
- Modify: `docs/rules/feature_diff.md`, `CLAUDE.md`.

- [ ] **Step 1: Update `docs/rules/feature_diff.md`.**
  - **§4:** add the bullet "**Proportional movement replaces front-loaded movement** (6.A.2, 14.A; user decision 2026-11-17, register `2026-11-17-subprojects-3-7-decisions.md` §1)". It gives:
    - step k of an N-step plot at time k/N, turns counted;
    - segments = distinct exact times;
    - exact ties keep 6.C/6.D;
    - the 6.B window as the next segment on which the turning ship or a ship it overlaps moves;
    - an MA-0 turn at time 1 with its roll before movement;
    - amended steps on the ship's next times, then trailing segments 2, 3, …;
    - gunfire after movement;
    - code `move_schedule.gd`, `movement_resolver.gd`.
  - **§2.2, the "Optional rules (14)" row:** drop "impulse movement with fire at the end of an impulse". Add "14.A (and 14.A.7) is closed: replaced by proportional movement (§4), fire during movement not offered".
  - **§5:** "Simultaneous segment-by-segment movement (6.A.1–2)" becomes "Simultaneous movement (6.A.1), at proportional pace instead of 6.A.2's front-loaded segments (§4)". The 6.D.3c line gets "(same segment = the same exact time)".
  - **Header:** add to "Compared against" a sentence naming `worktree-proportional-movement` and the Task 5 commit hash (`git log -1 --format=%h` before this commit).
- [ ] **Step 2: Update `CLAUDE.md`.**
  - In the MOVEMENT_RESOLUTION bullet, after "then the movement resolver runs", add: "at proportional pace: step k of an N-step plot at time k/N (`MoveSchedule`); the segments are the distinct times".
  - In the Hex Grid "Turns pivot on the bow" bullet: "at the end of the next segment" becomes "at the end of the next segment on which either ship moves".
  - In the "Sea look" bullet: "(`glide_seconds` per moving segment, from the preset)" becomes "(each ship at its own pace, one clock for the turn: `glide_seconds` per MP of the longest plot)".
  - Add after the Movement Plotting Protocol list a paragraph, **Proportional movement (`scripts/server/move_schedule.gd`, pure)**:
    - times are reduced `Vector2i`, compared by cross-multiplication;
    - the schedule comes from the post-PM plots, once per `run()`;
    - amended steps take the ship's next times, then trailing segments at times 2, 3, …;
    - MA-0 turns at time 1, their Tacking roll before the first segment;
    - the log has `segment_times`, `plot_steps`, `longest_plot` and `ResolutionEvent.time` (`START`, `END`);
    - `impulse` is the segment index.
- [ ] **Step 3: Run the suite and the audit.**
  - Run `make test`. Expected: all green.
  - Run the `scv-reviewer` agent on the branch (CLAUDE.md "SCV Audit"). Fix any violation it reports and re-run `make test`.
- [ ] **Step 4: Commit.**

```bash
git add docs/rules/feature_diff.md CLAUDE.md
git commit -m "docs: proportional movement in feature_diff (14.A closed) and CLAUDE.md"
```
