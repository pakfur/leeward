# Proportional movement: design

Date: 2026-11-17. The first item of the sub-projects 3–7 run (`2026-11-17-subprojects-3-7-decisions.md` §1,
"Proportional movement (replaces 14.A)"). Status: draft written for the unattended run. **U** marks the
user's binding answers from the register; **B** marks builder's calls, the register's or new ones made
here. A new or refined call is tagged **B (new)** or **B (refined)** and has its reason next to it.

## Intent

Today's movement is front-loaded (6.A.2). Every ship spends its first MP on segment 1, its second on
segment 2, and so on. A 3-MP ship therefore reaches its third hex on segment 3, while an 8-MP ship has
only gone three hexes by then. Slow ships win races for hexes that the fast ship "really" reached first.
That is the problem 14.A.1 describes, and the 14.A impulse table only reduces it.

The user wants the outcome directly: **faster ships beat slower ships**. All plotted movement is resolved
at once, and each ship moves at a pace proportional to its speed. When two ships plot into the same hex,
the one that gets there first enters it. The slower one meets the usual collision and bear-off rules.

## Goals

1. Each ship's step k (1-based) of an N-step plot happens at time k/N of the turn. Turns count as steps,
   as they do for speed (U).
2. The resolver's segments are the distinct times over all ships, in increasing order. Times are compared
   exactly, never as floats (B).
3. Every rule in 6.A–6.F works unchanged within a segment. The rules that look across segments (6.B
   overlap clearing, 6.C.1b, 6.D.3b–c, cycle breaks, rollbacks, deceleration amendments) get a defined
   meaning under the schedule.
4. Replays (overlap rollbacks, broken cycles, bear-off re-runs) stay deterministic, dice included.
5. The movement log carries each event's time. The view plays each ship at its own pace, every ship's
   move ends together, and the total playback time per turn stays the same (B).
6. A fleet in which every ship plots the same number of MPs resolves exactly as it does today, indices
   included.

## Non-goals

- Fire during movement (14.A.7). **Gunfire stays after movement** (U).
- An option to play front-loaded. Proportional movement **replaces front-loaded movement in every
  game** (U).
- Any new input control (register §0, U: view-only scope). Bear-off prompts keep their current server
  request.
- Changes to plotting, the validator, `DefaultCourse` or the stub AI's plotting. The schedule is derived
  from the plot. The AI's bear-off choice (`StubAI.bear_off_choice`) is unchanged.

## Approaches

- A. **14.A as written.** Four impulses, with MPs per impulse from the Impulse Movement table. Ships still
  tie within an impulse, so it only reduces the slow-ship advantage, and it adds a table. Rejected by the
  user.
- **B. Exact proportional times, k/N (chosen, U).** Each step has its own time. Ties happen only when the
  times are genuinely equal: equal speeds, or ratios such as 2/4 = 1/2.
- C. Float times. Rejected (B): floats would make equal times, such as 2/6 and 1/3, unequal under
  rounding, and a replay could order two steps differently.

## Design

### 1. The schedule

`MoveSchedule` is a new pure class in `scripts/server/move_schedule.gd`. It holds no game state.

- **Time.** A time is a `Vector2i(num, den)`, kept reduced (gcd 1, den > 0). Times are compared by
  cross-multiplication, `a.x * b.y` against `b.x * a.y`. Plots are at most about 12 steps, so the products
  are tiny. Two constants mark times outside the turn's steps:
  - `START = Vector2i(0, 1)` is for pre-movement events.
  - `END = Vector2i(1, 0)` is the check after the last segment. `compare` treats a denominator of 0 as
    greater than every other time.
- **Step times.** Step j (0-based) of an N-step plot is at `reduce(j + 1, N)`.
- **Whose plot.** The schedule is built once per `run()`. It uses each ship's plot as resolution begins,
  after poor maneuvering has rewritten it (6.F.3 keeps the step count, so N is unchanged) (B). Amended
  plots never change the schedule. That is what keeps replays deterministic (§4).
- **Segments.** The segment list is every distinct step time ≤ 1 over all ships, ascending. Segment
  indices (the existing `impulse` integers) index this list. A ship with an empty plot (held, fouled,
  grappled, out of play, a course that breaks a jammed rudder) contributes no times.
- **Trailing steps** (B, refined). An amended plot may be longer than N, when the deceleration minimum at
  a new heading exceeds the steps plotted (the plot's N need not meet the minimum at another facing, a
  default course is not checked, and a test can store any plot). The register's rule is that such steps
  "trail after the last segment in order".
  - Here the m-th extra step (step N − 1 + m) is at the integer time 1 + m: 2, 3, 4, …
  - Each trailing time is one segment, shared by every ship's m-th extra step. So trailing segment index
    `times.size() + (m − 1)` means the same thing in every pass.
  - Why not k/N beyond 1: times such as 4/3 and 9/8 from different passes would interleave, and the
    segment indices of a re-run would shift.

`MoveSchedule` answers these queries. Their exact signatures are in the plan, Task 1.
- `segment_of(ship, step)`: the segment of a step.
- `step_at(ship, segment)`: the ship's step on a segment, or −1.
- `steps_before(ship, segment)`: how many steps the ship has scheduled before a segment.
- `segment_count(steps_by_ship)`: the segments of a pass, trailing segments included.
- `time_of(segment)`.
- `next_segment(ids, after, steps_by_ship)`: §2, 6.B.

**Property (goal 6).** When every ship has the same N, the segments are 1/N … N/N and `segment_of(ship, j)
== j`. Every index, key and event is then exactly what it is today.

### 2. What each rule means under the schedule

The pass loop is unchanged in shape. Each segment index from 0 to `segment_count` (inclusive: the last
index is the end check, as today's extra segment is) runs `_resolve_impulse`, `_check_overlaps` and
`_note_overlaps`.

- **Who moves on a segment.** Only ships whose schedule has a step on that segment move. A ship between
  its steps is **idle**. It is not stopped. Its two hexes are held all segment, as for any ship that is
  not moving (`Occupancy.from_positions` already does this for every ship not in `intended_moves`). A
  ship is finished when its last step is done (`p.stopped`, as today).
  - Invariant: a ship that is not stopped has made every step scheduled before the current segment. So
    "its step on this segment" is `step_at(sid, segment)` and is always the next unmade step.
- **Step index versus segment index.** Every place that uses the segment number as a step number now
  asks the schedule:
  - `_resolve_impulse` reads `steps[step_at(...)]`.
  - `_all_on_last_step` asks whether that step is the ship's last (6.C.1b).
  - `_amended_steps` keeps `steps.slice(0, rollback.step)`. Every rollback, lost contest and bear-off
    record now carries a `step`.
  - The stern-contest deceleration test compares the minimum with `step`.
  - `bear_off_situation` builds its path from the steps made, `slice(0, step)`, and lists other ships'
    steps from this segment on (6.D.3a).
  - `_reached_segment(result, segment)` compares the MOVEs before the segment with
    `steps_before(ship, segment)`.
  - `_record_steering` maps a poor-maneuvering roll's step index to its segment.
- **6.A.5, simultaneity within a segment.** Unchanged. All of a segment's moves are made before any
  conflict is checked. Cycles (head-on bows, rings of sterns) can only form among ships that move on the
  same segment, which now means a tie.
- **6.B.2–4, overlap window** (B; the register's call, refined).
  - An overlap made on segment s is checked at the end of the next segment, after s, on which the turning
    ship or any ship it overlaps has a scheduled step in this pass's plots: `next_segment([sid] + other_ids,
    s, steps_by_ship)`. If none of them has another step, it is checked at the end check (index
    `segment_count`).
  - Refinement 1: "either of the two ships" becomes "the turning ship or any ship it overlaps", since a
    swing can overlap two ships at once.
  - Refinement 2: a scheduled step counts even when that ship was stopped in the meantime. A stopped
    ship cannot clear the overlap, so the check simply fails then. The check segment depends only on the
    plots, never on how the pass went, so rollback grouping ("all overlaps failing at the same segment end
    are rolled back together") stays deterministic.
  - The record stores this `check_segment`. `OVERLAP_ROLLBACK` is logged on it, where today it is logged
    on segment + 1.
  - `stop_cause` / `_undone_turn_ended_movement` find the turn's segment from the ship's `OVERLAP` event,
    not from "the rollback's segment − 1".
- **6.C.1b and 6.C.5, stern versus stern.** "No further MPs plotted" means the step on this segment is the
  ship's last. Under k/N every unamended last step is at time 1, so two last-step sterns can only meet at
  time 1. That is the end of the turn, which is where the rule's picture of two ships finishing together
  belongs.
- **6.C.2–6, bow versus bow.** A contested hex needs two bows entering on one segment, which is now an
  exact tie. The DRMs are unchanged, including +1 for the faster plotted speed (6.C.2b). The winner always
  enters (feature_diff §4).
- **6.D, bearing off.** A potential collision happens on the segment of the loser's blocked step. 6.D.3b
  holds by construction: segments are time-ordered, so an earlier situation is decided first.
  - 6.D.3c's d10 order is rolled only when two or more situations fall on one segment. That is rarer now,
    and the rule is unchanged.
  - A bear-off pause stops the pass at the end of its segment, as today. The re-run with the answer
    repeats everything before that segment (§4).
  - The amendment turns on the blocked step's segment, then moves ahead to the deceleration minimum on
    the ship's next unused times. Beyond N those are trailing times.
- **Rollbacks and cycle breaks.** Unchanged in logic. The keys (`_segment_hex_key(segment, hex)`) stay
  segment indices, which are stable across passes (§4). "Drop the cycle breaks from the rolled-back
  segment on" still compares indices.
- **Deceleration amendments** (6.B.4a/c, 6.B.5, 6.D.4). Kept steps are `slice(0, step)`. The added steps
  ahead take the ship's next scheduled times, then trailing times (register B).
- **The MA-0 turn** (5.D.1, 6.F.5) (B, refined).
  - A turn at MA 0 is a one-step plot, so N = 1 and the turn happens at time 1/1, together with every
    other ship's last step (register B).
  - "Keeps its pre-movement roll": the Tacking roll, the redraw of a tack an amended plot dropped, the
    6.F.5 poor-maneuvering roll at MA 0 and their IMMOBILIZED events are all drawn at the start of each
    pass, in ship order, before the first segment. Their events are on segment 0 with time `START`.
  - This is the order today's code already draws them in: at segment 0, inside the ship loop, before any
    group runs. So the dice stay identical. Only the turn itself moves to time 1.
  - Why: the roll decides whether the ship moves at all. Rolling it before movement matches the board
    game's ship log, and keeps it out of the segment order.
- **6.F, poor maneuvering.** It is rolled once before the passes, as today, and rewrites the plot without
  changing its length, so it is the plot the schedule is built from. Each roll is logged on its step's
  segment if the ship reaches it.
  - Example: a ship plotted S2 (a turn, then two ahead) fails its roll. Its plot becomes 1S1, at 1/3
    ahead, 2/3 the turn, 1 ahead.
- **6.E, collisions.** Unchanged. 6.E.2 stops both ships for the rest of the phase. Under the schedule
  the ship run into is often idle mid-plot. It too stops and loses its remaining steps, as the rule says.
- **Speed and `moved_this_turn`** (5.E.2, 5.E.3b, 8.F.3b). Unchanged. They count executed MOVE events.

### 3. Worked examples

Hexes are axial (q, r); direction 0 is E, 1 SE, 3 W, 4 NW. The resolver does not check MA except for an
MA-0 turn and the deceleration minimum, so the examples (and their tests) store plots directly. Ship A plots 8 MPs straight east from bow
(0,5). Ship B plots 3 MPs straight south-east from bow (4,3), entering (4,4), (4,5), (4,6). The hex they
race for is X = (4,5).

| Segment | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| Time | 1/8 | 1/4 | 1/3 | 3/8 | 1/2 | 5/8 | 2/3 | 3/4 | 7/8 | 1 |
| A (8 MPs) moves | step 1 | 2 | — | 3 | **4: enters X** | 5 | — | 6 | 7 | 8 |
| B (3 MPs) moves | — | — | step 1 | — | — | — | **2: X is A's stern** | — | — | (3) |

- **Proportional.** A's bow enters X at 1/2. At 5/8 A moves on, and X becomes A's stern. At 2/3 B's bow
  tries to enter X, which A holds. That is a potential collision for B (6.D). B bears off or rams A, and
  A, which got there first, sails on. If B had reached X at 3/4 or later, it would have passed astern of
  A.
- **Front-loaded (today).** B enters X on segment 2, its second MP. A reaches X on segment 4 and runs into
  B. The slow ship wins the race.

**Exact tie.** If A plots 6 MPs instead, its 4th step is at 4/6 = 2/3, the same time as B's 2nd. Both
bows try to enter X on one segment. That is a 6.C contested hex: each rolls a d6, and A takes +1 for the
faster plotted speed (6.C.2b). The loser must bear off or collide (6.C.4) (U: exact ties keep today's
simultaneous rules).

**Overlap window.**
- Ship S plots 3 MPs from bow (5,5) heading west: a turn to starboard (to NW) at 1/3, then two steps ahead
  at 2/3 and 1. Its stern swings into (5,6).
- (5,6) is the stern of ship F, bow (4,6), also heading west. F plots 2 MPs ahead, at 1/2 and 1.
- A third ship, G, plots 8 MPs elsewhere, so the segments are 1/8, 1/4, 1/3, 3/8, 1/2, … and S's overlap
  is made on segment 2 (1/3).
- Segment 3 (3/8) is G's alone. The overlap is checked at segment 4 (1/2), the next segment on which S or
  F moves. F's step clears it, and S keeps its turn.
- A rule of "the next segment index" would have judged it at 3/8, when neither ship had moved, and rolled
  S's turn back.

**Trailing steps.**
- A mover (speed 7, deceleration 4, so its minimum is 3 MPs at a heading with enough MA) plots only 2 MPs
  east, and a stopped ship holds the hex its 2nd step enters. Another ship plots 4 MPs, so the segments
  are 1/4, 1/2, 3/4, 1.
- The mover's 1st step is on segment 1 (1/2). Its 2nd step, on segment 3 (time 1), is blocked.
- It bears off to starboard. Its amended plot is 1 ahead, the turn (segment 3), then 1 more ahead to meet
  its minimum of 3. That 3rd step has no scheduled time left, so it trails at time 2, segment 4, after
  every other ship's last step.

**MA-0 turn.** A ship in irons plots one turn. Its Tacking roll is drawn before the first segment, as
today. If the roll passes, its stern swings at time 1, on the last segment, alongside every other ship's
last step.

### 4. Determinism of replays

- The schedule (times and `plot_steps`) is fixed for the whole `run()`. It comes from the post-PM plots,
  and the PM rolls are drawn before the passes from `rng_start`, so a bear-off re-run from the same RNG
  state rebuilds the same schedule.
- Segment indices ≤ 1 are therefore the same in every pass and every re-run. Trailing segment m is always
  index `times.size() + m − 1`. Only the end check's index (`segment_count`) can vary, and it is never a
  key.
- So `cycle_breaks`, `settled_contests`, `bear_off_decisions[sid].segment`, `pending_bear_off.segment`
  and `resume_impulse` keep their meaning across passes and re-runs. `TurnPhaseController` is unchanged.
- Every die still comes from the resolver's `rng`, reset to `rng_start` per pass:
  1. the PM rolls (once, before the passes);
  2. then per pass: the pre-movement tacking rolls in ship order;
  3. then segment by segment: contests, bear-off order, bear-off rolls, collision rigging and fouling.
  The re-run log therefore repeats every event before the decision's segment exactly. A test pins this
  with unequal paces (plan, Task 3).

### 5. Movement log

- `ResolutionEvent.impulse` keeps its name and meaning: the segment index in this log (B, new: renaming it
  would touch every resolver test for no gain).
- New `ResolutionEvent.time: Vector2i`. It is `START` for pre-movement events. Every other event is
  stamped at the end of `run()` with `log.segment_times[ev.impulse]`. `to_dict()` writes `"time": "n/d"`
  (`"end"` for `END`).
- New `ResolutionLog.segment_times: Array[Vector2i]`, one entry per segment index. Trailing segments are
  `(2, 1)`, `(3, 1)`, …, and the end check, when an event lies on it, is `END`. `max_impulses` stays the
  segment count (its size).
- New `ResolutionLog.plot_steps: Dictionary`, ship id → N, the schedule's plot sizes, and
  `ResolutionLog.longest_plot: int`, the largest N. The view paces each ship with them.
- `to_dict()` adds `"segment_times"` (strings), `"plot_steps"` and `"longest_plot"`.
- `PhaseEvents` (the turn log the combat log shows) is unchanged. `log_outcomes` reads results, not
  times.
- `PlayerView.BOX_FIELDS` is unchanged, since the movement log counts no boxes.

### 6. View playback at per-ship pace (B)

`MovementResolutionPlaybackController` replaces its per-stretch segment clock with one clock for the
turn.

- **Clock.** A segment's clock value is `t × longest_plot` for times ≤ 1, `longest_plot + (k − 1)` for
  trailing time k, and the previous segment's value + 1 for `END`. Seconds are clock × `glide_seconds()`.
  - A turn in which every ship completes its plot ends at clock `longest_plot`. That is today's total:
    `glide_seconds` per segment, over as many segments as the longest plot.
  - The extra unit for `END` is for the swing back of an overlap made on the last segment (B, new: without
    it the swing back would be instant).
- **Tracks.** Each ship has one track for the whole log. A key goes at every posed event (MOVE, plus a
  rolled-back turn's OVERLAP and OVERLAP_ROLLBACK, chosen as today).
  - The glide to a key starts at `max(previous key's clock, key clock − unit, resume clock)` and ends at
    the key's clock.
  - `unit` is `longest_plot / N` for the ship, and 1 for a trailing step.
  - So a 3-MP ship next to an 8-MP ship takes 8/3 clock units per step. Both arrive together at clock 8.
  - Within a glide the motion is linear. The track eases in on its first glide and out on its last, so the
    ships keep today's gentle start and stop.
- **Event pauses.** When the clock reaches a segment that carries special events (the same selection as
  today: collisions, contests, bear-off rolls, rollbacks, …), it stops for the pause. Every ship holds its
  pose, mid-glide if it is between steps.
- **Bear-off pause and resume.**
  - A paused log is played to the clock of the segment before `pending_bear_off.segment`, from tracks that
    hold only the events before that segment.
  - The re-run log is played from that clock (`resume_impulse` − 1's clock, or 0). Its glides start no
    earlier than the resume clock.
  - So a ship that was resting on its last pose at the pause starts from that pose, and nothing jumps.
- **Removed.** `glide_stretches` and `moving_clock` are removed. `track_for` and `pose_at` take clock
  values (signatures in the plan, Task 5).

### 7. Tests

| What | Why it changes |
|---|---|
| Single-ship and equal-N tests | Do not change (goal 6, §1 property). They are the regression evidence. |
| Multi-ship tests whose ships plot different step counts (crossings, head-on, rings, cascades, overlaps, contests, bear-off order and pauses) | Some expected segments, winners or collisions change, because the ships now meet at different times. Each change is made in the task that changes the timing, with a one-line `# proportional movement:` comment giving the new times. Tests that only assert a final outcome change only if that outcome changes. |
| MA-0 turn tests next to ships with more MPs | The turn's MOVE moves from segment 0 to the segment of time 1. |
| Integration tests that play whole turns (`test_game_loop`, `test_battle_to_victory`, `test_stub_ai`) | May see different positions. Updated only where they assert exact hexes or segments. A changed winner must be explained in the commit. |
| `test_playback_controller.gd` | The stretch and clock helpers it tests are replaced (§6). |
| New `test_move_schedule.gd` | Time arithmetic, segment indexing, trailing segments, the equal-N property. |
| New "Proportional movement" section in `test_movement_resolver.gd` (it reuses that file's ship and plot helpers) | The §3 examples, the overlap window, the MA-0 turn at 1/1, trailing amendment steps, the bear-off re-run prefix with unequal paces and the log's times. |

### 8. Documentation

- **`docs/rules/feature_diff.md`.**
  - §4 gets a new bullet, "Proportional movement replaces front-loaded movement (6.A.2, 14.A; user
    decision 2026-11-17)", summarising §1–2 and naming the register.
  - The §2.2 "Optional rules (14)" row drops impulse movement. 14.A (and 14.A.7, fire at the end of an
    impulse) is closed as replaced / not offered.
  - The §5 line "Simultaneous segment-by-segment movement (6.A.1–2)" becomes simultaneous movement at
    proportional pace.
  - The 6.D.3c line notes that same-segment situations are now exact-time ties.
  - The header's "Compared against" sentence names the branch and commit.
- **`CLAUDE.md`.**
  - The MOVEMENT_RESOLUTION bullet says segments are proportional times.
  - The Hex Grid "Turns pivot on the bow" bullet: "the end of the next segment" becomes "the next segment
    on which either ship moves", and the MA-0 turn is at time 1.
  - The "Sea look" bullet: each ship glides at its own pace and the total is `longest_plot` ×
    `glide_seconds`.
  - A short "Proportional movement" paragraph is added beside the Movement Plotting Protocol, naming
    `MoveSchedule`, the k/N rule, trailing segments and the log's `segment_times` / `time`.
- **The decisions register** is unchanged. The refinements above are marked here and fit within its
  entries.

## Left for later

- Showing the times in the bear-off prompt (6.D.3a lists the other ships' remaining hexes; their times
  would help a player). That belongs with the UX pass (register §0).
- Grounding (sub-project 3) and towing (5) add per-step rules to `_resolve_impulse`. They build on this
  schedule, which is why this comes first (register §0).
