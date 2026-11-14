extends Node
## GameController - Main game logic controller (manages views, state is in GameState)

@onready var hex_map: Node3D = $HexMap
@onready var camera: Camera3D = $Camera
@onready var ships_container: Node3D = $Ships
@onready var ui: Control = $UI
@onready var context_panel = $UI/ContextPanel
@onready var planning_panel = $UI/PlanningPanel
@onready var ship_status_panel = $UI/ShipStatusPanel
@onready var developer_ui: Window = $DeveloperUI

# Planning phase UI
const PlanningPhaseUI = preload("res://scenes/ui/planning_phase_ui.tscn")
const FireDeclarationPanelScene = preload("res://scenes/ui/fire_declaration_panel.tscn")
const FirePanelScript = preload("res://scripts/ui/fire_declaration_panel.gd")
const CombatLogPanelScene = preload("res://scenes/ui/combat_log_panel.tscn")
const GameOverPanelScene = preload("res://scenes/ui/game_over_panel.tscn")
const OceanViewScript = preload("res://scripts/view/ocean_view.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
var current_planning_ui: Control = null
var fire_panel: Control = null  # FireDeclarationPanel while fire orders are being declared
var combat_panel: Control = null  # "Combat" context content while combat resolves / plays back
var combat_log_panel: CombatLogPanel = null
var end_turn_panel: Control = null  # context-panel content while waiting in POST_COMBAT
var end_turn_button: Button = null
var game_over_panel: GameOverPanel = null  # modal result card; non-null once the game has ended
var _combat_playback_active: bool = false  # true from combat_log_ready until playback finishes
var _combat_playback_skip: bool = false
var pause_menu: Control = null  # PauseMenu: Escape / the corner Menu button
var menu_button: Button = null  # discreet corner button that opens the pause menu
var _leave_pending: bool = false  # leaving once the running combat playback has stopped
const COMBAT_REVEAL_SECONDS := 0.6

const NO_SHOT_HEADLINE := "No broadside bears on an enemy this turn."

# Views (presentation layer)
var ship_views: Dictionary = {}  # ship_id -> ShipView
var selected_ship_id: String = ""
var ship_indicators: Node3D = null     # ShipIndicators
var indicator_overlay: Control = null  # IndicatorOverlay
const HUMAN_PLAYER_ID := 0

# Planning phase state (client-side)
var selected_actions: Dictionary = {}  # ship_id -> {action_type -> bool}

# Movement plotting
var movement_client: MovementPlottingClient = null
var hex_overlay: Node3D = null  # HexOverlay instance
var submitted_paths: Dictionary = {}  # ship_id -> Array[PlotStep]
var _hover_candidates: Dictionary = {}  # Vector2i hex -> int resulting_facing (server-provided)
var _last_hover_hex: Vector2i = Vector2i(-99, -99)  # avoids re-raycasting when the hovered hex is unchanged
var _collision_names: Dictionary = {}  # offered hex -> name of the ship already in it
var _path_collision_text: String = ""  # warning when the plotted path enters another ship's hex
var _ma_by_len: Dictionary = {}  # plotted path length -> server's remaining movement at that length
var _allowance_notes: Dictionary = {}  # plotted path length -> allowance-change note for that step

# Resolution playback
var playback_controller: MovementResolutionPlaybackController = null

# Debug hex coordinate display
var hex_coord_label: Label = null
var hex_coords_enabled: bool = false

# When true, POST_COMBAT ends the turn automatically instead of waiting for the End Turn button
var skip_post_combat_delay: bool = false

## The player left the finished game; the scene manager returns to scenario selection.
signal back_to_scenarios_requested()

func _ready() -> void:
	Trace.trace_log("GameController", "GameController ready")

	# Load data
	DataManager.load_movement_allowance_table()
	DataManager.load_ship_definitions()
	DataManager.load_speed_change_table()
	DataManager.load_tacking_table()
	DataManager.load_bearing_off_table()
	DataManager.load_turning_table()

	# Clear previous game state
	GameState.clear_ships()

	# Load scenario from GameState (set by menu selection)
	var scenario_name = GameState.selected_scenario
	if scenario_name.is_empty():
		scenario_name = "test_basic"  # Fallback for direct testing

	var scenario = DataManager.load_scenario(scenario_name)
	_setup_scenario(scenario)

	# Connect signals
	GameState.phase_changed.connect(_on_phase_changed)
	if planning_panel:
		planning_panel.plan_submitted.connect(_on_player_plan_submitted)

	# Connect resolution log signal for playback
	if GameState.phase_controller:
		GameState.phase_controller.resolution_log_ready.connect(_on_resolution_log_ready)
		GameState.phase_controller.fire_declaration_requested.connect(_on_fire_declaration_requested)
		GameState.phase_controller.combat_log_ready.connect(_on_combat_log_ready)
		GameState.phase_controller.game_over.connect(_on_game_over)

	# Set up OceanView for water shader updates
	if GameState.environment_controller and hex_map:
		var ocean_view = OceanViewScript.new(GameState, hex_map)
		ocean_view.connect_to_controller(GameState.environment_controller)
		add_child(ocean_view)
		# Not updated here: GameState.environment is still the previous game's until the game
		# starts. OceanView updates on game_started and on every environment change.
		GameState.game_started.connect(ocean_view.update_water_shader.unbind(1))

	_setup_combat_log_panel()

	# Initialize hex overlay
	_setup_hex_overlay()
	_setup_indicators()

	# Initialize movement plotting client
	if GameState.movement_plotting_controller:
		movement_client = MovementPlottingClient.new(GameState.movement_plotting_controller)
		_connect_movement_signals()

	_setup_pause_menu()

	# Setup debug hex coordinate label
	_setup_hex_coord_label()
	if developer_ui:
		developer_ui.hex_coords_toggled.connect(_on_hex_coords_toggled)
		developer_ui.hex_labels_toggled.connect(_on_hex_labels_toggled)

	# Start the game
	GameState.start_new_game(scenario)

func _setup_combat_log_panel() -> void:
	combat_log_panel = CombatLogPanelScene.instantiate()
	if ui:
		ui.add_child(combat_log_panel)
		combat_log_panel.skip_requested.connect(_skip_combat_playback)

func _setup_hex_overlay() -> void:
	var overlay_script = load("res://scripts/view/hex_overlay.gd")
	hex_overlay = Node3D.new()
	hex_overlay.set_script(overlay_script)
	hex_overlay.name = "HexOverlay"
	add_child(hex_overlay)
	if hex_map:
		hex_overlay.arc_grid = hex_map.get_hex_grid()

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

## The corner Menu button and the pause menu (added last so it draws over every other panel).
func _setup_pause_menu() -> void:
	menu_button = Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "Menu"
	menu_button.tooltip_text = "Pause menu (Esc)"
	menu_button.theme_type_variation = &"SecondaryButton"
	menu_button.focus_mode = Control.FOCUS_NONE
	# Bottom-right: clear of the minimap (top right), the side panel (left) and the log bar.
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 10)
	menu_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	menu_button.pressed.connect(_open_pause_menu)
	pause_menu = PauseMenuScript.new()
	pause_menu.leave_confirmed.connect(_leave_game)
	if ui:
		ui.add_child(menu_button)
		ui.add_child(pause_menu)
	else:
		add_child(menu_button)
		add_child(pause_menu)


func _open_pause_menu() -> void:
	if game_over_panel or not pause_menu:
		return
	_clear_hover()
	pause_menu.open()


func is_pause_menu_open() -> bool:
	return pause_menu != null and pause_menu.is_open()


## Leave the game in progress for scenario selection, the way the game-over card does. A running
## combat playback is stopped first (it must not tell the server it finished).
func _leave_game() -> void:
	Trace.trace_log("GameController", "Leaving the game in progress")
	if movement_client and movement_client.is_plotting():
		movement_client.cancel()
	if _combat_playback_active:
		_leave_pending = true
		_combat_playback_skip = true
		return
	_on_back_to_scenarios()


## Escape opens and closes the pause menu; _input so a focused button cannot swallow it.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if not pause_menu:
		return
	match PauseMenuScript.escape_action(pause_menu.is_open(), game_over_panel != null):
		PauseMenuScript.OPEN:
			_open_pause_menu()
		PauseMenuScript.CLOSE:
			pause_menu.close()
		_:
			return
	get_viewport().set_input_as_handled()


func _setup_hex_coord_label() -> void:
	hex_coord_label = Label.new()
	hex_coord_label.name = "HexCoordLabel"
	hex_coord_label.visible = false
	hex_coord_label.add_theme_font_size_override("font_size", 14)
	hex_coord_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	hex_coord_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hex_coord_label.add_theme_constant_override("shadow_offset_x", 1)
	hex_coord_label.add_theme_constant_override("shadow_offset_y", 1)
	hex_coord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ui:
		ui.add_child(hex_coord_label)

func _on_hex_coords_toggled(enabled: bool) -> void:
	hex_coords_enabled = enabled
	if hex_coord_label:
		hex_coord_label.visible = enabled

func _on_hex_labels_toggled(enabled: bool) -> void:
	if hex_map:
		hex_map.set_hex_labels_visible(enabled)

func _process(_delta: float) -> void:
	if not hex_coords_enabled or not hex_coord_label or not camera or not hex_map:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var origin = camera.project_ray_origin(mouse_pos)
	var direction = camera.project_ray_normal(mouse_pos)

	if abs(direction.y) < 0.001:
		hex_coord_label.visible = false
		return

	var t = -origin.y / direction.y
	if t < 0:
		hex_coord_label.visible = false
		return

	var world_pos = origin + direction * t
	var hex = hex_map.get_hex_grid().world_to_axial(world_pos)
	hex_coord_label.text = "[q:%d, r:%d]" % [hex.x, hex.y]
	hex_coord_label.visible = true
	hex_coord_label.position = mouse_pos + Vector2(16, -8)

func _connect_movement_signals() -> void:
	movement_client.plotting_started.connect(_on_plotting_started)
	movement_client.hex_selected.connect(_on_hex_selected)
	movement_client.undo_complete.connect(_on_undo_complete)
	movement_client.plotting_cancelled.connect(_on_plotting_cancelled)
	movement_client.movement_submitted.connect(_on_movement_submitted)
	movement_client.plotting_error.connect(_on_plotting_error)

func _setup_scenario(scenario: Dictionary) -> void:
	Trace.trace_log("GameController", "Setting up scenario: %s" % scenario.get("name", "Unknown"))

	# Setup map settings
	if scenario.has("map") and hex_map:
		var map_config = scenario.map

		# Setup hex map texture if specified
		if map_config.has("map_texture"):
			var texture_path = map_config.map_texture
			if ResourceLoader.exists(texture_path):
				var texture = load(texture_path) as Texture2D
				hex_map.set_water_texture(texture)

		# Setup hex grid visibility
		if map_config.has("show_hex"):
			hex_map.set_hex_grid_visible(map_config.show_hex)
	# Legacy support for old format
	elif scenario.has("map_texture") and hex_map:
		var texture_path = scenario.map_texture
		if ResourceLoader.exists(texture_path):
			var texture = load(texture_path) as Texture2D
			hex_map.set_water_texture(texture)

	# Spawn ships (create both state and view)
	if scenario.has("ships"):
		for ship_data in scenario.ships:
			_spawn_ship(ship_data)

func _spawn_ship(ship_data: Dictionary) -> void:
	var ship_type_id = ship_data.get("ship_type", "")
	var type_def = DataManager.get_ship_definition(ship_type_id)

	if type_def == null:
		push_error("Ship definition not found: %s" % ship_type_id)
		return

	# Create Ship (immutable identity + type data) from scenario + type definition
	var ship_ref = Ship.initialize_from_scenario(ship_data, type_def.to_dict())

	# Create ship state (mutable game data only)
	var ship_state = ShipState.new()
	ship_state.initialize_from_scenario(ship_data, ship_ref)

	# Add state to GameState (a duplicate id is rejected there, with an error naming it)
	if not GameState.add_ship(ship_state):
		return

	# Create ship view (presentation only)
	var ship_view = ShipView.new()
	ship_view.name = "ShipView_" + ship_state.ship_id
	ships_container.add_child(ship_view)

	# Initialize view from state
	if hex_map:
		ship_view.initialize(ship_state, hex_map.get_hex_grid())

	# Track view
	ship_views[ship_state.ship_id] = ship_view

	# Connect selection signal
	ship_view.selected.connect(func(): _select_ship(ship_state.ship_id))

	Trace.trace_log("GameController", "Spawned ship: %s for player %d" % [ship_state.ship_name, ship_state.player_id])

func _unhandled_input(event: InputEvent) -> void:
	if game_over_panel:
		return  # the result card is modal: nothing reaches the map
	if is_pause_menu_open():
		get_viewport().set_input_as_handled()  # no map, End Turn or skip keys while paused
		return
	if event is InputEventMouseMotion:
		_update_plotting_hover(event.position)
		return

	# Handle keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		if _combat_playback_active and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_skip_combat_playback()
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and _end_turn_available():
			_on_end_turn_pressed()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_center_camera_on_all_ships()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_F12:
			_toggle_developer_ui()
			get_viewport().set_input_as_handled()
			return

	# Handle mouse click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# If plotting, try hex selection first
		if movement_client and movement_client.is_plotting():
			var hex = _get_hex_from_screen_pos(event.position)
			if hex != Vector2i(-99, -99):
				movement_client.select_hex(hex)
				get_viewport().set_input_as_handled()
				return

		# Fall through to ship selection
		_handle_ship_selection(event.position)
		get_viewport().set_input_as_handled()

func _get_hex_from_screen_pos(screen_pos: Vector2) -> Vector2i:
	if not camera or not hex_overlay or not hex_map:
		return Vector2i(-99, -99)

	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos)

	# Intersect with Y=0 plane
	if abs(direction.y) < 0.001:
		return Vector2i(-99, -99)

	var t = -origin.y / direction.y
	if t < 0:
		return Vector2i(-99, -99)

	var world_pos = origin + direction * t
	return hex_overlay.get_valid_hex_at_world_pos(world_pos, hex_map.get_hex_grid())

func _update_plotting_hover(screen_pos: Vector2) -> void:
	if not movement_client or not movement_client.is_plotting():
		if _last_hover_hex != Vector2i(-99, -99):
			_clear_hover()
		return
	var hex = _get_hex_from_screen_pos(screen_pos)  # valid hex or (-99,-99)
	if hex == _last_hover_hex:
		return  # same hex — nothing to update
	_last_hover_hex = hex
	_show_collision_warning(hex)
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
	_last_hover_hex = Vector2i(-99, -99)
	if ship_indicators:
		ship_indicators.clear_hover()
	if indicator_overlay:
		indicator_overlay.clear_hover()

func _handle_ship_selection(screen_pos: Vector2) -> void:
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0

	var space_state = hex_map.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)

	if result.is_empty():
		_deselect_ship()
		return

	# Check if we hit a ship
	var ship_view = _find_ship_view_from_collider(result.collider)
	if not ship_view:
		return
	var ship_state = GameState.get_ship(ship_view.state_id)
	if not ship_state:
		return

	if ship_state.player_id == HUMAN_PLAYER_ID:
		# Own ship: full selected-ship UI; status dialog stays hidden until info icon.
		# The camera does not move: the player clicked what they can already see.
		# While planning, the orders panel follows (one selected ship everywhere); a ship being
		# plotted keeps the selection until its plot is submitted or cancelled.
		if current_planning_ui and is_instance_valid(current_planning_ui) \
				and GameState.current_phase == GameState.GamePhase.PLANNING:
			if movement_client and movement_client.is_plotting():
				return
			current_planning_ui.select_ship(ship_view.state_id)
			return
		_select_ship(ship_view.state_id)
	else:
		# Enemy ship: read-only status dialog only, no indicators.
		_deselect_ship()
		if ship_status_panel:
			ship_status_panel.show_ship_status_from_state(ship_state)

func _find_ship_view_from_collider(collider: Node) -> ShipView:
	var node = collider
	while node:
		if node is ShipView:
			return node
		node = node.get_parent()
	return null

func _select_ship(ship_id: String) -> void:
	# Clear any previous selection visuals (dialog starts hidden on a new selection)
	if ship_indicators:
		ship_indicators.clear_selected()
	if ship_status_panel:
		ship_status_panel.visible = false

	selected_ship_id = ship_id
	_show_selected_indicators(ship_id)

func _on_info_toggled(ship_id: String) -> void:
	if ship_status_panel and not ship_id.is_empty():
		var ship_state = GameState.get_ship(ship_id)
		if ship_state:
			ship_status_panel.toggle(ship_state)

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

func _deselect_ship() -> void:
	selected_ship_id = ""
	if ship_indicators:
		ship_indicators.clear_selected()
	if indicator_overlay:
		indicator_overlay.clear_selected()
	if ship_status_panel:
		ship_status_panel.visible = false

func _center_camera_on_all_ships() -> void:
	var all_ships = GameState.get_all_ships()
	if all_ships.is_empty():
		return

	# Gather all ship positions from views
	var ship_positions: Array[Vector3] = []
	for ship_view in ship_views.values():
		ship_positions.append(ship_view.global_position)

	# Call camera method to center on ships
	if camera and camera.has_method("center_on_ships"):
		camera.center_on_ships(ship_positions)

func _on_phase_changed(phase: GameState.GamePhase) -> void:
	# Selection is a planning-time affordance — clear it (and any hover) on every phase change
	# so the one-shot indicator snapshot can't go stale across resolution/turn boundaries.
	_deselect_ship()
	if indicator_overlay:
		indicator_overlay.set_info_enabled(true)
	_hover_candidates.clear()
	_clear_hover()
	_close_fire_panel()
	if phase != GameState.GamePhase.POST_COMBAT:
		_clear_end_turn_ui()
	Trace.trace_log("GameController", "Phase changed to: %s" % GameState.get_phase_name())

	match phase:
		GameState.GamePhase.PLANNING:
			_enter_planning_phase()
		GameState.GamePhase.MOVEMENT_RESOLUTION:
			_resolve_movement()
		GameState.GamePhase.POST_COMBAT:
			_sync_all_views()  # drift and other late phases move ships without their own playback
			_enter_post_combat_phase()

func _enter_planning_phase() -> void:
	Trace.trace_log("GameController", "Entering planning phase for player 0")

	# Clear any leftover overlays from previous turn
	if hex_overlay:
		hex_overlay.clear_everything()
	submitted_paths.clear()
	combat_panel = null  # freed below when the planning UI takes the context panel
	if combat_log_panel:
		combat_log_panel.auto_expand(false)  # the map is what matters while plotting

	# Get player ships
	var player_0_ships = GameState.get_player_ships(0)
	if player_0_ships.is_empty():
		Trace.trace_log("GameController", "No ships for player 0")
		return

	# Create planning UI
	if not current_planning_ui:
		current_planning_ui = PlanningPhaseUI.instantiate()

		# Connect signals
		current_planning_ui.ship_selected.connect(_on_planning_ship_selected)
		current_planning_ui.action_toggled.connect(_on_planning_action_toggled)
		current_planning_ui.undo_pressed.connect(_on_plotting_undo_pressed)
		current_planning_ui.undo_all_pressed.connect(_on_plotting_undo_all_pressed)
		current_planning_ui.submit_pressed.connect(_on_plotting_submit_pressed)
		current_planning_ui.cancel_pressed.connect(_on_plotting_cancel_pressed)
		current_planning_ui.end_planning_pressed.connect(_on_end_planning_pressed)
		current_planning_ui.sail_change_requested.connect(_on_sail_change_requested)
		current_planning_ui.status_requested.connect(_on_info_toggled)

	# Load into context panel (must be done before setup to ensure @onready nodes are available)
	if context_panel:
		context_panel.set_context_title("Planning Phase")
		context_panel.set_context_content(current_planning_ui)

	# Setup with player ships (after adding to tree so @onready nodes are initialized)
	current_planning_ui.setup_for_player(player_0_ships)

	# Hide old planning panel (will be deprecated)
	if planning_panel:
		planning_panel.visible = false

func _on_planning_ship_selected(ship_id: String) -> void:
	Trace.trace_log("GameController", "Planning UI: Ship selected - %s" % ship_id)

	# Get ship state and view
	var ship_state = GameState.get_ship(ship_id)
	var ship_view = ship_views.get(ship_id)

	if not ship_state or not ship_view:
		Trace.trace_log("GameController", "Warning: Ship not found: %s" % ship_id)
		return

	# The plotting controls belong to the selected ship: a plot left open for another ship ends.
	if movement_client and movement_client.is_plotting() and movement_client.get_active_ship_id() != ship_id:
		var plotting_id := movement_client.get_active_ship_id()
		movement_client.cancel()
		if current_planning_ui:
			current_planning_ui.deactivate_movement_button(plotting_id)

	# Bring the ship into view only if it is off-screen or near the edge: a smooth pan,
	# never a rotation or zoom change (north stays up unless the player turns the camera).
	if camera and camera.has_method("pan_to_if_needed"):
		camera.pan_to_if_needed(ship_view.global_position)

	# Select ship on map (highlight)
	_select_ship(ship_id)

func _on_sail_change_requested(ship_id: String, target: String) -> void:
	# Single-player: plot player 0's sail change under the server guard  SCV:ALLOW
	var reason := "Sail changes can only be ordered on the server"
	if GameState.is_server and GameState.sail_controller:
		reason = GameState.sail_controller.plot_sail_change(HUMAN_PLAYER_ID, ship_id, target)
	Trace.trace_log("GameController", "Sail change %s -> '%s': %s" % [ship_id, target, reason if reason != "" else "accepted"])
	if current_planning_ui:
		current_planning_ui.show_sail_result(reason)

func _on_planning_action_toggled(ship_id: String, action_type: String, active: bool) -> void:
	Trace.trace_log("GameController", "Action '%s' toggled to %s for ship %s" % [action_type, active, ship_id])

	# Store action state locally
	if not selected_actions.has(ship_id):
		selected_actions[ship_id] = {}
	selected_actions[ship_id][action_type] = active

	# Handle movement action
	if action_type == "movement" and movement_client:
		if active:
			# If re-plotting a submitted ship, clear the old submission first
			if current_planning_ui and current_planning_ui.is_ship_submitted(ship_id):
				submitted_paths.erase(ship_id)
				current_planning_ui.mark_ship_unsubmitted(ship_id)
				# Clear the submitted path overlay
				if hex_overlay:
					hex_overlay.clear_submitted_path(ship_id)
				if GameState.is_server:
					# Single-player shortcut: clear the old movement plot (keeping any sail order)
					# under the server guard  SCV:ALLOW
					GameState.ship_controller.set_plotted_movement(ship_id, [])
				Trace.trace_log("GameController", "Re-plotting ship %s — cleared previous submission" % ship_id)

			var ship_state = GameState.get_ship(ship_id)
			if ship_state:
				movement_client.start_plotting(ship_state.player_id, ship_id)
		else:
			if movement_client.is_plotting_ship(ship_id):
				movement_client.cancel()

func _on_end_planning_pressed() -> void:
	# Double-check all ships are submitted
	if current_planning_ui and not current_planning_ui.are_all_ships_submitted():
		push_warning("End Planning pressed but not all ships submitted")
		return

	Trace.trace_log("GameController", "End Planning pressed — all player-0 ships submitted")

	# Cancel any stale plotting session
	if movement_client and movement_client.is_plotting():
		movement_client.cancel()

	# Single-player shortcut: call controller directly under server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		GameState.phase_controller.player_submit_plan(0)
		# Stub: submit player 1 immediately (StubAI will replace this in S08)
		GameState.phase_controller.player_submit_plan(1)
	else:
		push_warning("Client plan submission not yet implemented — needs network layer")

func _on_player_plan_submitted() -> void:
	_on_end_planning_pressed()

# ============================================================================
# Movement Plotting UI Callbacks
# ============================================================================

func _on_plotting_undo_pressed() -> void:
	if movement_client:
		movement_client.undo()

func _on_plotting_undo_all_pressed() -> void:
	if movement_client:
		movement_client.undo_all()

func _on_plotting_submit_pressed() -> void:
	if movement_client:
		movement_client.submit()

func _on_plotting_cancel_pressed() -> void:
	if movement_client:
		var ship_id = movement_client.get_active_ship_id()
		movement_client.cancel()
		# Deactivate the movement toggle button
		if current_planning_ui and not ship_id.is_empty():
			current_planning_ui.deactivate_movement_button(ship_id)

# ============================================================================
# Movement Plotting Response Handlers
# ============================================================================

func _on_plotting_started(ship_id: String, valid_hexes: Variant, remaining_ma_val: int, is_tacking: bool = false) -> void:
	Trace.trace_log("GameController", "Plotting started for ship %s" % ship_id)
	# Plotting one of our ships: a status panel left open for another ship would compete with it.
	if ship_status_panel:
		ship_status_panel.hide_unless_showing(ship_id)
	# Nothing clickable may sit over the hexes while a course is being plotted.
	if indicator_overlay:
		indicator_overlay.set_info_enabled(false)
	_ma_by_len = {0: remaining_ma_val}
	_allowance_notes.clear()
	var vnh = valid_hexes as MovementTypes.ValidNextHexes
	_update_collision_hexes(vnh, [])
	var ship_state = GameState.get_ship(ship_id)
	if hex_overlay and hex_map:
		var hex_grid = hex_map.get_hex_grid()
		hex_overlay.show_valid_hexes(vnh.get_all_valid_moves(), hex_grid, _collision_names.keys())

		# Show blocked directions as red overlays
		if ship_state:
			var blocked = _calculate_blocked_hexes(vnh, ship_state.hex_position, ship_state.facing, hex_grid)
			hex_overlay.show_blocked_hexes(blocked, hex_grid)

	if current_planning_ui:
		# Read-only queries for the "limited by acceleration" note  SCV:ALLOW
		var table_ma: int = GameState.ship_controller.get_movement_allowance(ship_id) if ship_state else remaining_ma_val
		var speed_last_turn: int = ship_state.speed if ship_state else 0
		var accel := 0
		if ship_state and ship_state.ship:
			accel = DataManager.get_speed_change("acceleration", ship_state.ship.maneuverability.to_lower())
		var can_submit_val: bool = movement_client.can_submit if movement_client else false
		current_planning_ui.show_plotting_controls(ship_id, remaining_ma_val, table_ma, speed_last_turn, accel,
			can_submit_val)
		_update_tacking_display(is_tacking)
	_rebuild_hover_candidates(vnh)
	_show_collision_warning(_last_hover_hex)

func _on_hex_selected(plotted_path: Array, valid_hexes: Variant, can_submit_val: bool, remaining_ma_val: int, is_tacking: bool = false) -> void:
	_show_plot_step(plotted_path, valid_hexes as MovementTypes.ValidNextHexes, can_submit_val, remaining_ma_val, is_tacking)

func _on_undo_complete(plotted_path: Array, valid_hexes: Variant, can_submit_val: bool, remaining_ma_val: int, is_tacking: bool = false) -> void:
	_show_plot_step(plotted_path, valid_hexes as MovementTypes.ValidNextHexes, can_submit_val, remaining_ma_val, is_tacking)

## Redraw the offered hexes, the plotted path and the readout after a step or an undo.
func _show_plot_step(plotted_path: Array, vnh: MovementTypes.ValidNextHexes, can_submit_val: bool, remaining_ma_val: int, is_tacking: bool) -> void:
	_update_collision_hexes(vnh, plotted_path)
	if hex_overlay and hex_map:
		var hex_grid = hex_map.get_hex_grid()
		hex_overlay.show_valid_hexes(vnh.get_all_valid_moves(), hex_grid, _collision_names.keys())
		hex_overlay.show_plotted_path(plotted_path, hex_grid)

		# Show blocked directions from current position
		var current_hex: Vector2i
		var current_facing: int
		if plotted_path.size() > 0:
			var last_step = plotted_path[-1]
			current_hex = last_step.hex
			current_facing = last_step.facing
		else:
			var ship_state = GameState.get_ship(movement_client.active_ship_id)
			current_hex = ship_state.hex_position
			current_facing = ship_state.facing
		var blocked = _calculate_blocked_hexes(vnh, current_hex, current_facing, hex_grid)
		hex_overlay.show_blocked_hexes(blocked, hex_grid)

	if current_planning_ui:
		current_planning_ui.update_plotting_state(plotted_path, remaining_ma_val, can_submit_val)
		current_planning_ui.set_allowance_note(PlanningText.plot_note(
			_track_allowance_change(plotted_path, remaining_ma_val), _plotted_heading_code(plotted_path)))
		_update_tacking_display(is_tacking)
	_rebuild_hover_candidates(vnh)
	_show_collision_warning(_last_hover_hex)

## Record the server's remaining movement for this path length and return the note to show: the
## latest step whose pivot changed the allowance (not just spent a point), "" when none did.
func _track_allowance_change(plotted_path: Array, remaining_ma_val: int) -> String:
	var n := plotted_path.size()
	for length in _ma_by_len.keys():
		if length > n:
			_ma_by_len.erase(length)
			_allowance_notes.erase(length)
	if n > 0 and _ma_by_len.has(n - 1) and not _ma_by_len.has(n):
		var ship_state: ShipState = GameState.get_ship(movement_client.active_ship_id) if movement_client else null
		if ship_state and hex_map and GameState.environment:
			var grid: HexGrid = hex_map.get_hex_grid()
			var wind: int = GameState.environment.wind_direction
			var old_facing: int = plotted_path[n - 2].facing if n >= 2 else ship_state.facing
			_allowance_notes[n] = PlanningText.allowance_change_note(_ma_by_len[n - 1], remaining_ma_val,
				grid.get_wind_facing(old_facing, wind), grid.get_wind_facing(plotted_path[n - 1].facing, wind))
	_ma_by_len[n] = remaining_ma_val
	for length in range(n, 0, -1):
		if str(_allowance_notes.get(length, "")) != "":
			return _allowance_notes[length]
	return ""


## Wind-facing code (L, C, B, R) of the heading at the end of the plotted path ("" if unknown).
func _plotted_heading_code(plotted_path: Array) -> String:
	if plotted_path.is_empty() or not hex_map or not GameState.environment:
		return ""
	return hex_map.get_hex_grid().get_wind_facing(plotted_path[-1].facing, GameState.environment.wind_direction)


## Which offered hexes hold another ship, and whether the plotted path already enters one.
func _update_collision_hexes(vnh: MovementTypes.ValidNextHexes, plotted_path: Array) -> void:
	var active_id: String = movement_client.active_ship_id if movement_client else ""
	var ships: Array = GameState.get_all_ships()
	var offered: Array = []
	if vnh:
		for vm in vnh.get_all_valid_moves():
			offered.append(vm.hex)
	_collision_names = PlanningText.occupied_hexes(offered, ships, active_id)
	_path_collision_text = ""
	var path_hexes: Array = []
	for step in plotted_path:
		path_hexes.append(step.hex)
	var on_path := PlanningText.occupied_hexes(path_hexes, ships, active_id)
	for hex in path_hexes:
		if on_path.has(hex):
			_path_collision_text = PlanningText.collision_text(on_path[hex])
			break

## The plotting area's warning: the hovered hex's, otherwise the plotted path's ("" hides it).
func _show_collision_warning(hover_hex: Vector2i) -> void:
	if not current_planning_ui:
		return
	var text := _path_collision_text
	if _collision_names.has(hover_hex):
		text = PlanningText.collision_text(_collision_names[hover_hex])
	current_planning_ui.set_collision_warning(text)

func _rebuild_hover_candidates(valid_hexes: MovementTypes.ValidNextHexes) -> void:
	_hover_candidates.clear()
	if valid_hexes == null:
		return
	for vm in valid_hexes.get_all_valid_moves():
		_hover_candidates[vm.hex] = vm.metadata.resulting_facing

func _on_plotting_cancelled(ship_id: String) -> void:
	if indicator_overlay:
		indicator_overlay.set_info_enabled(true)
	_hover_candidates.clear()
	_collision_names.clear()
	_path_collision_text = ""
	_clear_hover()
	Trace.trace_log("GameController", "Plotting cancelled for ship %s" % ship_id)
	if hex_overlay:
		hex_overlay.clear_all()

	if current_planning_ui:
		current_planning_ui.hide_plotting_controls()

func _on_movement_submitted(ship_id: String, final_path: Array) -> void:
	if indicator_overlay:
		indicator_overlay.set_info_enabled(true)
	_hover_candidates.clear()
	_collision_names.clear()
	_path_collision_text = ""
	_clear_hover()
	Trace.trace_log("GameController", "Movement submitted for ship %s: %d steps" % [ship_id, final_path.size()])

	# Store submitted path
	submitted_paths[ship_id] = final_path

	if hex_overlay and hex_map:
		hex_overlay.clear_valid_hexes()
		hex_overlay.clear_plotted_path()
		hex_overlay.show_submitted_path(ship_id, final_path, hex_map.get_hex_grid())

	if current_planning_ui:
		current_planning_ui.hide_plotting_controls()
		current_planning_ui.mark_ship_submitted(ship_id)

func _on_plotting_error(error_code: String, message: String) -> void:
	Trace.trace_log("GameController", "Plotting error: %s - %s" % [error_code, message])


func _update_tacking_display(is_tacking: bool) -> void:
	if not current_planning_ui or not movement_client:
		return
	if not is_tacking:
		current_planning_ui.update_tacking_state(false, 0.0)
		return

	var ship_state = GameState.get_ship(movement_client.active_ship_id)
	if not ship_state or not ship_state.ship:
		current_planning_ui.update_tacking_state(false, 0.0)
		return

	var maneuverability = ship_state.ship.maneuverability.to_lower()
	var wind_speed = GameState.environment.wind_speed if GameState.environment else 2
	var probability = DataManager.get_tacking_percent(maneuverability, wind_speed)
	Trace.trace_log("GameController", "Tacking attempt: %s, maneuverability=%s, wind_speed=%d, probability=%.0f%%" % [
		ship_state.ship_id, maneuverability, wind_speed, probability * 100.0
	])
	current_planning_ui.update_tacking_state(true, probability)


func _calculate_blocked_hexes(valid_hexes: MovementTypes.ValidNextHexes,
	current_hex: Vector2i,
	current_facing: int,
	hex_grid: HexGrid) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	if valid_hexes.forward.is_empty():
		blocked.append(hex_grid.get_neighbor(current_hex.x, current_hex.y, current_facing))
	if valid_hexes.port == null:
		var port_dir = (current_facing + 5) % 6
		blocked.append(hex_grid.get_neighbor(current_hex.x, current_hex.y, port_dir))
	if valid_hexes.starboard == null:
		var starboard_dir = (current_facing + 1) % 6
		blocked.append(hex_grid.get_neighbor(current_hex.x, current_hex.y, starboard_dir))
	return blocked

# ============================================================================
# Phase Resolution
# ============================================================================

func _resolve_movement() -> void:
	if not GameState.is_server:
		Trace.trace_log("GameController", "[Client] Waiting for movement resolution from server")
		return

	# Resolution is now driven by TurnPhaseController:
	# 1. Phase controller runs resolver and emits resolution_log_ready
	# 2. _on_resolution_log_ready creates playback controller and animates
	# 3. On playback_completed, we apply results and advance phase
	Trace.trace_log("GameController", "[Server] MOVEMENT_RESOLUTION phase entered, awaiting playback...")


@warning_ignore("shadowed_global_identifier")  # "log" is the project's convention for ResolutionLog
func _on_resolution_log_ready(log: MovementTypes.ResolutionLog) -> void:
	Trace.trace_log("GameController", "[Playback] Resolution log received: %d ships, %d impulses" % [log.ship_results.size(), log.max_impulses])

	# Clear hex overlay from planning
	if hex_overlay:
		hex_overlay.clear_everything()

	# Create playback controller
	if playback_controller and playback_controller.is_inside_tree():
		playback_controller.queue_free()

	var hex_grid_ref: HexGrid = hex_map.get_hex_grid() if hex_map else HexGrid.new()
	playback_controller = MovementResolutionPlaybackController.new(hex_grid_ref, ship_views, 0)
	playback_controller.name = "PlaybackController"
	add_child(playback_controller)

	playback_controller.playback_completed.connect(_on_playback_completed, CONNECT_ONE_SHOT)
	playback_controller.play(log)


func _on_playback_completed() -> void:
	Trace.trace_log("GameController", "[Playback] Playback complete, applying results and advancing")

	# Clean up playback controller
	if playback_controller:
		playback_controller.queue_free()
		playback_controller = null

	# Intentional view→controller callback: phase controller applies results and advances  SCV:ALLOW
	if GameState.phase_controller:
		GameState.phase_controller.on_playback_completed()

	_sync_all_views()

# ============================================================================
# Fire Declaration (COMBAT_RESOLUTION, DECLARE step)
# ============================================================================

func _on_fire_declaration_requested() -> void:
	var player_ships := GameState.get_player_ships(HUMAN_PLAYER_ID)
	var ship_ids: Array = []
	for ship in player_ships:
		ship_ids.append(ship.ship_id)

	var panel: Control = FireDeclarationPanelScene.instantiate()
	# The context panel parents the new content and frees the old; the cached planning UI is
	# among the freed nodes, so drop the reference and let the next turn build a fresh one.
	if context_panel:
		context_panel.set_context_title("Fire Orders")
		context_panel.set_context_content(panel)
	else:
		add_child(panel)
	current_planning_ui = null
	fire_panel = panel
	panel.fire_pressed.connect(_on_fire_pressed)
	panel.ship_focused.connect(_refresh_fire_overlay)
	panel.selection_changed.connect(_refresh_fire_overlay)

	if panel.setup(ship_ids) == 0:
		# Nothing to declare (only the enemy has a shot): explain why, then pass.
		Trace.trace_log("GameController", "No eligible shots for player 0 - submitting empty fire orders")
		_close_fire_panel()
		_show_combat_panel(_no_shot_lines(player_ships))
		_submit_fire_orders([])
		return
	if combat_log_panel:
		combat_log_panel.auto_expand(false)  # keep the arcs and targets visible
	# setup() focused the first ship, which drew its arcs and framed it with its targets.


## "No broadside bears..." plus one no-shot line per own ship (the same wording the fire panel uses
## for a ship without a shot), the reason previewed against that ship's nearest enemy.
func _no_shot_lines(own_ships: Array) -> Array[String]:
	var lines: Array[String] = [NO_SHOT_HEADLINE]
	var grid: HexGrid = GameState.fire_geometry.hex_grid if GameState.fire_geometry else null
	for ship: ShipState in own_ships:
		lines.append(FirePanelScript.no_shot_line(ship.ship_name, FirePanelScript.ship_no_shot_reason(
			ship, GameState.get_all_ships(), GameState.gunnery_calculator, grid)))
	return lines


## Context-panel content titled "Combat" while the exchange resolves and plays back.
func _show_combat_panel(lines: Array[String]) -> void:
	var box := VBoxContainer.new()
	box.name = "CombatPanel"
	box.add_theme_constant_override("separation", 8)
	for i in range(lines.size()):
		var label := Label.new()
		label.text = lines[i]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	var hint := Label.new()
	hint.text = "The combat log below shows each shot."
	hint.theme_type_variation = &"SecondaryLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	if context_panel:
		context_panel.set_context_title("Combat")
		context_panel.set_context_content(box)
	else:
		add_child(box)
	current_planning_ui = null
	combat_panel = box


func _on_fire_pressed(orders: Array) -> void:
	var panel := fire_panel
	if panel:
		panel.fire_button.disabled = true  # no double submit while the server decides
	var reason := _submit_fire_orders(orders)
	if reason != "":
		# Rejected: the panel stays open (re-enabled) with the reason.
		if is_instance_valid(panel) and panel == fire_panel:
			panel.show_error(reason)
		return
	# Accepted: the declare step is over, so the panel must not stay interactive.
	_close_fire_panel()
	var lines: Array[String] = ["Your orders: %s." % FirePanelScript.fire_button_text(orders.size())]
	_show_combat_panel(lines)


## Remove the fire panel (if any) and its arcs. Safe to call on any path out of the declare step.
func _close_fire_panel() -> void:
	if hex_overlay:
		hex_overlay.clear_arcs()
	if fire_panel and is_instance_valid(fire_panel):
		fire_panel.queue_free()
	fire_panel = null


## Returns "" when the server accepted the orders, otherwise its rejection reason.
func _submit_fire_orders(orders: Array) -> String:
	# Single-player: submit player 0's orders under the server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		return GameState.phase_controller.player_submit_fire_orders(HUMAN_PLAYER_ID, orders)
	push_warning("Client fire submission not yet implemented - needs network layer")
	return "fire orders can only be submitted on the server"


func _refresh_fire_overlay(ship_id: String) -> void:
	if not hex_overlay or not fire_panel or not GameState.fire_geometry:
		return
	var ship_state := GameState.get_ship(ship_id)
	if ship_state == null:
		return
	hex_overlay.clear_arcs()
	var geometry: FireGeometry = GameState.fire_geometry
	hex_overlay.show_arc(geometry.broadside_hexes(ship_state.hex_position, ship_state.facing,
		ShipState.PORT, FireGeometry.MAX_RANGE), ShipState.PORT)
	hex_overlay.show_arc(geometry.broadside_hexes(ship_state.hex_position, ship_state.facing,
		ShipState.STARBOARD, FireGeometry.MAX_RANGE), ShipState.STARBOARD)
	var target_hexes: Array[Vector2i] = []
	for target_id in fire_panel.get_target_ids(ship_id):
		var target := GameState.get_ship(target_id)
		if target:
			target_hexes.append(target.hex_position)
	hex_overlay.show_target_highlights(target_hexes)
	_frame_fire_view(ship_state, target_hexes)


## Pan (zooming out only if both cannot fit) so the firing ship and its chosen targets are on
## screen, clear of the side panels. Never rotates the camera.
func _frame_fire_view(ship_state: ShipState, target_hexes: Array[Vector2i]) -> void:
	if not camera or not camera.has_method("frame_points_if_needed") or not hex_map:
		return
	var grid: HexGrid = hex_map.get_hex_grid()
	var points: Array[Vector3] = [grid.axial_to_world(ship_state.hex_position.x, ship_state.hex_position.y)]
	for hex in target_hexes:
		points.append(grid.axial_to_world(hex.x, hex.y))
	camera.frame_points_if_needed(points, _map_safe_rect())


## The part of the viewport not covered by the context panel (left) or the log bar (bottom).
func _map_safe_rect() -> Rect2:
	var rect := get_viewport().get_visible_rect()
	var left := 0.0
	# The ContextPanel control spans the screen; its PanelContainer is the visible strip.
	if context_panel and context_panel.visible and context_panel.get("panel_container"):
		left = minf(context_panel.panel_container.get_global_rect().end.x, rect.size.x * 0.5)
	var bottom := CombatLogPanel.BAR_HEIGHT + 20.0
	if combat_log_panel and combat_log_panel.is_expanded():
		bottom = rect.size.y - combat_log_panel.get_global_rect().position.y + 10.0
	return Rect2(rect.position.x + left, rect.position.y, rect.size.x - left, rect.size.y - bottom)


@warning_ignore("shadowed_global_identifier")
func _on_combat_log_ready(log: PhaseEvents.PhaseLog) -> void:
	_close_fire_panel()
	if _combat_playback_active:
		return  # already playing this exchange
	_combat_playback_active = true
	_combat_playback_skip = false
	_play_combat_log(log)


## Reveal the combat events one at a time (skippable), syncing views as damage is read,
## then tell the phase controller playback is finished.
func _play_combat_log(combat_log: PhaseEvents.PhaseLog) -> void:
	var instant := skip_post_combat_delay or combat_log_panel == null
	if combat_log_panel:
		combat_log_panel.auto_expand(true)
		combat_log_panel.set_skip_hint(not instant)
	if not instant:
		for ev in CombatLogPanel.playback_events(combat_log):
			if _combat_playback_skip or _leave_pending:
				break
			combat_log_panel.set_reveal_limit(combat_log.events.find(ev) + 1)
			if CombatLogPanel.syncs_views(ev):
				_sync_all_views()
			var waited := 0.0
			while waited < COMBAT_REVEAL_SECONDS and not _combat_playback_skip:
				await get_tree().process_frame
				waited += get_process_delta_time()
	if combat_log_panel:
		combat_log_panel.clear_reveal_limit()
		combat_log_panel.set_skip_hint(false)
	_sync_all_views()
	_finish_combat_playback()


func _skip_combat_playback() -> void:
	if _combat_playback_active:
		_combat_playback_skip = true


func _finish_combat_playback() -> void:
	if not _combat_playback_active:
		return
	_combat_playback_active = false
	var phase_controller = GameState.phase_controller
	if phase_controller == null:
		return
	# The phase may have moved on (or the game ended) while we were revealing lines.
	if phase_controller.current_phase != TurnPhaseController.GamePhase.COMBAT_RESOLUTION \
			or phase_controller.combat_step != TurnPhaseController.CombatStep.RESOLVE:
		return
	# Intentional view->controller callback so the turn keeps cycling  SCV:ALLOW
	phase_controller.on_combat_playback_completed()

func _enter_post_combat_phase() -> void:
	if skip_post_combat_delay:
		_request_end_turn()
		return
	Trace.trace_log("GameController", "Post-combat phase - waiting for player to end turn")
	if combat_log_panel:
		combat_log_panel.auto_expand(true)  # let the player review the turn
	_show_end_turn_ui()


func _show_end_turn_ui() -> void:
	var box := VBoxContainer.new()
	box.name = "EndTurnPanel"
	box.add_theme_constant_override("separation", 12)
	var hint := Label.new()
	hint.text = "Review the combat log, then end the turn."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	# Every phase keeps its main button pinned at the bottom of the side panel.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(HSeparator.new())
	var key_hint := Label.new()
	key_hint.text = "Space or Enter also ends the turn."
	key_hint.theme_type_variation = &"SecondaryLabel"
	key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key_hint)
	var button := Button.new()
	button.name = "EndTurnButton"
	button.text = "End Turn"
	button.custom_minimum_size = Vector2(0, 44)
	button.focus_mode = Control.FOCUS_NONE  # Space/Enter are handled once, in _unhandled_input
	button.pressed.connect(_on_end_turn_pressed)
	box.add_child(button)
	if context_panel:
		context_panel.set_context_title("Turn %d complete" % GameState.phase_controller.current_turn)
		context_panel.set_context_content(box)
	else:
		add_child(box)
	current_planning_ui = null  # freed by the context panel; the next turn builds a fresh one
	end_turn_panel = box
	end_turn_button = button
	combat_panel = null  # freed by the context panel


func _clear_end_turn_ui() -> void:
	if end_turn_panel and is_instance_valid(end_turn_panel):
		end_turn_panel.queue_free()
	end_turn_panel = null
	end_turn_button = null


## The End Turn key shortcut only applies while the button is showing and no combat playback is
## running (that playback owns Space/Enter as its skip keys).
func _end_turn_available() -> bool:
	return end_turn_button != null and is_instance_valid(end_turn_button) \
			and not end_turn_button.disabled and not _combat_playback_active


func _on_end_turn_pressed() -> void:
	if end_turn_button:
		end_turn_button.disabled = true  # one press per turn
	_request_end_turn()


func _request_end_turn() -> void:
	# Single-player shortcut: end the turn under server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		GameState.phase_controller.player_end_turn(HUMAN_PLAYER_ID)
	else:
		push_warning("Client phase advance not yet implemented - needs network layer")


# ============================================================================
# Game Over
# ============================================================================

func _on_game_over(result: Dictionary) -> void:
	Trace.trace_log("GameController", "Game over", result)
	_close_fire_panel()
	_clear_end_turn_ui()
	_deselect_ship()
	_sync_all_views()
	if movement_client and movement_client.is_plotting():
		movement_client.cancel()
	if hex_overlay:
		hex_overlay.clear_everything()
	current_planning_ui = null
	if context_panel:
		var done := Label.new()
		done.text = "The battle is over."
		context_panel.set_context_title("Game over")
		context_panel.set_context_content(done)  # also frees any leftover planning controls
	game_over_panel = GameOverPanelScene.instantiate()
	if ui:
		ui.add_child(game_over_panel)
	else:
		add_child(game_over_panel)
	game_over_panel.show_result(result, GameState.get_all_ships())
	game_over_panel.back_requested.connect(_on_back_to_scenarios)
	if pause_menu:
		pause_menu.close()
	if menu_button:
		menu_button.visible = false  # the result card has its own way out
	_frame_final_position.call_deferred()


## Keep the final position in view below the result card (which sits at the upper centre).
func _frame_final_position() -> void:
	if not camera or not camera.has_method("frame_points_if_needed") or not game_over_panel:
		return
	var points: Array[Vector3] = []
	for view in ship_views.values():
		points.append(view.global_position)
	var safe := _map_safe_rect()
	var card_bottom := game_over_panel.get_global_rect().end.y + 10.0
	if card_bottom < safe.end.y - 80.0:
		safe = Rect2(safe.position.x, card_bottom, safe.size.x, safe.end.y - card_bottom)
	camera.frame_points_if_needed(points, safe, 40.0)


func _on_back_to_scenarios() -> void:
	if back_to_scenarios_requested.get_connections().is_empty():
		# Started on its own (e.g. `make play`) with no scene manager above: restart from the menus.
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	back_to_scenarios_requested.emit()

func _sync_all_views() -> void:
	for ship_id in ship_views.keys():
		var ship_view = ship_views[ship_id]
		var ship_state = GameState.get_ship(ship_id)
		if ship_state and ship_view and hex_map:
			ship_view.sync_to_state(ship_state, hex_map.get_hex_grid())
	if ship_status_panel:
		ship_status_panel.refresh()

func _toggle_developer_ui() -> void:
	if developer_ui:
		developer_ui.visible = not developer_ui.visible
		if developer_ui.visible:
			developer_ui.refresh_all()
			Trace.trace_log("GameController", "Developer UI opened (F12 to close)")
