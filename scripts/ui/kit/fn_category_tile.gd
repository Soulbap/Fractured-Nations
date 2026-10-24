## Kit category tile: icon + uppercase name (+ a quiet count), one of a group where one is chosen
## (construction categories, map layers grouped by kind). selected uses the kit's selected surface.
class_name FNCategoryTile
extends Button

var icon_rect: TextureRect
var title_label: Label
var count_label: Label
var selected := false:
	set(v):
		if v != selected:
			selected = v
			_restyle()


func _init(icon_name: StringName, title: String, count := "") -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, 22)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", FNUI.S3 - 1)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	add_child(h)
	icon_rect = FNIcons.rect(icon_name, FNUI.ICON_S)
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon_rect)
	title_label = FNUI.label(title, FNUI.CAPTION, FNUI.INK, "caps")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(title_label)
	count_label = FNUI.label(count, FNUI.CAPTION - 1, FNUI.INK_3, "number")
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(count_label)
	mouse_entered.connect(_restyle)
	mouse_exited.connect(_restyle)
	_restyle()


func _restyle() -> void:
	var st := &"selected" if selected else &"normal"
	add_theme_stylebox_override("normal", FNUI.state_style(st))
	add_theme_stylebox_override("hover", FNUI.state_style(&"selected_hover" if selected else &"hover"))
	icon_rect.modulate = FNUI.ACCENT.lightened(0.25) if selected else (FNUI.INK if is_hovered() else FNUI.INK_2)
	title_label.add_theme_color_override("font_color", FNUI.INK if selected or is_hovered() else FNUI.INK_2)
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_rect(Rect2(0, 0, 2, size.y), FNUI.ACCENT)
