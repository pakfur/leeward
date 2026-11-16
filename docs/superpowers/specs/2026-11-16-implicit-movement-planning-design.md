# Implicit movement planning: design

Date: 2026-11-16. Status: approved by the user 2026-11-16 (reviewed by a builder check; its questions are answered below).

## Intent

Planning today has an explicit per-ship **Movement** mode. You press Movement on a ship's card, click hexes, then press Submit (or Cancel). Only one ship plots at a time, and End Planning stays disabled until every ship has submitted.

The user wants planning to be one continuous editing surface instead. Every one of the player's ships always shows where it can go. Clicking the map edits that ship's course. Planning ends when the player says so. The modes, toggles and per-ship Submit go away. That removes friction and makes the map the main place where movement orders are given.

## What the user asked for

1. During PLANNING, the movement hexes of all the player's ships are shown.
2. Any ship's course is extended by clicking one of that ship's highlighted hexes.
3. A ship's course is cut back by clicking a hex already on its course.
4. Clicking a ship's movement hex selects that ship in the planning panel.
5. An explicit **End Planning** button sits at the bottom of the planning panel, with a **Cancel** button beside it. Cancel asks for confirmation, then resets the planning stage to how it stood at the start of the turn.
6. (Answer to a question.) A ship the player never plots keeps last turn's speed and heading. This is rule 6.G.2, *Failure to Plot*: "his ship moves ahead at the same actual speed as the previous g-t. If that is impossible … it moves ahead at the speed closest to last g-t's plotted speed that it can legally reach."

## Goals

- No Movement button, no per-ship Submit or Cancel, and no single-ship plotting mode.
- Every own ship that can move always has a stored course, visible on the map, from the moment PLANNING begins.
- Each click is a server request. The server validates it and stores the result at once, so the map, the crew overlay (braces for an MA-0 turn) and the resolver all read the same course.
- End Planning is always available in PLANNING until the plan is submitted.
- Cancel restores every own ship's orders to their start-of-turn state.
- The game follows 6.G.2 for any ship with no plot, including AI ships. `docs/rules/feature_diff.md` row 6.G.2 changes from a difference to "as the rules".

## Non-goals

- No change to the movement rules themselves: the validator, the resolver's segment model, collisions, bear-off, overlap rollback.
- No enforcement of the 5.A.4 deceleration minimum on player plots. It stays unenforced, as today. Only the 6.G.2 default course respects what the ship "can legally reach".
- No change to the AI's plotting strategy.
- No change to sail, crew or boarding orders, apart from restoring them on Cancel.

## Anti-goals

These would make the change a failure even if it works.

- **A course on the map that is not the stored course.** The point of approach A is one source of truth.
- **Hexes that cannot be told apart.** With several ships' hexes on the map at once, the player must always know which ship a hex belongs to. A click must never extend a different ship's course than the one the player meant.
- **A Cancel that loses orders the player did not mean to lose without asking.** It must confirm first. It must not reach into the previous turn: tasks already in progress are untouched.
- **Server authority weakened.** View code still never writes ShipState. Every edit is a request that is validated and answered with "" or a reason.

## Approaches considered

**A. Every ship always has a stored course (chosen).** When PLANNING begins, the server gives each own ship that can move its 6.G.2 course and stores it as the ship's plot. Each click is a request that edits the stored course and stores it immediately. Planned hexes are read from `plotted_actions.movement`. This is one source of truth: the crew overlay sees MA-0 turns at once, and Cancel just restores the start-of-turn snapshot. It costs server work: a request to reopen and edit a stored course, so for the player the session idea mostly goes away.

**B. One open session per ship until End Planning.** Each ship's course lives in an open plotting session and is stored only when End Planning is pressed. Untouched ships get 6.G.2 when movement resolves. This is less server work. But nothing outside the session sees an open course (crew rules read the stored plot), and the default course would need separate drawing code. Map, overlay and resolver could disagree. The user chose A.

## Design

### Server

1. **6.G.2 default course.** Add a pure query: given a ship and the current wind and state, return the course "ahead at last turn's speed, or the nearest speed it can legally reach". It is a list of ahead steps of length `n`.
   - `n` = `min(ShipState.speed, this turn's movement allowance)` (sail, rigging, wind facing, blocked wind, crit MP losses), further limited by any per-turn acceleration limit the validator applies to ahead moves.
     - *Planner's call:* use `ShipState.speed`, the actual speed last turn. The rule's first sentence says "actual". Its fallback mentions last turn's *plotted* speed, but that is not kept, and keeping it is not worth a new field.
     - *Planner's call:* when the MA is below the deceleration minimum (5.A.4), the MA wins. The game does not enforce the deceleration minimum on plots anywhere else, and a course past the MA would not validate.
     - Note both in the `feature_diff.md` 6.G.2 row.
   - If the ship cannot move at all (MA 0, luffing), the course is empty and the ship holds.
   - A ship that is fouled, grappled, struck, dismasted, destroyed or captured has no course; the existing refusals apply.
   - Ahead steps into another ship's hex are still a legal plot: collisions are resolved as today.
   - Use it in two places:
     - **At PLANNING start** (`TurnPhaseController._enter_planning_phase`, before the AI plots): store this course for every ship of every human player that can plot movement. Snapshot it as the ship's *start-of-turn course* (see Cancel).
     - **In the resolver**, replacing `SKIP_NO_PLOT`: a ship with no stored plot (an AI or headless-test ship) moves on its 6.G.2 course. Update `feature_diff.md` row 6.G.2 and its tests. Headless tests that rely on an unplotted ship staying put must plot an explicit empty course; the builder finds them by running the suite.

2. **Editing a stored course.** Add request methods on `TurnPhaseController`. Final names are the builder's call; these are the shapes.
   - `player_extend_course(player_id, ship_id, hex) -> String`: append the move whose click target is `hex` to the ship's stored course, validated exactly as today's SELECT_HEX. On success the new course is stored. Returns "" or a reason.
   - `player_cut_course(player_id, ship_id, step_index) -> String`: drop step `step_index` and every step after it, then store.
   - A read-only query for the client, e.g. `course_options(ship_id) -> {path, valid_next: ValidNextHexes, remaining_ma, is_tacking_attempt, …}`. It carries what `PlottingStartedResponse` / `HexSelectedResponse` carry today, so the client can draw hexes, hover previews, collision warnings, the steering note and the tacking note.
   - Every request checks what `_turn_refusal` and the crew requests check: PLANNING, not ready, the ship is the player's, and the ship can plot.
   - Implementation is the builder's call. Rebuilding a `MovementPlottingSession` from the stored path, applying the change and storing it is a reasonable way to reuse the validator unchanged. Sessions must not leak; nothing should stay open between requests.
   - `player_clear_movement` stays. Cutting at step 0 is the same thing.

3. **Cancel (planning reset).** At PLANNING start, record a per-ship *start-of-turn snapshot* for each own ship (server state, not view state):
   - the default course;
   - `crew_auto`;
   - the boarding order (`crew_orders.boarding`).

   Add a request `player_reset_planning(player_id) -> String`. It checks PLANNING and not ready, then for each of that player's ships:
   - movement ← snapshot course;
   - crew plan ← the carry-over default (`ShipStateController.clear_crew_plot`), which clears assignments, `crew_plotted` and `sail_target`;
   - boarding order ← snapshot;
   - `crew_auto` ← snapshot.

   Tasks already in progress, and anything not plotted this turn, are untouched. The snapshot is cleared at END_TURN.

4. **End Planning.** `player_submit_plan` is unchanged: it already needs no plots. Every ship now always has a stored course, or none when it cannot move.

5. The session protocol (`MovementPlottingController`) stays for the StubAI and its tests. The player's client stops using it. The CLAUDE.md "Movement Plotting Protocol" section is updated to say so.

### Client and view

1. **No Movement mode.**
   - Remove the card's Movement button and the shared plotting-controls box: Undo, Undo all, Submit, Cancel and the MA readout.
   - Remove `submitted_ships`, `mark_ship_submitted`, the ✓ marks and the "orders given" title.
   - Remove the client's single-session state from `MovementPlottingClient`, or replace the client with one that makes the new requests.
   - Remove `is_plotting()` gating where it only existed for the mode: the own-ship click guard, cancelling a plot on card change, and closing the crew overlay on plot start.

2. **Course readout on the expanded card.** The useful parts of the old plotting box move onto the selected ship's card, under its status box:
   - the movement allowance used and left (e.g. "Course: 3 of 5 MP");
   - the tacking note;
   - the steering / rudder note;
   - collision warnings;
   - a **Reset course** button, which restores the ship's start-of-turn course.

   Exact layout is the builder's call, in the card's existing style (`CrewStyle`, theme variations).

3. **Map.**
   - For every own ship that can plot, draw its stored course and its valid next hexes, all at once.
   - The selected ship's course and hexes are drawn at full strength; other ships' are dimmer.
   - Each ship's valid hexes and course are told apart by the ship they belong to: they start from that ship's bow, and the hover preview names the ship.
   - `HexOverlay` needs per-ship valid-hex sets and course nodes in place of today's single `_valid_hex_positions` and plotted-path node.

4. **Clicks.**
   - **Valid next hex:** extend that ship's course and select the ship in the panel.
   - **Hex on a ship's course:** cut that ship's course to *before* that step, so clicking the last step removes just that step. Then select the ship.
     - *Planner's call:* a turn step is drawn and hit-tested on the bow hex it keeps, as `HexOverlay.show_plotted_path` draws it today. It is not drawn on the neighbour in the new facing, because that neighbour is the next ahead hex and must stay clickable to extend the course.
     - When one hex holds several steps (an ahead step into a hex, then a turn there), a click cuts at the latest step there. Clicking again cuts the next one back.
     - At the course end, a valid next hex beats a course hex of the same ship.
   - **Overlap:** when a hex is a valid next hex, or a course hex, for more than one ship, the click goes to the ship selected in the panel. If none of them is selected, it goes to the ship whose course end (bow after the last step) is closest to the hex; ties go to the lower ship_id. Course hexes take precedence over valid next hexes for the same ship.
   - **Course wins over ships (user decision).** A click on a hex that is a course hex or valid next hex of any own ship goes to that course, even if a ship lies on the hex. This is how plotting works today (`_unhandled_input` tries the hex first). Moves into an occupied hex therefore stay clickable: a follower's ahead into the leader's stern, or a turn toward an adjacent ship. To select a ship whose hull is under someone's hexes, click its card in the panel or a part of it that is not highlighted.
   - **A ship, on a hex no course claims:** select it, as today. An enemy pins its status plate, as today.
   - **Empty water:** deselect, as today.

5. **Hover preview.** Show the speed and point-of-sail preview for whichever ship the hovered hex would go to under the rules above.

6. **Planning panel footer.**
   - **End Planning** is always enabled in PLANNING until the plan is submitted. It no longer shows the (n/N) count.
   - **Cancel** sits beside it. It opens a confirmation ("Reset all orders for this turn? Courses, crew, sail and boarding orders go back to how they were at the start of the turn.", with Reset / Keep orders). On Reset it calls `player_reset_planning` and redraws everything.
   - The instructions text (`PlanningText.instructions`) is rewritten for the new flow, e.g. "Click a ship's highlighted hexes to plot its course. Click a hex on its course to cut it back."

7. **Other UI that read the mode.**
   - The crew overlay stays as is. While it is open it covers the map, so hex clicks under it are not taken.
   - The enemy status plate: during PLANNING it shows on click only, not on hover, so it never pops up over the hexes being clicked.
   - The selected-ship speed / point-of-sail label keeps its current rule (shown only while the plate is suppressed).

### Tests

- 6.G.2 default course:
  - at last speed;
  - capped by a lower movement allowance;
  - MA 0 → empty;
  - a ship that cannot plot → none;
  - acceleration limit, if any.
- Planning start stores the default for human ships and snapshots it.
- The resolver moves an unplotted ship on its 6.G.2 course.
- `player_extend_course` / `player_cut_course`: legal, illegal, wrong phase, after ready, not the owner, cut at 0, cut at the last step.
- `player_reset_planning` restores course, crew, sail, boarding and auto, and leaves tasks in progress alone.
- Click routing helpers: the overlap rule and the course-hex precedence. Write these as pure statics so they can be tested.
- `test_server_authority.gd` still passes. The new view calls must be requests or read-only queries.

## Left to the builder

- Names of the new requests and queries, and whether the client keeps `MovementPlottingClient` (reworked) or replaces it.
- The tie rule for the 6.G.2 speed.
- Course readout layout on the card. Dim styling for non-selected ships' hexes.
- How `HexOverlay` stores per-ship sets.
- Whether `TurnPhaseController` or a small new server object holds the start-of-turn snapshot. It must be server state.
- Removing code that becomes dead (plotting controls, session client state, `submitted_ships`) and updating CLAUDE.md, `feature_diff.md` and the instructions text.
