# Board Planning, Piece 4 (Side Panel as Status and Players) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The side panel becomes one persistent panel for the whole turn: a **Players** roster (every player, human or AI, their side colour and what they are doing: planning, ready, resolving, ending turn) and **Your ships** status cards (with the Plan/Done / FIRE pills), with a footer that changes by phase (End Planning + Cancel, Fire, End Turn). The resolution panel still takes the side panel during a replay and hands it back.

**Architecture:** View only, no server change. A pure `RosterRows.rows(...)` turns read-only game state into roster rows; a `FleetPanel` Control holds the roster, the existing ship cards (`ShipListItem`) and a footer slot; GameController puts it in the `ContextPanel` once per game and swaps only the footer as phases change, instead of building `PlanningPhaseUI`, `FireStepPanel` and the End Turn box as separate contents.

**Tech Stack:** Godot 4.6 GDScript, GUT 9.5, godot-mcp.

**Spec:** `docs/superpowers/specs/2026-11-18-board-planning-design.md` (Piece 4). Pieces 1–3 (merged) built the board planning (CLAUDE.md "Board Planning"), the Orders ring, the fire step on the board (`FireStepPanel`, `FireOrdersModel`).

## Global Constraints

- No server change. Reads: `GameState.player_ids()`, `GameState.players` (PlayerState: id, side, name, is_ai), `phase_controller.is_player_ready(id)`, `phase_controller.ended_turn` (POST_COMBAT), `phase_controller.current_phase` / `combat_step`, the local `ResolutionReplay.resolving`, `ships_of_player`. Requests unchanged: `player_submit_plan`, `player_reset_planning`, `player_submit_fire_orders`, `player_end_turn`.
- Roster states: PLANNING → "planning" / "ready" (`is_player_ready`); fire declaration → "declaring" / "ready" (a player whose orders are in, as the server reports it; AI players "ready"); while the local replay runs, the local player "resolving"; POST_COMBAT → "reviewing" / "ended turn" (`ended_turn`); other phases "waiting". Other players never show "resolving" (networking will report it later). A player with no ship in play shows "no ships".
- The footer per phase keeps today's buttons, texts and enabling rules exactly (End Planning + Cancel with the "still in Plan" line; Fire with the hold-fire line; End Turn with "Review the combat log, then end the turn."), and Space/Enter keep their meanings.
- Clicking a card selects the ship and pans to her (`pan_to_if_needed`), and in PLANNING / the fire step opens her ring (pieces 1 and 3 behaviour).
- The resolution panel takes the side panel during a replay; when the replay ends the FleetPanel comes back with the footer of the phase then current.
- Strict server authority; Trace; `@warning_ignore` on the line; `make import`, commit `.uid`; fonts by `theme_type_variation`.
- Update CLAUDE.md (Planning Panel → the fleet panel; Board Planning; Resolution Replay's hand-back) at the end.

## Review Focus

1. Every phase's footer behaves exactly as before (enabling, texts, Space/Enter, Cancel's confirmation, refusals shown).
2. The roster never shows a state the local client cannot know (another player's replay).
3. The panel survives a replay, a reset (Developer UI), a new game and leaving without orphaned Controls or stale cards (a captured, destroyed or escaped ship's card updates or leaves).
4. A ship taken as a prize by the player joins "Your ships"; one lost as a prize leaves.
5. The maintenance prompt and bear-off (resolution panel steps) still take the side panel and hand it back.

---

### Task 1: `RosterRows` and the roster Control

**Files:**
- Create: `scripts/ui/fleet/roster_rows.gd` (`class_name RosterRows`, pure statics), `scripts/ui/fleet/player_roster.gd` (`class_name PlayerRoster extends VBoxContainer`)
- Test: `test/unit/test_roster_rows.gd`

**Interfaces:**
- Produces: `RosterRows.rows(game_state, local_player_id: int, local_resolving: bool) -> Array[Dictionary]` — one row per player id in order: `{id, name, side, is_ai, is_local, state: String, ships: int}` (state per Global Constraints; `name` falls back to "Player n" and the local one reads "You"); `RosterRows.state_label(state) -> String`; `PlayerRoster.show_rows(rows: Array) -> void` (a row: side colour dot (`ShipView.owner_color` by side relative to the local player), name, "AI" tag, state at the right).
- [ ] **Step 1: Failing tests:** `test_planning_states`, `test_fire_declaration_states`, `test_local_resolving_only`, `test_post_combat_states`, `test_no_ships`, `test_ai_tag_and_local_name`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: player roster rows`.

### Task 2: `FleetPanel`

**Files:**
- Create: `scripts/ui/fleet/fleet_panel.gd` (`class_name FleetPanel extends VBoxContainer`) (+ scene if the project's panels use scenes)
- Modify: `scripts/ui/planning_phase_ui.gd`, `scripts/ui/board_planning/fire_step_panel.gd` (their card lists and footers move into FleetPanel; keep or reduce these files to footer builders — say which), `scripts/ui/ship_list_item.gd` only if needed
- Test: `test/unit/test_fleet_panel.gd`; existing `test_planning_phase_ui.gd` / fire step panel tests updated (say which)

**Interfaces:**
- Produces: `FleetPanel.setup(local_player_id: int) -> void`, `refresh_roster(rows: Array) -> void`, `refresh_ships(ships: Array[ShipState]) -> void` (adds, updates and removes cards by ship id), `set_footer(control: Control) -> void` (`null` clears), `select_ship(ship_id)`; `signal ship_card_pressed(ship_id)`, plus the cards' existing signals forwarded (crew overlay, pill toggled).
- Layout: Players (roster), Your ships (cards, scrolling), footer pinned at the bottom.
- [ ] **Step 1: Failing tests:** `test_cards_added_updated_removed`, `test_footer_swaps`, `test_card_press_signal`, `test_roster_shown`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: fleet panel for the side panel`.

### Task 3: One side panel for the turn

**Files:**
- Modify: `scripts/core/game_controller.gd` (where PLANNING, the fire step and POST_COMBAT set the context content; the replay hand-back; game over keeps its own card), anything else that set side-panel content per phase
- Test: GameController-level tests for the footers per phase and the replay hand-back (update existing ones)

**Behaviour:**
- On game start: FleetPanel into the context panel (title "Your Fleet" or the phase title as today), roster and cards filled.
- Phase changes swap only the footer: PLANNING → End Planning + Cancel + "still in Plan" line; fire step → Fire + hold-fire line; POST_COMBAT → End Turn; other phases → no footer (or a status line).
- Roster refresh on `phase_changed`, readiness changes (submit, end turn), replay start/end; cards refresh on `_sync_all_views`-time changes (damage, capture, escape, destroyed).
- A replay (and its prompt steps) puts the resolution panel in; on drain the FleetPanel returns (re-added, not rebuilt from scratch if it can be kept; otherwise rebuilt) with the current footer.
- [ ] **Step 1: Failing tests:** `test_footer_per_phase`, `test_replay_hands_panel_back`, `test_prize_joins_your_ships`, `test_reset_rebuilds_panel` (Review Focus 1, 3, 4, 5).
- [ ] **Step 2–4:** implement; `make test` passes.
- [ ] **Step 5:** commit `feat: one side panel for the whole turn`.

### Task 4: Live check, docs, SCV

- [ ] **Step 1:** Run with the godot MCP through two full turns of `test_fleet` (planning, movement, fire on the board, the replay, End Turn) and `test_prizes` (a capture changes Your ships); a Developer UI reset; check Review Focus 1–5. `game_get_errors` zero. Screenshots `p4_planning.png`, `p4_fire.png`, `p4_post_combat.png` to the scratchpad `shots/`.
- [ ] **Step 2:** CLAUDE.md: replace the Planning Panel section with the fleet panel; Board Planning and Resolution Replay hand-back.
- [ ] **Step 3:** `scv-reviewer`; fix; `make test`; commit.
