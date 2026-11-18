extends GutTest
## Server authority over game state (CLAUDE.md "Server Authority"): view-side code
## (scripts/ui, scripts/view, scripts/core) reads state and sends requests that the server
## validates (player_submit_*, including player_submit_fire_orders with its marine fire orders, player_clear_movement, player_plot_crew, player_set_crew_auto,
## player_plot_sail_change, player_submit_maintenance_orders (grapple and ungrapple orders, prize-crew sizes), dev_commands.*, including dev_commands.start_fire,
## dev_commands.damage_ship and dev_commands.grapple_ships). Boarding orders are crew orders
## (player_plot_crew); the boarding controller and capture fields are never touched by view code. It never calls a state mutator or writes a ShipState field itself.
## This test scans the source so a violation fails `make test`.

const VIEW_DIRS := ["res://scripts/ui", "res://scripts/view", "res://scripts/core", "res://scripts/commands"]

## [regex, what it catches]
const FORBIDDEN := [
	# read-only queries (get_/is_/can_/has_) are allowed
	["\\bship_controller\\.(?!get_|is_|can_|has_)", "a ShipStateController mutator called from view code"],
	["\\bShipStateController\\b", "ShipStateController used from view code"],
	["\\bset_standing_order\\(", "a standing order set from view code (orders come from delivered signals)"],
	["\\benvironment_controller\\.set_", "an EnvironmentController mutator called from view code"],
	# the crew overlay reads plans through these queries only; crew plots go through
	# phase_controller.player_plot_crew / player_set_crew_auto
	["\\bcrew_task_controller\\.(?!current_plan\\(|planned_tack_sections\\(|handler\\()", "a CrewTaskController mutator called from view code"],
	["\\bsail_controller\\.(plot_sail_change|cancel_change)\\(", "a SailController mutator called from view code (use player_plot_sail_change)"],
	["\\bCrewTaskController\\.new\\b", "a CrewTaskController made in view code"],
	["\\b(register_handler|finalize_plots|begin_turn_tasks|advance_tasks|cancel_section|cancel_task|cancel_code|force_task|reset_progress|drop_all)\\(",
			"a crew-task engine call from view code"],
	["(?<!player_)\\b(plot_crew|set_auto|set_crew_auto|set_crew_assignments|set_crew_orders|add_task|update_task|end_task|set_plotted_sections)\\(",
			"a crew plot or task mutator called from view code (use player_plot_crew / player_set_crew_auto)"],
	["\\bphase_controller\\.advance_phase\\(", "phase advanced from view code (use dev_commands)"],
	# repairs (8.F): the view reads crew_tasks / checked_sections; RepairController's statics
	# (refusal, mp_warning, is_repair, max_mp) are pure queries; the only request is
	# dev_commands.damage_ship (Developer UI)
	["\\brepair_controller\\.", "a RepairController call from view code"],
	["\\bRepairController\\.new\\b", "a RepairController made in view code"],
	["(?<!dev_commands\\.)\\b(repair_box|mark_section_checked|set_mp_used|clear_crew_plot|after_movement|rigging_hit_while_dismasted|apply_hits|on_complete|on_reset)\\(",
			"a repair or damage mutator called from view code"],
	["\\.checked_sections\\s*\\[[^\\]]*\\]\\s*\\[[^\\]]*\\]\\s*=[^=]", "checked_sections changed in place from view code"],
	# fires (8.E): the view reads fire_list / fire_count() / is_burning(); the only request is
	# dev_commands.start_fire (Developer UI)
	["\\bfire_controller\\.(?!skill\\()", "a FireController mutator called from view code (use dev_commands.start_fire)"],
	["\\bFireController\\.new\\b", "a FireController made in view code"],
	# map events (map and scenario spec): the view may only ask the controller for arrival_speed / pursuers
	["\\bmap_controller\\.(?!arrival_speed\\(|pursuers\\()", "a MapController call from view code"],
	["\\bMapController\\.new\\b", "a MapController made in view code"],
	# leaving the map (8.G.1f): the view reads is_on_map() / GameState.ships_on_map(); only the
	# server's END_TURN step removes a ship
	["\\bremove_from_map\\(", "a ship removed from the map by view code"],
	["\\.removed_from_map\\s*(=|\\+=|-=)[^=]", "removed_from_map written from view code"],
	# terrain, escape and arrival (map and scenario spec): the view reads is_aground() /
	# is_escaped() / is_awaiting_arrival() / casts_lead()
	["\\.(aground|aground_turn|escape_declared|awaiting_arrival|arrives_turn)\\s*(=|\\+=|-=)[^=]", "a terrain, escape or arrival field written from view code"],
	["(?<!player_)\\b(set_aground|set_escape_declared|set_cast_lead|place_arrival|delay_arrival)\\(", "a terrain, escape or arrival mutator called from view code"],
	["(?<!dev_commands\\.)\\b(start_fire|explode|add_fire|remove_fire|clear_fires|set_explosion_checks)\\(",
			"a fire mutator called from view code"],
	# gunfire and marine fire (7.G): the view previews through GunneryCalculator and
	# MarineFireResolver's queries (preview, eligible_marine_shots, any_eligible_marine_shot,
	# validate_orders); orders go through phase_controller.player_submit_fire_orders
	["\\bmarine_fire_resolver\\.(?!preview\\(|eligible_marine_shots\\(|any_eligible_marine_shot\\(|validate_orders\\()",
			"a MarineFireResolver mutator called from view code (use player_submit_fire_orders)"],
	["\\b(MarineFireResolver|GunneryResolver)\\.new\\b", "a fire resolver made in view code"],
	["\\bgunnery_resolver\\.", "a GunneryResolver call from view code (use player_submit_fire_orders)"],
	["\\b(apply_crew_losses|apply_crew_boxes|remove_crew_box)\\(", "a crew-loss mutator called from view code"],
	["\\.(prepare|resolve)\\(", "a resolver step run from view code"],
	# grappling (8.C): the view reads grappled_with / is_grappled(); GrapplingController's queries
	# (grapple_options, grapple_chance, grapple_error and their ungrapple twins) are pure; orders go
	# through phase_controller.player_submit_maintenance_orders
	["\\bgrappling_controller\\.(?!grapple_options\\(|grapple_chance\\(|grapple_error\\(|ungrapple_options\\(|ungrapple_chance\\(|ungrapple_error\\(|adjacent\\()",
			"a GrapplingController mutator called from view code (use player_submit_maintenance_orders)"],
	["\\bGrapplingController\\.new\\b", "a GrapplingController made in view code"],
	["\\b(resolve_grapples|resolve_ungrapples|add_grapple|remove_grapple|set_ungrapple_attempts)\\(",
			"a grapple mutator called from view code"],
	["\\.(grappled_with|ungrapple_attempts)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "a grapple field written from view code"],
	["\\.(grappled_with|ungrapple_attempts)\\.(append|append_array|clear|erase|remove_at|push_back|push_front|pop_back|pop_front|insert|resize|sort|sort_custom|fill|merge)\\(",
			"a grapple field changed in place from view code"],
	# boarding (10.A-10.H): the view reads boarding_actions, linked_at_plot and the ShipState
	# boarding helpers; BoardingRules' statics and BoardingController's queries are pure; orders go
	# through phase_controller.player_plot_crew (the boarding order is a crew order)
	["\\bboarding_controller\\.(?!preview\\(|tbcf\\(|live_action_of\\(|live_action_between\\(|locked_in_boarding\\(|counter_board\\(|action_by_id\\(|actions\\(|has_actions_to_resolve\\(|drms_for\\(|marines_in_boarding\\(|prize_size_options\\(|defence_tbcf\\(|attack_tbcf\\(|reorganizing_capture_of\\()",
			"a BoardingController mutator called from view code (use player_plot_crew)"],
	["\\b(BoardingController|BoardingTaskHandler)\\.new\\b", "a boarding controller made in view code"],
	["(?<!dev_commands\\.)\\b(declare|capture|advance_reorganizing|end_of_turn|take_link_snapshot|transfer_control|set_controller_side|set_prize|set_crew|add_detached_box|remove_crew_box_from|apply_boarding_losses|apply_boarding_losses_shared|detach_prize_crew|grapple_ships|start_of_turn|retake|set_prize_size|set_navy|set_value_morale_rating)\\(",
			"a boarding or capture mutator called from view code"],
	["\\.(controller_side|prize|detached_boxes|navy|value_morale_rating|boarding_actions|linked_at_plot|boarding_seq|boarding_history)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "a boarding or capture field written from view code"],
	["\\b(set_commander)\\(", "a commander mutator called from view code"],
	["\\.(commander_id)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "commander_id written from view code"],
	["\\b(GameState|game_state)\\.(players|groups)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "players or groups written from view code"],
	["\\b(GameState|game_state)\\.(players|groups)\\.(append|clear|erase|merge|set|assign)\\(", "players or groups changed in place from view code"],
	["\\b(GameState|game_state)\\.signals\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "signals written from view code"],
	["\\b(GameState|game_state)\\.signals\\.(append|append_array|clear|erase|remove_at|push_back|insert|sort|sort_custom)\\(", "signals changed in place from view code"],
	["\\b(GameState|game_state)\\.end_offers\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "end_offers written from view code"],
	["\\b(GameState|game_state)\\.end_offers\\.(clear|erase|merge)\\(", "end_offers changed in place from view code"],
	["\\b(GameState|game_state)\\.talks\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "talks written from view code"],
	["\\b(GameState|game_state)\\.talks\\.(append|append_array|clear|erase|remove_at|push_back|insert|sort|sort_custom)\\(", "talks changed in place from view code"],
	["\\.standing_order\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "a standing order written from view code"],
	["\\.standing_order\\.(clear|erase|merge|assign|set)\\(", "a standing order changed in place from view code"],
	["\\b(get_player\\([^)]*\\)|players\\[[^\\]]*\\])\\.(id|side|name|is_ai)\\s*(=|\\+=|-=)[^=]", "a PlayerState field written from view code"],
	["\\.(delivered|words|address)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "a signal field written from view code"],
	["\\.(prize|detached_boxes|boarding_actions|linked_at_plot|boarding_history)\\.(append|append_array|clear|erase|remove_at|push_back|push_front|pop_back|pop_front|insert|resize|sort|sort_custom|fill|merge)\\(",
			"a boarding or capture field changed in place from view code"],
	["\\b(_?action|a)\\.(state|attacker_sections|defender_sections|rounds|outcome|prize_aboard|finished_turn|prize_size|helper_id|helper_sections|original_crew_joins|prize_action|retaken|shared_with)\\s*(=|\\+=|-=)[^=]", "a BoardingAction field written from view code"],
	["\\.(fire_list|crew_tasks|critical_effects|plotted_sections)\\.(append|append_array|clear|erase|remove_at|push_back|push_front|pop_back|pop_front|insert|resize|sort|sort_custom|fill)\\(",
			"a ShipState array changed in place from view code"],
	# the game itself: the view starts a scenario with GameState.start_scenario (server side) and
	# never fills or rewrites the state container, the logs or the phase controller's settings
	["\\b(GameState|game_state)\\.(clear_ships|add_ship|remove_ship|start_new_game|deserialize_full_state|sync_from_server|save_\\w*snapshot|clear_state_history|new_turn_log|transfer_control)\\(",
			"a GameState container mutator called from view code"],
	["\\bturn_logs?\\b.*\\.(add|insert|remove)\\(", "a turn log written from view code"],
	["\\bturn_logs\\s*\\[[^\\]]*\\]\\s*=[^=]", "a turn log stored from view code"],
	["\\.(events|players)\\.(append|append_array|clear|erase|remove_at|insert|sort|sort_custom|merge)\\(", "a logged event changed from view code"],
	["\\bphase_controller\\.\\w+\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "a TurnPhaseController field written from view code"],
	["\\bplayer_submit_plan\\(\\s*[1-9]", "a plan submitted for the AI side from view code (the server marks it ready)"],
	["\\bmovement_resolver\\.(run|apply_results|log_outcomes|roll_fouling)\\(", "a MovementResolver step run from view code"],
	["\\b(damage_controller|morale_controller|victory_controller|critical_hit_controller|fouling_controller|drift_resolver|stub_ai|command_validator|network_sync)\\.", "a server controller called from view code"],
	["\\.(moved_this_turn|collision_this_turn|pending_turn|immobilized|tacking|rudder_destroyed|wheel_shot_away|guns_dismounted|initial_broadside_fired|morale_rating|starting_crew_quality|pending_morale_checks|morale_triggers_used|unfoul_attempts|critical_seq)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]",
			"a ShipState field written from view code"],
	["\\.(crew_count|rigging_current_hp|hull_current_hp|guns_dismounted|initial_broadside_fired|pending_morale_checks|morale_triggers_used|unfoul_attempts)\\.(append|append_array|clear|erase|remove_at|insert|resize|fill)\\(",
			"a ShipState array changed in place from view code"],
	["\\.plotted_actions\\s*\\[[^\\]]*\\]\\s*=[^=]|\\.plotted_actions\\.(merge|erase|clear)\\(", "a plot written from view code"],
	["\\b(environment|env)\\.(wind_speed|wind_direction|pending_wind_speed|pending_wind_direction|original_wind_speed|original_wind_direction|sea_state|visibility|time_of_day|precipitation)\\s*(=|\\+=|-=)[^=]",
			"an EnvironmentState field written from view code"],
	["\\b(_?ship|ship_state|ss|state|s)\\.(hex_position|facing|speed|sail_state|status|crew_count|marine_count|rigging_current_hp|hull_current_hp|crew_quality|plotted_actions|fouled_with|critical_effects|crew_tasks|crew_plots|crew_auto|standing_order|plotted_sections|task_seq|fire_list|fire_seq|explosion_checks|checked_sections|mp_used_this_turn)\\s*(=|\\+=|-=)[^=]",
			"a ShipState field written from view code"],
]


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(d)))
	return out


func test_view_code_never_mutates_game_state() -> void:
	var violations: Array[String] = []
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		assert_eq(re.compile(f[0]), OK, "pattern compiles: %s" % f[0])
		checks.append([re, f[1]])
	var scanned := 0
	for dir_path in VIEW_DIRS:
		for path in _gd_files(dir_path):
			scanned += 1
			var lines := FileAccess.get_file_as_string(path).split("\n")
			for i in lines.size():
				var line: String = lines[i]
				if line.strip_edges().begins_with("#"):
					continue
				for c in checks:
					if c[0].search(line) != null:
						violations.append("%s:%d %s: %s" % [path, i + 1, c[1], line.strip_edges()])
	assert_gt(scanned, 10, "view code was scanned")
	assert_eq(violations.size(), 0, "view code must not mutate game state:\n" + "\n".join(violations))


## The grapple patterns (8.C) catch the violations they are meant to, and let the queries through.
func test_grapple_patterns_catch_mutations() -> void:
	var bad := [
		"GameState.grappling_controller.resolve_grapples(orders, 6)",
		"GameState.ship_controller.add_grapple(\"a\", \"b\")",
		"remove_grapple(a, b)",
		"ship.grappled_with = []",
		"s.grappled_with.append(\"b\")",
		"ship.ungrapple_attempts[\"b\"] = 2",
		"var g = GrapplingController.new(GameState)",
	]
	var good := [
		"var options = GameState.grappling_controller.grapple_options(ship_id)",
		"if s.grappled_with.has(other_id):",
		"var n := ship.grappled_with.size()",
		"GameState.phase_controller.player_submit_maintenance_orders(0, {\"grapple\": pairs})",
	]
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		re.compile(f[0])
		checks.append(re)
	for line in bad:
		var hit := false
		for re in checks:
			if re.search(line) != null:
				hit = true
		assert_true(hit, "caught: %s" % line)
	for line in good:
		for re in checks:
			assert_null(re.search(line), "allowed: %s" % line)


## The boarding patterns (boarding spec B4) catch the violations they are meant to, and let the
## queries through.
func test_boarding_patterns_catch_mutations() -> void:
	var bad := [
		"GameState.boarding_controller.resolve(6)",
		"GameState.boarding_controller.capture(action, false, 4)",
		"GameState.transfer_control(\"b\", 0)",
		"GameState.ship_controller.set_controller_side(\"b\", 0)",
		"set_prize(\"b\", {})",
		"ship.controller_side = 1",
		"s.prize[\"captor_id\"] = \"a\"",
		"GameState.boarding_actions.append(x)",
		"GameState.linked_at_plot = {}",
		"action.state = \"engaged\"",
		"a.defender_sections = []",
		"var c = BoardingController.new(GameState)",
		"damage_controller.apply_boarding_losses(\"b\", 5, [0], \"C\", 4)",
		"GameState.boarding_controller.start_of_turn(1)",
		"GameState.boarding_controller.retake(\"b\", \"rose\", 1)",
		"GameState.boarding_controller.set_prize_size(3, 4)",
		"GameState.ship_controller.set_navy(\"b\", \"French\")",
		"ship.navy = \"French\"",
		"s.value_morale_rating = 6",
		"action.helper_sections = []",
		"damage_controller.apply_boarding_losses_shared([], 5, 4)",
		"a.shared_with = 3",
	]
	var good := [
		"var p = GameState.boarding_controller.preview(ship_id, enemy_id, [4, 0])",
		"var plan := BoardingRules.with_order(s, plan(), ctx(), order)",
		"if ship.is_captured():",
		"var captor := str(ship.prize.get(\"captor_id\", \"\"))",
		"for a in GameState.boarding_actions:",
		"if action.state == BoardingAction.ENGAGED:",
		"GameState.phase_controller.player_plot_crew(0, ship_id, request)",
		"GameState.dev_commands.grapple_ships(\"a\", \"b\")",
		"var options = GameState.boarding_controller.prize_size_options(0)",
		"if BoardingController.recapture_due(s):",
		"if ship.navy == \"French\":",
		"GameState.phase_controller.player_submit_maintenance_orders(0, {\"prize_size\": {3: 4}})",
	]
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		re.compile(f[0])
		checks.append(re)
	for line in bad:
		var hit := false
		for re in checks:
			if re.search(line) != null:
				hit = true
		assert_true(hit, "caught: %s" % line)
	for line in good:
		for re in checks:
			assert_null(re.search(line), "allowed: %s" % line)


## The terrain, escape and arrival patterns catch writes and mutator calls, and let the queries through.
func test_terrain_patterns_catch_mutations() -> void:
	var bad := [
		"ship.aground = true",
		"s.escape_declared = false",
		"GameState.ship_controller.set_aground(\"a\", 2)",
		"place_arrival(id, 5)",
	]
	var good := [
		"if ship.is_aground():",
		"GameState.phase_controller.player_set_cast_lead(0, \"a\", true)",
		"if ship.aground == true:",
	]
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		re.compile(f[0])
		checks.append(re)
	for line in bad:
		var hit := false
		for re in checks:
			if re.search(line) != null:
				hit = true
		assert_true(hit, "caught: %s" % line)
	for line in good:
		for re in checks:
			assert_null(re.search(line), "allowed: %s" % line)


func test_dev_commands_refuse_unknown_property() -> void:
	var dc := DevCommands.new(GameState)
	if GameState.ships.is_empty():
		assert_ne(dc.set_ship_property("nope", "facing", 1), "", "an unknown ship is refused")
		return
	var sid: String = GameState.ships.keys()[0]
	assert_ne(dc.set_ship_property(sid, "hull_current_hp", 0), "", "an unlisted property is refused")


func _dev_ship(id: String, player: int, hex: Vector2i, facing: int) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({"ship_id": id, "player_id": player, "ship_name": id,
		"ship_type": "frigate_38", "class": 3, "crew_count": [3, 3, 3, 3], "marine_count": 2,
		"rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6]})
	state.hex_position = hex
	state.facing = facing
	state.rigging_current_hp = [5, 5, 6, 6] as Array[int]
	state.hull_current_hp = [5, 5, 5, 6] as Array[int]
	state.crew_count = [3, 3, 3, 3] as Array[int]
	GameState.ships[id] = state
	GameState.ships_by_side[player].append(id)
	return state


func test_dev_place_ship_moves_through_the_server_and_refuses_held_hexes() -> void:
	var old_ships: Dictionary = GameState.ships.duplicate()
	var old_by_player: Dictionary = GameState.ships_by_side.duplicate(true)
	var old_scenario: Dictionary = GameState.active_scenario
	GameState.ships = {}
	GameState.ships_by_side = {0: [], 1: []}
	GameState.active_scenario = {"map_bounds": {"width": 20, "height": 20}}
	var a := _dev_ship("dev_a", 0, Vector2i.ZERO, 0)
	_dev_ship("dev_b", 1, Vector2i(4, 4), 0)
	var dc := DevCommands.new(GameState)
	assert_ne(dc.place_ship("nope", Vector2i.ZERO, 0), "", "an unknown ship is refused")
	assert_string_contains(dc.place_ship("dev_a", Vector2i(4, 4), 0), "held by", "a ship's hex is refused")
	assert_string_contains(dc.place_ship("dev_a", Vector2i(5, 4), 0), "held by", "the stern on a ship is refused")
	assert_string_contains(dc.place_ship("dev_a", Vector2i(30, 0), 0), "off the map")
	assert_ne(dc.place_ship("dev_a", Vector2i.ZERO, 7), "", "a bad facing is refused")
	assert_eq(dc.place_ship("dev_a", Vector2i(3, 5), 3), "", "alongside dev_b")
	assert_eq(a.hex_position, Vector2i(3, 5))
	assert_eq(a.facing, 3)
	GameState.ships = old_ships
	GameState.ships_by_side = old_by_player
	GameState.active_scenario = old_scenario


## Movement is plotted in PLANNING before the player's plan is in (or in SETUP, before any turn
## loop runs); the server refuses it otherwise, whatever the view sends.
func test_plotting_refused_after_submit_or_outside_planning() -> void:
	var old_ships: Dictionary = GameState.ships.duplicate()
	var old_by_player: Dictionary = GameState.ships_by_side.duplicate(true)
	GameState.ships = {}
	GameState.ships_by_side = {0: [], 1: []}
	var plotter := _dev_ship("plot_a", 0, Vector2i.ZERO, 0)
	plotter.ship = Ship.from_dict({"ship_id": "plot_a", "player_id": 0, "ship_name": "plot_a",
		"ship_type": "frigate_38", "class": 3, "maneuverability": "C", "speed_type": "F/F",
		"crew_count": [3, 3, 3, 3], "marine_count": 2, "rigging_hp": [5, 5, 6, 6], "hull_hp": [5, 5, 5, 6]})
	plotter.sail_state = "MS"
	var pc: TurnPhaseController = GameState.phase_controller
	var mpc: MovementPlottingController = GameState.movement_plotting_controller
	var P := TurnPhaseController.GamePhase
	pc.current_phase = P.PLANNING
	pc.players_ready = {0: true, 1: false}
	var refused := mpc.handle_start_plotting(0, "plot_a", "r1")
	assert_true(refused is MovementTypes.PlottingErrorResponse)
	assert_eq((refused as MovementTypes.PlottingErrorResponse).error_code, "NOT_PLANNING", "plan already submitted")
	pc.players_ready = {0: false, 1: false}
	pc.current_phase = P.COMBAT_RESOLUTION
	var late := mpc.handle_start_plotting(0, "plot_a", "r2")
	assert_eq((late as MovementTypes.PlottingErrorResponse).error_code, "NOT_PLANNING", "outside PLANNING")
	pc.current_phase = P.PLANNING
	var ok := mpc.handle_start_plotting(0, "plot_a", "r3")
	assert_false(ok is MovementTypes.PlottingErrorResponse, "PLANNING, plan not yet in")
	mpc.sessions.clear()
	mpc.ship_sessions.clear()
	pc.current_phase = P.SETUP
	GameState.ships = old_ships
	GameState.ships_by_side = old_by_player


## The map-removal patterns (8.G.1f) catch the violations and let the queries through.
func test_map_removal_patterns_catch_mutations() -> void:
	var bad := [
		"GameState.ship_controller.remove_from_map(\"w\")",
		"remove_from_map(ship_id)",
		"ship.removed_from_map = true",
	]
	var good := [
		"if not ship_state.is_on_map():",
		"for s in GameState.ships_on_map():",
		"if ship.removed_from_map == true:",
	]
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		re.compile(f[0])
		checks.append(re)
	for line in bad:
		var hit := false
		for re in checks:
			if re.search(line) != null:
				hit = true
		assert_true(hit, "caught: %s" % line)
	for line in good:
		for re in checks:
			assert_null(re.search(line), "allowed: %s" % line)


## The players-and-sides patterns (players, groups, signals, talks, end offers, commanders, standing
## orders, PlayerState fields) catch the violations they are meant to, and let the queries through.
func test_players_and_sides_patterns_catch_mutations() -> void:
	var bad := [
		"GameState.players[0] = p",
		"GameState.players.clear()",
		"GameState.groups[0] = {}",
		"GameState.groups.erase(0)",
		"GameState.signals.append(sig)",
		"GameState.signals = []",
		"GameState.talks.clear()",
		"GameState.talks[0] = {}",
		"GameState.end_offers[0] = true",
		"GameState.end_offers.erase(0)",
		"ship.commander_id = 1",
		"GameState.ship_controller.set_commander(\"a\", 1)",
		"GameState.ship_controller.set_standing_order(\"a\", {})",
		"ship.standing_order = {}",
		"ship.standing_order[\"order\"] = \"engage\"",
		"s.standing_order.merge({\"a\": 1})",
		"s.standing_order.erase(\"order\")",
		"s.standing_order.clear()",
		"sig.delivered = true",
		"sig.words = []",
		"sig.address = {}",
		"GameState.get_player(0).is_ai = false",
		"GameState.players[0].side = 1",
		"GameState.get_player(0).name = \"x\"",
	]
	var good := [
		"var o = GameState.order_of(\"a\")",
		"if GameState.commands(0, \"a\"):",
		"var n := GameState.get_player(0).name",
		"if GameState.players[0].is_ai:",
		"var side := GameState.side_of_player(0)",
		"var order: Dictionary = ship.standing_order",
		"var t = GameState.phase_controller.talks_for(0)",
		"if sig.delivered:",
		"var p = GameState.signals.size()",
		"view.side = 1",
		"label.name = \"Plate\"",
	]
	var checks: Array = []
	for f in FORBIDDEN:
		var re := RegEx.new()
		re.compile(f[0])
		checks.append(re)
	for line in bad:
		var hit := false
		for re in checks:
			if re.search(line) != null:
				hit = true
		assert_true(hit, "caught: %s" % line)
	for line in good:
		for re in checks:
			assert_null(re.search(line), "allowed: %s" % line)
