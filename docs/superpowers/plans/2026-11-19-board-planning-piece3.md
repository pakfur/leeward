# Board Planning, Piece 3 (Fire on the Board) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fire orders are given on the board, after movement: in the fire declaration step every own ship with a shot shows FIRE; her radial menu offers port and starboard broadsides, the bow and stern chasers, the marines and hold fire; picking one shades its arc and rings the enemies it bears on; clicking a target opens an option box beside it (battery, aim, ammunition, voluntary reduction, the modified number and modifiers); orders are drawn as arrows; **Fire** in the side panel footer sends them. The fire declaration side panel goes.

**Architecture:** View only, no server change. Step 1 moves the fire panel's pure order logic (its statics and per-ship selection state) into a `FireOrdersModel` the panel then uses unchanged, so the rules of choosing (two targets, full before half, bow+stern at one target is a full broadside, reductions, dismantling, high only at long range) are kept, tested, in one place. Steps 2–3 build the board UI on that model (`FireBoard`, inside `BoardPlanning`) and retire the panel's UI. Numbers come from `GunneryCalculator.preview_orders` over the whole order set, so what is shown is what is rolled.

**Tech Stack:** Godot 4.6 GDScript, GUT 9.5, godot-mcp.

**Spec:** `docs/superpowers/specs/2026-11-18-board-planning-design.md` (Piece 3). Pieces 1–2 (merged) built `RadialMenu`, `RadialItem`, `PlanChecklist`, `PlanBadges`, `BoardPlanning`, `CourseChips`, `SignalComposer` in `scripts/ui/board_planning/` (CLAUDE.md "Board Planning"). Prototype: `prototypes/planning_radial/planning_radial.html` (fire phase: `fireItems`, `startTarget`, `pickTarget`, the option box, order arrows).

## Global Constraints

- No server change. Requests and queries used, unchanged: `player_submit_fire_orders(player_id, orders, marine_orders)`, `gunnery_calculator.eligible_shots` / `preview` / `preview_orders` / `validate_orders`, `marine_fire_resolver.eligible_marine_shots` / `preview`, `FireRules` statics, `FireGeometry` (arcs, `chase_arc`), `GameController.battery_arc`.
- Every number and every no-shot reason shown comes from those queries (or the existing `FireDeclarationPanel` statics moved into the model); nothing is recomputed in a new way.
- Fire stays after movement (user decision); the AI and headless paths (`skip_post_combat_delay`, no side panel) keep today's behaviour.
- Plan/Done in the fire step is the same view-only `PlanChecklist`: ships with a shot start Plan (FIRE pill), the rest Done ("NO TARGET" pill); Fire is always allowed; ships still in Plan hold fire, and the footer says "n ships have no fire orders: they hold fire".
- Ring items with no target are greyed with the reason (`FireDeclarationPanel.no_shot_reason` / `ship_no_shot_reason` wording, via the model).
- Strict server authority; Trace; `@warning_ignore` on the line; `make import`, commit `.uid`/`.import`; fonts by `theme_type_variation`; ring items take no focus.
- Update CLAUDE.md (Board Planning; the "Fire panel" note under Sides, Arcs and Rake) at the end; no `feature_diff.md` change.

## Review Focus

1. The orders sent equal what today's panel would send for the same choices (same `FireOrder` fields, same marine orders), including split sides, two targets, chasers, reductions and dismantling — the model's tests pin this.
2. The number in the option box equals `preview_orders` for the whole set after the change (a second target changes every shot's number by −12).
3. A ship whose only shot is a marine shot still gets a ring with Marines (today's panel lists such ships).
4. Bear-off or the resolution replay arriving while the fire ring or option box is open: nothing orphaned; the combat replay starts as today after Fire.
5. A ship with no crew to serve the guns, struck or surrendering: Done with the no-shot reason, never a FIRE pill.

---

### Task 1: `FireOrdersModel` (refactor, behaviour unchanged)

**Files:**
- Create: `scripts/ui/fire/fire_orders_model.gd` (`class_name FireOrdersModel extends RefCounted`)
- Modify: `scripts/ui/fire_declaration_panel.gd` (its pure statics move to the model, or stay as thin forwarders; its per-ship selection state is held by a model instance)
- Test: `test/unit/test_fire_orders_model.gd` (the panel's logic tests move here); `test/unit/test_fire_declaration_panel.gd` keeps its widget tests and must pass unchanged except for moved tests

**Interfaces:**
- Produces (FireOrdersModel): `setup(ship_ids: Array) -> void` (loads eligible shots and marine shots per ship from the calculator / resolver, as `FireDeclarationPanel.setup` does), `ships_with_shots() -> Array[String]`, `no_shot_reason(ship_id) -> String`, `sides_bearing(ship_id) -> Dictionary` (side → Array of target ids), `targets(ship_id, side) -> Array[Dictionary]` ({target_id, range, batteries: Array[String], preview: ShotPreview} per target), `marine_targets(ship_id) -> Array[Dictionary]` (target_id, preview dict), `choose(ship_id, side, target_id, battery) -> void`, `clear_side(ship_id, side) -> void`, `set_high(ship_id, side, on)`, `set_dismantling(ship_id, side, on)`, `set_reduction(ship_id, side, target_id, battery, n)`, `select_marine_target(ship_id, target_id)` ("" = hold), `hold_fire(ship_id)`, `orders() -> Array[GunneryTypes.FireOrder]` (exactly today's `get_all_orders`), `marine_orders() -> Array` (exactly today's `get_marine_orders`), `order_previews() -> Dictionary` (order key → ShotPreview from `preview_orders` over `orders()`), `ship_orders(ship_id) -> Array`; `signal changed()`.
- [ ] **Step 1:** Move the panel's logic tests to `test_fire_orders_model.gd` against the model API; add `test_orders_equal_panel_orders` (drive the panel and a model through the same choices on `test_fleet`-like fixtures; equal orders and marine orders) and `test_order_previews_match_preview_orders`.
- [ ] **Step 2–4:** implement the model, make the panel use it; `make test` passes with the panel's widget behaviour unchanged.
- [ ] **Step 5:** commit `refactor: fire orders model shared by the fire panel and the board`.

### Task 2: Fire ring, arcs, targets and the option box

**Files:**
- Create: `scripts/ui/board_planning/fire_board.gd` (`class_name FireBoard extends RefCounted` or Node: the fire step's board state over a `FireOrdersModel`), `scripts/ui/board_planning/fire_option_box.gd` (`class_name FireOptionBox extends PanelContainer`, beside the target, following the camera like `CourseChips`), icons `assets/ui/radial/{port,starboard,bowchase,sternchase,marines,hold}.svg` (prototype `I` set)
- Modify: `scripts/ui/board_planning/board_planning.gd` (fire-step ring items and target mode), `scripts/ui/board_planning/plan_badges.gd` (FIRE / NO TARGET / "n ORDERS" pills), `scripts/core/game_controller.gd` (arc shading through `hex_overlay` and `battery_arc`, target rings, order arrows — use the existing fire overlay drawing where it fits)
- Test: `test/unit/test_fire_board.gd`, `test/unit/test_board_planning.gd` (extend)

**Interfaces:**
- Consumes: `FireOrdersModel` (Task 1).
- Produces: `BoardPlanning.begin_fire(model: FireOrdersModel, own_ships: Array[ShipState]) -> void`, `end_fire() -> void`, `fire_ring_items(ship_id) -> Array[RadialItem]` (Port broadside, Starboard broadside, Bow chaser, Stern chaser, Marines, Hold fire / Clear orders, Done / Change orders; greyed with the model's reason; `on` when that side has an order), `enter_target_mode(ship_id, side) -> void`, `pick_target(target_id) -> void` (opens the option box), `leave_target_mode()`; signal `fire_overlay_changed(ship_id, side)` (GameController redraws arcs, rings and arrows).
- Option box: title "<ship> → <target> · range n"; battery chips (Full broadside / Bow battery / Stern battery, only those that bear, from the model); Low / High (High forced at range 10+, the model's note); Round / Dismantling (dismantling within 7, chasers round only); voluntary reduction − n +; the modified gunfire number and the modifier lines (`FireDeclarationPanel.modifier_lines` / `breakdown_text` wording, from `order_previews`); the two-target note when it applies; ✓ Order / Cancel. Marines: the column and chance (`marine_option_text`), ✓ Order / Cancel.
- Map: in target mode the side's arc shaded (`battery_arc` per bearing battery; chase arc for chasers), each target ringed with its range; orders drawn as arrows from the firing battery to the target in the side's colour (`BroadsideColors`), labelled with the number; the ring's ship's own order arrows stay while others are dimmed.
- Keys: Tab next ship in Plan (fire step), Esc steps back (option box → target mode → ring), Enter confirms the option box, else Done.
- [ ] **Step 1: Failing tests:** `test_fire_ring_greys_sides_without_targets`, `test_marine_only_ship_has_marines_item` (Review Focus 3), `test_target_mode_lists_bearing_targets`, `test_option_box_confirm_adds_order`, `test_second_target_changes_number` (Review Focus 2), `test_hold_fire_clears_and_marks_done`, `test_no_shot_ship_starts_done_with_reason` (Review Focus 5).
- [ ] **Step 2–4:** implement; `make import`; `make test` passes.
- [ ] **Step 5:** commit `feat: fire orders on the board`.

### Task 3: The fire step without the side panel list

**Files:**
- Modify: `scripts/core/game_controller.gd` (`_on_fire_declaration_requested`, `_on_fire_pressed`, `_show_orders_while_declaring`, `_close_fire_panel`, `_refresh_fire_overlay`), `scripts/ui/fire_declaration_panel.gd` + scene (removed, or reduced to the headless/no-side-panel path if anything still needs it — say which), the side panel during the fire step
- Test: GameController-level tests for the fire step (find the existing ones for `_on_fire_pressed` / fire declaration and update them)

**Behaviour:**
- On `fire_declaration_requested`: build the model, `BoardPlanning.begin_fire`, the side panel shows the fire step: the own ships with their FIRE / NO TARGET / n ORDERS pills (the piece-1 cards), the footer "n ships have no fire orders: they hold fire" and **Fire** (with the order count, `fire_button_text_with_marines`).
- Fire sends `player_submit_fire_orders(HUMAN_PLAYER_ID, model.orders(), model.marine_orders())`; a refusal shows in the footer and the step stays; success shows "Orders in — waiting for the other side" while others declare (today's `_show_orders_while_declaring`), then the combat replay as today.
- Bear-off, replay start, game over, leaving: `end_fire` and nothing orphaned (Review Focus 4).
- [ ] **Step 1: Failing tests:** `test_fire_button_sends_model_orders`, `test_refusal_keeps_the_step`, `test_fire_step_closed_by_replay`, and update existing fire-panel GameController tests.
- [ ] **Step 2–4:** implement; `make test` passes.
- [ ] **Step 5:** commit `feat: the fire step on the board replaces the fire panel`.

### Task 4: Live check, docs, SCV

- [ ] **Step 1:** Run with the godot MCP: `test_basic` and `test_fleet` through fire steps with real clicks: a full broadside, a split side (bow at one target, stern at another), two targets (watch the −12), a chaser, dismantling within 7, a voluntary reduction, marines alongside (`DevCommands.grapple_ships` or ships placed alongside), hold fire; the replay's FIRE steps show the same numbers. Review Focus 1–5 live where reachable. `game_get_errors` zero. Screenshots `p3_fire_ring.png`, `p3_option_box.png`, `p3_orders.png` to the scratchpad `shots/`.
- [ ] **Step 2:** CLAUDE.md: Board Planning (fire step), the "Fire panel" note (replaced by the board), `FireOrdersModel`.
- [ ] **Step 3:** `scv-reviewer`; fix; `make test`; commit.
