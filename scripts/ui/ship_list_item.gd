extends PanelContainer
## ShipListItem - Compact display of a ship in the planning phase list

signal selected()
signal action_button_pressed(action_type: String)
signal status_pressed()  ## the Status button: open this ship's status panel
signal crew_pressed()  ## the "Crew & damage" button: open the crew overlay for this ship

@onready var ship_icon: TextureRect = %ShipIcon
@onready var ship_name_label: Label = %ShipNameLabel
@onready var badge_label: Label = %BadgeLabel
@onready var speed_label: Label = %SpeedLabel
@onready var stats_label: Label = %StatsLabel
@onready var movement_button: Button = %MovementButton
@onready var crew_button: Button = %CrewButton
@onready var maintenance_button: Button = %MaintenanceButton
@onready var status_button: Button = %StatusButton

var ship_state: ShipState = null
var crew_summary_row: HFlowContainer = null  ## the crew summary chips (CrewRules.summary)
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

	# Connect button signals. Maintenance orders belong to a later milestone: hidden. The crew
	# button opens the crew overlay; it shows on the selected ship's card only.
	if movement_button:
		movement_button.pressed.connect(_on_movement_pressed)
	if crew_button:
		crew_button.visible = false
		crew_button.text = "Crew & damage  (C)"
		crew_button.toggle_mode = false
		crew_button.disabled = false
		crew_button.focus_mode = Control.FOCUS_NONE
		crew_button.tooltip_text = "Open the crew overlay: place crew sections on tasks (C)"
		crew_button.add_theme_stylebox_override("normal", CrewStyle.box(CrewStyle.BTN_PRIMARY, CrewStyle.BTN_PRIMARY_EDGE, 1, 4, 6))
		crew_button.add_theme_stylebox_override("hover", CrewStyle.box(Color("#376f95"), CrewStyle.BTN_PRIMARY_EDGE, 1, 4, 6))
	if maintenance_button:
		maintenance_button.visible = false
	if crew_button:
		crew_button.pressed.connect(func(): crew_pressed.emit())
	if stats_label:
		crew_summary_row = HFlowContainer.new()
		crew_summary_row.name = "CrewSummary"
		crew_summary_row.add_theme_constant_override("h_separation", 4)
		crew_summary_row.add_theme_constant_override("v_separation", 4)
		crew_summary_row.mouse_filter = Control.MOUSE_FILTER_PASS
		stats_label.add_sibling(crew_summary_row)
	if maintenance_button:
		maintenance_button.pressed.connect(_on_maintenance_pressed)

	if status_button:
		status_button.focus_mode = Control.FOCUS_NONE
		status_button.pressed.connect(func(): status_pressed.emit())

	# Make the panel clickable
	gui_input.connect(_on_gui_input)

func setup(state: ShipState) -> void:
	ship_state = state
	_update_display()

func _update_display() -> void:
	if not ship_state:
		return

	# Ship name
	if ship_name_label:
		ship_name_label.text = _title()

	# Speed
	if speed_label:
		speed_label.text = "Speed %d" % ship_state.speed
		speed_label.tooltip_text = "Speed last turn"

	# Detail lines: hull and rigging per section, sail by name, crew quality and morale
	if stats_label:
		var lines := PlanningText.card_lines(ship_state)
		stats_label.text = "\n".join(lines)

	# Status badge (fouled / struck / dismasted) locks out movement plotting
	var badge := PlanningSailUi.card_badge(ship_state)
	if badge_label:
		badge_label.text = badge
		badge_label.visible = badge != ""
		if ship_state.is_burning() and not ship_state.is_destroyed():
			badge_label.add_theme_color_override("font_color", CrewStyle.FIRE_TEXT)
			badge_label.tooltip_text = "Afire: each fire costs 1 hull and 1 rigging box a turn until it is put out (8.E.8)"
		else:
			badge_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35, 1))
			badge_label.tooltip_text = ""
	if movement_button:
		var can_move := PlanningSailUi.can_plot_movement(ship_state)
		movement_button.disabled = not can_move
		movement_button.tooltip_text = "" if can_move else PlanningSailUi.movement_block_reason(ship_state)

	# Ship icon
	if ship_icon:
		var icon_path = _get_icon_path_for_ship_type(ship_state.ship_type)
		if ResourceLoader.exists(icon_path):
			ship_icon.texture = load(icon_path)

func _get_icon_path_for_ship_type(ship_type: String) -> String:
	var type_lower = ship_type.to_lower()

	for key in ICON_PATHS.keys():
		if key in type_lower:
			return ICON_PATHS[key]

	return ICON_PATHS["default"]

func set_selected_state(selected_state: bool) -> void:
	is_selected = selected_state
	_apply_panel_style()
	if crew_button:
		crew_button.visible = selected_state


## The crew summary line (spec §4.8): chips [{"text", "kind"}]; hidden when `chips` is empty.
func set_crew_summary(chips: Array) -> void:
	if crew_summary_row == null:
		return
	for c in crew_summary_row.get_children():
		crew_summary_row.remove_child(c)
		c.queue_free()
	crew_summary_row.visible = not chips.is_empty()
	for chip in chips:
		crew_summary_row.add_child(crew_chip(chip))


static func crew_chip(chip: Dictionary) -> Label:
	var kind := str(chip.get("kind", ""))
	var l := Label.new()
	l.text = str(chip.get("text", ""))
	l.add_theme_font_size_override("font_size", 14)
	var bg := CrewStyle.BTN
	var edge := Color.TRANSPARENT
	var fg := CrewStyle.FG
	match kind:
		"auto":
			bg = CrewStyle.BTN_PRIMARY
		"default":
			bg = Color("#1f2a36")
			fg = CrewStyle.MUTED
		"fire":
			bg = CrewStyle.FIRE
			fg = Color("#1b0d05")
		"warn":
			bg = Color.TRANSPARENT
			edge = CrewStyle.BAD
			fg = CrewStyle.BAD_TEXT
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = 300
	var sb := CrewStyle.box(bg, edge, 1 if edge.a > 0 else 0, 8)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_color_override("font_color", fg)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = l.text
	return l

func set_submitted_state(submitted: bool) -> void:
	is_submitted = submitted
	_apply_panel_style()
	if ship_name_label and ship_state:
		ship_name_label.text = _title()

## "HMS Lively — 38-gun Frigate", with "(orders given)" once the ship has its orders.
func _title() -> String:
	var text := PlanningText.name_and_type(ship_state)
	return text + " (orders given)" if is_submitted else text

func _apply_panel_style() -> void:
	if is_selected:
		add_theme_stylebox_override("panel", selected_style)
	elif is_submitted:
		add_theme_stylebox_override("panel", submitted_style)
	else:
		add_theme_stylebox_override("panel", normal_style)

func set_action_button_state(action_type: String, active: bool) -> void:
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
