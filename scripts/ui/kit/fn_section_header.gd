## Kit section header: an uppercase caption, a hairline that fills the row and an optional aside
## on the right ("5 SQUADS"). Optional leading chip (e.g. the faction) in its own colour.
class_name FNSectionHeader
extends HBoxContainer

var title: Label
var aside: Label
var _rule: Control


func _init(text := "", aside_text := "", color := FNUI.INK_2) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", FNUI.S3)
	title = FNUI.label(text, FNUI.LABEL, color, "caps")
	add_child(title)
	_rule = Control.new()
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule.custom_minimum_size = Vector2(12, 0)
	_rule.draw.connect(func() -> void:
		var y := roundf(_rule.size.y * 0.5) + 0.5
		_rule.draw_line(Vector2(0, y), Vector2(_rule.size.x, y), Color(FNUI.LINE_STRONG, 0.7), 1.0))
	add_child(_rule)
	aside = FNUI.label(aside_text, FNUI.CAPTION, FNUI.INK_3, "caps")
	add_child(aside)


## A small coloured tag before the title (faction, mode).
func add_chip(text: String, color: Color) -> Label:
	var chip := FNUI.label(text, FNUI.CAPTION, color.lightened(0.35), "caps")
	var sb := FNUI.box(Color(color, 0.22), Color(color, 0.85), 1, 2, 0)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	chip.add_theme_stylebox_override("normal", sb)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(chip)
	move_child(chip, 0)
	return chip
