# Resolution panel — design

Date: 2026-11-18. Status: draft for approval. First piece of the UX pass.

## Intent

After the players have plotted movement and fire, the turn's dice rolls that change a ship are
shown one action at a time in a panel on the left of the screen, instead of as log lines. Each
step shows animated dice that land on the server's result, what is being rolled for, a picture
of the action, the modifiers and final number, and the outcome. The camera closes in on the
ship the step is about. The player clicks **Next** to go on, or **Resolve all** to run through
the rest. The goal: resolution should feel like something happening, not a log to read.

Why: the game resolves a great deal (gunfire, criticals, morale, boarding, drift, fire, towing)
and today it is a scrolling text log revealed on a timer. Networked PVP is the end goal, so the
replay must work per player.

## Goals

- A resolution panel on the left side, shown while the turn resolves and its replay plays.
- **One step per action** (user decision): a shot is one step, with its gunfire roll, any
  critical hit and the damage on one card; each morale check, drift, grapple, fire roll, tow
  attempt, boarding round and so on is a step of its own.
- **Next** advances one step; **Resolve all** plays the remaining steps quickly (dice settle at
  once, the camera does not move) and ends the replay.
- Animated dice (d6, d10, 2d6, 2d10 as the roll was) that land on the server's result.
- Each step: a title (what is rolled for), a placeholder picture per kind of step, the roll, the
  modifiers and final number where the event carries them, and an outcome line.
- The camera closes in on the step's ship (`IsometricCamera.focus_on_ship`) on each step.
- **Each player steps through their own replay** (user decision). The server resolves the turn
  as now and never waits for anyone's replay beyond what it waits for today.
- **Displayed ship state follows the replay** (user decision: build it if it is not large; it
  is moderate, see below): ships on the map show the state as of the step being shown, at the
  granularity below, not the end-of-turn state.

## Non-goals

- No change to game rules, dice or the server's turn loop. No new server request.
- No real art: pictures are placeholders (one per kind of step).
- No cannon-fire or smoke animation on the map (a later phase, user's note).
- No player roster or ship-status-only left panel yet (see Later).
- Movement playback is unchanged (it already animates); movement-phase rolls (tacking, bearing
  off, collisions) are out of this panel for now.

## Anti-goals

- The replay must never hold up the other player or the server.
- The panel must never show a different number from the one rolled (it reads the event).
- It must never mutate game state (strict server authority): view code only.
- It must not be slower to get through than the log is now, for a player who wants speed:
  Resolve all and the existing skip stay one click away.

## How it works today (facts the design rests on)

- Every turn-log event (`PhaseEvents.PhaseEvent`) carries its dice and modifiers in `data`:
  FIRE has `roll`, `modifiers`, the final number and results; MORALE_CHECK has `roll`, `rating`,
  `passed`; DRIFT has `roll`, `needed`, `modifier`; and so on.
- Only movement and combat wait for the view. COMBAT_RESOLUTION emits `combat_log_ready` and
  waits for `on_combat_playback_completed()`; `GameController._play_combat_log` reveals the
  combat log lines on a timer (skippable). DRIFT_CALCULATION, STATUS_ADJUSTMENT, MORALE_CHECK
  and MESSAGE_DELIVERY run straight through to POST_COMBAT, which waits for End Turn
  (STATUS_ADJUSTMENT may pause for a human's maintenance orders).
- `phase_changed` is emitted at the start of each phase, before its work, with two exceptions:
  COMBAT_RESOLUTION emits it on entry and again at DECLARE (after `boarding_controller.declare()`;
  the boarding-only path skips the second), and PLANNING emits it after its entry work.
- The combat log's "(yours)"/"(enemy)" labels come from `CombatLogPanel` (its name map,
  `event_names`), not from `PhaseEvent.to_text`.
- Combat has a boarding-only path that emits `combat_log_ready` with no fire declaration.
- Tests and AI-only runs skip playback (`skip_post_combat_delay`, the combat panel's skip).
- `ShipView.sync_to_state(ship_state, hex_grid)` draws any `ShipState` it is given;
  `ShipState.serialize()` / `deserialize()` make a detached copy.
- The left panel is `ContextPanel` (`set_context_content`), holding the planning UI.

## Approaches considered

- **A. In the real game, driven by the turn log (chosen).** A pure step builder groups the log
  into steps; a resolution panel shows them; the camera focuses per step. Combat replaces the
  timed reveal; the post-combat phases replay in the POST_COMBAT wait. Real ships, camera and
  dice; grows into the finished feature.
- B. A throwaway standalone scene with a saved log. Fastest for the look, but the camera move,
  half the effect, is untested, and it would be rebuilt.
- C. Server pauses after each phase until the view finishes. Keeps state in sync for free, but
  contradicts per-player replay; dropped.

## Design

### Steps (pure, unit tested)

`ResolutionSteps` (`scripts/ui/resolution/resolution_steps.gd`, pure statics):
`build(turn_log, from_index, phases) -> Array[ResolutionStep]`. A step is
`{kind, phase, ship_id, target_id, events: Array[PhaseEvent], dice: Array[{sides, values}],
title, modifiers: Array[{label, value}], final, outcome}`.

- A **lead event** opens a step; following events that belong to it (same phase, naming the
  same ship pair, of a follower type) are folded in until the next lead event. FIRE leads and
  folds the DAMAGE, critical-hit, GUNS_DISMOUNTED and MORALE_NOTED events it caused; MORALE_CHECK,
  DRIFT, GRAPPLE, UNGRAPPLE, UNFOUL, BOARDING_ROUND, MARINE_FIRE, FIRE_FOUGHT, EXPLOSION_CHECK,
  TOW_BEGUN, RALLY, AIM_FORCED and the like lead their own step. Events with no die and no
  change worth a card (HOLD_FIRE, SIGNAL, informational events) are not steps; they stay in the
  log.
- Which types lead, which follow and which are skipped is one table in this file; the exact
  table is the builder's, checked against the events each controller actually logs.
- Text (title, modifier labels, outcome) reuses the existing event wording (`to_text`) and the
  ship names by side, through the name map `CombatLogPanel` already builds (moved to a shared
  helper if needed); no rule logic in the view.
- **Input is the player's view of the log** (builder's call): steps are built from
  `PlayerView.events_for(local_player_id, turn)` dictionaries, not the raw log, so the panel shows
  only what that player may see (14.C: no box counts for ships the player does not command,
  no other side's signals, no other players' hidden preparations). Dice, modifiers and outcomes
  of enemy shots stay visible; box counts read "sections lost" as the filtered event gives them.
  The existing combat log is unchanged.

### Panel

Boarding rounds become steps; the existing `BoardingCard` is still shown, when its step comes up
(builder's call: kept, not replaced). The collapsed combat log's reveal limit is set to just past
the last event of the step shown.

`ResolutionPanel` (`scripts/ui/resolution/resolution_panel.gd` + scene) is put into the left
panel with `ContextPanel.set_context_content` while a replay runs, and the previous content is
restored after. Layout, top to bottom: phase and step count ("Combat · 3 of 11"), title, the
picture (a `TextureRect`, placeholder per kind), the dice (`ResolutionDice`, a drawn d6/d10
face that tumbles for ~0.8 s and lands on the value), modifiers and final number, outcome line,
then **Next ▸** and **Resolve all**. Keys: Space/Enter/→ = Next. The existing combat log stays
(collapsed) and fills in as steps are shown.

### Replay timing

- **Combat:** on `combat_log_ready`, `GameController` starts the replay of the combat steps
  instead of the timed reveal; when the player reaches the end (or Resolve all) it calls
  `on_combat_playback_completed()` as now. This is the one place a human's replay already holds
  the server, as today.
- **After combat:** drift, status adjustment (grapple, fire, repairs, tows, fixes), morale and
  messages resolve at once as now. On entering POST_COMBAT the view replays those phases'
  steps, then shows the End Turn button as now. A maintenance prompt (grapple, prize size)
  still comes when the server asks, before that replay (accepted limitation).
- No replay steps: the panel does not open.
- With `skip_post_combat_delay` (tests, AI-only runs) there is no replay: everything is instant, as
  now. The existing skip (Space/click on the log) acts as Resolve all.
- While the post-combat replay runs, End Turn is hidden; it appears when the replay ends
  (builder's call). The left panel content is not "restored" from a saved node: when the replay
  ends the view re-renders what the current phase shows (End Turn in POST_COMBAT).
- The replay is dropped, with no further calls to the server, when the game ends (`game_over`),
  the game is left, or the phase moves on past the one it is replaying (the combat replay still
  calls `on_combat_playback_completed()` only under today's guard).
- A maintenance prompt during STATUS_ADJUSTMENT shows as today, over the map; the post-combat
  replay starts only once POST_COMBAT is entered, after it.
- The camera focus keeps the ship clear of the left panel (the same left-panel offset the game
  controller uses for framing).
- In a networked game each client would run the same replay from the log it receives; nothing
  here assumes one machine except the snapshots below.
- `ResolutionReplay` (view state: steps, index, running) is one clear object, so a later roster
  can report "resolving" per player without reworking the panel.

### Displayed state in step with the replay

`DisplayStates` (view, `scripts/view/display_states.gd`): on each `phase_changed`, the view
stores a detached copy (`ShipState.deserialize(serialize())`) of every ship: the state before
that phase. Only the first `phase_changed` of a phase in a turn is kept (combat's second emission
at DECLARE is ignored), so boarders away and replotted marines appear with the first combat step. While a replay runs, `GameController._sync_all_views` (and the anchor, grapple and
tow lines) draw from the display copies instead of live state:

- At the start of a phase's replay every ship shows its state from before that phase.
- When a ship's last step in that phase has been shown, that ship switches to its state after
  the phase (the next phase's snapshot, or live state for the last).
- At the end of the replay, everything is live again.

So a drifting ship drifts on its drift step, and a ship hit twice in combat shows both hits after
the second shot (per ship per phase, not per hit). Per-hit state would need the server to snapshot
per event; deferred. The enemy status plate and ship cards read the same display copy while the
replay runs where it is simple to do; otherwise they show live state (builder's call, noted).

## Left to the builder

- The exact lead/follow/skip table, and the per-kind titles and placeholder pictures.
- Dice drawing and timing; panel styling within `leeward_theme.tres`.
- How Resolve all finishes (instant or a fast run).
- Tests: `ResolutionSteps` (grouping on real logs from scripted-dice turns), `DisplayStates`
  (which copy a ship shows at each step), and a live check through the godot MCP.

## Later (not this work)

- Planning moves out of the left panel; the left panel becomes ship status and a roster of all
  players (human or AI), their ships, and each player's state: planning, ready to resolve,
  resolving.
- Cannon fire and smoke on the map per shot; real pictures.
- Movement-phase rolls in the panel; per-hit displayed state.
