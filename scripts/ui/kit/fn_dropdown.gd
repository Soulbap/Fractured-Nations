## UI-UX-03 kit dropdown: one compact control for a choice that used to be a row of buttons - a small caption, the current
## value and a chevron ("FORMATION  Line ▾"). A click opens its FNMenu on the side with room; a choice emits `chosen` (the owner
## issues the existing order) and the value stays visible. A selection with different values reads "Mixed".
class_name FNDropdown
extends Button

signal chosen(id: Variant)

var caption_label: Label
var value_label: Label
var icon_rect: TextureRect
var menu: FNMenu
var _chevron: TextureRect
## False: the button is as wide as its own text (a menu of actions, not a value).
var fit_items := true


func _init(caption: String, tip := "") -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = tip
	custom_minimum_size = Vector2(0, 20)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := FNUI.state_style(StringName("hover" if st == "hover_pressed" else st), 0)
		sb.content_margin_left = 6
		sb.content_margin_right = 4
		add_theme_stylebox_override(st, sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -3
	h.add_theme_constant_override("separation", FNUI.S2)
	add_child(h)
	icon_rect = FNIcons.rect(&"idle", FNUI.ICON_S, FNUI.INK_2)
	icon_rect.visible = false
	h.add_child(icon_rect)
	caption_label = FNUI.label(caption, FNUI.CAPTION - 1, FNUI.INK_3, "caps")
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.visible = caption != ""
	h.add_child(caption_label)
	value_label = FNUI.label("", FNUI.LABEL, FNUI.INK, "caps")
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.clip_text = true
	h.add_child(value_label)
	_chevron = FNIcons.rect(&"chevron_down", FNUI.ICON_S - 2, FNUI.INK_2)
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_chevron)
	menu = FNMenu.new()
	menu.chosen.connect(func(id: Variant) -> void: chosen.emit(id))
	menu.closed.connect(_restyle_open)
	pressed.connect(_toggle)


func _ready() -> void:
	if not fit_items:
		return
	# Wide enough for the caption, the longest value and the chevron.
	var w := 0.0
	var f := FNUI.caps_font()
	for it: Dictionary in menu.items:
		w = maxf(w, f.get_string_size(String(it.text).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL).x)
	var cw := f.get_string_size(caption_label.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1).x if caption_label.visible else 0.0
	custom_minimum_size.x = maxf(custom_minimum_size.x, ceilf(w + cw + 34.0 + (14.0 if icon_rect.visible else 0.0)))


func set_items(items: Array) -> void:
	menu.set_items(items)


## The current value (null = mixed). The icon follows the value's item when it has one.
func set_value(id: Variant) -> void:
	menu.current = id
	var i: int = menu.index_of(id) if id != null else -1
	var text := String(menu.items[i].text) if i >= 0 else "Mixed"
	if value_label.text != text.to_upper():
		value_label.text = text.to_upper()
	value_label.add_theme_color_override("font_color", FNUI.INK if i >= 0 else FNUI.WARN)
	if i >= 0 and menu.items[i].get("icon", &"") != &"":
		icon_rect.texture = FNIcons.texture(StringName(menu.items[i].icon), FNUI.ICON_S)
		icon_rect.visible = true
	if menu.visible:
		menu._restyle()


func _host() -> Node:
	var n: Node = get_parent()
	while n and not n is CanvasLayer:
		n = n.get_parent()
	return n if n else get_tree().root


func _toggle() -> void:
	if menu.visible:
		menu.close()
		return
	menu.open_at(get_global_rect(), _host())
	_restyle_open()


func _restyle_open() -> void:
	var open: bool = menu.visible
	_chevron.texture = FNIcons.texture(&"chevron_up" if open else &"chevron_down", FNUI.ICON_S - 2)
	add_theme_stylebox_override("normal", _box(&"selected" if open else &"normal"))


func _box(state: StringName) -> StyleBoxFlat:
	var sb := FNUI.state_style(state, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	return sb


func _exit_tree() -> void:
	menu.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(menu):
		menu._catcher.queue_free()
		menu.queue_free()
