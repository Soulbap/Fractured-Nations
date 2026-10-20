## Construction menu: the catalog by category, plus delete / save / load / close.
## Built from StructureCatalog, so a new type shows up without touching the UI.
## WORLD-INTEGRATION-03: with ~70 types the categories fold; a click on a category header
## opens it (and closes the open one), selecting a type opens its category.
class_name ConstructionPanel
extends PanelContainer

var controller: ConstructionController
var _buttons := {}
var _headers := {}
var _sections := {}
var _open_category := "Buildings"
var _delete: Button
var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	# Top right: the left side belongs to the F3 overlay, the bottom to the HUD text.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_right = -12
	offset_top = 12
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
	# The categories scroll when the open one is taller than the screen allows (Defences
	# has 18 entries); the fixed buttons below stay in reach.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	box = _list
	for cat in StructureCatalog.CATEGORIES:
		var defs := StructureCatalog.in_category(cat)
		if defs.is_empty():
			continue
		var head := Button.new()
		head.toggle_mode = true
		head.focus_mode = Control.FOCUS_NONE
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.add_theme_font_size_override("font_size", 12)
		head.add_theme_color_override("font_color", Color(0.65, 0.68, 0.58))
		head.add_theme_color_override("font_pressed_color", Color(0.85, 0.9, 0.7))
		head.add_theme_color_override("font_hover_color", Color(0.85, 0.9, 0.7))
		head.pressed.connect(func() -> void:
			_open_category = cat
			refresh())
		box.add_child(head)
		_headers[cat] = head
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 2)
		box.add_child(section)
		_sections[cat] = section
		for d in defs:
			var tag := "  [line]" if d.linear else ("  [curve]" if d.surface == StructureDef.Surface.ROAD else ("  [area]" if d.surface == StructureDef.Surface.AREA else ""))
			var b := _button(d.display_name + tag, func() -> void: controller.select_type(d.id), true)
			b.tooltip_text = d.description
			section.add_child(b)
			_buttons[d.id] = b
	box = _scroll.get_parent() as VBoxContainer
	box.add_child(HSeparator.new())
	_delete = _button("Delete  (X)", func() -> void: controller.select_delete(), true)
	box.add_child(_delete)
	var row := HBoxContainer.new()
	for b in [_button("Save F5", func() -> void: controller.save()), _button("Load F9", func() -> void: controller.load_saved())]:
		b.custom_minimum_size.x = 93
		row.add_child(b)
	box.add_child(row)
	box.add_child(_button("Close  (B)", func() -> void: controller.set_active(false)))
	refresh()


func refresh() -> void:
	var placing := controller.tool == ConstructionController.Tool.PLACE and controller.def != null
	if placing and _sections.has(controller.def.category):
		_open_category = controller.def.category
	for cat in _headers:
		var open: bool = cat == _open_category
		var n: int = (_sections[cat] as VBoxContainer).get_child_count()
		_headers[cat].text = "%s  %s  (%d)" % ["v" if open else ">", cat.to_upper(), n]
		_headers[cat].set_pressed_no_signal(open)
		_sections[cat].visible = open
	for id in _buttons:
		_buttons[id].button_pressed = placing and controller.def.id == id
	_delete.button_pressed = controller.tool == ConstructionController.Tool.DELETE
	_fit_scroll.call_deferred()


## The scroll area is as tall as its content, up to what fits above the fixed buttons.
func _fit_scroll() -> void:
	if _scroll == null or _list == null:
		return
	var room := get_viewport_rect().size.y - 230.0
	_scroll.custom_minimum_size = Vector2(230.0, minf(_list.get_combined_minimum_size().y + 4.0, maxf(room, 200.0)))


func _button(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(210, 0)
	b.pressed.connect(func() -> void:
		cb.call()
		refresh())
	return b
