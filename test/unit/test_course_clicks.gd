extends GutTest
## CourseClicks.route: which course a map click edits, and how.

func _course(path: Array, next: Array) -> Dictionary:
	var p: Array[Vector2i] = []
	for h in path:
		p.append(h)
	var n: Array[Vector2i] = []
	for h in next:
		n.append(h)
	return {"path_hexes": p, "next_hexes": n, "end_hex": p[p.size() - 1]}


func test_valid_next_hex_extends_that_ship() -> void:
	var courses := {"a": _course([Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(2, 0)])}
	var r := CourseClicks.route(Vector2i(2, 0), courses, "")
	assert_eq(r, {"ship_id": "a", "kind": "extend", "step_index": -1})


func test_course_hex_cuts_at_that_step() -> void:
	var courses := {"a": _course([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], [Vector2i(3, 0)])}
	var r := CourseClicks.route(Vector2i(1, 0), courses, "a")
	assert_eq(r, {"ship_id": "a", "kind": "cut", "step_index": 1})


func test_shared_hex_cuts_at_the_latest_step() -> void:
	var a := Vector2i(1, 0)
	var courses := {"a": _course([a, a], [Vector2i(5, 5)])}
	assert_eq(CourseClicks.route(a, courses, "a")["step_index"], 1)


func test_hex_ahead_after_a_turn_extends() -> void:
	var a := Vector2i(1, 0)
	var d := Vector2i(2, 0)
	var courses := {"a": _course([a, a], [d])}
	assert_eq(CourseClicks.route(d, courses, "a")["kind"], "extend")


func test_course_end_valid_hex_beats_course_hex() -> void:
	var end := Vector2i(1, 0)
	var courses := {"a": _course([Vector2i(0, 0), end], [end])}
	var r := CourseClicks.route(end, courses, "a")
	assert_eq(r["kind"], "extend")


func test_selected_ship_wins_overlap() -> void:
	var h := Vector2i(3, 0)
	var courses := {
		"a": _course([Vector2i(2, 0)], [h]),
		"b": _course([Vector2i(9, 9)], [h]),
	}
	assert_eq(CourseClicks.route(h, courses, "b")["ship_id"], "b")


func test_overlap_without_selection_goes_to_nearest_course_end() -> void:
	var h := Vector2i(3, 0)
	var courses := {
		"a": _course([Vector2i(8, 0)], [h]),
		"b": _course([Vector2i(2, 0)], [h]),
	}
	assert_eq(CourseClicks.route(h, courses, "")["ship_id"], "b")


func test_overlap_tie_goes_to_lower_ship_id() -> void:
	var h := Vector2i(3, 0)
	var courses := {
		"b": _course([Vector2i(2, 0)], [h]),
		"a": _course([Vector2i(4, 0)], [h]),
	}
	assert_eq(CourseClicks.route(h, courses, "")["ship_id"], "a")


func test_unclaimed_hex_routes_nowhere() -> void:
	var courses := {"a": _course([Vector2i(0, 0)], [Vector2i(1, 0)])}
	assert_eq(CourseClicks.route(Vector2i(7, 7), courses, "a"), {})
