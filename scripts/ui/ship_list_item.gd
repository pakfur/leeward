extends PanelContainer
## ShipListItem - A ship's card in the planning panel. The cards are an accordion (planning panel
## rework C2, prototypes/planning_panel/planning_panel.html): the selected card is expanded (title,
## Movement / Crew & damage, then the ShipCardStatus box: hull, rigging, crew,
## marines and guns); every other card is one row: health icon, name, badge, speed / MA.

signal selected()
signal action_button_pressed(action_type: String)
signal crew_pressed()  ## the "Crew & damage" button: open the crew overlay for this ship

@onready var ship_name_label: Label = %ShipNameLabel
@onready var badge_label: Label = %BadgeLabel
@onready var speed_label: Label = %SpeedLabel
@onready var movement_button: Button = %MovementButton
@onready var crew_button: Button = %CrewButton
@onready var maintenance_button: Button = %MaintenanceButton

var ship_state: ShipState = null
var health_icon: ShipHealthIcon = null
var status_box: ShipCardStatus = null  ## hull, rigging, crew, marines, guns (expanded card only)
var chevron_label: Label = null  ## "▸" on a collapsed card
var action_row: HBoxContainer = null
var is_selected: bool = false
var is_submitted: bool = false
var _plan: Dictionary = {}

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
	var top_row: HBoxContainer = ship_name_label.get_parent()
	health_icon = ShipHealthIcon.new()
	health_icon.name = "HealthIcon"
	health_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(health_icon)
	top_row.move_child(health_icon, 0)
	chevron_label = Label.new()
	chevron_label.name = "Chevron"
	chevron_label.text = "▸"
	chevron_label.add_theme_color_override("font_color", CrewStyle.MUTED)
	chevron_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(chevron_label)
	action_row = movement_button.get_parent()
	status_box = ShipCardStatus.new()
	action_row.add_sibling(status_box)
	if maintenance_button:
		maintenance_button.pressed.connect(_on_maintenance_pressed)

	# Make the panel clickable
	gui_input.connect(_on_gui_input)
	_apply_expanded()

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
		speed_label.text = speed_text(ship_state.speed, _movement_allowance())
		speed_label.tooltip_text = "Speed last turn / movement allowance this turn"

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

	if health_icon:
		health_icon.show_ship(ship_state)
	_render_status()

## "Speed 3/5": speed last turn over this turn's movement allowance; no MA (< 0), "Speed 3".
static func speed_text(speed: int, ma: int) -> String:
	return "Speed %d/%d" % [speed, ma] if ma >= 0 else "Speed %d" % speed


## This turn's movement allowance (a read-only query), or -1 with no ship controller.
func _movement_allowance() -> int:
	if ship_state == null or GameState.ship_controller == null:
		return -1
	return GameState.ship_controller.get_movement_allowance(ship_state.ship_id)


## Selected = expanded (C2): only one card is open at a time; the panel selects one card.
func set_selected_state(selected_state: bool) -> void:
	is_selected = selected_state
	_apply_panel_style()
	_apply_expanded()
	if ship_name_label and ship_state:
		ship_name_label.text = _title()


## The expanded card shows its buttons and status box; a collapsed one only its top row.
func _apply_expanded() -> void:
	if action_row:
		action_row.visible = is_selected
	if crew_button:
		crew_button.visible = is_selected
	if status_box:
		status_box.visible = is_selected
	if chevron_label:
		chevron_label.visible = not is_selected
	tooltip_text = "" if is_selected else "Select to show this ship's orders"
	_render_status()


## The ship's crew plan (CrewTaskController.current_plan): the status box's crew and guns lines read it.
func set_crew_plan(plan: Dictionary) -> void:
	_plan = plan
	_render_status()


func _render_status() -> void:
	if status_box and ship_state and is_selected:
		status_box.render(ship_state, _plan)


func set_submitted_state(submitted: bool) -> void:
	is_submitted = submitted
	_apply_panel_style()
	if ship_name_label and ship_state:
		ship_name_label.text = _title()

## Expanded: "HMS Lively — 38-gun Frigate", with "(orders given)" once the ship has its orders.
## Collapsed: the name alone, with "✓" once it has its orders.
func _title() -> String:
	if not is_selected:
		return ship_state.ship_name + (" ✓" if is_submitted else "")
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
