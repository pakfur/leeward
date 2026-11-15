# Bearing off as a player decision (pause and prompt): design

**Status:** draft for review. **Feature diff:** §1 item 7, §3 row 6.D. **Rules:** 6.D.1–6.D.5, 6.E.1, 5.C (turning limits), 5.E (deceleration).

## 1. What the rules ask for

- **6.D.1** A potential collision happens when a ship tries to move ahead into a hex another ship holds, either at the start of the segment or after losing a contested-hex roll (6.C).
- **6.D.2** The ship may bear off only if a turn is legal at that point under the turning charts: it has not turned twice this g-t, did not just turn, and meets the same- and opposite-direction spacing. If so it rolls d10 on the Bearing Off chart: roll ≤ n succeeds (DRMs +1 for 4–6 MPs plotted, +2 for 7+, +3 rudder, +1 poor maneuvering).
- **6.D.3** The owning player decides whether to try (a ship may choose to collide, 6.E.1), and may first see every other ship's plot. Situations are decided in segment order. Two in the same segment: a d10 decides which goes first.
- **6.D.4** On success the ship turns in whichever eligible direction its player wants, then stops. If that would break its deceleration limit, it moves ahead just far enough to meet the minimum.
- **6.D.5** Once per g-t. A second potential collision that turn is automatic.

**Leeward today** (`movement_resolver.gd`, `_resolve_collision_or_bearoff`): always attempts when eligible. On success it stops without turning and ignores the deceleration minimum. It never asks anyone. 6.D.3b–c ordering and the once-per-turn limit are missing (§2.2).

## 2. Approach: decisions as replay input

The resolver already re-runs a whole resolution from the same RNG state when a plot must change (overlap rollbacks, stern contests, broken cycles). Bear-off decisions fit the same mechanism:

1. `MovementResolver.run(ships, env, bear_off_decisions := {})`. `bear_off_decisions` maps `ship_id` to `{choice: "port" | "starboard" | "collide", segment}`.
2. When `_resolve_collision_or_bearoff` reaches an eligible ship with no decision recorded, it asks a decider:
   - **AI ship** (`player_id` ≠ the human's): `StubAI.bear_off_choice(situation)` decides on the spot, deterministically and without dice.
   - **Human ship**: the pass stops and the outcome carries `decision_needed = BearOffSituation`. `run()` returns a log flagged `pending_decision`; its results are valid up to the start of that segment.
3. The controller collects the answer, adds it to `bear_off_decisions` and calls `run()` again. Everything before the decision segment replays identically, with the same dice. A second human situation later in the turn repeats the cycle.
4. With every decision in hand, the pass runs to the end, and the log is applied as now.

`BearOffSituation` (in `movement_types.gd`): `ship_id`, `blocker_id`, `segment`, `hex`, `eligible: Array[String]` (subset of port/starboard, from the turning charts), `chance` (chart number, DRM, success odds as shown to the player), and, if the user wants 6.D.3a, `others_plots` (each other ship's plotted steps).

### Success (6.D.4)

The player picks the direction before the roll. That is equivalent to picking after, because the roll does not change which direction is better, and it saves a second prompt. On success the ship's plot is **amended**: its steps up to the blocked segment, the turn, then ahead steps up to its deceleration minimum (the same helper rollbacks use, `_amended_steps`). The pass replays with the amended plot. Ahead steps after bearing off that meet another ship collide with no further bear-off attempt (6.D.5: `bore_off_this_turn` on the pass).

### Ordering (6.D.3b–c)

Earlier segments are decided first, which falls out of the pass order. Several situations in one segment: roll a d10 per situation with the resolver RNG, inside the pass, so that replays reproduce it. Situations are then resolved in that order, each one's decision before the next is offered.

### Choosing to collide

`choice: "collide"` skips the roll and calls `_apply_collision`. This also lets a player ram on purpose.

## 3. Turn-phase flow

`TurnPhaseController` (MOVEMENT_RESOLUTION):

```
_enter_movement_resolution_phase
  log = resolver.run(ships, env, _bear_off_decisions)
  if log.pending_decision: resolution_log_ready.emit(log)   # view plays up to log.pause_segment
  else: resolution_log_ready.emit(log)                      # as today

on_playback_paused()            # view: playback reached the decision segment
  bear_off_decision_requested.emit(log.pending_decision)

player_submit_bear_off(player_id, ship_id, choice) -> String   # "" or a rejection reason
  validate (owner, eligible choice) -> store -> re-run -> resolution_log_ready.emit(log, resume_segment)

on_playback_completed()         # unchanged: apply results, advance
```

Server-authoritative: the decision is validated on the server (owner, choice among `eligible` + "collide"). `_bear_off_decisions` is cleared at END_TURN.

## 4. UX (needs your call)

1. **When the prompt appears.**
   - **(A, recommended)** Playback runs up to the moment of the potential collision, pauses, and a small modal panel appears. After the answer, playback resumes from that segment with the re-run log. The prefix is identical, so nothing jumps.
   - (B) The prompt comes before any playback, over a static preview of where the ships stand at that segment. Simpler, but the player loses context.
2. **The panel.** Title "Collision ahead: <ship> will strike <other>". Buttons: "Bear off to port (60%)", "Bear off to starboard (60%)" (only the eligible ones; same odds, shown with the DRMs as the tacking chance is), and "Hold course and collide". If no turn is legal, there is no prompt (automatic collision, as now), but the log says why.
3. **6.D.3a: show other ships' plots?** The rules let the player see every plot before deciding. Showing them draws each enemy's plotted path on the map while the panel is open. Recommend yes. It is what the rules allow, and the AI decides with the same information.
4. **Timeouts / hot-seat.** None: the game waits, as at End Turn.

## 5. AI (`StubAI.bear_off_choice`)

Always tries when eligible. It picks the eligible direction whose new bow is farther from the blocker, preferring a heading that keeps its target in a broadside arc on a tie. It never chooses to collide, for now. This is deterministic, uses no dice, and is unit-testable.

## 6. Implementation steps (each with GUT tests, dice pinned with seeded RNG / ScriptedDice)

1. `BearOffSituation` type; eligibility per direction from the turning charts (6.D.2, examples 1–3 as tests).
2. Resolver: `bear_off_decisions` input, `decision_needed` outcome, "collide" choice; AI decider hook. Without a human ship the behaviour is unchanged apart from turning on success.
3. Success = turn + deceleration amendment + replay; 6.D.5 once per turn. Test with Constellation example 6.D.4: speed 9, plot 6P1, conflict after 2, success to starboard → 2S3.
4. Same-segment ordering d10 (6.D.3c).
5. TurnPhaseController: pause/resume protocol, `player_submit_bear_off` validation, END_TURN clear.
6. View: playback pause and resume at a segment; the decision panel; enemy plot overlay (if 4.3 = yes). Drive it with real clicks via godot-mcp.
7. Log text: "X bears off to starboard (rolled 2, needed ≤ 5)", "X holds course and collides with Y", and the existing collision lines.
8. Docs: feature_diff §1 item 7, §3 6.D row, §2.2 "order of bear-off resolution and once-per-turn limit"; CLAUDE.md movement section.

## 7. Open questions

1. Prompt timing: A (pause playback) or B (before playback)?
2. Show the other ships' plots during the decision (6.D.3a)?
3. Should the AI ever choose to ram (e.g. a larger class into a smaller one)? Recommend no, for now.
