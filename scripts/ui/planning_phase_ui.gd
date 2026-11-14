extends Control
## PlanningPhaseUI - Main planning interface displayed in context panel during PLANNING phase

signal ship_selected(ship_id: String)
signal action_toggled(ship_id: String, action_type: String, active: bool)
signal undo_pressed()
signal undo_all_pressed()
signal submit_pressed()
signal cancel_pressed()
signal end_planning_pressed()
signal sail_change_requested(ship_id: String, target: String)  ## target "" cancels the plotted order

const ShipListItem = preload("res://scenes/ui/ship_list_item.tscn")

@onready var title_label: Label = %TitleLabel
@onready var ship_list_container: VBoxContainer = %ShipListContainer
@onready var instructions_label: Label = %InstructionsLabel
@onready var end_planning_button: Button = %EndPlanningButton

# Plotting controls
@onready var plotting_controls: VBoxContainer = %PlottingControls
@onready var ma_label: Label = %MALabel
@onready var path_label: Label = %PathLabel
@onready var undo_button: Button = %UndoButton
@onready var undo_all_button: Button = %UndoAllButton
@onready var submit_button: Button = %SubmitButton
@onready var cancel_button: Button = %CancelButton
@onready var tacking_label: Label = %TackingLabel
@onready var ma_limit_label: Label = %MALimitLabel
@onready var collision_label: Label = %CollisionLabel

# Sail row
@onready var sail_row: VBoxContainer = %SailRow
@onready var sail_current_label: Label = %SailCurrentLabel
@onready var sail_status_label: Label = %SailStatusLabel
@onready var sail_buttons: VBoxContainer = %SailButtons
@onready var sail_hint_label: Label = %SailHintLabel
@onready var sail_error_label: Label = %SailErrorLabel

# Track state
var ship_list_items: Dictionary = {}  # ship_id -> ShipListItem
var selected_ship_id: String = ""
var action_states: Dictionary = {}  # ship_id -> {action_type -> bool}
var submitted_ships: Dictionary = {}  # ship_id -> bool
var total_player_ships: int = 0
var ship_states: Dictionary = {}  # ship_id -> ShipState (read-only references)
var _plot_max: int = 0  # most the plotting ship can spend this turn; fixed for the plot

func _ready() -> void:
	if undo_button:
		undo_button.pressed.connect(func(): undo_pressed.emit())
	if undo_all_button:
		undo_all_button.pressed.connect(func(): undo_all_pressed.emit())
	if submit_button:
		submit_button.pressed.connect(func(): submit_pressed.emit())
	if cancel_button:
		cancel_button.pressed.connect(func(): cancel_pressed.emit())
	if end_planning_button:
		end_planning_button.pressed.connect(func(): end_planning_pressed.emit())
		end_planning_button.disabled = true

func setup_for_player(player_ships: Array[ShipState]) -> void:
	clear_ships()
	total_player_ships = player_ships.size()

	for ship_state in player_ships:
		_add_ship_to_list(ship_state)

	# Select first ship by default
	if not player_ships.is_empty():
		_select_ship(player_ships[0].ship_id)

	_update_end_planning_state()
	_update_instructions()

func clear_ships() -> void:
	for child in ship_list_container.get_children():
		child.queue_free()

	ship_list_items.clear()
	selected_ship_id = ""
	action_states.clear()
	submitted_ships.clear()
	ship_states.clear()
	total_player_ships = 0
	_refresh_sail_row()

func _add_ship_to_list(ship_state: ShipState) -> void:
	var list_item = ShipListItem.instantiate()
	ship_list_container.add_child(list_item)

	# Setup the item with ship data
	list_item.setup(ship_state)

	# Connect signals
	list_item.selected.connect(func(): _on_ship_item_selected(ship_state.ship_id))
	list_item.action_button_pressed.connect(func(action_type): _on_action_button_pressed(ship_state.ship_id, action_type))

	# Track the item
	ship_list_items[ship_state.ship_id] = list_item

	# Initialize action states for this ship
	action_states[ship_state.ship_id] = {
		"movement": false,
		"crew": false,
		"maintenance": false
	}
	# Ships that cannot plot movement (fouled, struck, dismasted) need nothing more from the player
	ship_states[ship_state.ship_id] = ship_state
	submitted_ships[ship_state.ship_id] = not PlanningSailUi.can_plot_movement(ship_state)

func _on_ship_item_selected(ship_id: String) -> void:
	_select_ship(ship_id)
	ship_selected.emit(ship_id)

## Make `ship_id` the ship whose orders are shown and tell the controller (as a card click does).
func select_ship(ship_id: String) -> void:
	if ship_list_items.has(ship_id):
		_on_ship_item_selected(ship_id)

func _select_ship(ship_id: String) -> void:
	# Deselect previous
	if selected_ship_id != "" and ship_list_items.has(selected_ship_id):
		ship_list_items[selected_ship_id].set_selected_state(false)

	# Select new
	selected_ship_id = ship_id
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_selected_state(true)
	sail_error_label.visible = false
	_refresh_sail_row()

func _on_action_button_pressed(ship_id: String, action_type: String) -> void:
	if not action_states.has(ship_id):
		return

	# Toggle the state
	var current_state = action_states[ship_id].get(action_type, false)
	var new_state = not current_state

	# Giving a ship orders selects it in every sense (card, sail section, plotting controls, map):
	# `selected_ship_id` is the one ship whose orders the panel shows. Only one ship plots at a time.
	if new_state:
		if selected_ship_id != ship_id:
			_on_ship_item_selected(ship_id)
		if action_type == "movement":
			for other_id in action_states:
				if other_id != ship_id and action_states[other_id].get("movement", false):
					deactivate_movement_button(other_id)
	action_states[ship_id][action_type] = new_state

	# Update button visual state
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_action_button_state(action_type, new_state)

	# Emit signal
	action_toggled.emit(ship_id, action_type, new_state)

	Trace.trace_log("PlanningUI", "Action '%s' toggled to %s for ship %s" % [action_type, new_state, ship_id])

func get_action_state(ship_id: String, action_type: String) -> bool:
	if action_states.has(ship_id):
		return action_states[ship_id].get(action_type, false)
	return false

func update_ship_display(ship_state: ShipState) -> void:
	if ship_list_items.has(ship_state.ship_id):
		ship_list_items[ship_state.ship_id].setup(ship_state)
	_refresh_sail_row()

func is_ship_submitted(ship_id: String) -> bool:
	return submitted_ships.get(ship_id, false)

func are_all_ships_submitted() -> bool:
	for ship_id in submitted_ships:
		if not submitted_ships[ship_id]:
			return false
	return total_player_ships > 0

func get_submitted_count() -> int:
	var count := 0
	for ship_id in submitted_ships:
		if submitted_ships[ship_id]:
			count += 1
	return count

# ============================================================================
# Sail Row
# ============================================================================

## Shows the server's answer to a sail request: "" refreshes the row, anything else is the reason.
func show_sail_result(reason: String) -> void:
	_refresh_sail_row()
	sail_error_label.text = reason
	sail_error_label.visible = reason != ""

func _request_sail_change(target: String) -> void:
	if selected_ship_id != "":
		sail_change_requested.emit(selected_ship_id, target)

func _refresh_sail_row() -> void:
	if not sail_row:
		return
	var ship: ShipState = ship_states.get(selected_ship_id)
	if ship == null:
		sail_row.visible = false
		return
	var targets: Array = GameState.sail_controller.available_targets(selected_ship_id)
	var costs := {}
	for target in targets:
		costs[target] = GameState.sail_controller.change_cost(selected_ship_id, target)
	var row := PlanningSailUi.sail_row(ship, targets, costs)

	sail_row.visible = row["mode"] != PlanningSailUi.Mode.NONE
	sail_current_label.text = "Now: %s" % row["current"]
	sail_status_label.text = row["text"]
	sail_status_label.visible = row["text"] != ""
	sail_hint_label.text = row["hint"]
	sail_hint_label.visible = row["hint"] != ""
	sail_error_label.visible = false

	# The choices keep their places: the ordered one is shown pressed, pressing it again cancels.
	for child in sail_buttons.get_children():
		sail_buttons.remove_child(child)
		child.queue_free()
	for entry in row["buttons"]:
		var button := Button.new()
		var ordered: bool = entry["pressed"]
		button.text = ("● " if ordered else "○ ") + entry["text"]
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.set_pressed_no_signal(ordered)
		button.tooltip_text = "Press again to cancel this order" if ordered else "Order this sail change"
		var target: String = entry["target"]
		button.pressed.connect(func(): _request_sail_change("" if ordered else target))
		sail_buttons.add_child(button)

# ============================================================================
# Plotting Controls
# ============================================================================

## `remaining_ma_val` is the session's movement at the start of the plot (the most this ship can
## spend this turn, after acceleration limits); `table_ma` is what wind and sail alone would allow.
## `can_submit_val` is the server's answer for the empty path (staying put may be allowed).
func show_plotting_controls(ship_id: String, remaining_ma_val: int, table_ma: int,
		speed_last_turn: int = 0, acceleration: int = 0, can_submit_val: bool = false) -> void:
	_plot_max = remaining_ma_val
	if ship_list_items.has(ship_id) and ship_id != selected_ship_id:
		_select_ship(ship_id)  # the controls shown always belong to the selected ship
	if plotting_controls:
		plotting_controls.visible = true
		_update_ma_display(remaining_ma_val)
		_update_path_display([])
		_update_button_states(false, can_submit_val, true)
		set_collision_warning("")
		var note := PlanningText.movement_limit_note(table_ma, _plot_max, speed_last_turn, acceleration)
		if ma_limit_label:
			ma_limit_label.text = note
			ma_limit_label.visible = note != ""
		if ma_label:
			ma_label.tooltip_text = note if note != "" else "The most this ship can move this turn."

func hide_plotting_controls() -> void:
	if plotting_controls:
		plotting_controls.visible = false
	if tacking_label:
		tacking_label.visible = false
	set_collision_warning("")

func update_plotting_state(plotted_path_arr: Array, remaining_ma_val: int, can_submit_val: bool) -> void:
	_plot_max = maxi(_plot_max, remaining_ma_val)
	_update_ma_display(remaining_ma_val)
	_update_path_display(plotted_path_arr)
	_update_button_states(not plotted_path_arr.is_empty(), can_submit_val, plotted_path_arr.is_empty())

## "" hides the warning.
func set_collision_warning(text: String) -> void:
	if collision_label:
		collision_label.text = text
		collision_label.visible = text != ""

func update_tacking_state(is_tacking: bool, probability: float) -> void:
	if not tacking_label:
		return
	tacking_label.visible = is_tacking
	if is_tacking:
		var pct = int(probability * 100.0)
		tacking_label.text = "Tacking: %d%% success" % pct

func mark_ship_submitted(ship_id: String) -> void:
	submitted_ships[ship_id] = true
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_submitted_state(true)
	deactivate_movement_button(ship_id)
	_update_end_planning_state()
	_update_instructions()

func mark_ship_unsubmitted(ship_id: String) -> void:
	submitted_ships[ship_id] = false
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_submitted_state(false)
	_update_end_planning_state()
	_update_instructions()

func deactivate_movement_button(ship_id: String) -> void:
	if action_states.has(ship_id):
		action_states[ship_id]["movement"] = false
		if ship_list_items.has(ship_id):
			ship_list_items[ship_id].set_action_button_state("movement", false)

func _update_ma_display(remaining: int) -> void:
	if ma_label:
		ma_label.text = PlanningText.movement_line(remaining, _plot_max)

func _update_path_display(path: Array) -> void:
	if not path_label:
		return
	if path.is_empty():
		path_label.text = "Path: (none)"
		return

	var parts: PackedStringArray = []
	for step in path:
		parts.append("(%d,%d)" % [step.hex.x, step.hex.y])
	path_label.text = "Path: " + " → ".join(parts)

## Undo needs a plotted step; Submit follows the server, and says so when it means staying put.
func _update_button_states(can_undo: bool, can_submit_val: bool, path_empty: bool) -> void:
	if undo_button:
		undo_button.disabled = not can_undo
	if undo_all_button:
		undo_all_button.disabled = not can_undo
	if submit_button:
		submit_button.disabled = not can_submit_val
		submit_button.text = submit_text(can_submit_val, path_empty)

static func submit_text(can_submit_val: bool, path_empty: bool) -> String:
	return "Submit (hold position)" if can_submit_val and path_empty else "Submit"

func _update_end_planning_state() -> void:
	if not end_planning_button:
		return
	var all_submitted = are_all_ships_submitted()
	end_planning_button.disabled = not all_submitted
	var count = get_submitted_count()
	end_planning_button.text = "End Planning (%d/%d)" % [count, total_player_ships]

func _update_instructions() -> void:
	if not instructions_label:
		return
	instructions_label.text = PlanningText.instructions(
		total_player_ships - get_submitted_count(), total_player_ships, _unable_count())

func _unable_count() -> int:
	var count := 0
	for ship in ship_states.values():
		if not PlanningSailUi.can_plot_movement(ship):
			count += 1
	return count
