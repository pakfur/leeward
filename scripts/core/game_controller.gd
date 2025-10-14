extends Node
## GameController - Main game logic controller (manages views, state is in GameState)

@onready var hex_map: Node3D = $HexMap
@onready var camera: Camera3D = $Camera
@onready var ships_container: Node3D = $Ships
@onready var ui: Control = $UI
@onready var planning_panel = $UI/PlanningPanel
@onready var ship_status_panel = $UI/ShipStatusPanel
@onready var developer_ui: Window = $DeveloperUI

# Views (presentation layer)
var ship_views: Dictionary = {}  # ship_id -> ShipView
var selected_ship_id: String = ""

func _ready() -> void:
	print("GameController ready")

	# Load data
	DataManager.load_movement_allowance_table()
	DataManager.load_ship_definitions()

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

	# Set hex_map reference for environment controller (for water shader updates)
	if GameState.environment_controller and hex_map:
		GameState.environment_controller.set_hex_map(hex_map)
		# Trigger initial shader update
		GameState.environment_controller.force_update()

	# Start the game
	GameState.start_new_game(scenario)

func _setup_scenario(scenario: Dictionary) -> void:
	"""Setup the game from scenario data"""
	print("Setting up scenario: %s" % scenario.get("name", "Unknown"))

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
	"""Create a ship (state + view) from scenario data"""
	var ship_type = ship_data.get("ship_type", "")
	var ship_def = DataManager.get_ship_definition(ship_type)

	if ship_def.is_empty():
		push_error("Ship definition not found: %s" % ship_type)
		return

	# Create ship state (data only)
	var ship_state = ShipState.new()
	ship_state.initialize_from_scenario(ship_data, ship_def)

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

	print("Spawned ship: %s for player %d" % [ship_state.ship_name, ship_state.player_id])

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

	# Handle ship selection via mouse click (only if not handled by UI)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_ship_selection(event.position)
		get_viewport().set_input_as_handled()

func _handle_ship_selection(screen_pos: Vector2) -> void:
	"""Raycast to select ship"""
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
	"""Find the ship view that owns this collider"""
	var node = collider
	while node:
		if node is ShipView:
			return node
		node = node.get_parent()
	return null

func _select_ship(ship_id: String) -> void:
	"""Select a ship and show its status"""
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
	"""Center camera on all ships with appropriate zoom"""
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
	"""Handle phase transitions"""
	print("Phase changed to: %s" % GameState.get_phase_name())

	match phase:
		GameState.GamePhase.PLANNING:
			_enter_planning_phase()
		GameState.GamePhase.MOVEMENT_RESOLUTION:
			_resolve_movement()
		GameState.GamePhase.POST_COMBAT:
			_enter_post_combat_phase()

func _enter_planning_phase() -> void:
	"""Enter planning phase - show planning UI for player ships"""
	print("Entering planning phase for player 0")

	var player_0_ships = GameState.get_player_ships(0)
	if planning_panel and not player_0_ships.is_empty():
		planning_panel.show_for_planning_with_states(player_0_ships)

	# TODO: AI plans for player 1

func _on_player_plan_submitted() -> void:
	"""Player has submitted their plan"""
	print("Player submitted plan")

	# Submit plan to server (via phase controller if server, or via network if client)
	if GameState.is_server and GameState.phase_controller:
		GameState.phase_controller.player_submit_plan(0)

		# TODO: Wait for AI or submit AI plan immediately
		GameState.phase_controller.player_submit_plan(1)
	else:
		# TODO: Send plan submission to server via network
		push_warning("Client plan submission not yet implemented - needs network layer")

func _resolve_movement() -> void:
	"""Resolve movement for all ships - SERVER ONLY"""
	if not GameState.is_server:
		# Clients wait for server to sync state
		print("[Client] Waiting for movement resolution from server")
		_sync_all_views()
		await get_tree().create_timer(1.0).timeout
		return

	print("[Server] Resolving movement...")

	# Use ship controller to resolve movement
	if GameState.ship_controller:
		GameState.ship_controller.resolve_all_movement()

	# Sync all views to state after resolution
	_sync_all_views()

	# For now, just advance phase
	await get_tree().create_timer(1.0).timeout

	# Advance to next phase
	if GameState.phase_controller:
		GameState.phase_controller.advance_phase()

func _enter_post_combat_phase() -> void:
	"""Enter post-combat phase - player can manually advance"""
	print("Post-combat phase - waiting for player to end turn")
	# TODO: Add UI button to end turn
	# For now, auto-advance after delay
	await get_tree().create_timer(2.0).timeout

	if GameState.is_server and GameState.phase_controller:
		GameState.phase_controller.advance_phase()
	else:
		# TODO: Send advance phase request to server
		push_warning("Client phase advance not yet implemented - needs network layer")

func _sync_all_views() -> void:
	"""Sync all ship views to their current state"""
	for ship_id in ship_views.keys():
		var ship_view = ship_views[ship_id]
		var ship_state = GameState.get_ship(ship_id)
		if ship_state and ship_view and hex_map:
			ship_view.sync_to_state(ship_state, hex_map.get_hex_grid())

func _toggle_developer_ui() -> void:
	"""Toggle the developer UI window with F12"""
	if developer_ui:
		developer_ui.visible = not developer_ui.visible
		if developer_ui.visible:
			developer_ui.refresh_all()
			print("Developer UI opened (F12 to close)")
