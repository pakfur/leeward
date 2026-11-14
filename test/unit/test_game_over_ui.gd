extends GutTest
## Tests for the pure presentation helpers of the game-over panel.

const GameOverUI = preload("res://scripts/ui/game_over_panel.gd")


func _ship(id: String, player: int, struck: bool) -> ShipState:
	var state := ShipState.new()
	state.ship = Ship.from_dict({
		"ship_id": id, "player_id": player, "ship_name": "HMS Test", "ship_type": "frigate_38",
		"name": "38-gun Frigate", "maneuverability": "C", "speed_type": "F/F",
	})
	state.status = ShipState.Status.STRUCK if struck else ShipState.Status.ACTIVE
	return state


func test_headline_by_winner() -> void:
	assert_eq(GameOverUI.headline(0), "Victory")
	assert_eq(GameOverUI.headline(1), "Defeat")
	assert_eq(GameOverUI.headline(-1), "Draw")


func test_points_text_has_one_decimal() -> void:
	assert_eq(GameOverUI.points_text(0.0), "0.0")
	assert_eq(GameOverUI.points_text(12.0), "12.0")
	assert_eq(GameOverUI.points_text(7.26), "7.3")
	assert_eq(GameOverUI.points_text(3.04), "3.0")


func test_struck_text() -> void:
	assert_eq(GameOverUI.struck_text(1, 3), "1 of 3")
	assert_eq(GameOverUI.struck_text(0, 0), "0 of 0")


func test_struck_counts_per_side() -> void:
	var ships := [_ship("a", 0, false), _ship("b", 0, true), _ship("c", 1, true)]
	assert_eq(GameOverUI.struck_counts(ships, 0), {"struck": 1, "total": 2})
	assert_eq(GameOverUI.struck_counts(ships, 1), {"struck": 1, "total": 1})
	assert_eq(GameOverUI.struck_counts(ships, 2), {"struck": 0, "total": 0})


func test_reason_all_enemy_struck() -> void:
	assert_eq(GameOverUI.reason_text("all struck", {"struck": 0, "total": 2}, {"struck": 3, "total": 3}),
		"All enemy ships have struck")


func test_reason_all_own_struck() -> void:
	assert_eq(GameOverUI.reason_text("all struck", {"struck": 2, "total": 2}, {"struck": 1, "total": 3}),
		"All your ships have struck")


func test_reason_both_sides_struck() -> void:
	assert_eq(GameOverUI.reason_text("all struck", {"struck": 2, "total": 2}, {"struck": 3, "total": 3}),
		"Both sides have struck")


func test_reason_turn_limit() -> void:
	assert_eq(GameOverUI.reason_text("turn limit", {"struck": 0, "total": 2}, {"struck": 1, "total": 3}),
		"Turn limit reached")


func test_summary_collects_every_displayed_value() -> void:
	var ships := [_ship("a", 0, false), _ship("b", 0, true), _ship("c", 1, true), _ship("d", 1, true)]
	var result := {"winner": 0, "reason": "all struck", "points": {0: 18.5, 1: 2.0}, "turn": 7}
	var summary: Dictionary = GameOverUI.summary(result, ships)
	assert_eq(summary["headline"], "Victory")
	assert_eq(summary["reason"], "All enemy ships have struck")
	assert_eq(summary["turn"], "Game ended on turn 7")
	assert_eq(summary["player_points"], "18.5")
	assert_eq(summary["enemy_points"], "2.0")
	assert_eq(summary["player_struck"], "1 of 2")
	assert_eq(summary["enemy_struck"], "2 of 2")
	assert_eq(summary["points_note"],
		"Points: full value for each enemy ship struck, part value for sections destroyed.")


func test_summary_tolerates_missing_fields() -> void:
	var summary: Dictionary = GameOverUI.summary({"winner": -1}, [])
	assert_eq(summary["headline"], "Draw")
	assert_eq(summary["player_points"], "0.0")
	assert_eq(summary["player_struck"], "0 of 0")
