extends Node
## Trace - Global trace logging system for debugging
## Usage: Trace.trace_log("Movement", "Ship moved forward", ship_state)

signal trace_added(category: String)

# Storage: category -> Array of entry Dictionaries
# Each entry: { "timestamp": String, "message": String, "context": String }
var _traces: Dictionary = {}
# Ordered list of categories (insertion order)
var _categories: Array[String] = []


func trace_log(trace_category: String, message: String, context: Variant = null) -> void:
	"""Add a trace message under the given category"""
	if not _traces.has(trace_category):
		_traces[trace_category] = []
		_categories.append(trace_category)

	var entry: Dictionary = {
		"timestamp": Time.get_time_string_from_system(),
		"message": message,
		"context": str(context) if context != null else ""
	}

	_traces[trace_category].append(entry)

	# Print to Godot console for external log capture
	if context != null:
		print("[Trace:%s] %s | %s" % [trace_category, message, str(context)])
	else:
		print("[Trace:%s] %s" % [trace_category, message])

	trace_added.emit(trace_category)


func get_categories() -> Array[String]:
	"""Return ordered list of all categories seen so far"""
	return _categories.duplicate()


func get_traces(category: String) -> Array:
	"""Return all trace entries for a category"""
	if _traces.has(category):
		return _traces[category].duplicate()
	return []


func clear_category(category: String) -> void:
	"""Clear all stored traces for a category (keeps category in dropdown)"""
	if _traces.has(category):
		_traces[category].clear()


func clear_all() -> void:
	"""Clear all traces and categories"""
	_traces.clear()
	_categories.clear()
