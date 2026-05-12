extends Node
## Main - Entry point and scene manager

const SPLASH_SCREEN = preload("res://scenes/splash_screen.tscn")
const SCENARIO_SELECTION = preload("res://scenes/scenario_selection.tscn")
const GAME_SCENE = preload("res://scenes/main_game.tscn")

var current_scene: Node = null

func _ready() -> void:
	Trace.trace_log("Main", "Main controller ready")
	_load_splash_screen()

func _load_splash_screen() -> void:
	"""Load the splash screen / main menu"""
	_change_scene(SPLASH_SCREEN)

	if current_scene:
		current_scene.play_requested.connect(_on_play_requested)
		current_scene.quit_requested.connect(_on_quit_requested)

func _on_play_requested() -> void:
	"""User clicked Play - show scenario selection"""
	Trace.trace_log("Main", "Loading scenario selection")
	_change_scene(SCENARIO_SELECTION)

	if current_scene:
		current_scene.scenario_selected.connect(_on_scenario_selected)
		current_scene.back_requested.connect(_on_back_to_menu)

func _on_scenario_selected(scenario_name: String) -> void:
	"""User selected a scenario - start the game"""
	Trace.trace_log("Main", "Starting game with scenario: " + scenario_name)

	# Store selected scenario for GameController to load
	GameState.selected_scenario = scenario_name

	_change_scene(GAME_SCENE)

func _on_back_to_menu() -> void:
	"""Return to main menu"""
	Trace.trace_log("Main", "Returning to main menu")
	_load_splash_screen()

func _on_quit_requested() -> void:
	"""User requested quit (handled by splash screen's quit dialog)"""
	pass

func _change_scene(scene_resource: PackedScene) -> void:
	"""Change to a new scene"""
	# Remove current scene
	if current_scene:
		current_scene.queue_free()
		remove_child(current_scene)

	# Load new scene
	current_scene = scene_resource.instantiate()
	add_child(current_scene)
