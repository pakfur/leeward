# Selected-Ship UI — Design Spec

**Date:** 2026-05-31
**Status:** Approved (pending spec review)
**Area:** View / UI layer (`scripts/view/`, `scripts/ui/`, `scripts/core/game_controller.gd`)

## 1. Overview

Replace the current "selected ship" visual (a yellow highlight torus) with a richer,
information-bearing selection UI, and make ships directly clickable in the 3D world.

When a ship is selected, the player sees:

- A **windward indicator** — an arrow on the hex face turned toward the wind, pointing
  *inward* at that face (shows where the wind comes from).
- A **ship direction indicator** — an arrow on the bow's hex face, pointing *outward* in
  the ship's facing direction, with a two-line **Speed / point-of-sail** label.
- An **info icon** — a button that toggles the ship's status dialog.

During movement plotting, hovering a legal next hex shows a lower-opacity preview of the
windward + direction indicators (and label) for that prospective move.

## 2. Goals

- Select a ship by clicking directly on it in the 3D world (own ships get the full
  selected-ship UI; enemy ships open a read-only status dialog).
- Selecting via the planning panel card behaves identically to clicking an own ship.
- Replace the highlight torus with the windward indicator, direction indicator, and info
  icon.
- Indicators snap to hex faces, run perpendicular (90°) to the face, and stay anchored to
  the face while scaling with camera zoom between clamped min/max sizes.
- Status dialog is hidden on selection and toggled by the info icon.
- Plotting-hover preview of the indicators over legal next hexes.

## 3. Non-Goals

- No new movement rules, validation, or legality logic on the client.
- No networking/replication work (the single-process `is_server == true` model is unchanged;
  `NetworkSync` stays stubbed).
- No changes to the plotting request/response protocol — we render the data it already sends.
- No redesign of `ShipStatusPanel`'s contents (we reuse it, only gate/toggle its visibility).

## 4. Authority & SCV Constraints (binding)

This feature is **entirely View layer**. It must pass the `scv-reviewer` agent.

**Ship state authority.** The view reads state fields only (`ship_state.facing`,
`ship_state.speed`, `ship_state.hex_position`, `environment.wind_direction`,
`environment.wind_speed`). It assigns no state, calls no `is_server`-guarded mutator.

**Legal-moves authority.** All move legality is computed server-side
(`MovementValidator` → `MovementPlottingController`) and delivered in the plotting response.
The view **only renders that response** and never recomputes legality:

| Displayed value | Source (authoritative) | How the view obtains it |
|---|---|---|
| Which hexes are legal next moves | server | membership test against the response's `valid_next_hexes` |
| `resulting_facing` for a hovered candidate | server | `valid_next_hexes[..].metadata.resulting_facing` |
| `ma_cost`, `can_submit`, `remaining_ma`, tacking/luffing | server | response payload |
| Hover label speed | `ship_state.speed` (server state, constant during plotting) | field read |
| Selected ship's facing / windward face | server state | `ship_state.facing` / `environment.wind_direction` |
| Point-of-sail label word | `HexGrid.get_wind_facing()` — the **same shared helper the server uses** | pure call on authoritative state |

**Single source of truth.** The view never reimplements a rule. Where a derived value is
needed for display (the point-of-sail word), it calls the canonical `HexGrid.get_wind_facing()`,
not a parallel copy.

## 5. Architecture

A pure **model builder** produces a plain data DTO; two dumb **renderers** consume only the
DTO; `game_controller` coordinates. State access is confined to the builder.

```
                 reads state (read-only)
ShipState ─┐
Environment├──▶ ShipIndicatorModel.build_*()  ──▶  IndicatorModel (plain DTO)
HexGrid  ──┘        (pure, testable)                     │
                                                         ├──▶ ShipIndicators (Node3D)  → 3D arrows
                                                         └──▶ IndicatorOverlay (Control) → label + info icon
```

- The renderers never see `ShipState`/`EnvironmentState` — only the DTO. This isolates
  state access and makes the logic unit-testable without rendering.

### 5.1 `ShipIndicatorModel` (new — `scripts/view/ship_indicator_model.gd`)

Pure data + static builders. `class_name ShipIndicatorModel`.

DTO fields (one model describes one indicator set — selected or hover):
- `windward_visible: bool`, `windward_anchor: Vector3` (face midpoint, world),
  `windward_dir: Vector3` (outward face-normal, world, XZ-plane unit)
- `direction_anchor: Vector3`, `direction_dir: Vector3`
- `label_anchor: Vector3` (world point to project the label/icon near, e.g. the bow face)
- `speed: int`, `point_of_sail: String` (`"In Irons"|"Close Hauled"|"Broad Reach"|"Running"`)
- `opacity: float` (1.0 selected, ~0.6 hover)

Builders (`speed` is always `ship_state.speed` — current ship speed, the same for selected and hover):
- `build_selected(ship_state, environment, hex_grid) -> IndicatorModel`
- `build_hover(ship_state, hex: Vector2i, resulting_facing: int, environment, hex_grid) -> IndicatorModel`
  — `speed` is `ship_state.speed` (the selected ship's current speed, constant during plotting);
  only the direction face (`resulting_facing`) and point-of-sail differ from the selected model

Logic:
- Windward face index = `environment.wind_direction`; `windward_visible = environment.wind_speed > 0`.
- Direction face index = `ship_state.facing` (selected) or `resulting_facing` (hover).
- Anchor for a face: `hex_grid.axial_to_edge_world(q, r, face_index)` (existing — returns the
  hex/neighbor midpoint = the face midpoint).
- Outward normal: `(face_midpoint - hex_grid.axial_to_world(q, r)).normalized()`.
- `point_of_sail` from `_pos_label(hex_grid.get_wind_facing(facing, wind_direction))`:
  `L→"In Irons"`, `C→"Close Hauled"`, `B→"Broad Reach"`, `R→"Running"`.

### 5.2 `ShipIndicators` (new — `scripts/view/ship_indicators.gd`, `Node3D`)

Owns a small fixed pool of flat-on-water arrow meshes: selected-windward,
selected-direction, hover-windward, hover-direction. Style matches `HexOverlay`
(unshaded, no depth test, sits at `y ≈ 0.1`).

API:
- `show_selected(model: IndicatorModel)` / `clear_selected()`
- `show_hover(model: IndicatorModel)` / `clear_hover()`
- Holds a reference to the camera for clamp-scaling.

Per arrow:
- Position = `anchor`; orient the mesh in the XZ plane along `dir`.
- **Windward** arrow points *inward* (arrowhead toward the face, tail offset outward along `dir`).
- **Direction** arrow points *outward* (tail at the face, arrowhead offset outward along `dir`).
- Length/width multiplied by the current clamp scale (see §8).

`_process`: recompute clamp scale from camera distance each frame and apply (camera can
pan/zoom/rotate while a ship stays selected).

### 5.3 `IndicatorOverlay` (new — `scripts/ui/indicator_overlay.gd`, `Control` under `$UI`)

Owns the 2D pieces: the selected label, the hover label, and the info-icon `Button`.

API:
- `show_selected(model, ship_id)` — show label + info icon; `clear_selected()`
- `show_hover(model)` — show hover label only; `clear_hover()`
- Signal `info_toggled(ship_id: String)` — emitted when the info icon is pressed.

`_process`: position each visible control via `camera.unproject_position(world_anchor)`
(offset to sit beside the arrow), and apply the clamped scale to font/icon size; hide
controls whose anchor is behind the camera.

### 5.4 Coordinator (modify — `scripts/core/game_controller.gd`)

Ties selection/plotting/wind state to the renderers. No new state mutation.

## 6. Selection & Input Flow

### 6.1 Make ships clickable
`ShipView` currently has no collision, so the existing camera raycast in
`_handle_ship_selection` silently misses. Add an `Area3D` + `CollisionShape3D` (a simple
box/cylinder sized to the hull) as a child of `ShipView` in `_create_ship_model()`. The
existing raycast + `_find_ship_view_from_collider()` path then resolves clicks to a `ShipView`.

### 6.2 Click handling (extends `_handle_ship_selection`)
- **Hit an own ship** (`ship_state.player_id == human player`, currently `0`): run `_select_ship(id)`
  → camera focus (existing) + `ShipIndicators.show_selected` + `IndicatorOverlay.show_selected`;
  **status dialog stays hidden**.
- **Hit an enemy ship**: show `ShipStatusPanel` for it (read-only), no indicators, no info icon;
  no `selected_ship_id` change to the own-ship selection model (enemy inspect is a separate,
  transient view). Clicking empty water or another ship dismisses it.
- **Hit empty water**: deselect — clear indicators, info icon, and any open dialog;
  `selected_ship_id = ""`.

### 6.3 Planning panel selection
`planning_phase_ui.ship_selected` → `_on_planning_ship_selected` already calls camera focus +
`_select_ship`. It now drives the same indicator/overlay path as an own-ship click (no separate
code path — both funnel through `_select_ship`).

### 6.4 Selecting a new ship
`_select_ship` first clears the previous ship's indicators and closes its status dialog, then
shows the new ship's indicators (dialog hidden).

## 7. Info Icon & Status Dialog

- Reuse `ShipStatusPanel` (`scripts/ui/ship_status_panel.gd`). It already renders all ship
  fields and makes read-only controller queries (`SCV:ALLOW`).
- **Decouple auto-show:** `_select_ship` no longer calls `show_ship_status_from_state`.
- Add `ShipStatusPanel.toggle(ship_state)` — show+populate if hidden (or showing a different
  ship), hide if already showing this ship.
- `IndicatorOverlay.info_toggled(ship_id)` → `game_controller` calls
  `ship_status_panel.toggle(GameState.get_ship(ship_id))`.
- Enemy inspect calls `show_ship_status_from_state` directly (always show, no toggle).

## 8. Zoom Scaling (clamped, face-anchored)

- `scale = clamp(camera_distance * SCREEN_FACTOR, MIN_WORLD, MAX_WORLD)`.
- Grows as the camera zooms out (larger world size keeps apparent size ≈ constant), clamped at
  both ends so indicators never dwarf a far hex nor vanish against a near ship.
- **Anchor is fixed to the face midpoint**; only size (arrow length/width, label/icon size,
  offset distance) scales. The arrow's face-attached end does not move.
- Constants exported on `ShipIndicators` for tuning: `SCREEN_FACTOR`, `MIN_WORLD`, `MAX_WORLD`
  (and a parallel mapping for the 2D label/icon size). Initial values are placeholders to tweak
  in-engine.
- Camera distance read from `isometric_camera.camera_distance`.

## 9. Plotting Hover

- While `movement_client.is_plotting()`, handle `InputEventMouseMotion`: raycast cursor to the
  water plane → hex (reuse the `_get_hex_from_screen_pos` ray-plane pattern).
- If the hex is a **server-provided legal next hex**, look up its candidate metadata
  (`resulting_facing`) and call `ShipIndicators.show_hover` + `IndicatorOverlay.show_hover`
  with `opacity ≈ 0.6`. The label's `Speed:` is the selected ship's `ship_state.speed`
  (constant during plotting); only the direction arrow + point-of-sail reflect the hovered
  candidate's `resulting_facing`.
- If the cursor is not over a legal next hex, `clear_hover()`.
- The currently valid candidates are cached from the latest plotting response. `movement_client`
  already receives `valid_next_hexes` (with metadata); expose a lookup
  `get_candidate_at_hex(hex) -> {resulting_facing, ...}` (or cache the dict in the overlay/client).
- Selected-ship indicators remain displayed independently of hover.
- Hover clears on plotting submit/cancel and on selection change.

## 10. Removing the Old Highlight

- Delete `selection_indicator`, `_create_selection_indicator()`, and the torus visibility logic
  from `ship_view.gd`.
- **Remove `set_selected()` entirely.** Update its callers in `game_controller`
  (`_select_ship`, `_handle_ship_selection`) to drive the new indicator controller instead;
  selection visuals come entirely from `ShipIndicators` / `IndicatorOverlay`.

## 11. Visual Spec (locked during brainstorming)

```
            ^  [2] direction (outward, perpendicular to bow face)
            |     Speed: 3
            |     Close Hauled
   [1]  \   |
   wind  \  |        (windward [1]: inward arrowhead at the
    ▸------▸|         wind-facing face, perpendicular)
          \ |
       ___ \|___
      /    (ship)  \
      \    hull    / ⓘ  [3] info icon (toggles status dialog)
       \__________/
```

- Windward arrow: cyan, arrowhead toward the face (inward).
- Direction arrow: amber, arrowhead away from the bow (outward).
- Both perpendicular to and anchored on their hex face, snapped to the 6 hex directions.
- Selected = full opacity + label + info icon. Hover = ~60% opacity + label, **no info icon**.
- Windward hidden when `wind_speed == 0`.

## 12. Edge Cases / Error Handling

- `wind_speed == 0` → no windward indicator (selected and hover).
- "In Irons" (facing into wind) → direction indicator still shown; label reads "In Irons".
- Null guards: missing `ship_state`, `environment`, `camera`, or `ship` reference → skip render.
- Anchor behind the camera → hide the corresponding 2D control for that frame.
- Deselect / new selection / plotting end → clear the relevant indicator set and dialog.
- Camera animation (focus tween) in progress → indicators follow via per-frame `_process` updates.

## 13. Testing

GUT unit tests on the pure builder — `test/unit/test_ship_indicator_model.gd`:
- Windward face index equals `wind_direction`; `windward_visible` false when `wind_speed == 0`.
- Point-of-sail mapping `L/C/B/R → In Irons/Close Hauled/Broad Reach/Running`.
- Face anchor equals `HexGrid.axial_to_edge_world(...)`; normal points outward from hex center.
- Clamp-scale boundaries (below MIN clamps to MIN; above MAX clamps to MAX; mid passes through).
- `build_hover` uses `resulting_facing` for the direction face and `ship_state.speed` (constant) for the label speed.

Rendering, raycast picking, and `unproject` positioning are verified manually via the
`godot-mcp` run + `game_get_errors` (zero warnings) and visual inspection, per project convention.

## 14. File Changes

**New**
- `scripts/view/ship_indicator_model.gd` — pure DTO + builders
- `scripts/view/ship_indicators.gd` — 3D arrow renderer (Node3D)
- `scripts/ui/indicator_overlay.gd` — 2D label + info icon (Control)
- `test/unit/test_ship_indicator_model.gd`

**Modified**
- `scripts/view/ship_view.gd` — add collision body; remove highlight torus and `set_selected()`
- `scripts/core/game_controller.gd` — own/enemy click branching; drive indicators; wire info
  toggle; plotting-hover (mouse motion); clear on submit/cancel/deselect
- `scripts/ui/ship_status_panel.gd` — add `toggle()`; remove auto-show coupling
- `scripts/core/hex_grid.gd` — only if a small direction→world-vector helper is needed
  (otherwise none)
- Scene wiring: instance `ShipIndicators` under the 3D world and `IndicatorOverlay` under `$UI`
  (in `main_game.tscn` or created in `game_controller._ready()`, following existing patterns)

## 15. Tunables (defer)

`SCREEN_FACTOR`, `MIN_WORLD`, `MAX_WORLD`, 2D size mapping, hover opacity (0.5–0.7), arrow
colors, info-icon size/offset, collision-shape dimensions.

## 16. Final Step

Run the `scv-reviewer` agent after implementation and all tests pass; fix any violations before
declaring complete (per `CLAUDE.md`).
