## Settings screen (GAMEPLAY-02 controls), opened from the start screen and the in-game menu: the interface scale (UISettings).
## On the UI-01C kit like the menus; runs while the tree is paused. The scale is applied when the slider is let go (applying it
## while dragging would move the slider under the mouse) and saved at once; Esc or Back closes the screen.
class_name SettingsPanel
extends CanvasLayer

signal closed

var _slider: HSlider
var _value: Label
var _dragging := false


func _ready() -> void:
	layer = 97
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = FNUI.theme()
	add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(FNUI.BG, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	var panel := FNPanel.new(FNUI.OK, FNUI.S5)
	panel.custom_minimum_size = Vector2(380, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", FNUI.S4)
	panel.add_child(col)
	var title := FNUI.label("SETTINGS", 26, FNUI.INK, "title")
	title.add_theme_font_override("font", FNUI.font("bold", true, 3))
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FNUI.S4)
	col.add_child(row)
	var name_l := FNUI.label("INTERFACE SCALE", FNUI.TITLE, FNUI.INK, "caps")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)
	_value = FNUI.label("", FNUI.TITLE, FNUI.OK, "caps")
	row.add_child(_value)
	_slider = HSlider.new()
	_slider.min_value = UISettings.SCALE_MIN * 100.0
	_slider.max_value = UISettings.SCALE_MAX * 100.0
	_slider.step = UISettings.SCALE_STEP * 100.0
	_slider.tick_count = int(round((UISettings.SCALE_MAX - UISettings.SCALE_MIN) / 0.25)) + 1
	_slider.ticks_on_borders = true
	_slider.custom_minimum_size = Vector2(340, 24)
	_slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_slider.value = UISettings.ui_scale * 100.0
	_slider.value_changed.connect(_on_value)
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(func(_changed: bool) -> void:
		_dragging = false
		_apply())
	col.add_child(_slider)
	var hint := FNUI.label("Text, buttons and panels of every menu and the HUD. Applied when you let go of the slider and kept for the next start.",
		FNUI.LABEL, FNUI.INK_2, "body")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(340, 0)
	col.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", FNUI.S4)
	col.add_child(buttons)
	buttons.add_child(_button("Reset (%d %%)" % int(round(UISettings.SCALE_DEFAULT * 100.0)), func() -> void:
		_slider.set_value_no_signal(UISettings.SCALE_DEFAULT * 100.0)
		_on_value(_slider.value)
		_apply()))
	var back := _button("Back    Esc", close)
	buttons.add_child(back)
	_on_value(_slider.value)
	_slider.grab_focus.call_deferred()


func _button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(160, 32)
	b.add_theme_font_override("font", FNUI.font("semibold", true, 2))
	b.add_theme_font_size_override("font_size", FNUI.TITLE)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := FNUI.state_style(&"hover" if st == "focus" else StringName(st), 0)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		if st in ["hover", "focus"]:
			sb.border_width_left = 3
			sb.border_color = FNUI.OK
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(fn)
	return b


func _on_value(v: float) -> void:
	_value.text = "%d %%" % int(round(v))
	# keyboard / click on the track: no drag, apply at once
	if not _dragging and is_node_ready() and absf(v / 100.0 - UISettings.ui_scale) > 0.001 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_apply()


func _apply() -> void:
	UISettings.set_ui_scale(get_tree(), _slider.value / 100.0)


func close() -> void:
	if _dragging:
		_apply()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
