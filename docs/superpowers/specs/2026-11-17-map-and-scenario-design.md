# Map and scenario: design

Date: 2026-11-17. Roadmap sub-project 3 of the sub-projects 3–7 run
(`2026-11-17-subprojects-3-7-decisions.md` §0 and §2, both binding). Status: draft written for the unattended
run. **U** marks the user's binding answers from the register; **B** the builder's calls, the register's or
new ones made here. A new or refined call is tagged **B (new)** or **B (refined)** with its reason beside it.
Research memo: `docs/superpowers/research/sp3.md`. Rules: `docs/rules/close_action.md` 13.G, 7.B.7–9, 2.B.1,
3.A, 8.A.1, 8.G.1f, Scenario Book III.B–C, V.D, VI.

## Intent

Leeward's battles are fought on an open square of water whose edges mean nothing: moves ahead may run off it,
drift stops at it, and there is no land, no shoal, no way out and no ship that arrives late. The Scenario Book
needs all four: coastal battles with land and shallows, edges with and without sea room, escape, and
reinforcements. This sub-project adds them as one general terrain model, so later work (ports, booms,
coastlines, anchoring zones) is more data, not more movement code.

## Goals

1. A true rectangular board (offset rows) whose four edges are typed `open`, `none` or `escape` (U).
2. One pure terrain model, `TerrainMap`, holding typed hexes (land, shallow areas) and a list of typed
   boundaries. The map edges are just the boundaries a rectangle generates. Movement, drift and the AI ask
   only "what does crossing from hex A to hex B mean" and "what is in this hex" (U, the user's note).
3. Running aground in movement (13.G.2, 6.E.3 rigging loss) and in drift (no rigging), with depth rolled per
   bow entry (U). An aground ship cannot plot, drift or fire its guns, and counts as lost by default (U).
4. Casting the lead as an explicit order (13.G.4, U).
5. Escape: a scenario permission per side, a declaration request, the D.1 conditions, D.4 reporting, and
   victory points that no longer treat out of play as lost (U).
6. Reinforcements that arrive on a given turn (2.B.1, 3.A, B).
7. Land blocks line of sight (7.B.7, B).
8. The stub AI plays all of it: it keeps off land and doubtful shoals, casts the lead, and escapes when its
   posture says so (register §0: the AI must play every feature).
9. View-only minimum (U): terrain tints with the depth range, edge markers, views for arriving ships, AGROUND,
   ESCAPED and ESCAPING badges, combat-log lines. No new input controls.

## Non-goals

- Sea room by re-centring (III.B). Open edges are walls (U).
- Scattering at set-up (Scenario Book V.C), variable reinforcement entry (Scenario 12), special victory
  conditions (VI.C) (U: "no special-victory vocabulary"; B: scattering and variable entry out of scope).
- Ports, booms, coastline art, a shallow-water shader, the minimap tint.
- Refloating (13.G.3: never).
- Anchoring (sub-project 4) and towing (sub-project 5). This design leaves the hooks they need (§11).
- New input controls. Escape and the lead are server requests; humans reach them only through scripts and
  tests until the UX pass (U).

## Design

### 1. The board: a rectangle in offset rows

`map_bounds: {width, height}` keeps its keys but now means a rectangle of `height` rows of `width` hexes, in
"odd-r" offset coordinates (pointy-top hexes, odd rows shifted half a hex east, which is what
`HexGrid.axial_to_world` already draws: world x = √3·(q + r/2)).

- Rows run `row_min = -height / 2` to `row_min + height - 1` (integer division, as today). Columns run
  `col_min = -width / 2` to `col_min + width - 1`.
- `col = q + (r - (r & 1)) / 2`, `row = r`. Row 0 is unchanged from today's q range, so every existing
  scenario (all ships near row 0 on a 100 × 100 board) stays on the map.
- A scenario with no `map_bounds` is unbounded and has no edges (the unit tests rely on this).
- Edge names: N is the row above `row_min` (world −Z is north), S below `row_max`, W left of `col_min`, E right
  of `col_max`. **B (new):** a side leaving a corner hex diagonally belongs to N or S (rows win), so every
  off-map side has exactly one edge.
- The water plane is already a centred rectangle (`HexMap._create_water_plane`); the hex tracking and grid
  overlay switch from the parallelogram to this rectangle (view task).

### 2. `TerrainMap`

A new pure class in `scripts/state/terrain_map.gd`, built from the scenario dictionary. It holds no game state
and never changes once built.

- **Hex types.**
  - `land`: a set of hexes.
  - Shallow areas: `{name, base, hexes}`. Depth in a shallow hex is `base + d6`, rolled each time it is needed
    (§4). `depth_range(hex)` is `(base + 1, base + 6)`. Deep water is every other hex on the map.
  - `grounds(hex, draft)` is `"never"` (deep water, or `base + 1 > draft`), `"maybe"`, or `"always"` (land, or
    `base + 6 <= draft`). The AI and the view use it; the rules use only the roll.
- **Boundaries.** A `Boundary` is `{name, kind, sides}`: `kind` is `open`, `none` or `escape`; `sides` is a set
  of hex sides, each the unordered pair of the two neighbouring hexes it separates (key: `Vector4i` with the
  smaller hex first). The rectangle generates four boundaries named `N`, `E`, `S`, `W` whose sides are every
  side between an on-map hex and an off-map neighbour. A scenario may add more boundaries by listing sides
  (`terrain.boundaries`); none of today's scenarios does, but the mechanism and its tests are in, so a
  coastline or a boom later is data. Ports and obstacles are not built (U).
- **Queries** (exact signatures in the plan, Task 1):
  - `in_bounds(hex)`, `is_land(hex)`, `area_at(hex)`, `depth_range(hex)`, `grounds(hex, draft)`.
  - `crossing(from, to) -> Boundary` (null when the side between two neighbours is in no boundary). This is
    the only question movement, drift and the AI ask about edges.
  - `boundary(name)`, `distance_to_boundary(hex, name)` (hexes to the nearest outside hex of that boundary,
    for the AI).
  - `errors` (validation messages), `rect_hexes(width, height)` (static, for the view).
- **Caching.** `TerrainMap.of(scenario)` caches the last map by dictionary reference (`is_same`). Tests and
  the game replace `GameState.active_scenario` wholesale and never mutate it in place (checked: no test
  does). In-place mutation after a query is unsupported and documented.
- `Occupancy.in_bounds(hex, scenario)` keeps its signature and delegates to `TerrainMap.of(scenario)`.

#### Scenario JSON

```json
"map_bounds": {"width": 40, "height": 30},
"terrain": {
  "edges": {"N": "open", "E": "none", "S": "open", "W": "escape"},
  "land": [[4, 12], [5, 12], [6, 12]],
  "shallow": [
    {"name": "A", "base": 15, "hexes": [[3, 10], [4, 10], [5, 10]]},
    {"name": "B", "base": 19, "hexes": [[8, 10], [9, 10]]}
  ],
  "boundaries": [
    {"name": "boom", "kind": "open", "sides": [[[0, 5], [1, 5]], [[0, 6], [1, 5]]]}
  ]
},
"escape": {"1": {"from_turn": 10, "edges": ["W"], "share": 0.5}},
"aground_counts_lost": true,
"ai": {"1": "escape"},
"ships": [
  {"id": "thames", "side": 0, "ship_type": "frigate_32", "position": {"q": -18, "r": 0}, "facing": 0,
   "sail_state": "PS", "crew_quality": "Trained", "crew_morale": 4, "arrives": 4}
]
```

- Hexes are `[q, r]` axial pairs, as ship positions are.
- `edges` defaults to `open` for every edge of a bounded map. Unknown edge names or kinds are errors.
- `escape` is keyed by side (string). `from_turn` defaults to 1, `edges` to every boundary of kind `escape`,
  `share` to 0.0 (the fraction of the ship's value her own side scores, VI.B.6; the Scenario Book uses 0.5,
  0.9, 1.0 and 1.25).
- `aground_counts_lost` defaults to true (U).
- `ai` gives an AI posture per side; the only value is `"escape"` (B, register).
- A ship's `arrives` (integer g-t, default 1) makes it a reinforcement when ≥ 2 (§7). Its `sail_state` is its
  entry sail state; absent, PS (3.A, register B).
- **Validation** (`TerrainMap.errors`, reported by `GameState.placement_errors`): unknown edge name or kind; a
  land or shallow hex off the map; a hex both land and shallow, or in two areas; a negative or non-integer
  `base`; a boundary side whose two hexes are not neighbours, or an unknown kind. `placement_errors` adds: a
  ship (or a reinforcement's entry footprint) on land or off the map. Reinforcements are left out of the
  overlap check, since their entry is checked when they arrive.

### 3. Edges in plotting and resolution

What a crossing means, everywhere (movement, drift, the AI):

| Boundary kind | Plotting (validator) | Forced across (resolver, drift) |
|---|---|---|
| none crossed | allowed | moves |
| `open` | refused | blocked: the step or drift is not made |
| `none` | refused (U) | the ship leaves the map and is lost, destroyed for victory (III.C) |
| `escape`, ship may cross | allowed | the ship leaves the map and escapes (V.D.1a) |
| `escape`, ship may not | refused | blocked, as `open` |

- "May cross" (`MapRules.may_cross`): the boundary is `escape`, it is in the ship's side's permitted
  `edges`, the turn is ≥ `from_turn`, and the ship has declared escape (§8). **B (new):** an undeclared or
  unpermitted ship treats an escape edge as a wall: the rules give escape edges only to permitted ships, and
  destroying an undeclared ship there would punish a forced move the player did not choose.
- The table is `MapRules.crossing_outcome(scenario, ship, from, to, turn)`: `clear`, `blocked`, `lost` or
  `escape`, with the boundary's name.
- A step crosses one side: an ahead step moves the bow from its hex to the hex ahead; a turn moves the stern
  from its old hex to its new one (5.C.2, the bow pivots). Drift moves both hexes one side each.
- **Validator** (`MovementValidator`): the forward option and both turn options are offered only if the
  crossing is allowed (this replaces `_stern_in_bounds`, and closes the Known Limitation "moves ahead are not
  limited to the map bounds"). A plot whose last step left the map offers no further moves (its deceleration
  shortfall is then 0, 5.E.9). Land and shallows are never refused (U).
- **Resolver**, per segment, before ship conflicts (§4 has the order):
  - A step across an `open` edge (or an escape edge the ship may not cross) is not made: the ship stops where
    it is, event `EDGE_BLOCKED`, logged as `STOPPED_SHORT` with cause `map_edge`. This catches the steps no
    plot contains: a bear-off or rollback amendment's steps ahead, a poor-maneuvering "one hex ahead".
  - A step across `none` or a crossable escape edge is made as usual (no ship can hold an off-map hex), then
    the ship stops, event `LEFT_MAP {edge, kind}`. `apply_results` then loses it (`none`) or escapes it
    (`escape`) through `MapController` (§9).
  - **B (new), immediate removal.** A ship that leaves the map is taken off it in `apply_results`, not at
    END_TURN. III.C says "immediately removed"; for an escape edge the ship is physically off the board, and
    leaving it half on the map to fire and be fired on until END_TURN would be odd. D.1a is then met by the
    crossing itself, and the END_TURN check handles D.1b–c only.
- **Drift** follows the same table (§6).

### 4. Running aground in movement (13.G.2)

Checked in `MovementResolver._resolve_impulse` for every ship that has a step on the segment, after the
segment's intended moves are known and before the hexes held and the conflict groups are built. Ships are
taken in the resolver's ship order, so the dice order is fixed.

1. **Edge** (§3). A blocked step ends here.
2. **Land.** A step whose entered hex (the new bow ahead, the new stern on a turn) is land runs aground
   (13.G.2b: bow or stern).
3. **Shallow.** An ahead step whose new bow is in a shallow area rolls the depth: `base + d6`, one die from the
   resolver's `rng` (U: the accepted Dice exception, like 6.D.3c, so re-runs repeat it). Depth ≤ draft runs
   aground (13.G.2a; the scan reads ≤). A turn never rolls: only the bow's entry counts, and a turn does not
   move the bow.
4. A ship that runs aground:
   - **B (new): stays in the hexes it held before the step.** 13.G.2 says the ship "stops and loses rigging just
     as if it had collided"; a colliding ship does not enter the hex (6.E.2), a hull cannot sit on land, and
     keeping the ship out of the hex means terrain never makes a hex conflict with another ship. The ship is
     aground where it stands.
   - Stops (`p.stopped`, `stopped_at_impulse`), its remaining steps dropped. Speed 0 next turn, as after a
     collision (5.E.3b).
   - Loses rigging as in a collision (6.E.3): d6−1 at FS, d6+1 at MS, 2d6 at PS, none under no sail, through
     `collision_rigging_loss` and the same `apply_results` damage path (rigging checks included). Its rigging
     dice follow its depth die.
   - Event `AGROUND {terrain: "land"|"shallow", hex, depth, draft, rigging_loss}`; `ShipResolutionResult.aground`.
5. Then the segment runs as today. An aground ship is a ship that does not move this segment: others that
   sail into its hexes meet the usual collision and bear-off rules.

Bear-off pauses, rollbacks and replays need nothing new: every pass starts from the same `rng` state, so a
depth die drawn before the paused or rolled-back segment is drawn again with the same value. Rolls from the
rolled-back segment on may differ, as for every other die (6.B.4).

**Consequences** (13.G.3, U):
- `ShipState.aground` is set by `MapController.ground` (and `aground_turn`). It never clears (13.G.3).
- Cannot plot: `DefaultCourse.can_plot` false, plotting refused with `SHIP_AGROUND`.
- Cannot fire its guns: `GunneryCalculator.preview` refuses "an aground ship cannot fire its guns (13.G.3)".
  Marine fire, boarding and being boarded, grappling, sail changes and repairs stay allowed. It can be fired
  on (it is still in play).
- Never drifts, and holds any fouled or grappled group it is in (8.A.1, 8.A.6).
- Victory: lost at 100 % and not able to move or fight, unless the scenario sets `aground_counts_lost: false`,
  when it scores as a damaged ship (§10). Either way it is not "able to move or fight".

### 5. Casting the lead (13.G.4)

- **Order** (U): `TurnPhaseController.player_set_cast_lead(player_id, ship_id, on) -> String`, with the course
  checks (`_course_request_error`: PLANNING, plan not submitted, the player commands the ship, it can plot).
  Stored in `plotted_actions["cast_lead"]`, so it lasts one turn and is hidden from other players with the rest
  of the plot (`PlayerView` drops `plotted_actions`).
- **≤ 2 MPs** (13.G.4a, scan): `plan_errors` refuses a plan in which a ship casts the lead with a course
  (stored or default) of more than 2 steps. The resolver also ignores the order for a plot of more than 2 steps,
  so an AI or default course can never cheat it.
- **In resolution**, for a casting ship's ahead step into land or a shallow hex (replacing §4 steps 2–3 for that
  step): the depth is rolled (none for land). Too shallow (depth ≤ draft, or land):
  - **Poor Maneuvering** (13.G.4b): one d10 on the PM table (`poor_maneuvering_number`). A failure means the
    ship does not turn: it sails on into the shoal and runs aground as §4, staying in the hexes it held
    (**B (new)**: a failed PM turn moves "one hex ahead", 6.F.3, so into the shoal; the depth already rolled
    decides).
  - Otherwise it **bears off** automatically, always successfully: no Bearing Off roll, no prompt, and it does
    not count as the 6.D.5 once-per-turn bear-off (**B (new)**: 13.G.4 is its own rule; a casting ship may
    meet two shoals).
  - **Deeper side** (B): of the turns legal at that point of the plot (as `bear_off_situation` finds them) whose
    new stern is not land, take the one whose new hex ahead grounds least (`grounds`: never < maybe < always;
    off the map or a blocked crossing worst), then the deeper area base (deep water counts deepest), then
    starboard. **B (new):** with no such turn the ship stops before the hex, not aground: it knows the depth.
  - The bear-off becomes a plot amendment exactly like a 6.D.4 bear-off (kind `"lead"`): the turn, then steps
    ahead to the deceleration minimum on the new heading, and the pass is re-run. The amendment's events (the
    sounding and any PM roll) are put back into the final log; several lead amendments for one ship are all
    kept (they are recorded in a list, not by ship).
  - Deep enough: the ship enters, no second roll.
- Event `LEAD_CAST {hex, depth (-1 land), draft, outcome: "bore_off"|"entered"|"held"|"pm_failed", side}`.

### 6. Drift (8.A)

- **Eligibility.** A group (a lone ship, or ships fouled or grappled together) with any aground member never
  drifts (8.A.1, 8.A.6). This is one hook, `DriftResolver._holds_group(ship)`, which anchoring will extend.
- **The forced move.** `MapRules.forced_move` (pure static) classifies a whole
  footprint shifting from its hexes to new ones: `edge` (an `open` crossing or an escape edge the ship may not
  cross), `lost` (`none`), `escape`, `land`, `ship` (the blocker), or `clear` (with whether the new bow is
  shallow). Priority as listed: an edge outranks land, land outranks a ship (as "map edge outranks ship"
  today). Drift uses it now; anchoring's swing, veer and reposition will use it later (sp4 §6).
- **Outcomes**, per group after the drift d10:
  - Any member `edge`: the group holds ("map edge", as today).
  - Any member `land`: the group holds, those members run aground (13.G.2b), no rigging lost (13.G.2).
  - Any member `ship`: as today (fouling roll for a lone ship, partial drift 8.A.5).
  - Otherwise: one d6 per member whose new bow is in a shallow area, in group order, through
    `game_state.dice` (U); any member with depth ≤ draft runs aground and the group holds. Else the group
    drifts; a member with a hex across `none` is lost, one across a crossable escape edge escapes (**B (new)**:
    the group shifts as one, 8.A.6; its other members drift on).
- **Partial drift** (8.A.5, a lone ship): the end that drifts is checked the same way; land or a too-shallow bow
  leaves the ship aground in place, an edge holds it.
- **Dice order:** the drift d10; then the fouling d10 (only when a ship blocks, as today); then the depth d6s.
- Logged: the DRIFT event (`blocked: "aground"` when terrain held it) and `AGROUND {cause: "drift", …}` with
  `rigging_loss` 0.

### 7. Reinforcements (2.B.1, 3.A)

- A ship with `arrives: n ≥ 2` is built at game start with `ShipState.awaiting_arrival = true` and
  `arrives_turn = n`, at its entry bow hex and facing.
- `is_on_map()` is false while it waits, so every map query skips it (`Occupancy`, wind, drift, the resolver,
  views).
- **B (refined): `is_out_of_play()` is true while it waits.** The register says "not out of play", meaning
  victory counts it as alive while the AI, signals and orders skip it. Making `is_out_of_play()` cover it gets
  the second half for free across the 58 call sites (plotting, fire, crew tasks, morale, signals, flagships,
  readiness), where an audit would miss one. The first half is kept explicitly in `VictoryController` (§10).
- **Placement** (`MapController.place_arrivals(turn, phase)`), at the very start of ENVIRONMENT, before the wind
  change takes effect (2.B.1), every waiting ship with `arrives_turn ≤ turn`, by ship id:
  - Entry footprint free (no ship on the map holds either hex): placed. `awaiting_arrival` false, `speed` =
    `arrival_speed(ship)`, event `ARRIVED {hex, facing, sail_state, speed}`.
  - Held: **B** it waits a turn (`arrives_turn = turn + 1`), event `ARRIVAL_DELAYED {}`, target the ship in the
    way. It tries again every turn.
- **Last speed** (3.A, the Penelope example): **B (refined)** the table MA at its entry sail state (capped by
  rigging, `movement_sail_state`), its wind facing and the wind speed in force before this turn's change; no
  blocked wind and no critical-hit losses (it was elsewhere). With the deceleration limit, it must use at least
  that less its deceleration (5.E.4).
- The default course, the AI, signals and crew orders pick the ship up from that turn's PLANNING. The view makes
  its ship view when it appears on the map.
- Variable entry rolls (Scenario 12) are out (feature_diff §2.2).

### 8. Escape (Scenario Book V.D)

- **Permission** (`MapRules.permission(scenario, side)`): the scenario's `escape` entry for the side, or none.
- **Declaration** (U): `TurnPhaseController.player_declare_escape(player_id, ship_id, on) -> String`, in
  PLANNING. Checks: server, game not over, PLANNING, a valid player whose plan is not in, the ship exists and the
  player commands it, the ship is in play and on the map; for `on`, the side may escape and the turn is ≥
  `from_turn`. Stored in `ShipState.escape_declared`.
- **B (new): the declaration stands until withdrawn** (`on = false`). D.2 asks for "escape" in the notes each
  plot phase; with no UI yet, a standing order is the same thing written once. D.4 is still reported every turn
  it is in force.
- **Hidden until the end of the turn** (D.4): `PlayerView.ship_for` drops `escape_declared` for a reader of
  another side (as it does `standing_order`). At END_TURN an `ESCAPE_DECLARED` event is logged for every ship
  in play with the declaration on. That event is the enemy's notice.
- **Escaping** (D.1), for a declared ship of a permitted side at or after `from_turn`:
  - a. off a permitted escape edge, in movement or drift (§3, §6): escapes at once.
  - b. at END_TURN, ≥ 31 hexes from every pursuer (`ESCAPE_DISTANCE`).
  - c. at END_TURN, 20–30 hexes from the nearest pursuer, its own `max_ma` > 0, and `max_ma` ≥ that of every
    pursuer 20–30 hexes off whose class number is ≤ its own (the same or larger class).
  - A ship that meets a condition must escape (D.2).
- **B (new), D.1 details.**
  - A pursuer is an enemy ship in play, on the map and not aground: a struck, captured or grounded ship cannot
    chase. No pursuer at all meets b.
  - Range is between the closest hexes of the two footprints (7.C.4 style).
  - `max_ma(ship, wind_facing, wind_speed)`: the table MA at the ship's maximum sail state and rigging level
    (`max_sail_state`, `rigging_level`), 0 at WS 0, WF L or dismasted; no blocked wind and no critical-hit
    losses. Pursuers are taken at the escaping ship's wind facing (the D.1c NOTE).
  - c needs the escaping ship's own `max_ma` > 0, so two becalmed ships do not "outrun" each other.
  - A fouled or grappled ship does not escape by b or c: it cannot get away.
- **Escaped** (`MapController.escape`): status `ESCAPED` (new, last in the enum, so old saves keep their
  numbers), crew tasks dropped, pending morale checks cleared, `remove_from_map` (partners freed), event
  `ESCAPED {how: "edge"|"distance"|"speed", edge | range}`. It is out of play and off the map, and not lost
  (§10).
- **END_TURN order:** remove destroyed ships (8.G.1f); `ESCAPE_DECLARED` for every declared ship in play; the
  D.1b–c check (`MapController.resolve_escapes`), by ship id against the positions at the start of the check;
  the victory check.
- **AI** (§12).

### 9. `MapController`

A new server controller, `scripts/server/map_controller.gd`, `GameState.map_controller`, created with the
others. All mutations go through `ShipStateController`; every method checks `is_server`.

- `place_arrivals(turn, phase)`, `arrival_speed(ship)` (query): §7.
- `ground(ship_id, data, phase)`: sets aground and logs `AGROUND`. Movement's `apply_results` and drift call it.
- `escape(ship_id, data, phase)`: §8.
- `lose_off_map(ship_id, edge, phase)`: `DamageController.destroy(ship_id, "no_sea_room", phase)` (status
  DESTROYED, partners freed, fires and tasks cleared; the DESTROYED line reads "leaves the map where there is
  no sea room and is lost"), then `remove_from_map`.
- `resolve_escapes(turn, phase)`: §8.
- `pursuers(ship)` (query).

`MapRules` (`scripts/server/map_rules.gd`, pure statics, like `FireRules`) holds the rules every caller shares:
`crossing_outcome` (what one hex step across a side means for this ship: clear, blocked, lost or escape; used
by the validator, the resolver, drift and the AI, so the §3 table lives in one place), `forced_move` (§6),
`permission`, `declare_error`, `may_declare`, `may_cross`, `share`, `max_ma`, `condition`, `footprint_range`.

### 10. Victory (Scenario Book VI)

`VictoryController` is rewritten around three questions per ship, and stops hard-coding sides 0 and 1
(register §0).

- `is_lost(ship)`: struck, destroyed or captured (VI.B.2–3), or aground while `aground_counts_lost`. An escaped
  ship, a waiting reinforcement and an aground ship with the flag off are not lost.
- `points_lost(ship)`: 0 for a waiting reinforcement; the full value when lost; otherwise the section shares
  as today. An escaped ship still yields its damaged sections (VI.B.6).
- `escape_points(ship)`: `share × value` for an escaped ship, to its own (original) side (VI.B.6); else 0.
- Sides are the distinct original sides of the ships (`_sides()`). **B (new):** a side scores the points lost
  by every ship whose original side is another side, plus its own escape points; with two sides that is today's
  rule. `points` is `{side: float}` for every side (the game-over panel reads 0 and 1). The winner is the side
  with the most points, −1 on a tie at the top.
- **Defeat** ("all struck", VI.A.1c): a side none of whose ships (by controlling side) is in play and not lost,
  or awaiting arrival. Escaped ships are left out of the count: a side whose ships have all struck or escaped is
  done. A side holding only prizes is defeated, as today.
- **Unable** (2.A.1): `can_move_or_fight` is true for a waiting reinforcement, false for an escaped or aground
  ship, otherwise as today.
- Reasons are unchanged: "agreement", "all struck", "no ship able to move or fight", "turn limit".

### 11. Line of sight (7.B.7–9)

Land hexes join the `occupied` dictionary that `GunneryCalculator` and `StubAI._score_position` pass to
`FireGeometry.battery_bears` / `has_line_of_sight`, so the existing spine (7.B.8) and vertex (7.B.9) rules apply
to land unchanged. Shallow water blocks nothing; land does not block wind (B, register).

### 12. Stub AI

- **Safe moves, every strategy.** `_move_in_bounds` becomes `_move_safe(ship, move)`: the move's crossings are
  allowed (§3) or cross an escape edge the ship may use; neither the new bow nor the new stern is land; the new
  bow `grounds` "never". `BOUNDED_STRATEGIES` goes: `_steer`, `_clear_move` and `_meet_deceleration_minimum`
  apply `_move_safe` for every strategy, engage included (register). When no safe move exists the existing
  fallbacks (the plain padding move) still apply.
- **The lead.** After a ship's course is built, if it has ≤ 2 steps and an ahead step's bow `grounds` "maybe"
  or "always", the AI calls `player_set_cast_lead(…, true)` (register B).
- **Escape posture.** A ship escapes when its side may declare this turn and either the scenario's `ai` entry
  for its side is `"escape"` or its standing order is `disengage` (register B). It then:
  - calls `player_declare_escape(…, true)` before plotting;
  - plots strategy `"escape"`: with permitted escape edges, the score is minus ten times
    `distance_to_boundary` to the nearest of them, and a move that leaves the map across one scores
    `ESCAPE_EXIT_SCORE` (10 000); with none, `_score_disengage` (open the range).
- It never withdraws a declaration.
- Aground and waiting ships are skipped as locked ships (`SHIP_AGROUND`, `SHIP_OFF_MAP` join
  `LOCKED_ERROR_CODES`).

### 13. Events and the combat log

New `PhaseEvents.Type` values (and `to_text` lines; edge names read north/east/south/west, other boundaries by
name):

| Type | Data | Line |
|---|---|---|
| AGROUND | cause (movement/drift), terrain, hex, depth, draft | "Lively runs aground on the shoal at (3, 10): 17 ft, draws 18 ft" / "drifts aground on land at …" |
| LEAD_CAST | hex, depth, draft, outcome, side | "Lively casts the lead: 16 ft at (3, 10), draws 18 ft, bears off to starboard" |
| ESCAPE_DECLARED | — | "Topaze is trying to escape" |
| ESCAPED | how, edge / range | "Topaze escapes off the west edge" / "… 31 hexes from the nearest enemy" / "… 24 hexes off, and no enemy can catch her" |
| ARRIVED | hex, facing, sail_state, speed | "Thames arrives at (-18, 0) under plain sail" |
| ARRIVAL_DELAYED | (target: the ship in the way) | "Thames cannot enter: Lively holds her entry hex; she will try next turn" |

- `STOPPED_SHORT` gains cause `map_edge` ("stops at the edge of the map"); `DESTROYED` with reason
  `no_sea_room` reads "leaves the map where there is no sea room and is lost"; `DRIFT` with `blocked:
  "aground"` reads "drifts aground". `log_outcomes` logs `LEAD_CAST` and the `map_edge` stop;
  `MapController.ground` logs `AGROUND`.
- None of the new types counts boxes (the rigging lost aground shows as the DAMAGE events that follow), so
  `PlayerView.BOX_FIELDS` is unchanged. Movement events (`EDGE_BLOCKED`, `LEFT_MAP`, `AGROUND`,
  `LEAD_SOUNDING`) are new `ResolutionEventType`s; playback ignores non-MOVE events as today.

### 14. PlayerView

- `ship_for` drops `escape_declared` for a reader of another side.
- The lead order is inside `plotted_actions`, already dropped for any ship the reader does not command.
- `aground`, `awaiting_arrival`, `arrives_turn` and status `ESCAPED` are public (the board shows them; a
  scenario's order of battle is public).

### 15. View (U: view-only minimum)

- `HexMap` tracks and draws the rectangle (`TerrainMap.rect_hexes`).
- `HexOverlay.show_terrain(terrain, hex_grid)`: land hexes tinted sand, shallow hexes tinted pale green, one
  `Label3D` per shallow area ("A 16–21 ft") on the area hex nearest its centre; strips along the sides of
  `escape` boundaries (green) and `none` boundaries (red). Called on `game_started`.
- `GameController._sync_all_views` spawns a ShipView for every ship on the map that has none (arrivals).
- `ShipView` plays no explosion for a ship destroyed off the map (lost to a `none` edge).
- Badges: `PlanningSailUi.status_badge` gains "ESCAPED" (after DESTROYED) and "AGROUND" (after PRIZE, before
  DISMASTED), with their `movement_block_reason` texts; a new `escape_badge` ("ESCAPING", own declared ships)
  joins `card_badge`.
- The combat-log lines are the `to_text` lines (§13).

### 16. Determinism

- Movement depth dice and lead PM dice: the resolver's `rng`, in segment order, then resolver ship order
  within a segment, each ship's depth die before its rigging dice. A bear-off re-run or a rollback replays the
  prefix exactly.
- Drift depth dice: `game_state.dice`, after the drift d10 and any fouling d10, in group order.
- Arrivals, escapes and victory: no dice; ships by id.

### 17. Hooks for later sub-projects

- Anchoring (sp4 §6): `TerrainMap` areas are named (an anchoring zone can name one); `MapRules.forced_move` is the
  shared block / edge / aground test for swings, veering and repositioning; `DriftResolver._holds_group` is where
  an anchored ship joins aground in holding a group.
- Towing (sp5 §6): `MapController.escape` takes any ship, so a towed ship can escape with its tower; drift
  groups already hold an aground member.

### 18. Builder's calls, collected

Register calls kept as written: rectangle and typed edges, `TerrainMap` with typed boundaries, depth per entry
from the resolver RNG, no plot refusal into hazards, aground lost by default, the lead order and deeper-side
bear-off, reinforcements, land blocks LOS, AI escape posture, scattering out.

New or refined here (each with its reason in its section): rows win at corners (§1); an escape edge is a wall
for a ship that may not cross it (§3); immediate removal off the map (§3); an aground ship stays in its hexes
before the step (§4); lead details: PM failure grounds, no 6.D.5 count, no-turn holds, recorded as a list (§5);
drift priorities and group members lost or escaping (§6); waiting reinforcements are out of play (§7); arrival
speed from the table only (§7); standing escape declaration (§8); D.1 pursuers, range, `max_ma` and the linked-
ship and own-MA rules (§8); N-side scoring (§10).
