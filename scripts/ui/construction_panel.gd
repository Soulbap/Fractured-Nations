## Construction menu: the catalog by category, plus delete / save / load / close.
## Built from StructureCatalog, so a new type shows up without touching the UI.
class_name ConstructionPanel
extends PanelContainer

var controller: ConstructionController
var _buttons := {}
var _delete: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.06, 0.82)
	sb.border_color = Color(0.45, 0.5, 0.38, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var title := Label.new()
	title.text = "CONSTRUCTION"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.7))
	box.add_child(title)
	for cat in StructureCatalog.CATEGORIES:
		var head := Label.new()
		head.text = cat.to_upper()
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", Color(0.65, 0.68, 0.58))
		box.add_child(head)
		for d in StructureCatalog.in_category(cat):
			var b := _button(d.display_name + ("  [line]" if d.linear else ""), func() -> void: controller.select_type(d.id), true)
			b.tooltip_text = d.description
			box.add_child(b)
			_buttons[d.id] = b
	box.add_child(HSeparator.new())
	_delete = _button("Delete  (X)", func() -> void: controller.select_delete(), true)
	box.add_child(_delete)
	var row := HBoxContainer.new()
	for b in [_button("Save F5", func() -> void: controller.save()), _button("Load F9", func() -> void: controller.load_saved())]:
		b.custom_minimum_size.x = 93
		row.add_child(b)
	box.add_child(row)
	box.add_child(_button("Close  (B)", func() -> void: controller.set_active(false)))


func refresh() -> void:
	for id in _buttons:
		_buttons[id].button_pressed = controller.tool == ConstructionController.Tool.PLACE and controller.def and controller.def.id == id
	_delete.button_pressed = controller.tool == ConstructionController.Tool.DELETE


func _button(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(190, 0)
	b.pressed.connect(func() -> void:
		cb.call()
		refresh())
	return b
