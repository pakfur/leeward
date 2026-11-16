class_name BoardingCard
extends PanelContainer
## BoardingCard - one boarding round in the combat playback (boarding spec §4.5, UX3): two columns,
## attacker and defender, with the sections and boxes engaged, TBCF, odds and other DRMs, the 2d6,
## the % and BCF inflicted, the boxes lost, then the result in large type ("REPULSED · 1 MC",
## "CAPTURED", "THE FIGHT GOES ON"). Built from the BOARDING_ROUND and BOARDING_RESULT events;
## presentation only.

signal dismissed()

const INK := Color("#f1e6cf")
const MUTED := Color("#b9ab8f")
const BG := Color("#1d2633")
const EDGE := Color("#c8a45a")
const BAD := Color("#e0624f")
const GOOD := Color("#7fd18b")


## `round_data`: the BOARDING_ROUND event data; `result`: the BOARDING_RESULT data ({} if none);
## `names`: ship_id -> name.
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
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("BOARDING · ROUND %d" % int(round_data.get("round", 1)), 13, EDGE, true)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "×"
	close.flat = true
	close.focus_mode = FOCUS_NONE
	close.pressed.connect(func():
		dismissed.emit()
		queue_free())
	head.add_child(close)
	v.add_child(_label("%s boards %s" % [names.get(attacker_id, attacker_id), names.get(defender_id, defender_id)], 15, INK, true))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	v.add_child(cols)
	cols.add_child(_column("ATTACKER", str(names.get(attacker_id, attacker_id)), round_data.get("attacker", {}), true))
	cols.add_child(VSeparator.new())
	cols.add_child(_column("DEFENDER", str(names.get(defender_id, defender_id)), round_data.get("defender", {}), false))
	var verdict := result_text(result)
	var big := _label(verdict, 22, BAD if verdict.begins_with("REPULSED") else (GOOD if verdict.begins_with("CAPTURED") else INK), true)
	big.name = "ResultLabel"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(big)


## The result in display type: "CAPTURED", "REPULSED · 1 MC", "ATTACKERS LOST", "THE FIGHT GOES ON".
static func result_text(result: Dictionary) -> String:
	match str(result.get("result", "")):
		"captured":
			return "CAPTURED"
		"repulsed":
			var mcs := int(result.get("mcs", 0))
			return "REPULSED" + (" · %d MC" % mcs if mcs > 0 else "")
		"driven_off":
			return "ATTACKERS LOST"
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
