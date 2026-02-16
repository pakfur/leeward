extends GutTest
## Tests for Trace autoload singleton.

var trace: Node


func before_all() -> void:
	trace = Trace


func before_each() -> void:
	trace.clear_all()


## Basic Logging

func test_trace_log_creates_category() -> void:
	trace.trace_log("TestCat", "hello")
	assert_true(trace.get_categories().has("TestCat"))


func test_trace_log_stores_message() -> void:
	trace.trace_log("TestCat", "hello world")
	var entries = trace.get_traces("TestCat")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].message, "hello world")


func test_trace_log_with_context() -> void:
	trace.trace_log("TestCat", "msg", {"key": "val"})
	var entries = trace.get_traces("TestCat")
	assert_eq(entries.size(), 1)
	assert_ne(entries[0].context, "")


func test_trace_log_without_context() -> void:
	trace.trace_log("TestCat", "msg")
	var entries = trace.get_traces("TestCat")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].context, "")


func test_trace_log_has_timestamp() -> void:
	trace.trace_log("TestCat", "msg")
	var entries = trace.get_traces("TestCat")
	assert_ne(entries[0].timestamp, "")


func test_trace_log_with_string_context() -> void:
	trace.trace_log("TestCat", "msg", "some string context")
	var entries = trace.get_traces("TestCat")
	assert_eq(entries[0].context, "some string context")


## Categories

func test_categories_ordered_by_insertion() -> void:
	trace.trace_log("Alpha", "a")
	trace.trace_log("Beta", "b")
	trace.trace_log("Gamma", "c")
	var cats = trace.get_categories()
	assert_eq(cats.size(), 3)
	assert_eq(cats[0], "Alpha")
	assert_eq(cats[1], "Beta")
	assert_eq(cats[2], "Gamma")


func test_duplicate_category_not_added_twice() -> void:
	trace.trace_log("Cat", "a")
	trace.trace_log("Cat", "b")
	assert_eq(trace.get_categories().size(), 1)


func test_multiple_messages_same_category() -> void:
	trace.trace_log("Cat", "first")
	trace.trace_log("Cat", "second")
	var entries = trace.get_traces("Cat")
	assert_eq(entries.size(), 2)
	assert_eq(entries[0].message, "first")
	assert_eq(entries[1].message, "second")


## Unknown Category

func test_get_traces_unknown_category_returns_empty() -> void:
	var entries = trace.get_traces("nonexistent")
	assert_eq(entries.size(), 0)


## Clear

func test_clear_category() -> void:
	trace.trace_log("Cat", "msg")
	trace.clear_category("Cat")
	assert_eq(trace.get_traces("Cat").size(), 0)
	# Category still exists in list
	assert_true(trace.get_categories().has("Cat"))


func test_clear_all() -> void:
	trace.trace_log("A", "1")
	trace.trace_log("B", "2")
	trace.clear_all()
	assert_eq(trace.get_categories().size(), 0)
	assert_eq(trace.get_traces("A").size(), 0)
	assert_eq(trace.get_traces("B").size(), 0)


## Signal

func test_trace_added_signal_emitted() -> void:
	watch_signals(trace)
	trace.trace_log("SigCat", "test")
	assert_signal_emitted(trace, "trace_added")
	assert_signal_emitted_with_parameters(trace, "trace_added", ["SigCat"])


func test_trace_added_signal_fires_on_each_log() -> void:
	watch_signals(trace)
	trace.trace_log("Cat", "a")
	trace.trace_log("Cat", "b")
	trace.trace_log("Other", "c")
	assert_signal_emit_count(trace, "trace_added", 3)


## Edge Cases

func test_clear_nonexistent_category_no_error() -> void:
	trace.clear_category("never_existed")
	assert_eq(trace.get_categories().size(), 0)
