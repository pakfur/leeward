class_name ShipCardStatus
extends PanelContainer
## The status box on the expanded ship card of the planning panel (planning panel rework C2-C6,
## prototypes/planning_panel/planning_panel.html): Hull, Rigging, Crew and Marines as segmented
## lines (one segment per box, grouped by section, an emptied section outlined red), then Guns as
## one row of gun factors per broadside (dismounted guns drawn empty) with the sections-firing
## readout. View only: reads the ShipState and the crew plan it is given.

const Style = preload("res://scripts/ui/crew_overlay/crew_style.gd")

const CREW_COLOR := Color("#4f8fb8")
const MARINE_COLOR := Color("#c0463c")
const LONG_GUN_COLOR := Color("#b9c3cf")
const CARRONADE_COLOR := Color("#7f8b98")
const MEDIUM_GUN_COLOR := Color("#9aa6b3")
const LOST_EDGE := Color("#4a5868")

var _box: VBoxContainer


func _ready() -> void:
	name = "ShipCardStatus"
	add_theme_stylebox_override("panel", Style.box(Style.PANEL_2, Style.LINE, 1, 6, Style.px(10)))
	mouse_filter = MOUSE_FILTER_PASS
	_box = _vbox(8)
	add_child(_box)


## Redraws the box for `ship` with its crew plan (CrewTaskController.current_plan).
func render(ship: ShipState, plan: Dictionary) -> void:
	if _box == null:
		return
	CrewOverlay._clear(_box)
	if ship == null or ship.ship == null:
		return
	var assignments: Dictionary = plan.get("assignments", {})
	_box.add_child(_line("Hull", CrewOverlayText.boxes_caption(ship, "hull"),
		_sections(ship.hull_current_hp, ship.ship.hull_hp, Style.DECK, "Hull section %d")))
	_box.add_child(_line("Rigging", CrewOverlayText.boxes_caption(ship, "rigging"),
		_sections(ship.rigging_current_hp, ship.ship.rigging_hp, Color("#e4dbc4"), "Rigging section %d")))

	var crew := _hbox(5)
	crew.name = "CrewSections"
	for i in mini(ship.crew_count.size(), ship.ship.crew_count.size()):
		var job := CrewOverlayText.section_job(ship, i, assignments.get(i, {}))
		var col := _vbox(3)
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		var sec_name := CrewOverlayText.section_name(i)
		col.add_child(_section([int(ship.crew_count[i])], [int(ship.ship.crew_count[i])], CREW_COLOR,
			"%s: %d of %d boxes · %s" % [sec_name, int(ship.crew_count[i]), int(ship.ship.crew_count[i]), job["text"]]))
		var color: Color = Style.MUTED
		match job["kind"]:
			"task": color = Style.WARN
			"fire": color = Style.FIRE_TEXT
			"lost": color = Style.BAD_TEXT
		var tag := Style.label("%s %s" % [sec_name, job["text"]], 12, color, false, false, Style.COUNTER)
		tag.clip_text = true
		col.add_child(tag)
		crew.add_child(col)
	_box.add_child(_line("Crew", CrewOverlayText.crew_caption(ship), crew))

	var marines := _hbox(5)
	marines.name = "MarineSections"
	var m := _section([ship.marine_count], [ship.ship.marine_count], MARINE_COLOR,
		"Marines: %d of %d boxes" % [ship.marine_count, ship.ship.marine_count])
	m.size_flags_horizontal = SIZE_FILL
	m.custom_minimum_size.x = Style.px(14) * maxi(1, ship.ship.marine_count)
	marines.add_child(m)
	_box.add_child(_line("Marines", CrewOverlayText.marines_caption(ship, plan), marines))

	_box.add_child(_guns(ship, plan))


func _guns(ship: ShipState, plan: Dictionary) -> Control:
	var g := CrewOverlayText.guns_readout(ship, plan)
	var v := _vbox(4)
	v.name = "GunsLine"
	var head := _hbox(6)
	var title := Style.label("Guns", 12, Style.FG, true)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var big := Style.label(g["big"], 12, Style.BAD_TEXT if g["bad"] else Style.MUTED)
	big.name = "GunsReadout"
	head.add_child(big)
	v.add_child(head)
	for row in CrewOverlayText.gun_rows(ship, GameState.environment):
		var h := _hbox(8)
		var side := Style.label(str(row["side"]).to_upper(), 11, Style.MUTED, false, false, Style.COUNTER)
		side.custom_minimum_size.x = Style.px(78)
		h.add_child(side)
		var segs := _hbox(2)
		segs.add_theme_constant_override("separation", 2)
		segs.size_flags_horizontal = SIZE_EXPAND_FILL
		var kinds: Array = []
		for k in int(row["lg"]):
			kinds.append(LONG_GUN_COLOR)
		for k in int(row["mg"]):
			kinds.append(MEDIUM_GUN_COLOR)
		for k in int(row["cr"]):
			kinds.append(CARRONADE_COLOR)
		var off := mini(int(row["dismounted"]), kinds.size())
		for k in kinds.size():
			segs.add_child(_seg(kinds[k], k >= kinds.size() - off, Style.px(9)))
		var is_chase: bool = bool(row.get("chase", false))
		segs.tooltip_text = ("%s: 1 long gun factor (house rule: never dismounted, lower deck immaterial)" % row["side"]) if is_chase else "%s broadside: %d long gun, %d medium gun and %d carronade factors%s" % [
			row["side"], row["lg"], row["mg"], row["cr"],
			"" if off == 0 else ", %d guns dismounted (−1 each to this side's fire)" % off]
		if int(row["lower_deck"]) != 0:
			segs.tooltip_text += "\nLower deck guns closed by the sea (7.F.2): %s on this side's fire" % (
				"%d" % int(row["lower_deck"])).replace("-", "−")
		segs.mouse_filter = MOUSE_FILTER_PASS
		h.add_child(segs)
		var warn: bool = off > 0 or int(row["lower_deck"]) != 0
		h.add_child(Style.label(row["status"], 11, Style.WARN if warn else Style.MUTED, false, false, Style.COUNTER))
		v.add_child(h)
	v.add_child(Style.label(g["why"], 12, Style.MUTED, false, true))
	var key := _hbox(14)
	var gf: Dictionary = ship.ship.gun_factors
	for spec in [["long guns", "lg", LONG_GUN_COLOR], ["medium guns", "mg", MEDIUM_GUN_COLOR], ["carronades", "cr", CARRONADE_COLOR]]:
		if int(gf.get(spec[1], 0)) == 0:
			continue
		var k := _hbox(4)
		var sw := ColorRect.new()
		sw.color = spec[2]
		sw.custom_minimum_size = Vector2(Style.px(9), Style.px(9))
		sw.size_flags_vertical = SIZE_SHRINK_CENTER
		sw.mouse_filter = MOUSE_FILTER_IGNORE
		k.add_child(sw)
		k.add_child(Style.label("%s %d" % [spec[0], int(gf[spec[1]])], 11, Style.MUTED))
		key.add_child(k)
	key.add_child(Style.label("factors per side", 11, Style.MUTED))
	v.add_child(key)
	return v


## A titled line: "Hull ······ 21/21" over its segments.
func _line(title: String, caption: String, body: Control) -> Control:
	var v := _vbox(4)
	v.name = title + "Line"
	var h := _hbox(6)
	var t := Style.label(title, 12, Style.FG, true)
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(t)
	var c := Style.label(caption, 12, Style.MUTED)
	c.name = "Caption"
	h.add_child(c)
	v.add_child(h)
	v.add_child(body)
	return v


func _sections(cur: Array, mx: Array, color: Color, tip: String) -> Control:
	var secs := _hbox(5)
	for i in mini(cur.size(), mx.size()):
		var sec := _section([int(cur[i])], [int(mx[i])], color, (tip % (i + 1)) + ": %d of %d boxes" % [int(cur[i]), int(mx[i])])
		secs.add_child(sec)
	return secs


## One section: a segment per box, the lost ones hollow; outlined red once emptied.
func _section(cur: Array, mx: Array, color: Color, tip: String) -> Control:
	var left := int(cur[0])
	var full := int(mx[0])
	var sec := PanelContainer.new()
	var empty := left == 0 and full > 0
	sec.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, Style.BAD if empty else Color.TRANSPARENT, 1 if empty else 0, 3, 2))
	sec.size_flags_horizontal = SIZE_EXPAND_FILL
	sec.mouse_filter = MOUSE_FILTER_PASS
	sec.tooltip_text = tip
	var segs := _hbox(2)
	segs.add_theme_constant_override("separation", 2)
	for k in full:
		segs.add_child(_seg(color, k >= left, Style.px(11)))
	sec.add_child(segs)
	return sec


func _seg(color: Color, lost: bool, height: int) -> Control:
	var seg := Panel.new()
	seg.mouse_filter = MOUSE_FILTER_IGNORE
	seg.size_flags_horizontal = SIZE_EXPAND_FILL
	seg.custom_minimum_size.y = height
	seg.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT if lost else color, LOST_EDGE if lost else Color.TRANSPARENT, 1 if lost else 0, 2))
	return seg


func _vbox(sep_css: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Style.px(sep_css))
	v.mouse_filter = MOUSE_FILTER_IGNORE
	return v


func _hbox(sep_css: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Style.px(sep_css))
	h.mouse_filter = MOUSE_FILTER_IGNORE
	return h
