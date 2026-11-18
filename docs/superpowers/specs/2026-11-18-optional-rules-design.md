# Optional rules (14.B, 14.D, 14.E): design

Date: 2026-11-18. Roadmap sub-project 7, the rest of it, in the sub-projects 3–7 run
(`2026-11-17-subprojects-3-7-decisions.md` §0 and §6, both binding). Status: draft written for the unattended
run. **U** marks the user's binding answers from the register; **B** the builder's calls, the register's or new
ones made here. A new or refined call is tagged **B (new)** or **B (refined)**, with its reason beside it.
Research memo: `docs/superpowers/research/sp7.md` (written before sub-projects 3–6 landed; every code fact used
here was re-checked at `b486d9c`, after ships and guns). Rules: `docs/rules/close_action.md` 14.B.1–4, 14.D.1–3,
14.E.1–4, 9.B.2 / 9.C (striking), 7.C (gunfire modifiers); numbers checked against the scan (pdf pp. 39–40, Rules
Book pp. 36–37) in the memo: 14.B.2 "CQ=F (or G), or … at least five sections"; 14.D.2 "after the fifth time",
14.D.3 "every tenth g-t after the first fatigue … 15, 25, 35"; 14.E.3 / 14.E.4 "d6 … 4+ must fire high".

14.A is closed (replaced by proportional movement, register §1) and 14.C is done (`PlayerView`). After this
sub-project every rule of chapter 14 is either built or recorded as not offered, and `feature_diff.md` §2 is
empty: the roadmap is done.

## Intent

Three optional rules, each off unless a scenario (or the game's start) turns it on:

- **14.B voluntary surrender and rallying.** A badly hurt ship may haul down her colours before she is forced to
  strike, and may later try to run them up again. In Leeward this is also the 1v1 "concede".
- **14.D fatigue.** Gun crews tire: from a ship's sixth turn of firing her gunfire takes −1, from the sixteenth
  −2, and so on, for the rest of the game.
- **14.E historical gunfire limits.** A green or shaken crew (CQ E/F/G), or a ship heeled over firing to
  windward, often cannot hold its aim low: on a d6 of 4+ the shot goes high.

## Goals

1. **Switches** (B): a scenario `optional_rules` block — `voluntary_surrender` (bool), `fatigue` (bool),
   `gunfire_limits` (`"crew"`, `"heel"`, `"both"`, or absent/`"none"`) — all off by default, read through one
   pure reader, and an override passed to `GameState.start_scenario` (future lobby settings, tests).
2. **14.B** (U): surrender ordered in PLANNING by a request, effective at MORALE_CHECK; rally ordered in
   PLANNING and rolled at once; a second surrender is permanent; surrendering the last ship concedes.
3. **14.D** (B, as written): a public per-ship count of firing turns and a `fatigue` gunfire modifier.
4. **14.E** (B): one d6 per firing ship per g-t, rolled at resolution, covering both rules; the fire panel
   shows the chance before the player commits.
5. **The stub AI** surrenders and rallies by a simple policy (B); fatigue and 14.E need nothing from it.
6. **Events** SURRENDER, RALLY, AIM_FORCED; none counts boxes (`PlayerView.BOX_FIELDS` unchanged).
7. **View-only minimum** (U): a SURRENDERED badge, log lines, `fatigue` in the fire panel's modifier breakdown,
   the 14.E chance in the existing aim note; surrender and rally reachable through the server requests and two
   Developer UI buttons. No new player input control.
8. **Docs**: `feature_diff.md` (§2 emptied), `CLAUDE.md`, the scenario-creator skill, a test scenario with every
   rule on.

## Non-goals

- A lobby or options screen (U: no new input controls). The `start_scenario` override is the hook for one.
- Surrender or rally buttons on the planning card (the later UX pass).
- 14.A / 14.A.7 (closed, register §1). 14.C changes (done).
- Fatigue recovery or any other variant of 14.D (B: as written).

## Design

### 1. Switches (B)

**Scenario block.**

```json
"optional_rules": {"voluntary_surrender": true, "fatigue": true, "gunfire_limits": "both"}
```

Every key is optional. `gunfire_limits` takes `"crew"` (14.E.3), `"heel"` (14.E.4), `"both"`, or `"none"`
(the same as absent).

**Reader.** `OptionalRules` (new, `scripts/server/optional_rules.gd`, pure statics over a scenario dictionary;
the callers pass `game_state.active_scenario`, as `PlayerView.limited()` reads `tournament`):

| Function | Returns |
|---|---|
| `of(scenario) -> Dictionary` | the normalized block, `{"voluntary_surrender": bool, "fatigue": bool, "gunfire_limits": "none"/"crew"/"heel"/"both"}` |
| `voluntary_surrender(scenario) -> bool` | 14.B on |
| `fatigue(scenario) -> bool` | 14.D on |
| `crew_limit(scenario) -> bool` | `gunfire_limits` is `"crew"` or `"both"` |
| `heel_limit(scenario) -> bool` | `"heel"` or `"both"` |
| `merged(base: Dictionary, override: Dictionary) -> Dictionary` | `base` with `override`'s keys laid over it (both blocks) |
| `errors(scenario) -> Array[String]` | an unknown key, a non-bool switch, or a bad `gunfire_limits` value |

**Override.** `GameState.start_scenario(scenario_data, human_player_ids, optional_rules := {})`. A non-empty
override is merged into a copy of the scenario (`scenario["optional_rules"] = OptionalRules.merged(...)`) before
anything reads it, so `active_scenario` always holds the rules in force: a Developer UI reset
(`dev_commands.reset_game`, which passes `active_scenario` back) keeps them. **B (new):** `start_scenario` refuses
a scenario whose `OptionalRules.errors` is not empty (push_error, returns false), as it refuses bad terrain:
a misspelt switch would otherwise silently turn a rule off.

### 2. 14.B voluntary surrender and rallying

#### 2.1 State (all mutated only through `ShipStateController`; all public)

| `ShipState` field | Meaning |
|---|---|
| `surrender_ordered: bool` | ordered this g-t; she strikes at MORALE_CHECK |
| `surrenders: int` | voluntary surrenders made so far (0–2) |
| `surrendered: bool` | struck by a voluntary surrender and may still rally |
| `rally_turn: int` (−1) | the g-t of her last rally attempt (one a g-t) |

Helpers: `can_rally() -> bool` = `is_struck() and surrendered`. Invariant: `surrendered` implies STRUCK.
`ShipStateController.set_status` clears `surrendered` whenever the new status is not STRUCK, so a capture
(CAPTURED), an explosion (DESTROYED), a rally (ACTIVE) or a retaking (ACTIVE) can never leave a stale flag
(14.B.2: "once captured the ship may not rally").

Mutators: `set_surrender_ordered(ship_id, on)`, `record_surrender(ship_id) -> int` (surrenders + 1;
`surrendered` = the new count is 1), `end_surrender(ship_id)` (`surrendered` false: struck for good),
`restore_from_surrender(ship_id)` (status ACTIVE, which clears `surrendered`), `set_rally_turn(ship_id, turn)`.
All serialized.

Limited information (B, register: public): everything is public except `surrender_ordered`, which `PlayerView`
drops for a reader of another side, as it drops `escape_declared` (**B (new)**: the order is a secret plan until
the colours come down; teammates may read it, as a signalled order). The SURRENDER event then tells everyone.

#### 2.2 Eligibility (B; `SurrenderRules`, new, `scripts/server/surrender_rules.gd`, pure statics)

`sections_lost(ship) -> int`: rigging sections at 0 + hull sections at 0 + sailor sections at 0 + the marine
section at 0, each counted only when the type has boxes there, and a crew section counted only when none of its
boxes were detached as a prize crew (`ShipState.detached_boxes[i] == 0`; as `VictoryController.points_lost`).

`eligible(ship) -> bool`: CQ `F` or `G`, or `sections_lost(ship) >= SECTIONS_TO_SURRENDER` (5) (14.B.2).

`surrender_error(ship) -> String` ("" when she may): in play and on the map (not struck, destroyed, captured,
escaped, or awaiting arrival; an aground, anchored, fouled, grappled or towed ship may surrender, **B (new)**: the
rule names no exception, and an aground ship is already lost for victory), then eligibility:
"%s may surrender only at CQ F or G or with five sections lost (14.B.2): %d lost".

`rally_error(ship, turn) -> String`: "" when `can_rally()` and `rally_turn != turn`; else, in order: captured →
"a captured ship cannot rally (14.B.2)"; `surrenders >= 2` → "%s has surrendered twice: she has struck for good
(14.B.4)"; struck but not `surrendered` → "%s has struck for good"; not `can_rally()` → "%s has not
surrendered"; tried this turn → "%s has tried to rally this turn".
**B (new):** one attempt a g-t. 14.B.3 says "at any time"; one try per planning phase keeps a PVP player from
rolling until it passes.

#### 2.3 Ordering a surrender (U)

`TurnPhaseController.player_surrender(player_id: int, ship_id: String, on: bool = true) -> String`. Checks, in
order: server; game not over; `OptionalRules.voluntary_surrender` ("voluntary surrender is not used in this
scenario (14.B)"); PLANNING ("a ship surrenders in the planning phase (14.B)"); known player; plan not submitted;
known ship; `commands(player_id, ship_id)`; then with `on` the `SurrenderRules.surrender_error`. `on = false`
withdraws an order (**B (new)**: like a course, an order may be changed until the plan is in). Sets
`surrender_ordered`.

**During that g-t** (U: moves per plot, may be fired on, does not fire):
- Movement is untouched: the ship sails her plot.
- `GunneryCalculator.preview` refuses her as a firer: "a ship that is surrendering does not fire (14.B)". So
  `eligible_shots` is empty, `any_eligible_shot` ignores her, no HOLD_FIRE is logged, and the AI never orders
  fire for her. She is still a target (ACTIVE).
- `FireRules.marine_error` refuses her marines with the same words (**B (new)**: "does not fire" covers muskets).
- `BoardingRules._ba_error` refuses a new BA for her: "a ship that is surrendering does not board (14.B)".
  `CrewRules.normalize` therefore drops it at `finalize_plots`, for Automatic and manual crews alike. Boarders
  already fighting fight on. **B (new):** a ship hauling down her colours does not attack.

**At MORALE_CHECK** (U): before the noted morale checks,
`MoraleController.resolve_surrenders(phase)` takes every ship with `surrender_ordered`, in ship_id order:
1. clears the order;
2. skips her if she is already out of play (struck, destroyed or captured during the g-t);
3. `record_surrender` → n; logs **SURRENDER** `{"surrenders": n, "permanent": n >= 2}`;
4. `DamageController.strike(ship_id, "surrender", phase)` (STRIKE with reason "surrender"; every task but FF
   ends; her tow parts — the existing strike path);
5. when `permanent`, `end_surrender` (14.B.4: a second surrender is for good).

**B (new): surrenders come before the noted checks**, because 14.B.2 lets a ship surrender "before it is forced
to strike". `resolve_checks` then skips her (out of play) and clears her noted checks; a ship that would have
struck from morale this g-t surrenders instead and may rally later.

From then on she is an ordinary struck ship (14.B.2 "treated exactly like a ship that strikes"): not a target,
fights her fires only, drifts, is captured without a fight when boarded (10.A.3), stays anchored if anchored,
cannot be towed by her own side (towing ruling 4). Her escape declaration, if any, is kept (**B (new)**: harmless
while she is out of play; the player may withdraw it after a rally).

#### 2.4 Rallying (U)

`TurnPhaseController.player_rally(player_id: int, ship_id: String) -> String`. Same first checks as
`player_surrender` ("… rallies in the planning phase (14.B)"), then `SurrenderRules.rally_error(ship,
current_turn)`. Then at once (U: "rolled at once"):

`MoraleController.rally(ship_id: String, phase: int) -> Dictionary`: `set_rally_turn`; one `game_state.dice.d10()`;
passes when `roll >= ship.morale_rating` (as `_check`).
- **Pass:** `restore_from_surrender` (ACTIVE). Logs **RALLY** `{"roll", "rating", "passed": true}`.
- **Fail at CQ A–F:** CQ one letter worse (`set_crew_quality`). RALLY `{…, "passed": false, "quality": <new>}`.
- **Fail at CQ G:** `end_surrender` (struck for good, 14.B.3 "strikes due to successive morale failures"). RALLY
  `{…, "passed": false, "breaks": true}`.

Returns `{"passed": bool}`. `player_rally` returns "" whenever the roll was made (the outcome is in the log and
the state).

**After a pass** (U: "it plots this turn"): `TurnPhaseController._after_rally(ship)` does for her what PLANNING's
entry did for the others: when her commander is human (`human_player_ids`), stores her 6.G.2 default course and
her `planning_snapshot` entry (one helper, `_store_default_course(ship)`, split out of `_store_default_courses`
so both use it). Her crew plan this g-t is the carry-over default (`CrewRules.plan_of`: her FF parties stay); her
`crew_auto` is left as it was (**B (refined)**: the memo said "Automatic crew plan"; the player can plot her
crew now, so nothing is forced). Fouling, grapples and anchor are kept. 10.A.2's `linked_at_plot` was taken when
PLANNING began and stands.

**Readiness (B (new)).** `_auto_ready_players` sets ready a player who commands no ship in play. With 14.B on, a
human player whose only ships are rallyable surrenders is **not** auto-ready (`_has_rallyable_ship(id)`): the
turn waits for him so he can rally or submit. AI players stay auto-ready; the stub rallies inside
`plot_all_ai_ships`, which runs first.

#### 2.5 Victory (U)

No code change. A surrendered ship is STRUCK, so `VictoryController.is_lost` scores her at 100 % and
`_is_defeated` treats her as gone. In 1v1, surrendering the last ship ends the game at that g-t's END_TURN with
reason "all struck" (U: concede). A rallied ship is ACTIVE again and scores by her destroyed sections.

#### 2.6 Interactions settled

| With | Behaviour |
|---|---|
| Boarding (10.A.3, 10.E.2a) | a surrendered ship boarded is captured at once (existing struck path); once captured she cannot rally (status). A defender who orders surrender while locked in an action fights that g-t's round, then strikes; the action ends as a capture next combat (existing). |
| Prizes (10.H.4) | a surrendered ship taken and later retaken is ACTIVE under her own side (`retake`), `surrendered` false (set_status), `surrenders` kept: her next surrender is her second, and permanent (14.B.4, **B (new)**). |
| Towing | the strike parts her tow (existing `tow_controller.on_ship_changed`); her own side cannot tow her while surrendered (towing ruling 4); after a rally she may tow or be towed again. |
| Anchoring | kept while surrendered; she rides to it as a struck ship does. |
| Escape | a struck ship never escapes (out of play); her declaration is kept. |
| Fire (8.E.3) | a surrendered ship fights her fires at CQ G (`FireController.skill`), as any struck ship. |
| Signals | a surrendered ship's player may still send if another of his ships is in play (11.B.2b reads the sending ship; existing). |

### 3. 14.D fatigue (B, as written)

**Count.** `ShipState.gunfire_turns: int` — the g-t's in which the ship fired at least one shot (any battery or
chaser), the ship log's "gunfire" column (14.D.2). It is counted whatever the switch (**B (new)**: it is a log
fact, and switching the rule on mid-test or in a later save then reads a true history); only the modifier is
gated. Public (14.C.1d: gun state). `ShipStateController.note_gunfire_turn(ship_id)` adds one.
`GunneryResolver.resolve` calls it once per distinct firer, in ship_id order, after every shot of the step is
resolved (so every shot of the g-t reads the count before it).

**Penalty.** `FireRules.fatigue_penalty(prior: int) -> int` (positive), `prior` the firing turns before this one:
0 while `prior < FATIGUE_FREE_TURNS` (5); else `1 + (prior − 5) / FATIGUE_STEP_TURNS` (10), integer division. So
−1 from the 6th firing turn (prior 5–14), −2 from the 16th (15–24), −3 from the 26th. **B (register):** "after
the fifth" and "every tenth after the first fatigue" read consistently; the book's "g-t's 15, 25, 35" is taken
as the 15th turn completed.

**Modifier.** In `GunneryCalculator.preview`, when `OptionalRules.fatigue(active_scenario)`:
`_add_modifier(p, "fatigue", -FireRules.fatigue_penalty(firer.gunfire_turns))`, placed after
`guns_dismounted`. Its own modifier name, not merged into `guns_dismounted` (register), labelled "fatigue".
**B (new): it applies to chasers too** — it is the crew that tires, and the chasers are served by the same crew
(sections firing applies to them, ships-and-guns §4.3); and a chaser shot counts as a firing turn (ships-and-guns
§4.5 noted this for here). Not marine fire. Preview = rolled: the resolver uses `preview_orders`, so the
displayed MGN includes it.

### 4. 14.E historical gunfire limits (B)

**Which shots.** A shot qualifies when its order aims low, it is not high-only (range < 10), and:
- **crew** (14.E.3, `crew_limit` on): the firer's CQ is E, F or G; or
- **heel** (14.E.4, `heel_limit` on): the order is a broadside (side 0 or 1), the firer is at WF=C or WF=B, and
  the side fired is to windward: `FireRules.fires_to_windward(facing, wind_direction, side)` =
  `leeward_side(facing, wind_direction) != -1 and side != leeward_side(...)`. (`FireGeometry.leeward_side` is −1
  exactly at WF=L and WF=R, so this one test gives both conditions.) **B (new): the heel rule never applies to a
  chaser**: she fires along the keel, not across the heel; the crew rule does.

Pure: `FireRules.aim_limits(order_aim: String, high_only: bool, crew_quality: String, side: int, facing: int,
wind_direction: int, crew_on: bool, heel_on: bool) -> Array[String]`, giving `["crew"]`, `["heel"]`,
`["crew", "heel"]` or `[]`. `GunneryCalculator.preview` stores it on `ShotPreview.aim_limits` (new field) for a
shot that can fire. Every navy (register).

**The roll (dice order).** In `GunneryResolver.resolve`, after the shots are captured (step 1) and before they
are sorted and rolled: for each distinct firer with at least one qualifying shot, in ship_id order, one
`game_state.dice.d6()` (**one d6 covers both rules**, register). On `roll >= AIM_FORCED_MIN` (4) every
qualifying shot of that ship is fired high: its preview's order is replaced by a copy (`FireOrder.from_dict(
order.to_dict())`) with `aim = "high"`, so the results column, the hull-fire cause and the crit tables all read
high; the caller's orders are untouched. The MGN does not depend on aim, so preview = rolled still holds. Logs
**AIM_FORCED** `{"roll", "rules": [...], "sides": [...], "quality"}` (ship_id = the firer) when forced. Every qualifying
shot's FIRE event gains `"aim_ordered": "low"` and `"aim_roll": roll` (forced or not). **B (refined):** one roll
per ship per g-t ("the ship rolls a d6 when it fires"), before any gunnery die, so one ship's gunnery dice never
depend on another's aim roll. With the switch off no die is rolled and the documented dice order is unchanged.

**The chance before firing (preview = rolled).** The roll cannot be shown in advance, so its chance is: the fire
panel's aim note (the label beside the High-fire toggle, `FireDeclarationPanel.aim_note`) reads, when the side's
low shots have limits, "Low aim holds only on a d6 of 1–3 (14.E: crew CQ E)" / "(14.E: firing to windward)" /
"(14.E: crew CQ E, firing to windward)". The breakdown numbers are unchanged (aim does not move the MGN).

**AI.** Unchanged (**B (new)**): its low orders are rolled like anyone's; preferring high to dodge the roll would
throw away the hull hits it is after half the time.

### 5. Stub AI (B, register)

In `StubAI.plot_all_ai_ships`, with 14.B on:
1. **Rally first**, before plotting: every AI ship with `can_rally()` and no enemy in play on the map within 5
   hexes (`_enemy_within(ship, RALLY_CLEAR_RANGE)`, 5) calls `phase_controller.player_rally(commander, id)`; a
   passed ship is then plotted with the others.
2. Plot as now.
3. **Surrender last**: every AI ship in play with `wants_to_surrender(ship)` calls
   `phase_controller.player_surrender(commander, id, true)`.

`wants_to_surrender(ship) -> bool`: `SurrenderRules.eligible(ship)`, not already ordered, and either
- an enemy in `ship.linked_ids()`, in play, with `has_boarders()` (readied or boarding); or
- `enemy_guns_within(ship, SURRENDER_ODDS_RANGE) >= SURRENDER_ODDS * gun_strength(ship)` with the enemy sum > 0
  (range 3, odds 2).

`static gun_strength(ship) -> int` = max over the two broadsides of (lg + mg + cr − `guns_dismounted[side]`),
at least 0. **B (new):** "odds" are read as gun factors, the thing that makes a ship strike; chasers are left out
(one factor each, as for 2.A.1). Refusals are added to `refusals` like plotting refusals. The AI never withdraws
a surrender order.

### 6. Events (B, register)

Appended at the end of `PhaseEvents.Type` (stored logs keep their numbers):

| Type | Data | Text (`to_text`) |
|---|---|---|
| `SURRENDER` | `{surrenders, permanent}` | "HMS X hauls down her colours (voluntary surrender, 14.B)" + "; her second surrender: she cannot rally again" |
| `RALLY` | `{roll, rating, passed, quality \| breaks}` | "HMS X tries to rally: rolled 6, needed 4 — she rallies and fights on" / "— fails; crew quality drops to F" / "— fails; she has struck for good" |
| `AIM_FORCED` | `{roll, rules, sides, quality}` | "HMS X's gun crews cannot hold their aim low: rolled 5 (4+ fires high; 14.E: crew CQ E)" |

`STRIKE_REASONS["surrender"]` = "she surrendered (14.B)". `MODIFIER_LABELS["fatigue"]` = "fatigue". None counts
boxes, so `BOX_FIELDS` is unchanged and `PlayerView.events_for` passes them to everyone.

### 7. View (U: view-only minimum)

- **Badges.** `PlanningSailUi.status_badge`: "SURRENDERED" for a struck ship with `surrendered` (before the
  "STRUCK" test); a ship struck for good stays "STRUCK". `card_badge` adds "SURRENDERING" while
  `surrender_ordered` (own cards only show it). `ShipStatusBars.last_line`: ["Status", "Surrendered"].
- **Map.** `ShipView._update_struck_visual(false)` already restores the colours and removes the white flag, so a
  rally needs no new view code; the task checks it live.
- **Fire panel.** `NO_SHOT_SURRENDERING` "surrendering" for a ship with `surrender_ordered` (mapped from the
  calculator's reason and short-cut in `ship_no_shot_reason`), "surrendered" for a surrendered ship; the aim note
  of §4; `fatigue` appears in the breakdown through `modifier_label`.
- **Developer UI.** "Surrender" and "Rally" buttons in the ship tab, beside "Start fire", calling
  `dev_commands.surrender_ship(ship_id)` / `dev_commands.rally_ship(ship_id)`, which call the player requests for
  the ship's commanding player (same checks, so they work in PLANNING only). No buttons on the planning card.

### 8. Scenario and docs

`data/scenarios/test_optional_rules.json` turns every rule on (`gunfire_limits: "both"`): two ships a side so a
surrender does not end the game at once, one side at CQ E, the wind across the line of battle so one fleet fires
to windward. A test plays it to the end with every player AI. Docs as Goal 8; `feature_diff.md` §2 is emptied:
the optional-rules row goes to §5 (with §4 bullets for the readings), and the remaining §2 rows move to §3/§4/§5
as their status says (the plan's last task lists each).

### 9. Server authority and determinism

New requests `player_surrender` and `player_rally` take a `player_id` and check `commands`; the Developer UI
reaches them through `dev_commands`. View code only reads (`test_server_authority.gd` gains patterns for the new
fields and mutators). New dice: the rally d10 (PLANNING, at the request), the 14.E d6s (combat, documented step),
none for surrender or fatigue. With every switch off, no new die is rolled, no new modifier appears and every
existing test's numbers stand.

### 10. Builder's calls, collected

| Call | Kind | Reason |
|---|---|---|
| `start_scenario` refuses bad `optional_rules` | B (new) | a misspelt switch would silently turn a rule off |
| Override merged into `active_scenario` | B (new) | one place to read; a Developer UI reset keeps it |
| `surrender_ordered` hidden from other sides | B (new) | a plan, like a declared escape; SURRENDER tells everyone |
| Surrender may be withdrawn before the plan is in | B (new) | as any planning order |
| Aground, anchored, fouled, grappled, towed ships may surrender | B (new) | 14.B.2 names no exception |
| A surrendering ship fires no muskets and sends no new boarders | B (new) | "does not fire"; a ship hauling down does not attack |
| Surrenders before the noted morale checks | B (new) | 14.B.2 "before it is forced to strike" |
| One rally attempt a g-t | B (new) | no rolling until it passes in PVP |
| Rally keeps `crew_auto` | B (refined) | the player can plot the crew in the same planning |
| A rallyable human player is not auto-ready | B (new) | otherwise he could never rally |
| A retaken ship keeps her surrender count | B (new) | 14.B.4 counts surrenders, not captures |
| Escape declaration kept through a surrender | B (new) | harmless while out of play |
| Firing turns counted with the switch off | B (new) | a log fact; only the modifier is gated |
| Fatigue on chasers; a chaser shot is a firing turn | B (new) | the same crew serves them |
| Heel rule never on a chaser | B (new) | she fires along the keel |
| One 14.E d6 per ship, before any gunnery die | B (refined) | 14.E.3 "when it fires"; independent dice |
| AI aim unchanged | B (new) | high to dodge the roll loses hull hits |
| AI odds by gun factors, chasers out | B (new) | guns make a ship strike; as 2.A.1 |
| Register entries changed | — | none |
