extends Control
## PlanningPhaseUI - Main planning interface displayed in context panel during PLANNING phase

signal ship_selected(ship_id: String)
signal action_toggled(ship_id: String, action_type: String, active: bool)

const ShipListItem = preload("res://scenes/ui/ship_list_item.tscn")

@onready var title_label: Label = %TitleLabel
@onready var ship_list_container: VBoxContainer = %ShipListContainer
@onready var instructions_label: Label = %InstructionsLabel

# Track state
var ship_list_items: Dictionary = {}  # ship_id -> ShipListItem
var selected_ship_id: String = ""
var action_states: Dictionary = {}  # ship_id -> {action_type -> bool}

func _ready() -> void:
	pass

func setup_for_player(player_ships: Array[ShipState]) -> void:
	"""Initialize the planning UI with the player's ships"""
	clear_ships()

	for ship_state in player_ships:
		_add_ship_to_list(ship_state)

	# Select first ship by default
	if not player_ships.is_empty():
		_select_ship(player_ships[0].ship_id)

func clear_ships() -> void:
	"""Clear all ship list items"""
	for child in ship_list_container.get_children():
		child.queue_free()

	ship_list_items.clear()
	selected_ship_id = ""
	action_states.clear()

func _add_ship_to_list(ship_state: ShipState) -> void:
	"""Add a ship to the list"""
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

func _on_ship_item_selected(ship_id: String) -> void:
	"""Handle ship selection from list item"""
	_select_ship(ship_id)
	ship_selected.emit(ship_id)

func _select_ship(ship_id: String) -> void:
	"""Update UI to reflect ship selection"""
	# Deselect previous
	if selected_ship_id != "" and ship_list_items.has(selected_ship_id):
		ship_list_items[selected_ship_id].set_selected_state(false)

	# Select new
	selected_ship_id = ship_id
	if ship_list_items.has(ship_id):
		ship_list_items[ship_id].set_selected_state(true)

func _on_action_button_pressed(ship_id: String, action_type: String) -> void:
	"""Handle action button toggle"""
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

	print("PlanningPhaseUI: Action '%s' toggled to %s for ship %s" % [action_type, new_state, ship_id])

func get_action_state(ship_id: String, action_type: String) -> bool:
	"""Get the current state of an action for a ship"""
	if action_states.has(ship_id):
		return action_states[ship_id].get(action_type, false)
	return false

func update_ship_display(ship_state: ShipState) -> void:
	"""Update a specific ship's display (called when state changes)"""
	if ship_list_items.has(ship_state.ship_id):
		ship_list_items[ship_state.ship_id].setup(ship_state)
