extends Control
## Throwaway Godot port of the approved crew overlay HTML prototype (v15),
## docs/superpowers/prototypes/crew-overlay.html. Checks feel at game scale only:
## fake data in CrewProtoModel, no GameState, no server, no rules engine.
##
## Run: make proto-crew  (godot res://prototypes/crew_overlay/crew_overlay_proto.tscn)

const Model := preload("res://prototypes/crew_overlay/crew_proto_model.gd")
const Style := preload("res://prototypes/crew_overlay/proto_style.gd")
const Counter := preload("res://prototypes/crew_overlay/counter_token.gd")
const Station := preload("res://prototypes/crew_overlay/station_panel.gd")
const DeckView := preload("res://prototypes/crew_overlay/deck_view.gd")
const Sea := preload("res://prototypes/crew_overlay/sea_backdrop.gd")

var m := Model.new()

# static scaffolding
var _stage: Control
var _overlay: Control
var _turn_lbl: Label
var _open_btn: Button
var _roster_panel: VBoxContainer
var _roster: VBoxContainer
var _status: VBoxContainer
var _guns: VBoxContainer
var _pc_name: Label
var _pc_type: Label
var _dmg_btn: Button
var _dmg_list: VBoxContainer
var _dmg_open := true
var _ov_title: Label
var _ov_sub: Label
var _deck_name: Label
var _big_host: Control
var _big_deck: Control
var _other_decks: VBoxContainer
var _fire_n: Label
var _ship_opt: OptionButton
var _sail_opt: OptionButton
var _s2_chk: CheckBox
var _msg: PanelContainer
var _msg_timer: Timer
var _menu: PopupMenu
var _menu_sec := ""
var _menu_targets: Array = []
var _render_queued := false
var _big_h := 0.0
## The station or deck card under a dragged counter (set from drop queries).
var drop_hover_id := 0


func _ready() -> void:
	Trace.trace_log("proto", "crew overlay prototype: start (fake data, no game state)")
	set_anchors_preset(PRESET_FULL_RECT)
	m.message_requested.connect(_on_message)
	m.defaults()
	_build()
	_render()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--selftest="):
			var t: Node = load("res://prototypes/crew_overlay/proto_selftest.gd").new()
			t.out_dir = arg.substr(11)
			t.proto = self
			t.use_local = OS.get_cmdline_user_args().has("--selftest-local")
			add_child(t)


# =====================================================================
# scaffolding
# =====================================================================

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Style.INK
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	var app := HBoxContainer.new()
	app.set_anchors_preset(PRESET_FULL_RECT)
	app.add_theme_constant_override("separation", 0)
	app.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(app)
	var left_slot := Control.new()
	left_slot.custom_minimum_size.x = Style.px(300)
	left_slot.clip_contents = true
	left_slot.mouse_filter = MOUSE_FILTER_IGNORE
	app.add_child(left_slot)
	var planning := _build_planning()
	planning.set_anchors_preset(PRESET_FULL_RECT)
	left_slot.add_child(planning)
	_stage = Control.new()
	_stage.size_flags_horizontal = SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.mouse_filter = MOUSE_FILTER_IGNORE
	app.add_child(_stage)
	_build_stage()
	_menu = PopupMenu.new()
	_menu.add_theme_font_size_override("font_size", Style.px(14))
	_menu.add_theme_stylebox_override("panel", Style.box(Color("#1f2935"), Style.BTN_EDGE, 1, 6, 4))
	_menu.add_theme_color_override("font_color", Style.FG)
	_menu.add_theme_color_override("font_disabled_color", Color(Style.FG, 0.45))
	_menu.add_theme_color_override("font_separator_color", Style.MUTED)
	_menu.add_theme_font_size_override("font_separator_size", Style.px(11))
	_menu.id_pressed.connect(_on_menu_id)
	add_child(_menu)
	_msg_timer = Timer.new()
	_msg_timer.one_shot = true
	_msg_timer.timeout.connect(_clear_message)
	add_child(_msg_timer)


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


func _panel(sb: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	return p


static func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func _build_planning() -> Control:
	var sb := Style.box(Style.PANEL, Style.LINE, 0, 0, Style.px(16))
	sb.border_width_right = 1
	var panel := _panel(sb)
	panel.custom_minimum_size.x = Style.px(300)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := _vbox(14)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(v)

	var h1 := Style.label("Planning Phase", 24)
	h1.add_theme_font_override("font", Style.display_font())
	v.add_child(h1)

	# ship card
	var card := _panel(Style.box(Style.PANEL_2, Style.LINE, 1, 6, Style.px(12)))
	v.add_child(card)
	var cv := _vbox(4)
	card.add_child(cv)
	var nm := _hbox(8)
	var sq := ColorRect.new()
	sq.color = Style.OK
	sq.custom_minimum_size = Vector2(Style.px(12), Style.px(12))
	sq.size_flags_vertical = SIZE_SHRINK_CENTER
	nm.add_child(sq)
	_pc_name = Style.label("", 16, Style.FG, true)
	nm.add_child(_pc_name)
	cv.add_child(nm)
	_pc_type = Style.label("", 14, Style.MUTED)
	cv.add_child(_pc_type)
	_status = _vbox(8)
	cv.add_child(_status)
	cv.add_child(_hrule())
	cv.add_child(Style.caption("Guns"))
	_guns = _vbox(3)
	cv.add_child(_guns)
	_open_btn = Style.button("Crew & damage  (C)", true)
	_open_btn.pressed.connect(func(): m.open = true; _queue_render())
	cv.add_child(_open_btn)

	# collapsible damage
	var dmg := _panel(Style.box(Style.PANEL_2, Style.LINE, 1, 6, Style.px(10)))
	v.add_child(dmg)
	var dv := _vbox(8)
	dmg.add_child(dv)
	_dmg_btn = Button.new()
	_dmg_btn.flat = true
	_dmg_btn.focus_mode = FOCUS_NONE
	_dmg_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dmg_btn.add_theme_font_size_override("font_size", Style.px(11))
	_dmg_btn.add_theme_font_override("font", Style.bold_font())
	_dmg_btn.add_theme_color_override("font_color", Style.FG)
	_dmg_btn.pressed.connect(func(): _dmg_open = not _dmg_open; _queue_render())
	dv.add_child(_dmg_btn)
	_dmg_list = _vbox(6)
	dv.add_child(_dmg_list)

	# roster
	_roster_panel = _vbox(8)
	_roster_panel.add_child(Style.caption("Crew sections · drag onto the deck"))
	_roster = _vbox(6)
	_roster_panel.add_child(_roster)
	v.add_child(_roster_panel)

	v.add_child(_build_controls())
	return panel


func _hrule() -> Control:
	var r := ColorRect.new()
	r.color = Style.LINE
	r.custom_minimum_size.y = 1
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


func _ctl_row(text: String, ctl: Control) -> HBoxContainer:
	var h := _hbox(8)
	var l := Style.label(text, 14)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	ctl.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(ctl)
	return h


func _option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = FOCUS_NONE
	o.add_theme_font_size_override("font_size", Style.px(14))
	for it in items:
		o.add_item(it)
	return o


func _check(cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.focus_mode = FOCUS_NONE
	c.toggled.connect(cb)
	return c


func _build_controls() -> Control:
	var sb := Style.box(Color.TRANSPARENT, Style.BTN_EDGE, 1, 6, Style.px(12))
	var p := _panel(sb)
	p.draw.connect(func(): pass)
	var v := _vbox(10)
	p.add_child(v)
	v.add_child(Style.label("PROTOTYPE CONTROLS", 11, Style.WARN, true))
	v.add_child(Style.label("These stand in for game state, so you can see how the overlay reacts. They are not part of the design.", 12.5, Style.MUTED, false, true))
	_ship_opt = _option(["38-gun frigate", "74-gun ship of the line"])
	_ship_opt.item_selected.connect(func(i): m.set_ship("frigate" if i == 0 else "sol74"); _queue_render())
	v.add_child(_ctl_row("Ship", _ship_opt))
	_sail_opt = _option(["FS", "MS", "PS"])
	_sail_opt.item_selected.connect(func(i): m.set_sail(["FS", "MS", "PS"][i]); _queue_render())
	v.add_child(_ctl_row("Sail carried", _sail_opt))
	v.add_child(_ctl_row("Turn at MA 0 plotted (tacking)", _check(func(on): m.set_tacking(on); _queue_render())))
	v.add_child(_ctl_row("Shrouds severed", _check(func(on): m.set_shrouds(on); _queue_render())))
	v.add_child(_ctl_row("Wheel shot away", _check(func(on): m.wheel = on; _queue_render())))
	v.add_child(_ctl_row("Starboard broadside obscured", _check(func(on): m.obscured = on; _queue_render())))
	var step := _hbox(6)
	var minus := Style.button("−")
	minus.custom_minimum_size = Vector2(Style.px(24), Style.px(24))
	minus.pressed.connect(func(): m.remove_fire(); _queue_render())
	_fire_n = Style.label("1", 14)
	var plus := Style.button("+")
	plus.custom_minimum_size = Vector2(Style.px(24), Style.px(24))
	plus.pressed.connect(func(): m.add_fire(); _queue_render())
	for b in [minus, plus]:
		for st in ["normal", "hover", "pressed"]:
			var s2: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			s2.set_content_margin_all(2)
			b.add_theme_stylebox_override(st, s2)
	step.add_child(minus)
	step.add_child(_fire_n)
	step.add_child(plus)
	v.add_child(_ctl_row("Fires burning", step))
	_s2_chk = _check(func(on): m.set_s2_gone(on); _queue_render())
	v.add_child(_ctl_row("S2 wiped out by gunfire", _s2_chk))
	var nt := Style.button("End turn (advance tasks)")
	nt.pressed.connect(func(): m.next_turn(); _queue_render())
	v.add_child(nt)
	return p


func _build_stage() -> void:
	var sea := Sea.new()
	sea.set_anchors_preset(PRESET_FULL_RECT)
	_stage.add_child(sea)
	var hint := _panel(Style.box(Color(0.055, 0.082, 0.114, 0.85), Style.LINE, 1, 6))
	(hint.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = Style.px(12)
	(hint.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = Style.px(12)
	(hint.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = Style.px(8)
	(hint.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = Style.px(8)
	hint.add_child(Style.label("Press C or “Crew & damage” to open the crew overlay.", 14, Style.MUTED))
	hint.set_anchors_preset(PRESET_BOTTOM_LEFT)
	hint.position = Vector2(Style.px(16), -Style.px(16))
	hint.grow_vertical = GROW_DIRECTION_BEGIN
	hint.offset_left = Style.px(16)
	hint.offset_bottom = -Style.px(16)
	_stage.add_child(hint)

	_overlay = Control.new()
	_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.039, 0.059, 0.082, 0.97)
	shade.set_anchors_preset(PRESET_FULL_RECT)
	shade.mouse_filter = MOUSE_FILTER_PASS
	shade.gui_input.connect(_on_background_input)
	_overlay.add_child(shade)
	var ov := _vbox(0)
	ov.set_anchors_preset(PRESET_FULL_RECT)
	_overlay.add_child(ov)

	# header
	var hsb := Style.box(Color.TRANSPARENT, Style.LINE, 0, 0)
	hsb.border_width_bottom = 1
	hsb.content_margin_left = Style.px(18)
	hsb.content_margin_right = Style.px(190)
	hsb.content_margin_top = Style.px(12)
	hsb.content_margin_bottom = Style.px(12)
	var head := _panel(hsb)
	ov.add_child(head)
	var hh := _hbox(16)
	head.add_child(hh)
	var tv := _vbox(2)
	_ov_title = Style.label("", 26)
	_ov_title.add_theme_font_override("font", Style.display_font())
	tv.add_child(_ov_title)
	_ov_sub = Style.label("", 14, Style.MUTED)
	tv.add_child(_ov_sub)
	hh.add_child(tv)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	hh.add_child(spacer)
	var tabs := _panel(Style.box(Style.INK, Style.LINE, 1, 5, 3))
	tabs.size_flags_vertical = SIZE_SHRINK_CENTER
	var crew_tab := Style.button("Crew")
	crew_tab.disabled = true
	crew_tab.tooltip_text = "Only mode in this prototype"
	var ctsb := Style.box(Style.BTN, Color.TRANSPARENT, 0, 3)
	ctsb.content_margin_left = Style.px(10)
	ctsb.content_margin_right = Style.px(10)
	ctsb.content_margin_top = Style.px(5)
	ctsb.content_margin_bottom = Style.px(5)
	crew_tab.add_theme_stylebox_override("disabled", ctsb)
	crew_tab.add_theme_color_override("font_disabled_color", Style.FG)
	tabs.add_child(crew_tab)
	hh.add_child(tabs)
	var reset := Style.button("Reset to defaults")
	reset.tooltip_text = "Put every section back to its default task"
	reset.size_flags_vertical = SIZE_SHRINK_CENTER
	reset.pressed.connect(func(): m.reset_defaults(); _queue_render())
	hh.add_child(reset)
	var done := Style.button("Done  (Esc)", true)
	done.size_flags_vertical = SIZE_SHRINK_CENTER
	done.pressed.connect(func(): m.open = false; _queue_render())
	hh.add_child(done)

	# body: enlarged deck | side column
	var body := _hbox(0)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	ov.add_child(body)
	var dsb := Style.box(Color.TRANSPARENT)
	dsb.content_margin_left = Style.px(18)
	dsb.content_margin_right = Style.px(18)
	dsb.content_margin_top = Style.px(14)
	dsb.content_margin_bottom = Style.px(14)
	var dvp := _panel(dsb)
	body.add_child(dvp)
	var dv := _vbox(10)
	dvp.add_child(dv)
	var dl := _hbox(12)
	_deck_name = Style.label("", 22)
	_deck_name.add_theme_font_override("font", Style.display_font())
	dl.add_child(_deck_name)
	var bu := Style.label("bow up", 13, Style.MUTED)
	bu.size_flags_vertical = SIZE_SHRINK_END
	dl.add_child(bu)
	dv.add_child(dl)
	_big_host = Control.new()
	_big_host.size_flags_vertical = SIZE_EXPAND_FILL
	_big_host.mouse_filter = MOUSE_FILTER_IGNORE
	_big_host.resized.connect(_size_big_deck)
	dv.add_child(_big_host)

	var ssb := Style.box(Color.TRANSPARENT, Style.LINE, 0, 0, Style.px(14))
	ssb.border_width_left = 1
	var stack := _panel(ssb)
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(stack)
	var sh := _hbox(18)
	stack.add_child(sh)
	var left := _vbox(10)
	left.custom_minimum_size.x = Style.px(300)
	sh.add_child(left)
	left.add_child(Style.label("Drag a counter to a station, click a counter then a station, or right-click a counter. These decks accept drops too.", 13, Style.MUTED, false, true))
	left.add_child(Style.caption("Decks · top to bottom · click to show large"))
	_other_decks = _vbox(12)
	left.add_child(_other_decks)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = SIZE_EXPAND_FILL
	sp2.mouse_filter = MOUSE_FILTER_IGNORE
	sh.add_child(sp2)
	var tact := _vbox(6)
	tact.custom_minimum_size.x = Style.px(300)
	sh.add_child(tact)
	tact.add_child(Style.caption("Tactical picture"))
	var inset_p := _panel(Style.box(Color.TRANSPARENT, Style.LINE, 1, 6))
	tact.add_child(inset_p)
	var iv := _vbox(0)
	inset_p.add_child(iv)
	var inset := Sea.new()
	inset.inset = true
	inset.clip_contents = true
	inset.custom_minimum_size = Vector2(Style.px(300) - 2, (Style.px(300) - 2) * 150.0 / 340.0)
	iv.add_child(inset)
	var capsb := Style.box(Color.TRANSPARENT, Style.LINE, 0, 0)
	capsb.border_width_top = 1
	capsb.content_margin_left = Style.px(7)
	capsb.content_margin_top = Style.px(5)
	capsb.content_margin_bottom = Style.px(5)
	var cap := _panel(capsb)
	cap.add_child(Style.label("Topaze 4 hexes off the starboard bow · wind SW 2", 11.5, Style.MUTED, false, true))
	iv.add_child(cap)

	# above the map and the overlay
	_turn_lbl = Style.label("", 26)
	_turn_lbl.add_theme_font_override("font", Style.display_font())
	_turn_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_turn_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_turn_lbl.set_anchors_preset(PRESET_CENTER_TOP)
	_turn_lbl.grow_horizontal = GROW_DIRECTION_BOTH
	_turn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_lbl.offset_top = Style.px(14)
	_stage.add_child(_turn_lbl)
	var endplan := Style.button("End Planning (0/1)")
	endplan.disabled = true
	endplan.tooltip_text = "Submits this turn's orders once every ship has them (placeholder in the prototype)"
	endplan.set_anchors_preset(PRESET_TOP_RIGHT)
	endplan.grow_horizontal = GROW_DIRECTION_BEGIN
	endplan.offset_right = -Style.px(16)
	endplan.offset_top = Style.px(12)
	_stage.add_child(endplan)

	_msg = PanelContainer.new()
	_msg.visible = false
	_msg.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_msg.grow_horizontal = GROW_DIRECTION_BOTH
	_msg.grow_vertical = GROW_DIRECTION_BEGIN
	_msg.offset_bottom = -Style.px(18)
	_stage.add_child(_msg)


func _size_big_deck() -> void:
	if _big_deck == null or not is_instance_valid(_big_deck):
		return
	var h := maxf(Style.px(320), _big_host.size.y)
	var w := roundf(h * DeckView.PW / 1000.0)
	_big_deck.position = Vector2.ZERO
	_big_deck.size = Vector2(w, h)
	if _big_host.custom_minimum_size.x != w:
		_big_host.custom_minimum_size.x = w
	if absf(h - _big_h) > 1.0:
		_big_h = h
		_queue_render()  # counter size follows the deck width


# =====================================================================
# render (rebuilds the dynamic parts, as the HTML's render())
# =====================================================================

func _queue_render() -> void:
	if not _render_queued:
		_render_queued = true
		_render.call_deferred()


func _render() -> void:
	_render_queued = false
	var sh: Dictionary = m.ship()
	var decks: Array = sh["decks"]
	if not decks.any(func(d): return d["id"] == m.deck):
		m.deck = "upper"
	var deck: Dictionary = decks.filter(func(d): return d["id"] == m.deck)[0]
	_overlay.visible = m.open
	_roster_panel.visible = m.open
	_open_btn.visible = not m.open
	_ov_title.text = sh["name"]
	_ov_sub.text = "%s · crew quality %s · carrying %s" % [sh["type"], sh["crew_quality"], m.sail]
	_pc_name.text = sh["name"]
	_pc_type.text = "%s · crew quality %s" % [sh["type"], sh["crew_quality"]]
	_turn_lbl.text = "Turn %d" % m.turn
	_fire_n.text = str(m.fires.size())
	_render_status(sh)

	_deck_name.text = deck["name"]
	if _big_deck != null and is_instance_valid(_big_deck):
		_big_host.remove_child(_big_deck)
		_big_deck.queue_free()
	_big_deck = _build_deck(deck, false, true)
	_big_host.add_child(_big_deck)
	_size_big_deck()

	_clear(_other_decks)
	var order: Array = decks.filter(func(d): return d["id"] == "upper") + decks.filter(func(d): return d["id"] == "orlop") \
			+ decks.filter(func(d): return sh["gun_decks"].has(d["id"]))
	for d in order:
		_other_decks.add_child(_build_deck_card(d))

	_render_roster(sh)
	_render_guns()
	_render_damage(sh)


func _render_status(sh: Dictionary) -> void:
	_clear(_status)
	var level: int = sh["rig"]["cur"].filter(func(n): return n > 0).size()
	var max_sail := "plain sail" if level == 4 else "manoeuvring sail" if level == 3 else "fighting sail" if level > 0 else "dismasted"
	for spec in [["Hull", sh["hull"], "", Style.DECK], ["Rigging", sh["rig"], " · carries up to " + max_sail, Color("#e4dbc4")]]:
		var d: Dictionary = spec[1]
		var left := 0
		var all := 0
		for i in 4:
			left += d["cur"][i]
			all += d["max"][i]
		var bar := _vbox(4)
		var h := _hbox(6)
		var b := Style.label(spec[0], 12, Style.FG, true)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(b)
		h.add_child(Style.label("%d/%d%s" % [left, all, spec[2]], 12, Style.MUTED))
		bar.add_child(h)
		var secs := _hbox(5)
		for i in 4:
			var sb := Style.box(Color.TRANSPARENT, Style.BAD if d["cur"][i] == 0 else Color.TRANSPARENT, 1 if d["cur"][i] == 0 else 0, 3, 2)
			var sec := _panel(sb)
			sec.size_flags_horizontal = SIZE_EXPAND_FILL
			sec.mouse_filter = MOUSE_FILTER_PASS
			sec.tooltip_text = "%s section %d: %d of %d boxes" % [spec[0], i + 1, d["cur"][i], d["max"][i]]
			var segs := _hbox(2)
			segs.add_theme_constant_override("separation", 2)
			for k in d["max"][i]:
				var seg := Panel.new()
				seg.mouse_filter = MOUSE_FILTER_IGNORE
				seg.size_flags_horizontal = SIZE_EXPAND_FILL
				seg.custom_minimum_size.y = Style.px(11)
				var lost: bool = k >= d["cur"][i]
				seg.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT if lost else spec[3], Color("#4a5868") if lost else Color.TRANSPARENT, 1 if lost else 0, 2))
				segs.add_child(seg)
			sec.add_child(segs)
			secs.add_child(sec)
		bar.add_child(secs)
		_status.add_child(bar)


func _render_guns() -> void:
	_clear(_guns)
	var n := m.guns_crew()
	var silent := not Model.SECTIONS_FIRING.has(n)
	var mod: int = Model.SECTIONS_FIRING.get(n, 0)
	var big := Style.label("Guns silent" if silent else "%d of 4 sections · %s" % [n, "±0" if mod == 0 else str(mod)], 20,
			Style.BAD_TEXT if silent or mod <= -6 else Style.FG, true)
	_guns.add_child(big)
	_guns.add_child(Style.label("No sailor section is left at the guns: neither broadside can fire." if silent
			else "Gunfire modifier for sections firing, on both broadsides.", 12.5, Style.MUTED, false, true))
	_guns.add_child(Style.label("Marines: %s." % ("muskets at the rail" if m.assigned("M") == "marine_fire" else m.task_name(m.assigned("M")).to_lower()),
			12.5, Style.MUTED, false, true))


func _render_damage(sh: Dictionary) -> void:
	_clear(_dmg_list)
	var items: Array = []
	for i in m.fires.size():
		var f: Dictionary = m.fires[i]
		var t: int = m.turn - f["started"] + 1
		var occ := m.occupants("ff:%d" % f["id"])
		items.append(["Fire %d: burning %d turn%s · 1 hull and 1 rigging a turn · %s" % [i + 1, t, "s" if t > 1 else "",
				("fought by " + occ[0]) if not occ.is_empty() else "unfought: morale check each turn"], false])
	if m.wheel:
		items.append(["Wheel shot away: one turn per turn, poor maneuvering", false])
	if m.shrouds_severed:
		items.append(["Shrouds severed: −1 MP until repaired (RS)", false])
	if m.obscured:
		items.append(["Starboard broadside −2: obscured by fallen rigging", false])
	if m.rigging_damaged:
		items.append(["Rigging boxes lost: repairable (RR)", true])
	if m.hull_damaged:
		items.append(["Hull boxes lost: repairable (RH)", true])
	_dmg_btn.text = ("▾ " if _dmg_open else "▸ ") + "DAMAGE (%d)" % items.size()
	_dmg_list.visible = _dmg_open
	for it in items:
		var row := _hbox(8)
		var dot := ColorRect.new()
		dot.color = Color("#a07a4c") if it[1] else Style.BAD
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = SIZE_SHRINK_BEGIN
		var dot_wrap := MarginContainer.new()
		dot_wrap.add_theme_constant_override("margin_top", Style.px(6))
		dot_wrap.add_child(dot)
		dot_wrap.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(dot_wrap)
		var l := Style.label(it[0], 13, Style.FG, false, true)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(l)
		_dmg_list.add_child(row)
	var _unused = sh


func _render_roster(sh: Dictionary) -> void:
	_clear(_roster)
	for id in sh["crew"].keys():
		var row := _panel(Style.box(Style.PANEL, Style.LINE, 1, 6, Style.px(4)))
		var hb := _hbox(10)
		row.add_child(hb)
		_roster.add_child(row)
		if id == "S2" and m.s2_gone:
			var empty := Panel.new()
			empty.custom_minimum_size = Vector2(Style.px(44), Style.px(44))
			empty.add_theme_stylebox_override("panel", Style.box(Color.TRANSPARENT, Style.LINE, 1, 5))
			hb.add_child(empty)
			var iv := _vbox(2)
			iv.size_flags_horizontal = SIZE_EXPAND_FILL
			iv.add_child(Style.label("S2 lost", 14, Style.FG, true))
			iv.add_child(Style.label("Section wiped out; its task was abandoned (4.B.3).", 12.5, Style.MUTED, false, true))
			hb.add_child(iv)
			continue
		# Compact row so the whole roster fits under the ship card at 1080 px: the counter's pips show
		# the boxes, so "Sailors · 3 boxes" moves to the row's tooltip.
		var c := _counter(id, Style.px(38))
		c.size_flags_vertical = SIZE_SHRINK_CENTER
		hb.add_child(c)
		var info := _vbox(0)
		info.size_flags_horizontal = SIZE_EXPAND_FILL
		info.size_flags_vertical = SIZE_SHRINK_CENTER
		hb.add_child(info)
		var t := m.assigned(id)
		var pr: Dictionary = m.progress.get(id, {})
		row.tooltip_text = "%s · %s · %d boxes" % [id, "Marines" if Model.is_marine(id) else "Sailors", sh["crew"][id]]
		info.add_child(Style.label(m.task_name(t), 14, Style.FG, true, true))
		if not pr.is_empty() and m.task_turns(pr["task"]) > 1:
			var total := m.task_turns(pr["task"])
			var now := mini(pr["done"] + 1, total)
			var prog := _hbox(8)
			prog.add_child(Style.label("Turn %d of %d" % [now, total], 13, Style.WARN, true))
			var tb := _hbox(2)
			tb.add_theme_constant_override("separation", 2)
			tb.custom_minimum_size.x = Style.px(110)
			tb.size_flags_vertical = SIZE_SHRINK_CENTER
			for k in total:
				var seg := ColorRect.new()
				seg.mouse_filter = MOUSE_FILTER_IGNORE
				seg.size_flags_horizontal = SIZE_EXPAND_FILL
				seg.custom_minimum_size.y = Style.px(6)
				seg.color = Style.OK if k < pr["done"] else Style.WARN if k == pr["done"] else Color("#3a4757")
				tb.add_child(seg)
			prog.add_child(tb)
			info.add_child(prog)
		elif t.begins_with("ff:"):
			var fi := m.fire_index(t)
			if fi >= 0:
				info.add_child(Style.label("Turn %d · until it is out" % (m.turn - m.fires[fi]["started"] + 1), 13, Style.WARN, true))
		var where := "" if t == "" or t.begins_with("ff:") else str(m.station_decks(t)[0])
		if where != "" and where != m.deck:
			var deck_name := ""
			for d in sh["decks"]:
				if d["id"] == where:
					deck_name = d["name"]
			var loc := LinkButton.new()
			loc.text = "Show on " + deck_name
			loc.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			loc.focus_mode = FOCUS_NONE
			loc.add_theme_font_size_override("font_size", Style.px(12.5))
			loc.add_theme_color_override("font_color", Style.ACCENT)
			loc.add_theme_color_override("font_hover_color", Style.ACCENT.lightened(0.2))
			loc.pressed.connect(func(): m.deck = where; _queue_render())
			info.add_child(loc)


# =====================================================================
# decks and stations
# =====================================================================

func _counter(sec: String, px_size: float) -> Control:
	var c := Counter.new()
	c.setup(sec, m.ship()["crew"][sec], px_size)
	var pr: Dictionary = m.progress.get(sec, {})
	if not pr.is_empty() and m.task_turns(pr["task"]) > 1:
		var total := m.task_turns(pr["task"])
		c.prog_text = "T%d/%d" % [mini(pr["done"] + 1, total), total]
	c.auto_mark = m.auto.get(sec, false)
	c.selected = m.selected == sec
	c.tooltip_text = "%s · %s%s" % [sec, m.task_name(m.assigned(sec)), "\nFilled in automatically: every fire must be fought" if c.auto_mark else ""]
	c.make_preview = _make_preview
	c.clicked.connect(_on_counter_clicked)
	c.context_requested.connect(_open_menu)
	return c


## Drag preview: the counter lifted, tilted and centred on the pointer.
func _make_preview(sec: String) -> Control:
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	var c := Counter.new()
	c.is_preview = true
	var s := Style.px(56)
	c.setup(sec, m.ship()["crew"][sec], s)
	c.pivot_offset = Vector2(s, s) / 2.0
	c.rotation_degrees = -4
	c.scale = Vector2(1.08, 1.08)
	c.position = -Vector2(s, s) / 2.0
	holder.add_child(c)
	return holder


func _mini(sec: String, draggable: bool) -> Control:
	var l := MiniChip.new()
	l.sec = sec
	l.draggable = draggable
	l.make_preview = _make_preview
	l.text = sec
	l.add_theme_font_size_override("font_size", Style.px(11))
	l.add_theme_font_override("font", Style.bold_font())
	l.add_theme_color_override("font_color", Style.CARD_INK)
	var sb := Style.box(Style.CARD, Style.MARINE if Model.is_marine(sec) else Style.SAILOR, 0, 3)
	sb.border_width_top = 3
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	l.add_theme_stylebox_override("normal", sb)
	l.mouse_filter = MOUSE_FILTER_STOP if draggable else MOUSE_FILTER_IGNORE
	return l


func _deck_counter_size() -> float:
	# HTML: clamp(34px, 5.4cqw, 58px) of the deck's width, in CSS px, then scaled
	var w_css := (_big_h * DeckView.PW / 1000.0) / Style.K
	return Style.px(clampf(w_css * 0.054, 34, 58))


## Station codes for the small deck cards, where full labels would wrap mid-word.
const SHORT_LABEL := {"guns": "Guns", "marine_fire": "Marines", "braces": "T", "boarders": "FB", "rr": "RR",
	"rs": "RS", "sails": "Sails", "rh": "RH"}


func _build_deck(deck: Dictionary, small: bool, portrait: bool) -> Control:
	var sh: Dictionary = m.ship()
	var dv := DeckView.new()
	dv.setup(deck, sh["gun_decks"], portrait, small)
	var csize := _deck_counter_size()
	var fs_label := 10.0 if small else 11.0
	for id in Model.STATIONS.keys():
		if not m.station_decks(id).has(deck["id"]) or not m.station_visible(id):
			continue
		var st_def: Dictionary = Model.STATIONS[id]
		var st := _station(id, small)
		var why := m.station_disabled_reason(id)
		st.disabled = why != ""
		var cap := m.capacity(id)
		var occ := m.occupants(id)
		var turns := m.task_turns(id)
		st.content.add_child(_station_header(SHORT_LABEL.get(id, st_def["code"]) if small else st_def["label"] + (" · " + st_def["code"] if st_def["code"] != "" else ""),
				"" if small else "%d/%d%s" % [occ.size(), cap, (" · %d turns" % turns) if turns else ""], fs_label,
				_rect_width_px(st_def["rect"], small, portrait)))
		if id == "sails" and not small:
			var opts: Array = Model.SAIL_CHANGES.get(m.sail, [])
			var sel := OptionButton.new()
			sel.focus_mode = FOCUS_NONE
			sel.fit_to_longest_item = false
			sel.clip_text = true
			sel.add_theme_font_size_override("font_size", Style.px(12))
			for i in opts.size():
				var o: Dictionary = opts[i]
				sel.add_item("%s → %s (%d CS, %d turn%s)" % [m.sail, o["to"], o["cs"], o["turns"], "s" if o["turns"] > 1 else ""])
				if o["to"] == m.sail_target:
					sel.select(i)
			sel.tooltip_text = "Sail change target"
			sel.item_selected.connect(func(i): m.set_sail_target(opts[i]["to"]); _queue_render())
			st.content.add_child(sel)
		var slots := _slots(small)
		for s in occ:
			slots.add_child(_mini(s, false) if small else _counter(s, csize))
		st.content.add_child(slots)
		if not small:
			if why != "":
				# Short note on the station; the full rule is in the tooltip.
				st.content.add_child(_station_note(("Not at " + m.sail) if id == "rr" else why, true))
			elif id == "rh":
				st.content.add_child(_station_note("Cancelled if the ship moves more than 4 MPs (8.F.3b).", false))
			elif id == "guns":
				st.content.add_child(_station_note(st_def["note"], false))
		st.tooltip_text = why
		dv.place(st, st_def["rect"])
	# Fire parties: one station per fire (FF1, FF2 …) under Marine fire on the quarterdeck.
	# Two fires side by side; more wrap to two rows and show compact chips.
	if deck["id"] == "upper" and not m.fires.is_empty():
		var z: Array = Model.FIRE_ZONE.duplicate()
		var n := m.fires.size()
		var gap := 6.0
		var cols := mini(n, 2)
		var rows := ceili(n / float(cols))
		var long_zone := n > 2 and not m.station_visible("rs")
		if long_zone:
			# More than two fires: run the area forward along the deck (up to Rigging repair), two
			# stations across the beam, so each keeps room for a full counter.
			z[2] = 334
			rows = 2
			cols = ceili(n / 2.0)
		var w: float = (z[2] - gap * (cols - 1)) / cols
		var h: float = (z[3] - gap * (rows - 1)) / rows
		var cell_len_px: float = w / 1000.0 * _big_h
		var compact := small or (n > 2 and (not long_zone or cell_len_px < csize + Style.px(30)))
		for i in n:
			var f: Dictionary = m.fires[i]
			var key := "ff:%d" % f["id"]
			var occ := m.occupants(key)
			var burnt: int = m.turn - f["started"] + 1
			var st := _station(key, small)
			st.fire = true
			st.unfought = occ.is_empty()
			st.content.add_child(_station_header(("FF%d" % (i + 1)) if small or n > 2 else "Fire %d · FF%d" % [i + 1, i + 1],
					("%d turn%s" % [burnt, "s" if burnt > 1 else ""]) if n < 3 and not small else "", fs_label,
					_rect_width_px([0, 0, w, h], small, portrait)))
			var slots := _slots(small)
			for s in occ:
				slots.add_child(_mini(s, true) if compact else _counter(s, csize))
			st.content.add_child(slots)
			# Narrow stations (more than two fires) rely on the red colour and the tooltip instead.
			if occ.is_empty() and not compact and n <= 2:
				st.content.add_child(_station_note("Unfought: morale check each turn", true))
			if occ.is_empty():
				st.tooltip_text = "Unfought: a morale check every turn (8.E.6). Drag a section here."
			var col := i % cols
			var row := floori(i / float(cols))
			if long_zone:
				col = floori(i / 2.0)
				row = i % 2
			dv.place(st, [z[0] + col * (w + gap), z[1] + row * (h + gap), w, h])
	if not small:
		if deck["id"] == "upper" and m.wheel:
			dv.add_marker(262, 148, "Wheel shot away")
		if deck["id"] == "upper" and m.shrouds_severed:
			dv.add_marker(470, 40, "Shrouds severed")
		if m.obscured and sh["gun_decks"].has(deck["id"]):
			dv.add_marker(500, 300, "Stbd broadside −2 (obscured)")
		if deck["id"] == "upper" and m.rigging_damaged:
			dv.add_marker(870, 180, "Rigging section 1: %d/%d" % [sh["rig"]["cur"][0], sh["rig"]["max"][0]], true)
		if deck["id"] == "orlop" and m.hull_damaged:
			dv.add_marker(200, 180, "Hull section 1: %d/%d" % [sh["hull"]["cur"][0], sh["hull"]["max"][0]], true)
	return dv


func _station(target: String, small: bool) -> Control:
	var st := Station.new()
	st.target = target
	st.small = small
	st.ov = self
	st.set_padding(2 if small else Style.px(4))
	return st


## Pixel width of a station's content from its landscape rect.
func _rect_width_px(rect: Array, small: bool, portrait: bool) -> float:
	var pad := 2.0 * ((2 if small else Style.px(4)) + 2)
	if portrait:
		return rect[3] * DeckView.PK * (_big_h * DeckView.PW / 1000.0) / DeckView.PW - pad
	return rect[2] * (Style.px(300) - Style.px(8) * 2 - 3) / 1000.0 - pad


## Label and count side by side, as the HTML's `.sl`; stacked when the station is too narrow.
func _station_header(left: String, right: String, fs_css: float, avail: float) -> Control:
	var font := Style.bold_font()
	var fs := Style.px(fs_css)
	var need := font.get_string_size(left.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x \
			+ (font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + Style.px(6) if right != "" else 0.0)
	var h: BoxContainer
	if need <= avail:
		h = _hbox(6)
	else:
		h = _vbox(0)
	var l := Style.label(left.to_upper(), fs_css, Style.CARD_INK, true, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(l)
	if right != "":
		var r := Style.label(right, fs_css, Color(Style.CARD_INK, 0.75), true)
		r.size_flags_vertical = SIZE_SHRINK_BEGIN
		h.add_child(r)
	return h


func _station_note(text: String, why: bool) -> Label:
	return Style.label(text, 11.5, Color("#3a2a17"), why, true)


func _slots(small: bool) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.mouse_filter = MOUSE_FILTER_IGNORE
	f.add_theme_constant_override("h_separation", 2 if small else Style.px(4))
	f.add_theme_constant_override("v_separation", 2 if small else Style.px(4))
	f.size_flags_vertical = SIZE_EXPAND_FILL
	return f


func _build_deck_card(d: Dictionary) -> Control:
	var cur: bool = d["id"] == m.deck
	var card := DeckCard.new()
	card.deck_id = d["id"]
	card.ov = self
	var sb := Style.box(Color("#16273a") if cur else Color("#121b25"), Style.ACCENT if cur else Style.LINE, 2 if cur else 1, 6, Style.px(8))
	card.add_theme_stylebox_override("panel", sb)
	card.tooltip_text = "Enlarge " + d["name"]
	var v := _vbox(6)
	card.add_child(v)
	var nm := _hbox(6)
	nm.add_child(Style.label(d["name"], 13, Style.FG, true))
	# the note shrinks with an ellipsis, so a long one never widens the side column
	var note := Style.label("· " + ("shown large" if cur else d["note"]), 12, Style.ACCENT if cur else Style.MUTED)
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.size_flags_horizontal = SIZE_EXPAND_FILL
	note.tooltip_text = d["note"]
	nm.add_child(note)
	nm.add_child(_deck_badges(d))
	v.add_child(nm)
	var w := Style.px(300) - Style.px(8) * 2 - (4 if cur else 2)
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(w, w * 360.0 / 1000.0)
	var dv := _build_deck(d, true, false)
	dv.size = holder.custom_minimum_size
	holder.add_child(dv)
	v.add_child(holder)
	return card


func _deck_badges(d: Dictionary) -> Control:
	var sh: Dictionary = m.ship()
	var box := _hbox(3)
	box.size_flags_vertical = SIZE_SHRINK_CENTER
	var here: Array = Model.STATIONS.keys().filter(func(st): return m.station_visible(st) and m.station_decks(st).has(d["id"]))
	var n: int = m.sections().filter(func(s): return here.has(m.assigned(s)) and not Model.STATIONS[m.assigned(s)].get("is_default", false)).size()
	if n:
		box.add_child(_badge("%d on tasks" % n, Style.BTN, Style.FG, "Sections on tasks on this deck"))
	if d["id"] == "upper" and not m.fires.is_empty():
		box.add_child(_badge("%d fire%s" % [m.fires.size(), "s" if m.fires.size() > 1 else ""], Style.FIRE, Color("#1b0d05"), "Fires aboard"))
	if d["id"] == "upper" and (m.wheel or m.shrouds_severed):
		box.add_child(_badge("damage", Style.BAD, Color.WHITE, "Damage on this deck"))
	if d["id"] == "orlop" and m.hull_damaged:
		box.add_child(_badge("hull", Style.BAD, Color.WHITE, "Hull damage to repair"))
	if m.obscured and sh["gun_decks"][0] == d["id"]:
		box.add_child(_badge("−2 stbd", Style.BAD, Color.WHITE, "Obscured broadside"))
	return box


func _badge(text: String, bg: Color, fg: Color, tip: String) -> Label:
	var l := Style.label(text, 12, fg, true)
	var sb := Style.box(bg, Color.TRANSPARENT, 0, Style.px(9))
	sb.content_margin_left = Style.px(5)
	sb.content_margin_right = Style.px(5)
	l.add_theme_stylebox_override("normal", sb)
	l.tooltip_text = tip
	l.mouse_filter = MOUSE_FILTER_PASS
	return l


# =====================================================================
# interaction
# =====================================================================

func note_drop_hover(o: Object) -> void:
	drop_hover_id = o.get_instance_id() if o != null else 0


## Drop queries that reach the root are over no station or deck card.
func _can_drop_data(_at: Vector2, _data: Variant) -> bool:
	drop_hover_id = 0
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_hover_id = 0


## Valid/invalid highlight for a station: the dragged counter, else the selected one.
func mark_for(target: String) -> String:
	var sec := m.selected
	if get_viewport().gui_is_dragging():
		var d = get_viewport().gui_get_drag_data()
		sec = d.get("sec", "") if d is Dictionary else ""
	if sec == "" or m.assigned(sec) == target:
		return ""
	return "invalid" if m.refusal(sec, target) != "" else "valid"


func drop_on(target: String, sec: String) -> void:
	m.selected = ""
	m.assign(sec, target)
	_queue_render()


## The second click of click-then-click. Returns true when it was handled.
func station_clicked(target: String) -> bool:
	if m.selected == "":
		return false
	m.assign(m.selected, target)
	_queue_render()
	return true


func deck_card_clicked(deck_id: String) -> void:
	m.deck = deck_id
	_queue_render()


func _on_counter_clicked(sec: String) -> void:
	m.selected = "" if m.selected == sec else sec
	_queue_render()


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and m.selected != "":
		m.selected = ""
		_queue_render()


func _open_menu(sec: String, at: Vector2) -> void:
	_menu.clear()
	_menu_sec = sec
	_menu_targets = m.menu_targets()
	_menu.add_separator(sec + " · assign to")
	for i in _menu_targets.size():
		var t: String = _menu_targets[i]
		var cur := m.assigned(sec) == t
		var why := "" if cur else m.refusal(sec, t)
		var turns := m.task_turns(t)
		_menu.add_item(m.task_name(t) + (" · %d turns" % turns if turns else "") + ("   (current)" if cur else ""), i)
		var idx := _menu.get_item_index(i)
		_menu.set_item_disabled(idx, why != "" or cur)
		_menu.set_item_tooltip(idx, why if why != "" else "Current task" if cur else "")
	_menu.reset_size()
	var vp := get_viewport_rect().size
	var pos := Vector2(minf(at.x, vp.x - _menu.size.x - 8), minf(at.y, vp.y - _menu.size.y - 8))
	_menu.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))


func _on_menu_id(id: int) -> void:
	if id >= 0 and id < _menu_targets.size():
		m.assign(_menu_sec, _menu_targets[id])
		_queue_render()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_ESCAPE:
		if m.selected != "":
			m.selected = ""
		elif m.open:
			m.open = false
		_queue_render()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_C:
		m.open = not m.open
		_queue_render()
		get_viewport().set_input_as_handled()


# ---------------- message bar ----------------

func _on_message(text: String, kind: String, actions: Array) -> void:
	if kind == "clear":
		_clear_message()
		return
	_clear(_msg)
	var sb := Style.box(Color("#26313f"), Style.LINE, 1, 6)
	sb.border_width_left = 4
	sb.border_color = Style.BAD if kind == "bad" else Style.WARN
	sb.content_margin_left = Style.px(14)
	sb.content_margin_right = Style.px(14)
	sb.content_margin_top = Style.px(10)
	sb.content_margin_bottom = Style.px(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = Style.px(12)
	sb.shadow_offset = Vector2(0, 6)
	_msg.add_theme_stylebox_override("panel", sb)
	var h := _hbox(12)
	_msg.add_child(h)
	var l := Style.label(text, 14, Style.FG, false, true)
	l.custom_minimum_size.x = Style.px(380)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(l)
	var acts := _hbox(6)
	acts.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(acts)
	var list := actions if not actions.is_empty() else [{"label": "OK", "id": "ok"}]
	for a in list:
		var b := Style.button(a["label"], a.get("primary", false))
		b.add_theme_font_size_override("font_size", Style.px(13))
		var aid: String = a["id"]
		b.pressed.connect(func(): _on_message_action(aid))
		acts.add_child(b)
	_msg.custom_minimum_size.x = minf(Style.px(640), _stage.size.x - Style.px(32))
	_msg.visible = true
	_msg.reset_size()
	_msg.offset_left = -_msg.custom_minimum_size.x / 2.0
	_msg.offset_right = _msg.custom_minimum_size.x / 2.0
	if actions.is_empty():
		_msg_timer.start(4.2)
	else:
		_msg_timer.stop()


func _on_message_action(id: String) -> void:
	match id:
		"confirm_move":
			m.confirm_pending()
		"cancel_move":
			m.pending = {}
			_clear_message()
		_:
			_clear_message()
	_queue_render()


func _clear_message() -> void:
	_msg_timer.stop()
	_msg.visible = false


# =====================================================================
# small inner controls
# =====================================================================

## A compact chip (".mini"): small decks and three-plus fires. Draggable on fire stations.
class MiniChip extends Label:
	var sec := ""
	var draggable := false
	var make_preview: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
		if not draggable:
			return null
		set_drag_preview(make_preview.call(sec))
		return {"sec": sec}


## A deck in the side list: click to show it large; hovering it while dragging
## for 450 ms switches the enlarged deck, as in the HTML.
class DeckCard extends PanelContainer:
	var deck_id := ""
	var ov: Object
	var _hover_t := 0.0
	var _over := false

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			accept_event()
			ov.deck_card_clicked(deck_id)

	func _can_drop_data(_at: Vector2, _data: Variant) -> bool:
		ov.note_drop_hover(self)
		return false

	func _process(delta: float) -> void:
		var hov_id: int = ov.drop_hover_id
		var hov: Object = instance_from_id(hov_id) if hov_id != 0 else null
		var over: bool = get_viewport().gui_is_dragging() and hov is Node and (hov == self or is_ancestor_of(hov))
		if over != _over:
			_over = over
			_hover_t = 0.0
			queue_redraw()
		if over:
			_hover_t += delta
			if _hover_t >= 0.45 and ov.m.deck != deck_id:
				_hover_t = -INF
				ov.deck_card_clicked(deck_id)

	func _draw() -> void:
		if _over:
			draw_style_box(Style.box(Color.TRANSPARENT, Style.WARN, 1, 6), Rect2(Vector2.ZERO, size))
