# Sub-project 3 — Map and scenario: decision inputs

## 1. Rules summary

**Reinforcements (2.B.1, 3.A.1, Scenario Book VII "Start"/"Reinforcements").**
- Placed at the very start of the g-t (Phase 1, before the wind change takes effect) on the listed entry hex (the **bow** hex) and direction. OB code `A1635:3²` = map A, hex 1635, facing 3, arrives g-t 2. No superscript = on the map at the start.
- Reinforcements enter at **PS** unless the scenario says otherwise. They are assumed to have moved **straight ahead at their maximum PS speed on the previous g-t**, so the deceleration limit applies. Example: Penelope at WF=B, WS=3 "used 10 MPs" on g-t 1, so on g-t 2 she must use at least 7.
- Nothing covers an occupied entry hex.
- Variable entry exists in Scenario 12: from g-t 2, roll 2d6 each g-t; if the roll is < the g-t, Caesar enters 10 g-t's later. That is scenario-specific.

**Map edges and sea room (Scenario Book III.B–C).**
- By default there is sea room in every direction. Ships may move off any edge, and players re-centre all ships. Re-centring may not push a ship off the board, and is not used until all reinforcements are in.
- **No sea room** on an edge: a ship whose bow **or** stern moves off that edge is removed and **counts as destroyed** for victory. A ship that **drifts** off is destroyed too. A half-hex counts as off the map.
- **Escape edges:** removed, **not** destroyed (V.D).

**Escape (Scenario Book V.D, 8.G.1f, 2.B.5g).**
- Only ships the scenario permits may escape. Some scenarios allow it only from a given g-t or after a trigger (e.g. "after g-t 25"; "after destroying 2 enemy sections or g-t 20").
- Procedure (D.2): write "escape" in the notes during the Plot Phase. At the **end of that g-t**, a ship that meets any D.1 condition is removed, and it *must* escape even if it no longer wants to.
- Conditions (D.1, checked on scan p.51; the OCR "= 31" is **≥ 31**):
  - a. moved off a specified map edge;
  - b. **≥ 31 hexes** from the nearest enemy;
  - c. 20–30 hexes from the nearest enemy, and its maximum MA in its current WF (at maximum sail state) is ≥ that of every enemy 20–30 hexes away of the **same or larger class**. "Larger class" means a lower class number: a class 3 ship cannot stop a class 1 or 2 ship. Enemies are assumed to be in the same WF and at maximum sail state.
- D.4: a ship attempting escape must tell the enemy at the end of every g-t in which it tries.
- Removal comes in Reconciliation (8.G.1f, after morale checks and signals).
- VPs (D.3, VI.B.6): an escaped ship is not destroyed. The enemy still scores its damaged sections, and some scenarios give the escaping side a share of the ship's value (seen: 50 %, 90 %, 100 %, 125 %).
- VI.A.1c: the scenario ends when every ship of a side has struck, "except those that have escaped".
- Special victory conditions (VI.C) are scenario-specific: e.g. "any French ship escapes", "exit off Board Edge 1".

**Shallow water and land (13.G; checked on scan p.39).**
- 13.G.1: draft is in feet, from the SDC "D" column. `ships.json` drafts 18 (38), 16 (32) and 22 (74) match the SDC.
- 13.G.2: a ship runs aground if (a) its **bow** enters a hex whose depth is **≤ its draft** (the OCR reads "<"; the scan says ≤), or (b) its **bow or stern** enters a **land** hex. It stops and loses rigging "just as if it had collided" (6.E.3: d6−1 at FS, d6+1 at MS, 2d6 at PS, with rigging checks). A ship that **drifts** aground loses no rigging.
- 13.G.3: an aground ship cannot fire its guns. It can still use marine fire and board. It "may be considered destroyed (see scenario special rules)". Its counter stays on the board, and nothing ever refloats it.
- 8.A.1: aground ships do not drift.
- Depth in the scenarios is a random range, rolled anew each time a ship's bow enters a shaded hex: "area A 21+d6", "18+d6", "15+d6", "23+d6", "20+d6", "17+d6", "14+d6". So a frigate drawing 16 grounds in a 15+d6 hex only on a 1, and a 74 drawing 22 grounds on a 1–6.
- **13.G.4 Casting the lead:**
  - a. The ship plots **≤ 2 MPs** (scan; OCR "<2") and notes "cast".
  - b. Depth is determined just before each hex is entered. If it is too shallow, the ship **automatically bears off** instead of moving forward. This always succeeds unless the ship is Poor Maneuvering, which uses the PM table.
  - The garbled line after 13.G.4 in the OCR is the decorative rule bar; nothing is missing.

**LOS (7.B.7–9).**
- LOS is blocked by a **land** hex (shallow water does not block it), by a hex spine only if both hexes beside it block (7.B.8), and at a vertex only if the line actually enters a blocking hex (7.B.9).

**Scattering (Scenario Book V.C.1–2):** the OCR drops it. It is a d6 set-up displacement by diagram with CQ, class and speed DRMs. It is scenario set-up, not in the roadmap rows, and noted only for completeness.

## 2. Current code

- **Scenario load:**
  - `DataManager.load_scenario` (data_manager.gd:329) checks only `seed` and ship names.
  - `GameState.start_scenario` (game_state.gd:188) builds every ship up front via `_scenario_ship`/`add_ship`, then `_build_players` and `start_new_game`.
  - `placement_errors` (:452) checks overlap and `Occupancy.in_bounds`.
  - There is no terrain, arrival turn, edge type or escape permission. `Ship.draft` is loaded (ship.gd:26) and never read.
- **Bounds:**
  - `Occupancy.in_bounds` (occupancy.gd:47) is a **q/r range**. The map is a 60°-slanted **parallelogram** in world space (`HexGrid.axial_to_world`: x depends on r; `HexMap._initialize_hex_tracking` builds the same shape).
  - Every test scenario is 100×100. With no `map_bounds`, everything is in bounds.
- **Movement:**
  - `MovementValidator._stern_in_bounds` (movement_validator.gd:417) refuses a turn whose stern leaves the map.
  - Moves ahead are unchecked (Known Limitation).
  - `MovementResolver` (2130 lines) has no edge, terrain or ground handling. It has the machinery grounding would reuse:
    - collision stop: `_apply_collision`, `collision_rigging_loss` (:1297, :1384);
    - bear-off pauses and re-runs: `_potential_collision`, `_resolve_collision_or_bearoff`, `bear_off_situation`, `_bear_off_decisions`;
    - PM rolls: `_roll_poor_maneuvering`;
    - deterministic re-runs from the same RNG start.
- **Drift:** `DriftResolver._in_bounds` / "map edge" block (drift_resolver.gd:242–293). A map edge simply blocks; it never destroys the ship. No aground exclusion.
- **LOS:** `FireGeometry.has_line_of_sight(from, to, occupied, blocking)` (fire_geometry.gd:194) already implements spine/vertex blocking against `occupied` ∪ `blocking` dicts. Land is one more dict. Callers: `battery_bears`, `GunneryCalculator.preview`, `StubAI._score_position`.
- **Removal:** `ShipStateController.remove_from_map` (ship_state_controller.gd:431) frees partners. Its docstring requires escaped ships to stay `is_out_of_play()`. `ShipState.removed_from_map` / `is_on_map()`. `TurnPhaseController._enter_end_turn_phase` (:1397) removes destroyed ships before the victory check. `GameState.ships_on_map()` is used by occupancy, drift, wind, gunnery, views and the minimap.
- **Victory:**
  - `VictoryController` (victory_controller.gd): `points_lost` gives 100 % for any `is_out_of_play()` ship, so an escaped ship would wrongly score as lost.
  - `_is_defeated` / `_is_unable` / `can_move_or_fight` would count unarrived reinforcements and escaped ships as out of play.
  - Two sides (0/1) are hard-coded.
  - There are no special victory conditions or escape VPs.
- **AI:** `StubAI.BOUNDED_STRATEGIES` (stub_ai.gd:36) and `_move_in_bounds` (:918) keep close/follow/line/disengage on the map; engage is unbounded. There is no terrain avoidance, escape strategy or lead casting. `disengage` exists (an `_score_disengage` signal order).
- **View:**
  - `HexMap` has no per-hex terrain mesh (tracking only, one water plane).
  - `HexOverlay` can tint hex sets (`show_blocked_hexes`, `_add_hex_mesh`).
  - The minimap reads `map_bounds`.
  - `GameController._on_game_started` makes ship views once; `_sync_all_views` drops removed ships, but nothing adds views mid-game (needed for reinforcements).

## 3. Work breakdown

| # | Component | Files | Size |
|---|---|---|---|
| A | Terrain model: scenario `terrain` parsed into a pure `TerrainMap` (land set, shallow areas {base, die}, edge types); queries `is_land`, `depth_range`, `is_shallow`; validation in `placement_errors` | new `scripts/server/terrain_map.gd` (or `scripts/state/`), game_state.gd, data_manager.gd | S–M |
| B | Map edges: per-edge type (open / none / escape); bounds shape fix if chosen (Q6); validator and resolver handle a bow or stern leaving the map → destroyed or escaped; drift off a "none" edge destroys | occupancy.gd, movement_validator.gd, movement_resolver.gd, drift_resolver.gd | M |
| C | Escape: `player_declare_escape(player_id, ship_id, on)` request (PLANNING, ownership); scenario permission/turn gate; end-of-g-t check of D.1 a–c; new status `ESCAPED` (out of play, off the map); ESCAPED event; D.4 public flag in `PlayerView`; VP rules (damage only, plus scenario escape share); victory end rule VI.A.1c | turn_phase_controller.gd, ship_state.gd, ship_state_controller.gd, victory_controller.gd, player_view.gd, phase_events.gd | M |
| D | Reinforcements: per-ship `arrives` (turn, optionally sail state); ship exists but is not yet on the map; placed at ENVIRONMENT start with last speed = MA at PS; blocked entry handling; victory, AI and default course must ignore unarrived ships; view creates ship views on arrival | game_state.gd, turn_phase_controller.gd, ship_state.gd, victory_controller.gd, default_course.gd, game_controller.gd | M |
| E | Grounding in movement: bow into a shallow hex → depth roll from the resolver RNG (repeats on re-runs); bow or stern into land; stop + 6.E.3 rigging loss + checks; AGROUND status/event; interaction with stern swings, overlap rollback and bear-off pauses | movement_resolver.gd, movement_types.gd, phase_events.gd | L |
| F | Casting the lead: plot flag (course option, ≤ 2 MPs enforced in the validator and `plan_errors`); automatic bear-off through the 6.D path, PM roll when Poor Maneuvering | movement_validator.gd, movement_resolver.gd, turn_phase_controller.gd (`player_set_cast_lead`) | M |
| G | Aground consequences: no guns (`FireRules`), no plotting (`SHIP_AGROUND`), no drift (and group drift held), marines and boarding allowed; `can_move_or_fight` false; VP per Q4 | fire_rules.gd, movement_plotting_*, drift_resolver.gd, victory_controller.gd, crew_rules (sail changes?) | S–M |
| H | Drift aground (into shallow by depth roll, or land), no rigging loss | drift_resolver.gd | S |
| I | Land blocks LOS: pass land into `has_line_of_sight` blocking; preview/AI callers | fire_geometry.gd, gunnery_calculator.gd, stub_ai.gd | S |
| J | Stub AI: treat land and possibly-too-shallow hexes as `avoid` in `_steer` (by draft vs max/min depth); cast the lead when the course touches shallow; escape strategy + declaration (Q7); off-map exit only via escape edges | stub_ai.gd | M–L |
| K | View (if in scope, Q5): land/shallow hex tint + minimap; edge markers; escape toggle on the ship card; AGROUND/ESCAPING badges; combat-log lines; views for reinforcements | hex_overlay.gd, minimap.gd, planning UI, game_controller.gd | M |
| L | Test scenarios (one coastal with land/shallow/escape edge, one with reinforcements), scenario-creator skill schema, feature_diff rows 59–61 → §3/§4, CLAUDE.md Known Limitations, tests | data/scenarios, .claude/skills/scenario-creator/SKILL.md, docs | S–M |

## 4. Decisions needing the user (ordered by importance)

**Q1. What is the edge of the map?**
The rules give infinite sea room, with players re-centring the ships, unless an edge is declared "no sea room" (leaving = destroyed) or an escape edge. Leeward has a finite 100×100 board where moves ahead may run off.
- (a) **Per-edge types** `open` / `none` / `escape`. "open" is a wall: plotting a bow or stern off it is refused, and drift is blocked as now. "none" = destroyed on leaving (per the rules); "escape" = escaped. Cheap and predictable, and it closes the Known Limitation. Costs a little fidelity: a wall is not sea room, but a 100-hex board is effectively infinite.
- (b) Faithful sea room: a truly unbounded map (no bounds, camera and minimap follow the fleet), with "none" and "escape" edges only in scenarios that declare them. Most faithful, but more view work and an open-ended minimap.
- (c) Auto re-centring like the board game. Pointless on a computer.
- **Recommend (a).** Also: is a "none" edge (ship destroyed) acceptable as a hard rule, or should plotting off it be refused too, so only bear-off, collision or drift can push a ship off? I'd refuse plotting it and keep "destroyed" for forced moves and drift, per the rules.

**Q2. Depth: random per entry, or charted?**
The rules re-roll each shallow hex's depth (base+d6) every time a bow enters, and casting the lead is the safety valve.
- (a) **Faithful.** The map shows each area's range (e.g. "15–20 ft"); a hex is certainly safe if min > draft and certainly aground if max ≤ draft; in between is a gamble. The lead removes the gamble at ≤ 2 MPs. Adds tension, keeps 13.G.4 meaningful.
- (b) Fixed depth per hex, shown: grounding is never a surprise, so the lead is dropped (deliberate change) and the validator can refuse plots into too-shallow hexes. Simplest, but terrain becomes plain walls.
- (c) Fixed depth, hidden until sounded. Fog that limited information does not cover elsewhere; more UI.
- **Recommend (a).** It is the rule, it is cheap on a computer, and it gives the lead a purpose.

**Q3. Should the server refuse plotting into land (and into certain grounding)?**
- (a) **Refuse plots** whose bow or stern would enter land or a hex whose max depth ≤ draft, as the stern-off-map check does now. Grounding then comes only from bad luck, bear-off, collision, PM or drift. Friendlier, and the AI gets it free.
- (b) Allow everything (faithful: grounding is the player's mistake).
- **Recommend (a)** as a recorded deliberate change.

**Q4. What does running aground mean for victory?**
13.G.3 leaves it to the scenario.
- (a) **Default: aground = lost for VPs (100 %, like struck)** and out of "able to move or fight". The ship stays on the board, can use marine fire, board and be boarded, and can be fired on. A scenario flag `aground_counts_destroyed: false` turns it off.
- (b) Default not destroyed: VPs only for damaged sections, so a grounded ship is a cheap way to deny VPs.
- (c) Destroyed and removed like an explosion. Simplest, but loses the boarding and marine play.
- **Recommend (a).** It is historical ("total losses") and stops grounding from being a VP exploit.

**Q5. Is UI in scope this time?**
Terrain and escape cannot be played by a human without seeing them.
- (a) Back end only, as in SP2. Testable by AI and scripted players; terrain shows only in the Developer UI.
- (b) **Minimal view:** flat land/shallow hex tints with the depth range, minimap tint, escape-edge markers, an escape toggle and a cast-lead toggle on the ship card, AGROUND/ESCAPING badges, log lines, views for arriving reinforcements. No coastline art.
- (c) Full terrain art (shore meshes, shallow-water shader).
- **Recommend (b).** Reinforcement views are needed regardless, or arriving ships are invisible.

**Q6. Board shape and how scenarios name edges.**
`map_bounds` width/height is a q/r range, which in world space is a 60° parallelogram. Its "edges" are two horizontal rows and two slanted sides.
- (a) **Switch to a true rectangle** (offset rows: "odd-r"), with edges named N/S/E/W. Escape edges and terrain then read naturally. The view (`HexMap`, minimap, water plane) changes with it; existing scenarios keep their axial ship positions.
- (b) Keep the parallelogram and name the edges q_min/q_max/r_min/r_max.
- **Recommend (a).** It is cheap now and messy after terrain scenarios exist.

**Q7. How should the AI handle escape, and how much is in scope?**
- (a) **Escape only when the scenario permits it for that side and the side's posture says so.** The posture is a scenario `ai` hint per side (`"escape"`) or a DISENGAGE signal while escape is permitted. Then: declare escape every g-t, run for the escape edge (or open the range), and avoid terrain.
- (b) Heuristic: escape when losing on points or badly damaged.
- (c) AI never escapes. This breaks "AI must play every feature".
- **Recommend (a)**, and (b) later if wanted.

**Q8. How far should scenario victory go?**
Escape only matters if scoring rewards it.
- (a) **Escape VP share per side** (`escape_vp_share: {"1": 0.9}`) plus an optional escape window (`escape: {"sides": [1], "from_turn": 20, "edges": ["W"]}`). Standard VPs otherwise. Small.
- (b) (a) plus a small special-victory vocabulary: "side wins if N ships escape", "wins if enemy ship X strikes before g-t T". Medium.
- (c) A general SVC engine. Large; the Scenario Book is a roadmap non-goal.
- **Recommend (a).** (b) only if the user wants historical-style scenarios soon.

**Q9. Is casting the lead worth a separate order?**
Only applies if Q2 = (a).
- (a) **Faithful:** a per-ship "cast the lead" toggle; the ≤ 2 MP limit is enforced; automatic bear-off.
- (b) Implicit: any ship plotting ≤ 2 MPs is assumed to be sounding. One less control, slightly generous.
- **Recommend (b)** for playability (record it in §4). Slow movement near shoals is exactly when you would sound.

## 5. Decisions the builder can make alone

- **Terrain JSON:** `"terrain": {"land": [[q,r],…], "shallow": [{"name": "A", "base": 21, "die": "d6", "hexes": [...]}], "edges": {"N": "open", …}}`, with hex lists. An ASCII-row form can come later. Validation: no ship starts on land, shallow areas don't overlap land.
- **Where a grounding ship stops:**
  - Shallow (rule a): the bow is in the hex it entered, aground there.
  - Land (rule b): it stays at its last legal position, like a collision stop, since a hull cannot sit on land.
  - It is stopped (speed 0) and its plot is cut, as in 6.E.2.
- Depth rolls come from the resolver's `rng`, like the 6.D.3c order roll, so re-runs repeat them (accepted Dice exception). Drift depth rolls go through `game_state.dice`.
- **Grounding vs collision in the same segment:** settle land and depth first (terrain is static), then ship conflicts.
- **Aground:** new `ShipState.aground` bool plus `aground_turn`, rather than a status, so struck/captured still work. Plot refusal code `SHIP_AGROUND`; sail changes and repairs are still allowed. A fouled or grappled group holding an aground ship never drifts. The 6.E.3 loss and 7.D rigging checks go through the existing `DamageController` path.
- **Casting the lead's bear-off direction:** toward the deeper side (no prompt), or the owner's bear-off prompt if Q9 = (a) and a human commands the ship. A PM ship rolls the PM table.
- **Escape:** status `ESCAPED` via `remove_from_map`; `is_out_of_play()` true. In `VictoryController`, out of play no longer means 100 % lost: ESCAPED scores sections only (VI.B.4–6), plus the scenario share to its own side.
  - Victory "all struck" ignores escaped ships (VI.A.1c). A side whose only remaining ships escaped ends the game.
  - The D.1c relative-speed test uses each ship's own `speed_type` and rigging level at its max sail state, in the escaping ship's WF, with blocked wind ignored.
- **Escape timing:** checked at END_TURN right after the 8.G.1f destroyed-ship removal and before the victory check. The declaration is reset each PLANNING. PlayerView shows the declaration to the enemy only after END_TURN (D.4), via an ESCAPE_DECLARED event.
- **Leaving the map:** a ship whose bow or stern crosses a "none" edge in movement is DESTROYED (removed at END_TURN); crossing an "escape" edge counts as D.1a only for a ship that declared escape (D.2). An undeclared ship is refused at plot time; if forced across (bear-off, drift), it is treated as crossing an "open" edge (blocked) rather than destroyed.
- **Reinforcements:**
  - The ship is created at start with `arrives_turn > 1`; a new state such as `ShipState.arrival_turn` keeps it off the map (`is_on_map()` false) and *not* out of play.
  - Victory, defeat and "unable" checks treat unarrived ships as alive. AI, signals and orders skip them.
  - Placed at the start of ENVIRONMENT, before the wind applies, at PS (or the scenario value), last speed = MA at PS in the current WF/WS.
  - An occupied entry hex holds the ship one more g-t (logged).
  - Fixed turns only; variable entry rolls (Scenario 12) are left out and noted in feature_diff.
- Land does not block wind (5.G covers ships only).
- `ScenarioBook` scattering: out of scope; noted in feature_diff §2.
- The AI's `_move_in_bounds` is extended to "in bounds, not land, not certainly shallow" for **all** strategies, engage included.

## 6. Cross-sub-project dependencies and risks

- **SP4 Anchoring** depends on this: scenarios at anchor are coastal (Nile), veering is a drift and must ground, and 8.A.1 "not aground" sits next to "anchored". Put aground in the drift eligibility in a way anchoring can extend.
- **SP5 Towing:** a tow group drifting or moving into shallow water. 8.A.6 group logic must already hold an aground member.
- **SP7 Impulse movement (14.A):** grounding and the lead must work per impulse. Keep the grounding check per segment step, not per plot.
- **SP2 players:**
  - New requests (`player_declare_escape`, `player_set_cast_lead`) take a `player_id` and use `GameState.commands`.
  - DISENGAGE signal ↔ AI escape.
  - PlayerView must hide the escape declaration until the end of the g-t; new box-counting events need no `BOX_FIELDS` entry.
  - `VictoryController` is still hard-coded to sides 0/1 (`_points_scored(1 - player_id)`). Escape VPs make that worse; fix it to iterate sides while touching it.
- **Risks:**
  1. `MovementResolver` complexity: grounding mid-move interacts with overlap rollback, stern contests, bear-off pauses and replays, and needs deterministic depth rolls. This is the L item; test it heavily with `ScriptedDice` and a fixed RNG.
  2. Q6 changes how bounds are computed everywhere `in_bounds` is used, plus the minimap and water plane.
  3. The greedy AI climb can get trapped in bays or against land ("stalls" is already a Known Limitation).
  4. History snapshots (`ship_history[ship][turn]`) for ships not yet arrived.
  5. `remove_from_map`'s contract (out of play) must hold for ESCAPED, while VP scoring must stop equating out of play with lost.
