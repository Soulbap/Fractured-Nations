## In-game menu (GAMEPLAY-01G): Esc pauses the game and offers Resume, Save Game, Load Game, Main Menu and Quit - on the
## UI-01C kit, laid out like the start screen (MainMenu) in the 1152 x 648 logical canvas. Chooses and reports only: the
## actions are CoreDemo's (save / load through ConstructionController, the start screen through a scene reload). Runs while
## the tree is paused (PROCESS_MODE_ALWAYS); the simulation is stopped meanwhile.
class_name PauseMenu
extends CanvasLayer

## "resume", "save", "load", "main_menu" or "quit".
signal chosen(action: String)

## Tests: after Main Menu reloads the game, the start screen takes a screenshot and quits (--campaign-test g_menu_return).
static var test_quit_on_menu := false

## {ok, reason, scenario, title, time} of the save slot (CoreDemo.peek_save), refreshed whenever the menu opens.
var save_info := {}

var _status: Label
var _buttons := {}
var _root: Control
var _confirm := ""


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = FNUI.theme()
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(FNUI.BG, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(shade)
	var panel := FNPanel.new(FNUI.OK, FNUI.S5)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", FNUI.S3)
	panel.add_child(col)
	var title := FNUI.label("PAUSED", 26, FNUI.INK, "title")
	title.add_theme_font_override("font", FNUI.font("bold", true, 3))
	col.add_child(title)
	_status = FNUI.label("", FNUI.LABEL, FNUI.INK_2, "body")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320, 0)
	col.add_child(_status)
	for e: Array in [["resume", "Resume", "Esc"], ["save", "Save Game", "F5"], ["load", "Load Game", "F9"], ["main_menu", "Main Menu", ""], ["quit", "Quit Game", ""]]:
		_entry(col, e[0], e[1], e[2])
	refresh()


func _entry(parent: Container, action: String, text: String, key: String) -> void:
	var b := Button.new()
	b.text = text.to_upper() + ("    " + key if key != "" else "")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(320, 34)
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
	_buttons[action] = b


func refresh() -> void:
	if not _buttons.has("load"):
		return
	var ok := bool(save_info.get("ok", false))
	(_buttons["load"] as Button).disabled = not ok
	(_buttons["load"] as Button).tooltip_text = ("%s · %s game time" % [save_info.get("title", "Saved game"), MainMenu._clock(float(save_info.get("time", 0.0)))]) if ok \
		else String(save_info.get("reason", "")) if String(save_info.get("reason", "")) != "" else "No saved game"
	_confirm = ""
	(_buttons["resume"] as Button).grab_focus.call_deferred()


## A line under the title: what the last action did (or why it could not).
func say(text: String, good := true) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", FNUI.INK_2 if good else FNUI.DANGER)


func _choose(action: String) -> void:
	# Leaving the game asks once: what was not saved is lost.
	if (action == "main_menu" or action == "quit") and _confirm != action:
		_confirm = action
		say("Unsaved progress is lost. Press %s again to confirm." % ("Main Menu" if action == "main_menu" else "Quit Game"), false)
		return
	if action == "load" and not bool(save_info.get("ok", false)):
		say("Cannot load: %s" % save_info.get("reason", "no saved game"), false)
		return
	chosen.emit(action)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		chosen.emit("resume")
