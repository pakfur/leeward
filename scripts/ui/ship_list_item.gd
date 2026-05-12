extends PanelContainer
## ShipListItem - Compact display of a ship in the planning phase list

signal selected()
signal action_button_pressed(action_type: String)

@onready var ship_icon: TextureRect = %ShipIcon
@onready var ship_name_label: Label = %ShipNameLabel
@onready var speed_label: Label = %SpeedLabel
@onready var stats_label: Label = %StatsLabel
@onready var movement_button: Button = %MovementButton
@onready var crew_button: Button = %CrewButton
@onready var maintenance_button: Button = %MaintenanceButton

var ship_state: ShipState = null
var is_selected: bool = false
var is_submitted: bool = false

# Default icons by ship type
const ICON_PATHS = {
	"corvette": "res://assets/ui/ship_icons/corvette_icon.svg",
	"frigate": "res://assets/ui/ship_icons/frigate_icon.svg",
	"ship_of_line": "res://assets/ui/ship_icons/ship_of_line_icon.svg",
	"default": "res://assets/ui/ship_icons/default_ship_icon.svg"
}

# Style themes
var normal_style: StyleBoxFlat
var selected_style: StyleBoxFlat
var submitted_style: StyleBoxFlat

func _ready() -> void:
	# Create styles
	normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	normal_style.border_color = Color(0.4, 0.4, 0.5, 1.0)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(4)

	selected_style = StyleBoxFlat.new()
	selected_style.bg_color = Color(0.3, 0.35, 0.4, 1.0)
	selected_style.border_color = Color(0.6, 0.7, 0.8, 1.0)
	selected_style.set_border_width_all(2)
	selected_style.set_corner_radius_all(4)

	submitted_style = StyleBoxFlat.new()
	submitted_style.bg_color = Color(0.2, 0.3, 0.2, 0.9)
	submitted_style.border_color = Color(0.4, 0.7, 0.4, 1.0)
	submitted_style.set_border_width_all(1)
	submitted_style.set_corner_radius_all(4)

	add_theme_stylebox_override("panel", normal_style)

	# Connect button signals
	if movement_button:
		movement_button.pressed.connect(_on_movement_pressed)
	if crew_button:
		crew_button.pressed.connect(_on_crew_pressed)
	if maintenance_button:
		maintenance_button.pressed.connect(_on_maintenance_pressed)

	# Make the panel clickable
	gui_input.connect(_on_gui_input)

func setup(state: ShipState) -> void:
	"""Initialize the list item with ship state data"""
	ship_state = state
	_update_display()

func _update_display() -> void:
	"""Update all UI elements with current ship state"""
	if not ship_state:
		return

	# Ship name
	if ship_name_label:
		ship_name_label.text = ship_state.ship_name

	# Speed
	if speed_label:
		speed_label.text = "Spd: %d" % ship_state.speed

	# Stats line: "Hull: 8/8/8 Crew: 200/4 Sails: MS/4"
	if stats_label:
		var hull_str = "%d/%d/%d" % [
			ship_state.hull_current_hp[0],
			ship_state.hull_current_hp[1],
			ship_state.hull_current_hp[2]
		]
		var crew_str = "%s/%d" % [ship_state.crew_quality, ship_state.crew_morale]
		var sails_str = "%s/%s" % [ship_state.sail_state, ship_state.rigging_current_hp]

		stats_label.text = "Hull: %s  Crew: %s  Sails: %s" % [hull_str, crew_str, sails_str]

	# Ship icon
	if ship_icon:
		var icon_path = _get_icon_path_for_ship_type(ship_state.ship_type)
		if ResourceLoader.exists(icon_path):
			ship_icon.texture = load(icon_path)

func _get_icon_path_for_ship_type(ship_type: String) -> String:
	"""Get icon path based on ship type"""
	var type_lower = ship_type.to_lower()

	for key in ICON_PATHS.keys():
		if key in type_lower:
			return ICON_PATHS[key]

	return ICON_PATHS["default"]

func set_selected_state(selected: bool) -> void:
	is_selected = selected
	_apply_panel_style()

func set_submitted_state(submitted: bool) -> void:
	is_submitted = submitted
	_apply_panel_style()
	if ship_name_label and submitted:
		ship_name_label.text = ship_state.ship_name + " [OK]" if ship_state else ship_name_label.text
	elif ship_name_label and ship_state:
		ship_name_label.text = ship_state.ship_name

func _apply_panel_style() -> void:
	if is_selected:
		add_theme_stylebox_override("panel", selected_style)
	elif is_submitted:
		add_theme_stylebox_override("panel", submitted_style)
	else:
		add_theme_stylebox_override("panel", normal_style)

func set_action_button_state(action_type: String, active: bool) -> void:
	"""Set the toggle state of an action button"""
	var button: Button = null

	match action_type:
		"movement":
			button = movement_button
		"crew":
			button = crew_button
		"maintenance":
			button = maintenance_button

	if button:
		button.button_pressed = active

func _on_gui_input(event: InputEvent) -> void:
	"""Handle clicks on the panel"""
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			selected.emit()
			accept_event()

func _on_movement_pressed() -> void:
	action_button_pressed.emit("movement")

func _on_crew_pressed() -> void:
	action_button_pressed.emit("crew")

func _on_maintenance_pressed() -> void:
	action_button_pressed.emit("maintenance")
