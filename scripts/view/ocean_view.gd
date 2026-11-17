class_name OceanView
extends Node
## OceanView - feeds the game's wind and sea state to the SeaModel, which drives the water shader
## and the ship motion. Listens to EnvironmentController.environment_updated. Read-only.

var game_state: Node = null
var sea_model: SeaModel = null

func _init(p_game_state: Node = null, p_sea_model: SeaModel = null) -> void:
	game_state = p_game_state if p_game_state else GameState
	sea_model = p_sea_model

func connect_to_controller(controller: EnvironmentController) -> void:
	controller.environment_updated.connect(update_water_shader)

func update_water_shader() -> void:
	if not game_state or not game_state.environment:
		return
	var model := sea_model if sea_model else SeaModel.instance
	if not model:
		push_error("OceanView: no SeaModel to feed")
		return

	var env = game_state.environment
	model.set_environment(env.wind_direction, env.wind_speed, env.sea_state)

	Trace.trace_log("Environment", "Updated sea - Wind: %s (%d), Speed: %s (%d), Sea: %s (%d)" % [
		env.get_wind_direction_name(), env.wind_direction,
		env.get_wind_speed_name(), env.wind_speed,
		env.get_sea_state_name(), env.sea_state
	])
