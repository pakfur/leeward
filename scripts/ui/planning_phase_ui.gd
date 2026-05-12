extends Control
## PlanningPhaseUI - Main planning interface displayed in context panel during PLANNING phase

signal ship_selected(ship_id: String)
signal action_toggled(ship_id: String, action_type: String, active: bool)
signal undo_pressed()
signal undo_all_pressed()
signal submit_pressed()
signal cancel_pressed()
signal end_planning_pressed()

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

# Track state
var ship_list_items: Dictionary = {}  # ship_id -> ShipListItem
var selected_ship_id: String = ""
var action_states: Dictionary = {}  # ship_id -> {action_type -> bool}
var submitted_ships: Dictionary = {}  # ship_id -> bool
var total_player_ships: int = 0

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

func clear_ships() -> void:
	for child in ship_list_container.get_children():
		child.queue_free()

	ship_list_items.clear()
	selected_ship_id = ""
	action_states.clear()
	submitted_ships.clear()
	total_player_ships = 0

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
	submitted_ships[ship_state.ship_id] = false

func _on_ship_item_selected(ship_id: String) -> void:
	_select_ship(ship_id)
	ship_selected.emit(ship_id)

func _select_ship(ship_id: String) -> void:
	# Deselect previous
	if selected_ship_id != "" and ship_list_items.has(selected_ship_id):
		ship_list_items[selected_ship_id].set_selected_state(false)

	# Select new
	selected_ship_id = ship_id
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_selected_state(true)

func _on_action_button_pressed(ship_id: String, action_type: String) -> void:
	if not action_states.has(ship_id):
		return

	# Toggle the state
	var current_state = action_states[ship_id].get(action_type, false)
	var new_state = not current_state
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
# Plotting Controls
# ============================================================================

func show_plotting_controls(ship_id: String, remaining_ma_val: int, total_ma: int) -> void:
	if plotting_controls:
		plotting_controls.visible = true
		_update_ma_display(remaining_ma_val, total_ma)
		_update_path_display([])
		_update_button_states(true, false)

func hide_plotting_controls() -> void:
	if plotting_controls:
		plotting_controls.visible = false
	if tacking_label:
		tacking_label.visible = false

func update_plotting_state(plotted_path_arr: Array, remaining_ma_val: int, can_submit_val: bool) -> void:
	_update_ma_display(remaining_ma_val, remaining_ma_val + plotted_path_arr.size())
	_update_path_display(plotted_path_arr)
	_update_button_states(not plotted_path_arr.is_empty(), can_submit_val)

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

func _update_ma_display(remaining: int, total: int) -> void:
	if ma_label:
		ma_label.text = "Movement: %d/%d remaining" % [remaining, total]

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

func _update_button_states(can_undo: bool, can_submit_val: bool) -> void:
	if undo_button:
		undo_button.disabled = not can_undo
	if undo_all_button:
		undo_all_button.disabled = not can_undo
	if submit_button:
		submit_button.disabled = not can_submit_val

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
	if are_all_ships_submitted():
		instructions_label.text = "All ships plotted. Press End Planning to proceed."
	else:
		var remaining = total_player_ships - get_submitted_count()
		instructions_label.text = "%d ship(s) need movement plots. Click Movement to re-plot." % remaining
