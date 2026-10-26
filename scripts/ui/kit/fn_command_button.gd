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


## GAMEPLAY-05B: the tooltip wraps at a readable width (an order's explanation ran to one line of ~1400 px): its first line as the
## heading, the rest as body text.
func _make_custom_tooltip(for_text: String) -> Object:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var parts := for_text.split("\n", true, 1)
	v.add_child(FNUI.label(parts[0], FNUI.CAPTION, FNUI.INK, "caps"))
	if parts.size() > 1:
		var b := FNUI.label(parts[1], FNUI.CAPTION + 1, FNUI.INK_2, "body")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(330, 0)
		v.add_child(b)
	return v


## QOL-01 compact: a small tile for a command grid - icon over the name, the hotkey in the corner, the full help in the
## tooltip.
func _init(icon_name: StringName, title: String, key: String, tip := "", compact := false) -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = tip
	custom_minimum_size = Vector2(46, 38) if compact else Vector2(45, 46)
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
	if compact:
		# Icon over a short name; the hotkey small in the top right corner.
		v.offset_top = 3
		v.offset_bottom = -2
		v.add_theme_constant_override("separation", 1)
		title_label.add_theme_font_size_override("font_size", 8)
		key_label = FNUI.label(key, 7, FNUI.INK_3, "caps")
		key_label.visible = key != ""
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_label.anchor_left = 1.0
		key_label.anchor_right = 1.0
		key_label.offset_left = -20.0
		key_label.offset_right = -3.0
		key_label.offset_top = 1.0
		key_label.offset_bottom = 10.0
		add_child(key_label)
	else:
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
