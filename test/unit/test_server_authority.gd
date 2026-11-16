extends GutTest
## Server authority over game state (CLAUDE.md "Server Authority"): view-side code
## (scripts/ui, scripts/view, scripts/core) reads state and sends requests that the server
## validates (player_submit_*, including player_submit_fire_orders with its marine fire orders, player_clear_movement, player_plot_crew, player_set_crew_auto,
## player_plot_sail_change, player_submit_maintenance_orders (grapple and ungrapple orders), dev_commands.*, including dev_commands.start_fire,
## dev_commands.damage_ship and dev_commands.grapple_ships). Boarding orders are crew orders
## (player_plot_crew); the boarding controller and capture fields are never touched by view code. It never calls a state mutator or writes a ShipState field itself.
## This test scans the source so a violation fails `make test`.

const VIEW_DIRS := ["res://scripts/ui", "res://scripts/view", "res://scripts/core"]

## [regex, what it catches]
const FORBIDDEN := [
	# read-only queries (get_/is_/can_/has_) are allowed
	["\\bship_controller\\.(?!get_|is_|can_|has_)", "a ShipStateController mutator called from view code"],
	["\\bShipStateController\\b", "ShipStateController used from view code"],
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
	["\\bboarding_controller\\.(?!preview\\(|tbcf\\(|live_action_of\\(|live_action_between\\(|locked_in_boarding\\(|counter_board\\(|action_by_id\\(|actions\\(|has_actions_to_resolve\\(|drms_for\\(|marines_in_boarding\\()",
			"a BoardingController mutator called from view code (use player_plot_crew)"],
	["\\b(BoardingController|BoardingTaskHandler)\\.new\\b", "a boarding controller made in view code"],
	["(?<!dev_commands\\.)\\b(declare|capture|advance_reorganizing|end_of_turn|take_link_snapshot|transfer_control|set_controller|set_prize|set_crew|add_detached_box|remove_crew_box_from|apply_boarding_losses|detach_prize_crew|grapple_ships)\\(",
			"a boarding or capture mutator called from view code"],
	["\\.(controller_id|prize|detached_boxes|boarding_actions|linked_at_plot|boarding_seq|boarding_history)\\s*(\\[[^\\]]*\\]\\s*)?(=|\\+=|-=)[^=]", "a boarding or capture field written from view code"],
	["\\.(prize|detached_boxes|boarding_actions|linked_at_plot|boarding_history)\\.(append|append_array|clear|erase|remove_at|push_back|push_front|pop_back|pop_front|insert|resize|sort|sort_custom|fill|merge)\\(",
			"a boarding or capture field changed in place from view code"],
	["\\b(_?action|a)\\.(state|attacker_sections|defender_sections|rounds|outcome|prize_aboard|finished_turn|prize_size)\\s*(=|\\+=|-=)[^=]", "a BoardingAction field written from view code"],
	["\\.(fire_list|crew_tasks|critical_effects|plotted_sections)\\.(append|append_array|clear|erase|remove_at|push_back|push_front|pop_back|pop_front|insert|resize|sort|sort_custom|fill)\\(",
			"a ShipState array changed in place from view code"],
	["\\b(_?ship|ship_state|ss|state|s)\\.(hex_position|facing|speed|sail_state|status|crew_count|marine_count|rigging_current_hp|hull_current_hp|crew_quality|plotted_actions|fouled_with|critical_effects|crew_tasks|crew_plots|crew_auto|plotted_sections|task_seq|fire_list|fire_seq|explosion_checks|checked_sections|mp_used_this_turn)\\s*(=|\\+=|-=)[^=]",
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
		"GameState.ship_controller.set_controller(\"b\", 0)",
		"set_prize(\"b\", {})",
		"ship.controller_id = 1",
		"s.prize[\"captor_id\"] = \"a\"",
		"GameState.boarding_actions.append(x)",
		"GameState.linked_at_plot = {}",
		"action.state = \"engaged\"",
		"a.defender_sections = []",
		"var c = BoardingController.new(GameState)",
		"damage_controller.apply_boarding_losses(\"b\", 5, [0], \"C\", 4)",
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
	GameState.ships_by_player[player].append(id)
	return state


func test_dev_place_ship_moves_through_the_server_and_refuses_held_hexes() -> void:
	var old_ships: Dictionary = GameState.ships.duplicate()
	var old_by_player: Dictionary = GameState.ships_by_player.duplicate(true)
	var old_scenario: Dictionary = GameState.active_scenario
	GameState.ships = {}
	GameState.ships_by_player = {0: [], 1: []}
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
	GameState.ships_by_player = old_by_player
	GameState.active_scenario = old_scenario
