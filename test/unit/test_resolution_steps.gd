extends GutTest
## Tests for ResolutionSteps (the replay step builder) and PhaseEvent.from_dict.

const Type := PhaseEvents.Type
const SHIPS := {
	"a": {"name": "Alpha", "player": 0},
	"b": {"name": "Bravo", "player": 1},
	"c": {"name": "Charlie", "player": 0},
	"d": {"name": "Delta", "player": 1},
}


func _ev(type: Type, ship: String, data: Dictionary = {}, target := "", phase := 4) -> Dictionary:
	return PhaseEvents.PhaseEvent.new(type, phase, ship, data, target).to_dict()


func _fire_data() -> Dictionary:
	return {
		"side": 1, "battery": "full", "range": 3, "aim": "low", "ammo": "round", "bgn": 22,
		"modifiers": [{"name": "crew_quality", "value": 2}, {"name": "initial_broadside", "value": 3}],
		"mgn": 27, "d6": 4, "fgn": 31, "rake": "", "rigging": 2, "hull": 1, "crew": 1,
	}


func test_from_dict_round_trips() -> void:
	var ev := PhaseEvents.PhaseEvent.new(Type.GRAPPLE, 6, "a", {"roll": 2, "modifiers": [{"name": "skill", "value": -1}]}, "b")
	ev.sides = {"a": 0, "b": 1}
	var back := PhaseEvents.PhaseEvent.from_dict(ev.to_dict())
	assert_eq(back.type, ev.type)
	assert_eq(back.phase, ev.phase)
	assert_eq(back.ship_id, ev.ship_id)
	assert_eq(back.target_id, ev.target_id)
	assert_eq(back.data, ev.data)
	assert_eq(back.sides, ev.sides)
	back.data["roll"] = 9
	assert_eq(ev.data["roll"], 2, "the copy is detached")


func test_fire_folds_its_damage_and_crit() -> void:
	var evs: Array = [
		_ev(Type.FIRE, "a", _fire_data(), "b"),
		_ev(Type.DAMAGE, "b", {"hull": 1}),
		_ev(Type.CRITICAL_HIT, "b", {"roll": 3, "table": "hull", "result_id": "rudder"}),
		_ev(Type.GUNS_DISMOUNTED, "b", {"amount": 1, "side": 0}),
		_ev(Type.FIRE, "c", _fire_data(), "d"),
		_ev(Type.DAMAGE, "d", {"hull": 1}),
	]
	var steps := ResolutionSteps.build(evs, 0, SHIPS)
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].events.size(), 4)
	assert_eq(steps[0].kind, "gunfire")
	assert_eq(steps[0].ship_id, "a")
	assert_eq(steps[0].target_id, "b")
	assert_eq(steps[0].first_index, 0)
	assert_eq(steps[0].last_index, 3)
	assert_eq(steps[1].first_index, 4)
	assert_eq(steps[1].events.size(), 2)
	assert_eq(steps[0].dice, [{"sides": 6, "values": [4]}])
	assert_eq(steps[0].outcome_lines.size(), 4)


func test_follower_of_another_pair_is_not_folded() -> void:
	var evs: Array = [
		_ev(Type.FIRE, "a", _fire_data(), "b"),
		_ev(Type.DAMAGE, "d", {"hull": 1}),
		_ev(Type.DAMAGE, "b", {"hull": 1}, "", 5),
	]
	var steps := ResolutionSteps.build(evs, 0, SHIPS)
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].events.size(), 1, "another ship's damage and another phase's do not fold")


func test_hold_fire_and_signal_are_not_steps() -> void:
	var evs: Array = [
		_ev(Type.HOLD_FIRE, "a"),
		_ev(Type.SIGNAL, "a", {"from_player": 0, "words": ["ENGAGE"]}),
		_ev(Type.MORALE_CHECK, "a", {"roll": 7, "rating": 4, "passed": true}, "", 7),
	]
	var steps := ResolutionSteps.build(evs, 0, SHIPS)
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].kind, "morale")
	assert_eq(steps[0].first_index, 2)


func test_morale_dice_and_outcome() -> void:
	var ev := _ev(Type.MORALE_CHECK, "a", {"roll": 7, "rating": 4, "passed": false}, "", 7)
	var steps := ResolutionSteps.build([ev], 0, SHIPS)
	assert_eq(steps[0].dice, [{"sides": 10, "values": [7]}])
	var own := PhaseEvents.PhaseEvent.from_dict(ev)
	var wording := own.to_text(CombatLogPanel.event_names(own, SHIPS))
	assert_true(steps[0].outcome_lines[0].contains(wording))
	assert_true(steps[0].title.contains("Alpha"))


func test_fire_modifiers_copied() -> void:
	var steps := ResolutionSteps.build([_ev(Type.FIRE, "a", _fire_data(), "b")], 0, SHIPS)
	assert_eq(steps[0].modifiers, [
		{"label": PhaseEvents.modifier_label("crew_quality"), "value": 2},
		{"label": PhaseEvents.modifier_label("initial_broadside"), "value": 3},
	])
	assert_eq(steps[0].final_text, "Gunfire number 31")


func test_build_from_index() -> void:
	var evs: Array = [
		_ev(Type.MORALE_CHECK, "a", {"roll": 7, "rating": 4, "passed": true}, "", 7),
		_ev(Type.MORALE_CHECK, "b", {"roll": 2, "rating": 4, "passed": false}, "", 7),
	]
	var steps := ResolutionSteps.build(evs, 1, SHIPS)
	assert_eq(steps.size(), 1)
	assert_eq(steps[0].ship_id, "b")
	assert_eq(steps[0].first_index, 1)
	assert_eq(steps[0].last_index, 1)


func test_drift_step() -> void:
	# DriftResolver: the ship drifts when roll + modifier >= needed (8.A.2).
	var data := {"roll": 2, "needed": 4, "modifier": 1, "drifted": false, "from": {"q": 1, "r": 2}}
	var steps := ResolutionSteps.build([_ev(Type.DRIFT, "a", data, "", 5)], 0, SHIPS)
	assert_eq(steps[0].kind, "drift")
	assert_eq(steps[0].dice, [{"sides": 10, "values": [2]}])
	assert_eq(steps[0].modifiers, [{"label": "modifier", "value": 1}])
	assert_eq(steps[0].final_text, "Drifts on 4 or more")


func test_grapple_step() -> void:
	var data := {"roll": 2, "modifiers": [{"name": "skill", "value": -1}], "modifier": -1,
		"total": 1, "needed": 2, "success": true}
	var steps := ResolutionSteps.build([_ev(Type.GRAPPLE, "a", data, "b", 6)], 0, SHIPS)
	assert_eq(steps[0].kind, "grapple")
	assert_eq(steps[0].dice, [{"sides": 10, "values": [2]}])
	assert_eq(steps[0].modifiers, [{"label": PhaseEvents.modifier_label("skill"), "value": -1}])
	assert_eq(steps[0].final_text, "Total 1, needs 2 or less")


func test_lapsed_tow_has_no_dice() -> void:
	var steps := ResolutionSteps.build([_ev(Type.TOW_BEGUN, "a", {"success": false, "lapsed": "gone"}, "b", 6)], 0, SHIPS)
	assert_eq(steps[0].kind, "tow")
	assert_eq(steps[0].dice, [])


func test_two_d6_rolls_keep_their_count() -> void:
	var steps := ResolutionSteps.build([_ev(Type.EXPLOSION_CHECK, "a", {"roll": 7, "needed": 3, "explodes": false}, "", 6)], 0, SHIPS)
	assert_eq(steps[0].dice, [{"sides": 6, "values": [7], "count": 2}])


func test_hidden_boxes_stay_hidden() -> void:
	# What PlayerView gives for an enemy: no box fields, sections lost instead.
	var fire := _fire_data()
	for key in ["rigging", "hull", "crew"]:
		fire.erase(key)
	var evs: Array = [
		_ev(Type.FIRE, "a", fire, "b"),
		_ev(Type.DAMAGE, "b", {"cause": "other", "sections_lost": 1, "marine_section_lost": false}),
	]
	var steps := ResolutionSteps.build(evs, 0, SHIPS)
	assert_eq(steps.size(), 1)
	for line in steps[0].outcome_lines:
		assert_false(line.contains("no damage"), line)
		assert_false(line.contains("hull box"), line)
	assert_true(steps[0].outcome_lines[1].contains("1 section"))


func test_every_type_is_classified_exactly_once() -> void:
	for type in PhaseEvents.Type.values():
		var places := 0
		places += 1 if ResolutionSteps.LEADS.has(type) else 0
		places += 1 if ResolutionSteps.FOLLOWS.has(type) else 0
		places += 1 if ResolutionSteps.SKIPPED.has(type) else 0
		assert_eq(places, 1, "%s is in %d lists" % [PhaseEvents.Type.find_key(type), places])


# --- Limited information, through PlayerView itself ------------------------------

class FakeGame extends Node:
	var mine := ""

	func commands(_player_id: int, ship_id: String) -> bool:
		return ship_id == mine


## The event dict as PlayerView gives it to a player who commands only `mine`.
func _seen(type: Type, ship: String, data: Dictionary, target: String, mine: String) -> Dictionary:
	var game: FakeGame = autofree(FakeGame.new())
	game.mine = mine
	var view := PlayerView.new(game)
	var ev := PhaseEvents.PhaseEvent.new(type, 4, ship, data, target)
	var d := ev.to_dict()
	view._hide_boxes(0, ev, d)
	return d


func _all_text(steps: Array[ResolutionStep]) -> String:
	var parts := PackedStringArray()
	for step in steps:
		parts.append(step.title)
		parts.append(step.final_text)
		parts.append("\n".join(step.outcome_lines))
	return "\n".join(parts)


func test_enemy_marine_fire_hides_boxes_but_not_the_column() -> void:
	var data := {"boxes": 7, "column": "7-8", "modifiers": [{"name": "grappled_or_fouled", "value": -1}],
		"modifier": -1, "d6": 5, "total": 4, "crew": 2}
	var d := _seen(Type.MARINE_FIRE, "b", data, "a", "a")  # reader commands the target a
	assert_false(d["data"].has("boxes"))
	var text := _all_text(ResolutionSteps.build([d], 0, SHIPS))
	assert_false(text.contains("0 box"), text)
	assert_false(text.contains("7 box"), text)
	assert_true(text.contains("column 7-8"), text)
	assert_true(text.contains("2 crew boxes"), text)  # the target is hers: crew stays


func test_marine_fire_on_an_enemy_hides_the_crew_result() -> void:
	var data := {"boxes": 7, "column": "7-8", "modifiers": [], "modifier": 0, "d6": 5, "total": 5, "crew": 2}
	var d := _seen(Type.MARINE_FIRE, "a", data, "b", "a")  # reader commands the firer a
	assert_false(d["data"].has("crew"))
	var text := _all_text(ResolutionSteps.build([d], 0, SHIPS))
	assert_false(text.contains("no effect"), text)
	assert_false(text.contains("crew box"), text)
	assert_true(text.contains("7 boxes"), text)


func test_marine_fire_with_both_hidden() -> void:
	var data := {"boxes": 7, "column": "7-8", "modifiers": [], "modifier": 0, "d6": 5, "total": 5, "crew": 2}
	var d := _seen(Type.MARINE_FIRE, "a", data, "b", "c")
	var text := _all_text(ResolutionSteps.build([d], 0, SHIPS))
	assert_false(text.contains("box"), text)
	assert_true(text.contains("column 7-8"), text)


func test_enemy_blast_hides_its_hits() -> void:
	var data := {"range": 1, "mgn": 10, "d6": 3, "fgn": 13, "rigging": 2, "hull": 1, "crew": 3}
	var d := _seen(Type.BLAST, "a", data, "b", "a")  # target b is not hers
	assert_false(d["data"].has("hull"))
	var steps := ResolutionSteps.build([d], 0, SHIPS)
	assert_eq(steps[0].dice, [{"sides": 6, "values": [3]}])
	assert_false(_all_text(steps).contains("no damage"))
	assert_false(_all_text(steps).contains("hull"))


func test_enemy_boarding_round_shows_totals_without_box_counts() -> void:
	var side := {"sections": [0], "sailors": 6, "marines": 4, "cq": "C", "tbcf": 62, "odds": 0, "other": 0,
		"drm": -2, "roll": 9, "total": 7, "pct": 40, "inflicts": 3, "lost_sailors": 1, "lost_marines": 0, "below": 0}
	var data := {"action": "x", "round": 1, "attacker": side.duplicate(), "defender": side.duplicate()}
	var d := _seen(Type.BOARDING_ROUND, "a", data, "b", "c")  # neither ship hers
	assert_false(d["data"]["attacker"].has("tbcf"))
	var steps := ResolutionSteps.build([d], 0, SHIPS)
	assert_eq(steps[0].dice.size(), 2)
	var text := _all_text(steps)
	assert_false(text.contains("0 v 0"), text)
	assert_false(text.contains("62"), text)
	assert_true(text.contains("Attacker 7, defender 7"), text)


func test_enemy_prize_crew_and_recapture_never_invent_counts() -> void:
	var prize := _seen(Type.PRIZE_CREW, "b", {"sailors": 5, "marines": 2, "cq": "C", "mr": 4,
		"crew_count": [1], "marine_count": 1}, "a", "c")
	var rec := _seen(Type.RECAPTURED, "b", {"cause": "rose", "original_boxes": 6, "prize_boxes": 3,
		"cq": "C", "mr": 4}, "", "c")
	var text := _all_text(ResolutionSteps.build([prize, rec], 0, SHIPS))
	assert_true(prize["data"].get("sailors") == null)
	assert_false(text.contains("crew of 0"), text)
	assert_false(text.contains("?"), text)


func test_a_drift_group_is_one_step() -> void:
	var base := {"roll": 3, "needed": 5, "modifier": 0, "drifted": false, "from": {"q": 1, "r": 1}}
	var other := base.duplicate()
	other["from"] = {"q": 2, "r": 1}
	var lone := base.duplicate()
	lone["roll"] = 7
	var evs: Array = [_ev(Type.DRIFT, "a", base, "", 5), _ev(Type.DRIFT, "b", other, "", 5),
		_ev(Type.DRIFT, "c", lone, "", 5)]
	var steps := ResolutionSteps.build(evs, 0, SHIPS)
	assert_eq(steps.size(), 2)
	assert_eq(steps[0].ship_id, "a")
	assert_eq(steps[0].events.size(), 2)
	assert_eq(steps[0].last_index, 1)
	assert_eq(steps[0].dice, [{"sides": 10, "values": [3]}])
	assert_eq(steps[1].first_index, 2)


# --- prompt steps -------------------------------------------------------------

func test_bear_off_prompt_step() -> void:
	var situation := MovementTypes.BearOffSituation.new()
	situation.ship_id = "a"
	situation.blocker_id = "b"
	situation.segment = 2
	situation.eligible.assign(["port"])
	situation.number = 5
	situation.drm = 1
	situation.chance = 0.6
	var step := ResolutionSteps.bear_off_prompt(situation, SHIPS)
	assert_eq(step.kind, "prompt_bear_off")
	assert_eq(step.phase, TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION)
	assert_true(step.title.contains("Alpha") and step.title.contains("Bravo"), step.title)
	assert_eq(step.prompt.get("ship_id"), "a")
	assert_eq(step.ship_id, "a")
	assert_eq(step.target_id, "b")
	assert_eq(step.dice, [], "no roll has been made yet")
	assert_true(Array(step.outcome_lines).has(BearOffPanel.odds_text(situation)), "the chance as text")


func test_maintenance_prompt_step() -> void:
	var grapple := [{"ship_id": "a", "target_id": "b", "needed": 2, "percent": 30}]
	for step_name in ["grapple", "ungrapple"]:
		var step := ResolutionSteps.maintenance_prompt(step_name, grapple, SHIPS)
		assert_eq(step.kind, "prompt_maintenance")
		assert_eq(step.phase, TurnPhaseController.GamePhase.STATUS_ADJUSTMENT)
		assert_true(step.title.begins_with(MaintenanceOrdersPanel.title(step_name)), step.title)
		assert_eq(step.ship_id, "a")
		assert_eq(step.target_id, "b")
		assert_eq(step.prompt.get("step"), step_name)
		assert_eq(Array(step.outcome_lines), [MaintenanceOrdersPanel.intro_text(step_name)])
	var prize := [{"action_id": 3, "prize_id": "b", "captor_id": "a", "minimum": 2, "maximum": 4}]
	var p := ResolutionSteps.maintenance_prompt("prize_size", prize, SHIPS)
	assert_eq(p.title, "%s: Alpha" % MaintenanceOrdersPanel.title("prize_size"))
	assert_eq(p.ship_id, "a", "the captor")
	assert_eq(p.target_id, "b", "her prize")
	var two := grapple + [{"ship_id": "c", "target_id": "d", "needed": 2, "percent": 30}]
	assert_eq(ResolutionSteps.maintenance_prompt("grapple", two, SHIPS).title,
		MaintenanceOrdersPanel.title("grapple"), "several ships: the title names none")
