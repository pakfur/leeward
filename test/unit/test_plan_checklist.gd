extends GutTest

var _list: PlanChecklist
var _changes := 0


func before_each() -> void:
	_list = PlanChecklist.new()
	_changes = 0
	_list.changed.connect(func(): _changes += 1)


func test_begin_marks_unmovable_locked() -> void:
	_list.begin(["a", "b", "c"], {"a": true, "b": false, "c": true})
	assert_eq(_list.state("a"), "plan")
	assert_eq(_list.state("b"), "locked")
	assert_eq(_list.state("zzz"), "")
	assert_eq(_list.plan_count(), 2)


func test_set_done_ignored_for_locked() -> void:
	_list.begin(["a", "b"], {"a": true, "b": false})
	_changes = 0
	_list.set_done("b", true)
	assert_eq(_list.state("b"), "locked")
	assert_eq(_changes, 0)
	_list.set_done("a", true)
	assert_eq(_list.state("a"), "done")
	_list.set_done("a", false)
	assert_eq(_list.state("a"), "plan")


func test_next_in_plan_cycles_and_skips_done() -> void:
	_list.begin(["a", "b", "c", "d"], {"a": true, "b": true, "c": false, "d": true})
	_list.set_done("b", true)
	assert_eq(_list.next_in_plan("a"), "d")
	assert_eq(_list.next_in_plan("d"), "a")
	assert_eq(_list.next_in_plan(""), "a")
	_list.set_done("a", true)
	_list.set_done("d", true)
	assert_eq(_list.next_in_plan("a"), "")


func test_next_in_plan_returns_self_when_alone() -> void:
	_list.begin(["a", "b"], {"a": true, "b": true})
	_list.set_done("b", true)
	assert_eq(_list.next_in_plan("a"), "a")


func test_refresh_movable_unlocks_rallied_ship() -> void:
	_list.begin(["a", "b"], {"a": true, "b": false})
	_list.set_done("a", true)
	_list.refresh_movable({"a": true, "b": true})
	assert_eq(_list.state("b"), "plan")
	assert_eq(_list.state("a"), "done")
	_list.refresh_movable({"a": false, "b": true})
	assert_eq(_list.state("a"), "locked")


func test_changed_signal() -> void:
	_list.begin(["a"], {"a": true})
	assert_eq(_changes, 1)
	_list.set_done("a", true)
	assert_eq(_changes, 2)
	_list.set_done("a", true)
	assert_eq(_changes, 2, "no change, no signal")
	_list.clear()
	assert_eq(_changes, 3)
	assert_eq(_list.state("a"), "")


func test_badges_ignore_mouse_and_make_one_pill_per_ship() -> void:
	var badges := PlanBadges.new()
	add_child_autofree(badges)
	badges.setup(null)
	assert_eq(badges.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	badges.show_for({
		"a": {"world": Vector3.ZERO, "state": "plan"},
		"b": {"world": Vector3.ZERO, "state": "locked"},
	})
	assert_eq(badges.pill_for("a").text, "PLAN")
	assert_eq(badges.pill_for("b").text, "LOCKED")
	assert_eq(badges.pill_for("a").mouse_filter, Control.MOUSE_FILTER_IGNORE)
	badges.show_for({"a": {"world": Vector3.ZERO, "state": "done"}})
	assert_eq(badges.pill_for("a").text, "✓ DONE")
	badges.clear()
	assert_null(badges.pill_for("a"))


func test_badge_keep_inside_clamps_to_rect() -> void:
	var rect := Rect2(0, 0, 400, 300)
	var p := PlanBadges.keep_inside(Vector2(-50, 500), Vector2(60, 17), rect, 4.0)
	assert_eq(p, Vector2(4, 279))
