class_name PlanChecklist
extends RefCounted
## The per-ship Plan / Done checklist of board planning. View state only: it never reaches the
## server (End Planning is still `player_submit_plan`). A ship that cannot plot starts, and stays,
## Locked; a ship still in Plan at End Planning sails her stored default course.

signal changed()

const PLAN := "plan"
const DONE := "done"
const LOCKED := "locked"

var _order: Array[String] = []
var _states: Dictionary = {}  # ship_id -> PLAN | DONE | LOCKED


## Starts the turn: every id is Plan when `movable[id]`, else Locked.
func begin(ship_ids: Array, movable: Dictionary) -> void:
	_order.clear()
	_states.clear()
	for id in ship_ids:
		var sid := str(id)
		_order.append(sid)
		_states[sid] = PLAN if movable.get(sid, false) else LOCKED
	changed.emit()


## "plan", "done", "locked", or "" for a ship not in the checklist.
func state(ship_id: String) -> String:
	return _states.get(ship_id, "")


## Marks a ship Done (true) or back in Plan (false). Locked and unknown ships are left alone.
func set_done(ship_id: String, done: bool) -> void:
	var cur := state(ship_id)
	if cur == "" or cur == LOCKED:
		return
	var want := DONE if done else PLAN
	if cur == want:
		return
	_states[ship_id] = want
	changed.emit()


## Re-reads which ships can plot: a ship that became movable (a rally) turns Plan, one that
## stopped being movable turns Locked; the others keep their state.
func refresh_movable(movable: Dictionary) -> void:
	var any := false
	for id in _order:
		var cur: String = _states[id]
		var can: bool = movable.get(id, false)
		if can and cur == LOCKED:
			_states[id] = PLAN
			any = true
		elif not can and cur != LOCKED:
			_states[id] = LOCKED
			any = true
	if any:
		changed.emit()


## The next ship still in Plan after `after_id`, wrapping round; "" when none is. With
## `after_id` unknown the search starts at the first ship.
func next_in_plan(after_id: String) -> String:
	var n := _order.size()
	if n == 0:
		return ""
	var start := _order.find(after_id)
	for step in range(1, n + 1):
		var id := _order[(start + step) % n]
		if _states[id] == PLAN:
			return id
	return ""


func plan_count() -> int:
	var count := 0
	for id in _order:
		if _states[id] == PLAN:
			count += 1
	return count


func clear() -> void:
	if _order.is_empty():
		return
	_order.clear()
	_states.clear()
	changed.emit()
