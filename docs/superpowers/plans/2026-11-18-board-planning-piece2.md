# Board Planning, Piece 2 (Orders Ring and Signal Composer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The ship's radial menu gets an **Orders** ring (cast the lead, declare escape, surrender, rally) and a **Signal** item with a small composer, the first player controls for those requests; each item is greyed with the server's reason when it cannot be given.

**Architecture:** One new read-only server query, `TurnPhaseController.order_options(player_id, ship_id)`, answers what each order may be (and why not) using the same checks as the requests (refactored into shared helpers, so query and request can never disagree). The view (`BoardPlanning`) builds the Orders ring and the Signal item from it and sends the existing requests. A `SignalComposer` Control by the ship writes and sends a signal.

**Tech Stack:** Godot 4.6 GDScript, GUT 9.5, godot-mcp.

**Spec:** `docs/superpowers/specs/2026-11-18-board-planning-design.md` (Piece 2). Piece 1 (merged, 6ea1d44) built `RadialMenu`, `RadialItem`, `PlanChecklist`, `PlanBadges`, `BoardPlanning`, `CourseChips` in `scripts/ui/board_planning/` (see CLAUDE.md "Board Planning").

## Global Constraints

- Requests used, unchanged in behaviour: `player_set_cast_lead`, `player_declare_escape`, `player_surrender`, `player_rally`, `player_send_signal`, `player_cancel_signal`; queries `pending_signal`, `course_options`, `plan_errors`. One new read-only query: `order_options`. No other server change except refactoring the requests' existing checks into helpers the query shares (behaviour identical: their existing tests stay green unchanged).
- The view shows the server's reasons verbatim; it never re-derives an order's eligibility.
- Items not used by the scenario are hidden, not greyed: Declare escape when the scenario gives her side no escape (`MapRules.permission` empty); Surrender and Rally when 14.B is off (`OptionalRules.voluntary_surrender`); Rally unless she has surrendered (`ShipState.surrendered`).
- A surrendered ship (STRUCK by 14.B) has a ring with Rally (and nothing that needs her in play); her pill reads SURRENDERED.
- Strict server authority; Trace; `@warning_ignore` on the line; `make import` and commit `.uid`/`.import` files; fonts by `theme_type_variation`; no keyboard focus on ring items.
- Update CLAUDE.md (Board Planning section) at the end; no `feature_diff.md` change.

## Review Focus

1. Every greyed reason equals the string the request returns when tried (test on fixtures for each order).
2. Cast the lead on a course over 2 MP, then shortening it: the lead item enables; lengthening a course with the lead on: the server refuses End Planning (`plan_errors`), and the chip box shows it.
3. Declaring escape changes which hexes Move offers at the edge (course redrawn at once).
4. A rally is a die roll at the moment of the request: its result (pass/fail, the roll) is shown to the player at once, and a ship that rallied joins planning (Plan, with her default course), one that failed stays surrendered.
5. The Signal composer with the halyards cut, a dismasted ship, an address with no ship, a text over the limit, and a pending signal: each refused or greyed with the server's reason; the pending signal can be cancelled.

---

### Task 1: `order_options` query

**Files:**
- Modify: `scripts/server/turn_phase_controller.gd` (extract the checks of `player_set_cast_lead`, `player_declare_escape`, `player_surrender`, `player_rally`, `player_send_signal` (the per-ship part: halyards, dismasted, out of play) into private `_lead_error`, `_escape_error`, `_surrender_error`, `_rally_error`, `_signal_ship_error`; the requests call them)
- Test: `test/unit/test_order_options.gd`

**Interfaces:**
- Produces: `func order_options(player_id: int, ship_id: String) -> Dictionary` (read-only; `{}` for an unknown ship or one the player does not command):
  `{"lead": {"on": bool, "error": String}, "escape": {"shown": bool, "on": bool, "error": String}, "surrender": {"shown": bool, "on": bool, "error": String}, "rally": {"shown": bool, "error": String}, "signal": {"error": String, "pending": Dictionary, "limit": int, "addresses": Array}}`.
  - `lead.error`: the request's refusal for `on` = not current state; plus, when turning it on, "Only with a course of 2 MP or less" when the stored course is over 2 MP (the reason `plan_errors` gives — reuse that string).
  - `escape.shown` = the side has an escape permission; `escape.error` = the request's refusal (turn window, plan submitted, …).
  - `surrender.shown` = 14.B on and not surrendered; `rally.shown` = 14.B on and `ship.surrendered`.
  - `signal.pending` = `pending_signal(player_id).to_dict()` or `{}`; `limit` = `SignalText.limit(ship, year)`; `addresses` = `[{"kind": "fleet", "name": ""}]` + one per group of her side (`GameState.groups`) + one per own-side ship in play on the map (`{"kind": "ship", "name": ship_id}`), each with a display `label`.
- [ ] **Step 1: Failing tests:** for each order, a fixture where it is allowed (`error == ""`) and one or more where it is refused, asserting `error` equals the request's return value when the request is then tried on a copy of the same state (or tried and the state checked unchanged); `test_hidden_when_scenario_has_none` (escape, surrender, rally); `test_signal_addresses_and_limit`; `test_read_only` (calling it changes no ship field and logs nothing).
- [ ] **Step 2–4:** implement; `make test` passes (existing request tests unchanged).
- [ ] **Step 5:** commit `feat: order_options query for the orders ring`.

### Task 2: Orders ring

**Files:**
- Modify: `scripts/ui/board_planning/board_planning.gd`, `scripts/ui/board_planning/plan_badges.gd` (standing-order marks), `scripts/core/game_controller.gd` (sending the requests, refreshing courses after escape, showing a rally result)
- Create: SVG icons `assets/ui/radial/{orders,lead,escape,surrender,rally,back,signal}.svg` where missing (prototype `I` set)
- Test: `test/unit/test_board_planning.gd` (extend), `test/unit/test_plan_checklist.gd` (surrendered state)

**Interfaces:**
- Consumes: `order_options` (Task 1).
- Produces: `BoardPlanning.orders_items(ship) -> Array[RadialItem]` (Lead (toggle, `on`), Escape (toggle, `on`), Surrender (toggle), Rally, Back — hidden ones omitted); the main ring gains **Orders** (always) and **Signal** (Task 3 wires it; greyed with `signal.error`); signals `order_toggled(ship_id, order: String, on: bool)`, `rally_requested(ship_id)`.
- Behaviour: Orders opens the second ring in place (same anchor); Back or Esc returns to the main ring. GameController sends the request, shows a refusal in the ring caption (and keeps the ring open), refreshes `order_options` and the ring. After an escape toggle `_refresh_courses()` (Review Focus 3). Rally: after `player_rally`, read the ship's RALLY event from `GameState.turn_log` (or `player_view.events_for`) and show its result in the caption ("Rally: d10 7 against 4 — she is back in play" / "…failed: crew quality now F"); a rallied ship becomes Plan in the checklist (`refresh_movable`). Standing marks beside the pill: a lead mark, ESCAPE, and for a surrender ordered SURRENDER (amber); a surrendered ship's pill reads SURRENDERED.
- [ ] **Step 1: Failing tests:** `test_orders_ring_items_follow_options` (hidden/greyed/on), `test_back_returns_to_main_ring`, `test_escape_toggle_refreshes_courses` (GameController-level), `test_rally_result_caption` (ScriptedDice), `test_surrendered_ship_ring_has_rally_only`, `test_badges_show_standing_orders`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: orders ring (lead, escape, surrender, rally)`.

### Task 3: Signal composer

**Files:**
- Create: `scripts/ui/board_planning/signal_composer.gd` (`class_name SignalComposer extends PanelContainer`, by the ship, following the camera like `CourseChips`)
- Modify: `board_planning.gd`, `game_controller.gd`
- Test: `test/unit/test_signal_composer.gd`

**Interfaces:**
- Consumes: `order_options(...).signal` (Task 1), `SignalText.words(text, ship_names)` (pure; for the live word count only — the server re-checks on send).
- Produces: `SignalComposer.open(ship_name: String, options: Dictionary) -> void`, `close()`, `show_error(reason: String)`; `signal send_requested(address: Dictionary, text: String)`, `signal cancel_pending_requested()`, `signal closed()`.
- Layout: title "Signal from <ship>"; address picker (Fleet, each group, each ship by name); a LineEdit (this is the one control that takes keyboard focus; while it has focus board keys are off) with "n of limit words" under it (amber over the limit, the words error when `SignalText.words` gives one); Send / Close; when a signal is pending: its address and text with Cancel signal. Enter in the field sends; Esc closes.
- Behaviour: GameController sends `player_send_signal(HUMAN_PLAYER_ID, ship_id, address, text)` and shows a refusal with `show_error`; on success the composer shows the pending signal. Cancel → `player_cancel_signal`. Opening the composer closes the ring; Esc closes the composer.
- [ ] **Step 1: Failing tests:** `test_word_count_and_limit`, `test_send_emits_address_and_text`, `test_pending_signal_shown_with_cancel`, `test_board_keys_ignored_while_typing` (Tab/Space/Enter while the field has focus do not reach BoardPlanning), `test_error_shown`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: signal composer on the board`.

### Task 4: Live check, docs, SCV

- [ ] **Step 1:** Run with the godot MCP: `test_basic` (lead on a short course, refused on a long one; signal sent, pending shown, cancelled, a delivered signal in the log), a scenario with an escape edge (`test_coastal`: declare escape, the edge hexes appear in Move), `test_optional_rules` (surrender ordered, strikes at MORALE_CHECK, rally next turn with the result shown). Review Focus 1–5 live where reachable. `game_get_errors` zero. Screenshots to the scratchpad `shots/` as `p2_orders.png`, `p2_signal.png`.
- [ ] **Step 2:** CLAUDE.md: Board Planning section (Orders ring, Signal composer, `order_options`).
- [ ] **Step 3:** `scv-reviewer`; fix; `make test`; commit.
