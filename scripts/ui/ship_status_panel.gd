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

var current_ship_state: ShipState = null

func _ready() -> void:
	visible = false
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

func show_ship_status_from_state(ship_state: ShipState) -> void:
	"""Display status for a specific ship (from ShipState)"""
	current_ship_state = ship_state
	visible = true
	_update_display()

func _update_display() -> void:
	if not current_ship_state:
		return

	var s = current_ship_state
	var hull_max = s.ship.hull_hp if s.ship else [0, 0, 0, 0]

	if ship_name_label:
		ship_name_label.text = s.ship_name

	if ship_type_label:
		ship_type_label.text = s.ship.name if s.ship else s.ship_type

	if position_label:
		position_label.text = "Position: (%d, %d)" % [s.hex_position.x, s.hex_position.y]

	if facing_label:
		var facing_names = ["E", "SE", "SW", "W", "NW", "NE"]
		facing_label.text = "Facing: %s (%d)" % [facing_names[s.facing], s.facing]

	if speed_label:
		speed_label.text = "Speed: %d hexes/turn" % s.speed

	if sail_state_label:
		var sail_names = {"FS": "Fighting Sail", "MS": "Maneuvering Sail", "PS": "Plain Sail", "NS": "No Sail"}
		sail_state_label.text = "Sail: %s" % sail_names.get(s.sail_state, s.sail_state)

	if hull_label:
		var hull_text = "Hull: "
		for i in range(s.hull_current_hp.size()):
			var max_hp = hull_max[i] if i < hull_max.size() else 0
			hull_text += "%d/%d" % [s.hull_current_hp[i], max_hp]
			if i < s.hull_current_hp.size() - 1:
				hull_text += ", "
		hull_label.text = hull_text

	if crew_label:
		crew_label.text = "Crew: %d (%s)" % [s.crew_morale, s.crew_quality]

	if morale_label:
		var morale_names = ["", "", "Low", "Fair", "Good", "High"]
		morale_label.text = "Morale: %s (%d)" % [morale_names[s.crew_morale] if s.crew_morale < morale_names.size() else "Unknown", s.crew_morale]

	if rigging_label:
		# Read-only query — OK from UI layer  SCV:ALLOW
		var rq = GameState.ship_controller.get_rigging_quality(s.ship_id) if GameState.ship_controller else 4
		rigging_label.text = "Rigging: %d/4" % rq

	if ma_label:
		# Read-only query — OK from UI layer  SCV:ALLOW
		var ma = GameState.ship_controller.get_movement_allowance(s.ship_id) if GameState.ship_controller else 0
		ma_label.text = "Movement Allowance: %d" % ma

func _on_close_pressed() -> void:
	visible = false
	current_ship_state = null
