class_name ResolutionReplay
extends Node
## The resolution replay's view state: the queue of steps, the one on screen, and whether this
## player is still replaying (resolution panel spec, "Replay timing"). View only: it never talks to
## the server. `GameController` feeds it (`start`, `append`, `push_prompt`) and acts on its signals.
##
## A step stays on screen until Next (or the prompt's answer). Next past the last step leaves the
## replay waiting: steps appended then come up at once. The replay drains (signal `drained`, then the
## `finish_when_drained` callback, once) when it is waiting with nothing left and finishing was asked
## for. Resolve all shows every queued step instantly up to a prompt, which it shows and stops at: a
## prompt is never skipped.

signal step_shown(step: ResolutionStep, index: int)
signal drained()

## True from `start` until the replay drains or is cancelled: the "this player is still resolving"
## state a later roster reads.
var resolving: bool = false

## "combat" | "post_combat" | "bear_off".
var kind: String = ""
var phases: Array[int] = []

## The panel that shows the steps (a `ResolutionPanel`, or a stand-in in tests): `show_step`,
## `set_answer_section` and the `next_pressed` / `resolve_all_pressed` signals.
var _panel: Object = null
var _steps: Array[ResolutionStep] = []
## step index -> the answer Control of a prompt step, until the panel takes it.
var _answers: Dictionary = {}
var _index: int = -1
## The player asked for the step after `_index` and there was none yet.
var _waiting: bool = false
var _running: bool = false
var _resolving_all: bool = false
var _finish_callback: Callable = Callable()
var _finish_requested: bool = false

const PHASE_LABELS := {
	TurnPhaseController.GamePhase.MOVEMENT_RESOLUTION: "Movement",
	TurnPhaseController.GamePhase.COMBAT_RESOLUTION: "Combat",
	TurnPhaseController.GamePhase.DRIFT_CALCULATION: "Drift",
	TurnPhaseController.GamePhase.STATUS_ADJUSTMENT: "Status",
	TurnPhaseController.GamePhase.MORALE_CHECK: "Morale",
	TurnPhaseController.GamePhase.MESSAGE_DELIVERY: "Messages",
}


## The panel the steps are drawn on; its Next and Resolve all buttons drive the replay.
func attach_panel(panel: Object) -> void:
	if _panel == panel:
		return
	_disconnect_panel()
	_panel = panel
	if _panel != null:
		_panel.connect("next_pressed", next)
		_panel.connect("resolve_all_pressed", resolve_all)


## A new replay of `phases` begins with an empty queue: the first step appended comes up at once.
func start(replay_kind: String, replay_phases: Array[int]) -> void:
	_drop_answers()
	kind = replay_kind
	phases = replay_phases.duplicate()
	_steps.clear()
	_index = -1
	_waiting = true
	_running = true
	resolving = true
	_resolving_all = false
	_finish_callback = Callable()
	_finish_requested = false


## Queues `steps`; when the replay is waiting, the first of them comes up now.
func append(new_steps: Array[ResolutionStep]) -> void:
	if not _running:
		return
	_steps.append_array(new_steps)
	if _waiting:
		_advance()


## Queues a step that asks the player for something; `answer` (its controls) replaces Next and
## Resolve all while it is shown. The replay holds there until `prompt_answered`.
func push_prompt(step: ResolutionStep, answer: Control) -> void:
	if not _running:
		if answer != null and answer.get_parent() == null:
			answer.free()
		return
	_steps.append(step)
	if answer != null:
		_answers[_steps.size() - 1] = answer
	if _waiting:
		_advance()


## The prompt on screen was answered: its controls go and the replay moves on.
func prompt_answered() -> void:
	if not _running or not _showing_prompt():
		return
	if _panel != null:
		_panel.call("set_answer_section", null)
	_advance()


## `callback` runs (once, after `drained`) when the replay has shown every step and the player has
## moved past the last; at once if that is already so.
func finish_when_drained(callback: Callable) -> void:
	if not _running:
		return
	_finish_callback = callback
	_finish_requested = true
	if _waiting:
		_drain()


## The replay is dropped: no signal, no callback.
func cancel() -> void:
	_drop_answers()
	if _running and _showing_prompt() and _panel != null and is_instance_valid(_panel):
		_panel.call("set_answer_section", null)
	_running = false
	resolving = false
	_resolving_all = false
	_waiting = false
	_steps.clear()
	_index = -1
	_finish_callback = Callable()
	_finish_requested = false


func is_running() -> bool:
	return _running


## The index of the step on screen (-1 before the first).
func current_index() -> int:
	return _index


## The step on screen, or null.
func current_step() -> ResolutionStep:
	return _steps[_index] if _index >= 0 and _index < _steps.size() else null


func steps() -> Array[ResolutionStep]:
	return _steps


## True while Resolve all is showing steps (each lands instantly; the view does not move the camera).
func is_resolving_all() -> bool:
	return _resolving_all


## The next step (Next ▸). Ignored while a prompt is on screen.
func next() -> void:
	if not _running or _waiting or _showing_prompt():
		return
	_advance()


## Shows every queued step at once up to a prompt, and stops on it; past the last step the replay
## waits (or drains when finishing was asked for).
func resolve_all() -> void:
	if not _running or _showing_prompt():
		return
	_resolving_all = true
	while _running and not _waiting and not _showing_prompt():
		_advance()
	_resolving_all = false


## The phase heading for a step: "Combat", "Drift"...
static func phase_label(phase: int) -> String:
	return PHASE_LABELS.get(phase, "Resolution")


func _advance() -> void:
	if _index + 1 >= _steps.size():
		_waiting = true
		if _finish_requested:
			_drain()
		return
	_waiting = false
	_index += 1
	var step := _steps[_index]
	if _panel != null:
		_panel.call("show_step", step, _index, _steps.size(), phase_label(step.phase), _resolving_all)
		if _answers.has(_index):
			_panel.call("set_answer_section", _answers[_index])
			_answers.erase(_index)
	step_shown.emit(step, _index)


func _showing_prompt() -> bool:
	var step := current_step()
	return step != null and not _waiting and not step.prompt.is_empty()


func _drain() -> void:
	var callback := _finish_callback
	# Cleared before anyone hears of it: the callback may start the next replay on this node.
	_running = false
	resolving = false
	_waiting = false
	_resolving_all = false
	_finish_callback = Callable()
	_finish_requested = false
	drained.emit()
	if callback.is_valid():
		callback.call()


## Answer controls the panel never took are freed here (the panel owns the ones it shows).
func _drop_answers() -> void:
	for i in _answers:
		var c: Control = _answers[i]
		if is_instance_valid(c) and c.get_parent() == null:
			c.free()
	_answers.clear()


func _disconnect_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		_panel = null
		return
	if _panel.is_connected("next_pressed", next):
		_panel.disconnect("next_pressed", next)
	if _panel.is_connected("resolve_all_pressed", resolve_all):
		_panel.disconnect("resolve_all_pressed", resolve_all)
	_panel = null


func _exit_tree() -> void:
	_drop_answers()
