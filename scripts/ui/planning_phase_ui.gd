extends Control
## PlanningPhaseUI - Main planning interface displayed in context panel during PLANNING phase

signal ship_selected(ship_id: String)
signal action_toggled(ship_id: String, action_type: String, active: bool)
signal undo_pressed()
signal undo_all_pressed()
signal submit_pressed()
signal cancel_pressed()
signal end_planning_pressed()
signal crew_overlay_requested(ship_id: String)  ## a card's "Crew & damage" button

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
@onready var steering_label: Label = %SteeringLabel
@onready var ma_limit_label: Label = %MALimitLabel
@onready var collision_label: Label = %CollisionLabel
@onready var allowance_note_label: Label = %AllowanceNoteLabel


# Track state
var ship_list_items: Dictionary = {}  # ship_id -> ShipListItem
var selected_ship_id: String = ""
var action_states: Dictionary = {}  # ship_id -> {action_type -> bool}
var submitted_ships: Dictionary = {}  # ship_id -> bool
var total_player_ships: int = 0
var ship_states: Dictionary = {}  # ship_id -> ShipState (read-only references)
var _plot_max: int = 0  # most the plotting ship can spend this turn; fixed for the plot
var crew_overlay_open: bool = false  # the selected card hides its summary line while the overlay is open

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
	refresh_crew_summaries()

## The crew plan changed (crew overlay): the cards follow it.
func refresh_crew_orders() -> void:
	refresh_crew_summaries()

## The status box on every card from the stored crew plan (a read-only query); the cards redraw
## their hull, rigging, crew and guns from the ship too.
func refresh_crew_summaries() -> void:
	for ship_id in ship_list_items:
		var ship: ShipState = ship_states.get(ship_id)
		var item = ship_list_items[ship_id]
		if ship == null or GameState.crew_task_controller == null:
			continue
		item.setup(ship)
		item.set_crew_plan(GameState.crew_task_controller.current_plan(ship_id))

func clear_ships() -> void:
	for child in ship_list_container.get_children():
		child.queue_free()

	ship_list_items.clear()
	selected_ship_id = ""
	action_states.clear()
	submitted_ships.clear()
	ship_states.clear()
	total_player_ships = 0

func _add_ship_to_list(ship_state: ShipState) -> void:
	var list_item = ShipListItem.instantiate()
	ship_list_container.add_child(list_item)

	# Setup the item with ship data
	list_item.setup(ship_state)

	# Connect signals
	list_item.selected.connect(func(): _on_ship_item_selected(ship_state.ship_id))
	list_item.action_button_pressed.connect(func(action_type): _on_action_button_pressed(ship_state.ship_id, action_type))
	list_item.crew_pressed.connect(func(): crew_overlay_requested.emit(ship_state.ship_id))

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
	refresh_crew_summaries()

func _on_action_button_pressed(ship_id: String, action_type: String) -> void:
	if not action_states.has(ship_id):
		return

	# Toggle the state
	var current_state = action_states[ship_id].get(action_type, false)
	var new_state = not current_state

	# Giving a ship orders selects it in every sense (card, plotting controls, map):
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
		set_allowance_note("")
		var note := PlanningText.movement_limit_note(table_ma, _plot_max, speed_last_turn, acceleration)
		if ma_limit_label:
			ma_limit_label.text = note
			ma_limit_label.visible = note != ""
		if ma_label:
			ma_label.tooltip_text = note if note != "" else "The most this ship can move this turn."
		_scroll_plotting_into_view.call_deferred()

## The expanded card (C2) keeps its status box while plotting, so the panel scrolls down to bring
## the plotting controls and their buttons into view.
func _scroll_plotting_into_view() -> void:
	var scroll := plotting_controls.get_parent().get_parent() as ScrollContainer if plotting_controls else null
	if scroll and plotting_controls.visible:
		await get_tree().process_frame  # let the container lay the controls out first
		scroll.ensure_control_visible(plotting_controls)


func hide_plotting_controls() -> void:
	if plotting_controls:
		plotting_controls.visible = false
	set_allowance_note("")
	if tacking_label:
		tacking_label.visible = false
	update_steering_state("")
	set_collision_warning("")

func update_plotting_state(plotted_path_arr: Array, remaining_ma_val: int, can_submit_val: bool) -> void:
	_plot_max = maxi(_plot_max, remaining_ma_val)
	_update_ma_display(remaining_ma_val)
	_update_path_display(plotted_path_arr)
	_update_button_states(not plotted_path_arr.is_empty(), can_submit_val, plotted_path_arr.is_empty())

## The note under the readout when a pivot changed the allowance ("" hides it).
func set_allowance_note(text: String) -> void:
	if allowance_note_label:
		allowance_note_label.text = text
		allowance_note_label.visible = text != ""

## "" hides the warning.
func set_collision_warning(text: String) -> void:
	if collision_label:
		collision_label.text = text
		collision_label.visible = text != ""

## The tacking note (PlanningText.tacking_note) for a turn at MA 0; hidden when not tacking.
func update_tacking_state(is_tacking: bool, text: String = "") -> void:
	if not tacking_label:
		return
	tacking_label.visible = is_tacking
	if is_tacking:
		tacking_label.text = text

## Steering damage note (PlanningText.steering_note); "" hides it.
func update_steering_state(text: String) -> void:
	if not steering_label:
		return
	steering_label.text = text
	steering_label.visible = text != ""

func mark_ship_submitted(ship_id: String) -> void:
	submitted_ships[ship_id] = true
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_submitted_state(true)
	deactivate_movement_button(ship_id)
	_update_end_planning_state()
	_update_instructions()
	refresh_crew_summaries()

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
