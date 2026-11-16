class_name BoardingCard
extends PanelContainer
## BoardingCard - one boarding round in the combat playback (boarding spec §4.5, UX3): two columns,
## attacker and defender, with the sections and boxes engaged, TBCF, odds and other DRMs, the 2d6,
## the % and BCF inflicted, the boxes lost, then the result in large type ("REPULSED · 1 MC",
## "CAPTURED", "THE FIGHT GOES ON"). Several actions in one g-t (10.F) are stacked on one card, one
## block each. Built from the BOARDING_ROUND and BOARDING_RESULT events; presentation only.

signal dismissed()

const INK := Color("#f1e6cf")
const MUTED := Color("#b9ab8f")
const BG := Color("#1d2633")
const EDGE := Color("#c8a45a")
const BAD := Color("#e0624f")
const GOOD := Color("#7fd18b")


var _body: VBoxContainer = null
var _title: Label = null
var _rounds := 0


## `round_data`: the BOARDING_ROUND event data; `result`: the BOARDING_RESULT data ({} if none);
## `names`: ship_id -> name. Further actions fought in the same g-t (10.F) are added with add_round.
func setup(attacker_id: String, defender_id: String, round_data: Dictionary, result: Dictionary, names: Dictionary) -> void:
	name = "BoardingCard"
	mouse_filter = MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	add_theme_stylebox_override("panel", sb)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	var head := HBoxContainer.new()
	_body.add_child(head)
	_title = _label("BOARDING", 13, EDGE, true)
	_title.name = "TitleLabel"
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "×"
	close.flat = true
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(func():
		dismissed.emit()
		queue_free())
	head.add_child(close)
	add_round(attacker_id, defender_id, round_data, result, names)


## One more boarding round of the same g-t (10.F: each action against one enemy ship is fought
## separately), under the ones already shown.
func add_round(attacker_id: String, defender_id: String, round_data: Dictionary, result: Dictionary, names: Dictionary) -> void:
	_rounds += 1
	if _rounds > 1:
		_body.add_child(HSeparator.new())
	_title.text = title_text(_rounds)
	var sub := _label("%s boards %s · round %d" % [names.get(attacker_id, attacker_id), names.get(defender_id, defender_id),
		int(round_data.get("round", 1))], 15, INK, true)
	sub.name = "RoundLabel%d" % _rounds
	_body.add_child(sub)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	_body.add_child(cols)
	cols.add_child(_column("ATTACKER", str(names.get(attacker_id, attacker_id)), round_data.get("attacker", {}), true))
	cols.add_child(VSeparator.new())
	cols.add_child(_column("DEFENDER", str(names.get(defender_id, defender_id)), round_data.get("defender", {}), false))
	var verdict := result_text(result)
	var big := _label(verdict, 22 if _rounds == 1 else 20, BAD if verdict.begins_with("REPULSED") else (GOOD if verdict.begins_with("CAPTURED") else INK), true)
	big.name = "ResultLabel" if _rounds == 1 else "ResultLabel%d" % _rounds
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(big)


## "BOARDING", or with several actions this g-t "BOARDING · 2 ACTIONS (10.F)".
static func title_text(rounds: int) -> String:
	return "BOARDING" if rounds <= 1 else "BOARDING · %d ACTIONS (10.F)" % rounds


func round_count() -> int:
	return _rounds


## The last BOARDING_RESULT for the action of a BOARDING_ROUND event (a shared capture, 10.F,
## comes after the round's own result), or {}.
static func result_for(combat_log: PhaseEvents.PhaseLog, ev: PhaseEvents.PhaseEvent) -> Dictionary:
	var result := {}
	var action_id := int(ev.data.get("action", -1))
	var start := combat_log.events.find(ev)
	for k in range(start + 1, combat_log.events.size()):
		var later: PhaseEvents.PhaseEvent = combat_log.events[k]
		if later.type != PhaseEvents.Type.BOARDING_RESULT:
			continue
		if int(later.data.get("action", -2)) == action_id or (not later.data.has("action") and later.ship_id == ev.ship_id):
			result = later.data
	return result


## The result in display type: "CAPTURED", "REPULSED · 1 MC", "ATTACKERS LOST", "THE FIGHT GOES ON".
static func result_text(result: Dictionary) -> String:
	match str(result.get("result", "")):
		"captured":
			return "CAPTURED"
		"repulsed":
			var mcs := int(result.get("mcs", 0))
			return "REPULSED" + (" · %d MC" % mcs if mcs > 0 else "")
		"driven_off", "attackers_lost":
			return "ATTACKERS LOST"
		"shared_capture":
			return "CAPTURED · BY ANOTHER SHIP"
	return "THE FIGHT GOES ON"


## The lines of one side's column (tests read them): sections, TBCF, DRMs, roll, losses.
static func column_lines(side: Dictionary, attacker: bool) -> Array[String]:
	var lines: Array[String] = []
	var boxes := PackedStringArray()
	if int(side.get("sailors", 0)) > 0:
		boxes.append("%d sailor%s" % [int(side["sailors"]), "" if int(side["sailors"]) == 1 else "s"])
	if int(side.get("marines", 0)) > 0:
		boxes.append("%d marine%s" % [int(side["marines"]), "" if int(side["marines"]) == 1 else "s"])
	lines.append("%s · %s" % [PhaseEvents.sections_text(side.get("sections", [])), ", ".join(boxes)])
	if int(side.get("below", 0)) > 0:
		lines.append("incl. %d of the prize's crew from below (CQ G, 10.G.5)" % int(side["below"]))
	lines.append("TBCF %d (CQ %s)" % [int(side.get("tbcf", 0)), str(side.get("cq", "?"))])
	var drm := "odds %s" % _signed(int(side.get("odds", 0)))
	if attacker:
		drm += ", other %s" % _signed(int(side.get("other", 0)))
	lines.append("%s → %s" % [drm, _signed(int(side.get("drm", 0)))])
	lines.append("2d6 %d → %d" % [int(side.get("roll", 0)), int(side.get("total", 0))])
	lines.append("Enemy loses %d%% = %d BCF" % [int(side.get("pct", 0)), int(side.get("inflicts", 0))])
	var lost := PackedStringArray()
	if int(side.get("lost_sailors", 0)) > 0:
		lost.append("%d sailor%s" % [int(side["lost_sailors"]), "" if int(side["lost_sailors"]) == 1 else "s"])
	if int(side.get("lost_marines", 0)) > 0:
		lost.append("%d marine%s" % [int(side["lost_marines"]), "" if int(side["lost_marines"]) == 1 else "s"])
	lines.append("Lost: %s" % (", ".join(lost) if not lost.is_empty() else "none"))
	return lines


static func _signed(n: int) -> String:
	return "±0" if n == 0 else ("+%d" % n if n > 0 else "−%d" % absi(n))


func _column(role: String, ship_name: String, side: Dictionary, attacker: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.custom_minimum_size.x = 210
	v.add_child(_label(role, 11, MUTED, true))
	v.add_child(_label(ship_name, 14, INK, true))
	for line in column_lines(side, attacker):
		v.add_child(_label(line, 13, INK, false))
	return v


func _label(text: String, font_size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l
