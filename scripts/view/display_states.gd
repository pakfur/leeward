class_name DisplayStates
extends RefCounted
## View-only: detached ship copies, so the map can show each ship as she was at the replay step on
## screen (resolution panel spec, "Displayed state in step with the replay"). The copies are
## never written to the server; the live states are never touched.

## phase -> {ship_id: ShipState}: the state before that phase, for the captured turn.
var _copies: Dictionary = {}
var _turn: int = -1
## ship_id -> ShipState currently shown (a missing id or null = live).
var _shown: Dictionary = {}
var _active: bool = false


## Stores a detached copy of every ship as the state before `phase`. A second capture of the same
## (turn, phase) is ignored; a new turn drops the older turn's copies.
func capture(phase: int, turn: int, ships: Array) -> void:
	if turn != _turn:
		_copies.clear()
		_shown.clear()
		_turn = turn
	if _copies.has(phase):
		return
	var by_id := {}
	for s in ships:
		var state := s as ShipState
		if state == null or state.ship == null:
			continue
		by_id[state.ship_id] = ShipState.deserialize(state.serialize())
	_copies[phase] = by_id


## A replay of these phases starts: every ship shows its copy from before the first listed phase.
func begin(phases: Array[int]) -> void:
	_active = true
	_shown.clear()
	if not phases.is_empty():
		_show_before(phases[0])


## After showing `steps[index]`: each ship whose last step in `step.phase` is at or before `index`
## switches to her copy from before the next captured phase (live when there is none).
func step_shown(step: ResolutionStep, steps: Array[ResolutionStep], index: int) -> void:
	if not _active or step == null:
		return
	var phase := step.phase
	var last := {}
	for i in steps.size():
		var s := steps[i]
		if s.phase != phase:
			continue
		for id in _ships_of(s):
			last[id] = i
	var next_phase := _next_captured_phase(phase)
	for id in last:
		if int(last[id]) <= index:
			_shown[id] = _copy(next_phase, id)


## The replay moved into `phase`: every ship shows her copy from before it.
func phase_reached(phase: int) -> void:
	if _active:
		_show_before(phase)


## The copy to draw, or null = draw live.
func state_for(ship_id: String) -> ShipState:
	if not _active:
		return null
	return _shown.get(ship_id, null) as ShipState


## Everything live again.
func end() -> void:
	_active = false
	_shown.clear()


func active() -> bool:
	return _active


## A new game.
func clear() -> void:
	end()
	_copies.clear()
	_turn = -1


func _show_before(phase: int) -> void:
	_shown.clear()
	var by_id: Dictionary = _copies.get(phase, {})
	for id in by_id:
		_shown[id] = by_id[id]


func _next_captured_phase(phase: int) -> int:
	var best := -1
	for p in _copies:
		if int(p) > phase and (best < 0 or int(p) < best):
			best = int(p)
	return best


func _copy(phase: int, id: String) -> ShipState:
	if phase < 0:
		return null
	return (_copies[phase] as Dictionary).get(id, null) as ShipState


func _ships_of(step: ResolutionStep) -> PackedStringArray:
	var ids := PackedStringArray()
	for id in [step.ship_id, step.target_id]:
		if id != "" and not ids.has(id):
			ids.append(id)
	for ev in step.events:
		for id in ev.ship_ids():
			if not ids.has(id):
				ids.append(id)
	return ids
