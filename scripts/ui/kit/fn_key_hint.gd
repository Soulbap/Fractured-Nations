## Kit key hint: keycap + action ("[F1] CONTROLS"). Used by the RTS hint bar.
class_name FNKeyHint
extends HBoxContainer


func _init(key: String, action: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	var k := FNUI.keycap(key)
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(k)
	add_child(FNUI.label(action, FNUI.CAPTION, FNUI.INK_2, "caps"))
