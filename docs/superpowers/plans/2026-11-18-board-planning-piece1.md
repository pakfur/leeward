# Board Planning, Piece 1 (Radial Menu and Planning per Ship) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking one of your ships in PLANNING opens a radial menu (Move, Crew & damage, Reset course, Done / Plan again); Move puts that ship into today's hex-by-hex course plotting; each ship carries a Plan/Done mark on the map and in the side panel; the card's Course block moves to a chip box on the map.

**Architecture:** View only, no server change. A `RadialMenu` Control follows the ship on screen; a `PlanChecklist` (pure view state) holds Plan/Done; `GameController` routes clicks: outside Move mode a click on an own ship opens her ring and never edits a course; in Move mode only that ship's course takes clicks (existing `CourseClicks` / `player_extend_course` / `player_cut_course`). A `CourseChips` box at the course end shows the readout the card's Course block shows today.

**Tech Stack:** Godot 4.6 GDScript, GUT 9.5 (`make test`), godot-mcp for the live check.

**Spec:** `docs/superpowers/specs/2026-11-18-board-planning-design.md` (Piece 1). Prototype: `prototypes/planning_radial/planning_radial.html` (look and flow; its precomputed-reach Move is NOT built, user decision 2026-11-18).

## Global Constraints

- No server change. Requests used, unchanged: `player_extend_course`, `player_cut_course`, `player_reset_course`, `player_submit_plan`, `player_reset_planning`; queries `course_options`, `plan_errors`. `test_server_authority.gd` stays green.
- Plan/Done is view state only (user decision): it never reaches the server; End Planning is `player_submit_plan` as today.
- A ship still in Plan at End Planning sails her stored (default) course; the footer says "n ships still in Plan sail their default course" (1 ship: "1 ship is still in Plan: she sails her default course").
- Greyed ring items show the server's reason (`PlanningSailUi.movement_block_reason` / `can_plot_movement` for Move); no rule is re-encoded in the view.
- Outside Move mode, no map click edits a course.
- Keys in PLANNING: Tab = next own ship still in Plan (opens her ring), Space = open the ring of the selected own ship, Enter = Done for the ring's / Move-mode ship, Esc = step back (option box → Move mode → ring → nothing). C (crew overlay) and Home unchanged. Space/Enter keep their POST_COMBAT and replay meanings outside PLANNING.
- Runtime logging through `Trace`; `@warning_ignore` on the line; run `make import` after adding files and commit every `.uid` and imported-asset file; fonts by `theme_type_variation`.
- The radial follows the camera: its position is recomputed every frame from `Camera3D.unproject_position` of the ship's centre while open.
- Update CLAUDE.md (Planning Panel section and a new Board Planning note) at the end; no `feature_diff.md` change (no rule effect).

## Review Focus

1. A ship that cannot plot (anchored, fouled, grappled, struck, towed, a prize): her ring opens, Move is greyed with the server's reason, and she is never stuck in Plan (she starts Done with a lock badge).
2. Clicking a hex of another own ship's drawn course outside Move mode selects/opens rings and never extends or cuts that course.
3. The crew overlay open (C or the ring icon) while Move mode or a ring is up: no double handling of Esc, and the ring closes.
4. A new turn, a game reset (Developer UI) or leaving the game while a ring or Move mode is open: no orphan Controls, no stale checklist entries for ships no longer movable.
5. The ring near a screen edge stays fully on screen (clamped inside the map's safe rect).

---

### Task 1: `RadialMenu` and icons

**Files:**
- Create: `scripts/ui/board_planning/radial_menu.gd` (`class_name RadialMenu extends Control`), `scripts/ui/board_planning/radial_item.gd` (`class_name RadialItem extends RefCounted`), `assets/ui/radial/*.svg` (move, crew, orders, signal, reset, done, undo; simple 24×24 line icons in the prototype's style)
- Test: `test/unit/test_radial_menu.gd`

**Interfaces:**
- Produces:
  - `RadialItem`: `id: String`, `label: String`, `icon: Texture2D`, `hint: String`, `off_reason: String` ("" = enabled), `on: bool` (a toggled state, drawn with a green rim).
  - `RadialMenu.open(items: Array[RadialItem], title: String, subtitle: String) -> void`, `close() -> void`, `is_open() -> bool`, `set_anchor_provider(fn: Callable) -> void` (returns the screen point to centre on, called every frame), `set_safe_rect(rect: Rect2) -> void` (the ring is clamped to stay inside), `caption_text() -> String` (what the caption shows now), `item_count() -> int`; `signal item_chosen(id: String)` (never for an item with an `off_reason`), `signal closed()`.
  - Layout: items evenly on a circle of radius 78 px (scaled by the UI scale), first item at the top, 48 px round buttons, pop-in animation; the centre shows `title` / `subtitle`; hovering or focusing an item shows its label and either `hint` or `off_reason` (in the warning colour) below the ring.
- [ ] **Step 1: Failing tests:** `test_items_laid_out_on_circle` (positions at equal angles, first at the top), `test_disabled_item_emits_nothing`, `test_enabled_item_emits_id`, `test_caption_shows_reason_on_hover`, `test_clamped_inside_safe_rect` (anchor near a corner keeps every item inside the rect), `test_close_emits_closed`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: radial menu for board planning` with the `.uid`, `.svg` and `.import` files.

### Task 2: `PlanChecklist` and the map badges

**Files:**
- Create: `scripts/ui/board_planning/plan_checklist.gd` (`class_name PlanChecklist extends RefCounted`), `scripts/ui/board_planning/plan_badges.gd` (`class_name PlanBadges extends Control`: one small pill per own ship above her on screen, following the camera like `IndicatorOverlay`)
- Test: `test/unit/test_plan_checklist.gd`

**Interfaces:**
- Produces:
  - `PlanChecklist.begin(ship_ids: Array, movable: Dictionary) -> void` (every id Plan if `movable[id]`, else Locked), `state(ship_id) -> String` ("plan" | "done" | "locked" | ""), `set_done(ship_id, done: bool) -> void` (no-op for locked), `refresh_movable(movable: Dictionary) -> void` (a ship that became movable — a rally — becomes Plan; one that stopped being movable becomes Locked), `next_in_plan(after_id: String) -> String` (cyclic, "" when none), `plan_count() -> int`, `clear() -> void`; `signal changed()`.
  - `PlanBadges.setup(camera: Camera3D) -> void`, `show_for(entries: Dictionary) -> void` (ship_id → {"world": Vector3, "state": String}), `clear() -> void`. Pills: PLAN (amber), ✓ DONE (green), ⚓/🔒 DONE for locked (grey) — text, colours from the prototype.
- [ ] **Step 1: Failing tests:** `test_begin_marks_unmovable_locked`, `test_set_done_ignored_for_locked`, `test_next_in_plan_cycles_and_skips_done`, `test_refresh_movable_unlocks_rallied_ship`, `test_changed_signal`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: plan checklist and badges`.

### Task 3: Ring wiring and Move mode in `GameController`

**Files:**
- Modify: `scripts/core/game_controller.gd` (`_unhandled_input`, `_handle_course_click`, `_refresh_courses`, `_handle_ship_selection` / `_select_ship`, `_on_phase_changed`, the leave / new-game paths)
- Create: `scripts/ui/board_planning/course_chips.gd` (`class_name CourseChips extends PanelContainer`: at the screen position of the course end, following the camera: "Course: n of m MP", the course notes (`_course_info`'s lines), a refusal reason, ✓ Done, Keep planning; `signal done_pressed()`, `signal keep_pressed()`)
- Create: `scripts/ui/board_planning/board_planning.gd` (`class_name BoardPlanning extends Node`: the view-side coordinator owned by GameController: holds the `PlanChecklist`, the `RadialMenu`, `PlanBadges`, `CourseChips`, the Move-mode ship id; builds the ring items; GameController forwards clicks/keys to it)
- Test: `test/unit/test_board_planning.gd`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces (BoardPlanning): `begin_planning(own_ships: Array[ShipState]) -> void`, `end_planning() -> void`, `ring_items(ship: ShipState) -> Array[RadialItem]`, `open_ring(ship_id: String) -> void`, `enter_move(ship_id: String) -> void`, `leave_move() -> void`, `move_ship_id() -> String`, `handle_key(keycode: int) -> bool`, `checklist() -> PlanChecklist`; signals `crew_overlay_requested(ship_id)`, `reset_course_requested(ship_id)`, `move_mode_changed(ship_id)` (""=left).
- Behaviour:
  - Ring items for an own ship: Move (`off_reason` = `PlanningSailUi.movement_block_reason(ship)` when `not PlanningSailUi.can_plot_movement(ship)`), Crew & damage, Reset course (`off_reason` "No course plotted: she sails her default course." when `course_options(id).path` equals `start_of_turn_course(id)`), Done (`state == plan`) or Plan again (`state == done`; off for locked with the block reason).
  - Click routing in PLANNING (GameController): with a Move-mode ship, `_handle_course_click` only considers that ship's course (`CourseClicks.route` over `{id: _courses[id]}`); a click on her own hexes or empty sea away from her course leaves Move mode; a click on another own ship leaves Move mode and opens that ship's ring. Without a Move-mode ship, course clicks are never routed; a click on an own ship opens (or closes) her ring and selects her; an enemy click keeps today's behaviour (status plate); empty sea closes the ring.
  - `_refresh_courses` keeps drawing every own course, but `next_hexes` and blocked-hex marks only for the Move-mode ship.
  - Move mode: `CourseChips` follows the course end; Done in it marks the ship Done and leaves Move mode; refusals from a click show in it.
  - Keys per the Global Constraints, handled before the existing Space/Enter End Turn branch only while in PLANNING.
  - PLANNING entry: `begin_planning`; leaving PLANNING (any phase), a new game or leaving the game: `end_planning` (ring, chips, badges closed; Move mode left).
  - Crew overlay opening closes the ring and leaves Move mode.
- [ ] **Step 1: Failing tests** (`test_board_planning.gd`, BoardPlanning with a test GameState scenario as other UI tests do): `test_ring_items_for_movable_ship`, `test_move_greyed_with_server_reason_for_anchored_ship`, `test_done_and_plan_again_toggle`, `test_tab_opens_next_ship_in_plan`, `test_esc_steps_back`, `test_end_planning_closes_everything`; and a GameController-level test (as existing ones) `test_outside_move_mode_clicks_never_edit_course` (Review Focus 2) and `test_move_mode_click_extends_only_that_ship`.
- [ ] **Step 2–4:** implement; `make import`; `make test` passes (existing course-click tests updated only where they assumed clicks edit any ship's course outside Move mode — say which in the report).
- [ ] **Step 5:** commit `feat: radial menu and move mode on the board`.

### Task 4: Side panel cards

**Files:**
- Modify: `scripts/ui/ship_list_item.gd`, `scripts/ui/planning_phase_ui.gd` (+ its scene if needed), `scripts/core/game_controller.gd` (wiring)
- Test: existing planning UI tests (`test_planning_*` / `test_ship_list_item*` — find them) updated, plus new tests

**Interfaces:**
- Consumes: `PlanChecklist` (Task 2), `BoardPlanning` (Task 3).
- Changes: the card's Course block and its Reset course button are removed (the chip box and the ring replace them; `set_course_info` goes or becomes a no-op removed with its callers); each card shows the Plan/Done pill (`PlanChecklist.state`), clicking it toggles (not for locked); clicking a card selects the ship and opens her ring; the footer keeps End Planning and Cancel and adds the "still in Plan" line (Global Constraints wording), updated on `PlanChecklist.changed`.
- [ ] **Step 1: Failing tests:** `test_card_has_no_course_block`, `test_pill_reflects_checklist`, `test_pill_toggles_done`, `test_footer_counts_ships_in_plan`.
- [ ] **Step 2–4:** implement; `make test` passes.
- [ ] **Step 5:** commit `feat: side panel cards show plan state; course block moves to the board`.

### Task 5: Live check, docs, SCV

- [ ] **Step 1:** Run the game (`test_basic`, then `test_fleet`) with the godot MCP; with real clicks: open a ring, Move, plot a course hex by hex, see the chip box, Done, Tab to the next ship, toggle a pill, End Planning, play the turn through. Check Review Focus 1–5 live (anchored ship in `test_anchorage`, a ring at the screen edge, C while a ring is open, Developer UI reset mid-ring). `game_get_errors` zero. Save 2–3 screenshots to the scratchpad `shots/` folder for the user.
- [ ] **Step 2:** CLAUDE.md: Planning Panel section (no Course block; the card pill) and a short "Board planning" section (files, BoardPlanning, keys, Move mode routing).
- [ ] **Step 3:** `scv-reviewer`; fix; `make test`; commit.
