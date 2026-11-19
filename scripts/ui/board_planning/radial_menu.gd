class_name RadialMenu
extends Control
## A ring of round buttons over a ship on the map (board planning, view only; prototype
## prototypes/planning_radial/planning_radial.html, `.rad` and `renderRadial()`).
##
## The items sit evenly on a circle, the first at the top; a dark disc in the centre carries the
## title and subtitle; hovering or focusing an item shows its label and its hint (or, for a greyed
## item, its `off_reason` in the warning colour) in a caption under the ring. The centre comes from
## the anchor provider every frame and is clamped so the whole ring stays inside the safe rect.
##
## Coordinates: the anchor point and the safe rect are in this Control's own coordinates, which
## are the canvas coordinates when the menu fills the viewport from the origin (as it should).
## The menu itself never takes a mouse event; only its buttons do. It mutates no game state: a
## choice is reported through `item_chosen` and the caller acts on it.

signal item_chosen(id: String)
signal closed()

const RADIUS := 78.0
const BUTTON_SIZE := 48.0
const ICON_SIZE := 26.0
const DISC_RADIUS := 60.0
const DISC_TEXT_WIDTH := 104.0
## The caption's top (or bottom, when it is flipped above the ring) lies this far past the radius.
const CAPTION_GAP := 34.0
const CAPTION_WIDTH := 240.0
const HOVER_SCALE := 1.12
const POP_SECONDS := 0.16
const POP_STAGGER := 0.018
const HOVER_SECONDS := 0.12
const OFF_ALPHA := 0.38

const ITEM_BG := Color("#1f2b39")
const ITEM_BG_HOVER := Color("#2c4157")
const ITEM_BG_ON := Color("#1f3a2a")
const BRASS := Color("#d8b45a")
const SHADE := Color(0.055, 0.082, 0.114)  # CrewStyle.INK

const GREY_SHADER := """shader_type canvas_item;
void fragment() {
	COLOR.rgb = vec3(dot(COLOR.rgb, vec3(0.299, 0.587, 0.114)));
}
"""

static var _grey_material: ShaderMaterial = null

## Scales the ring, the buttons and the text (read when the menu opens).
var ui_scale := 1.0

var _items: Array[RadialItem] = []
var _buttons: Array[Button] = []
var _anchor_provider := Callable()
var _safe_rect := Rect2()
var _hovered := -1
var _focused := -1
var _open := false
## A message shown in the caption in place of the item's (a refusal, a die roll's result) until
## another item is hovered or the ring closes: {"text": String, "warn": bool}, or {}.
var _note: Dictionary = {}

var _ring: Control
var _disc: TextureRect
var _centre_box: VBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _caption_box: VBoxContainer
var _caption: PanelContainer
var _caption_title: Label
var _caption_detail: Label


func _init() -> void:
	name = "RadialMenu"
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	visible = false
	set_process(false)
	_build()


# --- public API ---------------------------------------------------------------------------------

func open(items: Array[RadialItem], title: String, subtitle: String) -> void:
	_clear_buttons()
	_items = items.duplicate()
	_hovered = -1
	_focused = -1
	_note = {}
	_title_label.text = title
	_title_label.visible = title != ""
	_subtitle_label.text = subtitle
	_subtitle_label.visible = subtitle != ""
	_layout_frame()
	for i in _items.size():
		_add_button(i)
	_open = true
	visible = true
	set_process(true)
	_update_caption()
	_place()
	_pop_in()


## Swaps the items of the open ring in place (a checklist change, an order given): the buttons are
## rebuilt with no pop-in, the title, position and any note stay, and the hovered item is hovered
## again. A new `subtitle` replaces the old one when given.
func refresh_items(items: Array[RadialItem], subtitle: Variant = null) -> void:
	if not _open:
		return
	var hovered := _hovered
	var note := _note
	_clear_buttons()  # hiding a hovered button may report a mouse exit
	_items = items.duplicate()
	_hovered = hovered if hovered < _items.size() else -1
	_note = note
	_focused = clampi(_focused, -1, _items.size() - 1)
	if subtitle is String:
		_subtitle_label.text = subtitle
		_subtitle_label.visible = subtitle != ""
	_layout_frame()
	for i in _items.size():
		_add_button(i)
	_update_caption()
	_place()
	if _hovered >= 0:
		hover_item(_hovered)  # the same item: the note stays


func close() -> void:
	if not _open:
		return
	_open = false
	_clear_buttons()
	_items.clear()
	_hovered = -1
	_focused = -1
	_note = {}
	visible = false
	set_process(false)
	closed.emit()


func is_open() -> bool:
	return _open


## `fn` takes no argument and returns the point (Vector2) to centre on; it is called every frame
## while the menu is open. Anything else returned keeps the ring where it is.
func set_anchor_provider(fn: Callable) -> void:
	_anchor_provider = fn
	if _open:
		_place()


## The ring is clamped to stay inside `rect`; an empty rect means no clamping.
func set_safe_rect(rect: Rect2) -> void:
	_safe_rect = rect
	if _open:
		_place()


func item_count() -> int:
	return _items.size()


## Shows `text` in the caption in place of the item's (in the warning colour when `warn`) until
## another item is hovered, the ring is reopened or it closes. "" clears it.
func show_note(text: String, warn := false) -> void:
	_note = {} if text == "" else {"text": text, "warn": warn}
	if _open:
		_update_caption()


## What the caption shows now: the note when one is set; else the hovered (else focused) item's
## label, a newline, then its `off_reason` when greyed, else its hint. "" when there is nothing.
func caption_text() -> String:
	if not _note.is_empty():
		return _note["text"]
	var item := _caption_item()
	if item == null:
		return ""
	var detail := item.hint if item.is_enabled() else item.off_reason
	return item.label if detail == "" else item.label + "\n" + detail


## True when the caption shows a greyed item's reason or a warning note (the warning colour).
func caption_is_reason() -> bool:
	if not _note.is_empty():
		return _note["warn"]
	var item := _caption_item()
	return item != null and not item.is_enabled()


## Where the caption is drawn, in the menu's coordinates (tests).
func caption_rect() -> Rect2:
	return Rect2(_ring.position + _caption_box.position,
			Vector2(_caption_box.size.x, _caption_box.get_combined_minimum_size().y))


func title_text() -> String:
	return _title_label.text


func subtitle_text() -> String:
	return _subtitle_label.text


## The ring's centre after clamping, in this Control's coordinates.
func ring_center() -> Vector2:
	return _ring.position


## The centre of item `index`'s button, in this Control's coordinates.
func item_center(index: int) -> Vector2:
	return _ring.position + _offset(index)


## Hover item `index` (-1 = none), as the mouse does.
func hover_item(index: int) -> void:
	var next := index if index >= 0 and index < _items.size() else -1
	if next >= 0 and next != _hovered:
		_note = {}  # another item: its own caption again
	_hovered = next
	for i in _buttons.size():
		var grow := i == _hovered and _items[i].is_enabled()
		_tween_scale(_buttons[i], HOVER_SCALE if grow else 1.0)
	_update_caption()


## Highlight item `index` as if keyboard-focused (the buttons take no real GUI focus, so Space,
## Enter and Tab stay with the board).
func focus_item(index: int) -> void:
	if index < 0 or index >= _buttons.size():
		return
	_focused = index
	_update_caption()


## Choose item `index` (a click or Enter on its button). A greyed item emits nothing.
func choose(index: int) -> void:
	if not _open or index < 0 or index >= _items.size():
		return
	var item := _items[index]
	if not item.is_enabled():
		return
	item_chosen.emit(item.id)


# --- frame ------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _open:
		_place()


func _place() -> void:
	var centre := _ring.position
	if _anchor_provider.is_valid():
		var point: Variant = _anchor_provider.call()
		if point is Vector2:
			centre = point
	_ring.position = _clamped(centre)
	_place_caption()


func _clamped(centre: Vector2) -> Vector2:
	if not _safe_rect.has_area():
		return centre
	var extent := (RADIUS + BUTTON_SIZE / 2.0 * HOVER_SCALE) * ui_scale
	return Vector2(
			_clamp_axis(centre.x, _safe_rect.position.x + extent, _safe_rect.end.x - extent),
			_clamp_axis(centre.y, _safe_rect.position.y + extent, _safe_rect.end.y - extent))


static func _clamp_axis(value: float, low: float, high: float) -> float:
	if low > high:
		return (low + high) / 2.0
	return clampf(value, low, high)


## Under the ring, or above it when there is no room below inside the safe rect; centred on the
## ring, but slid sideways to stay inside the safe rect (the ring's clamp is narrower than it).
func _place_caption() -> void:
	var box := _caption_box.get_combined_minimum_size()
	var width := maxf(box.x, _caption.custom_minimum_size.x)
	var height := box.y
	var below := (RADIUS + CAPTION_GAP) * ui_scale
	var top := below
	var left := -width / 2.0
	if _safe_rect.has_area():
		if _ring.position.y + below + height > _safe_rect.end.y:
			top = -below - height
		left = _clamp_axis(_ring.position.x + left, _safe_rect.position.x,
				_safe_rect.end.x - width) - _ring.position.x
	_caption_box.position = Vector2(left, top)
	_caption_box.size = Vector2(width, 0.0)


func _offset(index: int) -> Vector2:
	var n := maxi(_items.size(), 1)
	var angle := -PI / 2.0 + index * TAU / n
	return Vector2(cos(angle), sin(angle)) * RADIUS * ui_scale


# --- building -----------------------------------------------------------------------------------

func _build() -> void:
	_ring = Control.new()
	_ring.name = "Ring"
	_ring.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_ring)

	_disc = TextureRect.new()
	_disc.name = "Disc"
	_disc.mouse_filter = MOUSE_FILTER_IGNORE
	_disc.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_disc.stretch_mode = TextureRect.STRETCH_SCALE
	_disc.texture = _disc_texture()
	_ring.add_child(_disc)

	_centre_box = VBoxContainer.new()
	_centre_box.name = "Centre"
	_centre_box.mouse_filter = MOUSE_FILTER_IGNORE
	_centre_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_centre_box.add_theme_constant_override("separation", 0)
	_ring.add_child(_centre_box)
	_title_label = _label(&"DisplayLabel", CrewStyle.FG)
	_centre_box.add_child(_title_label)
	_subtitle_label = _label(&"CounterLabel", CrewStyle.MUTED)
	_centre_box.add_child(_subtitle_label)

	_caption_box = VBoxContainer.new()
	_caption_box.name = "Caption"
	_caption_box.mouse_filter = MOUSE_FILTER_IGNORE
	_ring.add_child(_caption_box)
	_caption = PanelContainer.new()
	_caption.mouse_filter = MOUSE_FILTER_IGNORE
	_caption.size_flags_horizontal = SIZE_SHRINK_CENTER
	_caption_box.add_child(_caption)
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 0)
	_caption.add_child(lines)
	_caption_title = _label(&"StrongLabel", CrewStyle.FG)
	lines.add_child(_caption_title)
	_caption_detail = _label(&"", CrewStyle.MUTED)
	lines.add_child(_caption_detail)


func _label(variation: StringName, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = MOUSE_FILTER_IGNORE
	if variation != &"":
		l.theme_type_variation = variation
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	return l


## Sizes that depend on `ui_scale`: the disc, the centre text and the caption.
func _layout_frame() -> void:
	var s := ui_scale
	var disc := DISC_RADIUS * s
	_disc.position = Vector2(-disc, -disc)
	_disc.size = Vector2(disc, disc) * 2.0
	var text_width := DISC_TEXT_WIDTH * s
	_title_label.add_theme_font_size_override("font_size", roundi(17.0 * s))
	_subtitle_label.add_theme_font_size_override("font_size", roundi(14.0 * s))
	# Autowrapped labels need a width of their own, or they wrap at every word and the box grows
	# far past the disc; then the box is centred on the ring at its real height.
	_title_label.custom_minimum_size.x = text_width
	_subtitle_label.custom_minimum_size.x = text_width
	var text_height := _centre_box.get_combined_minimum_size().y
	_centre_box.position = Vector2(-text_width / 2.0, -text_height / 2.0)
	_centre_box.size = Vector2(text_width, text_height)
	_caption_title.add_theme_font_size_override("font_size", roundi(16.0 * s))
	_caption_detail.add_theme_font_size_override("font_size", roundi(14.0 * s))
	var bg := CrewStyle.box(Color(SHADE, 0.86), Color.TRANSPARENT, 0, roundi(6.0 * s))
	bg.content_margin_left = 8.0 * s
	bg.content_margin_right = 8.0 * s
	bg.content_margin_top = 4.0 * s
	bg.content_margin_bottom = 4.0 * s
	_caption.add_theme_stylebox_override("panel", bg)


func _add_button(index: int) -> void:
	var item := _items[index]
	var side := BUTTON_SIZE * ui_scale
	var b := Button.new()
	b.name = "Item_" + item.id
	b.focus_mode = FOCUS_NONE  # never takes Space / Enter / Tab from the board
	b.custom_minimum_size = Vector2(side, side)
	b.size = Vector2(side, side)
	b.pivot_offset = Vector2(side, side) / 2.0
	b.position = _offset(index) - b.pivot_offset
	b.icon = item.icon
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_button(b, item)
	if not item.is_enabled():
		b.self_modulate = Color(1, 1, 1, OFF_ALPHA)
		b.material = _grey()
		b.mouse_default_cursor_shape = CURSOR_FORBIDDEN
	b.mouse_entered.connect(hover_item.bind(index))
	b.mouse_exited.connect(_on_mouse_exited.bind(index))
	b.pressed.connect(choose.bind(index))
	_ring.add_child(b)
	_buttons.append(b)


func _style_button(b: Button, item: RadialItem) -> void:
	var s := ui_scale
	var radius := roundi(BUTTON_SIZE * s / 2.0)
	var pad := (BUTTON_SIZE - ICON_SIZE) / 2.0 * s
	var rim := CrewStyle.OK if item.on else CrewStyle.BTN_EDGE
	var bg := ITEM_BG_ON if item.on else ITEM_BG
	var normal := _round_box(bg, rim, radius, pad, true)
	var hover := normal
	if item.is_enabled():
		hover = _round_box(ITEM_BG_ON if item.on else ITEM_BG_HOVER, CrewStyle.OK if item.on else BRASS,
				radius, pad, true)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("hover_pressed", hover)
	b.add_theme_stylebox_override("disabled", normal)
	var focus := _round_box(Color.TRANSPARENT, BRASS, radius, pad, false)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)


func _round_box(bg: Color, border: Color, radius: int, pad: float, shadow: bool) -> StyleBoxFlat:
	var sb := CrewStyle.box(bg, border, maxi(roundi(2.0 * ui_scale), 1), radius, pad)
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = roundi(5.0 * ui_scale)
		sb.shadow_offset = Vector2(0, 3.0 * ui_scale)
	return sb


func _clear_buttons() -> void:
	# Freed at the end of the frame (a button may be closing the menu from its own `pressed`);
	# left in the tree till then so it is never an orphan.
	for b in _buttons:
		b.hide()
		b.queue_free()
	_buttons.clear()


static func _disc_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.76, 0.98])
	gradient.colors = PackedColorArray([Color(SHADE, 0.72), Color(SHADE, 0.72), Color(SHADE, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


static func _grey() -> ShaderMaterial:
	if _grey_material == null:
		var shader := Shader.new()
		shader.code = GREY_SHADER
		_grey_material = ShaderMaterial.new()
		_grey_material.shader = shader
	return _grey_material


# --- hover, focus, caption ------------------------------------------------------------------

func _on_mouse_exited(index: int) -> void:
	if _hovered == index:
		hover_item(-1)


func _caption_item() -> RadialItem:
	var index := _hovered if _hovered >= 0 else _focused
	if index < 0 or index >= _items.size():
		return null
	return _items[index]


func _update_caption() -> void:
	var item := _caption_item()
	_caption_box.visible = item != null or not _note.is_empty()
	if not _caption_box.visible:
		return
	if not _note.is_empty():
		_caption_title.text = _note["text"]
		_caption_title.add_theme_color_override("font_color",
				CrewStyle.WARN if _note["warn"] else CrewStyle.FG)
		_caption_detail.text = ""
		_caption_detail.visible = false
	else:
		_caption_title.text = item.label
		_caption_title.add_theme_color_override("font_color", CrewStyle.FG)
		var detail := item.hint if item.is_enabled() else item.off_reason
		_caption_detail.text = detail
		_caption_detail.visible = detail != ""
		_caption_detail.add_theme_color_override("font_color",
				CrewStyle.MUTED if item.is_enabled() else CrewStyle.WARN)
	var width := _caption_width()
	_caption.custom_minimum_size.x = width
	# The labels autowrap: give them the caption's inner width now (their container sorts a frame
	# later), or their minimum height is one word per line and the caption's measured height (the
	# flip above the ring) is far too tall.
	var inner := maxf(width - 16.0 * ui_scale, 0.0)
	for l: Label in [_caption_title, _caption_detail]:
		l.custom_minimum_size.x = inner
		l.size = Vector2(inner, l.size.y)
		l.update_minimum_size()  # a resize alone leaves the containers' cached sizes stale
	_place_caption()


## The caption shrinks to its text, up to CAPTION_WIDTH (the labels wrap beyond it).
func _caption_width() -> float:
	var limit := CAPTION_WIDTH * ui_scale
	if not is_inside_tree():
		return limit
	var widest := 0.0
	for l: Label in [_caption_title, _caption_detail]:
		if not l.visible:
			continue
		# A TextLine owns its shaped text (Font.get_string_size would cache it on the theme font).
		var line := TextLine.new()
		line.add_string(l.text, l.get_theme_font("font"), l.get_theme_font_size("font_size"))
		widest = maxf(widest, line.get_size().x)
	return minf(widest + 2.0 + 16.0 * ui_scale, limit)


# --- animation ------------------------------------------------------------------------------

func _pop_in() -> void:
	if not is_inside_tree():
		return
	for i in _buttons.size():
		var b := _buttons[i]
		var delay := i * POP_STAGGER
		b.scale = Vector2(0.4, 0.4)
		b.modulate.a = 0.0
		var fade := b.create_tween()
		fade.tween_property(b, "modulate:a", 1.0, POP_SECONDS).set_delay(delay)
		var grow := b.create_tween()
		grow.tween_property(b, "scale", Vector2.ONE, POP_SECONDS).set_delay(delay) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		b.set_meta(&"scale_tween", grow)


func _tween_scale(b: Button, target: float) -> void:
	# get_meta with a null default still errors on a missing key: ask first.
	var previous: Variant = b.get_meta(&"scale_tween") if b.has_meta(&"scale_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	if not b.is_inside_tree():
		b.scale = Vector2(target, target)
		return
	var tween := b.create_tween()
	tween.tween_property(b, "scale", Vector2(target, target), HOVER_SECONDS) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	b.set_meta(&"scale_tween", tween)
