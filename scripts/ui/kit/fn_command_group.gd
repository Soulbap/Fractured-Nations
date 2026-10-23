## Kit command group: a caption over a row of FNCommandButtons ("COMBAT: assault, suppress, flank").
## aside is a quiet note at the right of the caption (e.g. "RMB MOVE").
class_name FNCommandGroup
extends VBoxContainer

var header: FNSectionHeader
var row: HBoxContainer


func _init(title: String, aside := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", FNUI.S2 + 1)
	header = FNSectionHeader.new(title, aside, FNUI.INK_3)
	header.title.add_theme_font_size_override("font_size", FNUI.CAPTION)
	add_child(header)
	row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", FNUI.S2)
	add_child(row)


func add(button: FNCommandButton) -> FNCommandButton:
	row.add_child(button)
	return button
