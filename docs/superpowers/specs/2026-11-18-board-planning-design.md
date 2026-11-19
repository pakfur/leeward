# Planning on the board — design

Date: 2026-11-18. Status: draft for approval. Second piece of the UX pass (after the resolution
panel). Prototype: `prototypes/planning_radial/planning_radial.html` (commit 2c04a37), approved.

## Intent

Planning moves out of the side panel and onto the ships. Clicking one of your ships opens a radial
menu of what she can be ordered to do; Move puts her into today's hex-by-hex course plotting on
the map. Fire, after movement, works the
same way on the board. The side panel becomes the place for status and the players.

Why: plotting a course hex by hex and declaring fire from a side-panel list put the player's eyes
in the panel instead of on the sea. The game is about ships; orders should be given to the ships.
Networked PVP is the end goal, so nothing here may assume one machine beyond what the game already
does.

## Goals

- A radial menu on each own ship in PLANNING and in fire declaration. Icons for every choice;
  choices that cannot be made now are greyed and say why (the server's own reasons).
- **Move:** the ring's Move enters today's hex-by-hex course plotting for that ship (user
  decision: no precomputed reachable hexes in this work).
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
- The view never mutates game state (strict server authority); every order is a server request.
- The greyed reasons must be the server's, never a second copy of a rule in the view.

## Decisions taken from the prototype (approved 2026-11-18)

- An explicit Done (in the ring and in a small chip box beside the chosen hex) rather than
  finishing the move marking Done; End Planning stays a button rather than firing automatically.
- The ring holds about six icons; rarer orders sit in a second ring under Orders.
- Enemy ships give their status plate on click, as today.

## Approach (user choice: four pieces, in order, each merged on its own)

1. **The radial menu and planning per ship** — the ring, Move into today's course plotting,
   Plan/Done, End Planning; the card's course block goes.
2. **Orders ring** — lead, escape, surrender, rally, signal composer.
3. **Fire on the board** — fire radial, arcs, targets, option box, order arrows, Fire button;
   the fire declaration panel goes.
4. **Side panel as status and players** — roster and status cards.

Rejected: one branch for all of it (nothing playable until the end, one huge review); fire first
(it only makes sense once planning on the board exists).

## Piece 1: The radial menu and planning per ship

**User decision 2026-11-18:** the precomputed reachable hexes, the hex-then-facing pick and the
route choice are dropped from this work (too many edge cases to settle now). Movement is plotted
as today, one hex at a time on the map; Move in the ring is the way into it. No server change.

### Server

None. The view keeps using `course_options`, `player_extend_course`, `player_cut_course`,
`player_reset_course` and `player_submit_plan` as now.

### View

- **Radial menu** (`scripts/ui/board_planning/`): a Control over the map, centred on the ship's
  screen position (camera `unproject_position`, followed every frame while open), items on a
  circle; hover or focus shows the item's name and either its hint or its greyed reason under the
  ring; keyboard: Tab next ship in Plan, Space opens the ring for the selected ship, Enter Done,
  Esc steps back (closes the ring, leaves Move mode, closes the option box). Icons are SVG files in
  `assets/ui/radial/`.
- Piece 1 ring: **Move**, **Crew & damage** (opens the overlay), **Orders** (omitted until piece
  2), **Reset course** (`player_reset_course`: back to the default course stored at PLANNING
  start, which for a stopped ship is to stay where she is; it also clears the cast lead),
  **Done** / **Plan again**. Move is greyed with `movement_block_reason` for a ship that cannot
  plot.
- **Move mode** (one ship at a time): today's course editing for that ship only: her valid next
  hexes lit (`course_options.valid_next`), a click on one extends the course
  (`player_extend_course`), a click on her course cuts it back (`player_cut_course`). Clicking any
  other ship, empty sea away from her course, Esc or Done leaves Move mode. A small chip box at the
  course end shows "n of m MP", the course notes today's card Course block shows (tacking,
  steering, collision, deceleration short), a refusal reason when a click is refused, and ✓ Done /
  Keep planning. Outside Move mode, clicks on the map never edit a course (they select ships and
  open rings).
- **Plan/Done** (`PlanChecklist`, view only): badges over each own ship (PLAN amber, DONE green,
  a lock for a ship that cannot plot), the same pill on the side card (click toggles), Tab and
  Space as above. The side panel footer: End Planning (enabled as today: `plan_errors` empty) and
  a line "n ships still in Plan: they sail the course shown" (singular: "1 ship is still in Plan: she sails the course shown"; wording ruled in the piece-1 final review).
- Removed: the card's Course block (its line and notes move to the chip box; Reset course moves
  to the ring); `CourseClicks` now routes only the Move-mode ship's clicks. `CourseView` keeps
  drawing every own course.

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
- Whether the chip and option boxes are 2D Controls following the camera (the prototype) or 3D.
- Exact wording of hints and badges (reasons come from the server).

## Later (not this work)

- Precomputed reachable hexes with a hex-then-facing pick and route choice (prototyped, set
  aside by the user 2026-11-18).

- Ship-to-ship talk in the Signal composer (11.B.3), once multiplayer exists.
- Per-ship Done shared with teammates, if multiplayer wants it.
