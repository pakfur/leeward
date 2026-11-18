# Resolution Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the timed combat-log reveal with a left-panel resolution replay: one step per action (dice, picture, modifiers, outcome, camera on the ship), Next / Resolve all, prompts as steps, and the map showing each ship's state in step with the replay.

**Architecture:** View-only. A pure step builder (`ResolutionSteps`) turns the local player's filtered events (`PlayerView.events_for`) into steps. A `ResolutionReplay` node owns the step queue and drives a `ResolutionPanel` placed in the `ContextPanel`. `DisplayStates` keeps detached ship copies taken at each phase entry, and `GameController._sync_all_views` draws from them while a replay runs. No server change except a pure `PhaseEvent.from_dict`.

**Tech Stack:** Godot 4.6 GDScript, GUT 9.5 (`make test`), godot-mcp for the live check.

**Spec:** `docs/superpowers/specs/2026-11-18-resolution-panel-design.md`

## Global Constraints

- Strict server authority: view code (`scripts/ui`, `scripts/view`, `scripts/core`) never calls a `ShipStateController` / controller mutator or writes a `ShipState` field; `test_server_authority.gd` must stay green. Display copies are detached `ShipState.deserialize(serialize())` objects owned by the view and never written back.
- Server requests used: `player_submit_bear_off`, `player_submit_maintenance_orders`, `on_combat_playback_completed`, `on_playback_paused` (existing, with their existing `SCV:ALLOW` comments). No new server request.
- Runtime logging through `Trace`, never `print()`.
- `@warning_ignore(...)` goes on the line itself.
- Run `make import` after adding scripts/scenes and commit every new `.uid` file.
- Fonts by `theme_type_variation` only (`HeaderLabel`, `StrongLabel`, `CounterLabel`, `TabularLabel`, `SecondaryLabel`), theme `assets/ui/leeward_theme.tres`.
- The local player is `GameController.HUMAN_PLAYER_ID` (0).
- `skip_post_combat_delay` (tests, AI-only runs) keeps today's instant behaviour: no replay, no panel.
- The camera never rotates for the replay (CLAUDE.md: only the player's controls rotate it).
- Keys: Space, Enter, Right arrow = Next. Resolve all stops at a prompt step; a prompt is never skipped.
- Update CLAUDE.md (UI section) at the end. No `feature_diff.md` change: no rule effect.

## Review Focus

1. Resolve all with a prompt step queued later must stop at the prompt, not answer it or hang.
2. The game is left (`_leaving`) or ends (`game_over`) mid-replay: no further server calls, no errors, no orphan panel.
3. A combat log with no step-worthy events (only HOLD_FIRE): the panel never opens and `on_combat_playback_completed()` is still called once.
4. A ship destroyed and taken off the map during the turn: its view is not freed while the replay still shows it afloat, and is freed once the replay passes that phase.
5. Limited information: a step about an enemy ship never shows box counts the filtered event hid.

---

### Task 1: `PhaseEvent.from_dict` and `ResolutionSteps`

**Files:**
- Modify: `scripts/server/phase_events.gd` (add `static func from_dict(d: Dictionary) -> PhaseEvent` on `PhaseEvent`, inverse of `to_dict`, including `sides`)
- Create: `scripts/ui/resolution/resolution_steps.gd` (`class_name ResolutionSteps`, pure statics), `scripts/ui/resolution/resolution_step.gd` (`class_name ResolutionStep extends RefCounted`)
- Modify: `scripts/ui/combat_log_panel.gd` only if a helper must be shared (keep `event_names` / `log_ships` where they are and call them)
- Test: `test/unit/test_resolution_steps.gd`

**Interfaces:**
- Produces:
  - `ResolutionStep` fields: `kind: String` (e.g. `"gunfire"`, `"marine_fire"`, `"morale"`, `"drift"`, `"grapple"`, `"ungrapple"`, `"unfoul"`, `"boarding"`, `"fire"`, `"explosion"`, `"tow"`, `"rally"`, `"aim"`, `"crit_fix"`, `"anchor"`, `"prompt_bear_off"`, `"prompt_maintenance"`), `phase: int`, `ship_id: String`, `target_id: String`, `events: Array[PhaseEvents.PhaseEvent]`, `first_index: int`, `last_index: int` (indices into the input list), `dice: Array` of `{"sides": 6|10, "values": Array[int]}`, `title: String`, `modifiers: Array` of `{"label": String, "value": int}`, `final_text: String`, `outcome_lines: PackedStringArray`, `prompt: Dictionary` (empty for non-prompts).
  - `static func build(event_dicts: Array, from_index: int, ship_info: Dictionary) -> Array[ResolutionStep]` — `event_dicts` is `PlayerView.events_for(...)` output, `ship_info` is `CombatLogPanel.log_ships(GameState.get_all_ships())`.
  - `static func lead_kind(type: PhaseEvents.Type) -> String` ("" = not a lead), `static func folds_into(lead: PhaseEvents.PhaseEvent, ev: PhaseEvents.PhaseEvent) -> bool`.

- [ ] **Step 1: Write failing tests** in `test_resolution_steps.gd`:
  - `test_from_dict_round_trips`: `PhaseEvent.from_dict(ev.to_dict())` equals the original in `type`, `phase`, `ship_id`, `target_id`, `data`, `sides`.
  - `test_fire_folds_its_damage_and_crit`: events [FIRE a→b, DAMAGE b, a critical-hit event on b, GUNS_DISMOUNTED b, FIRE c→d, DAMAGE d] give 2 steps, the first with 4 events, kind `"gunfire"`, `ship_id` a, `target_id` b, `last_index` 3.
  - `test_hold_fire_and_signal_are_not_steps`: [HOLD_FIRE, SIGNAL, MORALE_CHECK] give 1 step, kind `"morale"`.
  - `test_morale_dice_and_outcome`: a MORALE_CHECK with `{"roll": 7, "rating": 4, "passed": false}` gives `dice == [{"sides": 10, "values": [7]}]` and an outcome line that contains the event's own `to_text` wording.
  - `test_fire_modifiers_copied`: a FIRE event's `data.modifiers` become `modifiers` labels/values in order.
  - `test_build_from_index`: `from_index` skips earlier events and indices stay absolute.
  - `test_drift_step` and `test_grapple_step` with the data keys `DriftResolver` / `GrapplingController` actually log.
  - `test_hidden_boxes_stay_hidden`: a DAMAGE dict without box fields (as `PlayerView` gives an enemy) builds without error and its outcome line has no box count.
  Use real event data shapes: read the `data` each controller logs (`gunnery_resolver.gd`, `morale_controller.gd`, `drift_resolver.gd`, `grappling_controller.gd`, `boarding_controller.gd`, `fire_controller.gd`, `tow_controller.gd`, `critical_hit_controller.gd`, `marine_fire_resolver.gd`) rather than inventing keys.
- [ ] **Step 2:** `make test` — new tests fail (class not found).
- [ ] **Step 3: Implement.** One `const LEADS := {Type.FIRE: "gunfire", ...}` table, one `const FOLLOWS := [Type.DAMAGE, Type.GUNS_DISMOUNTED, Type.MORALE_NOTED, Type.STRIKE, <critical-hit types>, Type.FIRE_STARTED, Type.DESTROYED, Type.SHIP_CAPTURED, ...]`. A follower folds into the open step when it is in the same phase and names the lead's ship or target; otherwise it is dropped from steps (it stays in the log). Every `PhaseEvents.Type` must be classified as lead, follower or skipped — a test iterates `PhaseEvents.Type.values()` and asserts each is in exactly one list (`SKIPPED` const). Dice: one entry per die the event carries (`roll` int → one die, `roll` array → several; d10 vs d6 by type, 2d6 for EXPLOSION_CHECK and BOARDING_ROUND per the controllers). Text from `PhaseEvent.to_text(CombatLogPanel.event_names(ev, ship_info))`; the title is a short phrase per kind ("Broadside", "Morale check", "Drift", ...) plus the ship names.
- [ ] **Step 4:** `make test` — all pass.
- [ ] **Step 5:** `make import`; commit `feat: resolution steps from the player's events` with the `.uid` files.

### Task 2: `DisplayStates`

**Files:**
- Create: `scripts/view/display_states.gd` (`class_name DisplayStates extends RefCounted`)
- Test: `test/unit/test_display_states.gd`

**Interfaces:**
- Produces:
  - `func capture(phase: int, turn: int, ships: Array) -> void` — stores detached copies of every ship as the state *before* `phase`; a second capture of the same `(turn, phase)` is ignored (combat's second `phase_changed`).
  - `func begin(phases: Array[int]) -> void` — a replay of these phases starts; every ship shows its copy from before the first listed phase.
  - `func step_shown(step: ResolutionStep, steps: Array[ResolutionStep], index: int) -> void` — after showing `steps[index]`: each ship whose last step in `step.phase` is at or before `index` switches to its copy from before the next captured phase (or live, `null`, if none).
  - `func phase_reached(phase: int) -> void` — the replay moved into `phase`: every ship shows its copy from before `phase`.
  - `func state_for(ship_id: String) -> ShipState` — the copy to draw, or `null` = draw live.
  - `func end() -> void` — everything live again; `func active() -> bool`.
  - `func clear() -> void` (new game).

- [ ] **Step 1: Failing tests:** `test_capture_ignores_second_emit`, `test_begin_shows_pre_phase_copy` (a copy's `rigging_current_hp` differs from the live ship after live damage), `test_ship_switches_after_its_last_step`, `test_other_ship_waits_for_its_own_step`, `test_end_returns_live`, `test_copy_is_detached` (changing the live ship after capture does not change the copy). Build ships with the existing test helpers used in other unit tests (look at `test_player_view.gd` or `test_damage_controller.gd` for a ship fixture; set rigging explicitly).
- [ ] **Step 2:** `make test` fails.
- [ ] **Step 3: Implement** with `ShipState.deserialize(ship.serialize())`. Check `deserialize` restores the `ship` (type data) reference; if it does not, copy it from the live ship onto the copy as a plain view-side reference (the copy is never written to the server).
- [ ] **Step 4:** `make test` passes. **Step 5:** `make import`; commit `feat: display states for the resolution replay`.

### Task 3: Camera framing without rotation

**Files:**
- Modify: `scripts/core/isometric_camera.gd`
- Test: `test/unit/test_isometric_camera.gd`

**Interfaces:**
- Produces: `func frame_ship(world_pos: Vector3, distance: float, safe_rect: Rect2) -> void` (smooth pan + zoom to `distance`, clamped to min/max zoom, rotation unchanged, the point centred in `safe_rect` rather than the window); `func save_view() -> Dictionary` and `func restore_view(view: Dictionary) -> void` (target, zoom, rotation).
- [ ] **Step 1: Failing tests:** `test_frame_ship_keeps_rotation`, `test_frame_ship_clamps_zoom`, `test_restore_view_round_trips` (after the animation completes; drive it the way the existing camera tests do).
- [ ] **Step 2–4:** implement following `focus_on_ship`'s animation, minus the rotation; `make test` passes.
- [ ] **Step 5:** commit `feat: camera frame_ship for the resolution replay`.

### Task 4: `ResolutionDice`, picture and `ResolutionPanel`

**Files:**
- Create: `scripts/ui/resolution/resolution_dice.gd` (`class_name ResolutionDice extends Control`, drawn in `_draw()`), `scripts/ui/resolution/resolution_picture.gd` (`class_name ResolutionPicture extends Control`, a procedural placeholder per `kind`: sea band, ship silhouette, a motif per kind — smoke puffs for gunfire, waves/arrow for drift, flag for morale, hooks for grapple, flames for fire, hawser for tow, a question mark for prompts — plus the kind name as a caption), `scripts/ui/resolution/resolution_panel.gd` + `scenes/ui/resolution_panel.tscn` (`class_name ResolutionPanel extends VBoxContainer`)
- Test: `test/unit/test_resolution_panel.gd`

**Interfaces:**
- Consumes: `ResolutionStep` (Task 1).
- Produces:
  - `ResolutionDice.roll(dice: Array, instant: bool) -> void`, `signal settled()`, `func is_rolling() -> bool`; tumbles ~0.8 s showing random faces, lands on the given values (d10 faces 0–9).
  - `ResolutionPanel.show_step(step: ResolutionStep, index: int, total: int, phase_label: String, instant: bool) -> void`; `func set_answer_section(control: Control) -> void` (replaces Next/Resolve all while a prompt is shown; `null` restores them); `signal next_pressed()`, `signal resolve_all_pressed()`; `func header_text() -> String` ("Combat · 3 of 11").
  - Layout top to bottom: header (`CounterLabel`), title (`HeaderLabel`), `ResolutionPicture` (16:9, fills width), `ResolutionDice` (hidden when `dice` empty), modifiers list (`TabularLabel` rows "label  +n"), final line (`StrongLabel`), outcome lines (autowrap), spacer, `HSeparator`, button row **Resolve all** | **Next ▸** pinned at the bottom (like End Turn). Next is enabled once the dice settle.
- [ ] **Step 1: Failing tests:** `test_header_text`, `test_dice_hidden_without_dice`, `test_modifier_rows`, `test_next_waits_for_dice` (Next disabled while rolling, enabled after `instant` roll), `test_answer_section_replaces_buttons`.
- [ ] **Step 2–4:** implement; `make test` passes.
- [ ] **Step 5:** `make import`; commit `feat: resolution panel, dice and placeholder pictures` with `.uid` files.

### Task 5: `ResolutionReplay` and combat / post-combat wiring

**Files:**
- Create: `scripts/ui/resolution/resolution_replay.gd` (`class_name ResolutionReplay extends Node`)
- Modify: `scripts/core/game_controller.gd` (`_on_combat_log_ready`, `_play_combat_log`, `_enter_post_combat_phase`, `_show_end_turn_ui` call site, `_on_phase_changed`, `_on_game_over`, the leave path, `_sync_all_views` and the anchor/grapple/tow line refreshes, `_skip_combat_playback`)
- Test: `test/unit/test_resolution_replay.gd`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces (ResolutionReplay):
  - `func start(kind: String, phases: Array[int]) -> void` (`kind` = `"combat"` | `"post_combat"` | `"bear_off"`), `func append(steps: Array[ResolutionStep]) -> void`, `func push_prompt(step: ResolutionStep, answer: Control) -> void`, `func prompt_answered() -> void`, `func finish_when_drained(callback: Callable) -> void`, `func cancel() -> void`, `func is_running() -> bool`, `func current_index() -> int`, `func next() -> void`, `func resolve_all() -> void`.
  - `signal step_shown(step: ResolutionStep, index: int)`, `signal drained()`.
  - `var resolving: bool` — the "this player is still replaying" state a later roster reads.
- Behaviour (GameController):
  - **Combat:** `_on_combat_log_ready` → if `skip_post_combat_delay` or no context panel: today's instant path. Else capture is already done (Task 2 via `_on_phase_changed`); build steps for `COMBAT_RESOLUTION` events from `GameState.player_view.events_for(HUMAN_PLAYER_ID, turn)`; zero steps → finish at once; else put the panel in the context panel (title "Resolution"), run the replay; on drained (or the old skip) → `_finish_combat_playback()` as today. The boarding card is shown when a BOARDING_ROUND step is shown (`_show_boarding_card`). The collapsed combat log's reveal limit follows `step.last_index + 1` (indices from the filtered list map to the raw log by position: `events_for` drops events, so keep a filtered→raw index map in the step builder input or reveal by count of raw events up to the step's last event id; builder's call, tested).
  - **Post-combat:** a replay of DRIFT_CALCULATION, STATUS_ADJUSTMENT, MORALE_CHECK, MESSAGE_DELIVERY steps starts at the first of `maintenance_orders_requested(HUMAN_PLAYER_ID, …)` or `POST_COMBAT` entry. New events are appended when the server goes on (after a maintenance answer, and on `POST_COMBAT` entry): rebuild from `events_for` with `from_index` = number already consumed. The End Turn UI is shown only after drained in POST_COMBAT.
  - Each shown step: `camera.frame_ship(<ship's world centre from its display copy>, <close distance, e.g. a third of max zoom>, _map_safe_rect())`; `DisplayStates.step_shown(...)`; `_sync_all_views()`. Resolve all: dice instant, no camera moves, display states jump through, stops at a prompt. Replay end: `camera.restore_view(saved)`, `DisplayStates.end()`, `_sync_all_views()`.
  - `_sync_all_views` draws `DisplayStates.state_for(id)` when non-null, else live; a view is not erased for leaving the map while its display copy is on the map.
  - Cancel (no server calls) on `_leaving`, `game_over`, and when the phase moves past the replay's phases (a new PLANNING).
  - The old timed reveal (`COMBAT_REVEAL_SECONDS` loop) is removed; `skip_requested` from the log calls `resolve_all()`.
- [ ] **Step 1: Failing tests** (`test_resolution_replay.gd`, the replay node alone with a stub panel): `test_next_walks_steps`, `test_resolve_all_stops_at_prompt`, `test_drained_fires_once`, `test_append_while_waiting_continues`, `test_cancel_emits_nothing`. In `test_combat_log_ui.gd` or a new GameController-level test if one exists for combat playback: `test_no_steps_still_completes_combat` (Review Focus 3).
- [ ] **Step 2–4:** implement; `make test` passes (existing combat-playback and headless tests must stay green).
- [ ] **Step 5:** `make import`; commit `feat: resolution replay for combat and the post-combat phases`.

### Task 6: Prompts as steps

**Files:**
- Modify: `scripts/core/game_controller.gd` (`_on_bear_off_decision_requested`, `_on_bear_off_chosen`, `_on_maintenance_orders_requested`, `_on_maintenance_orders_submitted`), `scripts/ui/bear_off_panel.gd`, `scripts/ui/maintenance_orders_panel.gd` (each gains a compact mode: just the answer controls and error line, no title block, for the answer section; wording and checks unchanged)
- Modify: `scripts/ui/resolution/resolution_steps.gd` (`static func bear_off_prompt(situation, ship_info) -> ResolutionStep`, `static func maintenance_prompt(step_name: String, options: Array, ship_info) -> ResolutionStep`; kinds `"prompt_bear_off"`, `"prompt_maintenance"`; the bear-off step carries the bearing-off chance as text, no dice, since no roll has been made yet)
- Test: `test/unit/test_resolution_steps.gd`, `test/unit/test_bear_off_phase.gd` / `test_maintenance_orders.gd` as needed

- [ ] **Step 1: Failing tests:** `test_bear_off_prompt_step` (title names both ships, `prompt` holds `ship_id`), `test_maintenance_prompt_step` (grapple / ungrapple / prize titles from `MaintenanceOrdersPanel.title(step)`), `test_refusal_keeps_prompt` (replay stays on the prompt when the answer returns a reason; panel shows it).
- [ ] **Step 2–4:** bear-off: the replay starts with kind `"bear_off"` and the single prompt step (camera on the ship, `other_plots` drawn as today); answered → `prompt_answered()` → drained → panel removed, movement playback resumes as today. Maintenance: `push_prompt` into the running post-combat replay (start it first if not running, Task 5). `make test` passes.
- [ ] **Step 5:** commit `feat: bear-off and maintenance prompts as resolution steps`.

### Task 7: Live check, docs, SCV

- [ ] **Step 1:** `mcp__godot__run_project`, play `test_basic` (or `test_fleet`) through a turn with gunfire: confirm the panel shows steps, dice settle on the logged roll, camera frames without rotating, Next / Resolve all work, the map's damage appears on the shot's step, End Turn appears after the post-combat replay; `game_get_errors` returns zero. Screenshot one step and send it to the user with `SendUserFile`.
- [ ] **Step 2:** Exercise a grapple prompt (`DevCommands.grapple_ships` or a scenario with ships alongside) and a bear-off if reachable.
- [ ] **Step 3:** CLAUDE.md: replace the combat-log timed reveal description with the resolution replay (files, `ResolutionReplay.resolving`, prompts as steps, `DisplayStates`, `frame_ship`).
- [ ] **Step 4:** Run the `scv-reviewer` agent; fix violations; `make test`; commit.
