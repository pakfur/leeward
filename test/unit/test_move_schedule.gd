extends GutTest

func _steps(a: int, b: int) -> Dictionary:
	var sa: Array = []
	sa.resize(a)
	var sb: Array = []
	sb.resize(b)
	return {"a": sa, "b": sb}

func test_times_are_the_distinct_step_times_in_order() -> void:
	var s := MoveSchedule.new({"a": 8, "b": 3})
	var expected: Array[Vector2i] = [Vector2i(1, 8), Vector2i(1, 4), Vector2i(1, 3), Vector2i(3, 8), Vector2i(1, 2), Vector2i(5, 8), Vector2i(2, 3), Vector2i(3, 4), Vector2i(7, 8), Vector2i(1, 1)]
	assert_eq(s.times, expected)

func test_segment_of_and_step_at() -> void:
	var s := MoveSchedule.new({"a": 8, "b": 3})
	assert_eq(s.segment_of("a", 3), 4)
	assert_eq(s.segment_of("b", 1), 6)
	assert_eq(s.segment_of("b", 2), 9)
	assert_eq(s.segment_of("a", 7), 9)
	assert_eq(s.step_at("b", 6), 1)
	assert_eq(s.step_at("b", 5), -1)
	assert_eq(s.step_at("a", 2), -1)

func test_steps_before() -> void:
	var s := MoveSchedule.new({"a": 8, "b": 3})
	assert_eq(s.steps_before("b", 6), 1)
	assert_eq(s.steps_before("b", 7), 2)
	assert_eq(s.steps_before("a", 4), 3)
	assert_eq(s.steps_before("b", 10), 3)

func test_reduce_and_compare() -> void:
	assert_eq(MoveSchedule.reduce(2, 6), Vector2i(1, 3))
	assert_eq(MoveSchedule.compare(Vector2i(1, 3), Vector2i(3, 8)), -1)
	assert_eq(MoveSchedule.compare(Vector2i(2, 3), Vector2i(2, 3)), 0)
	assert_eq(MoveSchedule.compare(MoveSchedule.END, Vector2i(5, 1)), 1)
	assert_eq(MoveSchedule.compare(Vector2i(1, 1), Vector2i(2, 1)), -1)

func test_trailing_steps_follow_every_scheduled_time() -> void:
	var s := MoveSchedule.new({"a": 8, "b": 3})
	assert_eq(s.segment_of("b", 3), 10)
	assert_eq(s.segment_of("b", 4), 11)
	assert_eq(s.time_of(10), Vector2i(2, 1))
	assert_eq(s.time_of(11), Vector2i(3, 1))
	assert_eq(s.segment_count(_steps(8, 5)), 12)
	assert_eq(s.segment_count(_steps(8, 3)), 10)
	assert_eq(MoveSchedule.step_time(4, 3), Vector2i(3, 1))

func test_next_segment() -> void:
	var s := MoveSchedule.new({"a": 8, "b": 3})
	var steps := _steps(8, 3)
	assert_eq(s.next_segment(["b"], 2, steps), 6)
	assert_eq(s.next_segment(["a", "b"], 4, steps), 5)
	assert_eq(s.next_segment(["b"], 9, steps), 10)

func test_equal_plots_keep_step_per_segment() -> void:
	var s := MoveSchedule.new({"x": 4, "y": 4})
	var expected: Array[Vector2i] = [Vector2i(1, 4), Vector2i(1, 2), Vector2i(3, 4), Vector2i(1, 1)]
	assert_eq(s.times, expected)
	for id in ["x", "y"]:
		for j in range(4):
			assert_eq(s.segment_of(id, j), j)

func test_empty_plot_has_no_times() -> void:
	var s := MoveSchedule.new({"z": 0, "a": 2})
	var expected: Array[Vector2i] = [Vector2i(1, 2), Vector2i(1, 1)]
	assert_eq(s.times, expected)
	assert_eq(s.step_at("z", 0), -1)

func test_ma0_turn_is_at_the_end() -> void:
	assert_eq(MoveSchedule.new({"t": 1, "a": 4}).segment_of("t", 0), 3)

func test_front_loaded_mode_is_step_per_segment() -> void:
	var s := MoveSchedule.new({"a": 8, "b": 3}, true)
	assert_eq(s.segment_of("b", 2), 2)
	assert_eq(s.step_at("b", 2), 2)
	assert_eq(s.step_at("b", 5), 5)
	assert_eq(s.steps_before("a", 4), 4)
	assert_eq(s.segment_count(_steps(8, 3)), 8)
