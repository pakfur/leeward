class_name ScriptedDice
extends Dice
## ScriptedDice - Dice returning queued values, for deterministic tests.
## d6()/d10() pop one value; two_d6()/two_d10() pop two and add them.

var _queue: Array = []

func _init() -> void:
	super._init(RandomNumberGenerator.new())

func queue(values: Array) -> void:
	_queue.append_array(values)

func remaining() -> int:
	return _queue.size()

func _next() -> int:
	if _queue.is_empty():
		push_error("ScriptedDice: roll requested but queue is empty")
		return 0
	return _queue.pop_front()

func d6() -> int:
	return _next()

func d10() -> int:
	return _next()

func two_d6() -> int:
	return _next() + _next()

func two_d10() -> int:
	return _next() + _next()
