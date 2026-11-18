class_name CrewOverlayFooter
extends PanelContainer
## The bottom strip of the crew & damage overlay (planning panel rework C7-C8): the roster of crew
## sections (a row per section with a draggable counter, its task, progress and where it stands)
## and the collapsible DAMAGE (N) list. Both moved here from the planning panel's old crew block.
## View only: reads through the CrewOverlayClient; counters come from the overlay so drags and
## clicks land on its stations.

const Style = preload("res://scripts/ui/crew_overlay/crew_style.gd")

var client: CrewOverlayClient = null
var overlay: CrewOverlay = null

var _roster: HFlowContainer
var _dmg_btn: Button
var _dmg_list: VBoxContainer
var _dmg_open := true


func setup(p_client: CrewOverlayClient, p_overlay: CrewOverlay) -> void:
	client = p_client
	overlay = p_overlay


func _ready() -> void:
	name = "CrewOverlayFooter"
	var sb := Style.box(Color.TRANSPARENT, Style.LINE, 0, 0)
	sb.border_width_top = 1
	sb.content_margin_left = Style.px(18)
	sb.content_margin_right = Style.px(18)
	sb.content_margin_top = Style.px(12)
	sb.content_margin_bottom = Style.px(12)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = MOUSE_FILTER_IGNORE
	var h := _hbox(18)
	add_child(h)

	var rv := _vbox(6)
	rv.size_flags_horizontal = SIZE_EXPAND_FILL
	rv.size_flags_stretch_ratio = 3.0
	rv.add_child(Style.caption("Crew sections · drag onto the deck"))
	_roster = HFlowContainer.new()
	_roster.name = "Roster"
	_roster.add_theme_constant_override("h_separation", Style.px(6))
	_roster.add_theme_constant_override("v_separation", Style.px(6))
	_roster.mouse_filter = MOUSE_FILTER_IGNORE
	rv.add_child(_roster)
	h.add_child(rv)

	var dmg := PanelContainer.new()
	dmg.add_theme_stylebox_override("panel", Style.box(Style.PANEL_2, Style.LINE, 1, 6, Style.px(10)))
	dmg.mouse_filter = MOUSE_FILTER_IGNORE
	dmg.size_flags_horizontal = SIZE_EXPAND_FILL
	dmg.size_flags_stretch_ratio = 2.0
	dmg.size_flags_vertical = SIZE_SHRINK_BEGIN
	h.add_child(dmg)
	var dv := _vbox(8)
	dmg.add_child(dv)
	_dmg_btn = Button.new()
	_dmg_btn.name = "DamageToggle"
	_dmg_btn.flat = true
	_dmg_btn.focus_mode = FOCUS_NONE
	_dmg_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dmg_btn.add_theme_font_size_override("font_size", Style.px(11))
	_dmg_btn.add_theme_font_override("font", Style.theme_font(Style.STRONG))
	_dmg_btn.add_theme_color_override("font_color", Style.FG)
	_dmg_btn.pressed.connect(func(): _dmg_open = not _dmg_open; render())
	dv.add_child(_dmg_btn)
	_dmg_list = _vbox(6)
	_dmg_list.name = "DamageList"
	dv.add_child(_dmg_list)


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


## Redraws both parts for the client's ship (called from CrewOverlay._render).
func render() -> void:
	if client == null or _roster == null:
		return
	var ship := client.ship()
	if ship == null:
		return
	_render_roster(ship, client.plan())
	_render_damage(ship)


func _render_damage(ship: ShipState) -> void:
	CrewOverlay._clear(_dmg_list)
	var turn = client.game_state.get("current_turn") if client.game_state != null else null
	var items := CrewOverlayText.damage_lines(ship, int(turn) if turn != null else -1, client.plan())
	_dmg_btn.text = ("▾ " if _dmg_open else "▸ ") + "DAMAGE (%d)" % items.size()
	_dmg_list.visible = _dmg_open
	if items.is_empty():
		_dmg_list.add_child(Style.label("No damage.", 13, Style.MUTED))
	for it in items:
		var row := _hbox(8)
		var dot := ColorRect.new()
		dot.color = Style.FIRE if it.get("fire", false) else (Color("#a07a4c") if it["repairable"] else Style.BAD)
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
	var layout := CrewDeckLayouts.layout_for(ship.ship_type, ship.ship.ship_class if ship.ship else 0)
	for section in range(ShipState.MARINES + 1):
		var row := PanelContainer.new()
		row.name = "Roster_" + CrewOverlayText.section_name(section)
		row.add_theme_stylebox_override("panel", Style.box(Style.PANEL, Style.LINE, 1, 6, Style.px(4)))
		row.mouse_filter = MOUSE_FILTER_PASS
		row.custom_minimum_size.x = Style.px(230)
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
			tb.custom_minimum_size.x = Style.px(80)
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
