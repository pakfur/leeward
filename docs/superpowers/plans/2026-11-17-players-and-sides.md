# Players and Sides Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split players from sides on the server, then add signalling, talking between ships, ending by agreement, limited information and AI captains that obey signals.

**Architecture:** A mechanical rename makes the ship's side honest (`side`, not `player_id`). A `PlayerState` registry and `ShipState.commander_id` then add players, and every `player_*` request checks `GameState.commands(player_id, ship_id)`. Pure statics handle signal words (`SignalText`), parsed orders (`SignalOrders`) and the per-player projection (`PlayerView`). TurnPhaseController requests and the MESSAGE_DELIVERY phase carry the state changes.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.5 (`make test`; `make import` first whenever a new `class_name` is added).

**Spec:** `docs/superpowers/specs/2026-11-17-players-and-sides-design.md`, which executors read alongside this plan. The rules are `docs/rules/close_action.md` (2.A.1, 4.A.4, 8.G.1e, 11.A–B, 14.C).

## Global Constraints

- Strict server authority. Every new mutation goes through `ShipStateController` or a `GameState` / `TurnPhaseController` server method guarded by `if not is_server: push_error(...)`. View code never writes state. `test_server_authority.gd` must pass, and is extended for each new mutator or container (`players`, `signals`, `talks`, `end_offers`, `commander_id`, `standing_order`).
- Requests return `""` or a reason string, except `player_submit_plan` and `player_end_turn`, which keep `bool`.
- All randomness goes through `game_state.dice`. Tests pin rolls with `ScriptedDice`.
- Use `Trace` and never `print()`.
- Old keys stay readable: `"player_id"` in scenario ships and in `Ship`/`ShipState` dicts, and `"controller_id"` in `ShipState` dicts. Existing scenario files are not edited for the rename.
- A scenario with no `"players"` key behaves exactly as today: one player per side, player id = side number.
- The view keeps playing as `HUMAN_PLAYER_ID = 0`, and no new UI is built.
- Word limits are 3 words; 5 for a flagship; 7 for a flagship with `gunnery_navy() == "British"` when the scenario `year` ≥ 1803. A talk message is at most 5 words.
- An AI side never offers to end the game. AI captains read full state (spec §6).
- Each task updates `CLAUDE.md` where it changes a name or API that CLAUDE.md describes. Task 11 does `feature_diff.md` and the final SCV audit.

## Review Focus

1. **An old 1v1 game must play exactly as before.** Every scenario without `"players"`, run end to end, must give the same result. `test_battle_to_victory.gd` must stay green unchanged apart from renames (Task 1, Task 3).
2. **Command can leave a player during the game, and the turn loop must not stall.** The captor's player commands a prize. A player whose last ship is captured or struck is auto-ready and is not waited on at End Turn (Task 3, test `test_player_left_with_nothing_is_not_waited_on`).
3. **Ship names in signals are more than one word.** "BREAK LINE ASTERN HMS LIVELY ." is 5 words, the same as "BREAK LINE ASTERN LIVELY .". A hyphen inside a word is refused (Task 4).
4. **A signal's sending ship can be struck after the signal is sent.** The signal is still delivered, but no new signal may be sent from that ship (Task 5).
5. **A followed leader can be lost, or can be following a ship itself.** The AI falls back to `engage` when the leader is out of play or off the map. A chain of followers still makes legal plots with no stalls into the leader's hexes (Task 10).

---

### Task 1: Rename the ship's owner to `side`

No behaviour change in this task.

**Files:**
- Modify: `scripts/state/ship.gd`, `scripts/state/ship_state.gd`, `scripts/autoload/game_state.gd`, `scripts/server/ship_state_controller.gd`, `scripts/server/phase_events.gd`, and every file under `scripts/` and `test/` that reads the renamed members.
- Modify: `CLAUDE.md`, plus `.claude/skills/scenario-creator/SKILL.md`, which documents `"player_id"` → `"side"` and keeps the alias.
- Test: create `test/unit/test_side_rename.gd`.

**Interfaces (Produces):**

| Old | New |
|---|---|
| `Ship.player_id` | `Ship.side: int` |
| `ShipState.player_id` | `ShipState.side: int` |
| `ShipState.original_player_id` | `ShipState.original_side: int` |
| `ShipState.controller_id` | `ShipState.controller_side: int` |
| `ShipStateController.set_controller(ship_id, controller_id)` | `set_controller_side(ship_id: String, side: int) -> bool` |
| `GameState.ships_by_player` | `GameState.ships_by_side` |
| `get_player_ships` | `get_side_ships(side: int) -> Array[ShipState]` |
| `get_original_player_ships` | `get_original_side_ships(side: int)` |
| `controller_of` | `side_of(ship_id: String) -> int` |
| `transfer_control(ship_id, player_id)` | `transfer_control(ship_id: String, side: int) -> bool` |
| `PhaseEvent.players` | `PhaseEvent.sides` |
| `PhaseLog.controller_of` | `PhaseLog.side_of` |
| `PhaseEvents.HUMAN_PLAYER` | `PhaseEvents.HUMAN_SIDE` |

`ShipView.owner_color(side)`, `CombatLogPanel.side_label(name, side)` and `GameOverPanel.struck_counts(ships, side)` change their parameter names only.

What stays as it is:
- `player_id` parameters of `TurnPhaseController.player_*` requests, `human_player_ids`, `ai_player_ids` and the prompt id lists. They become real player ids in Task 3.
- `StubAI` methods that take `player_ids: Array[int]` (`grapple_orders`, `ungrapple_orders`, `prize_sizes`). They are renamed `sides` here, since they filter ships by side.
- `VictoryController` result `winner`, which is a side.

- [ ] **Step 1: Write the failing test.** Create `test/unit/test_side_rename.gd` with these tests:
  - `test_ship_reads_player_id_alias`: `Ship.from_dict({... "player_id": 1 ...}).side == 1`, and the same with the `"side": 1` key.
  - `test_ship_state_reads_controller_id_alias`: `ShipState.from_dict` of a dict with `"controller_id": 0` gives `controller_side == 0`. A dict with `"controller_side": 0` gives the same.
  - `test_to_dict_writes_new_keys`: `to_dict()` has `"side"` and `"controller_side"` and no `"player_id"` or `"controller_id"`.
  - `test_scenario_ship_side_key`: `GameState.start_scenario` with one ship carrying `"side": 1` puts that ship in `get_side_ships(1)`.
- [ ] **Step 2: Run the test and confirm it fails.** Run `make import && make test`. Expected: parse errors or failures in `test_side_rename.gd`.
- [ ] **Step 3: Rename.**
  1. Rename the members in `ship.gd` and `ship_state.gd`. `from_dict` / `initialize_from_scenario` read `data.get("side", data.get("player_id", 0))` and `data.get("controller_side", data.get("controller_id", -1))`.
  2. Replace `.player_id` member reads on ships across `scripts/` and `test/`. Grep `\.player_id\b`, then check each hit: request parameters named `player_id` are not ship members and stay.
  3. Rename the GameState and PhaseEvents members listed above.
  4. Update the CLAUDE.md names and the scenario-creator skill.
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`. Expected: all tests pass, 1806 plus the new ones. Then run `grep -rn "original_player_id\|controller_id\|ships_by_player\|get_player_ships\|controller_of\b" scripts test`. Expected: only the two alias reads in `from_dict` and `initialize_from_scenario`.
- [ ] **Step 5: Commit.** `git commit -am "refactor: a ship's owner is its side (player/side split, step 1)"`. Use `git add` for the new test file first.

### Task 2: Players, commanders, flagships and groups

**Files:**
- Create: `scripts/state/player_state.gd`.
- Modify: `scripts/state/ship_state.gd`, `scripts/state/ship.gd` (flag), `scripts/server/ship_state_controller.gd`, `scripts/autoload/game_state.gd`.
- Create: `data/scenarios/test_squadron.json`.
- Test: create `test/unit/test_players.gd`.

**Interfaces (Produces):**
- `class_name PlayerState extends RefCounted` has `id: int`, `side: int`, `name: String` and `is_ai: bool`, plus `to_dict()` and `static from_dict(d) -> PlayerState`.
- `ShipState.commander_id: int = -1` is serialised as `"commander_id"`.
- `Ship.flag: String`, which is `""`, `"fleet"` or `"squadron"`, read from the scenario ship's `"flag"`. `ShipState.is_flagship() -> bool` is true when `ship.flag != ""` and the ship is not out of play. `is_fleet_flagship() -> bool` is the same test for `"fleet"`.
- `ShipStateController.set_commander(ship_id: String, player_id: int) -> bool`.
- On `GameState`:
  - `players: Dictionary` maps an int id to a `PlayerState`. `groups: Dictionary` maps a side to a Dictionary of group name → `Array[String]` of ship ids.
  - Queries: `get_player(id) -> PlayerState` (null if unknown), `players_of_side(side) -> Array[PlayerState]` sorted by id, `side_of_player(id) -> int` (−1 if unknown), `commander_of(ship_id) -> int`, `commands(player_id: int, ship_id: String) -> bool`, `ships_of_player(id) -> Array[ShipState]` sorted by ship id, `in_play_ships_of_player(id) -> Array[ShipState]` (not `is_out_of_play()`).
  - `start_scenario(scenario, human_player_ids)` builds the players (below) after the ships, and sets each `is_ai` to "not in human_player_ids".
  - Load errors (`push_error` and `start_scenario` returns false): a ship listed under two players; a player listed on a side with no ships; a ship id under a player that doesn't exist; two fleet flagships on one side.
  - With no `"players"` key, each side present gets `PlayerState(id = side, side = side, name = "Side %d")`.
  - A ship listed under no player goes to the lowest-id player of its side.
  - `groups` is read from the scenario's `"groups"` (keys are side strings), defaulting to `{}`.
- `test_squadron.json`: side 0 has players 0 (two ships, one of them `"flag": "fleet"`, British, and year 1805) and 1 (one ship). Side 1 has players 2 (two ships, one `"flag": "fleet"`) and 3 (one ship, `"flag": "squadron"`). Groups for side 0 are `"Van"` (player 0's ships) and `"Rear"` (player 1's ship). Use valid placements; `GameState.placement_errors()` must return empty.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_players.gd`:
  - `test_default_one_player_per_side`: `test_basic.json` gives `players.size() == 2`, `commands(0, <a side 0 ship>)` true and `commands(1, <that ship>)` false.
  - `test_squadron_players_and_commanders`: `side_of_player(1) == 0`, `ships_of_player(0).size() == 2`, and `commander_of(<player 1's ship>) == 1`.
  - `test_unlisted_ship_goes_to_lowest_player`.
  - `test_duplicate_ship_is_a_load_error`: `start_scenario` returns false (use `assert_push_error` or count errors as other tests do).
  - `test_two_fleet_flagships_is_a_load_error`.
  - `test_flagship_out_of_play_is_not_a_flagship`: after a strike through `DamageController.strike`, `is_flagship()` is false.
  - `test_groups_loaded`: `groups[0]["Rear"] == [<player 1's ship id>]`.
  - `test_players_serialise`: `PlayerState.from_dict(p.to_dict())` round-trips all four fields.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make import && make test`. Expected: failures in `test_players.gd`.
- [ ] **Step 3: Implement** the interfaces above. Also extend `test_server_authority.gd`: the view may not write `players`, `groups` or `commander_id`, and may not call `set_commander`.
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: players, commanders, flagships and groups`.

### Task 3: Requests by player

**Files:**
- Modify: `scripts/server/turn_phase_controller.gd`, `scripts/server/boarding_controller.gd` (`capture`, `retake`), `scripts/server/stub_ai.gd` (`_get_ai_ships` reads AI players' ships), `scripts/autoload/game_state.gd` (`start_scenario` id lists).
- Modify the view's ownership checks: `scripts/core/game_controller.gd` (`HUMAN_PLAYER_ID` checks → `GameState.commands(HUMAN_PLAYER_ID, id)`; colours and labels stay by side), and the crew overlay client, fire panel and course clicks wherever they test `side == 0` for ownership.
- Test: create `test/unit/test_player_requests.gd`.

**Interfaces:**
- Consumes `GameState.commands`, `players_of_side`, `in_play_ships_of_player` and `PlayerState.is_ai` from Task 2.
- Produces:
  - `TurnPhaseController.players_ready: Dictionary` (player id → bool, one entry per player).
  - `is_player_ready(player_id) -> bool`.
  - `_auto_ready_players()`, run at PLANNING start and at POST_COMBAT entry: every AI player, and every player with an empty `in_play_ships_of_player`, is set ready.
  - `ended_turn: Dictionary` (player id → bool). `player_end_turn(player_id) -> bool` accepts any human player with at least one in-play ship and enters END_TURN once every human with an in-play ship has ended. Players with nothing in play are not waited on.
  - Every `player_*` ownership test uses `game_state.commands(player_id, ship_id)`.
  - `plan_errors(player_id)` covers only that player's commanded ships.
  - Friend/foe in `player_submit_fire_orders` and `maintenance_options` compares `side`.
  - `bear_off_decision_requested` and `maintenance_orders_requested` carry the commanding player's id. `maintenance_options(player_id, step)` lists only that player's ships' options.
  - `capture` sets the prize's `commander_id` to the commander of `action.attacker_id`. `retake` sets it to the commander before capture (recorded as `prize["original_commander"]`). If that player has no other in-play ship, or does not exist, the lowest-id player of the side gets it.
  - `serialize`/`deserialize` of `players_ready` write and read a Dictionary, and still read the old `[bool, bool]` array.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_player_requests.gd`, all on `test_squadron.json` with humans `[0, 1]`:
  - `test_teammate_cannot_plot_anothers_ship`: `player_extend_course(1, <player 0's ship>, hex)` returns a reason, not "".
  - `test_planning_waits_for_every_player`: after `player_submit_plan(0)` the phase is still PLANNING. After `player_submit_plan(1)` it has advanced, because players 2 and 3 are AI and were auto-ready.
  - `test_end_turn_waits_for_every_human`.
  - `test_player_left_with_nothing_is_not_waited_on`: strike player 1's only ship. Then `player_submit_plan(0)` alone advances PLANNING, and `player_end_turn(0)` alone ends the turn.
  - `test_fire_orders_only_for_own_ships`: player 1 submitting an order for player 0's ship is refused.
  - `test_prize_commanded_by_captor_player`: capture through `BoardingController.capture` with an attacker that player 1 commands gives `commander_of(prize) == 1`.
  - `test_retaken_ship_returns_to_original_commander`.
  - `test_ai_ships_are_ai_players_ships`: `StubAI._get_ai_ships()` returns only player 2's and 3's ships when humans are `[0, 1]`. With humans `[0]`, player 1's ship is included.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make test`.
- [ ] **Step 3: Implement.** Keep `test_battle_to_victory.gd` and the existing 1v1 tests unchanged apart from the readiness type: where tests set `players_ready = [false, false]`, change them to `{0: false, 1: false}`.
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`. Then do a live check: `make play` via the godot MCP `run_project`. `game_get_errors` must be empty after one full turn on `test_basic` (plot, End Planning, fire, End Turn).
- [ ] **Step 5: Commit.** `feat: requests checked against the commanding player`.

### Task 4: Signal words (pure)

**Files:**
- Create: `scripts/server/signal_text.gd`.
- Test: create `test/unit/test_signal_text.gd`.

**Interfaces (Produces):**
- `class_name SignalText`, made of static functions.
- `static func words(text: String, ship_names: Array[String]) -> Dictionary` returns `{"words": Array[String], "error": String}`. It works in these steps:
  1. Upper-case the text.
  2. Split off each punctuation mark (any of `.,;:!?()"`) as a word of its own.
  3. Replace each ship name, upper-cased and with or without a leading prefix word (a first word ending in "." or listed in `PREFIXES := ["HMS", "USS"]`), with one word. Longest name first.
  4. Split the rest on whitespace.

  A word that contains `'` or `-` gives error `"%s: contractions and hyphenated words are not allowed (11.A.7)"`. Empty text gives `"Empty signal"`.
- `static func limit(ship: ShipState, year: int) -> int` returns 3 when `not ship.is_flagship()`. It returns 7 when the ship is a flagship, `ship.gunnery_navy() == "British"` and `year >= 1803`. Otherwise it returns 5. A `year` of 0 means no year.
- `const TALK_LIMIT := 5`.

- [ ] **Step 1: Write the failing tests** (11.A.6–7; the cases come from the rules book's example):
  - `words("set spacing between ships 2", [])` has 5 words, all upper case, and no error.
  - `words("BREAK ENEMY LINE ASTERN PRINCIPE DE ASTURIAS", ["Principe de Asturias"])` is 5 words.
  - With names `["HMS Lively"]`, both `"ENGAGE HMS LIVELY ."` and `"ENGAGE LIVELY ."` are 3 words: ENGAGE, the name, and ".".
  - `"CLOSE TO 5 HEXES!"` is 5 words, with the `!` counted.
  - `"DON'T FIRE"` has an error containing "11.A.7". `"MUSKET-SHOT"` errors too.
  - `limit`: a non-flagship gives 3. A French flagship in 1805 gives 5. A British flagship in 1802 gives 5. A British flagship in 1803 gives 7. A British flagship with year 0 gives 5.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make import && make test`.
- [ ] **Step 3: Implement** in `signal_text.gd`.
- [ ] **Step 4: Confirm the tests pass.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: signal word rules (11.A.6-7)`.

### Task 5: Sending and delivering signals

**Files:**
- Create: `scripts/state/signal_state.gd`.
- Modify: `scripts/autoload/game_state.gd` (`signals`, cleared on a new game), `scripts/server/turn_phase_controller.gd`, and `scripts/server/phase_events.gd` (new `Type.SIGNAL`, whose data is `{from_player, address, words}` with `ship_id` = the sending ship).
- Test: create `test/unit/test_signals.gd`.

**Interfaces:**
- Consumes `SignalText.words` / `limit` (Task 4), and `commands`, `groups` and `players_of_side` (Task 2).
- Produces:
  - `class_name SignalState extends RefCounted` has `turn`, `from_player`, `from_ship`, `address: Dictionary` (`{"kind": "fleet"|"group"|"ship", "name": String}`, where for a ship `name` is the ship id), `words: Array[String]` and `delivered: bool`, plus `to_dict`/`from_dict`.
  - `TurnPhaseController.player_send_signal(player_id: int, from_ship: String, address: Dictionary, text: String) -> String` checks, in this order:
    1. the phase is PLANNING and the plan is not submitted;
    2. `commands(player_id, from_ship)`;
    3. the ship is not out of play (11.B.2b: "Struck or dismasted ships cannot send signals");
    4. it is not dismasted;
    5. none of the player's ships `has_critical("signal_halyards_cut")` (11.B.2c);
    6. the address is valid for the player's side;
    7. `SignalText.words` gives no error;
    8. the word count is ≤ `limit(ship, int(active_scenario.get("year", 0)))`.

    On success it replaces this player's undelivered signal for the turn.
  - `player_cancel_signal(player_id) -> String`.
  - Query `signals_for(player_id: int, turn := -1) -> Array[SignalState]`: delivered signals of the player's side, all turns or one.
  - Query `pending_signal(player_id) -> SignalState`: the player's own signal this g-t, or null.
  - `ships_addressed(signal: SignalState) -> Array[String]`: the fleet means every in-play ship of the side, a group means its listed ships, a ship means that ship.
  - `_enter_message_delivery_phase` marks this turn's signals delivered, logs one `SIGNAL` event each (in `from_player` order), emits `signals_delivered(turn: int)`, and then advances.

- [ ] **Step 1: Write the failing tests** on `test_squadron.json`, with humans `[0, 1]`, in PLANNING:
  - `test_flagship_sends_seven_words_in_1805`: player 0 sends from the British fleet flagship to `{"kind":"fleet"}`; 7 words return "".
  - `test_captain_limited_to_three`: player 0 sends 4 words from its non-flagship; the reason contains "3" (the sending ship's limit). Player 1 likewise.
  - `test_halyards_cut_blocks_every_ship_of_the_player`: put the critical on player 0's non-flagship, then send from the flagship; the result is a reason.
  - `test_struck_ship_cannot_signal` and `test_dismasted_ship_cannot_signal`.
  - `test_unknown_group_refused`. `test_enemy_ship_address_refused`.
  - `test_second_signal_replaces_first`.
  - `test_refused_after_plan_submitted`.
  - `test_delivered_at_message_delivery`: before the phase, `signals_for(1)` is empty. After the turn reaches POST_COMBAT, `signals_for(1)` has player 0's signal (11.A.4: same side reads all) and `signals_for(2)` is empty.
  - `test_struck_after_sending_still_delivered`: strike the sender after a successful send and before delivery; the signal is still delivered.
  - `test_signal_event_logged`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make import && make test`.
- [ ] **Step 3: Implement.** Extend `test_server_authority.gd`: the view may not write `signals`.
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: signalling (4.A.4, 11.A-B, 8.G.1e)`.

### Task 6: Talking between ships (11.B.3)

**Files:**
- Modify: `scripts/autoload/game_state.gd` (`talks: Array`), `scripts/server/turn_phase_controller.gd`, and `scripts/server/phase_events.gd` (`Type.TALK`, data `{talk_id, from_player, words}`).
- Test: create `test/unit/test_talks.gd`.

**Interfaces (Produces):**
- A talk is a Dictionary `{id: String, turn: int, ship_a: String, ship_b: String, first_player: int, second_player: int, messages: Array}`. `ship_a` is the lower ship id, and each message is `{player, words}`.
- `_open_talks()` runs at PLANNING start, after the auto-ready step. For each pair of ships that are on map, not out of play, on the same side, commanded by different players, and whose `stern_hex()` values are neighbours (sorted by `ship_a`, then `ship_b`), it rolls one `game_state.dice.d6()`. On 1–3 the commander of `ship_a` writes first; on 4–6 the commander of `ship_b` does. The `id` is `"talk_<turn>_<ship_a>_<ship_b>"`.
- `player_send_talk(player_id: int, talk_id: String, text: String) -> String` requires:
  - the phase is PLANNING;
  - the talk is this turn's;
  - with no messages yet, only `first_player` may write; with one message, only `second_player`; with two, the reason is "The exchange is over";
  - `SignalText.words` gives no error, and the word count is ≤ `SignalText.TALK_LIMIT`.

  It logs `TALK` at once.
- Query `talks_for(player_id) -> Array` gives this turn's talks the player is in.

- [ ] **Step 1: Write the failing tests.** Build the positions in the test: put player 0's and player 1's ships stern to stern-adjacent with `ScriptedDice.queue([5])`.
  - `test_adjacent_sterns_open_a_talk`: one talk; `first_player` is ship_b's commander.
  - `test_not_adjacent_no_talk`.
  - `test_enemy_pair_no_talk`.
  - `test_same_player_pair_no_talk`.
  - `test_second_player_cannot_write_first`.
  - `test_six_words_refused`.
  - `test_one_exchange_only`: the third message is refused.
  - `test_halyards_cut_does_not_stop_talk`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make test`.
- [ ] **Step 3: Implement.** The view may not write `talks` (authority test).
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: talking between ships (11.B.3)`.

### Task 7: Ending by agreement (2.A.1)

**Files:**
- Modify: `scripts/autoload/game_state.gd` (`end_offers: Dictionary` mapping side → bool, cleared on a new game), `scripts/server/turn_phase_controller.gd`, `scripts/server/victory_controller.gd`, and `scripts/server/phase_events.gd` (`Type.END_OFFER`, data `{side, offer: bool}`).
- Test: create `test/unit/test_end_by_agreement.gd`.

**Interfaces (Produces):**
- `GameState.senior_human_player(side) -> int`, in this order:
  1. the human (`not is_ai`) commanding the in-play fleet flagship;
  2. else the lowest-id human commanding an in-play squadron flagship;
  3. else the lowest-id human of the side;
  4. else −1.
- `TurnPhaseController.player_offer_end(player_id: int, offer: bool) -> String` refuses unless `player_id == senior_human_player(side_of_player(player_id))`, and refuses once the game is over. It sets `end_offers[side]` and logs `END_OFFER`.
- `VictoryController.check(turn)` checks agreement first: when every side present has `end_offers[side] == true`, it returns `{winner, reason: "agreement", points, turn}`. The winner is the side with more points, or −1 on equal points. A side with no human never offers.

- [ ] **Step 1: Write the failing tests**:
  - `test_only_senior_human_may_offer`: in the squadron scenario with all four players human, player 1's offer is refused and player 0's is accepted.
  - `test_senior_passes_when_flagship_struck`: all four players human. Before the strike, `senior_human_player(1) == 2`. Strike player 2's fleet flagship; `senior_human_player(1) == 3` (player 3's squadron flagship). Side 0 has no squadron flagship, so striking player 0's fleet flagship leaves `senior_human_player(0) == 0` (the lowest-id human).
  - `test_game_ends_when_all_sides_agree`: both sides offer and the turn reaches END_TURN; `game_result.reason == "agreement"`.
  - `test_offer_withdrawn`: offer, then `player_offer_end(p, false)`; the game does not end.
  - `test_ai_side_never_agrees`: humans `[0, 1]`, side 0 offers, and the game continues.
  - `test_equal_points_draw`: `winner == -1`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make test`.
- [ ] **Step 3: Implement.** Also make `GameOverPanel` show `"Ended by agreement"` for that reason (text only), and if `winner == -1`, "Drawn".
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: game end by agreement (2.A.1)`.

### Task 8: Limited information (14.C)

**Files:**
- Create: `scripts/server/player_view.gd`.
- Test: create `test/unit/test_player_view.gd`.

**Interfaces (Produces):**
- `class_name PlayerView extends RefCounted`, made with `_init(game_state)`.
- `limited() -> bool` is true unless the scenario has `"tournament": true`.
- `ship_for(player_id: int, ship_id: String) -> Dictionary`:
  - For a ship the player commands, or when `not limited()`: `ship_state.to_dict()`.
  - Otherwise, the same dict with the box fields replaced. `rigging_current_hp`, `hull_current_hp`, `crew_count` and `marine_count` are removed. Added in their place: `rigging_sections_lost` and `hull_sections_lost` (sections at 0 boxes), `crew_sections_lost` (sailor sections at 0) and `marine_section_lost: bool`. Guns, crits, fires, status, position, facing, sail, speed, links and prize stay (14.C.1d, 14.C.2).
- `ships_for(player_id) -> Array[Dictionary]` covers all ships, sorted by id.
- `events_for(player_id: int, turn: int) -> Array[Dictionary]` gives the turn's events as dicts with these changes:
  - `SIGNAL` events are dropped unless the event's side is the reader's side.
  - `TALK` events are dropped unless the reader is in that talk.
  - For an event about a ship (`ship_id` or `target_id`) the reader doesn't command, its box-count fields are replaced by `{"sections_lost": n, "marine_section_lost": bool}`. Those fields are listed per type in `const BOX_FIELDS := {Type.DAMAGE: [...], Type.MARINE_FIRE: [...], Type.BOARDING_ROUND: [...], Type.BOARDING_RESULT: [...], Type.BLAST: [...], Type.PRIZE_CREW: [...], Type.DEFENCE_SPLIT: [...]}`. Read each type's data keys from `phase_events.gd`'s comments and the code that logs it. Add `sections_emptied: {"rigging": [i…], "hull": [i…], "crew": [i…]}` (section indices the event emptied; crew index 4 is the marines) to the DAMAGE event data in `DamageController`. For DAMAGE, `n` is the total of those lists and `marine_section_lost` is crew containing 4. For the other types, the listed box fields are dropped with no replacement, because their losses also appear as DAMAGE events.

- [ ] **Step 1: Write the failing tests**:
  - `test_own_ship_full`.
  - `test_enemy_ship_sections_only`: set enemy rigging `[0, 3, 6, 6]` → `rigging_sections_lost == 1` and no `rigging_current_hp` key.
  - `test_teammate_ship_also_limited` (14.C.1 "any other player").
  - `test_guns_and_crits_visible`.
  - `test_tournament_shows_all`.
  - `test_enemy_damage_event_has_no_boxes`.
  - `test_signal_event_hidden_from_enemy`.
  - `test_talk_event_only_to_talkers`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make import && make test`.
- [ ] **Step 3: Implement.** `PlayerView` is a pure query. Add a `player_view` member on GameState in `_initialize_server_controllers()`.
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: limited information projection (14.C)`.

### Task 9: Signals become standing orders

**Files:**
- Create: `scripts/server/signal_orders.gd`.
- Modify: `scripts/state/ship_state.gd` (`standing_order: Dictionary = {}`, serialised), `scripts/server/ship_state_controller.gd` (`set_standing_order(ship_id, order: Dictionary) -> bool`), and `scripts/server/turn_phase_controller.gd` (delivery applies orders).
- Test: create `test/unit/test_signal_orders.gd`.

**Interfaces (Produces):**
- `class_name SignalOrders`. `static func parse(words: Array[String], ship_ids_by_word: Dictionary) -> Array[Dictionary]` takes `ship_ids_by_word` as the upper-cased one-word ship name → id map, with and without prefix. It returns the orders in the order they appear:
  - `ENGAGE` gives `{"order":"engage"}`.
  - `ENGAGE X` or `ATTACK X`, where X is a ship name, gives `{"order":"engage","target":id}`.
  - `CLOSE TO n`, with n from 1 to 15, gives `{"order":"close","range":n}`. Out-of-range or non-numeric n is ignored.
  - `FOLLOW FLAGSHIP` gives `{"order":"follow","leader":"FLAGSHIP"}`, resolved at delivery to the side's in-play fleet flagship.
  - `FOLLOW X` gives `{"order":"follow","leader":id}`.
  - `FORM LINE` gives `{"order":"line"}`.
  - `DISENGAGE` gives `{"order":"disengage"}`.
  - Other words are ignored.
- `TurnPhaseController._apply_signal_orders(signal)` is called during delivery for each signal. It takes the last parsed order. For an `engage` target it keeps the order only if the target is an enemy. For a `follow` leader it keeps it only if the leader is a friend that is not the receiving ship itself. A kept order is set on every ship in `ships_addressed(signal)`, including human-commanded ships (information only). A `line` order also stores `"group"`: the group name, or `""` for fleet or ship addresses.
- `ShipState.current_order() -> Dictionary` returns `standing_order`. It returns `{"order":"engage"}` when `standing_order` is empty, and also when the target or leader is out of play or not on the map.

- [ ] **Step 1: Write the failing tests**:
  - A parse table covering every row above.
  - `"ENGAGE ATTACK"`, with no ship, gives `engage` with no target.
  - The last order wins: `"ENGAGE THEN DISENGAGE"` applied gives `disengage`.
  - `test_fleet_signal_sets_every_ship`.
  - `test_group_signal_sets_group_only`.
  - `test_follow_flagship_resolves_to_flagship_id`.
  - `test_order_falls_back_when_leader_struck`: `current_order().order == "engage"`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make import && make test`.
- [ ] **Step 3: Implement.** Add `standing_order` / `set_standing_order` to the authority test.
- [ ] **Step 4: Confirm the full suite passes.** Run `make test`.
- [ ] **Step 5: Commit.** `feat: signals become standing orders`.

### Task 10: AI captains steer by standing orders

**Files:**
- Modify: `scripts/server/stub_ai.gd`.
- Test: modify `test/unit/test_stub_ai.gd` (new tests).

**Interfaces:**
- Consumes `ShipState.current_order()` (Task 9).
- Produces:
  - `_get_strategy(ship)` returns `strategy_override` if it is set, else `current_order().order`.
  - New strategy methods with the same signature as `_strategy_engage(ship_state, controller, session_id, version, started) -> int`:
    - `_strategy_close`: as engage, but it scores positions by `abs(range − order.range)` toward holding that range.
    - `_strategy_follow`: aims for the hex astern of the leader's current stern, along the leader's facing, and must not end in or plot into the leader's occupied hexes.
    - `_strategy_line`: follows the ship listed before it in `order.group`'s list (by `GameState.groups`). The first ship follows the fleet flagship, or engages if it is the flagship. With no group, it follows the fleet flagship.
    - `_strategy_disengage`: maximises distance from the nearest enemy.
  - `engage` with a `target` uses that ship instead of `_nearest_enemy` when it is in play.
  - `choose_fire_orders` prefers shots at `target` when one bears.
  - All strategies end with `_meet_deceleration_minimum`, as today.

- [ ] **Step 1: Write the failing tests** in `test_stub_ai.gd`:
  - `test_close_holds_range`: with order range 5 and the enemy at 10, the plotted end is nearer range 5 than the start.
  - `test_follow_moves_toward_leader_stern` and `test_follow_never_enters_leader_hexes`.
  - `test_line_follows_previous_ship_in_group`.
  - `test_disengage_opens_range`.
  - `test_engage_target_overrides_nearest`.
  - `test_fire_prefers_ordered_target`.
  - `test_follow_chain_plots_legally`: three ships in a chain all get submitted plots, with no `CANNOT_SUBMIT`.
- [ ] **Step 2: Run the tests and confirm they fail.** Run `make test`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Confirm the full suite passes, then check it live.** Run `make test`. Then run the game with `test_squadron.json` (via the Developer UI or scenario selection) for two turns. Use `game_get_errors` and expect it to be empty. Confirm by `game_eval` that the AI ships plotted.
- [ ] **Step 5: Commit.** `feat: AI captains obey signals`.

### Task 11: Rules diff, docs and SCV audit

**Files:**
- Modify: `docs/rules/feature_diff.md`, `CLAUDE.md`, `.claude/skills/scenario-creator/SKILL.md`.

- [ ] **Step 1: Update `feature_diff.md`**, following the close-action-rules skill's "Keeping feature_diff.md current".
  - Move these from §2 to §5, with rule numbers and code names: signalling (4.A.4, 11.A, 11.B.1–2, 8.G.1e), flagships, signal halyards cut (11.B.2c), talking between ships (11.B.3), game end by agreement (2.A.1), and limited information (14.C).
  - Add these to §4: content not checked (11.A.7, the players' honour); lower case accepted and upper-cased; talk friendly-only; senior human casts the side's vote; an AI side never agrees; AI captains see full state; signals parsed into AI standing orders (an addition).
  - Set the header commit.
- [ ] **Step 2: Update `CLAUDE.md`**: the GameState players section, the requests list under Server Authority, the MESSAGE_DELIVERY phase (no longer a stub), the scenario schema line, and the "Not implemented: signalling" line. Update the scenario-creator skill's schema (`players`, `groups`, `flag`, `side`, `tournament`).
- [ ] **Step 3: Confirm the suite passes.** Run `make test`. Run both validators: `python3 .claude/skills/validate-rule-table/scripts/validate.py` and `validate_combat.py`.
- [ ] **Step 4: Run the `scv-reviewer` agent on the branch.** Fix any violations and re-run `make test`.
- [ ] **Step 5: Commit.** `docs: players and sides in feature_diff and CLAUDE.md`.
