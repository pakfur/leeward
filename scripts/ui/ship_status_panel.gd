extends PanelContainer
## ShipStatusPanel - Displays detailed ship status information

@onready var ship_name_label: Label = %ShipNameLabel
@onready var ship_type_label: Label = %ShipTypeLabel
@onready var position_label: Label = %PositionLabel
@onready var facing_label: Label = %FacingLabel
@onready var speed_label: Label = %SpeedLabel
@onready var sail_state_label: Label = %SailStateLabel
@onready var hull_label: Label = %HullLabel
@onready var crew_label: Label = %CrewLabel
@onready var morale_label: Label = %MoraleLabel
@onready var rigging_label: Label = %RiggingLabel
@onready var ma_label: Label = %MALabel
@onready var close_button: Button = %CloseButton

var current_ship: Ship = null

func _ready() -> void:
	visible = false
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func show_ship_status(ship: Ship) -> void:
	"""Display status for a specific ship"""
	current_ship = ship
	visible = true
	_update_display()

func _update_display() -> void:
	if not current_ship:
		return

	var status = current_ship.get_status_summary()

	if ship_name_label:
		ship_name_label.text = status.name

	if ship_type_label:
		ship_type_label.text = status.type

	if position_label:
		position_label.text = "Position: (%d, %d)" % [status.position.x, status.position.y]

	if facing_label:
		var facing_names = ["E", "SE", "SW", "W", "NW", "NE"]
		facing_label.text = "Facing: %s (%d)" % [facing_names[status.facing], status.facing]

	if speed_label:
		speed_label.text = "Speed: %d hexes/turn" % status.speed

	if sail_state_label:
		var sail_names = {"FS": "Fighting Sail", "MS": "Maneuvering Sail", "PS": "Plain Sail", "NS": "No Sail"}
		sail_state_label.text = "Sail: %s" % sail_names.get(status.sail_state, status.sail_state)

	if hull_label:
		var hull_text = "Hull: "
		for i in range(status.hull_hp.size()):
			hull_text += "%d/%d" % [status.hull_hp[i], status.hull_max[i]]
			if i < status.hull_hp.size() - 1:
				hull_text += ", "
		hull_label.text = hull_text

	if crew_label:
		crew_label.text = "Crew: %d (%s)" % [status.crew, status.crew_quality]

	if morale_label:
		var morale_names = ["", "", "Low", "Fair", "Good", "High"]
		morale_label.text = "Morale: %s (%d)" % [morale_names[status.morale] if status.morale < morale_names.size() else "Unknown", status.morale]

	if rigging_label:
		rigging_label.text = "Rigging: %d/4" % status.rigging

	if ma_label:
		ma_label.text = "Movement Allowance: %d" % status.movement_allowance

func _on_close_pressed() -> void:
	visible = false
	current_ship = null
