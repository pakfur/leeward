# Planning on the board — design

Date: 2026-11-18. Status: draft for approval. Second piece of the UX pass (after the resolution
panel). Prototype: `prototypes/planning_radial/planning_radial.html` (commit 2c04a37), approved.

## Intent

Planning moves out of the side panel and onto the ships. Clicking one of your ships opens a radial
menu of what she can be ordered to do; Move lights every hex she can reach, you pick the hex and
her facing, and a dotted route and a ghost ship show the course. Fire, after movement, works the
same way on the board. The side panel becomes the place for status and the players.

Why: plotting a course hex by hex and declaring fire from a side-panel list put the player's eyes
in the panel instead of on the sea. The game is about ships; orders should be given to the ships.
Networked PVP is the end goal, so nothing here may assume one machine beyond what the game already
does.

## Goals

- A radial menu on each own ship in PLANNING and in fire declaration. Icons for every choice;
  choices that cannot be made now are greyed and say why (the server's own reasons).
- **Move:** every reachable end hex lit under the real movement rules; pick a hex, then an arrow
  for her facing; the route is drawn dotted and a ghost ship stands at the end; alternative routes
  to the same hex and facing can be cycled.
- **Plan / Done per ship** on the player's screen only (user decision): every movable own ship
  starts in Plan; Done marks her orders given; Tab goes to the next ship still in Plan. A ship
  still in Plan at End Planning sails her default course (6.G.2), and the side panel says so.
  End Planning stays one button (`player_submit_plan`).
- **Fire stays after movement** (user decision): in the fire declaration step ships whose guns
  bear show FIRE; the same radial offers port and starboard broadsides, the chasers, the marines,
  and hold fire; a target is picked on the map, and an option box by the target sets battery, aim,
  ammunition and voluntary reduction, with the number from the server's preview.
- **Orders ring** under Orders: cast the lead, declare escape, surrender, rally; and Signal with a
  small composer. These are the first player controls for those requests.
- The side panel becomes status and players: a roster (planning / ready / resolving) and a status
  card per own ship; the resolution panel still takes it during a replay.

## Non-goals

- No rule changes. Courses and fire orders are stored and checked by the server exactly as now.
- The crew & damage overlay is unchanged (user decision): crew, sails, fires, repairs, boarding,
  anchoring and towing orders stay there. The ring has one icon that opens it.
- Ship-to-ship talk (11.B.3) waits for multiplayer.
- No per-ship Done on the server (user decision): it is the local player's checklist.

## Anti-goals

- A legal course the player could plot today must not become unplottable.
- Lighting the reachable hexes must not stall the frame (precomputed, see Move).
- The view never mutates game state (strict server authority); every order is a server request.
- The greyed reasons must be the server's, never a second copy of a rule in the view.

## Decisions taken from the prototype (approved 2026-11-18)

- Pick a hex, then an arrow for the facing (the shortest route's facing is chosen on the hex
  click, so one click already sets a course).
- An explicit Done (in the ring and in a small chip box beside the chosen hex) rather than
  finishing the move marking Done; End Planning stays a button rather than firing automatically.
- The ring holds about six icons; rarer orders sit in a second ring under Orders.
- Enemy ships give their status plate on click, as today.

## Approach (user choice: four pieces, in order, each merged on its own)

1. **Moving on the board** — server reach query and whole-course request, the radial menu,
   Move, Plan/Done, End Planning; the old step-by-step course editing and the card's course
   block go.
2. **Orders ring** — lead, escape, surrender, rally, signal composer.
3. **Fire on the board** — fire radial, arcs, targets, option box, order arrows, Fire button;
   the fire declaration panel goes.
4. **Side panel as status and players** — roster and status cards.

Rejected: one branch for all of it (nothing playable until the end, one huge review); fire first
(it only makes sense once planning on the board exists).

## Piece 1: Moving on the board

### Server (read-only query and one request)

- `TurnPhaseController.course_reach(ship_id: String) -> Dictionary` (read-only, like
  `course_options`): `{}` when `DefaultCourse.can_move` is false; else
  `{"ends": Array, "max_ma": int, "min_mp": int}`. Each end is
  `{"hex": Vector2i, "facing": int, "mp": int, "tacking": bool, "routes": Array}`; each route is
  the step list as `DefaultCourse.as_dicts` gives it (the format `set_plotted_movement` stores).
  - Search: depth-first from the ship's position with an empty path, asking
    `MovementValidator.calculate_valid_moves(ship, hex, facing, path)` for the next steps at each
    node — the same rules the plotting already uses (turning distances, tacking at MA 0, speed
    change, blocked wind, critical MP loss, a jammed rudder, terrain and edges, towing).
  - An end is a node whose `ValidMovesResult.can_submit` is true (no rudder-jam error and a
    deceleration shortfall of 0; use the result's `mp_spent`, do not re-derive). The search is
    complete and finite: `calculate_valid_moves` already returns ahead and both pivots with every
    turn limit, and stops after a luffing end or an MA-0 turn.
  - Each end carries `stops: String`: `"tacking"` (an MA-0 turn: its Tacking roll may fail,
    `is_tacking_attempt`), `"irons"` (a pivot into a luffing heading ends her movement in irons),
    `"stopped"` (a stopped ship's first-step turn ends her movement, 5.E.8), or `""`. The chip box
    shows the matching warning.
  - Routes to one end (hex and facing) are keyed by the full step sequence (move types and
    positions), so two routes that share a bow track but turn at different places, and sweep the
    stern differently, are both kept; sorted fewest MPs first, then turns as late as possible; at
    most four kept per end. Different MP counts to the same hex and facing are routes of one end;
    each route shows its MP count (her speed next turn depends on it).
  - An end whose last step crosses a permitted escape edge (she leaves the map) is an end like
    any other, drawn as an arrow over the edge from the hex she leaves; the chip box says she
    escapes. Ends depend on her escape declaration (`_crossing_allowed`), so piece 2 refreshes
    her reach when the declaration changes.
  - The empty course (no move) is not an end; Reset course restores the default course.
- `TurnPhaseController.player_set_course(player_id, ship_id, steps: Array) -> String`: the same
  request checks as `player_extend_course` (PLANNING, commander, plan not submitted, ship able to
  plot); walks the steps in order from the ship's position, carrying the growing path as
  `player_extend_course` does. A stored step's `hex` is the resulting bow (unchanged for a
  pivot), while `validate_hex_selection` takes the click hex (for a pivot, the bow's neighbour in
  the new facing), so each step is matched against `calculate_valid_moves` by resulting hex,
  facing and move type, and that `ValidMove`'s click hex is validated. Stores the whole course
  with `set_plotted_movement` only if every step is valid; returns "" or the first refusal (course
  unchanged). A test plots a course with turns of both directions and an MA-0 turn.
- `player_extend_course` / `player_cut_course` stay (tests, AI) but the view stops using them.

### Precomputing the reachable hexes (user's suggestion)

The ends depend only on the ships' positions and states at the start of PLANNING (other ships'
plots do not count; a sail change completes later in the turn), so the view asks for every
movable own ship's `course_reach` as PLANNING begins, one ship per frame (`CourseReachCache`,
view), and reuses the answer when Move is chosen. A ship whose answer is not ready yet is asked
at once. The cache is dropped when PLANNING ends and refreshed for a ship whose ability to move
changes during planning (a rally). Performance target: `course_reach` under 50 ms for the
largest MA in `test_fleet`; a test measures it.

### View

- **Radial menu** (`scripts/ui/board_planning/`): a Control over the map, centred on the ship's
  screen position (camera `unproject_position`, followed every frame while open), items on a
  circle; hover or focus shows the item's name and either its hint or its greyed reason under the
  ring; keyboard: Tab next ship in Plan, Space opens the ring for the selected ship, Enter Done,
  Esc steps back (closes the ring, leaves Move, closes the option box). Icons are SVG files in
  `assets/ui/radial/`.
- Piece 1 ring: **Move**, **Crew & damage** (opens the overlay), **Orders** (greyed "coming
  soon" until piece 2, or omitted), **Reset course** (`player_reset_course`: back to the default course stored at PLANNING start,
  which for a stopped ship is to stay where she is; it also clears the cast lead), **Done** /
  **Plan again**. Move is greyed with `movement_block_reason` for a ship that cannot plot.
- **Move mode:** reachable end hexes lit on the hex overlay (a new layer), the hovered one brighter
  with a preview route and ghost; clicking an end sends `player_set_course` with its first route
  and shows the facing arrows (one per reachable facing at that hex) and a chip box (MP used,
  speed next turn, "Route n of m ⟳", "another ship lies there now", ✓ Done, Keep planning).
  Clicking an arrow or cycling the route sends `player_set_course` again. One click on a hex
  takes the end at that hex with the fewest MPs, ties to the facing nearest her present facing.
  Her own bow hex is lit when it is an end (a turn on the spot, or out and back): in Move mode a
  click there picks that end; her stern hex, Esc or Done leaves Move mode.
  **Cast the lead** (piece 2) only allows a course of 2 MP or less (`plan_errors`): when a longer
  course is set while the lead is on, the view also sends `player_set_cast_lead(false)` and the
  chip box says so. The dotted route
  follows the route's bow track; the ghost is a translucent outline of the ship at the end.
  A refused request shows its reason in the chip box.
- **Plan/Done** (`PlanChecklist`, view only): badges over each own ship (PLAN amber, DONE green,
  a lock for a ship that cannot plot), the same pill on the side card (click toggles), Tab and
  Space as above. The side panel footer: End Planning (enabled as today: `plan_errors` empty) and
  a line "n ships still in Plan sail their default course".
- Removed: `CourseClicks` step extension and course cutting by clicking the course; the card's
  Course block (its notes move to the chip box). `CourseView` keeps drawing every own course
  (dotted) and the default courses (faint).

## Piece 2: Orders ring

- Orders opens a second ring: **Cast the lead** (`player_set_cast_lead`; greyed unless the
  course is 2 MP or less), **Declare escape** (`player_declare_escape`; shown only when the
  scenario has an escape edge for her side; greyed with `MapRules.declare_error`), **Surrender**
  and **Rally** (`player_surrender` / `player_rally`; shown only when the scenario switches 14.B
  on; greyed with `SurrenderRules.surrender_error` / `rally_error`), **Back**. Standing orders
  show as small badges by the ship (lead, escape declared, surrender ordered).
- **Signal** (main ring): a composer by the ship: address (fleet / group / ship of her side),
  text with the word count against `SignalText.limit`, Send / Cancel; the pending signal is shown
  with Cancel (`player_cancel_signal`); greyed with the server's reason (halyards cut, dismasted).
  Delivered signals stay in the log as now.

## Piece 3: Fire on the board

- In the fire declaration step every own ship with an eligible shot
  (`gunnery_calculator.eligible_shots`, `marine_fire_resolver.eligible_marine_shots`) is in Plan
  with a FIRE badge; the rest Done with "no target".
- Fire ring: **Port broadside**, **Starboard broadside**, **Bow chaser**, **Stern chaser**,
  **Marines**, **Hold fire / Clear orders**, **Done**; greyed with the reason no target bears.
- Picking one shades its arc (`FireGeometry` per battery; the chase arc) and rings each enemy it
  bears on with the range. Clicking a target opens the option box beside it: battery (full / bow /
  stern, only those that bear), aim (low / high; high forced at range 10–15), ammunition (round /
  dismantling within 7), voluntary reduction stepper, the modified gunfire number and modifiers
  from `GunneryCalculator.preview_orders` over the whole order set, the two-target note, Order /
  Cancel. Marines: the column and chance from `MarineFireResolver.preview`.
- Orders are arrows coloured by side (port, starboard, chase, muskets) with the number; the side
  panel footer has **Fire** (`player_submit_fire_orders` with gun and marine orders); ships still
  in Plan hold fire, and the footer says so.
- The fire declaration panel is removed; its pure helpers that `FireRules` does not already hold
  move to a small view helper used by the option box.

## Piece 4: Side panel as status and players

- **Players:** each player of the game (`GameState.player_ids()`), human or AI, with their side
  colour and state: planning / ready (`phase_controller.is_player_ready`) / resolving (the local
  player's `ResolutionReplay.resolving`; other players show resolving only once networking
  reports it).
- **Your ships:** a status card per own ship (today's `ShipCardStatus`: hull, rigging, crew,
  marines, guns, badges) with the Plan/Done pill; clicking a card selects the ship and pans to it.
- The resolution panel keeps taking the side panel during a replay.

## Left to the builder

- Icon art (simple, legible at 26 px, period-flavoured), radial animation and sizes.
- Whether the facing arrows and chip box are 2D Controls following the camera or 3D overlay
  meshes (the prototype used 2D).
- The ghost ship's look.
- Exact wording of hints and badges (reasons come from the server).

## Later (not this work)

- Ship-to-ship talk in the Signal composer (11.B.3), once multiplayer exists.
- Per-ship Done shared with teammates, if multiplayer wants it.
