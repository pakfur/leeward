# Anchoring: design

Date: 2026-11-17. Roadmap sub-project 4 of the sub-projects 3–7 run
(`2026-11-17-subprojects-3-7-decisions.md` §0 and §3, both binding). Status: draft written for the unattended
run. **U** marks the user's binding answers from the register; **B** the builder's calls, the register's or
new ones made here. A new or refined call is tagged **B (new)** or **B (refined)** with its reason beside it.
Research memo: `docs/superpowers/research/sp4.md`. Rules: `docs/rules/close_action.md` 13.A–F, 8.A.7, 8.B,
2.B.5, SoP V.A–B, 5.D.4a–b, 5.D.7, 7.C.12c, 13.E.3; ship log crew task codes
(`docs/rules/images/ship-log-blank-1.png`, checked: PBA 2/3, PSA 6±SK, PBS 2×(5±SK), PSS 2×(6±SK), PT 5±SK,
TX/A/AX/VO/VI/HS 1); Diagrams 25 and 26.

## Intent

Ships in Leeward can stop but never hold their ground: every stopped ship drifts, and a battle in a bay or
off a lee shore cannot be fought as the Scenario Book fights it (the Nile, Algeciras, Lissa). Anchoring is the
book's answer: a ship prepares an anchor, drops it once stopped, rides to it, and may rig springs to haul her
broadside round. This sub-project adds all of chapter 13 except 13.G (done in sub-project 3), played by the
stub AI and drawn by a view-only minimum.

## Goals

1. The nine anchoring crew tasks from the ship log (PBA, PSA, PBS, PSS, A, AX, VO, VI, HS), with their
   lengths, on the existing crew-task engine (manual and Automatic) (B, register).
2. Anchoring by bow or stern, normally or with springs (13.A.2–4), only where the scenario allows it
   (Scenario Book V.B; B, register: `anchoring` field), at most twice a scenario (13.A.5).
3. A ship must slow to a stop first: A needs a 0-MP plot, and the deceleration limit (5.E.4) stands (U).
4. The anchor's effects in the Maintenance Phase (SoP V.A–B), run in DRIFT_CALCULATION right after drift
   (B, register): the post-anchoring drift (13.C.5), the swing to the wind with the d6 (13.C.4), the oblique
   drift on a wind change (13.C.6), veering out (13.E.1), dropping and cutting (13.C.2, 13.F.2).
5. Springs at full cost (U): PBS 2 × (5 ± SK), PSS 2 × (6 ± SK); one HS section per turn; a spring turn
   pivots on the bow (AB) or the stern (AS, 13.D.2); applied in a short step at the start of
   MOVEMENT_RESOLUTION, before any ship moves; refused and logged when the swung-into hex is held; the ship
   fires on the new bearing that turn (U). Veering in (13.E.2) runs in the same step.
6. An anchored ship (or a group containing one) never rolls on the drift table (B, register).
7. The anchored +1 to the BGN (7.C.12c; already `"anchored": 1` in `gunfire_modifiers.json`).
8. The in-irons exceptions: anchored ships are never in irons (5.D.4a); the g-t after cutting is free
   (5.D.4b, 13.F.3).
9. Scenario: `anchoring` permission and a per-ship starting `anchor`; a test scenario with anchored ships.
10. The stub AI: ships that start anchored stay, rig springs and haul to bear; they cut when a signalled order
    says move and no enemy is in range; ANCHOR and CUT CABLES signals; emergency anchoring when drifting toward
    land or a `none` edge (B, register).
11. Anchor state public, preparation hidden by `PlayerView` (B, register).
12. View-only minimum (U): anchor marker and cable line, ANCHORED badge, combat-log lines, a read-only anchor
    station in the crew overlay, and Developer UI buttons to anchor and cut for manual testing.

## Non-goals

- Weighing anchor (13.F.1: only cutting is in the game).
- A depth limit for anchoring (the rules have none; register).
- Towing (sub-project 5), though the V.B sub-phase is built so towing can join it (§6).
- New input controls (U). Humans order anchoring through `player_plot_crew` (existing request: a crew order
  or hand-placed sections) and, for manual testing, the Developer UI.
- A swing preview, a springs turn drawn on the map, or an order picker in the overlay (later UX pass).

## Design

### 1. Geometry

An anchored ship is described by its anchor, not its hexes; the hexes follow from it.

- `anchor.hex`: the anchor counter's hex (fixed until cut).
- `anchor.end`: `"bow"` (AB) or `"stern"` (AS): the end the cable leaves from.
- `anchor.cable`: hexes from the anchor to the anchored end, 0–4. 0 only between dropping and the next drift
  step (13.C.2: the counter goes in the anchored end's own hex); 1 after the 13.C.5 drift; +1 per veer out
  (13.E.1c: at most 3 VOs, so at most 4); −1 per veer in.
- `anchor.veered`: VOs in effect, 0–3 (`cable = 1 + veered` once settled).
- The anchored end lies `cable` hexes directly downwind of the anchor:
  `end_hex = anchor.hex + cable × HexGrid.DIRECTIONS[(wind_direction + 3) % 6]`. AB: bow = `end_hex`, stern =
  `HexGrid.stern_of(bow, facing)`. AS: stern = `end_hex`, bow = `stern + DIRECTIONS[facing]`. Diagram 25 A–D and
  E–F, and 13.C.6's oblique drift, all follow from this one formula.
- Proper wind facing (13.A.3, 13.C.4): AB faces the wind (`facing = wind_direction`, WF=L), AS faces downwind
  (`facing = (wind_direction + 3) % 6`, WF=R).
- `anchor.swing_dir`: 0, −1 (port) or +1 (starboard): the direction a normal anchored ship is swinging in
  (13.C.4 "continues turning in that direction").
- `anchor.wind_dir`: the wind direction the ship was last laid to (a springs ship keeps its WF, 13.D.1).
- `anchor.springs`: rigged springs (13.D).
- `anchor.turn`: the g-t the anchor was dropped (0 for a scenario's starting anchor).

Turning conventions: port is `facing − 1`, starboard `facing + 1` (CLAUDE.md "Sides"). Fewest g-t's (13.C.4):
`diff = (proper − facing + 6) % 6`; 1–2 starboard, 4–5 port, 3 the d6 (1–3 port, 4–6 starboard).

### 2. Ship state

New `ShipState` fields (all mutated only through `ShipStateController`, all serialized):

| Field | Meaning |
|---|---|
| `anchor: Dictionary` | `{}` when not anchored; else the keys of §1 (`hex` a `Vector2i` in memory, `{"q", "r"}` serialized). |
| `anchor_ready: String` | `""`, `"bow"` or `"stern"`: PBA or PSA completed and not yet used (13.B.4). |
| `springs_ready: bool` | PBS or PSS completed before anchoring (13.B.2). |
| `anchorings_used: int` | Anchorings so far, 0–2 (13.A.5). A scenario's starting anchor counts as one (**B (new)**: the book counts anchorings, and a ship that begins at anchor has used one). |
| `cable_cut_turn: int` | The g-t of the last cut, −1 never (5.D.4b). |

Helpers: `is_anchored()`, `anchored_end_hex()`, `has_springs()`.

Consequences, wired through existing hooks:
- `DefaultCourse.can_plot` is false for an anchored ship; plotting is refused with
  `SHIP_ANCHORED` ("Ship %s is anchored: cut the cable (AX) to get under way (13.C.3)"). The resolver then
  gives it no default course and treats it as a stationary ship, as it does an aground one.
- `ShipStateController.remove_from_map` clears the anchor (a destroyed ship's anchor goes with it).
- Struck, captured and destroyed ships stay anchored until removed: their crews cannot plot anchoring tasks
  (`crew_can_act()`; a prize crew may plot only boarding and repairs, 10.H.2).

### 3. Crew tasks

`crew_tasks.json` gains the nine codes, each one section (`[1, 1]`):

| Code | Turns | Meaning, rule |
|---|---|---|
| PBA | `{ad: 2, eg: 3}` | Prepare bow anchor, 13.B.1 |
| PSA | `{sk_base: 6}` | Prepare stern anchor, 13.B.1 |
| PBS | `{sk_base: 5, times: 2}` | Prepare bow springs, 13.B.2 (CQ C → 8) |
| PSS | `{sk_base: 6, times: 2}` | Prepare stern springs, 13.B.2 (CQ C → 10) |
| A | `{fixed: 1}` | Anchor, 13.C.1 |
| AX | `{fixed: 1}` | Cut anchor cable, 13.F.2 |
| VO | `{fixed: 1}` | Veer out, 13.E.1 |
| VI | `{fixed: 1}` | Veer in, 13.E.2 |
| HS | `{fixed: 1}` | Handle springs, 13.D.3 (params `{"turn": "port"|"starboard"}`) |

`CombatTables.task_turns` reads the new `times` key: `times × max(1, sk_base + SK)` (9.A.2: recomputed from the
current crew quality every g-t). The validator accepts `{sk_base, times}`.

**Legality** (`AnchorRules.refusal`, pure; quoted rule in each reason). The ship's crew must be able to act.
- PBA / PSA: not anchored (**B (new)**: the next anchor is prepared after cutting; one anchor in the model at a
  time); no anchor ready (13.B.3: one end only, and "cannot plot PBA twice before first anchoring"); no live
  task preparing the other end; fewer than two anchorings used (13.A.5).
- PBS / PSS: springs not ready and not rigged; the matching anchor ready, or anchored by that end without
  springs (13.B.2 "before or after anchoring", 13.B.3 example "a ship that has completed PBA may plot PBS");
  no live task preparing the other end's springs.
- A: not anchored; an anchor ready; fewer than two anchorings; the scenario allows anchoring at the hex the
  anchor would drop in (§7); and no MPs plotted (13.C.1). While planning, A with a course plotted is kept with a
  warning; End Planning drops it, as it drops braces with no MA-0 turn (the same `ctx.final` pattern).
- AX: anchored.
- VO: anchored; wind speed > 0 (13.E.3); fewer than 3 VOs (13.E.1c); not fouled or grappled (**B (new)**: §5).
- VI: anchored; at least one VO (13.E.2).
- HS: anchored with springs; wind speed > 0 (13.E.3); not fouled or grappled (13.D.2); params turn port or
  starboard.
- Per plan: one section per code; HS excludes VO and VI (13.E.1d, 13.E.2); AX excludes HS, VO and VI
  (13.F.2); VO excludes VI. Sections are taken in section order; a later conflicting one is dropped with a
  warning.

**Ordering them.**
- *Manual crew*: `player_plot_crew` with assignments `{section: {"code": "PBA", "params": {}}}` (no new
  request). `CrewRules.normalize` makes them legal (new branch, the reasons above).
- *Automatic crew* (the default, and the AI): a new crew order `crew_orders.anchor`, one of `""`,
  `"prepare_bow"`, `"prepare_stern"`, `"prepare_springs"`, `"anchor"`, `"cut"`, `"veer_out"`, `"veer_in"`,
  `"turn_port"`, `"turn_starboard"`. New rule **A2c** in `CrewAuto.allocate` (after the boarding order, before
  the sail change) places one section in worker order for it when `AnchorRules.refusal` allows.
  `prepare_springs` means PBS or PSS for the end ready or anchored. Preparation in progress continues by rule
  A2 (tasks in progress), so the order is needed only to begin.
- **B (new): the anchor order lapses each g-t** (`clear_crew_plot` drops it; the boarding order alone stands).
  Every anchoring task is a one-off action or continues as a task in progress, so a standing order would only
  re-trigger actions by mistake (a second anchoring, a second VO).
- `plot_crew` refuses an unknown anchor order value ("Unknown anchor order %s").

**The handler.** `AnchorController` (`scripts/server/anchor_controller.gd`) extends `CrewTaskHandler` and is
registered for all nine codes, as `RepairController` is for RR/RH/RS.
- `prepare` (start of MOVEMENT_RESOLUTION): re-checks `AnchorRules.refusal` with `final` and the course the
  ship will actually sail (its stored course, or its default course when `movement_plotted` is false). An A
  plotted with MPs is refused here: "MPs plotted: the anchoring is erased (13.C.1)".
- `on_complete` (STATUS_ADJUSTMENT, `advance_tasks`): PBA → `anchor_ready = "bow"`; PSA → `"stern"`; PBS / PSS →
  `anchor.springs = true` when anchored by that end (13.B.2 "take effect as soon as their preparation is
  completed"), else `springs_ready = true`. The one-g-t codes do nothing on completion: their effects ran in
  the steps of §4 and §5, which find them as live tasks started this g-t (`started_turn == current_turn`).
- `cancel_reason`: the base reasons; PBA/PSA once anchored; PBS/PSS once there is no anchor of that end ready or
  dropped (a cut cable takes the springs with it).

### 4. The anchoring step (SoP V.A–B), DRIFT_CALCULATION

`AnchorController.resolve_anchoring(phase)`, called by `TurnPhaseController._enter_drift_calculation_phase`
right after `drift_resolver.resolve` (B, register). Two parts, in order.

**V.A, riding to the anchor.** For every ship on the map, not destroyed, anchored before this g-t
(`anchor.turn < current_turn`), leeward first (the drift order, 8.A.2, through a new public
`DriftResolver.leeward_first`), when the wind speed is above 0 (13.E.3: at WS 0 nothing moves; the 13.C.5
drift waits for the wind):
1. **Facing.** Normal anchoring: one 60° step toward the proper facing (13.C.4), in `swing_dir` if set, else
   the fewest-steps direction, the d6 when exactly opposite; `swing_dir` is kept until the proper facing is
   reached. A settled ship whose wind shifted turns the same way (13.C.6; the wind moves one hexside at a
   time, so one step always reaches it). Springs: the facing turns with the wind
   (`facing + (wind_direction − anchor.wind_dir)`, the shorter way) so the WF is kept (13.D.1).
2. **Cable.** `cable` 0 becomes 1 (13.C.5: exactly one hex to leeward the g-t after anchoring). A VO task started
   this g-t adds 1 (13.E.1b).
3. **Position.** The footprint of §1 for the new facing and cable. If it differs from the ship's hexes, the ship
   is moved there as one forced move (Diagram 25 B: turn and drift together), checked by
   `AnchorRules.forced_check`:
   - **clear**: the ship moves. If its bow enters a new shallow hex the depth is rolled (`game_state.dice`, d6,
     as for drift) and depth ≤ draft grounds it where it stood (13.G.2, no rigging lost).
   - **ship** (a new hex is held by another ship on the map): a fouling roll, as a blocked drift
     (`movement_resolver.roll_fouling(ship, blocker, true)`, unless either is already fouled, dismasted or a
     wreck), and the ship stays put (B, register).
   - **land**: the ship runs aground where it stands (`MapController.ground`, cause `anchor`; no rigging lost,
     13.G.2) and stays put.
   - **edge** (a new hex off the map): the ship stays put. **B (refined):** an anchored ship's forced move never
     takes it off the map, whatever the edge's kind: the cable holds it, and losing or "escaping" a ship to a
     wind shift it could not refuse would be a trap. (Drift's partial and edge rules are for free ships.)
   - A ship fouled or grappled to another stays put and logs the hold (**B (new)**: a linked group is held by its
     anchored member, §6; moving one member alone would break the link geometry).
   - **On a hold**: the facing is unchanged; a VO this g-t is lost; the 13.C.5 cable of 1 stands, so the ship
     tries again next g-t (the position no longer matches its anchor); a d6 swing direction already rolled is
     kept. **On success**: facing, hexes, `cable`, `veered`, `swing_dir` (0 once at the proper facing) and
     `wind_dir` are stored.
   - Event `ANCHOR_MOVE` when the ship moved or was held (§9). Nothing when the footprint is already right.

**V.B, dropping and cutting.** Then, by ship id:
- **Drop** (13.C.2): a ship with a live A task started this g-t drops its ready anchor in the anchored end's
  hex: `anchor = {hex, end: anchor_ready, springs: springs_ready, cable: 0, veered: 0, swing_dir: 0,
  wind_dir, turn}`; `anchor_ready = ""`, `springs_ready = false`, `anchorings_used + 1`, speed 0,
  `irons_entry_turn = −1` (5.D.7: dropping anchor ends irons). Normal drift was rolled first, so the ship may
  have drifted this g-t (13.C.1–2). Event `ANCHORED`.
- **Cut** (13.F.2): a ship with a live AX task started this g-t: `anchor = {}`, `cable_cut_turn = turn`. Event
  `CABLE_CUT`. It may plot movement next g-t.

Dice order, part V.A, per ship in leeward order: the swing d6 (only when opposite and no direction is set),
then either the fouling d10 (blocked by a ship) or the depth d6 (a clear move into shallows). V.B rolls nothing.

### 5. The springs step, start of MOVEMENT_RESOLUTION

`AnchorController.resolve_spring_step(phase)`, called by `_enter_movement_resolution_phase` after
`crew_task_controller.begin_turn_tasks` and before the resolver runs (U). It changes the board before any ship
moves, so every resolver pass (bear-off re-runs, rollbacks) and the combat step see the new hexes; under
proportional movement it lies before the first segment. For every anchored ship on the map, by ship id:
- **Spring turn** (13.D.2–3): a live HS task started this g-t turns the ship 60° to its `params.turn`. AB pivots
  on the bow (the stern swings); **AS pivots on the stern** (the bow swings). Refused, and logged, when the hex
  swung into is held by a ship, is land or is off the map (U: "held"; **B (refined)**: land and the board edge
  refuse it too, no collision and no grounding), or at WS 0, without springs, or fouled or grappled
  (`prepare` already refuses those; the step re-checks). A turn never rolls depth (as in movement, only a bow
  entering ahead rolls). Event `SPRING_TURN`.
- **Veer in** (13.E.2): a live VI task started this g-t moves the anchored end one hex upwind (`cable − 1`,
  `veered − 1`). Blocked by a ship, land or the edge: it does not happen, no collision (13.E.2). Event
  `VEER_IN`.

No dice. Ships are checked against the hexes as they stand when their turn comes (an earlier ship's spring
turn counts).

### 6. Drift and movement hooks

- `DriftResolver._holds_group(ship)` returns `ship.is_aground() or ship.is_anchored()`: an anchored ship, and
  any fouled or grappled group containing one, never rolls on the drift table (B, register). A ship dropping
  anchor this g-t is not anchored yet when drift runs, so it drifts normally (13.C.2).
- `MovementResolver._is_in_irons` is false for an anchored ship (5.D.4a) and in the g-t after the cut
  (`cable_cut_turn == current_turn − 1`, 5.D.4b, 13.F.3). That g-t a turn at MA 0 still takes the Tacking roll,
  without the +1 for irons (5.D.6). The next g-t at WF=L it is in irons again.
- Towing (sub-project 5) joins `resolve_anchoring` part V.B (tow cut, "Anchoring & Towing") and `_holds_group`.

### 7. Where ships may anchor (Scenario Book V.B; B, register)

Scenario key `anchoring` (`AnchorRules.permitted(scenario, hex)`):
- absent or `false`: nowhere (the book's default);
- `true`: anywhere on the board (Nile, Lissa);
- a zone: `{"rows": [first, last]}` (odd-r offset rows of `TerrainMap.axial_to_offset`, inclusive; the
  tournament map's "hexes xx01–xx15") and/or `{"areas": ["A", …]}` (named shallow areas of the terrain); a hex in
  either is allowed.
- No depth check. The hex tested is where the anchor would drop: the bow for a bow anchor, the stern for a
  stern anchor, at plotting time (`ctx`) and again in `prepare`. **B (new):** a ship that drifts out of the zone
  on the g-t it anchors still drops it (the cable went out where the anchorage was).
- `AnchorRules.scenario_errors` (reported by `GameState.placement_errors`): an `anchoring` value that is not a
  bool or a zone of the forms above, an unknown area name, a ship `anchor` with an unknown end or a cable outside
  1–4, a starting anchor hex off the map.

**A starting anchor**, per ship: `"anchor": {"end": "bow"|"stern", "springs": bool, "cable": 1-4,
"hex": [q, r]}` (all optional but `end`). Without `hex` the anchor lies `cable` hexes upwind of the anchored
end at the scenario's starting wind (the Nile rule: "in the hex ahead of the bow" for a ship facing the
wind). `AnchorController.place_scenario_anchors()` runs in `GameState.start_new_game` once the environment
exists: `anchor.turn = 0`, settled at the given cable (`veered = cable − 1`), counts as one anchoring. A
starting anchor is allowed whatever `anchoring` says (the scenario put her there). A normal anchor laid at
the wrong facing swings in the first drift step.

### 8. Gunnery (7.C.12c)

`GunneryCalculator.preview` adds the flat modifier `anchored` (+1, `tables.flat_modifier("anchored")`) when
the firer is anchored at the combat step. A ship dropping anchor this g-t is not yet anchored (V.B comes after
combat); a ship cutting this g-t still is. `PhaseEvents.MODIFIER_LABELS["anchored"] = "anchored"`.

### 9. Events and the combat log

New `PhaseEvents.Type` values, appended after `ARRIVAL_DELAYED`:

| Type | Data | Line |
|---|---|---|
| ANCHORED | end, springs, hex | "Ajax anchors by the bow at (3, 4)" / "… by the stern with springs at …" |
| ANCHOR_MOVE | causes (`swing`, `settle`, `veer_out`, `wind`), from_facing, to_facing, roll (−1 none), from, to, cable, blocked (`""`, `ship`, `land`, `edge`, `linked`), fouled (bool or null); target_id the blocker | "Ajax swings to her anchor and drops back on her cable to (2, 4)" / "Ajax cannot ride to her anchor: Brunswick is in the way (fouled)" |
| CABLE_CUT | hex (the anchor) | "Ajax cuts her cable" |
| SPRING_TURN | direction (`port`/`starboard`), pivot (`bow`/`stern`), from_facing, to_facing, refused (`""` or reason) | "Ajax hauls on her springs and turns to starboard" / "Ajax cannot haul round: Brunswick holds the hex" |
| VEER_IN | cable, refused | "Ajax veers in to 1 hex of cable" / "Ajax cannot veer in: …" |

CREW_TASK lines name the new codes (`CREW_TASK_NAMES` / `CREW_TASK_GERUNDS`). None of the new types counts
boxes, so `PlayerView.BOX_FIELDS` is unchanged.

### 10. PlayerView (B, register; refined)

The anchor (hex, end, cable, springs rigged), `anchorings_used` and `cable_cut_turn` are public: the counter
and the cable are on the board. **B (refined):** what a ship has *prepared* is hidden as well as its progress,
from every reader who does not command the ship (the same rule as a crew plot): `ship_for` drops
`anchor_ready` and `springs_ready` and removes PBA/PSA/PBS/PSS entries from `crew_tasks`; `events_for` drops
CREW_TASK events with those codes. With limited information off (`tournament`) everything shows, as today.
A readied anchor is a plan; the enemy learns of it when it drops.

### 11. Stub AI (B, register; refined)

All through the existing protocol: `assign_crew` sets `crew_orders.anchor` = `anchor_order(ship)`; plotting
of an anchored ship is skipped (`SHIP_ANCHORED` joins `LOCKED_ERROR_CODES`).

- **Anchored ship**, in this order:
  1. `"cut"` when its stored standing order is `cut` (CUT CABLES), or is a move order (`engage`, `close`,
     `follow`, `line`, `disengage`) and no enemy in play is within 15 hexes. **B (refined):** "a standing order
     says move" means a *signalled* order (`ShipState.standing_order` non-empty), not `GameState.order_of`'s
     default `engage`; otherwise every ship that starts anchored with no enemy in range would cut at once,
     against "starts-anchored ships stay".
  2. `"prepare_springs"` while springs are not rigged (and may be prepared).
  3. With springs: the haul. Of no turn, starboard and port (that order breaks ties), the first whose
     footprint (a legal spring turn, §5) gives the most batteries of one side bearing on its target (the
     ordered engage target, else the nearest enemy) within 15 hexes (`_bearing_batteries`); `"turn_<side>"`
     when that is a turn, else `""`.
- **Not anchored**, when anchoring is permitted at its drop hex and fewer than two anchorings are used, and
  either its standing order is `anchor` (ANCHOR signal) or it is in **drift danger**: `"prepare_bow"` while no
  anchor is ready or being prepared, then `"anchor"`. Its movement strategy is then `"anchor"`: hold (an empty
  plot carried to the deceleration minimum), so it slows to a stop and A is legal once speed allows a 0-MP plot
  (U: no waiver).
  - **Drift danger (B (new) definition):** the ship cannot make way (dismasted, or movement allowance 0 at its
    facing) and, shifting its footprint downwind one hex at a time up to `DRIFT_DANGER_HEXES` = 4 times, it
    meets land, a `none` boundary crossing or a shallow hex that grounds it `"always"`, before any `open` edge.
- `cut` as a strategy for a ship not anchored is `engage`.
- **Signals** (`SignalOrders.parse`): `ANCHOR` → `{"order": "anchor"}`; `CUT CABLES` / `CUT CABLE` →
  `{"order": "cut"}` (the last order wins, as today). Humans' ships get the standing order too (information
  only).

### 12. Developer UI and server authority

- `DevCommands.anchor_ship(ship_id, end := "bow", springs := false) -> String` and
  `DevCommands.cut_anchor_cable(ship_id) -> String` (server and debug builds only, like `grapple_ships`), through
  `AnchorController.drop_now` / `cut_now`. The Developer UI's per-ship controls get "Anchor" and "Cut cable"
  buttons beside "Start fire".
- `test_server_authority.gd` forbids, in view code: writes to `anchor`, `anchor_ready`, `springs_ready`,
  `anchorings_used`, `cable_cut_turn` (and `anchor[...] =`); calls to `drop_anchor`, `update_anchor`,
  `cut_cable`, `set_anchor_ready`, `set_springs_ready`; any `anchor_controller.` use.

### 13. View (U: view-only minimum)

- `AnchorMarkers` (`scripts/view/anchor_markers.gd`, like `GrappleLines`): a dark anchor marker at each anchor
  hex and a hemp cable from it to the anchored end; `GameController._sync_all_views` refreshes it.
- `PlanningSailUi.status_badge`: `"ANCHORED"` after `"AGROUND"`, before `"DISMASTED"`; block reason "Ship is
  anchored: cut the cable (AX) to get under way (13.C.3)."
- Crew overlay: `CrewRules.station_of` maps the nine codes to station `"anchor"`; `CrewRules.stations` adds a
  read-only "Anchor & cable" station (accepts `"none"`, note from `AnchorRules.status_text`) while the ship is
  anchored, has an anchor or springs ready, or a section is on an anchoring task; `deck_layouts.json` gives it a
  rect on the upper deck. Its `refusal` explains that anchoring is ordered through crew orders.
- Combat log: the §9 lines.

### 14. Determinism

- Drift step: `game_state.dice` only, leeward order, per ship the swing d6, then the fouling d10 or the depth
  d6. Spring step and V.B: no dice.
- Nothing anchoring-related draws from the resolver's `rng`, so movement re-runs are unaffected.

### 15. Builder's calls, collected

Register calls kept: springs full cost and the start-of-movement step (U); slow to a stop (U); all of 13.A–F
in scope; `anchoring` field without depth; `AnchorController` for the nine codes, effects right after drift;
anchored groups never drift; anchor public, preparation hidden; scenario `anchor`; AI behaviour; blocked forced
moves as a blocked drift.

New or refined (reasons in their sections): a starting anchor counts as one anchoring (§2); no new anchor
prepared while anchored (§3); the anchor order lapses each g-t (§3); edge and land in forced moves, linked
ships hold (§4, refined); spring turns also refused by land and the edge (§5, refined); a ship drifting out
of the zone on its anchoring g-t still anchors (§7); readiness hidden too (§10, refined); "says move" means a
signalled order (§11, refined); the drift-danger test (§11).
