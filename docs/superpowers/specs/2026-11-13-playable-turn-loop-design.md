# Playable Turn Loop — Design Spec

**Date:** 2026-11-13
**Status:** Approved 2026-11-13; revised the same day against the 1997 rulebook (section 15
lists what changed after approval)
**Area:** Server controllers (`scripts/server/`), state (`scripts/state/`), rule data
(`data/rules/`), planning/combat UI (`scripts/ui/`, `scripts/core/game_controller.gd`)

Items marked **[call]** are decisions made by the spec author, not by the project owner.
They are listed again in section 14 so they can be reviewed in one place.

## 1. Intent

Leeward's turn loop already cycles through all ten phases, but only ENVIRONMENT, PLANNING and
MOVEMENT_RESOLUTION do anything. Every later phase is a stub that auto-advances, so a game
cannot be won, lost, or even meaningfully fought.

The goal is a game that is **playable for full turns against the AI**: ships manoeuvre,
choose targets, fire, take damage, drift, lose morale and strike, and one side wins.
The owner's intent is a deeply technical, tactical board-game simulation of age-of-sail
combat, based on the tabletop game *Close Action*. Rules may be changed where a change suits
a one-hex, computer-moderated game better.

This spec designs **Milestone 0 (foundations)** and **Milestone 1 (a turn that can be won)**
in detail. Milestones 2 and 3 are a roadmap only (section 13); each gets its own spec later.

## 2. Goals

- A scenario can be played from turn 1 to a declared winner, single-player against the AI.
- Gunnery follows the Close Action procedure and tables: gunnery factors by range, modifiers,
  die roll, result table, damage to rigging, hull and crew.
- Targets are chosen **after movement resolves**, simultaneously and hidden (owner's decision).
- Sail state can be changed by plotted order.
- Ships that do not move drift; ships check morale and strike.
- Every die roll and modifier is recorded in an event log the player can read.
- All new logic is server-authoritative, deterministic under a seed, and covered by GUT tests.

## 3. Non-Goals (this spec)

- Critical hits (including the hull and rigging checks made when a section is lost), fire,
  explosion, sinking, grappling, player-directed unfouling, boarding, marine fire, repairs,
  manual crew-task allocation, blocked wind (Milestone 2).
- Anchoring, towing, signalling, lower-deck gun/freeboard limits, heavy-weather rigging loss,
  terrain, prize crews, chase guns, half-broadside fire, medium guns (Milestone 3).
- Networking. The single-process `is_server == true` model is unchanged.
- Rich combat visuals. A readable log and state display are required; smoke, sound and
  animation are optional polish left to the builder.

## 4. Anti-Goals

- No invented combat maths. `docs/07-naval-combat-mechanics.md` (percentage accuracy, armour
  in millimetres) contradicts the Close Action tables and is **not** a source for this work.
  It should be marked non-canonical at the top of the file. **[call]**
- No hidden outcomes: a result the player cannot trace to a table row, modifiers and a roll
  is a defect.
- No turn that stalls waiting for input when the player has nothing to decide.

## 5. Rule Sources

- **Authoritative ruleset (owner's direction): the 1997 Clash of Arms edition**,
  `docs/CoA_-_Close_Action_the_Age_of_Fighting_Sail_vol_1_1997.pdf` (117 scanned pages;
  printed page = PDF page − 3). Key pages: sequence of play p45, ship log p94, Ship Data Chart
  p106 (notes p107), Movement p108, combat tables p109, Gunfire Results p110, Gunnery
  Factor/BGN p111, Rigging criticals p112, Hull criticals p113, victory p52. Rule numbers
  cited below (for example 7.C.15) are from this book.
- The same charts exist as cleaner scans in `docs/*.jpeg` and are the transcription source
  for tables.
- `docs/Close-Action-Rules-v6-1.txt` is an older edition (d6-based, different numbers) and is
  **not** to be used where it differs.
- Where the 1997 rule text and the 1997 chart disagree, the chart wins **[call]**. Known case:
  the two-target modifier is −10 in rule 7.C.12g and −12 on the Gunfire Results chart; use −12.
- **d10 is read 0–9**; 2d10 gives 0–18 (rule 1.D.2).

## 6. Milestone 0 — Foundations

### 6.1 Rule tables as data

Transcribe into `data/rules/*.json`, each with a `DataManager` loader and typed lookup, each
covered by the table validator (`.claude/skills/validate-rule-table/`) and a GUT test with
spot-checked cells:

| File | Source | Content |
|---|---|---|
| `gunnery_factor_table.json` | `gunfire_tables_2.jpeg` top | LG/MG/CR multiplier by range 1–15 |
| `basic_gunfire_number_table.json` | `gunfire_tables_2.jpeg` bottom | TGF × range → BGN; second (French) value at range 11–15; grey = cannot fire |
| `gunfire_results_table.json` | `gunfire_tables.jpeg` | FGN 1–52+, low and high, FS/+MS/+PS columns, CH# column |
| `gunfire_modifiers.json` | `gunfire_tables.jpeg` right column | all modifiers in 9.4 |
| `crew_loss_table.json` | `gunfire_tables.jpeg` bottom left | sailor/marine split by cause |
| `drifting_table.json` | `combat_tables_1.jpeg` | sail state × wind speed, class DRMs |
| `unfouling_table.json` | `combat_tables_1.jpeg` | success threshold by attempt number |
| `crew_quality_table.json` | `combat_tables_1.jpeg` | SK modifier, boarding factors |

Slashed gunfire results (`r/c`, `h-c/·`) must be stored so that the "roll d6: 1–3 left, 4–6
right" rule can be applied. The CH# column is stored now but not used until Milestone 2.

Transcription from a scan is error-prone. Each transcribed table must be checked cell by cell
against the image by a second pass before it is relied on.

### 6.2 Ship data

`data/rules/ships.json` currently stores real gun counts. The tables work on **gun factors
per side** (rule 1.G.7: "the LG and CR factors for each side of the ship"). Each ship
definition carries, from the Ship Data Chart: long-gun and carronade factors per side, the
critical-hit modifier (`CH`), the freeboard and lower-deck gunfire modifier (the chart's
`(F:L)` pair — stored, unused until Milestone 3), nationality, and the purchase-cost row
(victory points by crew quality/morale rating). The historical gun description may be kept
as display-only data.

Ship roster (owner's decision): only ships with a row on the chart are used.

- `frigate_38` — re-entered from the British 38 row.
- `ship_of_line_74` — re-entered from the British 74 row (class 2, manoeuvre type b). Its
  current values match no British 74 and are replaced.
- `corvette_24` — removed. It has no chart row and its class 5 is outside the tables' classes
  1–4. A British 32-gun frigate (`frigate_32`, class 3) is added and replaces it as the enemy
  in `test_basic.json` and `test_fleet.json`; tests that reference the corvette are updated.
  (Class 4 ships do exist as individual scenario rows in the 1997 scenario book, for example
  Volage on p79; adding them is a later, separate decision.)

### 6.3 Ship state

Extend `ShipState` (serialised, snapshotted, deserialised):

- `crew_count` becomes four sailor sections (it is three today, while `Ship.crew_count` and the
  rules have four) and is **initialised from the ship definition** in
  `initialize_from_scenario`, as is `marine_count`. Today both stay at zero.
- `crew_quality` is initialised from scenario/ship as a letter A–G and now changes in play.
- `morale_rating` (2–6, higher is worse; replaces `crew_morale`). Never changes.
- `status`: ACTIVE or STRUCK. **[call]** (sunk, captured and exited arrive with later
  milestones.)
- `guns_dismounted`: one value per side; a negative gunfire modifier (section 9.5).
- `initial_broadside_fired`: one flag per side.
- `sail_change`: target sail state, turns remaining and the sections assigned, or none.
- `moved_this_turn: bool` — set by movement resolution, read by drift.
- `pending_morale_checks: int` and the set of morale triggers already used (a section lost
  again later must not trigger twice).
- `unfoul_attempts: int` — attempts made against the current fouled partner.
- `plotted_actions.sail_change` already exists and is used as the plotted order.

All mutations go through `ShipStateController` methods with the usual server guard.

### 6.4 Dice and event log

- One helper for rolls (`d6`, `d10` as 0–9, `2d6`, `2d10`) drawing from `game_state.rng`, so a
  seed reproduces a whole game. The movement resolver's separate RNG may stay as is.
- A **phase event log**: an ordered list of typed events per turn (fire declared, shot
  resolved with table row/modifiers/roll, damage applied, drift, unfouling, morale check,
  strike, sail change, victory). The server emits it per phase; the view plays it back and
  the UI shows it as text. Whether this extends `MovementTypes.ResolutionLog` or is a new type
  is the builder's choice; the movement log's existing behaviour must not change.

### 6.5 Rigging level and sail availability (owner's decision: Close Action rule)

`ShipStateController.get_rigging_quality` derives a 1–4 quality from the percentage of total
rigging HP, and `movement_allowance.json` holds, for levels 1–2 at wind speeds 2–4, a single
entry keyed `ps`. The Movement chart (`docs/movement_1.jpeg`) shows the real structure:
columns are "number of rigging sections" 4 (fs/ms/ps), 3 (fs/ms), 2 (fs), 1 (fs). Replace the
current handling with the rule (5.F):

- **Rigging level = number of rigging sections that still have at least one box** (4 down
  to 0). Level 0 is dismasted.
- **Plain sail** only at level 4; **manoeuvring sail** at levels 4–3; **fighting sail** until
  dismasted.
- In `movement_allowance.json` the lone low-rigging entries keyed `ps` are re-keyed to `fs`;
  the numbers are kept (they match the chart). The table validator learns the expected key
  set per rigging level.
- A ship carrying more sail than its rigging allows is **not** forced to change sail. Its
  movement allowance is read from the highest sail state its rigging level allows; damage it
  takes still uses the sail state it is carrying until the crew alter sail (rule 7.D.6).
  It may only plot sail changes downward from the state it carries.
- A dismasted ship has movement allowance 0 (it only drifts) and uses the "Dismasted" drift
  row; any sail change in progress is cancelled.
- Existing tests that assume percentage quality or the `ps` keys are updated.

### 6.6 Known issues to fix along the way

`EnvironmentController` rolls each d10 as 1–10 and compensates in its thresholds for the main
2d10 roll, but two details are wrong against the chart:

- Wind speed follow-up d10: chart is 0–4 → −1 speed, 5–9 → +1 speed. The code gives +1 on a
  40% branch and −1 otherwise.
- Coastal wind direction changes on 2d10 results 2–3. The code changes on the equivalent of
  4–5.

Move these rolls onto the dice helper and correct both.

## 7. Turn Flow After This Work

The `GamePhase` enum is unchanged. **[call]**

1. **ENVIRONMENT** — as today.
2. **PLANNING** — movement plot (as today) plus an optional sail-change order per ship.
3. **MOVEMENT_RESOLUTION** — as today; additionally records `moved_this_turn`.
4. **COMBAT_RESOLUTION** — now two steps inside the phase:
   - **Declare.** The server computes every ship's eligible targets. If no ship on either side
     has any eligible target, the step is skipped silently. Otherwise the server waits for a
     fire-orders submission from each player. The AI submits immediately. Orders are hidden
     from the opponent until both are in.
   - **Resolve.** All fire is simultaneous: every shot is computed against the state at the
     start of the step, then all damage is applied. The server emits the event log and waits
     for the view to finish playback (same pattern as movement), then advances.
5. **DRIFT_CALCULATION** — drift for stopped ships.
6. **STATUS_ADJUSTMENT** — unfouling rolls; sail changes progress/take effect.
7. **MORALE_CHECK** — all morale checks noted this turn are rolled; strikes.
8. **MESSAGE_DELIVERY** — remains a stub.
9. **POST_COMBAT** — player reviews the turn's log and presses **End Turn**. The current
   two-second timer is removed.
10. **END_TURN** — victory check. If the game is over, the loop stops and a result is shown;
    otherwise state snapshots are saved and the next turn begins.

This matches the 1997 Maintenance order: drift, unfouling, then reconciliation (morale,
status update).

## 8. Sail Changes (rules 5.F.6–9)

- Sail states: NS (furled), FS, MS, PS. One step per order.
- FS↔MS and FS↔NS: one sailor section, one turn. MS↔PS: two sections, two consecutive turns.
  Crew quality E, F or G adds one turn to either.
- The change takes effect in the STATUS_ADJUSTMENT of its last turn. Until then the old sail
  state applies to movement and to damage taken.
- The assigned sections do nothing else until the change completes; they do not count as
  "sections firing" (rule 4.B.4). Allocation is automatic in this milestone: the
  highest-numbered sailor sections that still have boxes. **[call]**
- A change in progress cannot be cancelled by the player. It is cancelled if an assigned
  section is eliminated or the ship is dismasted.
- A sail state the ship's rigging level does not allow is not offered (section 6.5).
- A struck ship cannot change sail.

## 9. Gunnery

### 9.1 Fire orders

Per ship, for each broadside (port, starboard): hold fire, or name one target with an aim
(**low** at hull, or **high** at rigging) and an ammunition type — **roundshot** (range 15)
or **dismantling shot** (range 7). A ship may therefore engage at most two targets, one per
side, which matches the rulebook limit of two (7.A.4). **[call]** — Close Action's bow/stern
batteries exist because its ships are two hexes long; with one-hex ships each broadside is a
single battery, so the half-broadside modifier never applies.

Ranges 10–15 are high only. Struck ships neither fire nor are valid targets.

### 9.2 Arcs **[call]**

Ships face a hex side (directions 0–5). Measured from the ship's heading:

- **Broadside arc:** the 60° wedge centred on the beam, bounded by and including the two
  hex rows at 60° and 120° off the bow on that side (directions `facing ± 1` and
  `facing ± 2`), out to 15 hexes.
- Hexes outside both broadside wedges cannot be fired at. Chase guns are not modelled.

This matches the 60° battery arc of the rules and of `docs/02-game-rules.md`, and leaves
real blind zones ahead and astern.

### 9.3 Range, line of sight, rake

- **Range** is hex distance.
- **Line of sight** runs centre to centre. It is blocked if it passes through a hex holding
  any other ship. Where the line runs exactly along a hex edge, it is blocked only if both
  hexes sharing that edge are occupied. The rulebook's "friendly ships create blocking hexes"
  rule is deferred to Milestone 2.
- **Rake** (rule 7.E.2, adapted **[call]**): the target is within 5 hexes, the firing ship can
  fire at it, and the firing ship lies strictly inside the target's **bow or stern 60° wedge**
  (within 30° of the line ahead or astern; hexes exactly on the 30° boundary do not count).
  The rulebook's condition is "outside all of the target's fire arcs"; with one battery per
  side that would include the quarters, so the wedge ahead/astern is used instead.
  - Rake modifier: +4 at range 1–2, +3 at 3, +2 at 4, +1 at 5; it stacks with initial
    broadside.
  - A **stern** rake doubles the crew hits on the results table (7.E.5).
  - On one target, stern rakes are applied first, then bow rakes, then other fire.

### 9.4 Resolution (rules 7.C)

For each firing broadside:

1. **Total gunnery factor** = sum over gun types of (factors on that side × the range
   multiplier), fractions rounded up after adding.
2. **Basic gunfire number** from the BGN table by TGF and range (French-gunned ships use the
   second value at ranges 11–15). A grey cell means the broadside cannot fire at that range.
3. **Modified gunfire number** = BGN plus all of:
   - Firer's crew quality: A +6, B +4, C +2, D 0, E −2, F −4, G −6.
   - Sailor sections able to fire: 4 → 0, 3 → −3, 2 → −6, 1 → −9, 0 → cannot fire. A section
     counts if it has at least one box and is not assigned to a sail change.
   - Guns dismounted on that side (section 9.5).
   - Rake (9.3).
   - Initial broadside — the first time that side fires in the game, if the range is 5 or
     less: +4 at range 1–2, +3 at 3, +2 at 4, +1 at 5. If the side first fires beyond range 5
     the bonus is lost. Either way the flag is spent.
   - Two targets this phase: −12 on each shot.
   - Firing ship at plain sail in wind speed 2+: −1.
   - Dismantling shot: +1.
   - Wind speed 4: the value printed on the Gunfire Results chart. The rule text (7.C.12)
     says −1; read the chart (`gunfire_tables.jpeg`, "Other modifiers") and use its value.
   - Firing ship dismasted at the start of the turn: minus the sea state.
4. **Final gunfire number** = modified number + 1d6 (rule 7.C.15). A final number below 1
   has no effect; the shot still counts as fired. **[call]**
5. Read the Gunfire Results row for the aim. Take the FS column; add the +MS column if the
   **target** is at MS or PS; add the +PS column too if the target is at PS (7.D.5). A furled
   target takes the FS column with rigging hits halved (for a half box, roll d6: 1–3 it is
   lost). A dismasted target takes no rigging hits. Resolve slashed results with a d6.
   Dismantling shot ignores hull hits.

The UI must be able to show, before the player commits, the modified number for each possible
shot (everything except the die), so the same calculation must be callable as a pure query.

### 9.5 Damage (rules 7.D)

- **Rigging (`r`)** and **hull (`h`)** boxes come off the lowest-numbered section that still
  has boxes.
- **Crew (`c`)**: for each box roll d6 on the Crew Loss table — roundshot fired low: 1–5
  sailor, 6 marine; anything else (including dismantling shot fired low): 1–3 sailor, 4–6
  marine. Sailor boxes come off the lowest-numbered section with boxes. If the rolled type
  has none left, take the other.
- **Losing a hull section** dismounts guns on **both** sides: −1 for hull section 1, a further
  −2 for section 2, a further −3 for section 3 (cumulative modifier to gunfire). It also notes
  morale checks: one for section 1, one for section 2, two for section 3.
- **Losing hull section 4** (all hull gone): the ship strikes at once (9.C.2a).
- **Losing any crew section** (each sailor section, and the marines): one morale check. All
  crew boxes gone: the ship strikes.
- **Dismasted** (all rigging boxes gone): one morale check.
- An already-dismasted ship that is raked: one morale check.
- The hull and rigging *checks* on the critical-hit tables that the rulebook makes when a
  section is lost are Milestone 2.

## 10. Drift (rule 8.A)

In DRIFT_CALCULATION, every ship that is **stopped** — it did not move forward this turn, or
it collided, or it is fouled — rolls on the Drifting table (struck ships included): d10 (0–9),
+1 for class 3, +2 for class 4, against the number for its sail state and the wind speed.
A roll at or above the number means it drifts; "auto" always drifts; wind speed 0 never does.

- Resolve ships from most leeward to most windward.
- A drifting ship moves one hex directly downwind, facing unchanged.
- If that hex is occupied, the ship does not drift. A fouling roll is made on the Collision
  table (d10, 6+ fouled; −1 for the drifting ship, +1 per ship at MS, +2 per ship at PS; not
  if either ship is dismasted). No rigging damage.
- Ships fouled together roll once, using whichever ship is least likely to drift, and move
  together. If either is blocked, neither moves.
- Wind direction lies on a hex direction, so "directly downwind" is always a single hex.

### 10.1 Fouled ships

Today `fouled_with` is set by collisions, never cleared, and never read by movement.

- Fouled ships cannot plot or execute movement (no forward move, no turn). The movement
  validator and plotting controller must enforce this, and the AI must respect it.
- Fouled ships can fire if a target lies in a broadside arc, and can be fired on.
- In STATUS_ADJUSTMENT **each** ship of a fouled pair rolls once on the Unfouling table
  (rule 8.D): d10 plus that ship's SK modifier; succeeds on ≤2 at its first attempt against
  this partner, ≤3 at its second, ≤4 from the third on. If either succeeds, both are freed.
  No crew is needed. In the rulebook the roll is optional; in this milestone every eligible
  ship always attempts it, and struck ships do not roll. **[call]** Player-chosen unfouling
  arrives with grappling and boarding in Milestone 2.

## 11. Morale and Striking (rules 9.A–C)

- **Crew quality** (A–G) sets the gunnery modifier and the SK modifier (−3 to +3).
  **Morale rating** (2–6) never changes.
- Morale checks are noted when their trigger happens (section 9.5) and all rolled in
  MORALE_CHECK. Each trigger fires once per ship; a section lost again later does not
  trigger again.
- **Check:** roll d10 (0–9); a roll at or above the morale rating passes. No modifiers.
- **Failure:** crew quality drops one letter, permanently.
- **Striking:** a ship strikes when it loses all hull boxes, loses all crew boxes, or fails a
  morale check while already at crew quality G.
- A struck ship cannot move under orders, fire, change sail or roll to unfoul. It still
  drifts and stays on the map as an obstacle that blocks line of sight. It is not a valid
  target.
- There is no sinking in this milestone: in the 1997 rules ships are lost by striking, and
  sinking arises only from the waterline-damage critical hit (Milestone 2).

## 12. Victory, AI, UI, Tests

### 12.1 Victory (scenario book, section VI)

Checked in END_TURN.

- The game ends when every ship of one side has struck. If both sides are in that state on
  the same turn the result is decided on points.
- A scenario may set an optional `turn_limit`; the game also ends when it is reached.
  **[call]** (The rulebook's tournament length is 30 turns.)
- At game end the side with more **victory points** wins; equal points is a draw. A side
  scores, for each enemy ship, a share of that ship's point value (its purchase cost on the
  Ship Data Chart at its **starting** crew quality and morale rating):
  - struck: 100%;
  - otherwise, for sections completely lost: rigging sections 1–3: 5% each; rigging section
    4: 10%; hull sections 1–3: 10% each; each crew section: 10%. Fractions are not rounded.

### 12.2 AI

The stub AI currently only sails straight ahead. For a playable game it must, at minimum:

- steer to close with the nearest active enemy and turn to bring a broadside to bear once
  within gun range, using the existing plotting protocol and legal-move data;
- submit fire orders: for each broadside, the eligible target with the highest modified
  number; aim low inside range 10, high otherwise; roundshot always.

Heuristics beyond this are the builder's choice. The AI must go through the same server
requests as the player.

### 12.3 UI

- **Planning:** a sail-change control per ship, showing duration and that it will reduce
  sections available to fire.
- **Fire declaration** (new, shown only when the player has at least one eligible target): for
  each of the player's ships with a target, each broadside lists eligible targets with range,
  rake/initial-broadside flags and the modified number; the player picks target, aim and
  ammunition per broadside, or holds fire. Selecting a ship highlights its two broadside arcs
  on the hex map. One Submit for all ships.
- **Combat log:** a scrollable text view of the turn's event log, including table rows,
  modifiers and rolls.
- **Ship status panel:** hull, rigging and crew boxes by section, guns dismounted, crew
  quality, morale rating, sail state and pending sail change, fouled and struck status.
  Enemy ships show the same (no fog of war).
- **Post-combat:** an End Turn button replaces the timer.
- **Game over:** winner, turn count, points and ships struck on each side, and a way back to
  scenario selection.
- Struck ships are visually distinguishable.

Layout and styling follow the existing planning and context panels; details are the builder's.

### 12.4 Tests

- GUT unit tests for each table lookup, arc/LOS/rake geometry, gunnery resolution with fixed
  seeds, damage allocation, drift ordering and blocking, unfouling, morale and strike,
  sail-change timing, and victory points.
- `test_game_loop.gd` updated for the new waits (fire declaration, combat playback, End Turn),
  plus a scripted two-ship fight that runs to a winner.
- The determinism test extended to cover combat: same seed and orders → identical event logs.
- Controllers follow the `phase-implementer` skill; the `scv-reviewer` agent is run once at
  the end.

## 13. Roadmap After This Spec

**Milestone 2 — Close quarters:** critical hits (the stored CH# column; hull and rigging
checks on section loss), fire, spreading and explosion, waterline damage and sinking,
grappling/ungrappling and player-directed unfouling in POST_COMBAT, marine fire, boarding and
capture, repairs, manual crew-task allocation, blocked wind, friendly blocking hexes.

**Milestone 3 — Deferred:** anchoring, towing, signalling, lower-deck guns and freeboard,
heavy-weather rigging loss, terrain, prize crews, chase guns, medium guns, class 4 ships,
leaving the map.

## 14. Calls Made by the Spec Author

1. Where the 1997 rule text and chart disagree, the chart wins (two-target modifier −12).
2. `07-naval-combat-mechanics.md` is marked non-canonical.
3. `GamePhase` enum unchanged; fire declaration is a step inside COMBAT_RESOLUTION and is
   skipped when nobody has a target.
4. One battery per broadside; at most two targets per ship; no half-broadside fire.
5. 60° broadside arcs centred on the beam; no chase guns yet.
6. Rake = firer strictly inside the target's bow or stern 60° wedge at range ≤ 5.
7. Sail changes take sailor sections automatically (highest-numbered first).
8. Ship status limited to ACTIVE / STRUCK for now.
9. Optional scenario `turn_limit`.
10. Every eligible fouled ship automatically attempts to unfoul each turn.
11. A final gunfire number below 1 has no effect.

## 15. Changes After Approval (from the 1997 rulebook)

The owner approved the first draft and then named the 1997 PDF as the authoritative ruleset.
Reading it changed these points:

- **Sinking removed.** The 1997 rules have no sink roll for hull loss; a ship with no hull
  strikes. (The draft used a v6.1 sink procedure.)
- **Morale check** is d10 ≥ morale rating (draft: d6), morale rating runs 2–6, and a ship
  strikes on failing at crew quality G (draft: on reaching G).
- **Morale triggers** follow the ship log: hull sections 1/2/3 give 1/1/2 checks; each crew
  section gives one.
- **Hull section loss dismounts guns** on both sides (new).
- **No forced sail reduction.** A ship carrying sail it can no longer use keeps taking damage
  at that state and moves at the best state its rigging allows (draft: forced down at once).
- **Ammunition** is chosen per broadside and dismantling shot has no national restriction
  (draft: per ship, British barred).
- **Rake** widened from "exactly on the bow/stern hex row" to the bow/stern 60° wedge, to
  stay closer to the rulebook's "outside all of the target's arcs".
- **Unfouling:** each ship of the pair rolls with its own SK modifier.
- **Victory points** use the rulebook's partial-damage percentages.
- **Gun data** confirmed as factors per side; `(F:L)` is freeboard and lower-deck modifier.
- **Wind rolls:** two small errors in the existing environment code are to be fixed.
