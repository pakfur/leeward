class_name CrewSidePanel
extends VBoxContainer
## The planning panel's crew block for the selected ship (crew-tasks spec §4.6): hull and rigging
## bars, the Guns readout, the collapsible DAMAGE (N) list and, while the overlay is open, the
## roster (a row per section with a draggable counter). Ported from the prototype's left panel.
## View only: reads through the CrewOverlayClient; drags land on the overlay's stations.

const Style = preload("res://scripts/ui/crew_overlay/crew_style.gd")

var client: CrewOverlayClient = null
var overlay: CrewOverlay = null  # drag previews and counter clicks go through the overlay

var _status: VBoxContainer
var _guns: VBoxContainer
var _dmg_btn: Button
var _dmg_list: VBoxContainer
var _dmg_open := true
var _roster_panel: VBoxContainer
var _roster: VBoxContainer
var _render_queued := false
## Hidden while a move is plotted (the planning panel needs the room for its controls).
var suppressed := false:
	set(value):
		suppressed = value
		visible = not value and client != null and client.ship() != null


func setup(p_client: CrewOverlayClient, p_overlay: CrewOverlay) -> void:
	client = p_client
	overlay = p_overlay
	client.changed.connect(refresh)
	client.open_changed.connect(func(_on): refresh())
	refresh()


func _ready() -> void:
	name = "CrewSidePanel"
	add_theme_constant_override("separation", Style.px(8))
	mouse_filter = MOUSE_FILTER_IGNORE
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.box(Style.PANEL_2, Style.LINE, 1, 6, Style.px(10)))
	card.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(card)
	var cv := _vbox(6)
	card.add_child(cv)
	_status = _vbox(8)
	cv.add_child(_status)
	cv.add_child(_hrule())
	cv.add_child(Style.caption("Guns"))
	_guns = _vbox(3)
	cv.add_child(_guns)

	var dmg := PanelContainer.new()
	dmg.add_theme_stylebox_override("panel", Style.box(Style.PANEL_2, Style.LINE, 1, 6, Style.px(10)))
	dmg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dmg)
	var dv := _vbox(8)
	dmg.add_child(dv)
	_dmg_btn = Button.new()
	_dmg_btn.flat = true
	_dmg_btn.focus_mode = FOCUS_NONE
	_dmg_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dmg_btn.add_theme_font_size_override("font_size", Style.px(11))
	_dmg_btn.add_theme_font_override("font", Style.bold_font())
	_dmg_btn.add_theme_color_override("font_color", Style.FG)
	_dmg_btn.pressed.connect(func(): _dmg_open = not _dmg_open; refresh())
	dv.add_child(_dmg_btn)
	_dmg_list = _vbox(6)
	dv.add_child(_dmg_list)

	_roster_panel = _vbox(8)
	_roster_panel.add_child(Style.caption("Crew sections · drag onto the deck"))
	_roster = _vbox(6)
	_roster.name = "Roster"
	_roster_panel.add_child(_roster)
	add_child(_roster_panel)
	refresh()


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


func _hrule() -> Control:
	var r := ColorRect.new()
	r.color = Style.LINE
	r.custom_minimum_size.y = 1
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


func refresh() -> void:
	if not _render_queued and is_inside_tree():
		_render_queued = true
		_render.call_deferred()


func _render() -> void:
	_render_queued = false
	if client == null or _status == null:
		return
	var ship := client.ship()
	visible = ship != null and not suppressed
	if ship == null:
		return
	var plan := client.plan()
	_render_status(ship)
	_render_guns(ship, plan)
	_render_damage(ship)
	_roster_panel.visible = client.is_open
	if client.is_open:
		_render_roster(ship, plan)


func _render_status(ship: ShipState) -> void:
	CrewOverlay._clear(_status)
	if ship.ship == null:
		return
	for spec in [["Hull", ship.hull_current_hp, ship.ship.hull_hp, "hull", Style.DECK],
			["Rigging", ship.rigging_current_hp, ship.ship.rigging_hp, "rigging", Color("#e4dbc4")]]:
		var cur: Array = spec[1]
		var mx: Array = spec[2]
		var bar := _vbox(4)
		var h := _hbox(6)
		var b := Style.label(spec[0], 12, Style.FG, true)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(b)
		h.add_child(Style.label(CrewOverlayText.boxes_caption(ship, spec[3]), 12, Style.MUTED))
		bar.add_child(h)
		var secs := _hbox(5)
		for i in mini(cur.size(), mx.size()):
			var empty := int(cur[i]) == 0
			var sec := PanelContainer.new()
			sec.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, Style.BAD if empty else Color.TRANSPARENT, 1 if empty else 0, 3, 2))
			sec.size_flags_horizontal = SIZE_EXPAND_FILL
			sec.mouse_filter = MOUSE_FILTER_PASS
			sec.tooltip_text = "%s section %d: %d of %d boxes" % [spec[0], i + 1, int(cur[i]), int(mx[i])]
			var segs := _hbox(2)
			segs.add_theme_constant_override("separation", 2)
			for k in int(mx[i]):
				var seg := Panel.new()
				seg.mouse_filter = MOUSE_FILTER_IGNORE
				seg.size_flags_horizontal = SIZE_EXPAND_FILL
				seg.custom_minimum_size.y = Style.px(11)
				var lost: bool = k >= int(cur[i])
				seg.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT if lost else spec[4], Color("#4a5868") if lost else Color.TRANSPARENT, 1 if lost else 0, 2))
				segs.add_child(seg)
			sec.add_child(segs)
			secs.add_child(sec)
		bar.add_child(secs)
		_status.add_child(bar)


func _render_guns(ship: ShipState, plan: Dictionary) -> void:
	CrewOverlay._clear(_guns)
	var g := CrewOverlayText.guns_readout(ship, plan)
	var big := Style.label(g["big"], 20, Style.BAD_TEXT if g["bad"] else Style.FG, true)
	big.name = "GunsReadout"
	_guns.add_child(big)
	_guns.add_child(Style.label(g["why"], 12.5, Style.MUTED, false, true))
	_guns.add_child(Style.label(g["marines"], 12.5, Style.MUTED, false, true))


func _render_damage(ship: ShipState) -> void:
	CrewOverlay._clear(_dmg_list)
	var items := CrewOverlayText.damage_lines(ship)
	_dmg_btn.text = ("▾ " if _dmg_open else "▸ ") + "DAMAGE (%d)" % items.size()
	_dmg_list.visible = _dmg_open
	for it in items:
		var row := _hbox(8)
		var dot := ColorRect.new()
		dot.color = Color("#a07a4c") if it["repairable"] else Style.BAD
		dot.custom_minimum_size = Vector2(8, 8)
		dot.mouse_filter = MOUSE_FILTER_IGNORE
		var dot_wrap := MarginContainer.new()
		dot_wrap.add_theme_constant_override("margin_top", Style.px(6))
		dot_wrap.add_child(dot)
		dot_wrap.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(dot_wrap)
		var l := Style.label(it["text"], 13, Style.FG, false, true)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(l)
		_dmg_list.add_child(row)


func _render_roster(ship: ShipState, plan: Dictionary) -> void:
	CrewOverlay._clear(_roster)
	var assignments: Dictionary = plan.get("assignments", {})
	var layout := CrewDeckLayouts.layout_for(ship.ship_type)
	for section in range(ShipState.MARINES + 1):
		var row := PanelContainer.new()
		row.name = "Roster_" + CrewOverlayText.section_name(section)
		row.add_theme_stylebox_override("panel", Style.box(Style.PANEL, Style.LINE, 1, 6, Style.px(4)))
		row.mouse_filter = MOUSE_FILTER_PASS
		var hb := _hbox(10)
		row.add_child(hb)
		_roster.add_child(row)
		var sec_name := CrewOverlayText.section_name(section)
		if not ship.section_alive(section):
			var empty := Panel.new()
			empty.custom_minimum_size = Vector2(Style.px(38), Style.px(38))
			empty.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, Style.LINE, 1, 5))
			empty.mouse_filter = MOUSE_FILTER_IGNORE
			hb.add_child(empty)
			var lv := _vbox(2)
			lv.size_flags_horizontal = SIZE_EXPAND_FILL
			lv.add_child(Style.label("%s lost" % sec_name, 14, Style.FG, true))
			lv.add_child(Style.label("Section wiped out; its task was abandoned (4.B.3).", 12.5, Style.MUTED, false, true))
			hb.add_child(lv)
			continue
		var c := overlay.roster_counter(section, Style.px(38)) if overlay else Control.new()
		c.size_flags_vertical = SIZE_SHRINK_CENTER
		hb.add_child(c)
		var info := _vbox(0)
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		info.size_flags_vertical = SIZE_SHRINK_CENTER
		hb.add_child(info)
		var entry: Dictionary = assignments.get(section, {})
		row.tooltip_text = "%s · %s · %d boxes" % [sec_name, "Marines" if section == ShipState.MARINES else "Sailors", ship.section_boxes(section)]
		info.add_child(Style.label(CrewOverlayText.task_title(section, entry), 14, Style.FG, true, true))
		var pr := CrewOverlayText.progress_of(ship, section, entry)
		if not pr.is_empty():
			var prog := _hbox(8)
			prog.add_child(Style.label("Turn %d of %d" % [pr["now"], pr["total"]], 13, Style.WARN, true))
			var tb := _hbox(2)
			tb.add_theme_constant_override("separation", 2)
			tb.custom_minimum_size.x = Style.px(110)
			tb.size_flags_vertical = SIZE_SHRINK_CENTER
			for k in int(pr["total"]):
				var seg := ColorRect.new()
				seg.mouse_filter = MOUSE_FILTER_IGNORE
				seg.size_flags_horizontal = SIZE_EXPAND_FILL
				seg.custom_minimum_size.y = Style.px(6)
				seg.color = Style.OK if k < int(pr["done"]) else Style.WARN if k == int(pr["done"]) else Color("#3a4757")
				tb.add_child(seg)
			prog.add_child(tb)
			info.add_child(prog)
		var st_id := CrewRules.station_of(section, entry)
		var decks := CrewDeckLayouts.station_decks(layout, st_id)
		if not decks.is_empty() and not decks.has(client.deck):
			var where: String = decks[0]
			var deck_name := where
			for d in layout.get("decks", []):
				if d["id"] == where:
					deck_name = d["name"]
			var loc := LinkButton.new()
			loc.text = "Show on " + deck_name
			loc.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			loc.focus_mode = FOCUS_NONE
			loc.add_theme_font_size_override("font_size", Style.px(12.5))
			loc.add_theme_color_override("font_color", Style.ACCENT)
			loc.add_theme_color_override("font_hover_color", Style.ACCENT.lightened(0.2))
			loc.pressed.connect(func(): client.set_deck(where))
			info.add_child(loc)
