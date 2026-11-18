# Optional Rules (14.B, 14.D, 14.E) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Offer the last three optional rules of Close Action chapter 14 — voluntary surrender and rallying
(14.B), fatigue (14.D) and historical gunfire limits (14.E) — each switched on per scenario (or by an override
at game start), played by the stub AI, shown by a view-only minimum, and leave `feature_diff.md` §2 empty.

**Architecture:**
- One pure reader, `OptionalRules`, over `active_scenario.optional_rules`; `start_scenario` merges an override
  into the scenario and refuses a bad block (Task 1).
- 14.D: a public count of firing turns on `ShipState`, bumped by `GunneryResolver`; a `fatigue` modifier in
  `GunneryCalculator.preview` from the pure `FireRules.fatigue_penalty` (Task 2).
- 14.E: pure `FireRules.aim_limits` stored on `ShotPreview.aim_limits`; one d6 per firing ship in a new,
  documented resolver step that turns qualifying low shots high; the fire panel's aim note shows the chance
  (Task 3).
- 14.B: state on `ShipState`, pure `SurrenderRules`, requests `player_surrender` / `player_rally` on
  `TurnPhaseController`, the strike at MORALE_CHECK and the rally roll in `MoraleController` (Tasks 4–5); the AI
  policy in `StubAI` (Task 6); badges, fire-panel words and Developer UI buttons (Task 7).
- Test scenario, docs and the SCV audit (Task 8).

**Size:** 8 tasks. Each is one reviewer gate; `make test` is green after each.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5. `make test` runs the whole suite. Run `make import` before
`make test` whenever a task adds a `class_name` or any new file; Godot then writes the `.uid` files, which the
task's commit must include.

**Spec:** `docs/superpowers/specs/2026-11-18-optional-rules-design.md`. Executors read it alongside this plan;
section numbers below (§n) are the spec's. Binding requirements:
`docs/superpowers/specs/2026-11-17-subprojects-3-7-decisions.md` §0 and §6. Rules: `docs/rules/close_action.md`
14.B, 14.D, 14.E (search `grep -n '^\*\*14\.[BDE]' docs/rules/close_action.md`). Invoke the `close-action-rules`
skill before game-logic work, and `phase-implementer` before changing a phase method (Tasks 4–5).

## Global Constraints

- **Switch block:** scenario key `optional_rules`, keys `voluntary_surrender` (bool), `fatigue` (bool),
  `gunfire_limits` (`"none"` | `"crew"` | `"heel"` | `"both"`; absent = `"none"`). All off by default.
- **14.B numbers:** eligible at CQ `F` or `G`, or `SurrenderRules.SECTIONS_TO_SURRENDER` = 5 sections lost
  (rigging + hull + sailor + marine sections at 0; a crew section whose boxes were detached as a prize crew does
  not count). `SurrenderRules.MAX_SURRENDERS` = 2 (the second is permanent). Rally: one d10, passes when
  `roll >= morale_rating`; fail lowers CQ one letter; fail at G = struck for good. One rally attempt per g-t.
- **14.D numbers:** `FireRules.FATIGUE_FREE_TURNS` = 5, `FireRules.FATIGUE_STEP_TURNS` = 10;
  `fatigue_penalty(prior)` = 0 for prior < 5, else `1 + (prior - 5) / 10` (prior 5 → 1, 14 → 1, 15 → 2, 24 → 2,
  25 → 3). Modifier name `"fatigue"`, value `-fatigue_penalty(ship.gunfire_turns)`.
- **14.E numbers:** `FireRules.AIM_FORCED_MIN` = 4 (d6 ≥ 4 forces high). Crew rule: CQ E, F or G. Heel rule:
  broadside sides 0/1 only, `FireGeometry.leeward_side(facing, wind_direction) != -1` and `side != leeward`.
  Only low orders that are not high-only (range < 10) qualify. Never marine fire.
- **Events** (appended at the end of `PhaseEvents.Type`, in this order): `SURRENDER`, `RALLY`, `AIM_FORCED`.
  None counts boxes: `PlayerView.BOX_FIELDS` unchanged.
- **Dice:** through `game_state.dice` only. With every switch off, no new die, no new modifier, no new event:
  every existing test's numbers stand.
- **Fixture directions:** `HexGrid.DIRECTIONS` 0 = E (1, 0), 1 = SE (0, 1), 2 = SW (−1, 1), 3 = W (−1, 0),
  4 = NW (0, −1), 5 = NE (1, −1). Starboard is `facing + 1` / `+ 2`. `leeward_side(0, w)`: w = 5 or 4 →
  STARBOARD (WF C / B); w = 1 or 2 → PORT; w = 0 (WF L) or 3 (WF R) → −1.
- **Gunnery fixture:** as `test/unit/test_gunnery_resolver.gd` (`_setup_ships`, `_make_ship`, `_order`): wind
  speed 2, sea 1, CQ D, sail MS; A bow (0, 0) facing 0, B bow (−1, 1) facing 3, so A's starboard full broadside
  bears on B. Tests that change `GameState.active_scenario` save and restore it (`before_each` / `after_each`).
- **Server authority:** view code (`scripts/ui`, `scripts/view`, `scripts/core`, `scripts/commands`) only reads;
  `test_server_authority.gd` must stay green. Requests take `player_id` and check `game_state.commands`.
- Use `Trace`, never `print()`.
- An existing test may change its expected values only where a task says so; each such change is listed in the
  commit message with the reason.
- The PostToolUse hook runs the full `make test` after edits under `scripts/server/`, `scripts/state/`,
  `scripts/core/`, `scripts/autoload/` and `test/unit/`.
- `docs/rules/feature_diff.md`, `CLAUDE.md` and the scenario-creator skill are updated in Task 8 only.
- **Commits:** every commit that adds a file also adds its `.uid` (run `make import` first). Plain separate git
  commands from the worktree, no `git -C`. End every commit message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A switch that is off still changes play** (a die rolled, a modifier added, a ship refused). Pinned by
   Task 1 `test_all_off_by_default`, Task 2 `test_no_fatigue_modifier_when_off`, Task 3
   `test_no_aim_roll_when_off` and the unchanged `test_gunnery_resolver.gd`.
2. **A stale `surrendered` flag** after a capture, an explosion or a retaking lets a ship rally that may not.
   Pinned by Task 4 `test_set_status_clears_surrendered` and Task 5 `test_captured_ship_cannot_rally`.
3. **A player who can only rally is never asked** (auto-ready, planning ends at once). Pinned by Task 5
   `test_rallyable_human_is_not_auto_ready`.
4. **Preview ≠ rolled** with fatigue or a forced aim. Pinned by Task 2 `test_fire_event_mgn_includes_fatigue`
   and Task 3 `test_forced_high_keeps_mgn`.
5. **A surrendering ship still attacks** (guns, muskets or new boarders) during her last g-t. Pinned by Task 4
   `test_surrendering_ship_does_not_fire`, `test_surrendering_ship_fires_no_muskets`,
   `test_surrendering_ship_sends_no_new_boarders`.

---

### Task 1: The switches — `OptionalRules` and the `start_scenario` override

**Files:**
- Create: `scripts/server/optional_rules.gd`, `test/unit/test_optional_rules.gd`.
- Modify: `scripts/autoload/game_state.gd` (`start_scenario`).

**Interfaces (Produces):**
- `class_name OptionalRules extends RefCounted`, pure statics, header comment naming 14.B, 14.D, 14.E and the
  register §6:
  - `const KEY := "optional_rules"`, `const GUNFIRE_LIMIT_VALUES: Array[String] = ["none", "crew", "heel", "both"]`,
    `const SWITCHES: Array[String] = ["voluntary_surrender", "fatigue"]`.
  - `static func of(scenario: Dictionary) -> Dictionary` → `{"voluntary_surrender": bool, "fatigue": bool,
    "gunfire_limits": String}`; a missing block or key is off / `"none"`; a bad value reads as off / `"none"`.
  - `static func voluntary_surrender(scenario: Dictionary) -> bool`, `static func fatigue(scenario) -> bool`,
    `static func crew_limit(scenario) -> bool` (`"crew"` or `"both"`), `static func heel_limit(scenario) -> bool`
    (`"heel"` or `"both"`).
  - `static func merged(base: Dictionary, override: Dictionary) -> Dictionary`: a copy of `base` with each key of
    `override` laid over it.
  - `static func errors(scenario: Dictionary) -> Array[String]`: `[]` when there is no block; else one message per
    problem: block not a Dictionary ("optional_rules must be an object"); unknown key ("unknown optional rule
    'x'"); a switch that is not a bool ("optional_rules.fatigue must be true or false"); `gunfire_limits` not a
    String of `GUNFIRE_LIMIT_VALUES` ("optional_rules.gunfire_limits must be none, crew, heel or both").
- `GameState.start_scenario(scenario_data: Dictionary, human_player_ids: Array[int], optional_rules: Dictionary =
  {}) -> bool`: first, when `optional_rules` is not empty, `scenario_data = scenario_data.duplicate(true)` and
  `scenario_data[OptionalRules.KEY] = OptionalRules.merged(scenario_data.get(OptionalRules.KEY, {}),
  optional_rules)`; then (beside the terrain check) each `OptionalRules.errors(scenario_data)` message is
  `push_error`ed and it returns false with "GameState: scenario not started: bad optional_rules". Update its doc
  comment. No other caller changes (`dev_commands.reset_game` passes `active_scenario`, which already holds the
  merged block).

- [ ] **Step 1: Write the failing tests** in `test/unit/test_optional_rules.gd`:
  - `test_all_off_by_default`: `OptionalRules.of({}) == {"voluntary_surrender": false, "fatigue": false,
    "gunfire_limits": "none"}`; the four predicates false on `{}` and on `{"optional_rules": {}}`.
  - `test_reads_each_switch`: `{"optional_rules": {"voluntary_surrender": true}}` → only `voluntary_surrender`;
    `{"fatigue": true}` → only `fatigue`; `gunfire_limits` `"crew"` → `crew_limit` true, `heel_limit` false;
    `"heel"` → the reverse; `"both"` → both; `"none"` → neither.
  - `test_errors`: `errors({}) == []`; `errors({"optional_rules": {"fatigue": true, "gunfire_limits": "both"}}) ==
    []`; `{"optional_rules": {"fatigu": true}}` → one error containing "unknown optional rule"; `{"fatigue": 1}`
    → one containing "true or false"; `{"gunfire_limits": "french"}` → one containing "none, crew, heel or both";
    `{"optional_rules": []}` → one containing "must be an object".
  - `test_merged_overrides_keys`: `merged({"fatigue": true}, {"gunfire_limits": "crew"}) == {"fatigue": true,
    "gunfire_limits": "crew"}`; `merged({"fatigue": true}, {"fatigue": false})["fatigue"] == false`.
  - `test_start_scenario_merges_the_override`: load `data/scenarios/test_basic.json` (as
    `test_data_manager_scenarios.gd` loads scenarios), `GameState.start_scenario(s, [] as Array[int],
    {"fatigue": true})` is true; `OptionalRules.fatigue(GameState.active_scenario)`; the loaded dictionary `s`
    itself has no `optional_rules` key (copied, not changed).
  - `test_start_scenario_refuses_bad_rules`: with `{"gunfire_limits": "french"}` as the override, returns false
    (expect the push_error: use GUT's `assert_push_error` or the suite's existing pattern for expected errors,
    e.g. in `test_map_scenarios.gd`).
  - Restore `GameState` after the start tests the way `test_battle_to_victory.gd` does.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`. Expected: the new tests fail
  (`OptionalRules` unknown).
- [ ] **Step 3: Implement** `optional_rules.gd` and the `start_scenario` change per the Interfaces.
- [ ] **Step 4: Run.** `make import && make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/optional_rules.gd scripts/server/optional_rules.gd.uid scripts/autoload/game_state.gd test/unit/test_optional_rules.gd test/unit/test_optional_rules.gd.uid
git commit -m "feat: optional_rules scenario switches and the start_scenario override (14.B, 14.D, 14.E)"
```

### Task 2: 14.D fatigue

**Files:**
- Modify: `scripts/state/ship_state.gd`, `scripts/server/ship_state_controller.gd`, `scripts/server/fire_rules.gd`,
  `scripts/server/gunnery_calculator.gd`, `scripts/server/gunnery_resolver.gd`, `scripts/server/phase_events.gd`,
  `test/unit/test_server_authority.gd`.
- Create: `test/unit/test_fatigue.gd`.

**Interfaces:**
- Consumes: `OptionalRules.fatigue(scenario)` (Task 1).
- Produces:
  - `ShipState.gunfire_turns: int = 0` (`@export`, comment "14.D.2: g-t's in which the ship fired any battery or
    chaser (the log's gunfire column)"), in `serialize` (`"gunfire_turns"`) and `deserialize` (default 0).
  - `ShipStateController.note_gunfire_turn(ship_id: String) -> bool`: server only (push_error on client, as
    `set_escape_declared`), `gunfire_turns += 1`, emits `ship_state_changed`.
  - `FireRules.FATIGUE_FREE_TURNS := 5`, `FireRules.FATIGUE_STEP_TURNS := 10`,
    `static func fatigue_penalty(prior: int) -> int` (Global Constraints), comment citing 14.D.2–3 and the
    register's reading.
  - `GunneryCalculator.preview`: right after the `guns_dismounted` line (for chasers too, so outside the
    `if not chase:` block), `if OptionalRules.fatigue(game_state.active_scenario): _add_modifier(p, "fatigue",
    -FireRules.fatigue_penalty(firer.gunfire_turns))`. Update the header comment of `preview` (chasers take
    fatigue).
  - `GunneryResolver.resolve`: after the shot loop, every distinct firer of a resolved shot, ascending ship_id,
    gets one `note_gunfire_turn`. Header comment: "14.D: each ship that fired counts one firing turn, after all
    shots (no die)."
  - `PhaseEvents.MODIFIER_LABELS["fatigue"] = "fatigue"`.
  - `test_server_authority.gd` `FORBIDDEN` gains `["\\.gunfire_turns\\s*(=|\\+=|-=)[^=]", "the fatigue count
    written from view code"]` and `["\\bnote_gunfire_turn\\(", "the fatigue count changed from view code"]`, with
    a `test_fatigue_patterns_catch_mutations` in the style of `test_terrain_patterns_catch_mutations`
    (bad: `ship.gunfire_turns = 3`, `GameState.ship_controller.note_gunfire_turn("a")`; good:
    `var n := ship.gunfire_turns`, `if ship.gunfire_turns >= 5:`).

- [ ] **Step 1: Write the failing tests** in `test/unit/test_fatigue.gd` (the gunnery fixture; set
  `GameState.active_scenario = {"optional_rules": {"fatigue": true}}` unless stated):
  - `test_fatigue_penalty_steps` (14.D.2–3): `fatigue_penalty(0) == 0`, `(4) == 0`, `(5) == 1`, `(14) == 1`,
    `(15) == 2`, `(24) == 2`, `(25) == 3`.
  - `test_preview_takes_fatigue`: A's starboard full broadside at B with `a.gunfire_turns = 4`: no `fatigue`
    modifier; `= 5`: modifier `{"name": "fatigue", "value": -1}` and `mgn` one less than with 4; `= 15`: −2.
  - `test_no_fatigue_modifier_when_off`: `active_scenario = {}`, `a.gunfire_turns = 20`: no `fatigue` modifier.
  - `test_chaser_takes_fatigue`: B moved dead ahead of A (B bow (3, 0), facing 0), order side
    `GunneryTypes.CHASE_BOW`, battery `GunneryTypes.BATTERY_CHASE`, `a.gunfire_turns = 5`: modifier −1.
  - `test_resolve_counts_one_turn_per_firing_ship`: dice `_sixes()`; A fires its starboard full broadside at B
    and B its starboard full broadside at A: after `_fire`, `a.gunfire_turns == 1` and `b.gunfire_turns == 1`;
    fire the same orders again: 2 and 2.
  - `test_two_shots_count_once`: a third ship C of side 1 dead ahead of A at range 2 (bow (3, 0), facing 0);
    A fires its starboard full broadside at B and its bow chaser (`CHASE_BOW`, `BATTERY_CHASE`) at C in one
    `_fire`: `a.gunfire_turns == 1`.
  - `test_count_runs_with_the_switch_off`: `active_scenario = {}`, one A shot resolved → `a.gunfire_turns == 1`.
  - `test_fire_event_mgn_includes_fatigue`: `a.gunfire_turns = 5`, A fires at B: A's FIRE event `mgn` equals the
    `preview` mgn and its `modifiers` hold `fatigue` −1.
  - `test_gunfire_turns_serialized`: `ShipState.deserialize(a.serialize()).gunfire_turns == a.gunfire_turns`
    (with 7).
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run.** `make test`. Expected: all green; `test_gunnery_resolver.gd` and
  `test_gunnery_calculator.gd` unchanged.
- [ ] **Step 5: Commit.**

```bash
git add scripts/state/ship_state.gd scripts/server/ship_state_controller.gd scripts/server/fire_rules.gd scripts/server/gunnery_calculator.gd scripts/server/gunnery_resolver.gd scripts/server/phase_events.gd test/unit/test_server_authority.gd test/unit/test_fatigue.gd test/unit/test_fatigue.gd.uid
git commit -m "feat: 14.D fatigue — firing turns counted, fatigue modifier from the 6th"
```

### Task 3: 14.E historical gunfire limits

**Files:**
- Modify: `scripts/server/fire_rules.gd`, `scripts/server/gunnery_types.gd`, `scripts/server/gunnery_calculator.gd`,
  `scripts/server/gunnery_resolver.gd`, `scripts/server/phase_events.gd`, `scripts/ui/fire_declaration_panel.gd`,
  `test/unit/test_fire_declaration_panel.gd`.
- Create: `test/unit/test_gunfire_limits.gd`.

**Interfaces:**
- Consumes: `OptionalRules.crew_limit`, `OptionalRules.heel_limit` (Task 1).
- Produces:
  - `FireRules.AIM_FORCED_MIN := 4`, `FireRules.LIMITED_QUALITIES: Array[String] = ["E", "F", "G"]`.
  - `static func fires_to_windward(facing: int, wind_direction: int, side: int) -> bool`: false for a side other
    than 0/1; else `leeward := FireGeometry.leeward_side(facing, wind_direction)`, `leeward != -1 and side !=
    leeward`.
  - `static func aim_limits(aim: String, high_only: bool, crew_quality: String, side: int, facing: int,
    wind_direction: int, crew_on: bool, heel_on: bool) -> Array[String]`: `[]` unless `aim == "low"` and not
    `high_only`; then `"crew"` when `crew_on` and the CQ is in `LIMITED_QUALITIES`, then `"heel"` when `heel_on`
    and `fires_to_windward(facing, wind_direction, side)`, in that order.
  - `GunneryTypes.ShotPreview.aim_limits: Array[String] = []` (comment: "14.E rules that may force this low shot
    high on a d6 of 4+; empty when none").
  - `GunneryCalculator.preview`: just before `p.can_fire = true`, `p.aim_limits = FireRules.aim_limits(order.aim,
    p.high_only, firer.crew_quality, order.side, firer.facing, game_state.environment.wind_direction,
    OptionalRules.crew_limit(sc), OptionalRules.heel_limit(sc))` with `sc = game_state.active_scenario`.
  - `GunneryResolver.resolve`: a new step between capture (step 1) and the sort (step 2), `_roll_aim_limits(shots,
    phase)`: the firers of shots whose `preview.aim_limits` is not empty, ascending ship_id; per firer one
    `game_state.dice.d6()`; each of its qualifying shot dictionaries gets `"aim_roll": roll`; when `roll >=
    FireRules.AIM_FORCED_MIN` each such preview's `order` is replaced by a copy (`GunneryTypes.FireOrder.from_dict(
    order.to_dict())`) with `aim = GunneryTypes.AIM_HIGH`, and one `AIM_FORCED` event is logged (ship_id the
    firer, data `{"roll": roll, "rules": <the union of the shots' aim_limits, "crew" before "heel">, "sides":
    <the sorted distinct sides of those shots>, "quality": <the firer's crew_quality>}`). `_resolve_shot` adds `"aim_ordered": "low"` and
    `"aim_roll": roll` to the FIRE data of a shot that has `aim_roll`. Dice-order header: a new first item
    "0. (14.E, only with gunfire_limits on) one d6 per firing ship that has a qualifying low shot, ascending
    firer ship_id, before any shot's dice; 4+ fires every such shot of that ship high".
  - `PhaseEvents.Type.AIM_FORCED` appended (after `SURRENDER` and `RALLY`, which this task also appends now so
    the enum order is fixed: `SURRENDER`, `RALLY`, `AIM_FORCED`; their comments name Tasks 4–5 and their text is
    added there), with comment `# 14.E a low aim forced high: {roll, rules: ["crew"|"heel"], sides, quality}`;
    `to_text`: "%s's gun crews cannot hold their aim low: rolled %d (4+ fires high; 14.E: %s)", the rules read
    `"crew CQ %s" % quality` for `"crew"` and "firing to windward" for `"heel"`, joined by ", ".
  - `FireDeclarationPanel`: `static func aim_note(high_only: bool, limits: Array = [], crew_quality: String = "")
    -> String`: high-only → the existing note; else empty `limits` → ""; else `"Low aim holds only on a d6 of
    1–3 (14.E: %s)"` with parts `"crew CQ %s" % crew_quality` for `"crew"` and `"firing to windward"` for
    `"heel"`, joined by ", ". The refresh (where `widgets["high_note"].text = aim_note(any_high_only)` is set)
    passes the union of the side's previews' `aim_limits` and the ship's `crew_quality` (read from
    `GameState.get_ship(ship_id)`, a read).

- [ ] **Step 1: Write the failing tests** in `test/unit/test_gunfire_limits.gd` (gunnery fixture, ScriptedDice,
  `active_scenario` set per test):
  - `test_fires_to_windward` (14.E.4): facing 0, side STARBOARD: wind 1 → true (WF C, port leeward), wind 2 →
    true (WF B); wind 5 → false (starboard leeward); wind 0 → false (WF L); wind 3 → false (WF R); side
    `GunneryTypes.CHASE_BOW` with wind 1 → false.
  - `test_aim_limits` (14.E.3–4): `aim_limits("low", false, "E", 1, 0, 0, true, false) == ["crew"]`; `"D"` →
    `[]`; `"G"` → `["crew"]`; `("low", false, "D", 1, 0, 1, false, true) == ["heel"]`; `("low", false, "F", 1, 0,
    1, true, true) == ["crew", "heel"]`; `("high", false, "G", 1, 0, 1, true, true) == []`; `("low", true, "G",
    1, 0, 1, true, true) == []` (range 10+); `("low", false, "G", 2, 0, 1, false, true) == []` (a chaser).
  - `test_preview_carries_aim_limits`: `{"gunfire_limits": "crew"}`, A at CQ E, starboard full low at B:
    `preview.aim_limits == ["crew"]`; aim high → `[]`; with `{}` → `[]`.
  - `test_forced_high_on_four` (14.E.3): `{"gunfire_limits": "crew"}`, A CQ E, B CQ D; only A fires (low): dice
    queue `[4]` then `_sixes()`: A's FIRE event `aim == "high"`, `aim_ordered == "low"`, `aim_roll == 4`; exactly
    one AIM_FORCED event, ship_id `a_ship`, data `roll == 4`, `rules == ["crew"]`, `sides == [1]`, logged before
    the FIRE event; the caller's order object still has `aim == "low"`.
  - `test_low_holds_on_three`: same with queue `[3]` then sixes: FIRE `aim == "low"`, `aim_roll == 3`, no
    AIM_FORCED.
  - `test_forced_high_keeps_mgn`: the forced shot's FIRE `mgn` equals `GunneryCalculator.preview` of the original
    low order.
  - `test_one_roll_covers_both_rules`: `{"gunfire_limits": "both"}`, A CQ F, wind 1 (A's starboard to windward):
    queue `[5]` then sixes: one AIM_FORCED with `rules == ["crew", "heel"]`; exactly one d6 consumed before the
    gunnery dice (check `_dice.remaining()` against a count, or script the gunnery d6 as a distinct value and
    read it back from FIRE `d6`).
  - `test_rolls_in_firer_order`: both A and B at CQ E, both fire low: queue `[4, 1]` then sixes: A forced
    (`aim_roll` 4), B not (`aim_roll` 1); a second run with `[1, 4]`: the reverse.
  - `test_no_aim_roll_when_off`: `active_scenario = {}`, A CQ G fires low: queue `_sixes()`; the FIRE event has
    no `aim_roll` key and `d6 == 6` (the first die is the gunnery die).
  - `test_aim_forced_text`: an AIM_FORCED event (data `{"roll": 5, "rules": ["crew", "heel"], "sides": [1],
    "quality": "E"}`) `to_text({"a_ship": "HMS A"})` contains "cannot hold their aim low", "rolled 5" and
    "crew CQ E, firing to windward".
  - In `test/unit/test_fire_declaration_panel.gd`, `test_aim_note_shows_the_gunfire_limit`:
    `aim_note(false, ["crew"], "E") == "Low aim holds only on a d6 of 1–3 (14.E: crew CQ E)"`;
    `aim_note(false, ["crew", "heel"], "F")` ends with "(14.E: crew CQ F, firing to windward)";
    `aim_note(false, [], "E") == ""`; `aim_note(true, ["crew"], "E") == aim_note(true)`.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run.** `make test`. Expected: all green; the existing resolver tests are unchanged (no die is
  rolled with the switch off).
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/fire_rules.gd scripts/server/gunnery_types.gd scripts/server/gunnery_calculator.gd scripts/server/gunnery_resolver.gd scripts/server/phase_events.gd scripts/ui/fire_declaration_panel.gd test/unit/test_fire_declaration_panel.gd test/unit/test_gunfire_limits.gd test/unit/test_gunfire_limits.gd.uid
git commit -m "feat: 14.E historical gunfire limits — one d6 per firing ship forces low shots high on 4+"
```

### Task 4: 14.B surrender — state, eligibility, the order and the strike at MORALE_CHECK

**Files:**
- Create: `scripts/server/surrender_rules.gd`, `test/unit/test_surrender.gd`.
- Modify: `scripts/state/ship_state.gd`, `scripts/server/ship_state_controller.gd`,
  `scripts/server/turn_phase_controller.gd`, `scripts/server/morale_controller.gd`,
  `scripts/server/gunnery_calculator.gd`, `scripts/server/fire_rules.gd`, `scripts/server/boarding_rules.gd`,
  `scripts/server/phase_events.gd`, `scripts/server/player_view.gd`, `test/unit/test_server_authority.gd`.

**Interfaces:**
- Consumes: `OptionalRules.voluntary_surrender` (Task 1); `PhaseEvents.Type.SURRENDER` (appended in Task 3).
- Produces:
  - `ShipState` (`@export`, serialized under the same names, defaults on deserialize):
    `surrender_ordered: bool = false`, `surrenders: int = 0`, `surrendered: bool = false`, `rally_turn: int = -1`
    (Task 5 uses it); `func can_rally() -> bool: return is_struck() and surrendered`.
  - `ShipStateController` (server only, push_error on a client, emit `ship_state_changed`, return bool like
    `set_escape_declared`): `set_surrender_ordered(ship_id, on: bool)`; `record_surrender(ship_id) -> int`
    (`surrenders += 1`, `surrendered = surrenders == 1`, returns the new count; -1 for an unknown ship);
    `end_surrender(ship_id)` (`surrendered = false`); `set_rally_turn(ship_id, turn: int)`;
    `restore_from_surrender(ship_id)` (calls `set_status(ship_id, ShipState.Status.ACTIVE)`). And
    `set_status` now sets `ship.surrendered = false` whenever the new status is not `STRUCK`.
  - `class_name SurrenderRules extends RefCounted` (pure statics):
    `const SECTIONS_TO_SURRENDER := 5`, `const SURRENDER_QUALITIES: Array[String] = ["F", "G"]`,
    `const MAX_SURRENDERS := 2`;
    `static func sections_lost(ship: ShipState) -> int` (§2.2: a section counts when the type's section has
    boxes and the current one is 0; a sailor section also needs `detached_boxes[i] == 0`, the marine section
    `detached_boxes[ShipState.MARINES] == 0`);
    `static func eligible(ship: ShipState) -> bool`;
    `static func surrender_error(ship: ShipState) -> String` (§2.2 order: `ship.is_out_of_play() or not
    ship.is_on_map()` → "%s is not in play" % name; not eligible → "%s may surrender only at CQ F or G or with
    five sections lost (14.B.2): %d lost");
    `static func rally_error(ship: ShipState, turn: int) -> String` (§2.2; order: captured, `surrenders >=
    MAX_SURRENDERS`, struck but not `surrendered` ("struck for good"), not `can_rally()`, `rally_turn == turn`;
    wording in §2.2) — implemented here, used in Task 5; Task 4 adds `test_rally_error_order` covering each
    branch.
  - `TurnPhaseController.player_surrender(player_id: int, ship_id: String, on: bool = true) -> String` (§2.3
    checks and wording, through a shared helper `_surrender_request_error(player_id, ship_id, verb)` that Task 5
    reuses with "rallies"); sets `surrender_ordered`. Messages: "voluntary surrender is not used in this
    scenario (14.B)", "a ship %s in the planning phase (14.B)" (verb "surrenders" / "rallies"), "invalid player
    %d", "this player's plan is already submitted", "no ship %s", "%s is not this player's ship" (as
    `player_declare_escape`), then `SurrenderRules.surrender_error` when `on`.
  - Effects during the g-t:
    - `GunneryCalculator.preview`: after the `is_aground` refusal, `if firer.surrender_ordered: return
      _refuse(p, "a ship that is surrendering does not fire (14.B)")`.
    - `FireRules.marine_error`: after the struck check, `if firer.surrender_ordered: return "a ship that is
      surrendering does not fire (14.B)"`.
    - `BoardingRules._ba_error`: after the `NO_BOARD_QUALITIES` check, `if ship.surrender_ordered: return "a ship
      that is surrendering does not board (14.B)"`.
  - `MoraleController.resolve_surrenders(phase: int) -> void` (§2.3 steps 1–5) and
    `MoraleController.resolve_phase(phase: int) -> void` = `resolve_surrenders(phase)` then
    `resolve_checks(phase)`; `TurnPhaseController._enter_morale_check_phase` calls `resolve_phase` instead of
    `resolve_checks`. Header comment updated.
  - `PhaseEvents`: SURRENDER comment `# 14.B a ship hauls down her colours: {surrenders, permanent}`;
    `to_text`: "%s hauls down her colours (voluntary surrender, 14.B)" + "; her second surrender: she cannot
    rally again" when `permanent`; `STRIKE_REASONS["surrender"] = "she surrendered (14.B)"`.
  - `PlayerView.ship_for`: `surrender_ordered` erased for a reader of another side, beside `escape_declared`
    (update the doc comment); the other three fields stay.
  - `test_server_authority.gd` `FORBIDDEN` gains `["\\.(surrender_ordered|surrenders|surrendered|rally_turn)\\s*
    (=|\\+=|-=)[^=]", "a surrender field written from view code"]` (one regex, no spaces) and
    `["\\b(set_surrender_ordered|record_surrender|end_surrender|restore_from_surrender|set_rally_turn)\\(",
    "a surrender mutator called from view code"]` and `["\\bmorale_controller\\.", "MoraleController used from
    view code"]`, with `test_surrender_patterns_catch_mutations` (bad: `ship.surrendered = true`,
    `s.surrenders += 1`, `GameState.ship_controller.record_surrender("a")`,
    `GameState.morale_controller.rally("a", 2)`; good: `if ship.can_rally():`, `if ship.surrendered:`,
    `GameState.phase_controller.player_surrender(0, "a", true)`, `GameState.dev_commands.surrender_ship("a")`).

- [ ] **Step 1: Write the failing tests** in `test/unit/test_surrender.gd`. Fixture: two `frigate_38` ships as in
  `test_escape.gd` (`_make_ship`), `a` side 0 bow (0, 0) facing 0, `b` side 1 bow (−1, 1) facing 3;
  `GameState.active_scenario = {"optional_rules": {"voluntary_surrender": true}}`; `pc =
  GameState.phase_controller`, `pc.current_phase = PLANNING`, `pc.players_ready = {0: false, 1: false}`,
  `pc.game_result = {}`; ScriptedDice; save/restore as `test_escape.gd`. frigate_38 sections: rigging
  `[5, 5, 6, 6]`, hull `[5, 5, 5, 6]`, crew `[3, 3, 3, 3]`, marines 2.
  - `test_sections_lost_counts_every_kind`: rigging `[0, 0, 6, 6]`, hull `[0, 5, 5, 6]`, crew `[0, 3, 3, 3]`,
    marines 0 → `sections_lost == 5`; with `detached_boxes = [3, 0, 0, 0, 2]` (crew 0 and marines detached) → 3.
  - `test_eligibility` (14.B.2): CQ D with 4 sections lost → not eligible; 5 → eligible; CQ F, none lost →
    eligible; CQ G → eligible; CQ E, none → not.
  - `test_surrender_request_checks`: option off (`active_scenario = {}`) → reason contains "not used in this
    scenario"; outside PLANNING → contains "planning phase"; player 1 for `a` → contains "not this player's";
    `pc.players_ready[0] = true` → contains "already submitted"; `a` not eligible → contains "14.B.2"; struck `a`
    → contains "not in play"; eligible → "" and `a.surrender_ordered`; `player_surrender(0, "a", false)` → "" and
    the order is gone.
  - `test_surrendering_ship_does_not_fire`: `a.surrender_ordered = true` (through the request): `preview` of A's
    starboard broadside at B refuses with "surrendering"; `eligible_shots("a_id")` is empty; B can still fire at A.
  - `test_surrendering_ship_fires_no_muskets`: `FireRules.marine_error(a, b, 1)` contains "surrendering".
  - `test_surrendering_ship_sends_no_new_boarders`: `BoardingRules._ba_error(a, {}, {}, 0, "b_id")` (or through
    `task_error` with code `BoardingRules.BA`) with section 0 readied (a live BR task on section 0, as
    `test_boarding_rules.gd` builds one) → contains "does not board".
  - `test_strikes_at_morale_check` (14.B.2): order `a`; `GameState.morale_controller.resolve_phase(PHASE)`:
    `a.is_struck()`, `a.surrendered`, `a.surrenders == 1`, `not a.surrender_ordered`, `a.can_rally()`; events
    SURRENDER (`surrenders == 1`, `permanent == false`) then STRIKE (`reason == "surrender"`).
  - `test_surrender_comes_before_noted_checks`: order `a`, `a.pending_morale_checks = 1`, empty ScriptedDice:
    `resolve_phase` rolls nothing (`_dice.remaining() == 0`, no push_error), `a.surrendered`,
    `a.pending_morale_checks == 0`.
  - `test_order_lapses_if_already_out_of_play`: order `a`, then set `a` STRUCK by `damage_controller.strike(...,
    "morale", ...)`: `resolve_surrenders` logs no SURRENDER, `a.surrenders == 0`, `not a.surrender_ordered`,
    `not a.surrendered`.
  - `test_second_surrender_is_permanent` (14.B.4): `a.surrenders = 1` (set directly in the test; ACTIVE); order,
    `resolve_phase`: SURRENDER `permanent == true`, `a.is_struck()`, `not a.surrendered`, `not a.can_rally()`.
  - `test_set_status_clears_surrendered`: a surrendered `a`: `set_status(CAPTURED)` → `not a.surrendered`;
    likewise DESTROYED and ACTIVE.
  - `test_last_ship_surrender_concedes` (U): only `a` and `b`; `a` surrenders and strikes:
    `GameState.victory_controller.check(1)` has `reason == "all struck"` and `winner == 1`.
  - `test_surrender_order_hidden_from_the_enemy`: `a.surrender_ordered = true`; with limited information on
    (`tournament` absent), `GameState.player_view.ship_for(1, "a_id")` has no `surrender_ordered` key and has
    `surrenders` and `surrendered`; `ship_for(0, "a_id")["surrender_ordered"] == true`.
  - `test_surrender_fields_serialized`: round-trip `serialize` / `deserialize` keeps all four fields.
  - `test_surrender_text`: SURRENDER `to_text` contains "hauls down her colours"; with `permanent` it also
    contains "cannot rally again"; STRIKE with reason "surrender" contains "surrendered".
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Implement** per the Interfaces (invoke `phase-implementer` for the MORALE_CHECK change).
- [ ] **Step 4: Run.** `make test`. Expected: all green; `test_morale_controller.gd` unchanged.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/surrender_rules.gd scripts/server/surrender_rules.gd.uid scripts/state/ship_state.gd scripts/server/ship_state_controller.gd scripts/server/turn_phase_controller.gd scripts/server/morale_controller.gd scripts/server/gunnery_calculator.gd scripts/server/fire_rules.gd scripts/server/boarding_rules.gd scripts/server/phase_events.gd scripts/server/player_view.gd test/unit/test_server_authority.gd test/unit/test_surrender.gd test/unit/test_surrender.gd.uid
git commit -m "feat: 14.B voluntary surrender — ordered in planning, struck at the morale check"
```

### Task 5: 14.B rallying, planning after a rally, and the Developer requests

**Files:**
- Create: `test/unit/test_rally.gd`.
- Modify: `scripts/server/turn_phase_controller.gd`, `scripts/server/morale_controller.gd`,
  `scripts/server/phase_events.gd`, `scripts/server/dev_commands.gd`.

**Interfaces:**
- Consumes: Task 4's fields, mutators, `SurrenderRules.rally_error`, `_surrender_request_error`;
  `PhaseEvents.Type.RALLY` (Task 3).
- Produces:
  - `MoraleController.rally(ship_id: String, phase: int) -> Dictionary` (§2.4): `set_rally_turn(ship_id,
    game_state.phase_controller.current_turn)`; `roll := game_state.dice.d10()`; pass when `roll >=
    ship.morale_rating`: `restore_from_surrender`; fail at A–F: `set_crew_quality` one letter worse (reuse
    `QUALITY_ORDER`); fail at G: `end_surrender`. Logs RALLY `{"roll", "rating", "passed"}` plus `"quality"`
    (after a fail above G) or `"breaks": true` (at G). Returns `{"passed": bool}`.
  - `TurnPhaseController.player_rally(player_id: int, ship_id: String) -> String` (§2.4: shared checks with verb
    "rallies", then `SurrenderRules.rally_error(ship, current_turn)`, then `morale_controller.rally(ship_id,
    current_phase)`, then on a pass `_after_rally(ship)`). Returns "" when the roll was made.
  - `TurnPhaseController._store_default_course(ship: ShipState) -> void`: the body of the loop in
    `_store_default_courses` (default course when `DefaultCourse.can_move`, then the `planning_snapshot` entry);
    `_store_default_courses` resets `planning_snapshot` and calls it for each human-commanded ship.
    `_after_rally(ship)` calls it when `human_player_ids.has(game_state.commander_of(ship.ship_id))`.
  - `_auto_ready_players`: a player is auto-ready when AI, or when `in_play_ships_of_player(id)` is empty **and**
    not `_has_rallyable_ship(id)`; `_has_rallyable_ship(id) -> bool` = `OptionalRules.voluntary_surrender(
    active_scenario)` and some ship of `ships_of_player(id)` has `can_rally()` and `surrenders <
    SurrenderRules.MAX_SURRENDERS`. Update its doc comment.
  - `PhaseEvents` RALLY: comment `# 14.B.3 a surrendered ship tries to rally: {roll, rating, passed, quality |
    breaks}`; `to_text`: "%s tries to rally: rolled %d, needed %d — she rallies and fights on" / "— fails; crew
    quality drops to %s" / "— fails; she has struck for good".
  - `DevCommands.surrender_ship(ship_id: String, on: bool = true) -> String` and
    `DevCommands.rally_ship(ship_id: String) -> String`: `_refusal()` first; unknown ship → "no ship %s"; then
    the player request for `game_state.commander_of(ship_id)`; Trace on success.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_rally.gd` (Task 4's fixture; `a` MR 4; make `a`
  surrendered by ordering and `morale_controller.resolve_phase`, then set `pc.current_phase = PLANNING`,
  `pc.players_ready = {0: false, 1: false}` and `GameState.current_turn` / `pc.current_turn` to 2):
  - `test_rally_passes` (14.B.3): queue `[4]`: `player_rally(0, "a_id") == ""`, `a` ACTIVE, `not a.surrendered`,
    `a.surrenders == 1`, RALLY `passed == true`, `roll == 4`, `rating == 4`.
  - `test_rally_fails_and_lowers_quality`: CQ D, queue `[3]`: `a` still struck, `a.surrendered`, CQ `E`, RALLY
    `quality == "E"`.
  - `test_rally_fails_at_g_for_good`: CQ G, queue `[3]`: `not a.surrendered`, `a.is_struck()`, RALLY `breaks ==
    true`; a later `player_rally` in a new turn is refused ("has not surrendered" or "for good").
  - `test_one_attempt_per_turn`: queue `[3]`, rally fails; a second `player_rally` the same turn contains "this
    turn" and rolls nothing; next turn (current_turn 3) it may try again.
  - `test_rally_request_checks`: option off → "not used"; outside PLANNING → "planning phase"; wrong player;
    submitted plan; an ACTIVE ship → "has not surrendered".
  - `test_captured_ship_cannot_rally` (14.B.2): surrendered `a` set CAPTURED → refused, `not a.surrendered`.
  - `test_rallied_ship_plots_this_turn` (U): `pc.human_player_ids = [0]`, `a.speed = 2`, queue `[6]`: after the
    rally `pc.planning_snapshot.has("a_id")`, `DefaultCourse.can_move(GameState, a)` and `pc.plan_errors(0)` is
    empty; with `pc.human_player_ids = []` no snapshot entry is made.
  - `test_rally_then_second_surrender_is_permanent` (14.B.4): rally passes, then (make `a` eligible: CQ F) order
    again and `resolve_phase`: SURRENDER `permanent == true`, `not a.can_rally()`.
  - `test_rallied_ship_scores_by_sections`: after a passed rally `GameState.victory_controller.points_lost(a)` is
    less than the ship's full value (`a.ship.point_value(a.starting_crew_quality, a.original_morale_rating())`).
  - `test_rallyable_human_is_not_auto_ready`: `pc.ai_player_ids = [1]`, `a` the only ship of player 0,
    surrendered: after `pc._auto_ready_players()` `pc.players_ready[0] == false`; with the option off → true; with
    `a` struck for good (`end_surrender`) → true.
  - `test_dev_commands_reach_the_requests`: in PLANNING, `GameState.dev_commands.surrender_ship("a_id")` == ""
    for an eligible `a` (`a.surrender_ordered`); `rally_ship` on a surrendered `a` with queue `[6]` → "" and ACTIVE;
    `surrender_ship("nope")` contains "no ship".
  - `test_rally_text`: the three RALLY texts above, by data.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement** per the Interfaces (invoke `phase-implementer`: PLANNING requests).
- [ ] **Step 4: Run.** `make test`. Expected: all green.
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/turn_phase_controller.gd scripts/server/morale_controller.gd scripts/server/phase_events.gd scripts/server/dev_commands.gd test/unit/test_rally.gd test/unit/test_rally.gd.uid
git commit -m "feat: 14.B rallying — one MC in planning, a rallied ship plots this turn"
```

### Task 6: The stub AI surrenders and rallies

**Files:**
- Create: `test/unit/test_stub_ai_surrender.gd`.
- Modify: `scripts/server/stub_ai.gd`.

**Interfaces:**
- Consumes: `player_surrender`, `player_rally` (Tasks 4–5), `SurrenderRules.eligible`, `OptionalRules`.
- Produces (`StubAI`):
  - `const RALLY_CLEAR_RANGE := 5`, `const SURRENDER_ODDS_RANGE := 3`, `const SURRENDER_ODDS := 2`.
  - `static func gun_strength(ship_state: ShipState) -> int`: 0 when out of play; else max over sides 0 and 1 of
    `lg + mg + cr − guns_dismounted[side]`, at least 0 (chasers not counted).
  - `func enemy_guns_within(ship_state: ShipState, max_range: int) -> int`: the sum of `gun_strength` of the
    enemies (other side, in play, on the map) within `max_range` (footprint to footprint, as `_enemy_within`).
  - `func wants_to_surrender(ship_state: ShipState) -> bool` (§5).
  - `func wants_to_rally(ship_state: ShipState) -> bool`: `can_rally()`, `surrenders <
    SurrenderRules.MAX_SURRENDERS` and not `_enemy_within(ship_state, RALLY_CLEAR_RANGE)`.
  - `plot_all_ai_ships`: when `OptionalRules.voluntary_surrender(game_state.active_scenario)`, first
    `_rally_ai_ships()` (each AI ship, ship_id order, that `wants_to_rally`: `player_rally(commander, id)`), then
    plotting as now (after the rallies, so a rallied ship is plotted), then `_surrender_ai_ships()` (each AI ship
    in play that `wants_to_surrender`: `player_surrender(commander, id, true)`), then `assign_crew()` as now. A
    non-empty reply is appended to `refusals` as `{"ship_id", "request": "rally"|"surrender", "reason"}`.
    `assign_crew` runs after the surrender orders, so `CrewRules` drops a surrendering ship's new BA.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_stub_ai_surrender.gd` (fixture as `test_stub_ai.gd`;
  `GameState.phase_controller.current_phase = PLANNING`, `players_ready = {0: false, 1: false}`;
  `active_scenario = {"optional_rules": {"voluntary_surrender": true}}`; the AI ship is side 1, so player 1, an AI
  player in a headless game):
  - `test_gun_strength`: gun factors `{"lg": 6, "mg": 0, "cr": 4}` with `guns_dismounted = [3, 1]` → 9; struck →
    0.
  - `test_surrenders_against_two_to_one`: AI ship `s1` (side 1) CQ F, gun factors 4 LG; enemy `e0` (side 0) at
    range 2 with 10 LG: `wants_to_surrender(s1)`; `plot_all_ai_ships()` → `s1.surrender_ordered`. Enemy 7 LG
    (< 8) → not. Enemy at range 4 with 10 → not.
  - `test_surrenders_to_a_linked_boarder`: `s1` CQ G, enemy grappled to it (`ShipStateController.add_grapple`)
    with a live BR task (an entry in `crew_tasks` with code `"BR"` as `test_boarding_rules.gd` builds one), enemy
    guns weaker → wants to surrender.
  - `test_not_eligible_never_surrenders`: `s1` CQ D, no sections lost, enemy 20 LG adjacent → false.
  - `test_off_switch`: option off → `plot_all_ai_ships` orders nothing and makes no request (no refusal).
  - `test_rallies_when_clear`: `s1` surrendered (through `player_surrender` and `morale_controller.resolve_phase`,
    then PLANNING again on turn 2), no enemy within 5: ScriptedDice `[6]` (and enough further values if plotting
    rolls nothing — it does not): after `plot_all_ai_ships`, `s1` ACTIVE and plotted
    (`s1.plotted_actions.get("movement_plotted", false)` or a stored course, as `test_stub_ai.gd` checks a plot).
  - `test_no_rally_with_enemy_near`: enemy within 4 → no rally, no die rolled.
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run.** `make test`. Expected: all green; every existing AI test unchanged (the option is off).
- [ ] **Step 5: Commit.**

```bash
git add scripts/server/stub_ai.gd test/unit/test_stub_ai_surrender.gd test/unit/test_stub_ai_surrender.gd.uid
git commit -m "feat: the stub AI surrenders at 2:1 or to linked boarders, and rallies when clear (14.B)"
```

### Task 7: View-only minimum — badges, fire-panel words, Developer UI buttons

**Files:**
- Modify: `scripts/ui/planning_sail_ui.gd`, `scripts/ui/ship_status_bars.gd`, `scripts/ui/fire_declaration_panel.gd`,
  `scripts/ui/developer_ui.gd`, `test/unit/test_planning_sail_ui.gd`, `test/unit/test_fire_declaration_panel.gd`
  (and the test file of `ShipStatusBars.last_line`, if one exists; else add the test to
  `test_planning_sail_ui.gd`).

**Interfaces:**
- Consumes: Task 4–5 fields and `dev_commands.surrender_ship` / `rally_ship`.
- Produces:
  - `PlanningSailUi.status_badge`: before the `is_struck()` test, `if ship.is_struck() and ship.surrendered:
    return "SURRENDERED"`. `card_badge` adds `"SURRENDERING"` after the escape badge while
    `ship.surrender_ordered and not ship.is_out_of_play()`.
  - `ShipStatusBars.last_line`: `["Status", "Surrendered"]` for a struck ship with `surrendered`, before
    "Struck".
  - `FireDeclarationPanel`: `const NO_SHOT_SURRENDERING := "surrendering"`, `const NO_SHOT_SURRENDERED :=
    "surrendered"`; `no_shot_reason` maps a reason containing "surrendering" to `NO_SHOT_SURRENDERING` (before the
    "struck" test); `ship_no_shot_reason` returns `NO_SHOT_SURRENDERED` for a struck ship with `surrendered`
    (before `NO_SHOT_STRUCK`) and `NO_SHOT_SURRENDERING` for `surrender_ordered`.
  - `DeveloperUI`: in the ship tab, beside "Start fire" (where `fire_btn` is made, around line 281), two buttons
    "Surrender" and "Rally" connected to `_on_surrender_pressed(sid)` / `_on_rally_pressed(sid)`, written like
    `_on_start_fire_pressed` (call `game_state.dev_commands.surrender_ship(ship_id)` /
    `rally_ship(ship_id)`, `_log` the reply, emit `ship_changed` on "").

- [ ] **Step 1: Write the failing tests.**
  - `test_planning_sail_ui.gd`: `test_surrendered_badge`: a struck ship with `surrendered` → `status_badge ==
    "SURRENDERED"`; struck without → "STRUCK"; an ACTIVE ship with `surrender_ordered` → `card_badge` contains
    "SURRENDERING"; `ShipStatusBars.last_line(ship, "")` for the surrendered ship == `["Status", "Surrendered"]`.
  - `test_fire_declaration_panel.gd`: `test_no_shot_words_for_surrender`: `no_shot_reason(["a ship that is
    surrendering does not fire (14.B)"]) == "surrendering"`; `ship_no_shot_reason` for a struck surrendered ship
    is "surrendered" and for a ship with `surrender_ordered` is "surrendering" (pass `null` calculator and grid,
    as existing tests of it do, or the real ones).
- [ ] **Step 2: Run and confirm failure.** `make test`.
- [ ] **Step 3: Implement** per the Interfaces.
- [ ] **Step 4: Run.** `make test` green (including `test_server_authority.gd`).
- [ ] **Step 5: Live check** (godot-mcp, CLAUDE.md "Tooling"): `make import`, run the project (`make play`), and
  in `game_eval` turn the rule on for the running game with `GameState.active_scenario["optional_rules"] =
  {"voluntary_surrender": true}` (a debugging hook, not game code); make a ship eligible in PLANNING with
  `GameState.dev_commands.damage_ship(id, 2, 2)` repeated (or the Developer UI's Damage button), press
  Surrender (F12, ship tab), End Planning, and play to POST_COMBAT: the card reads SURRENDERED, the map shows the
  white flag and grey hull, the log has the SURRENDER and STRIKE lines; next PLANNING press Rally until it passes
  (one try a turn): the flag goes, the colours come back, the card shows a course block. `game_get_errors`
  returns zero. Note what you saw in the commit message.
- [ ] **Step 6: Commit.**

```bash
git add scripts/ui/planning_sail_ui.gd scripts/ui/ship_status_bars.gd scripts/ui/fire_declaration_panel.gd scripts/ui/developer_ui.gd test/unit/test_planning_sail_ui.gd test/unit/test_fire_declaration_panel.gd
git commit -m "feat: SURRENDERED badge, surrender words in the fire panel, Surrender and Rally in the Developer UI"
```

### Task 8: Test scenario, docs, and the final audit

**Files:**
- Create: `data/scenarios/test_optional_rules.json`, `test/unit/test_optional_rules_scenario.gd`.
- Modify: `docs/rules/feature_diff.md`, `CLAUDE.md`, `.claude/skills/scenario-creator/SKILL.md`.

**Interfaces:**
- **`test_optional_rules.json`** (schema: `.claude/skills/scenario-creator/SKILL.md`): 40 × 30 board, all edges
  open; wind from the north-east (direction 5), speed 2, steady; `sea_state` 1;
  `turn_limit` 30; `"optional_rules": {"voluntary_surrender": true, "fatigue": true, "gunfire_limits": "both"}`.
  - Side 0: `br_74` "HMS Bellona" bow (10, 12) facing 0 MS; `br_38` "HMS Arethusa" bow (10, 16) facing 0 MS. CQ C,
    MR 4.
  - Side 1: `fr_74` "Héros" bow (26, 12) facing 3 MS; `fr_38` "Sirène" bow (26, 16) facing 3 MS. CQ E (the crew
    rule bites), MR 4.
  - With the wind from 5 (NE): side 0 facing 0 is at WF C, `leeward_side(0, 5)` = STARBOARD, so its port
    (north) broadside is to windward; side 1 facing 3 is at WF B, `leeward_side(3, 5)` = PORT, so its starboard
    (north) broadside is to windward. No overlaps; everything in bounds.
- **feature_diff.md** (invoke `close-action-rules` for the conventions): §2 becomes empty, every row moved:
  - Header "Compared against": add this sub-project (`worktree-optional-rules`, `git rev-parse --short HEAD`).
  - §2.2 row "Optional rules (14)" out; §5 gains three ✔ rows: voluntary surrender and rallying (14.B.1–4:
    `surrender_rules.gd`, `turn_phase_controller.gd` (`player_surrender`, `player_rally`),
    `morale_controller.gd` (`resolve_surrenders`, `rally`), `stub_ai.gd`); fatigue (14.D.2–3: `fire_rules.gd`
    (`fatigue_penalty`), `gunnery_calculator.gd`, `ShipState.gunfire_turns`); historical gunfire limits
    (14.E.3–4: `fire_rules.gd` (`aim_limits`, `fires_to_windward`), `gunnery_resolver.gd` (`_roll_aim_limits`)),
    each "switched on by the scenario's `optional_rules`, off by default (`optional_rules.gd`)". The 14.C row stays.
  - §4 bullets: **Optional rules are scenario switches** (register §6, `start_scenario` override);
    **Surrender takes effect at the end of the g-t** (U: ordered in PLANNING, moves and may be fired on, fires no
    guns or muskets and sends no new boarders, strikes at MORALE_CHECK before the noted checks; the book has it
    take effect at once and "may not be fired upon"); **rally once a g-t, in PLANNING, rolled at once**; **in 1v1
    surrendering the last ship concedes** (U); **a surrender order is hidden from the other side until the colours
    come down** (14.C reading); **fatigue as written** (−1 from the 6th firing turn, −2 from the 16th; chasers
    included; the count runs with the rule off); **14.E: one d6 per ship per g-t covers both rules; the heel rule
    never applies to chasers; every navy; not marine fire**; **14.A** stays recorded as replaced (it is).
  - The other §2 rows move by status: the ✔ rows of §2.1 (fire and explosions, repairs, grappling, boarding,
    marine fire) and of §2.2 (acceleration reductions, 5.D.5 irons, struck ships as CQ G, crew disorganized, hull
    #10) go to §5 as one bullet each (keep their code locations; drop text §5 already has); the critical-hits row
    goes to §5 as fixed once its stale "Still missing: signalling" is checked against the code (signalling is in:
    `player_send_signal` refuses with halyards cut) — if anything is still missing, it goes to §3 instead; the
    crew-task plotting row goes to §5 (its partial list is now complete); the scattering / variable entry /
    special victory row goes to §4 as "not offered" (register §2: scattering out of scope, Scenario 12 entry
    rolls left out, no special-victory vocabulary). §2 then says: "None. Every gap the roadmap listed is built or
    recorded in §3–§4 (roadmap done, 2026-11-18)." Keep §1's headline items consistent with the moves.
- **CLAUDE.md:**
  - Turn Phase Cycle: PLANNING — `player_surrender(player_id, ship_id, on)` / `player_rally(player_id, ship_id)`
    (14.B, checks, the rally d10 rolled at once, a rallied human ship gets its default course; a rallyable human
    is not auto-ready); COMBAT_RESOLUTION — a surrendering ship does not fire, fire muskets or send new boarders;
    the 14.E aim step in the resolver; MORALE_CHECK — `morale_controller.resolve_phase()`: surrenders, then the
    noted checks.
  - Server Objects: `morale_controller` (`resolve_phase`, `resolve_surrenders`, `rally`); `gunnery_calculator`
    (`fatigue` modifier, `ShotPreview.aim_limits`); `gunnery_resolver` (14.E aim rolls, firing turns counted);
    `stub_ai` (surrender and rally policy, constants); `dev_commands` (`surrender_ship`, `rally_ship`); a new
    bullet for `OptionalRules` and `SurrenderRules` (pure statics).
  - Dice: the rally d10 (PLANNING) and the 14.E d6s (resolver step 0).
  - `ShipState` fields: `surrender_ordered`, `surrenders`, `surrendered`, `rally_turn`, `gunfire_turns`,
    `can_rally()`; `set_status` clears `surrendered`.
  - Events list: SURRENDER, RALLY, AIM_FORCED.
  - Scenarios: the `optional_rules` block and the `start_scenario` override.
  - Ship Status: a surrendered ship is STRUCK with `surrendered` (may rally), badge SURRENDERED.
  - Server Authority: the two new requests in the list of view-facing requests.
  - Known Limitations: the "Not implemented" sentence no longer names the optional rules ("every optional rule
    of 14 is in or recorded: 14.A replaced by proportional movement, 14.B, 14.C, 14.D, 14.E switched per
    scenario"); keep the rest that is still true.
- **scenario-creator skill:** document `optional_rules` (keys, values, defaults, what each does in one line, the
  `start_scenario` override) next to `tournament`, with the new scenario as the example.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_optional_rules_scenario.gd` (whole-loop driving as
  `test_ships_and_guns_scenario.gd`, every player AI, `GameState.start_scenario(s, [] as Array[int])`):
  - `test_scenario_places_cleanly`: `placement_errors().is_empty()`; `OptionalRules.of(active_scenario) ==
    {"voluntary_surrender": true, "fatigue": true, "gunfire_limits": "both"}`;
    `FireRules.fires_to_windward(0, 5, ShipState.PORT)` and `not fires_to_windward(0, 5, ShipState.STARBOARD)`;
    `fires_to_windward(3, 5, ShipState.STARBOARD)` and `not fires_to_windward(3, 5, ShipState.PORT)`.
  - `test_scenario_plays_to_the_end_cleanly`: play to game over or 30 turns with no `push_error`; assert at least
    one FIRE event with an `aim_roll` key (side 1 is CQ E); and either a FIRE event with a `fatigue` modifier or,
    if the game ended before any ship's 6th firing turn, document that in the test from the logs and assert the
    highest `gunfire_turns` seen; log (Trace) whether any SURRENDER happened.
  - The existing `test_every_scenario_places_cleanly` (`test_map_scenarios.gd`) covers the new file.
- [ ] **Step 2: Run and confirm failure.** `make import && make test`.
- [ ] **Step 3: Write the scenario file.** `make test` green.
- [ ] **Step 4: Update the docs** as the Interfaces say.
- [ ] **Step 5: Run and confirm everything passes.** `make test`; `python3
  .claude/skills/validate-rule-table/scripts/validate.py`, `validate_combat.py`, `validate_ships.py` (unchanged
  data, still OK). Then run the `scv-reviewer` agent (CLAUDE.md "SCV Audit") and fix what it finds.
- [ ] **Step 6: Commit.**

```bash
git add data/scenarios/test_optional_rules.json test/unit/test_optional_rules_scenario.gd test/unit/test_optional_rules_scenario.gd.uid docs/rules/feature_diff.md CLAUDE.md .claude/skills/scenario-creator/SKILL.md
git commit -m "docs: optional-rules scenario, CLAUDE.md, scenario skill, feature_diff §2 emptied (roadmap done)"
```
