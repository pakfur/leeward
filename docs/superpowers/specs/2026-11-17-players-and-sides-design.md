# Players and sides: design

Date: 2026-11-17. Sub-project 2 of `2026-11-16-feature-gap-roadmap-design.md`. Status: draft for approval (builder check done 2026-11-17).

## Intent

Today a "player" and a "side" are the same number (0 or 1). Networked 1v1 and team PVP, the end goal, needs them apart: a **side** wins or loses and decides who is friendly; a **player** commands some of a side's ships, gives their orders, sees what a captain could see, and signals. This sub-project builds that split and the rules that hang on it, **on the server only**. The UX comes later (user, 2026-11-17).

**Why signalling at all (user).** Players are free to use any out-of-game comms they like. In-game signalling exists to give the feel of the limited information a sea captain had. Between players of one side it follows the existing rules (chapter 11). AI captains obey a small set of signals, so a human admiral can lead AI captains.

## Goals

1. Separate player from side throughout the server: every request is validated against the requesting **player**; friend-or-foe, victory and prizes go by **side**.
2. Scenarios name the players of each side, the ships each commands, flagships and ship groups. A scenario without them gets one player per side (today's behaviour).
3. Signalling (4.A.4, 11.A, 11.B.1–2, 8.G.1e) with the word limits, the address groups and the halyards-cut, struck and dismasted bans.
4. Talking between ships (11.B.3).
5. Game end by agreement (2.A.1).
6. Limited information (14.C) as a per-player projection of the game state, switched off by a scenario's tournament flag.
7. AI captains turn signals addressed to them into standing orders and steer by them.

## Non-goals

- Networking, transport, lobbies, per-client state sync.
- Any UI for signals, talking, ending by agreement or player selection. The current view keeps playing as player 0 on side 0 against the AI.
- Moving the view's enemy reads onto the limited-information projection (that goes with the UX work; see "Left for later").
- AI admirals that write signals. AI players send none.
- Checking signal *content* (11.A.7: no hex numbers, no MPs, no plot references). The server cannot judge it; it is left to the players' honour (`feature_diff.md` §4).

## Anti-goals

- A second kind of signal (typed orders) next to the text. There is one kind: text, within the rules' limits.
- "player_id" that still means "side" anywhere after this work.
- A team rule that lets one player act for another's ships.

## Constraints

- Strict server authority (CLAUDE.md, memory): new player actions are new server request methods returning "" or a reason; `test_server_authority.gd` keeps passing and is extended to the new state.
- All dice through `game_state.dice`.
- Existing scenarios, saves of `ShipState.to_dict` and the 1806 tests keep working (tests change only where names change).
- `docs/rules/feature_diff.md` and `CLAUDE.md` updated in the same changes.

## Approaches (chosen by the user, 2026-11-17)

**Splitting player from side.**
- A. Keep `ShipState.player_id` meaning the side, add `commander_id`. Small diff, but "player_id" keeps meaning "side" in ~200 places.
- **B (chosen).** Mechanical rename first (ship-level `player_id` → `side`, `ships_by_player` → `ships_by_side`, …), then add players. Large but mechanical; honest names afterwards.
- C. A full identity/session model. Premature before networking.

**How AI captains understand signals.**
- **A (chosen).** Signals are plain text; the server reads a small set of phrases out of any signal and turns them into standing orders for the AI captains it is addressed to. One signal works for human and AI captains alike.
- B. Typed order signals beside the text. Easier to parse, but not in the rules and two things for the UI to offer.

## Design

### 1. The rename (first change, no behaviour change)

| Before | After |
|---|---|
| `Ship.player_id` (scenario owner) | `Ship.side` |
| `ShipState.player_id` (controlling side: captor once a prize) | `ShipState.side` |
| `ShipState.original_player_id` | `ShipState.original_side` |
| `ShipState.controller_id` (captor side, −1 = owner) | `ShipState.controller_side` |
| `GameState.ships_by_player`, `get_player_ships`, `get_original_player_ships`, `controller_of`, `transfer_control(ship, player)` | `ships_by_side`, `get_side_ships`, `get_original_side_ships`, `side_of`, `transfer_control(ship, side)` |
| `PhaseEvent.players` | `PhaseEvent.sides` |
| `PhaseEvents.HUMAN_PLAYER`, `ShipView.owner_color(player_id)`, combat log / game-over / minimap side labels | keyed by side |
| `VictoryController` result `winner` | a side (unchanged value) |

Serialised dicts read the old keys as aliases (`player_id`, `controller_id`) so older saves and the scenario files load. Scenario ship entries may say `"side"`; `"player_id"` stays accepted. Request parameters named `player_id` keep the name: after step 2 they really are players.

### 2. Players

New `PlayerState` (`scripts/state/player_state.gd`, pure data): `id: int`, `side: int`, `name: String`, `is_ai: bool`. Which ships a player commands is stored once, in `ShipState.commander_id`; `GameState.ships_of_player(id)` derives the list (my call: one source of truth, so a later command transfer needs only `ShipStateController.set_commander`).

`GameState`:
- `players: Dictionary` (id → `PlayerState`), `get_player(id)`, `players_of_side(side)`, `side_of_player(id)` (−1 unknown).
- `commander_of(ship_id) -> int` and `commands(player_id, ship_id) -> bool`, the single ownership test every request uses.
- `ShipState.commander_id: int` (−1 = none), mutated only through `ShipStateController`.

Scenario schema (additions, all optional):

```json
"players": [
  {"id": 0, "side": 0, "name": "Admiral", "ships": ["victory", "temeraire"]},
  {"id": 1, "side": 0, "name": "Captain", "ships": ["neptune"]},
  {"id": 2, "side": 1, "name": "Villeneuve", "ships": ["bucentaure", "redoutable"]}
],
"groups": {"0": {"Van": ["victory", "temeraire"], "Rear": ["neptune"]}}
```

Per ship: `"flag": "fleet"` or `"squadron"` (fleet flagship / subordinate flagship, the scenario book's markings; at most one fleet flagship per side). Without `"players"`, each side gets one player whose id equals the side number and who commands all its ships. A ship listed under no player goes to the lowest-id player of its side; a ship listed twice, or a player on a side with no ships, is a load error.

`GameState.start_scenario(scenario, human_player_ids)` now takes **player** ids; every other player is AI (`PlayerState.is_ai`). `TurnPhaseController.human_player_ids`, `ai_player_ids`, `bear_off_prompt_player_ids`, `maintenance_prompt_player_ids` hold player ids.

Requests (all of `player_*`): the ship check becomes `game_state.commands(player_id, ship_id)`. **Mixed sides.** A side may have human and AI players (a human admiral with AI captains is the point of §7). The view plays as player 0 and its ownership checks (`GameController`, `CourseClicks`, crew overlay, fire panel, prompts) move to `commands(HUMAN_PLAYER_ID, ship_id)` now, so AI teammates' ships are shown as friendly but not editable; colours and "yours"/"enemy" labels stay by side.

**Players with nothing to command.** A player who commands no ship in play (all struck, destroyed or captured, or none left; a dismasted ship still plots crew and fires, so it counts) stays in `players`, can still read signals, and is ready automatically at PLANNING and at End Turn, so the turn loop never waits on them.

Side-wide actions stay per player: `players_ready` becomes a `Dictionary` player id → bool, and the phase advances when every player is ready (AI players are ready at PLANNING start, as now). Fire orders, bear-off, maintenance orders and End Turn are per player, each covering that player's ships. `player_end_turn` waits for every human player (today it accepts player 0 only). Prompts (`bear_off_decision_requested`, `maintenance_orders_requested`) go to the commanding player. Friend-or-foe in the fire, grapple and boarding code compares `side`.

**Prizes.** A prize is commanded by the player who commands the ship whose boarders took it (`BoardingAction` attacker); a retaken ship goes back to its original commander, or to the lowest-id player of its side if that player commands nothing any more. Victory points stay per side by original side.

### 3. Signals (4.A.4, 11.A, 11.B.1–2, 8.G.1e)

State: `Signal` (`scripts/state/signal_state.gd`): `turn`, `from_player`, `from_ship`, `address` (`{"kind": "fleet"|"group"|"ship", "name": …}`), `words: Array[String]`, `delivered: bool`. `GameState.signals: Array` (all turns, kept for history).

Request: `TurnPhaseController.player_send_signal(player_id, from_ship, address, text) -> String` ("" or a reason). Allowed in PLANNING until that player's plan is submitted; a second call the same g-t replaces the first (one signal per player per g-t, 11.B.2). `player_cancel_signal(player_id)` withdraws it. Checks:
- `from_ship` is commanded by the player and is neither out of play nor dismasted (11.B.2b);
- none of the player's ships has `signal_halyards_cut` (11.B.2c);
- the address is the player's own side's fleet, one of its scenario groups, or one of its ships (11.A.5);
- the word count is within the limit of the sending ship (a flagship that is out of play is not one; she cannot send anyway): 3 words; 5 for a flagship; 7 for a British-navy flagship (`gunnery_navy() == "British"`) when the scenario `year` ≥ 1803 (11.A.6; no year = 5);
- words (11.A.7): the text is upper-cased (playability: no refusal for lower case); each punctuation mark is a word of its own; a ship name of the scenario counts as one word however many it has, matched with or without a leading prefix ("HMS LIVELY" or "LIVELY"; the prefix is a first word in capitals or ending in a full stop, such as HMS or USS; my call, ship ids are not accepted); numbers are words; a word with an apostrophe or a hyphen inside it is refused ("contractions and hyphenated words are not allowed").

Delivery: `MESSAGE_DELIVERY` stops being a stub. It marks the g-t's signals delivered and emits `signals_delivered(turn)`; logs a `SIGNAL` event per signal (visible to the sending side only, see §6). Every player of the side may read every delivered signal of the side (11.A.4): query `signals_for(player_id, turn := -1)`. A signal sent from a ship that strikes or is dismasted later the same g-t is still delivered (my call: it was written in the Plot Phase).

In 1v1 (one player per side) signalling has nothing to do but is not switched off; halyards cut still blocks a signal, which is the only effect 11.A.2 leaves.

### 4. Talking between ships (11.B.3)

At PLANNING start the server finds pairs of **friendly** ships commanded by **different** players whose sterns are adjacent (`stern_hex()` neighbours) and opens a talk for each (`GameState.talks`: `{turn, ship_a, ship_b, first_player, messages: []}`). A d6 (via `game_state.dice`, in ship-id order of the pairs) picks who writes first. My call: only friendly ships talk; 11.A.3 leaves talking to the enemy unrestricted, so in-game talk to the enemy adds nothing. Talks open only between ships whose commanders are both human players; AI captains do not talk (ruling 2026-11-17).

Request: `player_send_talk(player_id, talk_id, text) -> String`. The first writer sends one message of at most 5 words (same word rules as §3), shown at once (not held to end of g-t), then the other replies once; nothing more. Halyards cut does not stop talking (it is shouting across, not flags). A talk not used by the end of PLANNING lapses. Query `talks_for(player_id)`.

### 5. Ending by agreement (2.A.1)

Request `player_offer_end(player_id, offer: bool) -> String`. One vote per side (user-approved): the side's vote is cast by its **senior human player** (my call): the human commanding the fleet flagship, else the lowest-id human commanding a squadron flagship, else the lowest-id human of the side; flagships that are out of play do not count. A side with no human player never agrees, so a game against the AI ends only by the other conditions; all-human sides decide among themselves. When every side's senior player has offered by END_TURN, `VictoryController` returns `{winner, reason: "agreement", points, turn}`, the winner by points (draw when equal, `winner = -1`). An offer stands until withdrawn.

### 6. Limited information (14.C)

New pure class `PlayerView` (`scripts/server/player_view.gd`): `ship_for(player_id, ship_id) -> Dictionary` and `ships_for(player_id) -> Array`. For a ship the player commands, everything. For any other ship (enemy **or friendly**, 14.C.1 says "any other player"), when limited information is on:
- rigging: sections lost (0–4), not boxes; hull: the same; crew: sailor sections lost and whether the marine section is lost;
- guns: all gun data (BGN inputs and modifiers, guns dismounted), 14.C.1d;
- everything else a captain would see or ask for, 14.C.2: position, facing, sail state, speed, status, fires, fouled/grappled, critical effects, prize flag.

Another ship's plotted actions are hidden from players who do not command her (ruling 2026-11-17).

`PlayerView.events_for(player_id, turn)` filters the turn log by one rule (my call): any event field that counts boxes (rigging, hull, sailor or marine) of a ship the reader does not command is replaced by the sections lost by that event, with a marine-section flag (this covers DAMAGE, MARINE_FIRE, BOARDING_ROUND, BOARDING_RESULT, BLAST, PRIZE_CREW, DEFENCE_SPLIT and any later event; each event type declares its box fields in one table in `PlayerView`); everything else (crits, repairs, morale, crew tasks, fires) is shown, 14.C.2. `SIGNAL` events go only to the sending side; `TALK` events only to the two players talking; `END_OFFER` to everyone. Scenario `"tournament": true` turns limited information off (14.C.3); the default is on. My call: on by default, since giving a captain's view is the point (user's intent).

The current view does not use `PlayerView` yet (non-goal). Its tests pin the projection.

**AI captains see everything (user, 2026-11-17).** `StubAI` keeps reading full `ShipState` for targeting, boarding odds and positioning; limited information binds human players only, for now. Recorded in `feature_diff.md` §4 as a known exception.

### 7. AI captains obey signals

New pure `SignalOrders.parse(words, scenario_ship_names) -> Array[Dictionary]` reads these phrases anywhere in a signal (other words are ignored):

| Phrase | Standing order |
|---|---|
| `ENGAGE` | `{"order": "engage"}` (today's default strategy) |
| `ENGAGE <ship>` / `ATTACK <ship>` | `{"order": "engage", "target": id}` (an enemy ship) |
| `CLOSE TO <n>` | `{"order": "close", "range": n}` (hold within n hexes of the nearest enemy, 1–15) |
| `FOLLOW FLAGSHIP` / `FOLLOW <ship>` | `{"order": "follow", "leader": id}` (a friendly ship; sail in her wake) |
| `FORM LINE` | `{"order": "line"}` (follow the next ship ahead in the addressed group's listed order; the first follows the flagship, or engages if she is the flagship) |
| `DISENGAGE` | `{"order": "disengage"}` (open the range from the nearest enemy) |

At delivery each AI-commanded ship the signal reaches (fleet = all the side's ships, a group = its ships, a ship = that ship) replaces its standing order with the last order parsed (`ShipState.standing_order`, through `ShipStateController`). No order, an order whose target or leader is gone (out of play or off the map), or no signal yet: `engage`. A human captain's ships get the order too, as information only. `StubAI._get_strategy` reads the standing order; new strategies `follow`, `line`, `close`, `disengage` plot through the existing session protocol and keep the deceleration and turning rules. Fire, boarding and grapple choices are unchanged except that `engage <ship>` prefers that target when it can be fired on.

### 8. Rules book cross-reference and docs

`feature_diff.md`: the signalling, flagship, 11.B.3, 2.A.1 agreement and 14.C rows move to §5 (or §3 where a call above differs), the content-check honour rule and the friendly-only talk and the AI-never-agrees call go to §4. `CLAUDE.md`: the "Not implemented: signalling" line, the GameState/TurnPhaseController sections and the scenario schema (also `scenario-creator` skill).

## Testing

- The rename lands with the whole suite green and no behaviour change.
- New scenario `data/scenarios/test_squadron.json`: two players per side, three ships each side, flagships and groups.
- Headless tests: ownership refusals across players of one side; readiness waits for every player; prompts reach the commanding player; prizes' commander; each signal check (word counts by flag and year, punctuation, multi-word ship names, hyphen refused, halyards, struck, dismasted, wrong address, outside PLANNING, replace); delivery in MESSAGE_DELIVERY and side-only reading; talk opening (stern adjacency, d6 via `ScriptedDice`), order and limits; agreement (senior player, all sides, AI never, points winner, draw); `PlayerView` for own/friendly/enemy, tournament off; `SignalOrders.parse` table; each AI strategy produces a legal plot that moves the right way.

## Left to the builder

- Internal structure of `SignalOrders` and the new AI strategies, within the phrase table.
- Exact event field names for `SIGNAL`, `TALK` and `END_OFFER`.
- Order of the rename commits.

## Left for later

- UI: sending/reading signals, talk, end offer, player selection, a hot-seat or networked client.
- The view reading enemy ships through `PlayerView` (and the authority test that enforces it).
- AI admirals writing signals; an AI side ever agreeing to end.
- AI captains playing from `PlayerView` instead of full state.
