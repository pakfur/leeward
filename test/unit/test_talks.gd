extends GutTest
## Talking between ships (11.B.3): opened at PLANNING start, one word each way.

const PHASES := TurnPhaseController.GamePhase
var _old_dice: Dice

func before_each() -> void:
	_old_dice = null
	var s := DataManager.load_scenario("test_squadron").duplicate(true)
	assert_true(GameState.start_scenario(s, [0, 1] as Array[int]))
	_pc().current_phase = PHASES.PLANNING
	_pc().players_ready = {0: false, 1: false, 2: false, 3: false}
	GameState.talks.clear()
	_place("brit_a2", Vector2i(0, 0), 0)
	_place("brit_b1", Vector2i(-3, 0), 3)  # sterns at (-1,0) and (-2,0)


func after_each() -> void:
	var pc := _pc()
	pc.ai_player_ids = [] as Array[int]
	pc.human_player_ids = [] as Array[int]
	pc.bear_off_prompt_player_ids = [] as Array[int]
	pc.maintenance_prompt_player_ids = [] as Array[int]
	pc.current_phase = PHASES.SETUP
	pc.players_ready = {0: false, 1: false}
	GameState.dice = Dice.new(GameState.rng)
	GameState.clear_ships()
	GameState.players.clear()
	GameState.groups.clear()
	GameState.talks.clear()


func _pc() -> TurnPhaseController:
	return GameState.phase_controller


func _place(id: String, bow: Vector2i, facing: int) -> void:
	var s: ShipState = GameState.ships[id]
	s.hex_position = bow
	s.facing = facing


func _open(roll: int = 5) -> void:
	var d := ScriptedDice.new()
	d.queue([roll, roll, roll])
	GameState.dice = d
	GameState.talks.clear()
	_pc()._open_talks()


func test_adjacent_sterns_open_a_talk() -> void:
	_open(5)
	assert_eq(GameState.talks.size(), 1)
	var t: Dictionary = GameState.talks[0]
	assert_eq(t["id"], "talk_%d_brit_a2_brit_b1" % GameState.current_turn)
	assert_eq(t["first_player"], GameState.commander_of("brit_b1"))
	assert_eq(t["second_player"], GameState.commander_of("brit_a2"))
	_open(2)
	assert_eq(GameState.talks[0]["first_player"], GameState.commander_of("brit_a2"))


func test_not_adjacent_no_talk() -> void:
	_place("brit_b1", Vector2i(-6, 0), 3)
	_open()
	assert_eq(GameState.talks.size(), 0)


func test_enemy_pair_no_talk() -> void:
	_place("brit_b1", Vector2i(40, 40), 0)
	_place("fr_a2", Vector2i(-3, 0), 3)
	_open()
	assert_eq(GameState.talks.size(), 0)


func test_same_player_pair_no_talk() -> void:
	_place("brit_b1", Vector2i(40, 40), 0)
	_place("brit_a1", Vector2i(-3, 0), 3)
	_open()
	assert_eq(GameState.talks.size(), 0)


func test_second_player_cannot_write_first() -> void:
	_open(5)
	var id: String = GameState.talks[0]["id"]
	assert_ne(_pc().player_send_talk(0, id, "ahoy"), "")
	assert_eq(_pc().player_send_talk(1, id, "ahoy"), "")
	assert_eq(_pc().talks_for(0).size(), 1)
	assert_eq(_pc().talks_for(2).size(), 0)


func test_six_words_refused() -> void:
	_open(5)
	assert_ne(_pc().player_send_talk(1, GameState.talks[0]["id"], "one two three four five six"), "")
	assert_eq(_pc().player_send_talk(1, GameState.talks[0]["id"], "one two three four five"), "")


func test_one_exchange_only() -> void:
	_open(5)
	var id: String = GameState.talks[0]["id"]
	assert_eq(_pc().player_send_talk(1, id, "ahoy"), "")
	assert_eq(_pc().player_send_talk(0, id, "aye"), "")
	assert_eq(_pc().player_send_talk(1, id, "again"), "The exchange is over")
	assert_eq(_pc().player_send_talk(0, id, "again"), "The exchange is over")


func test_halyards_cut_does_not_stop_talk() -> void:
	GameState.ship_controller.add_critical_effect("brit_a2", {"id": "signal_halyards_cut"})
	_open(5)
	assert_eq(_pc().player_send_talk(1, GameState.talks[0]["id"], "ahoy"), "")


func test_reply_allowed_after_plan_submitted() -> void:
	_open(5)
	var id: String = GameState.talks[0]["id"]
	_pc().players_ready[0] = true
	_pc().players_ready[1] = true
	_pc().players_ready[2] = false  # another player still planning
	assert_eq(_pc().player_send_talk(1, id, "ahoy"), "")
	assert_eq(_pc().player_send_talk(0, id, "aye"), "")


func test_ai_commander_pair_no_talk_and_no_die() -> void:
	_place("brit_b1", Vector2i(40, 40), 0)
	_place("fr_a2", Vector2i(-3, 0), 3)
	GameState.ships["fr_a2"].controller_side = 0  # friendly to brit_a2, commanded by AI player 2
	GameState.ships["fr_a2"].commander_id = 2
	var d := ScriptedDice.new()
	d.queue([5])
	GameState.dice = d
	GameState.talks.clear()
	_pc()._open_talks()
	assert_eq(GameState.talks.size(), 0)
	assert_eq(d.remaining(), 1)
