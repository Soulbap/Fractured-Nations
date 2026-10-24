## Kit status indicator: icon + uppercase word in the status colour ("MOVING", "ENGAGED").
## The colour is never the only signal: icon and word say the same thing.
class_name FNStatusIndicator
extends HBoxContainer

var icon: TextureRect
var text_label: Label
var _icon_name := &""
var _px := FNUI.ICON_S


func _init(px := FNUI.ICON_S, font_size := FNUI.LABEL) -> void:
	_px = px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	icon = FNIcons.rect(&"idle", px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(icon)
	text_label = FNUI.label("", font_size, FNUI.INK, "caps")
	text_label.clip_text = true
	text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(text_label)


func set_status(icon_name: StringName, text: String, color: Color) -> void:
	if icon_name != _icon_name:
		_icon_name = icon_name
		icon.texture = FNIcons.texture(icon_name, _px)
	icon.modulate = color
	text_label.text = text
	text_label.add_theme_color_override("font_color", color)
