## Shared Field Manual presentation tokens. UI-01B keeps gameplay/data in the existing panels.
class_name FieldManual
extends RefCounted

const INK := Color("f0f1e8")
const CANVAS := Color(0.067, 0.082, 0.063, 0.90)
const OLIVE := Color("b8bf85")
const BLUE := Color("91b9fa")
const AMBER := Color("e7be63")
const DANGER := Color("e48a7d")
const SUCCESS := Color("94c87e")
const SECONDARY := Color("b9bdb3")
const DIM := Color(0.45, 0.48, 0.42, 1.0)

static func panel(border := OLIVE, alpha := 0.90, padding := 8) -> StyleBoxFlat:

	var s := StyleBoxFlat.new()
	s.bg_color = Color(CANVAS, alpha)
	s.border_color = Color(border, 0.70)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(padding)
	return s


static func button_style(fill: Color, border: Color, text := INK) -> StyleBoxFlat:

	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func style_button(button: Button, accent := OLIVE) -> void:

	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(SECONDARY, 0.45))
	button.add_theme_stylebox_override("normal", button_style(Color(0.10, 0.13, 0.095, 0.96), Color(DIM, 0.9)))
	button.add_theme_stylebox_override("hover", button_style(Color(accent, 0.24), accent))
	button.add_theme_stylebox_override("pressed", button_style(Color(accent, 0.42), accent.lightened(0.12)))
	button.add_theme_stylebox_override("disabled", button_style(Color(0.08, 0.09, 0.075, 0.7), Color(DIM, 0.35)))


static func style_label(label: Label, size := 14, color := INK) -> void:

	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
