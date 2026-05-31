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
const OceanViewScript = preload("res://scripts/view/ocean_view.gd")
var current_planning_ui: Control = null

# Views (presentation layer)
var ship_views: Dictionary = {}  # ship_id -> ShipView
var selected_ship_id: String = ""

# Planning phase state (client-side)
var selected_actions: Dictionary = {}  # ship_id -> {action_type -> bool}

# Movement plotting
var movement_client: MovementPlottingClient = null
var hex_overlay: Node3D = null  # HexOverlay instance
var submitted_paths: Dictionary = {}  # ship_id -> Array[PlotStep]

# Resolution playback
var playback_controller: MovementResolutionPlaybackController = null

# Debug hex coordinate display
var hex_coord_label: Label = null
var hex_coords_enabled: bool = false

# When true, POST_COMBAT auto-advances immediately instead of awaiting 2-second timer
var skip_post_combat_delay: bool = false

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

	# Set up OceanView for water shader updates
	if GameState.environment_controller and hex_map:
		var ocean_view = OceanViewScript.new(GameState, hex_map)
		ocean_view.connect_to_controller(GameState.environment_controller)
		add_child(ocean_view)
		ocean_view.update_water_shader()

	# Initialize hex overlay
	_setup_hex_overlay()

	# Initialize movement plotting client
	if GameState.movement_plotting_controller:
		movement_client = MovementPlottingClient.new(GameState.movement_plotting_controller)
		_connect_movement_signals()

	# Setup debug hex coordinate label
	_setup_hex_coord_label()
	if developer_ui:
		developer_ui.hex_coords_toggled.connect(_on_hex_coords_toggled)
		developer_ui.hex_labels_toggled.connect(_on_hex_labels_toggled)

	# Start the game
	GameState.start_new_game(scenario)

func _setup_hex_overlay() -> void:
	var overlay_script = load("res://scripts/view/hex_overlay.gd")
	hex_overlay = Node3D.new()
	hex_overlay.set_script(overlay_script)
	hex_overlay.name = "HexOverlay"
	add_child(hex_overlay)

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

	# Add state to GameState
	GameState.add_ship(ship_state)

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
	# Handle keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
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

func _handle_ship_selection(screen_pos: Vector2) -> void:
	if not camera:
		return

	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0

	var space_state = hex_map.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)

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

	# Check if we hit a ship
	var collider = result.collider
	var ship_view = _find_ship_view_from_collider(collider)

	if ship_view:
		_select_ship(ship_view.state_id)

func _find_ship_view_from_collider(collider: Node) -> ShipView:
	var node = collider
	while node:
		if node is ShipView:
			return node
		node = node.get_parent()
	return null

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
	Trace.trace_log("GameController", "Phase changed to: %s" % GameState.get_phase_name())

	match phase:
		GameState.GamePhase.PLANNING:
			_enter_planning_phase()
		GameState.GamePhase.MOVEMENT_RESOLUTION:
			_resolve_movement()
		GameState.GamePhase.POST_COMBAT:
			_enter_post_combat_phase()
		GameState.GamePhase.END_TURN:
			_end_turn()

func _enter_planning_phase() -> void:
	Trace.trace_log("GameController", "Entering planning phase for player 0")

	# Clear any leftover overlays from previous turn
	if hex_overlay:
		hex_overlay.clear_everything()
	submitted_paths.clear()

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

	# Focus camera on ship with smooth animation
	if camera and camera.has_method("focus_on_ship"):
		camera.focus_on_ship(ship_view.global_position, ship_state.facing)

	# Select ship on map (highlight)
	_select_ship(ship_id)

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
					GameState.ship_controller.clear_plotted_actions(ship_id)
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
	if hex_overlay and hex_map:
		var hex_grid = hex_map.get_hex_grid()
		var vnh = valid_hexes as MovementTypes.ValidNextHexes
		hex_overlay.show_valid_hexes(vnh.get_all_valid_moves(), hex_grid)

		# Show blocked directions as red overlays
		var ship_state = GameState.get_ship(ship_id)
		if ship_state:
			var blocked = _calculate_blocked_hexes(vnh, ship_state.hex_position, ship_state.facing, hex_grid)
			hex_overlay.show_blocked_hexes(blocked, hex_grid)

	if current_planning_ui:
		var ship_state = GameState.get_ship(ship_id)
		var total_ma = GameState.ship_controller.get_movement_allowance(ship_id) if ship_state else remaining_ma_val
		current_planning_ui.show_plotting_controls(ship_id, remaining_ma_val, total_ma)
		_update_tacking_display(is_tacking)

func _on_hex_selected(plotted_path: Array, valid_hexes: Variant, can_submit_val: bool, remaining_ma_val: int, is_tacking: bool = false) -> void:
	if hex_overlay and hex_map:
		var hex_grid = hex_map.get_hex_grid()
		var vnh = valid_hexes as MovementTypes.ValidNextHexes
		hex_overlay.show_valid_hexes(vnh.get_all_valid_moves(), hex_grid)
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
		_update_tacking_display(is_tacking)

func _on_undo_complete(plotted_path: Array, valid_hexes: Variant, can_submit_val: bool, remaining_ma_val: int, is_tacking: bool = false) -> void:
	if hex_overlay and hex_map:
		var hex_grid = hex_map.get_hex_grid()
		var vnh = valid_hexes as MovementTypes.ValidNextHexes
		hex_overlay.show_valid_hexes(vnh.get_all_valid_moves(), hex_grid)
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
		_update_tacking_display(is_tacking)

func _on_plotting_cancelled(ship_id: String) -> void:
	Trace.trace_log("GameController", "Plotting cancelled for ship %s" % ship_id)
	if hex_overlay:
		hex_overlay.clear_all()

	if current_planning_ui:
		current_planning_ui.hide_plotting_controls()

func _on_movement_submitted(ship_id: String, final_path: Array) -> void:
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

func _enter_post_combat_phase() -> void:
	Trace.trace_log("GameController", "Post-combat phase - waiting for player to end turn")
	if not skip_post_combat_delay:
		await get_tree().create_timer(2.0).timeout

	# Single-player shortcut: advance phase under server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		GameState.phase_controller.advance_phase()
	else:
		push_warning("Client phase advance not yet implemented - needs network layer")

func _end_turn() -> void:
	# Single-player shortcut: advance phase under server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		GameState.phase_controller.advance_phase()

func _sync_all_views() -> void:
	for ship_id in ship_views.keys():
		var ship_view = ship_views[ship_id]
		var ship_state = GameState.get_ship(ship_id)
		if ship_state and ship_view and hex_map:
			ship_view.sync_to_state(ship_state, hex_map.get_hex_grid())

func _toggle_developer_ui() -> void:
	if developer_ui:
		developer_ui.visible = not developer_ui.visible
		if developer_ui.visible:
			developer_ui.refresh_all()
			Trace.trace_log("GameController", "Developer UI opened (F12 to close)")
