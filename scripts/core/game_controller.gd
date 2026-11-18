extends Node
## GameController - Main game logic controller (manages views, state is in GameState)

@onready var hex_map: Node3D = $HexMap
@onready var camera: Camera3D = $Camera
@onready var ships_container: Node3D = $Ships
@onready var ui: Control = $UI
@onready var context_panel = $UI/ContextPanel
@onready var developer_ui: Window = $DeveloperUI

# Planning phase UI
const PlanningPhaseUI = preload("res://scenes/ui/planning_phase_ui.tscn")
const FireDeclarationPanelScene = preload("res://scenes/ui/fire_declaration_panel.tscn")
const FirePanelScript = preload("res://scripts/ui/fire_declaration_panel.gd")
const CombatLogPanelScene = preload("res://scenes/ui/combat_log_panel.tscn")
const GameOverPanelScene = preload("res://scenes/ui/game_over_panel.tscn")
const OceanViewScript = preload("res://scripts/view/ocean_view.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const CrewOverlayScene = preload("res://scenes/ui/crew_overlay.tscn")
const ResolutionPanelScene = preload("res://scenes/ui/resolution_panel.tscn")
var current_planning_ui: Control = null
var fire_panel: Control = null  # FireDeclarationPanel while fire orders are being declared
var combat_panel: Control = null  # "Movement" / "Combat" context content while a phase plays back
## Movement playback has no skip: the panel must not offer one (combat playback does, in its log).
const MOVEMENT_PLAYBACK_SKIPPABLE := false
var combat_log_panel: CombatLogPanel = null
var end_turn_panel: Control = null  # context-panel content while waiting in POST_COMBAT
var end_turn_button: Button = null
var game_over_panel: GameOverPanel = null  # modal result card; non-null once the game has ended
var _boarding_card: BoardingCard = null  # the boarding rounds of the last combat, over the map (boarding spec §4.5)
var _boarding_card_log: PhaseEvents.PhaseLog = null  # the combat log the card shows
var _combat_playback_active: bool = false  # true from combat_log_ready until playback finishes
var pause_menu: Control = null  # PauseMenu: Escape / the corner Menu button
var menu_button: Button = null  # discreet corner button that opens the pause menu
var _leaving: bool = false  # Leave game confirmed: playback is abandoned, nothing advances the game
## The crew & damage overlay (crew-tasks spec §4): its client, the overlay over the map and the
## planning panel's crew block. View code; changes go through the server's crew requests.
var crew_client: CrewOverlayClient = null
var crew_overlay: CrewOverlay = null

# The resolution replay (resolution panel spec): the combat steps on combat_log_ready, the
# post-combat phases' steps before End Turn. View only; the map draws `display_states` meanwhile.
## The phases the post-combat replay shows.
const POST_COMBAT_PHASES: Array[int] = [TurnPhaseController.GamePhase.DRIFT_CALCULATION,
	TurnPhaseController.GamePhase.STATUS_ADJUSTMENT, TurnPhaseController.GamePhase.MORALE_CHECK,
	TurnPhaseController.GamePhase.MESSAGE_DELIVERY]
var display_states := DisplayStates.new()
var resolution_replay: ResolutionReplay = null  # made on first use (_replay())
var resolution_panel: ResolutionPanel = null  # context-panel content while a replay runs
var _replay_saved_view: Dictionary = {}  # the camera pose before the replay framed its first step
var _replay_raw_index: PackedInt32Array = PackedInt32Array()  # filtered event index -> turn_log index
var _replay_display_phase: int = -1  # the phase whose display copies the map shows
var _post_events_read: int = 0  # filtered events of the turn the post-combat replay has built steps from

const NO_SHOT_HEADLINE := "No broadside bears on an enemy this turn."

# Views (presentation layer)
var ship_views: Dictionary = {}  # ship_id -> ShipView
var selected_ship_id: String = ""
var ship_indicators: Node3D = null     # ShipIndicators
var indicator_overlay: Control = null  # IndicatorOverlay
var status_overlay: ShipStatusOverlay = null  # graphic status by a clicked or hovered enemy ship
var anchor_markers: AnchorMarkers = null  # anchors and cables of anchored ships (13), redrawn with the ships
var grapple_lines: GrappleLines = null  # the grapples between ships (8.C), redrawn with the ships
var tow_lines: TowLines = null  # the hawsers of the tows (12.A), redrawn with the ships
var _mouse_pos: Vector2 = Vector2(-1, -1)  # last mouse position seen (viewport coordinates)
const HUMAN_PLAYER_ID := 0

# Courses (PLANNING): every own ship's stored course is drawn and edited on the map at once.
var hex_overlay: Node3D = null  # HexOverlay instance
var _courses: Dictionary = {}  # ship_id -> CourseClicks entry {path_hexes, next_hexes, end_hex}
var _hover_candidates: Dictionary = {}  # ship_id -> {Vector2i click target -> MoveMetadata} (server-provided)
var _click_refusals: Dictionary = {}  # ship_id -> reason the server gave for the last click on its course
var _last_hover_hex: Vector2i = Vector2i(-99, -99)  # avoids re-routing when the hovered hex is unchanged

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

	# Load scenario from GameState (set by menu selection)
	var scenario_name = GameState.selected_scenario
	if scenario_name.is_empty():
		scenario_name = "test_basic"  # Fallback for direct testing

	var scenario = DataManager.load_scenario(scenario_name)
	_setup_scenario(scenario)

	# Connect signals
	GameState.phase_changed.connect(_on_phase_changed)

	# Connect resolution log signal for playback
	if GameState.phase_controller:
		GameState.phase_controller.resolution_log_ready.connect(_on_resolution_log_ready)
		GameState.phase_controller.fire_declaration_requested.connect(_on_fire_declaration_requested)
		GameState.phase_controller.combat_log_ready.connect(_on_combat_log_ready)
		GameState.phase_controller.game_over.connect(_on_game_over)
		GameState.phase_controller.bear_off_decision_requested.connect(_on_bear_off_decision_requested)
		GameState.phase_controller.maintenance_orders_requested.connect(_on_maintenance_orders_requested)
	# The ships are built by the server (GameState.start_scenario); their views follow on game_started.
	GameState.game_started.connect(_on_game_started)

	# The shared sea (shader clock, swell, zoom intensity, look presets) and OceanView, which feeds it
	if GameState.environment_controller and hex_map:
		var sea_model := SeaModel.new()
		sea_model.name = "SeaModel"
		sea_model.material = hex_map.ocean_material
		add_child(sea_model)
		var ocean_view = OceanViewScript.new(GameState, sea_model)
		ocean_view.connect_to_controller(GameState.environment_controller)
		add_child(ocean_view)
		# Not updated here: GameState.environment is still the previous game's until the game
		# starts. OceanView updates on game_started and on every environment change.
		GameState.game_started.connect(ocean_view.update_water_shader.unbind(1))

	_setup_combat_log_panel()

	# Initialize hex overlay
	_setup_hex_overlay()
	_setup_indicators()

	_setup_pause_menu()
	_setup_crew_overlay()

	# Setup debug hex coordinate label
	_setup_hex_coord_label()
	if developer_ui:
		developer_ui.hex_coords_toggled.connect(_on_hex_coords_toggled)
		developer_ui.hex_labels_toggled.connect(_on_hex_labels_toggled)
		developer_ui.ship_changed.connect(_on_dev_ship_changed)

	# Start the game. The human player's ships ask before bearing off (6.D.3) and for the
	# Maintenance Phase orders (8.C); the AI's decide for themselves.
	GameState.start_scenario(scenario, [HUMAN_PLAYER_ID] as Array[int])

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
	indicator_overlay.map_rect_provider = _map_safe_rect  # labels stay clear of the side panel

	status_overlay = ShipStatusOverlay.new()
	status_overlay.name = "ShipStatusOverlay"
	add_child(status_overlay)  # in the world: it lies on the water
	if hex_map:
		var grid: HexGrid = hex_map.get_hex_grid()
		var map_size := Vector2(hex_map.grid_width * grid.hex_size * HexGrid.SQRT3,
			hex_map.grid_height * grid.hex_size * 1.5)
		status_overlay.setup(camera, grid, Rect2(-map_size * 0.5, map_size))

## The corner Menu button and the pause menu (added last so it draws over every other panel).
func _setup_pause_menu() -> void:
	menu_button = Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "Menu"
	menu_button.tooltip_text = "Pause menu (Esc)"
	menu_button.theme_type_variation = &"SecondaryButton"
	menu_button.focus_mode = Control.FOCUS_NONE
	# Top right, just under the minimap: clear of the ship status panel (bottom right), the side
	# panel (left) and the log bar (bottom).
	menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	menu_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var minimap := get_node_or_null("UI/MiniMap") as Control
	if minimap:
		var minimap_bottom := minimap.position.y + minimap.size.y
		menu_button.offset_top = minimap_bottom + 8.0
		menu_button.offset_bottom = menu_button.offset_top
	menu_button.pressed.connect(_open_pause_menu)
	pause_menu = PauseMenuScript.new()
	pause_menu.leave_confirmed.connect(_leave_game)
	pause_menu.closed.connect(_set_paused.bind(false))
	if ui:
		ui.add_child(menu_button)
		ui.add_child(pause_menu)
	else:
		add_child(menu_button)
		add_child(pause_menu)


func _setup_crew_overlay() -> void:
	crew_client = CrewOverlayClient.new(GameState, HUMAN_PLAYER_ID)
	crew_overlay = CrewOverlayScene.instantiate()
	crew_overlay.name = "CrewOverlay"
	crew_overlay.z_index = 60  # over the map, the minimap and the log bar; the side panel stays clear
	if ui:
		ui.add_child(crew_overlay)
		if pause_menu:
			ui.move_child(crew_overlay, pause_menu.get_index())
	else:
		add_child(crew_overlay)
	crew_overlay.setup(crew_client)
	crew_client.changed.connect(_on_crew_changed)
	crew_client.open_changed.connect(func(_on): _on_crew_changed())
	_fit_crew_overlay()


## The overlay covers the map area only: right of the side panel (spec §4.1).
func _fit_crew_overlay() -> void:
	if not crew_overlay:
		return
	var left := 0.0
	if context_panel and context_panel.visible and context_panel.get("panel_container"):
		left = context_panel.panel_container.get_global_rect().end.x
	if absf(crew_overlay.offset_left - left) > 0.5:
		crew_overlay.offset_left = left


## A Developer UI command changed a ship (e.g. started a fire): redraw what shows it.
func _on_dev_ship_changed(ship_id: String) -> void:
	var ship_state: ShipState = GameState.get_ship(ship_id)
	if ship_state == null:
		return
	if current_planning_ui and is_instance_valid(current_planning_ui):
		current_planning_ui.update_ship_display(ship_state)
		current_planning_ui.refresh_crew_orders()
	if crew_client:
		crew_client.refresh()
	_sync_all_views()


func _on_crew_changed() -> void:
	if current_planning_ui and is_instance_valid(current_planning_ui):
		current_planning_ui.crew_overlay_open = crew_client.is_open
		current_planning_ui.refresh_crew_orders()
	_click_refusals.clear()  # the crew or sail change may have made a refused move legal
	_refresh_courses()  # a sail order can change the movement allowance


## C: open or close the crew overlay for the selected own ship (spec §4.1, §9 Q4).
func _toggle_crew_overlay() -> void:
	if not crew_client:
		return
	if crew_client.is_open:
		crew_client.close()
		return
	var ship_id := selected_ship_id
	if current_planning_ui and is_instance_valid(current_planning_ui) and current_planning_ui.selected_ship_id != "":
		ship_id = current_planning_ui.selected_ship_id
	if ship_id == "" and crew_client.ship_id != "":
		ship_id = crew_client.ship_id
	if ship_id == "":
		var own := GameState.ships_of_player(HUMAN_PLAYER_ID)
		if not own.is_empty():
			ship_id = own[0].ship_id
	_open_crew_overlay(ship_id)


func _open_crew_overlay(ship_id: String) -> void:
	var ship := GameState.get_ship(ship_id)
	if ship == null or not GameState.commands(HUMAN_PLAYER_ID, ship_id):
		return  # other players' plots are secret
	_clear_hover()
	crew_client.open_for(ship_id)


func _open_pause_menu() -> void:
	if game_over_panel or not pause_menu:
		return
	_clear_hover()
	pause_menu.open()
	_set_paused(true)


## The pause menu pauses the scene tree: ship animation tweens, movement playback waits, the
## paced combat reveal and every pausable node's _process/input hold until it closes. (The
## pause menu itself runs with PROCESS_MODE_ALWAYS.) View-level only: no game state changes.
func _set_paused(on: bool) -> void:
	if is_inside_tree():
		get_tree().paused = on


func _exit_tree() -> void:
	_set_paused(false)  # never leave the next scene paused


func is_pause_menu_open() -> bool:
	return pause_menu != null and pause_menu.is_open()


## Leave the game in progress for scenario selection, the way the game-over card does, on one
## confirmation in every state. Any running movement or combat playback is abandoned first: it
## must never tell the server it finished, so the game does not advance any further.
func _leave_game() -> void:
	if _leaving:
		return
	_leaving = true
	Trace.trace_log("GameController", "Leaving the game in progress")
	_cancel_resolution_replay()  # no step reaches the server any more
	if playback_controller:
		if playback_controller.playback_completed.is_connected(_on_playback_completed):
			playback_controller.playback_completed.disconnect(_on_playback_completed)
		playback_controller.abort()
		playback_controller.queue_free()
		playback_controller = null
	_set_paused(false)
	_on_back_to_scenarios()


## Escape opens and closes the pause menu; _input so a focused button cannot swallow it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position  # every motion, also over panels: the hover status follows it
		return
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		return
	if not pause_menu:
		return
	# Esc in the crew overlay drops a picked-up counter, then closes it (spec §4.1).
	if not pause_menu.is_open() and crew_overlay and crew_overlay.visible and game_over_panel == null:
		if crew_overlay.handle_escape():
			get_viewport().set_input_as_handled()
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
	_update_status_hover()
	_fit_crew_overlay()
	_follow_tow_lines()
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

## A new game (or a Developer UI reset): one ShipView per ship the server built, replacing any old ones.
func _on_game_started(_scenario: Dictionary) -> void:
	_cancel_resolution_replay()
	display_states.clear()
	_replay_saved_view = {}
	for id in ship_views.keys():
		var old_view: Node = ship_views[id]
		if is_instance_valid(old_view):
			if old_view.get_parent():
				old_view.get_parent().remove_child(old_view)  # free the name for the new view
			old_view.queue_free()
	ship_views.clear()
	for ship_state in GameState.ships_on_map():
		_spawn_ship_view(ship_state)
	# The board: the scenario's rectangle, its land, shallows and typed edges (map spec §15).
	var terrain := TerrainMap.of(GameState.active_scenario)
	if hex_map:
		hex_map.resize_to(terrain)
		if hex_overlay:
			hex_overlay.show_terrain(terrain, hex_map.get_hex_grid())


## The ids of the ships on the map that have no view yet (reinforcements that have just arrived),
## sorted.
static func views_to_spawn(view_ids: Array, ships: Array[ShipState]) -> Array[String]:
	var out: Array[String] = []
	for ship_state in ships:
		if ship_state.is_on_map() and not view_ids.has(ship_state.ship_id):
			out.append(ship_state.ship_id)
	out.sort()
	return out


## The ids of the ships the springs step moved before movement this g-t (a spring turn or a veer in
## that was not refused, 13.D.2, 13.E.2), sorted: their views are synced before playback starts, so
## they sail from the new hexes.
static func spring_step_ship_ids(turn_log: PhaseEvents.PhaseLog) -> Array[String]:
	var out: Array[String] = []
	if turn_log == null:
		return out
	for type in [PhaseEvents.Type.SPRING_TURN, PhaseEvents.Type.VEER_IN]:
		for ev in turn_log.of_type(type):
			if str(ev.data.get("refused", "")) == "" and not out.has(ev.ship_id):
				out.append(ev.ship_id)
	out.sort()
	return out


## The ships that get a planning-panel card: those on the map (no card for a reinforcement still
## waiting to arrive, or a ship gone off the map).
static func planning_ships(ships: Array[ShipState]) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for ship_state in ships:
		if ship_state.is_on_map():
			out.append(ship_state)
	return out


func _spawn_ship_view(ship_state: ShipState) -> void:
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

	Trace.trace_log("GameController", "Spawned ship: %s for player %d" % [ship_state.ship_name, ship_state.side])

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
		# The resolution panel takes Space / Enter as Next (its own key handling, which runs first);
		# while its dice tumble they must not reach End Turn or anything else.
		if _replay_running() and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and _end_turn_available():
			_on_end_turn_pressed()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			_toggle_crew_overlay()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_HOME:
			_center_camera_on_all_ships()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_F12:
			_toggle_developer_ui()
			get_viewport().set_input_as_handled()
			return

	# Handle mouse click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# A hex some own ship's course claims goes to that course, even over a ship (spec: course
		# wins over ships); anything else selects as usual.
		if _handle_course_click(_course_hex_at(event.position)):
			get_viewport().set_input_as_handled()
			return
		_handle_ship_selection(event.position)
		get_viewport().set_input_as_handled()

## The hex under `screen_pos` for course routing, or (-99, -99).
func _course_hex_at(screen_pos: Vector2) -> Vector2i:
	if not camera or not hex_overlay or not hex_map:
		return Vector2i(-99, -99)
	var world_pos = _water_point_at(screen_pos)
	if world_pos == null:
		return Vector2i(-99, -99)
	return hex_overlay.hex_at_world_pos(world_pos, hex_map.get_hex_grid())

## The ship whose course is drawn at full strength and wins overlapping clicks: the planning
## panel's selected card, else the map selection.
func _course_selected_id() -> String:
	if current_planning_ui and is_instance_valid(current_planning_ui) and current_planning_ui.selected_ship_id != "":
		return current_planning_ui.selected_ship_id
	return selected_ship_id

## A click on `hex` in PLANNING: when a course claims it (CourseClicks.route), extend or cut that
## ship's course through the server, select the ship and redraw. False when no course claims it.
func _handle_course_click(hex: Vector2i) -> bool:
	if GameState.current_phase != GameState.GamePhase.PLANNING or _courses.is_empty():
		return false
	if hex == Vector2i(-99, -99) or GameState.phase_controller == null:
		return false
	var route := CourseClicks.route(hex, _courses, _course_selected_id())
	if route.is_empty():
		return false
	var ship_id: String = route["ship_id"]
	var reason: String
	if route["kind"] == "extend":
		reason = GameState.phase_controller.player_extend_course(HUMAN_PLAYER_ID, ship_id, hex)
	else:
		reason = GameState.phase_controller.player_cut_course(HUMAN_PLAYER_ID, ship_id, int(route["step_index"]))
	if reason == "":
		_click_refusals.erase(ship_id)
	else:
		Trace.trace_log("GameController", "Course %s of %s at %s refused: %s" % [route["kind"], ship_id, hex, reason])
		_click_refusals[ship_id] = reason
	# The card shows the course readout (and any refusal) of the selected ship only.
	if current_planning_ui and is_instance_valid(current_planning_ui) and current_planning_ui.selected_ship_id != ship_id:
		current_planning_ui.select_ship(ship_id)
	_last_hover_hex = Vector2i(-99, -99)  # the hovered hex may now mean something else
	_refresh_courses()
	if crew_client:
		crew_client.refresh()  # a turn at MA 0 opens the braces
	if current_planning_ui and is_instance_valid(current_planning_ui):
		current_planning_ui.refresh_crew_summaries()
	return true

## Draw every own ship's stored course and the hexes it may extend to (the panel's selected ship at
## full strength), and rebuild the click routing, the hover candidates and each card's course readout.
func _refresh_courses() -> void:
	# Outside PLANNING the overlay is not ours to clear (a bear-off pause draws the other plots).
	if GameState.current_phase != GameState.GamePhase.PLANNING or GameState.phase_controller == null:
		return
	_courses.clear()
	_hover_candidates.clear()
	if hex_overlay:
		hex_overlay.clear_courses()
		hex_overlay.clear_blocked_hexes()
	var selected := _course_selected_id()
	var grid: HexGrid = hex_map.get_hex_grid() if hex_map else null
	var ships: Array = GameState.ships_on_map()
	for ship: ShipState in GameState.ships_of_player(HUMAN_PLAYER_ID):
		var id := ship.ship_id
		var options: Dictionary = GameState.phase_controller.course_options(id)  # read-only query
		if options.is_empty():
			# Cannot plot (fouled, grappled, struck, dismasted, a prize): no course, no stale readout.
			if current_planning_ui and is_instance_valid(current_planning_ui):
				current_planning_ui.set_course_info(id, {})
			continue
		var input := CourseView.course_input(options, ship)
		_courses[id] = input
		var vnh: MovementTypes.ValidNextHexes = options["valid_next"]
		_hover_candidates[id] = CourseView.hover_candidates(vnh)
		var marks: Array[Vector2i] = offered_collisions(vnh, ships, id)["marks"]
		if hex_overlay and grid:
			hex_overlay.show_course(id, input["path_hexes"], input["next_hexes"], marks, grid, id == selected)
			if id == selected:
				var path: Array = options["path"]
				var end_facing: int = path[-1].facing if not path.is_empty() else ship.facing
				hex_overlay.show_blocked_hexes(blocked_hexes_for(vnh, input["end_hex"], end_facing, grid), grid)
		if current_planning_ui and is_instance_valid(current_planning_ui):
			current_planning_ui.set_course_info(id, _course_info(ship, options, ships))

## The card's course readout for `ship`: MP used of the allowance (the server's count), the tacking
## and steering notes, the heading note (allowance change, irons) and the warning line (a refused
## click, else the path's collision, then a jammed rudder, then a course too short, 5.E.4).
func _course_info(ship: ShipState, options: Dictionary, ships: Array) -> Dictionary:
	var info := CourseView.course_info(options)
	var path: Array = options.get("path", [])
	if hex_map and GameState.environment:
		var grid: HexGrid = hex_map.get_hex_grid()
		var wind: int = GameState.environment.wind_direction
		var end_facing: int = path[-1].facing if not path.is_empty() else ship.facing
		info["note"] = CourseView.course_note(options, grid.get_wind_facing(ship.facing, wind),
			grid.get_wind_facing(end_facing, wind),
			IronsRules.excused(ship, GameState.environment, GameState.current_turn))
	info["tacking"] = _tacking_text(ship, bool(options.get("is_tacking_attempt", false)))
	info["steering"] = _steering_text(ship)
	var collision := path_collision_text(path, ship.hex_position, ship.facing, ships, ship.ship_id)
	info["collision"] = CourseView.warning_text(str(_click_refusals.get(ship.ship_id, "")), collision,
		str(options.get("rudder_error", "")), str(options.get("speed_error", "")))
	return info

## The tacking note for a course that turns at MA 0 ("" otherwise): the chance with the sections
## the crew plan puts at the braces and with a full crew (5.D.2a).
func _tacking_text(ship: ShipState, is_tacking: bool) -> String:
	if not is_tacking or ship.ship == null or GameState.crew_task_controller == null or GameState.movement_resolver == null:
		return ""
	# Read-only queries: the sections at the braces and the Tacking chart with this ship's DRMs.
	var sections: int = GameState.crew_task_controller.planned_tack_sections(ship.ship_id)
	var probability: float = GameState.movement_resolver.tacking_chance(ship, sections)
	var full: float = GameState.movement_resolver.tacking_chance(ship, TackCrewHandler.max_sections())
	return PlanningText.tacking_note(probability, sections, full, TackCrewHandler.max_sections())

## Steering damage (hull #2, #3; 6.F): the Poor Maneuvering chance for a turn, a turn left over from
## last g-t, or the direction a jammed rudder holds ("" for a ship with sound steering).
func _steering_text(ship: ShipState) -> String:
	if ship.ship == null or GameState.movement_resolver == null:
		return ""
	# Read-only query: the Poor Maneuvering chart, as the resolver will roll it  SCV:ALLOW
	var chance: float = GameState.movement_resolver.poor_maneuvering_chance(ship)
	return PlanningText.steering_note(ship.is_poor_maneuvering(), chance, ship.pending_turn,
		ship.rudder_jam_direction(), ship.rudder_destroyed)

## Where the camera ray through `screen_pos` meets the water plane (y = 0), or null.
func _water_point_at(screen_pos: Vector2) -> Variant:
	if not camera:
		return null
	var origin = camera.project_ray_origin(screen_pos)
	var direction = camera.project_ray_normal(screen_pos)
	if abs(direction.y) < 0.001:
		return null
	var t = -origin.y / direction.y
	if t < 0:
		return null
	return origin + direction * t

## The hex of water under `screen_pos`, or (-99, -99).
func _water_hex_at(screen_pos: Vector2) -> Vector2i:
	var world_pos = _water_point_at(screen_pos)
	if world_pos == null or not hex_map:
		return Vector2i(-99, -99)
	return hex_map.get_hex_grid().world_to_axial(world_pos)

## The ship lying on `hex` (its bow or its stern hex), or "" for open water. Pure: callers pass
## GameState.get_all_ships().
static func ship_at_hex(hex: Vector2i, ships: Array) -> String:
	var typed: Array[ShipState] = []
	typed.assign(ships)
	return str(Occupancy.build(typed).get(hex, ""))

## The speed and point-of-sail preview for the ship the hovered hex would extend (CourseClicks.route).
func _update_plotting_hover(screen_pos: Vector2) -> void:
	if _courses.is_empty() or GameState.current_phase != GameState.GamePhase.PLANNING:
		if _last_hover_hex != Vector2i(-99, -99):
			_clear_hover()
		return
	var hex := _course_hex_at(screen_pos)
	if hex == _last_hover_hex:
		return  # same hex — nothing to update
	_last_hover_hex = hex
	var route := CourseClicks.route(hex, _courses, _course_selected_id()) if hex != Vector2i(-99, -99) else {}
	var ship_id: String = route.get("ship_id", "")
	var cands: Dictionary = _hover_candidates.get(ship_id, {})
	var ship_state: ShipState = GameState.get_ship(ship_id)
	if route.get("kind", "") != "extend" or not cands.has(hex) or ship_state == null \
			or not hex_map or not GameState.environment:
		_hide_hover()
		return
	var env = GameState.environment
	var meta: MovementTypes.MoveMetadata = cands[hex]
	var model = ShipIndicatorModel.build_hover(
		meta.resulting_hex, meta.resulting_facing, ship_state.speed,
		env.wind_direction, env.wind_speed, hex_map.get_hex_grid())
	model.ship_name = ship_state.ship_name  # several courses are drawn at once: say whose this is
	if ship_indicators:
		ship_indicators.show_hover(model)
	if indicator_overlay:
		indicator_overlay.show_hover(model)

func _clear_hover() -> void:
	_last_hover_hex = Vector2i(-99, -99)
	_hide_hover()

## Hide the hover preview, keeping the last hovered hex.
func _hide_hover() -> void:
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

	# The model's click box, else the ship lying on the clicked hex (bow or stern)
	var ship_view: ShipView = null
	if not result.is_empty():
		ship_view = _find_ship_view_from_collider(result.collider)
	if not ship_view:
		ship_view = ship_views.get(ship_at_hex(_water_hex_at(screen_pos), GameState.get_all_ships()))
	if not ship_view:
		_deselect_ship()
		return
	var ship_state = GameState.get_ship(ship_view.state_id)
	if not ship_state:
		return

	if GameState.commands(HUMAN_PLAYER_ID, ship_state.ship_id):
		# Own ship: full selected-ship UI.
		# The camera does not move: the player clicked what they can already see.
		# While planning, the orders panel follows (one selected ship everywhere).
		if current_planning_ui and is_instance_valid(current_planning_ui) \
				and GameState.current_phase == GameState.GamePhase.PLANNING:
			current_planning_ui.select_ship(ship_view.state_id)
			return
		_select_ship(ship_view.state_id)
	else:
		# Enemy ship: its status stays up over it until something else is clicked; no indicators.
		_deselect_ship()
		_pin_status(ship_view.state_id)

## The ship under `screen_pos`, or null.
func _ship_view_at(screen_pos: Vector2) -> ShipView:
	if not camera or not hex_map:
		return null
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000.0
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = hex_map.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return _find_ship_view_from_collider(result.collider)

## Tell the status overlay which ship the mouse rests on (none while it is over a panel, the
## pause menu or the result card); the overlay applies the hover delay.
func _update_status_hover() -> void:
	if not status_overlay:
		return
	# No status on the water while broadside arcs are shown (it would cover those hexes), or while
	# ships are moving (it is placed from where they stand).
	status_overlay.set_suppressed(fire_panel != null
		or (crew_client != null and crew_client.is_open)
		or GameState.current_phase == GameState.GamePhase.MOVEMENT_RESOLUTION)
	# The plate carries speed and point of sail; the floating label stands in only while it is hidden.
	if indicator_overlay:
		indicator_overlay.set_selected_label_enabled(status_overlay.is_suppressed())
	var ship_view: ShipView = null
	# While planning the plate shows on click only (it would pop up over the course hexes).
	if not game_over_panel and not is_pause_menu_open() \
			and GameState.current_phase != GameState.GamePhase.PLANNING \
			and get_viewport().gui_get_hovered_control() == null:
		ship_view = _ship_view_at(_mouse_pos)
	var ship_state: ShipState = GameState.get_ship(ship_view.state_id) if ship_view else null
	if ship_state and shows_status_plate(ship_state):
		status_overlay.set_hover_target(ship_state.ship_id, ship_state)
	else:
		status_overlay.set_hover_target("", null)

## Only ships the player does not command (enemies, and AI teammates' ships) get the status plate
## on the water: the planning panel's card shows more about one of ours.
static func shows_status_plate(ship_state: ShipState) -> bool:
	return ship_state != null and ship_state.commanding_player() != HUMAN_PLAYER_ID

## Keep the graphic status up over a clicked enemy ship.
func _pin_status(ship_id: String) -> void:
	var ship_state = GameState.get_ship(ship_id)
	if status_overlay and ship_state:
		status_overlay.pin(ship_id, ship_state)

func _find_ship_view_from_collider(collider: Node) -> ShipView:
	var node = collider
	while node:
		if node is ShipView:
			return node
		node = node.get_parent()
	return null

func _select_ship(ship_id: String) -> void:
	# Clear any previous selection visuals
	if ship_indicators:
		ship_indicators.clear_selected()

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
	if indicator_overlay:
		indicator_overlay.show_selected(model, ship_id)

func _deselect_ship() -> void:
	selected_ship_id = ""
	if ship_indicators:
		ship_indicators.clear_selected()
	if indicator_overlay:
		indicator_overlay.clear_selected()
	if status_overlay:
		status_overlay.unpin()

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
	# The state before this phase, for the replay's display copies (combat's second emission, at
	# DECLARE, is ignored by DisplayStates).
	if GameState.phase_controller:
		display_states.record_phase(phase, GameState.phase_controller.current_turn, GameState.get_all_ships())
	if _replay_running() and replay_outlived(resolution_replay.kind, resolution_replay.phases, phase):
		_cancel_resolution_replay()
		_end_resolution_display()
	# Selection is a planning-time affordance — clear it (and any hover) on every phase change
	# so the one-shot indicator snapshot can't go stale across resolution/turn boundaries.
	_deselect_ship()
	if phase != GameState.GamePhase.PLANNING:
		_courses.clear()
		_hover_candidates.clear()
		if hex_overlay:
			hex_overlay.clear_courses()
			hex_overlay.clear_blocked_hexes()
	_clear_hover()
	_close_fire_panel()
	if phase != GameState.GamePhase.POST_COMBAT:
		_clear_end_turn_ui()
	if phase == GameState.GamePhase.PLANNING:
		_clear_boarding_card()
		_sync_all_views()  # a recapture at the start of the g-t (10.H.4) changes colours and flags
	if crew_client:
		if phase != GameState.GamePhase.PLANNING and crew_client.is_open:
			crew_client.close()  # the map plays the turn; C reopens the overlay read-only
		else:
			crew_client.refresh()
	Trace.trace_log("GameController", "Phase changed to: %s" % GameState.get_phase_name())

	match phase:
		GameState.GamePhase.PLANNING:
			_enter_planning_phase()
		GameState.GamePhase.MOVEMENT_RESOLUTION:
			_show_movement_panel()
			_resolve_movement()
		GameState.GamePhase.POST_COMBAT:
			_enter_post_combat_phase()  # syncs the views, after the replay's display copies are up

func _enter_planning_phase() -> void:
	Trace.trace_log("GameController", "Entering planning phase for player 0")

	# Clear any leftover overlays from previous turn
	if hex_overlay:
		hex_overlay.clear_everything()
	_click_refusals.clear()
	combat_panel = null  # freed below when the planning UI takes the context panel
	if combat_log_panel:
		combat_log_panel.auto_expand(false)  # the map is what matters while plotting

	# Get player ships
	var player_0_ships := planning_ships(GameState.ships_of_player(HUMAN_PLAYER_ID))
	if player_0_ships.is_empty():
		Trace.trace_log("GameController", "No ships for player %d" % HUMAN_PLAYER_ID)
		return

	# Create planning UI
	if not current_planning_ui:
		current_planning_ui = PlanningPhaseUI.instantiate()

		# Connect signals
		current_planning_ui.ship_selected.connect(_on_planning_ship_selected)
		current_planning_ui.end_planning_pressed.connect(_on_end_planning_pressed)
		current_planning_ui.crew_overlay_requested.connect(_open_crew_overlay)
		current_planning_ui.reset_planning_confirmed.connect(_on_reset_planning_confirmed)
		current_planning_ui.reset_course_requested.connect(_on_reset_course_requested)

	# Load into context panel (must be done before setup to ensure @onready nodes are available)
	if context_panel:
		context_panel.set_context_title("Planning Phase")
		context_panel.set_context_content(current_planning_ui)

	# Setup with player ships (after adding to tree so @onready nodes are initialized)
	current_planning_ui.setup_for_player(player_0_ships)
	if crew_client:
		crew_client.follow_ship(current_planning_ui.selected_ship_id)
	# Every own ship's default course (stored before the server announced PLANNING) is on the map at once.
	_refresh_courses()

func _on_planning_ship_selected(ship_id: String) -> void:
	Trace.trace_log("GameController", "Planning UI: Ship selected - %s" % ship_id)

	# Get ship state and view
	var ship_state = GameState.get_ship(ship_id)
	var ship_view = ship_views.get(ship_id)

	if not ship_state or not ship_view:
		Trace.trace_log("GameController", "Warning: Ship not found: %s" % ship_id)
		return

	# Bring the ship into view only if it is off-screen or near the edge: a smooth pan,
	# never a rotation or zoom change (north stays up unless the player turns the camera).
	if camera and camera.has_method("pan_to_if_needed"):
		camera.pan_to_if_needed(ship_view.global_position)

	# Select ship on map (highlight)
	_select_ship(ship_id)
	if crew_client:
		crew_client.follow_ship(ship_id)
	_refresh_courses()  # the selected ship's course is drawn at full strength

## Cancel, confirmed: every order of the turn back to the planning start, then redraw it all.
func _on_reset_planning_confirmed() -> void:
	if not GameState.phase_controller:
		return
	var reason: String = GameState.phase_controller.player_reset_planning(HUMAN_PLAYER_ID)
	if reason != "":
		Trace.trace_log("GameController", "Planning reset refused: %s" % reason)
	_click_refusals.clear()
	_refresh_courses()
	if current_planning_ui and is_instance_valid(current_planning_ui):
		current_planning_ui.refresh_crew_summaries()
	if crew_client:
		crew_client.refresh()

## A card's Reset course: that ship back to its planning start course.
func _on_reset_course_requested(ship_id: String) -> void:
	if not GameState.phase_controller:
		return
	var reason: String = GameState.phase_controller.player_reset_course(HUMAN_PLAYER_ID, ship_id)
	if reason != "":
		Trace.trace_log("GameController", "Course reset of %s refused: %s" % [ship_id, reason])
	_click_refusals.erase(ship_id)
	_refresh_courses()
	if crew_client:
		crew_client.refresh()  # an MA-0 turn may no longer need the braces

func _on_end_planning_pressed() -> void:
	Trace.trace_log("GameController", "End Planning pressed")

	# The AI's plan is in already (TurnPhaseController.ai_player_ids); only the human's is sent.
	if GameState.is_server and GameState.phase_controller:
		if not GameState.phase_controller.player_submit_plan(HUMAN_PLAYER_ID):
			# Refused (a course short of its deceleration limit, 5.E.4): show the first such ship,
			# whose card names what it must use.
			var errors: Dictionary = GameState.phase_controller.plan_errors(HUMAN_PLAYER_ID)
			if not errors.is_empty():
				var first: String = errors.keys()[0]
				Trace.trace_log("GameController", "End Planning refused", {"ship_id": first,
					"reason": errors[first]})
				if current_planning_ui and is_instance_valid(current_planning_ui):
					current_planning_ui.select_ship(first)  # as a card click: expands its card
	else:
		push_warning("Client plan submission not yet implemented — needs network layer")

# ============================================================================
# Course collision warnings (pure)
# ============================================================================

## The one hex an offered move enters: an ahead move its new bow hex (the click target), a turn
## the hex its stern swings into.
static func move_entered_hex(vm: MovementTypes.ValidMove) -> Vector2i:
	if vm.move == MovementTypes.MoveType.FORWARD:
		return vm.hex
	return HexGrid.stern_of(vm.metadata.resulting_hex, vm.metadata.resulting_facing)

## Offered moves that enter a hex of another ship (bow or stern):
## {"warnings": {click target: hover text}, "marks": Array[Vector2i]}. An ahead move enters its
## click target ("Collision risk: X is here"; one mark). A turn enters the hex its stern swings
## into ("Stern would swing into X"); both its click target and that hex are marked.
static func offered_collisions(vnh: MovementTypes.ValidNextHexes, ships: Array, active_id: String) -> Dictionary:
	var warnings := {}
	var marks: Array[Vector2i] = []
	if vnh != null:
		var moves: Array = vnh.get_all_valid_moves()
		var entered: Array = []
		for vm in moves:
			entered.append(move_entered_hex(vm))
		var names := PlanningText.occupied_hexes(entered, ships, active_id)
		for i in range(moves.size()):
			if not names.has(entered[i]):
				continue
			var click: Vector2i = moves[i].hex
			var swing: bool = entered[i] != click
			warnings[click] = PlanningText.swing_collision_text(names[entered[i]]) if swing \
				else PlanningText.collision_text(names[entered[i]])
			for h in ([click, entered[i]] if swing else [click]):
				if not marks.has(h):
					marks.append(h)
	return {"warnings": warnings, "marks": marks}

## Warning for the plotted path: the first step that enters another ship's hex, worded as for the
## offered moves ("" when the path is clear).
static func path_collision_text(plotted_path: Array, start_bow: Vector2i, start_facing: int, ships: Array, active_id: String) -> String:
	var entered := path_entered_hexes(plotted_path, start_bow, start_facing)
	var names := PlanningText.occupied_hexes(entered, ships, active_id)
	for i in range(entered.size()):
		if names.has(entered[i]):
			if entered[i] != plotted_path[i].hex:  # a turn: the stern swung into it
				return PlanningText.swing_collision_text(names[entered[i]])
			return PlanningText.collision_text(names[entered[i]])
	return ""

## The hex each plotted step enters, from the ship's bow and facing before the plot: an ahead
## step its new bow hex, a turn (same bow hex, new facing) its swung stern hex.
static func path_entered_hexes(plotted_path: Array, start_bow: Vector2i, start_facing: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var bow := start_bow
	var facing := start_facing
	for step in plotted_path:
		if step.hex == bow and step.facing != facing:
			result.append(HexGrid.stern_of(step.hex, step.facing))
		else:
			result.append(step.hex)
		bow = step.hex
		facing = step.facing
	return result

## Hexes to mark as blocked around the plotting ship: the forward / port / starboard neighbours the
## server refuses. When the server offers no move at all (head to wind ended the move, in irons, or
## nothing left), the plot is over and nothing is drawn around the ship.
static func blocked_hexes_for(valid_hexes: MovementTypes.ValidNextHexes,
	current_hex: Vector2i,
	current_facing: int,
	hex_grid: HexGrid) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	if valid_hexes == null or not valid_hexes.has_any_moves():
		return blocked
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

	# The springs step (spring turns, veering in) moved some ships before movement: on the first log
	# only, their views take the new hexes so playback starts from them. Not every view: on a
	# bear-off re-run the movement results are not applied yet.
	if log.resume_impulse == 0 and hex_map:
		for ship_id in spring_step_ship_ids(GameState.turn_log):
			var view = ship_views.get(ship_id)
			var ship_state: ShipState = GameState.get_ship(ship_id)
			if view and ship_state:
				view.sync_to_state(ship_state, hex_map.get_hex_grid())

	# Create playback controller
	if playback_controller and playback_controller.is_inside_tree():
		playback_controller.queue_free()

	var hex_grid_ref: HexGrid = hex_map.get_hex_grid() if hex_map else HexGrid.new()
	playback_controller = MovementResolutionPlaybackController.new(hex_grid_ref, ship_views, 0)
	playback_controller.name = "PlaybackController"
	add_child(playback_controller)

	playback_controller.playback_completed.connect(_on_playback_completed, CONNECT_ONE_SHOT)
	playback_controller.playback_paused.connect(_on_playback_paused, CONNECT_ONE_SHOT)
	playback_controller.play(log)


## Playback reached a potential collision of one of the player's ships: the server asks for the
## decision (bear_off_decision_requested).
func _on_playback_paused() -> void:
	if _leaving:
		return
	# Intentional view→controller callback, like playback completion  SCV:ALLOW
	if GameState.phase_controller:
		GameState.phase_controller.on_playback_paused()


## 6.D.3: the decision is a step of its own short replay (kind "bear_off") in the resolution panel:
## the two ships and the odds above, the choices as its answer section, the camera on the ship, and
## the rest of every other ship's plotted move (situation.other_plots, chosen by the server) on the
## map. Movement playback owns the ship views meanwhile (no display copies, no sync). Without the side
## panel the old floating panel is used.
func _on_bear_off_decision_requested(player_id: int, situation: MovementTypes.BearOffSituation) -> void:
	if player_id != HUMAN_PLAYER_ID or _leaving:
		return  # another player's decision
	var ship: ShipState = GameState.get_ship(situation.ship_id)
	var blocker: ShipState = GameState.get_ship(situation.blocker_id)
	var panel := BearOffPanel.new()
	var prompt: ResolutionStep = null
	if context_panel:
		prompt = ResolutionSteps.bear_off_prompt(situation, CombatLogPanel.log_ships(GameState.get_all_ships()))
	panel.setup(situation, ship.ship_name if ship else situation.ship_id,
		blocker.ship_name if blocker else situation.blocker_id, prompt != null)
	panel.choice_made.connect(_on_bear_off_chosen.bind(panel, prompt))
	if prompt != null:
		if _replay_running():
			_cancel_resolution_replay()  # an earlier decision's step the server has moved past
		var movement: Array[int] = [TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION]
		_start_resolution_replay("bear_off", movement)
		resolution_replay.push_prompt(prompt, panel)
		resolution_replay.finish_when_drained(_on_bear_off_replay_drained)
	else:
		add_child(panel)
	current_planning_ui = null
	if hex_overlay and hex_map:
		var none: Array[Vector2i] = []
		for other_id in situation.other_plots:
			var hexes: Array[Vector2i] = []
			hexes.assign(situation.other_plots[other_id])
			hex_overlay.show_course(other_id, hexes, none, none, hex_map.get_hex_grid(), false)


## A refusal stays on the step with its reason; an accepted choice (the server has re-run the
## resolution and playback resumes) ends the bear-off replay.
func _on_bear_off_chosen(ship_id: String, choice: String, panel: BearOffPanel, prompt: ResolutionStep) -> void:
	var reason := "bear-off decisions can only be submitted on the server"
	# Single-player: submit player 0's decision under the server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		reason = GameState.phase_controller.player_submit_bear_off(HUMAN_PLAYER_ID, ship_id, choice)
	else:
		push_warning("Client bear-off submission not yet implemented - needs network layer")
	if reason != "":
		if is_instance_valid(panel):
			panel.show_error(reason)
		return
	_prompt_answered(prompt)


## The bear-off step was answered: the camera goes back and the side panel shows movement again.
## The ship views are movement playback's: nothing is synced here.
func _on_bear_off_replay_drained() -> void:
	if camera and not _replay_saved_view.is_empty() and camera.has_method("restore_view"):
		camera.restore_view(_replay_saved_view)
	_replay_saved_view = {}
	if GameState.phase_controller \
			and GameState.phase_controller.current_phase == TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION:
		_show_movement_panel()


## Maintenance Phase (8.C, 10.G.6): the server asks for the player's grapple, ungrapple or prize-crew
## orders. The request is a prompt step of the post-combat replay, started here when it is not
## running, before any sync: the steps already resolved this turn after combat (drift, tow attempts)
## come first, each ship drawn as she was, and a ship lost in drift keeps her view until her drift
## step. A second request in the phase is another prompt step in the same replay. Tests and AI-only
## runs (skip_post_combat_delay), and a scene without the side panel, use the old panel.
func _on_maintenance_orders_requested(player_id: int, step: String, options: Array) -> void:
	if player_id != HUMAN_PLAYER_ID or _leaving:
		return
	var names := {}
	for ship: ShipState in GameState.get_all_ships():
		names[ship.ship_id] = ship.ship_name
	var panel := MaintenanceOrdersPanel.new()
	if skip_post_combat_delay or context_panel == null:
		_sync_all_views()  # drift has moved ships since the last sync
		panel.setup(step, options, names)
		panel.orders_submitted.connect(_on_maintenance_orders_submitted.bind(panel, null))
		if context_panel:
			context_panel.set_context_title(MaintenanceOrdersPanel.title(step))
			context_panel.set_context_content(panel)
		else:
			add_child(panel)
		current_planning_ui = null
		if combat_log_panel:
			combat_log_panel.auto_expand(false)  # keep the ships alongside visible
		return
	panel.setup(step, options, names, true)
	var prompt := ResolutionSteps.maintenance_prompt(step, options,
		CombatLogPanel.log_ships(GameState.get_all_ships()))
	panel.orders_submitted.connect(_on_maintenance_orders_submitted.bind(panel, prompt))
	_feed_post_combat_replay(true)  # starts the replay (and syncs from its copies) when not running
	resolution_replay.push_prompt(prompt, panel)


## A refusal stays on the step with its reason. Accepted, the server rolls the step and goes on
## (perhaps to the next prompt, or on to POST_COMBAT, feeding the replay as it goes); the replay
## then moves past the prompt.
func _on_maintenance_orders_submitted(step: String, pairs: Variant, panel: MaintenanceOrdersPanel,
		prompt: ResolutionStep) -> void:
	var reason := "maintenance orders can only be submitted on the server"
	# Single-player: submit player 0's orders under the server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		reason = GameState.phase_controller.player_submit_maintenance_orders(HUMAN_PLAYER_ID, {step: pairs})
	else:
		push_warning("Client maintenance orders not yet implemented - needs network layer")
	if reason != "":
		if is_instance_valid(panel):
			panel.show_error(reason)
		return
	if prompt == null:
		_sync_all_views()  # the old panel: new grapples drawn at once
		return
	_prompt_answered(prompt)


## Moves the replay past `prompt` when it is the step on screen (an answer that came after the
## replay moved on, or was dropped, does nothing).
func _prompt_answered(prompt: ResolutionStep) -> void:
	if prompt != null and _replay_running() and resolution_replay.current_step() == prompt:
		resolution_replay.prompt_answered()


func _on_playback_completed() -> void:
	if _leaving:
		return
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
	var player_ships := GameState.ships_of_player(HUMAN_PLAYER_ID)
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
	_show_phase_panel("Combat", "CombatPanel", lines, "The combat log below shows each shot.")


## Lines for the "Movement" panel shown while ships animate; a skip is offered only if one exists.
static func movement_panel_lines(skippable: bool) -> Array[String]:
	var lines: Array[String] = ["Ships are moving…"]
	if skippable:
		lines.append("Space or click the log to skip")
	return lines


## Context-panel content titled "Movement" while movement plays back: no planning controls.
func _show_movement_panel() -> void:
	_show_phase_panel("Movement", "MovementPanel", movement_panel_lines(MOVEMENT_PLAYBACK_SKIPPABLE), "")


## Replace the context panel's content with read-only lines (plus an optional secondary hint).
## The planning UI it held is freed with it, so the next planning phase builds a fresh one.
func _show_phase_panel(title: String, node_name: String, lines: Array[String], hint_text: String) -> void:
	var box := VBoxContainer.new()
	box.name = node_name
	box.add_theme_constant_override("separation", 8)
	for i in range(lines.size()):
		var label := Label.new()
		label.text = lines[i]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(label)
	if hint_text != "":
		var hint := Label.new()
		hint.text = hint_text
		hint.theme_type_variation = &"SecondaryLabel"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(hint)
	if context_panel:
		context_panel.set_context_title(title)
		context_panel.set_context_content(box)
	else:
		add_child(box)
	current_planning_ui = null
	combat_panel = box


func _on_fire_pressed(orders: Array) -> void:
	var panel := fire_panel
	var marine_orders: Array = []
	if panel:
		panel.fire_button.disabled = true  # no double submit while the server decides
		marine_orders = panel.get_marine_orders()
	var reason := _submit_fire_orders(orders, marine_orders)
	if reason != "":
		# Rejected: the panel stays open (re-enabled) with the reason.
		if is_instance_valid(panel) and panel == fire_panel:
			panel.show_error(reason)
		return
	# Accepted: the declare step is over, so the panel must not stay interactive.
	_close_fire_panel()
	_show_orders_while_declaring(orders, marine_orders.size())


## "Your orders: ..." in the side panel while the other players still declare. When the submit
## completed the declarations, combat has already resolved inside it and the resolution replay (or a
## later phase) holds the side panel: it is not replaced.
func _show_orders_while_declaring(orders: Array, marine_count: int) -> void:
	var pc := GameState.phase_controller
	if pc == null or pc.current_phase != TurnPhaseController.GamePhase.COMBAT_RESOLUTION \
			or pc.combat_step != TurnPhaseController.CombatStep.DECLARE:
		return
	var lines: Array[String] = [orders_summary_line(orders, marine_count)]
	_show_combat_panel(lines)


## "Your orders: Fire 2 half broadsides." for the accepted order dictionaries (a split side is two
## half broadsides, not two broadsides).
static func orders_summary_line(orders: Array, marine_count: int = 0) -> String:
	return "Your orders: %s." % FirePanelScript.fire_button_text_with_marines(orders, marine_count)


## Remove the fire panel (if any) and its arcs. Safe to call on any path out of the declare step.
func _close_fire_panel() -> void:
	if hex_overlay:
		hex_overlay.clear_arcs()
	if fire_panel and is_instance_valid(fire_panel):
		fire_panel.queue_free()
	fire_panel = null


## Returns "" when the server accepted the orders, otherwise its rejection reason.
func _submit_fire_orders(orders: Array, marine_orders: Array = []) -> String:
	# Single-player: submit player 0's orders under the server guard  SCV:ALLOW
	if GameState.is_server and GameState.phase_controller:
		return GameState.phase_controller.player_submit_fire_orders(HUMAN_PLAYER_ID, orders, marine_orders)
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
	for side in FirePanelScript.ALL_SIDES:
		# The chosen batteries' arc is highlighted (rim); the rest of the broadside's arc is faint.
		# A chaser's arc (sides 2 and 3) is drawn from its own end, rimmed while it fires.
		var whole := broadside_arc(geometry, ship_state, side)
		var batteries: Array[String] = fire_panel.get_batteries(ship_id, side)
		if batteries.is_empty():
			# A chaser holding fire keeps its arc on the map, faint (fill only); a broadside as before.
			hex_overlay.show_arc(whole, side, not GunneryTypes.is_chase_side(side))
			continue
		var chosen := battery_arc(geometry, ship_state, side, batteries)
		var rest: Array[Vector2i] = []
		for h in whole:
			if not chosen.has(h):
				rest.append(h)
		hex_overlay.show_arc(chosen, side)
		hex_overlay.show_arc(rest, side, false)
	var target_hexes := fire_target_hexes(fire_panel.get_target_ids(ship_id))
	hex_overlay.show_target_highlights(target_hexes)
	_frame_fire_view(ship_state, target_hexes)


## The hexes to outline for the chosen fire targets: both the bow and the stern hex of each.
static func fire_target_hexes(target_ids: Array) -> Array[Vector2i]:
	var hexes: Array[Vector2i] = []
	for target_id in target_ids:
		var target := GameState.get_ship(target_id)
		if target:
			hexes.append_array(target.occupied_hexes())
	return hexes


## Union of the bow and stern battery arcs on one side, without the ship's own hexes.
static func broadside_arc(geometry: FireGeometry, ship_state: ShipState, side: int) -> Array[Vector2i]:
	return battery_arc(geometry, ship_state, side,
		[GunneryTypes.BATTERY_BOW, GunneryTypes.BATTERY_STERN] as Array[String])


## The arc of the given batteries ("bow" fires from the bow hex, "stern" from the stern hex;
## both = the full broadside) on one side, without the ship's own hexes. A chase side
## (GunneryTypes.CHASE_BOW / CHASE_STERN) is drawn from its own end, the bow or the stern hex,
## whatever `batteries` holds.
static func battery_arc(geometry: FireGeometry, ship_state: ShipState, side: int,
		batteries: Array[String]) -> Array[Vector2i]:
	var own := ship_state.occupied_hexes()
	var result: Array[Vector2i] = []
	var hexes: Array[Vector2i] = []
	if GunneryTypes.is_chase_side(side):
		hexes.append(own[1] if side == GunneryTypes.CHASE_STERN else own[0])
	else:
		for battery in batteries:
			hexes.append(own[0] if battery == GunneryTypes.BATTERY_BOW else own[1])
	for battery_hex in hexes:
		for h in geometry.broadside_hexes(battery_hex, ship_state.facing, side, FireGeometry.MAX_RANGE):
			if not result.has(h) and not own.has(h):
				result.append(h)
	return result


## Pan (zooming out only if both cannot fit) so the firing ship and its chosen targets are on
## screen, clear of the side panels. Never rotates the camera.
func _frame_fire_view(ship_state: ShipState, target_hexes: Array[Vector2i]) -> void:
	if not camera or not camera.has_method("frame_points_if_needed") or not hex_map:
		return
	var grid: HexGrid = hex_map.get_hex_grid()
	var points: Array[Vector3] = []
	for hex in ship_state.occupied_hexes() + target_hexes:
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
	_play_combat_log(log)


## The combat steps, one at a time in the resolution panel; when the player is through them (or
## at once when there are none) the phase controller is told playback is finished. Tests and
## AI-only runs (skip_post_combat_delay), and a scene without the side panel, skip the replay.
func _play_combat_log(combat_log: PhaseEvents.PhaseLog) -> void:
	if skip_post_combat_delay or context_panel == null:
		for ev in combat_log.events:
			if ev.type == PhaseEvents.Type.BOARDING_ROUND:
				_show_boarding_card(combat_log, ev)
		_sync_all_views()
		_finish_combat_playback()
		return
	var combat: Array[int] = [TurnPhaseController.GamePhase.COMBAT_RESOLUTION]
	var steps := _replay_steps(0, combat)
	if steps.is_empty():
		_sync_all_views()
		_finish_combat_playback()  # nothing to show: the panel never opens
		return
	_start_resolution_replay("combat", combat)
	resolution_replay.append(steps)
	resolution_replay.finish_when_drained(_on_combat_replay_drained)


func _on_combat_replay_drained() -> void:
	_finish_combat_playback()  # the server runs on to POST_COMBAT, which may start the next replay
	if not _replay_running():
		_end_resolution_display()


## The boarding card for a BOARDING_ROUND event (boarding spec §4.5): shown over the map until the
## player closes it or the next turn's planning begins.
## Several rounds in one combat log (several actions, 10.F) are stacked on the same card.
func _show_boarding_card(combat_log: PhaseEvents.PhaseLog, ev: PhaseEvents.PhaseEvent) -> void:
	var names := {}
	for s in GameState.get_all_ships():
		names[s.ship_id] = s.ship_name
	var result := BoardingCard.result_for(combat_log, ev)
	if _boarding_card != null and is_instance_valid(_boarding_card) and _boarding_card_log == combat_log:
		_boarding_card.add_round(ev.ship_id, ev.target_id, ev.data, result, names)
	else:
		_clear_boarding_card()
		var card := BoardingCard.new()
		card.setup(ev.ship_id, ev.target_id, ev.data, result, names)
		if ui:
			ui.add_child(card)
		else:
			add_child(card)
		_boarding_card = card
		_boarding_card_log = combat_log
	_boarding_card.reset_size()
	var area := get_viewport().get_visible_rect()
	_boarding_card.position = Vector2(area.size.x * 0.5 - _boarding_card.size.x * 0.5, 70.0)


func _clear_boarding_card() -> void:
	if _boarding_card != null and is_instance_valid(_boarding_card):
		_boarding_card.queue_free()
	_boarding_card = null
	_boarding_card_log = null


## A click on the combat log (or its old skip) is Resolve all.
func _skip_combat_playback() -> void:
	if _replay_running():
		resolution_replay.resolve_all()


func _finish_combat_playback() -> void:
	if _leaving:
		_combat_playback_active = false
		return
	if not _combat_playback_active:
		return
	_combat_playback_active = false
	var phase_controller = GameState.phase_controller
	if phase_controller == null:
		return
	# The phase may have moved on (or the game ended) while the steps were shown.
	if phase_controller.current_phase != TurnPhaseController.GamePhase.COMBAT_RESOLUTION \
			or phase_controller.combat_step != TurnPhaseController.CombatStep.RESOLVE:
		return
	# Intentional view->controller callback so the turn keeps cycling  SCV:ALLOW
	phase_controller.on_combat_playback_completed()

## POST_COMBAT: the steps of drift, status adjustment, morale and messages are replayed first; the
## End Turn button comes up when the player is through them (at once when there are none).
## Drift and the other late phases move ships without their own playback, so the views are synced
## here: once the replay has started (its display copies show each ship as she was before drift, so a
## ship lost off the map in drift keeps her view until her drift step), or at once with no replay.
func _enter_post_combat_phase() -> void:
	if skip_post_combat_delay:
		_sync_all_views()
		_request_end_turn()
		return
	Trace.trace_log("GameController", "Post-combat phase - waiting for player to end turn")
	if context_panel != null:
		_feed_post_combat_replay()  # a replay that starts syncs the views from its display copies
		if _replay_running():
			resolution_replay.finish_when_drained(_on_post_combat_replay_drained)
			return
	_sync_all_views()
	_show_post_combat_end_turn()


## Puts the post-combat steps logged since the last call into the replay, starting the replay when
## it is not running and there is something to show (or `open_empty`: a prompt is about to be
## pushed). Steps of other phases are left out.
func _feed_post_combat_replay(open_empty: bool = false) -> void:
	var running := _replay_running() and resolution_replay.kind == "post_combat"
	var steps := _replay_steps(_post_events_read if running else 0, POST_COMBAT_PHASES)
	if not running:
		if steps.is_empty() and not open_empty:
			return
		_start_resolution_replay("post_combat", POST_COMBAT_PHASES)
	resolution_replay.append(steps)


func _on_post_combat_replay_drained() -> void:
	_end_resolution_display()
	if GameState.phase_controller \
			and GameState.phase_controller.current_phase == TurnPhaseController.GamePhase.POST_COMBAT:
		_show_post_combat_end_turn()


func _show_post_combat_end_turn() -> void:
	if combat_log_panel:
		combat_log_panel.auto_expand(true)  # let the player review the turn
	_show_end_turn_ui()


# --- The resolution replay ------------------------------------------------------------------

func _replay() -> ResolutionReplay:
	if resolution_replay == null:
		resolution_replay = ResolutionReplay.new()
		resolution_replay.name = "ResolutionReplay"
		add_child(resolution_replay)
		resolution_replay.step_shown.connect(_on_replay_step_shown)
	return resolution_replay


## Drops the replay with no further server calls. A combat replay dropped this way never reaches
## `_finish_combat_playback`, so its playback flag is cleared here: the next combat_log_ready must play.
func _cancel_resolution_replay() -> void:
	_combat_playback_active = false
	if resolution_replay:
		resolution_replay.cancel()


func _replay_running() -> bool:
	return resolution_replay != null and resolution_replay.is_running()


## The steps of this turn's events the local player may see, from filtered index `from_index`, in
## `phases` only. Also refreshes the filtered -> raw index map the log's reveal limit uses.
func _replay_steps(from_index: int, phases: Array[int]) -> Array[ResolutionStep]:
	var out: Array[ResolutionStep] = []
	var turn_log: PhaseEvents.PhaseLog = GameState.turn_log
	if turn_log == null or GameState.player_view == null:
		return out
	var dicts: Array = GameState.player_view.events_for(HUMAN_PLAYER_ID, turn_log.turn)
	_replay_raw_index = raw_indices(turn_log.events, dicts)
	if phases == POST_COMBAT_PHASES:
		_post_events_read = dicts.size()
	for step in ResolutionSteps.build(dicts, from_index, CombatLogPanel.log_ships(GameState.get_all_ships())):
		if phases.has(step.phase):
			out.append(step)
	return out


## Starts a replay of `phases`: the panel goes into the side panel, the map shows each ship as she
## was before the first phase, and the camera pose is kept for the end (kept across a combat
## replay running straight into the post-combat one).
func _start_resolution_replay(kind: String, phases: Array[int]) -> void:
	_ensure_resolution_panel()
	if _replay_saved_view.is_empty() and camera and camera.has_method("save_view"):
		_replay_saved_view = camera.save_view()
	_replay().start(kind, phases)
	if kind == "bear_off":
		return  # movement playback owns the ship views: no display copies, no sync
	display_states.begin(phases)
	_replay_display_phase = phases[0] if not phases.is_empty() else -1
	if combat_log_panel:
		combat_log_panel.set_skip_hint(false)
		combat_log_panel.auto_expand(false)  # the log stays collapsed and fills in step by step
	_sync_all_views()


func _ensure_resolution_panel() -> void:
	if resolution_panel == null or not is_instance_valid(resolution_panel) \
			or resolution_panel.is_queued_for_deletion():
		resolution_panel = ResolutionPanelScene.instantiate()
	if context_panel:
		context_panel.set_context_title("Resolution")
		context_panel.set_context_content(resolution_panel)
	elif resolution_panel.get_parent() == null:
		add_child(resolution_panel)
	current_planning_ui = null  # freed by the context panel
	combat_panel = null
	_replay().attach_panel(resolution_panel)


## Each step as it comes up: the map shows the display copies for it, the log reveals up to its last
## event, a boarding round brings up the boarding card, and (not during Resolve all) the camera
## frames the ship and her target.
func _on_replay_step_shown(step: ResolutionStep, index: int) -> void:
	if resolution_replay.kind == "bear_off":
		_frame_step(step)  # the views stay where movement playback paused them
		return
	if step.phase != _replay_display_phase:
		display_states.phase_reached(step.phase)
		_replay_display_phase = step.phase
	var live := {}  # a ship with no later copy yet shows her state now, not what follows a prompt
	for s: ShipState in GameState.get_all_ships():
		live[s.ship_id] = s
	display_states.step_shown(step, resolution_replay.steps(), index, live)
	var turn_log: PhaseEvents.PhaseLog = GameState.turn_log
	if not step.events.is_empty() and turn_log != null:
		if combat_log_panel and step.last_index < _replay_raw_index.size():
			combat_log_panel.set_reveal_limit(_replay_raw_index[step.last_index] + 1)
		if step.kind == "boarding" and step.first_index < _replay_raw_index.size():
			var raw := _replay_raw_index[step.first_index]
			if raw < turn_log.events.size() and turn_log.events[raw].type == PhaseEvents.Type.BOARDING_ROUND:
				_show_boarding_card(turn_log, turn_log.events[raw])
	_sync_all_views()
	if not resolution_replay.is_resolving_all():
		_frame_step(step)


## Close on the step's ship (as the map draws her), with her target in the frame when there is one,
## clear of the side panel. Never rotates.
func _frame_step(step: ResolutionStep) -> void:
	if not camera or not camera.has_method("frame_ship") or not hex_map:
		return
	var grid: HexGrid = hex_map.get_hex_grid()
	var points: Array[Vector3] = []
	for id in [step.ship_id, step.target_id]:
		if id == "":
			continue
		if resolution_replay.kind == "bear_off":
			# Mid-movement: the ships are where playback paused them, not where their states say.
			var view := ship_views.get(id) as Node3D
			if view != null and view.is_inside_tree():
				points.append(Vector3(view.global_position.x, 0.0, view.global_position.z))
			continue
		var s: ShipState = _drawn_state(id)
		if s != null and s.is_on_map():
			points.append(grid.ship_center_world(s.hex_position, s.facing))
	if points.is_empty():
		return
	var focus := points[0]
	var separation := 0.0
	if points.size() > 1:
		focus = (points[0] + points[1]) * 0.5
		separation = points[0].distance_to(points[1])
	var ship_length := grid.axial_to_world(0, 0).distance_to(grid.axial_to_world(1, 0))
	var safe := _map_safe_rect()
	var distance := step_frame_distance(separation + 3.0 * ship_length, camera.max_zoom / 3.0,
		camera.fov, get_viewport().get_visible_rect().size.y, safe.size)
	camera.frame_ship(focus, distance, safe)


## The camera distance that shows `span` world units within the smaller side of `safe_size`
## (with room to spare), and never closer than `base`.
static func step_frame_distance(span: float, base: float, fov_deg: float, viewport_height: float,
		safe_size: Vector2) -> float:
	var fit := minf(safe_size.x, safe_size.y) * 0.7
	if fit <= 0.0 or viewport_height <= 0.0:
		return base
	var needed := span * viewport_height / (2.0 * tan(deg_to_rad(fov_deg) * 0.5) * fit)
	return maxf(base, needed)


## The replay is over (or dropped): the camera goes back, the map and log show live state again.
## What the side panel shows next is the caller's (End Turn in POST_COMBAT, the next phase's UI).
func _end_resolution_display() -> void:
	if camera and not _replay_saved_view.is_empty() and camera.has_method("restore_view"):
		camera.restore_view(_replay_saved_view)
	_replay_saved_view = {}
	display_states.end()
	_replay_display_phase = -1
	if combat_log_panel:
		combat_log_panel.clear_reveal_limit()
	_sync_all_views()


## Whether the phase `phase` has moved past a replay of `phases`: before them, or after them (the
## post-combat replay runs on while POST_COMBAT waits for it).
static func replay_outlived(kind: String, phases: Array[int], phase: int) -> bool:
	if phases.is_empty():
		return true
	if kind == "post_combat" and phase == TurnPhaseController.GamePhase.POST_COMBAT:
		return false
	return phase < (phases.min() as int) or phase > (phases.max() as int)


## For each event dict of `filtered` (`PlayerView.events_for`: events dropped, never reordered), the
## index of its event in `raw` (the turn log). Matched in order on type, phase, ships and every
## plain data value both still hold (the filter only removes or adds fields); an event with no
## match maps past the end of `raw`.
static func raw_indices(raw: Array[PhaseEvents.PhaseEvent], filtered: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var j := 0
	for d in filtered:
		var found := -1
		for k in range(j, raw.size()):
			if _same_event(raw[k], d):
				found = k
				break
		if found < 0:
			out.append(raw.size())
		else:
			out.append(found)
			j = found + 1
	return out


static func _same_event(ev: PhaseEvents.PhaseEvent, d: Dictionary) -> bool:
	if int(d.get("type", -1)) != int(ev.type) or int(d.get("phase", -1)) != ev.phase \
			or str(d.get("ship_id", "")) != ev.ship_id or str(d.get("target_id", "")) != ev.target_id:
		return false
	var data: Dictionary = d.get("data", {})
	for key in data:
		var value: Variant = data[key]
		if value is Dictionary or value is Array or not ev.data.has(key):
			continue
		if ev.data[key] != value:
			return false
	return true


## The state the map draws for `ship_id`: its display copy while a replay shows one, else live.
func _drawn_state(ship_id: String) -> ShipState:
	var copy := display_states.state_for(ship_id)
	return copy if copy != null else GameState.get_ship(ship_id)


func _drawn_ships() -> Array:
	var out: Array = []
	for ship: ShipState in GameState.get_all_ships():
		out.append(_drawn_state(ship.ship_id))
	return out


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


## The End Turn key shortcut only applies while the button is showing and no combat playback or
## resolution replay is running (the replay owns Space/Enter as Next).
func _end_turn_available() -> bool:
	return end_turn_button != null and is_instance_valid(end_turn_button) \
			and not end_turn_button.disabled and not _combat_playback_active and not _replay_running()


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
	_cancel_resolution_replay()  # dropped: no further server calls
	display_states.end()
	_replay_saved_view = {}  # the final position is framed below instead
	if combat_log_panel:
		combat_log_panel.clear_reveal_limit()
	_close_fire_panel()
	_clear_end_turn_ui()
	_deselect_ship()
	_sync_all_views()
	_courses.clear()
	if hex_overlay:
		hex_overlay.clear_everything()
	current_planning_ui = null
	if context_panel:
		var done := Label.new()
		done.text = "The battle is over."
		context_panel.set_context_title("Game over")
		context_panel.set_context_content(done)  # also frees any leftover planning controls
	_clear_boarding_card()
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
	# Reinforcements placed since the last sync (2.B.1) get their views first.
	for ship_id in views_to_spawn(ship_views.keys(), GameState.get_all_ships()):
		_spawn_ship_view(GameState.get_ship(ship_id))
	# While a resolution replay runs each ship is drawn from her display copy (the state at the step
	# on screen); a view leaves only when what it draws has left the map.
	for ship_id in ship_views.keys():
		var ship_view = ship_views[ship_id]
		var ship_state: ShipState = _drawn_state(ship_id)
		if ship_state and ship_view and hex_map:
			ship_view.sync_to_state(ship_state, hex_map.get_hex_grid())
		if ship_state and not ship_state.is_on_map():
			# 8.G.1f: the ship left the map; its view fades out and frees itself.
			ship_views.erase(ship_id)
			if selected_ship_id == ship_id:
				_deselect_ship()
	if hex_map:
		var drawn := _drawn_ships()
		if anchor_markers == null:
			anchor_markers = AnchorMarkers.new()
			add_child(anchor_markers)
		anchor_markers.refresh(drawn, hex_map.get_hex_grid())
		if grapple_lines == null:
			grapple_lines = GrappleLines.new()
			add_child(grapple_lines)
		grapple_lines.refresh(drawn, hex_map.get_hex_grid())
		if tow_lines == null:
			tow_lines = TowLines.new()
			add_child(tow_lines)
		tow_lines.refresh(drawn, hex_map.get_hex_grid())

## The hawsers ride on the drawn ships every frame (view only): movement playback glides the views
## between hexes, and a hawser drawn from the hexes alone would hang still until the next sync.
func _follow_tow_lines() -> void:
	if tow_lines == null or hex_map == null:
		return
	var ships: Array = _drawn_ships()
	if TowLines.any_tow(ships):
		tow_lines.follow_views(ships, ship_views, hex_map.get_hex_grid())


func _toggle_developer_ui() -> void:
	if developer_ui:
		developer_ui.visible = not developer_ui.visible
		if developer_ui.visible:
			developer_ui.refresh_all()
			Trace.trace_log("GameController", "Developer UI opened (F12 to close)")
