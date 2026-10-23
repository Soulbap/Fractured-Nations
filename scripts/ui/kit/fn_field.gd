## Kit field: one fact in an inspector - a caption and its value on one line ("GARRISON   40 soldiers"),
## optionally with an icon and a value colour. Used by the construction base strip, the vehicle /
## facility panel and the map inspector.
class_name FNField
extends HBoxContainer

var caption_label: Label
var value_label: Label
var icon_rect: TextureRect


func _init(caption: String, value := "", icon_name := &"", caption_w := 64.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", FNUI.S3)
	if icon_name != &"":
		icon_rect = FNIcons.rect(icon_name, FNUI.ICON_S - 1, FNUI.INK_3)
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(icon_rect)
	caption_label = FNUI.label(caption, FNUI.CAPTION, FNUI.INK_3, "caps")
	caption_label.custom_minimum_size = Vector2(caption_w, 0)
	add_child(caption_label)
	value_label = FNUI.label(value, FNUI.LABEL, FNUI.INK, "body")
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label measured at zero width asks for one line per character; give it a floor.
	value_label.custom_minimum_size = Vector2(90, 0)
	add_child(value_label)


func set_value(text: String, color := FNUI.INK) -> void:
	value_label.text = text
	value_label.add_theme_color_override("font_color", color)
