## UI-UX-03 kit menu: the list a dropdown opens - one row per choice (icon, name, hotkey), the current choice marked with an
## accent bar and a check, the help of the row under the mouse in its tooltip. It opens next to an anchor rectangle on the
## side that has room (above a control in the lower half of the screen, else below), is kept inside the screen, and closes on
## a choice, a click anywhere outside it (that click does nothing else) or Esc. It lives on the anchor's CanvasLayer as its
## last child while open, so no panel draws over it.
class_name FNMenu
extends PanelContainer

signal chosen(id: Variant)
signal closed

const ROW_H := 20.0

## [{id, text, icon, key, tip}] in order.
var items: Array = []
## The id marked as current (null: none, e.g. a selection with mixed values).
var current: Variant = null
var _rows: Array[Button] = []
var _box: VBoxContainer
var _catcher: Control


func _init() -> void:
	theme = FNUI.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := FNUI.box(Color(FNUI.BG, 0.97), FNUI.LINE_STRONG, 1, FNUI.RADIUS, 3)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", sb)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 1)
	add_child(_box)
	visible = false
	_catcher = Control.new()
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.visible = false
	_catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close()
			_catcher.accept_event())


func set_items(p_items: Array) -> void:
	items = p_items
	for r in _rows:
		r.queue_free()
	_rows.clear()
	for i in items.size():
		var it: Dictionary = items[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(0, ROW_H)
		b.tooltip_text = String(it.get("tip", ""))
		b.text = ""
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 7
		h.offset_right = -7
		h.add_theme_constant_override("separation", FNUI.S3)
		b.add_child(h)
		var ic := FNIcons.rect(StringName(it.get("icon", &"")), FNUI.ICON_S, FNUI.INK_2)
		ic.visible = it.get("icon", &"") != &""
		h.add_child(ic)
		var l := FNUI.label(String(it.text), FNUI.LABEL, FNUI.INK, "caps")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
		var k := FNUI.label(String(it.get("key", "")), FNUI.CAPTION - 1, FNUI.INK_3, "caps")
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(k)
		var id: Variant = it.id
		b.pressed.connect(func() -> void:
			close()
			chosen.emit(id))
		_box.add_child(b)
		_rows.append(b)
	_restyle()


func index_of(id: Variant) -> int:
	for i in items.size():
		if items[i].id == id:
			return i
	return -1


## Screen rectangle of row i (tests click it).
func item_rect(i: int) -> Rect2:
	return _rows[i].get_global_rect() if i >= 0 and i < _rows.size() else Rect2()


func _restyle() -> void:
	for i in _rows.size():
		var on: bool = current != null and items[i].id == current
		var b := _rows[i]
		var n := FNUI.box(Color(FNUI.ACCENT, 0.16) if on else Color.TRANSPARENT, Color.TRANSPARENT, 0, 1, 0)
		n.border_width_left = 2 if on else 0
		n.border_color = FNUI.ACCENT
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", FNUI.box(FNUI.BG_HOVER if not on else Color(FNUI.ACCENT, 0.26), Color.TRANSPARENT, 0, 1, 0))
		b.add_theme_stylebox_override("pressed", FNUI.box(FNUI.BG_PRESSED, Color.TRANSPARENT, 0, 1, 0))
		var h := b.get_child(0)
		(h.get_child(0) as TextureRect).modulate = FNUI.ACCENT if on else FNUI.INK_2
		(h.get_child(1) as Label).add_theme_color_override("font_color", FNUI.ACCENT.lightened(0.25) if on else FNUI.INK)


## Opens beside `anchor` (a screen rectangle, normally the dropdown button), at least as wide as it.
func open_at(anchor: Rect2, host: Node) -> void:
	_restyle()
	if _catcher.get_parent() != host:
		if _catcher.get_parent():
			_catcher.get_parent().remove_child(_catcher)
		host.add_child(_catcher)
	if get_parent() != host:
		if get_parent():
			get_parent().remove_child(self)
		host.add_child(self)
	host.move_child(_catcher, -1)
	host.move_child(self, -1)
	var vp := get_viewport().get_visible_rect()
	_catcher.position = Vector2.ZERO
	_catcher.size = vp.size
	_catcher.visible = true
	visible = true
	size = Vector2.ZERO
	custom_minimum_size = Vector2(maxf(anchor.size.x, 110.0), 0)
	var s := get_combined_minimum_size()
	size = s
	var up := anchor.get_center().y > vp.size.y * 0.5
	var y := anchor.position.y - s.y - 2.0 if up else anchor.end.y + 2.0
	if up and y < 0.0:
		y = anchor.end.y + 2.0
	elif not up and y + s.y > vp.size.y:
		y = anchor.position.y - s.y - 2.0
	position = Vector2(clampf(anchor.position.x, 2.0, maxf(vp.size.x - s.x - 2.0, 2.0)), clampf(y, 2.0, maxf(vp.size.y - s.y - 2.0, 2.0))).round()


func close() -> void:
	if not visible:
		return
	visible = false
	_catcher.visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if is_instance_valid(_catcher) and _catcher.get_parent() == null:
		_catcher.queue_free()
