extends GutTest
## The minimap is built from the scenario of the game being started (GameState.game_started),
## never from whatever GameState.active_scenario held when the scene was instantiated.

const MinimapScene = preload("res://scenes/ui/minimap.tscn")

var _saved_scenario: Dictionary


func before_each() -> void:
	_saved_scenario = GameState.active_scenario


func after_each() -> void:
	GameState.active_scenario = _saved_scenario


func _make_minimap() -> Control:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	var minimap: Control = MinimapScene.instantiate()
	add_child_autofree(minimap)
	return minimap


func test_ready_ignores_the_previous_games_scenario() -> void:
	GameState.active_scenario = {"map_bounds": {"width": 7, "height": 9}, "minimap_texture": ""}
	var minimap := _make_minimap()
	assert_eq(minimap.map_bounds, Vector2(100, 100), "stale scenario not applied at _ready")
	assert_null(minimap.background.texture, "dark panel until the game starts")


func test_minimap_listens_for_the_game_start() -> void:
	var minimap := _make_minimap()
	assert_true(GameState.game_started.is_connected(minimap.configure_for_scenario))


func test_no_minimap_texture_gives_the_dark_panel_in_every_game() -> void:
	var minimap := _make_minimap()
	var scenario := {"map_bounds": {"width": 30, "height": 20}, "minimap_texture": ""}
	minimap.configure_for_scenario(scenario)
	assert_null(minimap.background.texture, "first game: no texture over the panel")
	assert_eq(minimap.map_bounds, Vector2(30, 20))
	minimap.configure_for_scenario(scenario)
	assert_null(minimap.background.texture, "a later game looks the same")


func test_a_scenario_minimap_texture_is_used() -> void:
	var minimap := _make_minimap()
	minimap.configure_for_scenario({"minimap_texture": "res://icon.svg"})
	if ResourceLoader.exists("res://icon.svg"):
		assert_not_null(minimap.background.texture)
	minimap.configure_for_scenario({"minimap_texture": ""})
	assert_null(minimap.background.texture, "the next game's scenario without one clears it")
