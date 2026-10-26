## Start screen (GAMEPLAY-01B): New Game, Continue, Development Scenario, Quit - on the UI-01C kit, over the
## world that is already loaded behind it (the terrain is the backdrop). Chooses only; CoreDemo starts the
## scenario. Continue is offered when a save exists; an unreadable save is shown as an error and the menu stays.
## Laid out in the 1152 x 648 logical canvas (stretch mode canvas_items), so 1920 x 1080 and 1280 x 720 scale it.
class_name MainMenu
extends CanvasLayer

## "new_game", "continue", "dev" or "quit".
signal chosen(action: String)

## {ok, reason, scenario, title, time} of the save (CoreDemo.peek_save), set before the menu is shown.
var save_info := {}

var _status: Label
var _buttons := {}
var _root: Control


func _ready() -> void:
	layer = 90
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = FNUI.theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(FNUI.BG, 0.88)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	# A darker band behind the menu column, so the text never sits on bright terrain.
	var band := ColorRect.new()
	band.anchor_bottom = 1.0
	band.offset_right = 470.0
	band.color = Color(FNUI.BG, 0.72)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(band)
	var edge := ColorRect.new()
	edge.anchor_bottom = 1.0
	edge.offset_left = 470.0
	edge.offset_right = 471.0
	edge.color = Color(FNUI.LINE_STRONG, 0.6)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)
	var col := VBoxContainer.new()
	col.position = Vector2(72, 92)
	col.custom_minimum_size = Vector2(330, 0)
	col.add_theme_constant_override("separation", FNUI.S3)
	_root.add_child(col)
	var title := FNUI.label("FRACTURED NATIONS", 34, FNUI.INK, "title")
	title.add_theme_font_override("font", FNUI.font("bold", true, 3))
	col.add_child(title)
	var sub := FNUI.label("Persistent military sandbox", FNUI.TITLE, FNUI.INK_2, "caps")
	col.add_child(sub)
	col.add_child(_rule(48))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)
	_entry(col, "new_game", "New Game", "One North squad of eight in the south. No base, little supply: find caches, build a Command Post, grow from there.")
	_entry(col, "continue", "Continue", "")
	_entry(col, "dev", "Development Scenario", "The full three-faction war with North HQ, five squads and free construction. Test environment.")
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap2)
	_entry(col, "settings", "Settings", "")
	_entry(col, "quit", "Quit", "")
	_status = FNUI.label("", FNUI.LABEL, FNUI.DANGER, "caps")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(330, 0)
	col.add_child(_status)
	var foot := FNUI.label("F1 in game shows the controls", FNUI.CAPTION, FNUI.INK_3, "caps")
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 72.0
	foot.offset_top = -34.0
	_root.add_child(foot)
	refresh()


func _rule(w: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = FNUI.OK
	r.custom_minimum_size = Vector2(w, 2)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _entry(parent: Container, action: String, text: String, info: String) -> void:
	var b := Button.new()
	b.text = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(330, 34)
	b.add_theme_font_override("font", FNUI.font("semibold", true, 2))
	b.add_theme_font_size_override("font_size", FNUI.HEADLINE)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := FNUI.state_style(&"hover" if st == "focus" else StringName(st), 0)
		sb.content_margin_left = 12
		if st == "normal":
			sb.bg_color = Color(FNUI.BG_RAISED, 0.55)
			sb.border_color = Color(FNUI.LINE, 0.0)
		if st in ["hover", "focus"]:
			sb.border_width_left = 3
			sb.border_color = FNUI.OK
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func() -> void: _choose(action))
	parent.add_child(b)
	var l := FNUI.label(info, FNUI.LABEL, FNUI.INK_2, "body")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	l.visible = info != ""
	parent.add_child(l)
	_buttons[action] = [b, l]


func refresh() -> void:
	if not _buttons.has("continue"):
		return
	var b: Button = _buttons["continue"][0]
	var l: Label = _buttons["continue"][1]
	var ok := bool(save_info.get("ok", false))
	b.disabled = not ok
	if ok:
		l.text = "%s  ·  %s game time" % [save_info.get("title", "Saved game"), _clock(float(save_info.get("time", 0.0)))]
	elif save_info.get("reason", "") != "":
		l.text = String(save_info.reason)
	else:
		l.text = "No saved game"
	l.add_theme_color_override("font_color", FNUI.INK_2 if ok or save_info.get("missing", true) else FNUI.DANGER)
	l.visible = true
	(_buttons["new_game"][0] as Button).grab_focus.call_deferred()


func show_error(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _choose(action: String) -> void:
	# GAMEPLAY-02 (controls): the settings screen opens over the start screen; it does not start anything.
	if action == "settings":
		_open_settings()
		return
	if action == "continue" and not bool(save_info.get("ok", false)):
		show_error("Cannot continue: %s" % save_info.get("reason", "no saved game"))
		return
	show_error("")
	chosen.emit(action)


func _open_settings() -> void:
	if has_node("Settings"):
		return
	var sp := SettingsPanel.new()
	sp.name = "Settings"
	add_child(sp)
	sp.closed.connect(func() -> void: (_buttons["settings"][0] as Button).grab_focus.call_deferred())


static func _clock(t: float) -> String:
	return "%d:%02d:%02d" % [int(t / 3600.0), int(t / 60.0) % 60, int(t) % 60]
