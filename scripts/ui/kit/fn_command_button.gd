## Kit command button: icon over an uppercase title, with the hotkey as a keycap. States: normal,
## hover, pressed, disabled (theme), armed (waiting for its target click: amber) and current
## (the order the selection is carrying out now: a green bar under the button).
class_name FNCommandButton
extends Button

var icon_rect: TextureRect
var title_label: Label
var key_label: Label
var armed := false:
	set(v):
		if v != armed:
			armed = v
			_restyle()
var current := false:
	set(v):
		if v != current:
			current = v
			queue_redraw()
var _icon_name := &""


func _init(icon_name: StringName, title: String, key: String, tip := "") -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = tip
	custom_minimum_size = Vector2(45, 46)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 4
	v.offset_bottom = -3
	add_child(v)
	icon_rect = FNIcons.rect(icon_name, FNUI.ICON_L - 2)
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_name = icon_name
	v.add_child(icon_rect)
	title_label = FNUI.label(title, FNUI.CAPTION, FNUI.INK, "caps")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_label)
	key_label = FNUI.keycap(key, 8)
	key_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	key_label.visible = key != ""
	v.add_child(key_label)
	mouse_entered.connect(_restyle)
	mouse_exited.connect(_restyle)


## Changes title and icon in place (e.g. ROE: FIRE FREE <-> HOLD FIRE).
func set_face(icon_name: StringName, title: String) -> void:
	if icon_name != _icon_name:
		_icon_name = icon_name
		icon_rect.texture = FNIcons.texture(icon_name, FNUI.ICON_L - 2)
	title_label.text = title


func set_enabled(on: bool) -> void:
	if disabled == (not on):
		return
	disabled = not on
	_restyle()


func _restyle() -> void:
	if armed:
		add_theme_stylebox_override("normal", FNUI.state_style(&"armed"))
		add_theme_stylebox_override("hover", FNUI.state_style(&"armed"))
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")
	var tint := FNUI.ARMED if armed else (FNUI.INK_3 if disabled else (FNUI.INK if is_hovered() else FNUI.INK.darkened(0.08)))
	icon_rect.modulate = tint
	title_label.add_theme_color_override("font_color", FNUI.INK_3 if disabled else (FNUI.ARMED if armed else FNUI.INK))
	key_label.modulate.a = 0.45 if disabled else 1.0


func _draw() -> void:
	if current:
		draw_rect(Rect2(6, size.y - 2, size.x - 12, 1.5), FNUI.OK)
