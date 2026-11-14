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

const HEADING_NAMES := ["east", "south-east", "south-west", "west", "north-west", "north-east"]
const HUMAN_PLAYER_ID := 0

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
	var text := "Sail: %s" % PlanningSailUi.sail_label(s.sail_state)
	var moves_as := s.movement_sail_state()
	if moves_as != s.sail_state.to_upper():
		text += " (moves as %s)" % PlanningSailUi.sail_label(moves_as).to_lower()
	return text


## Owner, plus the ship type only when it says something the name does not.
static func identity_line(s: ShipState) -> String:
	var side := "Yours" if s.player_id == HUMAN_PLAYER_ID else "Enemy"
	var type_name: String = s.ship.name if s.ship else s.ship_type
	if type_name != "" and type_name.to_lower() != s.ship_name.to_lower():
		return "%s · %s" % [side, type_name]
	return side


static func heading_line(facing: int) -> String:
	return "Heading: %s" % (HEADING_NAMES[facing] if facing >= 0 and facing < HEADING_NAMES.size() else "?")


static func speed_line(speed: int) -> String:
	return "Speed last turn: %d %s" % [speed, "hex" if speed == 1 else "hexes"]


## Before movement: "Movement allowance this turn: 5", or why the ship cannot move at all.
## After movement has resolved this turn (`moved` >= 0): "Moved 4 hexes this turn".
## `partner_name` names the ship it is fouled with (used only when fouled).
static func movement_line(s: ShipState, allowance: int, partner_name: String = "", moved: int = -1) -> String:
	if moved >= 0:
		return "Moved %d %s this turn" % [moved, "hex" if moved == 1 else "hexes"]
	if s.is_struck():
		return "Cannot move (struck)"
	if s.is_dismasted():
		return "Cannot move (dismasted)"
	if s.fouled_with != "":
		return "Cannot move (fouled with %s)" % (partner_name if partner_name != "" else s.fouled_with)
	return "Movement allowance this turn: %d" % allowance


## Movement has been resolved this turn from combat until the turn ends (the ship's speed then
## holds the hexes it moved); before that the allowance is what the ship may still spend.
static func movement_resolved(phase: int) -> bool:
	return phase >= TurnPhaseController.GamePhase.COMBAT_RESOLUTION


static func crew_quality_line(quality: String) -> String:
	return "Crew quality %s (of A–G)" % quality


static func morale_line(morale: int) -> String:
	return "Morale rating %d (2 best – 6 worst)" % morale


## "" when no sail change is ordered or underway.
static func sail_change_line(s: ShipState) -> String:
	if not s.sail_change.is_empty():
		var turns: int = s.sail_change.get("turns_left", 0)
		return "Sail change: %s, %d %s left" % [
			PlanningSailUi.sail_label(s.sail_change.get("target", "?")), turns, "turn" if turns == 1 else "turns"]
	var ordered: String = s.plotted_actions.get("sail_change", "")
	if ordered != "":
		return "Sail change ordered: %s" % PlanningSailUi.sail_label(ordered)
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


## Damage and condition lines in display order: rigging, hull, crew, marines, [guns, only when
## something is dismounted], crew quality, morale.
static func status_lines(s: ShipState) -> Array[String]:
	var lines: Array[String] = []
	var ship: Ship = s.ship
	lines.append(box_line("Rigging", s.rigging_current_hp, ship.rigging_hp if ship else [] as Array[int]))
	lines.append(box_line("Hull", s.hull_current_hp, ship.hull_hp if ship else [] as Array[int]))
	lines.append(box_line("Crew", s.crew_count, ship.crew_count if ship else [] as Array[int]))
	lines.append("Marines %d/%d" % [s.marine_count, ship.marine_count if ship else 0])
	if s.guns_dismounted[0] > 0 or s.guns_dismounted[1] > 0:
		lines.append("Guns dismounted: port %d, starboard %d" % [s.guns_dismounted[0], s.guns_dismounted[1]])
	lines.append(crew_quality_line(s.crew_quality))
	lines.append(morale_line(s.morale_rating))
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
	var ship: Ship = s.ship
	var no_max: Array[int] = []

	if ship_name_label:
		ship_name_label.text = s.ship_name

	if ship_type_label:
		ship_type_label.text = identity_line(s)

	if position_label:
		position_label.text = "Position: (%d, %d)" % [s.hex_position.x, s.hex_position.y]

	if facing_label:
		facing_label.text = heading_line(s.facing)

	if speed_label:
		speed_label.text = speed_line(s.speed)
		# Once movement has resolved, speed holds this turn's hexes: the movement line says so.
		speed_label.visible = not movement_resolved(GameState.current_phase)

	if sail_state_label:
		sail_state_label.text = sail_line(s)

	if rigging_label:
		rigging_label.text = "%s (carries up to %s)" % [
			box_line("Rigging", s.rigging_current_hp, ship.rigging_hp if ship else no_max),
			PlanningSailUi.sail_label(s.max_sail_state()).to_lower()]

	if hull_label:
		hull_label.text = box_line("Hull", s.hull_current_hp, ship.hull_hp if ship else no_max)

	if crew_label:
		crew_label.text = box_line("Crew", s.crew_count, ship.crew_count if ship else no_max)

	if morale_label:
		morale_label.text = "%s\n%s" % [crew_quality_line(s.crew_quality), morale_line(s.morale_rating)]

	if _extra_label:
		var extra: Array[String] = ["Marines %d/%d" % [s.marine_count, ship.marine_count if ship else 0]]
		if s.guns_dismounted[0] > 0 or s.guns_dismounted[1] > 0:
			extra.append("Guns dismounted: port %d, starboard %d" % [s.guns_dismounted[0], s.guns_dismounted[1]])
		var change := sail_change_line(s)
		if change != "":
			extra.append(change)
		_extra_label.text = "\n".join(extra)

	if _badge_label:
		_badge_label.text = "  ".join(badges(s))
		_badge_label.visible = not _badge_label.text.is_empty()

	if ma_label:
		# Read-only queries — OK from UI layer  SCV:ALLOW
		var ma = GameState.ship_controller.get_movement_allowance(s.ship_id) if GameState.ship_controller else 0
		var partner: ShipState = GameState.get_ship(s.fouled_with) if s.fouled_with != "" else null
		var moved: int = s.speed if movement_resolved(GameState.current_phase) else -1
		ma_label.text = movement_line(s, ma, partner.ship_name if partner else "", moved)

func _on_close_pressed() -> void:
	visible = false
	current_ship_state = null

## Close the panel if it shows a ship other than `ship_id`.
func hide_unless_showing(ship_id: String) -> void:
	if visible and current_ship_state and current_ship_state.ship_id != ship_id:
		_on_close_pressed()

func toggle(ship_state: ShipState) -> void:
	"""Toggle the panel for a ship: hide if already showing it, otherwise show it."""
	if visible and current_ship_state == ship_state:
		visible = false
		current_ship_state = null
	else:
		show_ship_status_from_state(ship_state)
