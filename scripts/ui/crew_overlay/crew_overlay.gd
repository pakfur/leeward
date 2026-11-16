class_name CrewOverlay
extends Control
## CrewOverlay - the crew & damage overlay over the map (crew-tasks spec §4), rebuilt from the
## approved Godot prototype (prototypes/crew_overlay/crew_overlay_proto.gd): header with the
## Automatic switch, the selected deck drawn large (bow up), every deck as a small card, the
## tactical picture, the message bar and the assign-to menu. Stations come from CrewRules.stations
## through the CrewOverlayClient; the overlay draws what it is given.
##
## View only: every change is a request through the client (player_plot_crew,
## player_set_crew_auto); the redraw uses the server's normalized plan.

const Style = preload("res://scripts/ui/crew_overlay/crew_style.gd")

## The fire zone when fires burn (spec §4.3); phase 4 lists fire stations.
const FIRE_ZONE_ID := "fire_zone"

var client: CrewOverlayClient = null

var _shade: ColorRect
var _ov_title: Label
var _ov_sub: Label
var _ro_note: Label
var _auto_btn: CheckButton
var _help_btn: Button
var _reset_btn: Button
var _deck_name: Label
var _big_host: Control
var _big_deck: Control
var _other_decks: VBoxContainer
var _inset: CrewTacticalInset
var _caption: Label
var _msg: PanelContainer
var _msg_timer: Timer
var _menu: PopupMenu
var _menu_section := -1
var _menu_targets: Array = []
var _render_queued := false
var _big_h := 0.0
## The station or deck card under a dragged counter (set from drop queries).
var drop_hover_id := 0
# Per-render caches (one server query per render).
var _plan: Dictionary = {}
var _stations: Array[Dictionary] = []
var _ship: ShipState = null
var _layout: Dictionary = {}


func setup(p_client: CrewOverlayClient) -> void:
	client = p_client
	client.changed.connect(_queue_render)
	client.message.connect(_on_message)
	client.open_changed.connect(func(on: bool): visible = on; _queue_render())
	visible = client.is_open


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()
	_queue_render()


## Esc: first drops a picked-up counter, then closes (spec §4.1). Returns true when handled.
func handle_escape() -> bool:
	if not visible or client == null:
		return false
	if _msg.visible and not client.pending.is_empty():
		client.cancel_pending()
		return true
	if client.drop_pick():
		return true
	client.close()
	return true


# =====================================================================
# scaffolding
# =====================================================================

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


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0.039, 0.059, 0.082, 0.97)
	_shade.set_anchors_preset(PRESET_FULL_RECT)
	_shade.mouse_filter = MOUSE_FILTER_STOP
	_shade.gui_input.connect(_on_background_input)
	add_child(_shade)
	var ov := _vbox(0)
	ov.set_anchors_preset(PRESET_FULL_RECT)
	add_child(ov)

	# header
	var hsb := Style.box(Color.TRANSPARENT, Style.LINE, 0, 0)
	hsb.border_width_bottom = 1
	hsb.content_margin_left = Style.px(18)
	hsb.content_margin_right = Style.px(18)
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
	_ro_note = Style.label("", 13, Style.WARN)
	tv.add_child(_ro_note)
	hh.add_child(tv)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	hh.add_child(spacer)
	_auto_btn = CheckButton.new()
	_auto_btn.name = "AutomaticSwitch"
	_auto_btn.focus_mode = FOCUS_NONE
	_auto_btn.add_theme_font_size_override("font_size", Style.px(14))
	_auto_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	_auto_btn.toggled.connect(_on_auto_toggled)
	hh.add_child(_auto_btn)
	_help_btn = Style.button("?")
	_help_btn.tooltip_text = "\n".join(CrewOverlayText.AUTO_RULES)
	_help_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	_help_btn.pressed.connect(func(): _on_message("Automatic crew rules:\n" + "\n".join(CrewOverlayText.AUTO_RULES), "info", []))
	hh.add_child(_help_btn)
	_reset_btn = Style.button("Reset to defaults")
	_reset_btn.name = "ResetButton"
	_reset_btn.tooltip_text = "Put every section back to its default task (tasks in progress stay)"
	_reset_btn.size_flags_vertical = SIZE_SHRINK_CENTER
	_reset_btn.pressed.connect(func(): client.reset_defaults())
	hh.add_child(_reset_btn)
	var done := Style.button("Done  (Esc)", true)
	done.name = "DoneButton"
	done.size_flags_vertical = SIZE_SHRINK_CENTER
	done.pressed.connect(func(): client.close())
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
	_inset = CrewTacticalInset.new()
	_inset.custom_minimum_size = Vector2(Style.px(300) - 2, (Style.px(300) - 2) * CrewTacticalInset.VIEW_H / CrewTacticalInset.VIEW_W)
	iv.add_child(_inset)
	var capsb := Style.box(Color.TRANSPARENT, Style.LINE, 0, 0)
	capsb.border_width_top = 1
	capsb.content_margin_left = Style.px(7)
	capsb.content_margin_top = Style.px(5)
	capsb.content_margin_bottom = Style.px(5)
	var cap := _panel(capsb)
	_caption = Style.label("", 11.5, Style.MUTED, false, true)
	cap.add_child(_caption)
	iv.add_child(cap)

	_msg = PanelContainer.new()
	_msg.visible = false
	_msg.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_msg.grow_horizontal = GROW_DIRECTION_BOTH
	_msg.grow_vertical = GROW_DIRECTION_BEGIN
	_msg.offset_bottom = -Style.px(18)
	add_child(_msg)

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


func _size_big_deck() -> void:
	if _big_deck == null or not is_instance_valid(_big_deck):
		return
	var h := maxf(Style.px(320), _big_host.size.y)
	var w := roundf(h * CrewDeckView.PW / 1000.0)
	_big_deck.position = Vector2.ZERO
	_big_deck.size = Vector2(w, h)
	if _big_host.custom_minimum_size.x != w:
		_big_host.custom_minimum_size.x = w
	if absf(h - _big_h) > 1.0:
		_big_h = h
		_queue_render()  # counter size follows the deck width


# =====================================================================
# render
# =====================================================================

func _queue_render() -> void:
	if not _render_queued and is_inside_tree():
		_render_queued = true
		_render.call_deferred()


func _render() -> void:
	_render_queued = false
	if client == null or not visible:
		return
	if not sync_cache():
		return
	var decks: Array = _layout.get("decks", [])
	if not decks.any(func(d): return d["id"] == client.deck):
		client.deck = "upper"
	var deck: Dictionary = {}
	for d in decks:
		if d["id"] == client.deck:
			deck = d
	if deck.is_empty():
		return
	var editable := client.editable()
	_ov_title.text = _ship.ship_name
	_ov_sub.text = CrewOverlayText.header_subtitle(_ship)
	_ro_note.text = client.read_only_note()
	_ro_note.visible = _ro_note.text != ""
	_auto_btn.set_pressed_no_signal(_ship.crew_auto)
	_auto_btn.text = "Automatic crew: %s" % ("on" if _ship.crew_auto else "off")
	_auto_btn.disabled = not editable
	_auto_btn.tooltip_text = "On: the ship's officers place the sections by fixed rules (?). Off: you place them."
	_reset_btn.visible = not _ship.crew_auto
	_reset_btn.disabled = not editable

	_deck_name.text = deck["name"]
	if _big_deck != null and is_instance_valid(_big_deck):
		_big_host.remove_child(_big_deck)
		_big_deck.queue_free()
	_big_deck = _build_deck(deck, false, true)
	_big_host.add_child(_big_deck)
	_size_big_deck()

	_clear(_other_decks)
	var gun_decks: Array = _layout.get("gun_decks", [])
	var order: Array = decks.filter(func(d): return d["id"] == "upper") + decks.filter(func(d): return d["id"] == "orlop") \
			+ decks.filter(func(d): return gun_decks.has(d["id"]))
	for d in order:
		_other_decks.add_child(_build_deck_card(d))

	_inset.show_ships(_ship, client.game_state.get_all_ships(),
		client.game_state.environment.wind_direction if client.game_state.environment else -1)
	_caption.text = CrewOverlayText.tactical_caption(_ship, client.game_state.get_all_ships(),
		client.game_state.fire_geometry, client.game_state.environment)


# =====================================================================
# decks and stations
# =====================================================================

## Reads the ship, plan and stations from the client (one query per render).
func sync_cache() -> bool:
	_ship = client.ship() if client else null
	if _ship == null:
		return false
	_plan = client.plan()
	_stations = client.stations()
	_layout = CrewDeckLayouts.layout_for(_ship.ship_type)
	return true


## A counter for the planning panel's roster (same face, drag and click as on the deck).
func roster_counter(section: int, px_size: float) -> Control:
	sync_cache()
	return _counter(section, px_size)


func _entry(section: int) -> Dictionary:
	return _plan.get("assignments", {}).get(section, {})


func _station_by_id(id: String) -> Dictionary:
	for st in _stations:
		if st["id"] == id:
			return st
	return {}


func _counter(section: int, px_size: float) -> Control:
	var c := CrewCounterToken.new()
	c.setup(section, _ship.section_boxes(section), px_size)
	var entry := _entry(section)
	c.prog_text = CrewOverlayText.progress_tag(_ship, section, entry)
	var st_id := CrewRules.station_of(section, entry)
	var is_default := st_id == CrewRules.STATION_GUNS or st_id == CrewRules.STATION_MARINE_FIRE
	c.auto_mark = (_plan.get("auto", []) as Array).has(section) and not is_default
	var st := _station_by_id(st_id)
	c.locked = (st.get("locked", []) as Array).has(section)
	c.disorganized = _ship.is_disorganized(section)
	c.selected = client.selected == section
	c.draggable = client.editable()
	var tip := "%s · %s" % [CrewOverlayText.section_name(section), CrewOverlayText.task_title(section, entry)]
	if c.auto_mark:
		tip += "\nPlaced by the rules (AUTO)"
	if c.locked:
		tip += "\n" + (CrewOverlayText.LOCKED_AUTO if _ship.crew_auto else "Locked: %s" % str(st.get("note", "")))
	c.tooltip_text = tip
	c.make_preview = _make_preview
	c.clicked.connect(_on_counter_clicked)
	c.context_requested.connect(_open_menu)
	return c


## Drag preview: the counter lifted, tilted and centred on the pointer.
func _make_preview(section: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	var c := CrewCounterToken.new()
	c.is_preview = true
	var s := Style.px(56)
	c.setup(section, _ship.section_boxes(section) if _ship else 1, s)
	c.pivot_offset = Vector2(s, s) / 2.0
	c.rotation_degrees = -4
	c.scale = Vector2(1.08, 1.08)
	c.position = -Vector2(s, s) / 2.0
	holder.add_child(c)
	return holder


func _mini(section: int) -> Control:
	var l := Label.new()
	l.text = CrewOverlayText.section_name(section)
	l.add_theme_font_size_override("font_size", Style.px(11))
	l.add_theme_font_override("font", Style.bold_font())
	l.add_theme_color_override("font_color", Style.CARD_INK)
	var sb := Style.box(Style.CARD, Style.MARINE if section == ShipState.MARINES else Style.SAILOR, 0, 3)
	sb.border_width_top = 3
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	l.add_theme_stylebox_override("normal", sb)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _deck_counter_size() -> float:
	# HTML: clamp(34px, 5.4cqw, 58px) of the deck's width, in CSS px, then scaled
	var w_css := (_big_h * CrewDeckView.PW / 1000.0) / Style.K
	return Style.px(clampf(w_css * 0.054, 34, 58))


func _station_decks(id: String) -> Array:
	if id.begins_with(CrewRules.STATION_FIRE_PREFIX):
		return CrewDeckLayouts.station_decks(_layout, FIRE_ZONE_ID)
	return CrewDeckLayouts.station_decks(_layout, id)


func _station_rect(st: Dictionary) -> Array:
	var id: String = st["id"]
	if not id.begins_with(CrewRules.STATION_FIRE_PREFIX):
		return CrewDeckLayouts.station_rect(id)
	# Fires split the fire zone: up to two side by side, more in two rows.
	var z := CrewDeckLayouts.station_rect(FIRE_ZONE_ID)
	var fires := _stations.filter(func(s): return (s["id"] as String).begins_with(CrewRules.STATION_FIRE_PREFIX) \
		and not s.get("menu_only", false))
	var n := fires.size()
	var i := fires.find(st)
	var cols := mini(n, 2)
	var rows := ceili(n / float(maxi(1, cols)))
	var gap := 6.0
	var w: float = (z[2] - gap * (cols - 1)) / cols
	var h: float = (z[3] - gap * (rows - 1)) / rows
	return [z[0] + (i % cols) * (w + gap), z[1] + floori(i / float(cols)) * (h + gap), w, h]


func _build_deck(deck: Dictionary, small: bool, portrait: bool) -> Control:
	var dv := CrewDeckView.new()
	dv.setup(deck, _layout.get("gun_decks", []), portrait, small)
	var csize := _deck_counter_size()
	var fs_label := 10.0 if small else 11.0
	for st in _stations:
		var id: String = st["id"]
		if not _station_decks(id).has(deck["id"]) or st.get("menu_only", false):
			continue
		var rect := _station_rect(st)
		if rect.size() < 4:
			continue
		var panel := _station(id, small)
		var why: String = st.get("disabled_reason", "")
		panel.disabled = why != ""
		panel.fire = not (st.get("fire", {}) as Dictionary).is_empty()
		var occ: Array = st.get("occupants", [])
		panel.unfought = panel.fire and occ.is_empty()
		var code: String = st.get("code", "")
		var title: String = st["short"] if small else st["label"] + (" · " + code if code != "" and code != SailController.CODE and not panel.fire else "")
		var right := ""
		if not small:
			var cap: int = st.get("capacity", 0)
			var turns: int = st.get("turns", 0)
			if id == CrewRules.STATION_BRACES:
				right = _braces_header(occ.size())
			elif panel.fire:
				var age := int(st["fire"].get("age", 0))
				right = "burning %d turn%s" % [age, "" if age == 1 else "s"] if age > 0 else "breaks out"
			elif cap > 0:
				right = "%d/%d%s" % [occ.size(), cap, (" · %d turn%s" % [turns, "" if turns == 1 else "s"]) if turns > 0 else ""]
		panel.content.add_child(_station_header(title, right, fs_label, _rect_width_px(rect, small, portrait)))
		if id == CrewRules.STATION_SAILS and not small:
			panel.content.add_child(_sail_picker(st))
		var slots := _slots(small)
		for s in occ:
			slots.add_child(_mini(int(s)) if small else _counter(int(s), csize))
		panel.content.add_child(slots)
		if not small:
			var warn: String = st.get("warning", "")
			if why != "":
				panel.content.add_child(_station_note(why, true))
			elif warn != "":
				panel.content.add_child(_station_note(warn, true))
			elif id == CrewRules.STATION_GUNS or id == CrewRules.STATION_REORGANIZING or id == CrewRules.STATION_RH or (id == CrewRules.STATION_MARINE_FIRE and str(st.get("note", "")).begins_with("Marines held back")):
				panel.content.add_child(_station_note(st.get("note", ""), false))
		panel.tooltip_text = why if why != "" else str(st.get("warning", "")) if str(st.get("warning", "")) != "" else str(st.get("note", ""))
		if id == CrewRules.STATION_BRACES:
			panel.tooltip_text += "\n" + _braces_tooltip()
		dv.place(panel, rect)
	if not small:
		_add_markers(dv, deck)
	return dv


func _braces_header(n: int) -> String:
	var mr = client.game_state.get("movement_resolver")
	if mr == null:
		return "%d/3" % n
	return "%d/3 · %d %%" % [n, roundi(mr.tacking_chance(_ship, n) * 100.0)]


func _braces_tooltip() -> String:
	var mr = client.game_state.get("movement_resolver")
	if mr == null:
		return ""
	var parts: PackedStringArray = []
	for n in range(TackCrewHandler.max_sections() + 1):
		parts.append("%d at the braces: %d %%" % [n, roundi(mr.tacking_chance(_ship, n) * 100.0)])
	return "Tacking chance: " + ", ".join(parts)


func _sail_picker(st: Dictionary) -> Control:
	var sel := OptionButton.new()
	sel.name = "SailTargetPicker"
	sel.focus_mode = FOCUS_NONE
	sel.fit_to_longest_item = false
	sel.clip_text = true
	sel.add_theme_font_size_override("font_size", Style.px(12))
	var choices: Array = st.get("choices", [])
	var target: String = st.get("target", "")
	var targets: Array = []
	if _ship.has_sail_change():
		sel.add_item("→ %s (in progress)" % target)
		sel.disabled = true
		return sel
	sel.add_item("No sail change")
	targets.append("")
	for c in choices:
		sel.add_item(c["text"])
		targets.append(c["target"])
	sel.select(maxi(0, targets.find(target)))
	sel.disabled = not client.editable() or str(st.get("disabled_reason", "")) != ""
	sel.tooltip_text = "The sail change ordered (an order: it stays live with Automatic on)"
	sel.item_selected.connect(func(i): client.set_sail_target(targets[i]))
	return sel


func _add_markers(dv: CrewDeckView, deck: Dictionary) -> void:
	var id: String = deck["id"]
	var gun_decks: Array = _layout.get("gun_decks", [])
	var mast_y := [40.0, 320.0]
	var mast_k := 0
	for effect in _ship.critical_effects:
		var eid := str(effect.get("id", ""))
		if id == "upper":
			match eid:
				"shrouds_severed", "braces_cut", "lines_jammed", "signal_halyards_cut", "sheets_cut":
					var text: String = {"shrouds_severed": "Shrouds severed", "braces_cut": "Braces cut",
						"lines_jammed": "Lines jammed", "signal_halyards_cut": "Signal halyards cut",
						"sheets_cut": "Sheets cut"}[eid]
					dv.add_marker(470.0 + 130.0 * floori(mast_k / 2.0), mast_y[mast_k % 2], text)
					mast_k += 1
				"rudder_jammed":
					dv.add_marker(60, 140, "Rudder jammed")
		if eid == "broadside_obscured" and gun_decks.size() > 0 and gun_decks[0] == id:
			var side := int(effect.get("side", -1))
			dv.add_marker(500, 300 if side == ShipState.STARBOARD else 60,
				"%s broadside −2 (obscured)" % ("Stbd" if side == ShipState.STARBOARD else "Port"))
	if id == "upper" and _ship.wheel_shot_away:
		dv.add_marker(262, 148, "Wheel shot away")
	if id == "upper" and _ship.rudder_destroyed:
		dv.add_marker(60, 220, "Rudder destroyed")
	if id == "upper" and _ship.missing_boxes("rigging") > 0:
		var r := _taking_damage(_ship.rigging_current_hp)
		if r >= 0 and _ship.ship:
			dv.add_marker(870, 180, "Rigging section %d: %d/%d" % [r + 1, _ship.rigging_current_hp[r], _ship.ship.rigging_hp[r]], true)
	if id == "orlop" and _ship.missing_boxes("hull") > 0:
		var h := _taking_damage(_ship.hull_current_hp)
		if h >= 0 and _ship.ship:
			dv.add_marker(200, 180, "Hull section %d: %d/%d" % [h + 1, _ship.hull_current_hp[h], _ship.ship.hull_hp[h]], true)


## The section now taking damage: the lowest-numbered one with boxes.
static func _taking_damage(boxes: Array) -> int:
	for i in boxes.size():
		if int(boxes[i]) > 0:
			return i
	return -1


func _station(target: String, small: bool) -> CrewStationPanel:
	var st := CrewStationPanel.new()
	st.target = target
	st.small = small
	st.ov = self
	st.set_padding(2 if small else Style.px(4))
	return st


## Pixel width of a station's content from its landscape rect.
func _rect_width_px(rect: Array, small: bool, portrait: bool) -> float:
	var pad := 2.0 * ((2 if small else Style.px(4)) + 2)
	if portrait:
		return rect[3] * CrewDeckView.PK * (_big_h * CrewDeckView.PW / 1000.0) / CrewDeckView.PW - pad
	return rect[2] * (Style.px(300) - Style.px(8) * 2 - 3) / 1000.0 - pad


## Label and count side by side; stacked when the station is too narrow.
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
	var cur: bool = d["id"] == client.deck
	var card := DeckCard.new()
	card.deck_id = d["id"]
	card.name = "DeckCard_" + str(d["id"])
	card.ov = self
	var sb := Style.box(Color("#16273a") if cur else Color("#121b25"), Style.ACCENT if cur else Style.LINE, 2 if cur else 1, 6, Style.px(8))
	card.add_theme_stylebox_override("panel", sb)
	card.tooltip_text = "Enlarge " + d["name"]
	var v := _vbox(6)
	card.add_child(v)
	var nm := _hbox(6)
	nm.add_child(Style.label(d["name"], 13, Style.FG, true))
	var deck_note := CrewOverlayText.deck_note(d, _ship.ship.armament if _ship.ship else {})
	var note := Style.label("· " + ("shown large" if cur else deck_note), 12, Style.ACCENT if cur else Style.MUTED)
	note.clip_text = true
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.size_flags_horizontal = SIZE_EXPAND_FILL
	note.tooltip_text = deck_note
	note.visible = cur or deck_note != ""
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
	var box := _hbox(3)
	box.size_flags_vertical = SIZE_SHRINK_CENTER
	var n := 0
	for st in _stations:
		var id: String = st["id"]
		if id == CrewRules.STATION_GUNS or id == CrewRules.STATION_MARINE_FIRE or not _station_decks(id).has(d["id"]):
			continue
		n += (st.get("occupants", []) as Array).size()
	if n:
		box.add_child(_badge("%d on tasks" % n, Style.BTN, Style.FG, "Sections on tasks on this deck"))
	var fires := _stations.filter(func(s): return not (s.get("fire", {}) as Dictionary).is_empty()).size()
	if d["id"] == "upper" and fires > 0:
		box.add_child(_badge("%d fire%s" % [fires, "s" if fires > 1 else ""], Style.FIRE, Color("#1b0d05"), "Fires aboard"))
	if d["id"] == "upper" and (_ship.wheel_shot_away or _ship.rudder_destroyed or _ship.critical_effects.any(
			func(e): return str(e.get("id", "")) != "broadside_obscured")):
		box.add_child(_badge("damage", Style.BAD, Color.WHITE, "Damage on this deck"))
	if d["id"] == "orlop" and _ship.missing_boxes("hull") > 0:
		box.add_child(_badge("hull", Style.BAD, Color.WHITE, "Hull boxes lost"))
	var gun_decks: Array = _layout.get("gun_decks", [])
	if not gun_decks.is_empty() and gun_decks[0] == d["id"]:
		for side in [ShipState.STARBOARD, ShipState.PORT]:
			if _ship.obscured_penalty(side) != 0:
				box.add_child(_badge("−2 %s" % ("stbd" if side == ShipState.STARBOARD else "port"), Style.BAD, Color.WHITE, "Obscured broadside"))
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


func _can_drop_data(_at: Vector2, _data: Variant) -> bool:
	drop_hover_id = 0
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		drop_hover_id = 0
	elif what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		_queue_render()


## Valid/invalid highlight for a station: the dragged counter, else the picked-up one.
func mark_for(target: String) -> String:
	if client == null:
		return ""
	var section := client.selected
	if get_viewport().gui_is_dragging():
		var d = get_viewport().gui_get_drag_data()
		section = int(d.get("section", -1)) if d is Dictionary else -1
	return client.mark_for(target, section)


func drop_on(target: String, section: int) -> void:
	client.assign(section, target)


## The second click of click-then-click. Returns true when it was handled.
func station_clicked(target: String) -> bool:
	if client.selected < 0:
		return false
	client.assign(client.selected, target)
	return true


func deck_card_clicked(deck_id: String) -> void:
	client.set_deck(deck_id)


func _on_counter_clicked(section: int) -> void:
	if not client.editable():
		return
	client.pick(section)


func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		client.drop_pick()


func _on_auto_toggled(on: bool) -> void:
	client.set_automatic(on)


func _open_menu(section: int, at: Vector2) -> void:
	if not client.editable():
		_on_message(client.read_only_note(), "bad", [])
		return
	_menu.clear()
	_menu_section = section
	_menu_targets.clear()
	# fires first, then the stations shown, in drawing order (CrewRules.stations lists fires first)
	for st in _stations:
		if str(st.get("accepts", "")) != "none":
			_menu_targets.append(st)
	_menu.add_separator(CrewOverlayText.section_name(section) + " · assign to")
	var current := client.station_of(section)
	for i in _menu_targets.size():
		var st: Dictionary = _menu_targets[i]
		var cur: bool = st["id"] == current
		var why := "" if cur else client.refusal(section, st["id"])
		var turns: int = st.get("turns", 0)
		_menu.add_item(str(st["label"]) + (" · %d turns" % turns if turns > 1 else "") + ("   (current)" if cur else ""), i)
		var idx := _menu.get_item_index(i)
		_menu.set_item_disabled(idx, why != "" or cur)
		_menu.set_item_tooltip(idx, why if why != "" else "Current task" if cur else "")
	_menu.reset_size()
	var vp := get_viewport_rect().size
	var pos := Vector2(minf(at.x, vp.x - _menu.size.x - 8), minf(at.y, vp.y - _menu.size.y - 8))
	_menu.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))


func _on_menu_id(id: int) -> void:
	if id >= 0 and id < _menu_targets.size():
		client.assign(_menu_section, _menu_targets[id]["id"])


# ---------------- message bar ----------------

func _on_message(text: String, kind: String, actions: Array) -> void:
	if kind == "clear" or text == "":
		_clear_message()
		return
	_clear(_msg)
	var sb := Style.box(Color("#26313f"), Style.LINE, 1, 6)
	sb.border_width_left = 4
	sb.border_color = Style.BAD if kind == "bad" else Style.ACCENT if kind == "info" else Style.WARN
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
	l.name = "MessageText"
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
	_msg.custom_minimum_size.x = minf(Style.px(640), size.x - Style.px(32))
	_msg.visible = true
	_msg.reset_size()
	_msg.offset_left = -_msg.custom_minimum_size.x / 2.0
	_msg.offset_right = _msg.custom_minimum_size.x / 2.0
	if actions.is_empty() and kind != "info":
		_msg_timer.start(4.2)
	else:
		_msg_timer.stop()


func _on_message_action(id: String) -> void:
	match id:
		"confirm_move":
			client.confirm_pending()
		"cancel_move":
			client.cancel_pending()
		"turn_off_auto":
			_clear_message()
			client.set_automatic(false)
		_:
			_clear_message()


func _clear_message() -> void:
	_msg_timer.stop()
	_msg.visible = false


# =====================================================================
# small inner controls
# =====================================================================

## A deck in the side list: click to show it large; hovering it while dragging for 450 ms switches
## the enlarged deck.
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
			if _hover_t >= 0.45 and ov.client.deck != deck_id:
				_hover_t = -INF
				ov.deck_card_clicked(deck_id)

	func _draw() -> void:
		if _over:
			draw_style_box(CrewStyle.box(Color.TRANSPARENT, CrewStyle.WARN, 1, 6), Rect2(Vector2.ZERO, size))
