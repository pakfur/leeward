extends GutTest
## RosterRows: one row per player with a state the local client can know.

const Phase := TurnPhaseController.GamePhase

var pc: TurnPhaseController


func before_each() -> void:
	assert_true(GameState.start_scenario(DataManager.load_scenario("test_basic").duplicate(true), [0] as Array[int]))
	pc = GameState.phase_controller
	pc.current_phase = Phase.SETUP
	pc.combat_step = TurnPhaseController.CombatStep.NONE


func after_each() -> void:
	pc.current_phase = Phase.SETUP
	pc.combat_step = TurnPhaseController.CombatStep.NONE
	pc.players_ready = {0: false, 1: false}
	pc.ended_turn = {}
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	GameState.clear_ships()
	GameState.players.clear()


func _state_of(id: int, resolving := false) -> String:
	for row in RosterRows.rows(GameState, 0, resolving):
		if row.id == id:
			return row.state
	return "?"


func test_planning_states() -> void:
	pc.current_phase = Phase.PLANNING
	pc.players_ready = {0: false, 1: false}
	assert_eq(_state_of(0), "planning")
	pc.players_ready[0] = true
	assert_eq(_state_of(0), "ready")
	assert_eq(_state_of(1), "planning")


func test_fire_declaration_states() -> void:
	pc.current_phase = Phase.COMBAT_RESOLUTION
	pc.combat_step = TurnPhaseController.CombatStep.DECLARE
	pc._fire_ready = {0: false, 1: false}
	assert_eq(_state_of(0), "declaring")
	assert_eq(_state_of(1), "ready")  # AI
	pc._fire_ready[0] = true
	assert_eq(_state_of(0), "ready")
	pc.combat_step = TurnPhaseController.CombatStep.RESOLVE
	assert_eq(_state_of(0), "waiting")


func test_local_resolving_only() -> void:
	pc.current_phase = Phase.PLANNING
	assert_eq(_state_of(0, true), "resolving")
	assert_ne(_state_of(1, true), "resolving")


func test_post_combat_states() -> void:
	pc.current_phase = Phase.POST_COMBAT
	pc.ended_turn = {0: false, 1: false}
	assert_eq(_state_of(0), "reviewing")
	pc.ended_turn[0] = true
	assert_eq(_state_of(0), "ended_turn")
	assert_eq(RosterRows.state_label("ended_turn"), "ended turn")
	pc.current_phase = Phase.MORALE_CHECK
	assert_eq(_state_of(0), "waiting")


func test_no_ships() -> void:
	for ship in GameState.ships_of_player(1):
		ship.status = ShipState.Status.DESTROYED
	pc.current_phase = Phase.PLANNING
	var rows := RosterRows.rows(GameState, 0, false)
	assert_eq(rows[1].state, "no_ships")
	assert_eq(rows[1].ships, 0)
	assert_eq(rows[0].ships, GameState.in_play_ships_of_player(0).size())
	assert_eq(RosterRows.state_label("no_ships"), "no ships")


func test_ai_tag_and_local_name() -> void:
	var rows := RosterRows.rows(GameState, 0, false)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].name, "You")
	assert_true(rows[0].is_local)
	assert_false(rows[0].is_ai)
	assert_true(rows[1].is_ai)
	assert_false(rows[1].is_local)
	GameState.players[1].name = ""
	assert_eq(RosterRows.rows(GameState, 0, false)[1].name, "Player 1")
	GameState.players[1].name = "Villeneuve"
	assert_eq(RosterRows.rows(GameState, 0, false)[1].name, "Villeneuve")
	var roster := PlayerRoster.new()
	add_child_autofree(roster)
	roster.show_rows(rows)
	assert_eq(roster.get_child_count(), 2)
