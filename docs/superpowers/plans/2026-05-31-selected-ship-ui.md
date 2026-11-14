# Selected-Ship UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the selection-highlight torus with face-anchored windward/direction indicators + an info-icon-toggled status dialog, make ships clickable (own = full UI, enemy = read-only status), and add a plotting-hover preview.

**Architecture:** A pure, read-only `ShipIndicatorModel` builder (unit-tested) computes geometry + labels from primitive state values; two dumb renderers consume only that DTO — `ShipIndicators` (flat-on-water 3D arrows) and `IndicatorOverlay` (2D label + info icon). `game_controller` wires selection / plotting state to them. All move legality + ship state stay server-authoritative; the view only reads fields and renders server-provided plotting responses.

**Tech Stack:** Godot 4.6 / GDScript, GUT tests, `godot-mcp` for run + `game_get_errors` verification.

**Spec:** `docs/superpowers/specs/2026-05-31-selected-ship-ui-design.md`

---

## Conventions for every task

- After editing any file under `scripts/core/`, `scripts/autoload/`, `scripts/server/`, `scripts/state/`, or `test/unit/`, the `.claude/hooks/run_related_tests.py` PostToolUse hook runs `make test` automatically. You may also run it manually.
- "Verify in engine" means: run `mcp__godot__run_project` (projectPath `/Users/jk/gws/Leeward`), wait ~3s, call `mcp__godot__game_get_errors`, and confirm it returns `{"count": 0, "errors": []}` (zero warnings), then `mcp__godot__stop_project`.
- Human player id is `0`.

---

## Task 1: `ShipIndicatorModel` (pure DTO + builders)

**Files:**
- Create: `scripts/view/ship_indicator_model.gd`
- Test: `test/unit/test_ship_indicator_model.gd`

- [ ] **Step 1: Write the failing test**

Create `test/unit/test_ship_indicator_model.gd`:

```gdscript
extends GutTest

const Model = preload("res://scripts/view/ship_indicator_model.gd")

var hex_grid: HexGrid

func before_each() -> void:
	hex_grid = HexGrid.new(1.0)

func test_point_of_sail_mapping() -> void:
	assert_eq(Model.point_of_sail_label("L"), "In Irons")
	assert_eq(Model.point_of_sail_label("C"), "Close Hauled")
	assert_eq(Model.point_of_sail_label("B"), "Broad Reach")
	assert_eq(Model.point_of_sail_label("R"), "Running")
	assert_eq(Model.point_of_sail_label("?"), "")

func test_clamp_scale_bounds() -> void:
	assert_eq(Model.clamp_scale(1.0, 0.1, 0.5, 2.0), 0.5)    # below min -> min
	assert_eq(Model.clamp_scale(100.0, 0.1, 0.5, 2.0), 2.0)  # above max -> max
	assert_almost_eq(Model.clamp_scale(10.0, 0.1, 0.5, 2.0), 1.0, 0.0001)

func test_windward_hidden_when_calm() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 2, 0, hex_grid)
	assert_false(m.windward_visible)

func test_windward_face_is_wind_direction() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 0, 3, 4, 2, hex_grid)  # wind from NW(4)
	assert_eq(m.windward_anchor, hex_grid.axial_to_edge_world(0, 0, 4))
	assert_true(m.windward_visible)

func test_direction_face_is_facing_when_selected() -> void:
	var m = Model.build_selected(Vector2i(0, 0), 1, 3, 4, 2, hex_grid)  # facing SE(1)
	assert_eq(m.direction_anchor, hex_grid.axial_to_edge_world(0, 0, 1))

func test_hover_uses_resulting_facing_and_constant_speed() -> void:
	var m = Model.build_hover(Vector2i(2, -1), 5, 4, 0, 2, hex_grid)  # resulting facing NE(5)
	assert_eq(m.direction_anchor, hex_grid.axial_to_edge_world(2, -1, 5))
	assert_eq(m.speed, 4)
	assert_almost_eq(m.opacity, 0.6, 0.001)

func test_point_of_sail_in_irons_when_facing_into_wind() -> void:
	# facing == wind_direction -> relative 0 -> "L" -> In Irons
	var m = Model.build_selected(Vector2i(0, 0), 2, 3, 2, 2, hex_grid)
	assert_eq(m.point_of_sail, "In Irons")

func test_center_anchor_is_hex_center() -> void:
	var m = Model.build_selected(Vector2i(3, -2), 0, 1, 0, 2, hex_grid)
	assert_eq(m.center_anchor, hex_grid.axial_to_world(3, -2))
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `make test-file F=test/unit/test_ship_indicator_model.gd`
Expected: FAIL — `Model` script does not exist / parse error.

- [ ] **Step 3: Write the implementation**

Create `scripts/view/ship_indicator_model.gd`:

```gdscript
class_name ShipIndicatorModel
extends RefCounted
## ShipIndicatorModel - Pure, read-only presentation DTO + builders for the
## selected-ship and plotting-hover indicators.
##
## View layer: computes geometry and labels from primitive values it is handed.
## No game-state access, no mutation. Renderers consume this DTO only.

var windward_visible: bool = false
var windward_anchor: Vector3 = Vector3.ZERO   # wind-facing hex-face midpoint (world)
var windward_dir: Vector3 = Vector3.ZERO       # outward face normal (world, XZ unit)
var direction_anchor: Vector3 = Vector3.ZERO   # bow hex-face midpoint (world)
var direction_dir: Vector3 = Vector3.ZERO      # outward face normal (world, XZ unit)
var center_anchor: Vector3 = Vector3.ZERO      # hex center (world) — for the info icon
var label_anchor: Vector3 = Vector3.ZERO       # world point to project the label near
var speed: int = 0
var point_of_sail: String = ""
var opacity: float = 1.0

const POS_LABELS := {
	"L": "In Irons",
	"C": "Close Hauled",
	"B": "Broad Reach",
	"R": "Running",
}

static func point_of_sail_label(wind_facing_code: String) -> String:
	return POS_LABELS.get(wind_facing_code, "")

static func clamp_scale(distance: float, factor: float, min_world: float, max_world: float) -> float:
	return clampf(distance * factor, min_world, max_world)

static func build_selected(hex_position: Vector2i, facing: int, ship_speed: int, wind_direction: int, wind_speed: int, hex_grid: HexGrid) -> ShipIndicatorModel:
	return _build(hex_position, facing, ship_speed, wind_direction, wind_speed, hex_grid, 1.0)

static func build_hover(hex_position: Vector2i, resulting_facing: int, ship_speed: int, wind_direction: int, wind_speed: int, hex_grid: HexGrid) -> ShipIndicatorModel:
	return _build(hex_position, resulting_facing, ship_speed, wind_direction, wind_speed, hex_grid, 0.6)

static func _build(hex_position: Vector2i, facing: int, ship_speed: int, wind_direction: int, wind_speed: int, hex_grid: HexGrid, opacity_val: float) -> ShipIndicatorModel:
	var m := ShipIndicatorModel.new()
	var q := hex_position.x
	var r := hex_position.y
	var center := hex_grid.axial_to_world(q, r)

	m.center_anchor = center

	# Direction indicator anchored on the bow face (= facing / resulting_facing)
	m.direction_anchor = hex_grid.axial_to_edge_world(q, r, facing)
	m.direction_dir = (m.direction_anchor - center).normalized()

	# Windward indicator anchored on the wind-facing face (= wind_direction); hidden when calm
	m.windward_visible = wind_speed > 0
	m.windward_anchor = hex_grid.axial_to_edge_world(q, r, wind_direction)
	m.windward_dir = (m.windward_anchor - center).normalized()

	m.label_anchor = m.direction_anchor
	m.speed = ship_speed
	m.point_of_sail = point_of_sail_label(hex_grid.get_wind_facing(facing, wind_direction))
	m.opacity = opacity_val
	return m
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `make test-file F=test/unit/test_ship_indicator_model.gd`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/view/ship_indicator_model.gd test/unit/test_ship_indicator_model.gd
git commit -m "feat: add ShipIndicatorModel pure builder for selected-ship indicators"
```

---

## Task 2: `ShipView` — add click collision, remove highlight torus + `set_selected()`

**Files:**
- Modify: `scripts/view/ship_view.gd`
- Modify: `scripts/core/game_controller.gd` (callers of `set_selected`)

- [ ] **Step 1: Add a collision body so raycast clicks register**

In `scripts/view/ship_view.gd`, change `_create_ship_model()` to add a body, and add the helper. Replace:

```gdscript
func _create_ship_model(ship_size: int) -> void:
	"""Create ship model based on ship size"""
	model_node = Node3D.new()
	add_child(model_node)

	if ship_size == 1:
		_create_1hex_model()
	else:
		_create_2hex_model()
```

with:

```gdscript
func _create_ship_model(ship_size: int) -> void:
	"""Create ship model based on ship size"""
	model_node = Node3D.new()
	add_child(model_node)

	if ship_size == 1:
		_create_1hex_model()
	else:
		_create_2hex_model()

	_add_click_collision()

func _add_click_collision() -> void:
	"""Add a static body so the camera raycast in game_controller can pick this ship."""
	var body := StaticBody3D.new()
	body.name = "ClickBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.5, 1.8)
	shape.shape = box
	shape.position = Vector3(0, 0.4, 0)
	body.add_child(shape)
	add_child(body)
```

- [ ] **Step 2: Remove the highlight torus and `set_selected()`**

In `scripts/view/ship_view.gd`:

Delete the field (line 10):
```gdscript
var selection_indicator: MeshInstance3D
```

Change `_ready()` from:
```gdscript
func _ready() -> void:
	wave_calculator = WaveCalculator.new()
	_create_selection_indicator()
```
to:
```gdscript
func _ready() -> void:
	wave_calculator = WaveCalculator.new()
```

Delete the entire `_create_selection_indicator()` function:
```gdscript
func _create_selection_indicator() -> void:
	"""Create a selection indicator ring"""
	selection_indicator = MeshInstance3D.new()
	var torus_mesh = TorusMesh.new()
	torus_mesh.inner_radius = 0.6
	torus_mesh.outer_radius = 0.7
	selection_indicator.mesh = torus_mesh

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 0, 0.8)  # Yellow
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_indicator.material_override = material

	selection_indicator.position = Vector3(0, 0.05, 0)
	selection_indicator.visible = false
	add_child(selection_indicator)
```

Delete the entire `set_selected()` function:
```gdscript
func set_selected(is_selected: bool) -> void:
	"""Show/hide selection indicator"""
	selection_indicator.visible = is_selected
	# Note: Don't emit signal here - this is for programmatic selection updates
	# The 'selected' signal should only be emitted by user interaction (3D clicks)
```

- [ ] **Step 3: Update `game_controller` callers (temporary minimal selection — no visual yet)**

In `scripts/core/game_controller.gd`, replace `_handle_ship_selection()`'s empty-click branch. Change:
```gdscript
	if result.is_empty():
		# Click on empty space - deselect
		if not selected_ship_id.is_empty():
			var view = ship_views.get(selected_ship_id)
			if view:
				view.set_selected(false)
			selected_ship_id = ""
			if ship_status_panel:
				ship_status_panel.visible = false
		return
```
to:
```gdscript
	if result.is_empty():
		# Click on empty space - deselect
		if not selected_ship_id.is_empty():
			selected_ship_id = ""
			if ship_status_panel:
				ship_status_panel.visible = false
		return
```

Replace the whole `_select_ship()`:
```gdscript
func _select_ship(ship_id: String) -> void:
	# Deselect previous
	if not selected_ship_id.is_empty() and ship_views.has(selected_ship_id):
		ship_views[selected_ship_id].set_selected(false)

	# Select new
	selected_ship_id = ship_id
	if ship_views.has(ship_id):
		ship_views[ship_id].set_selected(true)

	# Update status panel
	if ship_status_panel:
		var ship_state = GameState.get_ship(ship_id)
		if ship_state:
			ship_status_panel.show_ship_status_from_state(ship_state)
```
with:
```gdscript
func _select_ship(ship_id: String) -> void:
	selected_ship_id = ship_id
```

- [ ] **Step 4: Verify no test regressions and clean run**

Run: `make test`
Expected: PASS (all existing tests still green; `make test` also catches the `game_controller.gd` edit via the hook).

Verify in engine (run_project → game_get_errors → expect 0 → stop_project). Then click a ship in the planning phase: the camera focuses on it (planning-panel path still works), no torus appears, and no errors are logged.

- [ ] **Step 5: Commit**

```bash
git add scripts/view/ship_view.gd scripts/core/game_controller.gd
git commit -m "refactor: add ship click collision; remove highlight torus and set_selected"
```

---

## Task 3: `ShipIndicators` 3D arrow renderer + wire selection

**Files:**
- Create: `scripts/view/ship_indicators.gd`
- Modify: `scripts/core/game_controller.gd`

- [ ] **Step 1: Create the renderer**

Create `scripts/view/ship_indicators.gd`:

```gdscript
extends Node3D
## ShipIndicators - Flat-on-water 3D arrow renderer for the selected ship and the
## plotting-hover preview. Consumes a ShipIndicatorModel DTO only; no game state. (View layer.)

const Model = preload("res://scripts/view/ship_indicator_model.gd")

const ARROW_Y := 0.12                              # just above the hex overlay (0.1)
const WIND_COLOR := Color(0.27, 0.78, 1.0)         # cyan
const DIR_COLOR := Color(1.0, 0.80, 0.27)          # amber

# Zoom-scaling (tunable in-engine)
@export var scale_factor: float = 0.045
@export var min_world: float = 0.6
@export var max_world: float = 2.2

var _camera: Camera3D = null
var _arrows: Dictionary = {}            # role:String -> MeshInstance3D
var _selected_model: ShipIndicatorModel = null
var _hover_model: ShipIndicatorModel = null

func setup(camera: Camera3D) -> void:
	_camera = camera
	for role in ["sel_wind", "sel_dir", "hov_wind", "hov_dir"]:
		var mi := MeshInstance3D.new()
		mi.name = role
		mi.mesh = _build_unit_arrow_mesh()
		mi.material_override = _make_material()
		mi.visible = false
		add_child(mi)
		_arrows[role] = mi

func show_selected(model: ShipIndicatorModel) -> void:
	_selected_model = model
	_refresh()

func clear_selected() -> void:
	_selected_model = null
	_refresh()

func show_hover(model: ShipIndicatorModel) -> void:
	_hover_model = model
	_refresh()

func clear_hover() -> void:
	_hover_model = null
	_refresh()

func _process(_delta: float) -> void:
	if _selected_model != null or _hover_model != null:
		_refresh()

func _refresh() -> void:
	_apply(_selected_model, "sel_wind", "sel_dir")
	_apply(_hover_model, "hov_wind", "hov_dir")

func _apply(model: ShipIndicatorModel, wind_role: String, dir_role: String) -> void:
	var wind_mi: MeshInstance3D = _arrows[wind_role]
	var dir_mi: MeshInstance3D = _arrows[dir_role]
	if model == null:
		wind_mi.visible = false
		dir_mi.visible = false
		return
	var s := _scale_for(model.center_anchor)
	# Direction arrow: tail at face, head outward (+dir)
	_place_arrow(dir_mi, model.direction_anchor, model.direction_anchor + model.direction_dir * s, s, DIR_COLOR, model.opacity)
	dir_mi.visible = true
	# Windward arrow: head at face (inward), tail outward
	if model.windward_visible:
		_place_arrow(wind_mi, model.windward_anchor + model.windward_dir * s, model.windward_anchor, s, WIND_COLOR, model.opacity)
		wind_mi.visible = true
	else:
		wind_mi.visible = false

func _scale_for(anchor: Vector3) -> float:
	var dist := 20.0
	if _camera:
		dist = _camera.global_position.distance_to(anchor)
	return Model.clamp_scale(dist, scale_factor, min_world, max_world)

func _place_arrow(mi: MeshInstance3D, tail: Vector3, head: Vector3, width_scale: float, color: Color, opacity: float) -> void:
	var d := head - tail
	d.y = 0.0
	var length := d.length()
	if length < 0.0001:
		mi.visible = false
		return
	var dir := d / length
	mi.position = Vector3(tail.x, ARROW_Y, tail.z)
	mi.rotation = Vector3(0, atan2(-dir.z, dir.x), 0)
	mi.scale = Vector3(length, 1.0, width_scale)
	var mat: StandardMaterial3D = mi.material_override
	mat.albedo_color = Color(color.r, color.g, color.b, opacity)

func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	return mat

func _build_unit_arrow_mesh() -> ArrayMesh:
	# Arrow pointing +X, length 1: shaft x in [0,0.7] half-width 0.09, head x in [0.7,1.0] half-width 0.20
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	var hw := 0.09
	var hh := 0.20
	v.append(Vector3(0, 0, -hw)); v.append(Vector3(0.7, 0, -hw))
	v.append(Vector3(0.7, 0, hw)); v.append(Vector3(0, 0, hw))
	idx.append_array([0, 1, 2, 0, 2, 3])
	var base := v.size()
	v.append(Vector3(0.7, 0, -hh)); v.append(Vector3(1.0, 0, 0)); v.append(Vector3(0.7, 0, hh))
	idx.append_array([base, base + 1, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
```

- [ ] **Step 2: Wire it into `game_controller`**

In `scripts/core/game_controller.gd`, add member vars near the other view vars (after line 19 `var ship_views ...`):
```gdscript
var ship_indicators: Node3D = null     # ShipIndicators
var indicator_overlay: Control = null  # IndicatorOverlay (added in Task 4)
const HUMAN_PLAYER_ID := 0
```

In `_ready()`, after `_setup_hex_overlay()` (line 79), add a call:
```gdscript
	_setup_indicators()
```

Add the setup function (place it just after `_setup_hex_overlay()`):
```gdscript
func _setup_indicators() -> void:
	ship_indicators = load("res://scripts/view/ship_indicators.gd").new()
	ship_indicators.name = "ShipIndicators"
	add_child(ship_indicators)
	ship_indicators.setup(camera)
```

Replace the minimal `_select_ship()` from Task 2:
```gdscript
func _select_ship(ship_id: String) -> void:
	selected_ship_id = ship_id
```
with:
```gdscript
func _select_ship(ship_id: String) -> void:
	# Clear any previous selection visuals (dialog starts hidden on a new selection)
	if ship_indicators:
		ship_indicators.clear_selected()
	if ship_status_panel:
		ship_status_panel.visible = false

	selected_ship_id = ship_id
	_show_selected_indicators(ship_id)

func _show_selected_indicators(ship_id: String) -> void:
	var ship_state = GameState.get_ship(ship_id)
	if not ship_state or not hex_map or not GameState.environment:
		return
	var env = GameState.environment
	var model = ShipIndicatorModel.build_selected(
		ship_state.hex_position, ship_state.facing, ship_state.speed,
		env.wind_direction, env.wind_speed, hex_map.get_hex_grid())
	if ship_indicators:
		ship_indicators.show_selected(model)

func _deselect_ship() -> void:
	selected_ship_id = ""
	if ship_indicators:
		ship_indicators.clear_selected()
	if ship_status_panel:
		ship_status_panel.visible = false
```

Replace the empty-click branch in `_handle_ship_selection()` (the Task 2 version):
```gdscript
	if result.is_empty():
		# Click on empty space - deselect
		if not selected_ship_id.is_empty():
			selected_ship_id = ""
			if ship_status_panel:
				ship_status_panel.visible = false
		return
```
with:
```gdscript
	if result.is_empty():
		_deselect_ship()
		return
```

- [ ] **Step 3: Verify**

Run: `make test` → PASS (no regressions).
Verify in engine: select a ship via the planning panel → the cyan windward arrow (inward, on the wind face) and amber direction arrow (outward, off the bow) appear, snapped to faces; zooming the camera changes their size between bounds; `game_get_errors` returns 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/view/ship_indicators.gd scripts/core/game_controller.gd
git commit -m "feat: render face-anchored windward/direction arrows for selected ship"
```

---

## Task 4: `IndicatorOverlay` (label + info icon) and status-dialog toggle

**Files:**
- Create: `scripts/ui/indicator_overlay.gd`
- Modify: `scripts/ui/ship_status_panel.gd`
- Modify: `scripts/core/game_controller.gd`

- [ ] **Step 1: Create the 2D overlay**

Create `scripts/ui/indicator_overlay.gd`:

```gdscript
extends Control
## IndicatorOverlay - 2D label(s) + info-icon button for the selected ship and plotting hover.
## Consumes ShipIndicatorModel DTOs; emits info_toggled. No game-state access. (View layer.)

signal info_toggled(ship_id: String)

var _camera: Camera3D = null
var _sel_label: Label = null
var _hov_label: Label = null
var _info_btn: Button = null
var _sel_ship_id: String = ""
var _sel_model: ShipIndicatorModel = null
var _hov_model: ShipIndicatorModel = null

func setup(camera: Camera3D) -> void:
	_camera = camera
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_sel_label = _make_label()
	_hov_label = _make_label()
	add_child(_sel_label)
	add_child(_hov_label)

	_info_btn = Button.new()
	_info_btn.text = "i"
	_info_btn.tooltip_text = "Ship status"
	_info_btn.custom_minimum_size = Vector2(28, 28)
	_info_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_info_btn.visible = false
	_info_btn.pressed.connect(func(): info_toggled.emit(_sel_ship_id))
	add_child(_info_btn)

func _make_label() -> Label:
	var l := Label.new()
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.91, 0.93, 0.96))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func show_selected(model: ShipIndicatorModel, ship_id: String) -> void:
	_sel_model = model
	_sel_ship_id = ship_id
	_update()

func clear_selected() -> void:
	_sel_model = null
	_sel_ship_id = ""
	_sel_label.visible = false
	_info_btn.visible = false

func show_hover(model: ShipIndicatorModel) -> void:
	_hov_model = model
	_update()

func clear_hover() -> void:
	_hov_model = null
	_hov_label.visible = false

func _process(_delta: float) -> void:
	if _sel_model != null or _hov_model != null:
		_update()

func _update() -> void:
	_update_label(_sel_model, _sel_label)
	_update_label(_hov_model, _hov_label)
	_update_info_button()

func _update_label(model: ShipIndicatorModel, label: Label) -> void:
	if model == null or _camera == null:
		label.visible = false
		return
	var anchor := model.label_anchor + model.direction_dir * 0.6
	if _camera.is_position_behind(anchor):
		label.visible = false
		return
	label.text = "Speed: %d\n%s" % [model.speed, model.point_of_sail]
	label.modulate = Color(1, 1, 1, model.opacity)
	label.reset_size()
	label.position = _camera.unproject_position(anchor) + Vector2(10, -10)
	label.visible = true

func _update_info_button() -> void:
	if _sel_model == null or _camera == null or _camera.is_position_behind(_sel_model.center_anchor):
		_info_btn.visible = false
		return
	_info_btn.position = _camera.unproject_position(_sel_model.center_anchor) + Vector2(14, 14)
	_info_btn.visible = true
```

- [ ] **Step 2: Add `toggle()` to `ShipStatusPanel`**

In `scripts/ui/ship_status_panel.gd`, add after `_on_close_pressed()`:
```gdscript
func toggle(ship_state: ShipState) -> void:
	"""Toggle the panel for a ship: hide if already showing it, otherwise show it."""
	if visible and current_ship_state == ship_state:
		visible = false
		current_ship_state = null
	else:
		show_ship_status_from_state(ship_state)
```

- [ ] **Step 3: Wire the overlay + info toggle in `game_controller`**

In `scripts/core/game_controller.gd`, extend `_setup_indicators()`:
```gdscript
func _setup_indicators() -> void:
	ship_indicators = load("res://scripts/view/ship_indicators.gd").new()
	ship_indicators.name = "ShipIndicators"
	add_child(ship_indicators)
	ship_indicators.setup(camera)

	indicator_overlay = load("res://scripts/ui/indicator_overlay.gd").new()
	indicator_overlay.name = "IndicatorOverlay"
	if ui:
		ui.add_child(indicator_overlay)
	indicator_overlay.setup(camera)
	indicator_overlay.info_toggled.connect(_on_info_toggled)
```

Extend `_show_selected_indicators()` to also drive the overlay:
```gdscript
func _show_selected_indicators(ship_id: String) -> void:
	var ship_state = GameState.get_ship(ship_id)
	if not ship_state or not hex_map or not GameState.environment:
		return
	var env = GameState.environment
	var model = ShipIndicatorModel.build_selected(
		ship_state.hex_position, ship_state.facing, ship_state.speed,
		env.wind_direction, env.wind_speed, hex_map.get_hex_grid())
	if ship_indicators:
		ship_indicators.show_selected(model)
	if indicator_overlay:
		indicator_overlay.show_selected(model, ship_id)
```

Extend `_deselect_ship()` to clear the overlay:
```gdscript
func _deselect_ship() -> void:
	selected_ship_id = ""
	if ship_indicators:
		ship_indicators.clear_selected()
	if indicator_overlay:
		indicator_overlay.clear_selected()
	if ship_status_panel:
		ship_status_panel.visible = false
```

Add the info-toggle handler (near `_select_ship`):
```gdscript
func _on_info_toggled(ship_id: String) -> void:
	if ship_status_panel and not ship_id.is_empty():
		var ship_state = GameState.get_ship(ship_id)
		if ship_state:
			ship_status_panel.toggle(ship_state)
```

- [ ] **Step 4: Verify**

Run: `make test` → PASS.
Verify in engine: select a ship → arrows + a two-line "Speed: N / <point of sail>" label appear and an "i" button shows near the ship; the status dialog is **hidden** until you click "i", which toggles it open/closed. `game_get_errors` returns 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/indicator_overlay.gd scripts/ui/ship_status_panel.gd scripts/core/game_controller.gd
git commit -m "feat: add indicator label + info-icon overlay; gate status dialog behind info toggle"
```

---

## Task 5: Own-ship vs enemy-ship click behavior

**Files:**
- Modify: `scripts/core/game_controller.gd`

- [ ] **Step 1: Branch on ownership in `_handle_ship_selection()`**

Replace the "Check if we hit a ship" tail of `_handle_ship_selection()`:
```gdscript
	# Check if we hit a ship
	var collider = result.collider
	var ship_view = _find_ship_view_from_collider(collider)

	if ship_view:
		_select_ship(ship_view.state_id)
```
with:
```gdscript
	# Check if we hit a ship
	var ship_view = _find_ship_view_from_collider(result.collider)
	if not ship_view:
		return
	var ship_state = GameState.get_ship(ship_view.state_id)
	if not ship_state:
		return

	if ship_state.player_id == HUMAN_PLAYER_ID:
		# Own ship: full selected-ship UI; status dialog stays hidden until info icon.
		if camera and camera.has_method("focus_on_ship"):
			camera.focus_on_ship(ship_view.global_position, ship_state.facing)
		_select_ship(ship_view.state_id)
	else:
		# Enemy ship: read-only status dialog only, no indicators.
		_deselect_ship()
		if ship_status_panel:
			ship_status_panel.show_ship_status_from_state(ship_state)
```

- [ ] **Step 2: Verify**

Run: `make test` → PASS.
Verify in engine using the `test_fleet` scenario (player_0 ships + enemy ships): clicking an own ship shows the full indicator UI; clicking an enemy ship opens its status dialog with no arrows/info-icon; clicking empty water clears everything. `game_get_errors` returns 0.

(To run `test_fleet`: it is selected from the scenario menu, or set `GameState.selected_scenario` via the dev flow; the default `test_basic` also has one enemy ship and is sufficient to exercise both branches.)

- [ ] **Step 3: Commit**

```bash
git add scripts/core/game_controller.gd
git commit -m "feat: own-ship click selects with indicators; enemy click shows read-only status"
```

---

## Task 6: Plotting-hover preview

**Files:**
- Modify: `scripts/core/game_controller.gd`

- [ ] **Step 1: Cache hover candidates from the server's valid-next-hexes**

In `scripts/core/game_controller.gd`, add a member var near `submitted_paths`:
```gdscript
var _hover_candidates: Dictionary = {}  # Vector2i hex -> int resulting_facing (server-provided)
```

Add a helper (place near the plotting response handlers):
```gdscript
func _rebuild_hover_candidates(vnh) -> void:
	_hover_candidates.clear()
	if vnh == null:
		return
	for vm in (vnh as MovementTypes.ValidNextHexes).get_all_valid_moves():
		_hover_candidates[vm.hex] = vm.metadata.resulting_facing
```

Call it at the end of `_on_plotting_started()`, `_on_hex_selected()`, and `_on_undo_complete()`. Add this line at the end of each of those three functions (each already receives `valid_hexes`):
```gdscript
	_rebuild_hover_candidates(valid_hexes)
```
(`_on_plotting_started(ship_id, valid_hexes, ...)`, `_on_hex_selected(plotted_path, valid_hexes, ...)`, and `_on_undo_complete(...)` all expose `valid_hexes` as their second parameter — confirm the parameter name in `_on_undo_complete` matches and pass it.)

- [ ] **Step 2: Show/clear hover on mouse motion**

In `_unhandled_input()`, add a motion branch at the top of the function body (after the signature, before the keyboard block):
```gdscript
	if event is InputEventMouseMotion:
		_update_plotting_hover(event.position)
		return
```

Add the hover updater + clear (near `_get_hex_from_screen_pos`):
```gdscript
func _update_plotting_hover(screen_pos: Vector2) -> void:
	if not movement_client or not movement_client.is_plotting():
		_clear_hover()
		return
	var hex = _get_hex_from_screen_pos(screen_pos)  # returns a valid hex or (-99,-99)
	if hex == Vector2i(-99, -99) or not _hover_candidates.has(hex):
		_clear_hover()
		return
	var ship_state = GameState.get_ship(movement_client.active_ship_id)
	if not ship_state or not hex_map or not GameState.environment:
		_clear_hover()
		return
	var env = GameState.environment
	var model = ShipIndicatorModel.build_hover(
		hex, _hover_candidates[hex], ship_state.speed,
		env.wind_direction, env.wind_speed, hex_map.get_hex_grid())
	if ship_indicators:
		ship_indicators.show_hover(model)
	if indicator_overlay:
		indicator_overlay.show_hover(model)

func _clear_hover() -> void:
	if ship_indicators:
		ship_indicators.clear_hover()
	if indicator_overlay:
		indicator_overlay.clear_hover()
```

- [ ] **Step 3: Clear hover when plotting ends**

In `_on_plotting_cancelled()` and `_on_movement_submitted()` (the client-signal handlers), add at the top of each:
```gdscript
	_hover_candidates.clear()
	_clear_hover()
```
If `_on_plotting_cancelled`/`_on_movement_submitted` are not already present as separate functions, they are the handlers connected in `_connect_movement_signals()` (`plotting_cancelled` → `_on_plotting_cancelled`, `movement_submitted` → `_on_movement_submitted`); add the two lines to those existing handlers.

- [ ] **Step 4: Verify**

Run: `make test` → PASS.
Verify in engine: start plotting a ship (toggle Movement in the planning panel), then move the mouse over the green legal-next hexes — a ~60%-opacity windward + direction arrow and label preview appear over the hovered hex using that move's resulting facing; moving off a legal hex clears the preview; the selected ship's own indicators remain. Submitting/cancelling clears the hover. `game_get_errors` returns 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/game_controller.gd
git commit -m "feat: plotting-hover preview of indicators over legal next hexes"
```

---

## Task 7: Integration verification + SCV audit

**Files:** none (verification only)

- [ ] **Step 1: Full test run**

Run: `make test`
Expected: all tests PASS (including `test_ship_indicator_model.gd`).

- [ ] **Step 2: End-to-end manual run**

Run the project via `mcp__godot__run_project`, then exercise: planning-panel select, direct own-ship click, enemy-ship click, empty-water deselect, info-icon toggle, plotting hover, camera zoom scaling, and `wind_speed == 0` (no windward arrow). After each, call `mcp__godot__game_get_errors` and confirm `count == 0`. Stop with `mcp__godot__stop_project`.

- [ ] **Step 3: SCV audit (required by CLAUDE.md)**

Dispatch the `scv-reviewer` agent over the changed files (`ship_indicator_model.gd`, `ship_indicators.gd`, `indicator_overlay.gd`, `ship_view.gd`, `ship_status_panel.gd`, `game_controller.gd`). Confirm zero CRITICAL/WARNING violations (no state mutation outside the server layer; the view only reads state + renders server responses). Fix any findings before finishing.

- [ ] **Step 4: Final commit (if the audit required fixes)**

```bash
git add -A
git commit -m "fix: address SCV review for selected-ship UI"
```

---

## Self-Review (performed against the spec)

- **Spec coverage:** click-to-select + ownership (Task 5), planning-panel parity (Task 3, reuses `_select_ship`), remove torus (Task 2), windward/direction face-anchored perpendicular arrows (Tasks 1+3), clamped zoom scaling (Tasks 1+3), info-icon-toggled status dialog reusing `ShipStatusPanel` (Task 4), hover preview with constant `ship_state.speed` (Task 6), `set_selected()` removal (Task 2), tests (Task 1), SCV gate (Task 7). All spec sections map to a task.
- **Authority:** the model takes primitive values; `game_controller` reads state fields and passes server-provided `resulting_facing` through — no legality computed in the view. ✔
- **Type consistency:** `ShipIndicatorModel.build_selected/build_hover/clamp_scale/point_of_sail_label`, `ShipIndicators.show_selected/clear_selected/show_hover/clear_hover/setup`, `IndicatorOverlay.show_selected/clear_selected/show_hover/clear_hover/setup` + `info_toggled`, `ShipStatusPanel.toggle`, `ValidMove.hex` / `ValidMove.metadata.resulting_facing`, `HexGrid.new(size)` — names are used consistently across tasks.
