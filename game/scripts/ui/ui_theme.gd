class_name UITheme
extends RefCounted
## Tema da interface: fonte Fredoka (OFL, Milena Brandão & Hafontia),
## botões arredondados em tons pastel, sombras suaves.

const FONT_FILE := preload("res://game/assets/fonts/Fredoka.ttf")

const CREAM := Color(1.0, 0.97, 0.92)
const INK := Color(0.30, 0.18, 0.26)
const PEACH := Color(1.0, 0.72, 0.56)
const TEAL := Color(0.12, 0.66, 0.64)
const ROSE := Color(0.96, 0.46, 0.58)
const GOLD := Color(1.0, 0.80, 0.30)

static var _theme: Theme
static var _fonts := {}


static func font(weight := 600) -> FontVariation:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = FONT_FILE
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv


static func box(bg: Color, radius := 22, border := Color(0, 0, 0, 0), bw := 0, shadow := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	if shadow > 0:
		sb.shadow_color = Color(0.35, 0.15, 0.3, 0.25)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	return sb


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 26
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_focus_color", "Button", INK)
	t.set_stylebox("normal", "Button", box(Color(1.0, 0.95, 0.9, 0.92), 26, Color(1, 1, 1, 0.9), 3))
	t.set_stylebox("hover", "Button", box(Color(1.0, 0.86, 0.78, 0.96), 26, Color(1, 1, 1, 1), 3))
	t.set_stylebox("pressed", "Button", box(TEAL, 26, Color(1, 1, 1, 1), 3))
	t.set_stylebox("focus", "Button", box(Color(1.0, 0.86, 0.78, 0.0), 26, GOLD, 4, 0))
	t.set_stylebox("panel", "PanelContainer", box(Color(1.0, 0.95, 0.92, 0.88), 34, Color(1, 1, 1, 0.9), 3, 14))
	t.set_constant("separation", "VBoxContainer", 14)
	t.set_constant("separation", "HBoxContainer", 14)
	_theme = t
	return t


static func label(text: String, size := 26, color := INK, weight := 600) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
