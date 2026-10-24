## Kit unit row: one unit in a roster - emblem, callsign, strength and status, with an optional
## trailing flag icon (e.g. hold fire). Hover and selected are surface states, not text colour;
## several rows can be selected at once. Click emits activated(shift).
class_name FNUnitRow
extends PanelContainer

signal activated(shift: bool)

var emblem: FNUnitEmblem
var callsign: Label
var strength: Label
var status: FNStatusIndicator
var flag: TextureRect
var selected := false:
	set(v):
		if v != selected:
			selected = v
			_restyle()
var _hover := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(0, 24)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", FNUI.S3)
	add_child(h)
	emblem = FNUnitEmblem.new(Vector2(20, 13))
	h.add_child(emblem)
	callsign = FNUI.label("", FNUI.BODY + 1, FNUI.INK, "title")
	callsign.custom_minimum_size = Vector2(40, 0)
	callsign.clip_text = true
	callsign.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(callsign)
	strength = FNUI.label("", FNUI.BODY, FNUI.INK, "number")
	strength.custom_minimum_size = Vector2(26, 0)
	h.add_child(strength)
	status = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(status)
	flag = FNIcons.rect(&"roe_hold", FNUI.ICON_S, FNUI.ARMED)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.visible = false
	h.add_child(flag)
	mouse_entered.connect(func() -> void:
		_hover = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hover = false
		_restyle())
	_restyle()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(ev.shift_pressed)
		accept_event()


## Strength as "alive/total", coloured by the share still fighting.
func set_strength(alive: int, total: int) -> void:
	strength.text = "%d/%d" % [alive, total]
	var r := float(alive) / maxf(total, 1)
	strength.add_theme_color_override("font_color", FNUI.INK if r >= 0.75 else (FNUI.WARN if r >= 0.5 else FNUI.DANGER))


func _restyle() -> void:
	var st := &"normal"
	if selected:
		st = &"selected_hover" if _hover else &"selected"
	elif _hover:
		st = &"hover"
	var sb := FNUI.state_style(st, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 7
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	if st == &"normal":
		# A roster line, not a button: faint fill, no frame until hovered or selected.
		sb.bg_color = Color(FNUI.BG_RAISED, 0.45)
		sb.set_border_width_all(0)
	add_theme_stylebox_override("panel", sb)
	queue_redraw()


func _draw() -> void:
	# Selected rows carry a solid bar on the left edge, so selection reads without colour too.
	if selected:
		draw_rect(Rect2(0, 0, 2, size.y), FNUI.ACCENT)
