extends RefCounted
## Palette (the HTML prototype's :root tokens), sizes and small UI helpers for the
## crew overlay prototype. K scales the HTML's CSS pixels to the game's 1920x1080
## canvas: 14 px body text becomes the game theme's 18 px.

const K := 18.0 / 14.0

const INK := Color("#0e151d")
const PANEL := Color("#1a232e")
const PANEL_2 := Color("#222d3a")
const LINE := Color("#354252")
const FG := Color("#e6ebf1")
const MUTED := Color("#98a5b4")
const SEA := Color("#2a5680")
const SEA_LINE := Color("#3b6b96")
const DECK := Color("#c8a26a")
const DECK_DARK := Color("#7d5d33")
const PLANK := Color("#b38c55")
const CARD := Color("#eadfc4")
const CARD_EDGE := Color("#8d7b57")
const CARD_INK := Color("#2a2116")
const SAILOR := Color("#2f6a8e")
const MARINE := Color("#a3322a")
const FIRE := Color("#e8692a")
const WARN := Color("#e3b344")
const OK := Color("#62b47d")
const BAD := Color("#e0574d")
const ACCENT := Color("#79b7dc")
const BAD_TEXT := Color("#ff9b93")
const FIRE_TEXT := Color("#ffb48c")
const BTN := Color("#2b3a4b")
const BTN_EDGE := Color("#4a5d72")
const BTN_PRIMARY := Color("#2f5f80")
const BTN_PRIMARY_EDGE := Color("#4f86ad")

static var _bold: FontVariation
static var _display: FontVariation


## Scaled pixel size from an HTML CSS-pixel size.
static func px(v: float) -> int:
	return int(round(v * K))


## The project ships no fonts, so all three HTML faces fall back to Godot's default
## font: display is a lightly spaced regular, body as is, counter face emboldened.
static func bold_font() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.9
	return _bold


static func display_font() -> Font:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = ThemeDB.fallback_font
		_display.spacing_glyph = 1
	return _display


static func box(bg: Color, border: Color = Color.TRANSPARENT, bw := 0, radius := 0, pad := -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	if pad >= 0.0:
		sb.set_content_margin_all(pad)
	return sb


static func label(text: String, size_css: float, color: Color = FG, bold := false, wrapped := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px(size_css))
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", bold_font())
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Uppercase small caption as in the HTML's `.lbl`.
static func caption(text: String) -> Label:
	var l := label(text.to_upper(), 11, MUTED)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func button(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", px(14))
	var pad := px(8)
	var normal := box(BTN_PRIMARY if primary else BTN, BTN_PRIMARY_EDGE if primary else BTN_EDGE, 1, px(4))
	normal.content_margin_left = px(12)
	normal.content_margin_right = px(12)
	normal.content_margin_top = pad
	normal.content_margin_bottom = pad
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("#376f95") if primary else Color("#33465b")
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = normal.bg_color.darkened(0.25)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", FG)
	b.add_theme_color_override("font_hover_color", FG)
	b.add_theme_color_override("font_disabled_color", Color(FG, 0.55))
	if primary:
		b.add_theme_font_override("font", bold_font())
	return b
