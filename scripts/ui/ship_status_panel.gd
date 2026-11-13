class_name ShipStatusPanel
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

const SAIL_NAMES := {"FS": "Fighting Sail", "MS": "Maneuvering Sail", "PS": "Plain Sail", "NS": "No Sail"}
const MORALE_NAMES := ["", "", "Low", "Fair", "Good", "High"]

var current_ship_state: ShipState = null
var _extra_label: Label = null  # marines, guns dismounted, pending sail change
var _badge_label: Label = null  # FOULED / STRUCK / DISMASTED

func _ready() -> void:
	visible = false
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	_build_extra_labels()


func _build_extra_labels() -> void:
	var box := get_node_or_null("VBox")
	if box == null:
		return
	_extra_label = Label.new()
	_extra_label.name = "ExtraLabel"
	box.add_child(_extra_label)
	_badge_label = Label.new()
	_badge_label.name = "BadgeLabel"
	_badge_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	box.add_child(_badge_label)


## Re-read the shown ship (the view calls this when state may have changed).
func refresh() -> void:
	if visible and current_ship_state:
		_update_display()


## "Hull 5/5 4/5 5/5 6/6": current/max per section (missing max entries read as 0).
static func box_line(label: String, current: Array[int], maximum: Array[int]) -> String:
	var parts := PackedStringArray()
	for i in range(current.size()):
		parts.append("%d/%d" % [current[i], maximum[i] if i < maximum.size() else 0])
	return "%s %s" % [label, " ".join(parts)]


static func sail_line(s: ShipState) -> String:
	var text := "Sail: %s" % SAIL_NAMES.get(s.sail_state, s.sail_state)
	var moves_as := s.movement_sail_state()
	if moves_as != s.sail_state.to_upper():
		text += " (moves as %s)" % moves_as
	return text


## "" when no sail change is ordered or underway.
static func sail_change_line(s: ShipState) -> String:
	if not s.sail_change.is_empty():
		var turns: int = s.sail_change.get("turns_left", 0)
		return "Sail change: %s, %d %s left" % [
			s.sail_change.get("target", "?"), turns, "turn" if turns == 1 else "turns"]
	var ordered: String = s.plotted_actions.get("sail_change", "")
	if ordered != "":
		return "Sail change ordered: %s" % ordered
	return ""


static func badges(s: ShipState) -> Array[String]:
	var result: Array[String] = []
	if s.fouled_with != "":
		result.append("FOULED")
	if s.is_struck():
		result.append("STRUCK")
	if s.is_dismasted():
		result.append("DISMASTED")
	return result


## Damage and condition lines in display order (guns line only when something is dismounted).
static func status_lines(s: ShipState) -> Array[String]:
	var lines: Array[String] = []
	var ship: Ship = s.ship
	lines.append(box_line("Rigging", s.rigging_current_hp, ship.rigging_hp if ship else [] as Array[int]))
	lines.append(box_line("Hull", s.hull_current_hp, ship.hull_hp if ship else [] as Array[int]))
	lines.append(box_line("Crew", s.crew_count, ship.crew_count if ship else [] as Array[int]))
	lines.append("Marines %d/%d" % [s.marine_count, ship.marine_count if ship else 0])
	if s.guns_dismounted[0] > 0 or s.guns_dismounted[1] > 0:
		lines.append("Guns dismounted: port %d, starboard %d" % [s.guns_dismounted[0], s.guns_dismounted[1]])
	var morale: String = MORALE_NAMES[s.morale_rating] if s.morale_rating >= 0 and s.morale_rating < MORALE_NAMES.size() else "Unknown"
	lines.append("Quality %s · Morale %s (%d)" % [s.crew_quality, morale, s.morale_rating])
	return lines

func show_ship_status_from_state(ship_state: ShipState) -> void:
	"""Display status for a specific ship (from ShipState)"""
	current_ship_state = ship_state
	visible = true
	_update_display()

func _update_display() -> void:
	if not current_ship_state:
		return

	var s = current_ship_state
	var lines := status_lines(s)  # rigging, hull, crew, marines, [guns], quality/morale

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
		sail_state_label.text = sail_line(s)

	if rigging_label:
		rigging_label.text = "%s (max sail %s)" % [lines[0], s.max_sail_state()]

	if hull_label:
		hull_label.text = lines[1]

	if crew_label:
		crew_label.text = lines[2]

	if morale_label:
		morale_label.text = lines[lines.size() - 1]

	if _extra_label:
		var extra: Array[String] = [lines[3]]
		if lines.size() > 5:
			extra.append(lines[4])
		var change := sail_change_line(s)
		if change != "":
			extra.append(change)
		_extra_label.text = "\n".join(extra)

	if _badge_label:
		_badge_label.text = "  ".join(badges(s))
		_badge_label.visible = not _badge_label.text.is_empty()

	if ma_label:
		# Read-only query — OK from UI layer  SCV:ALLOW
		var ma = GameState.ship_controller.get_movement_allowance(s.ship_id) if GameState.ship_controller else 0
		ma_label.text = "Movement Allowance: %d" % ma

func _on_close_pressed() -> void:
	visible = false
	current_ship_state = null

func toggle(ship_state: ShipState) -> void:
	"""Toggle the panel for a ship: hide if already showing it, otherwise show it."""
	if visible and current_ship_state == ship_state:
		visible = false
		current_ship_state = null
	else:
		show_ship_status_from_state(ship_state)
