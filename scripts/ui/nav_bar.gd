## UI-UX-03 main navigation of the tactical view, part of GameHUD: the game's major screens reachable by mouse, keys shown as
## accelerators. Two small panels on the top edge:
##   left   Map (M), Build (B), Development (F2), Base (selects the player's base building - its panel recruits, stores and
##          builds vehicles; repeated clicks go through the bases) and, where the scenario has it, the Armoury (F10);
##   right  pause and the four speeds (Space, 1-4), the war clock and the game menu (Esc).
## Only screens that exist are listed; one that cannot open now is disabled with the reason in its tooltip, and an open one
## shows the selected surface. Every button calls what its key calls (CoreDemo, ConstructionController, DevelopmentPanel, ...).
class_name HudNavBar
extends Control

const H := 22.0

var hud: GameHUD
var _left: FNPanel
var _right: FNPanel
var _buttons := {}
var _clock: Label
var _timer := 0.0
var _base_i := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	_left = _panel()
	_right = _panel()
	var lh := _row(_left)
	_add(lh, &"map", &"map", "Map", "M", "TACTICAL MAP  (M)\nThe whole war: territory, objectives, your forces, reported enemies, operations; order squads across the map.")
	_add(lh, &"build", &"build", "Build", "B", "CONSTRUCTION  (B)\nBases, defences, roads and facilities. Idle soldiers nearby build what you place.")
	_add(lh, &"development", &"development", "Development", "F2", "MILITARY DEVELOPMENT  (F2)\nResearch new structures, weapons and roles.")
	_add(lh, &"base", &"base", "Base", "", "BASE\nSelect your base building: recruit squads at the barracks, stores, vehicles. Click again for the next base.")
	_add(lh, &"armoury", &"armoury", "Armoury", "F10", "ARMOURY  (F10)\nDevelopment Scenario: give a soldier any weapon or role.")
	var rh := _row(_right)
	_add(rh, &"pause", &"pause", "", "", "PAUSE  (Space)\nStop the war while you give orders; the camera and orders still work.")
	for i in 4:
		var k := StringName("speed%d" % i)
		_add(rh, k, &"", "%dx" % [1, 2, 4, 8][i], "", "SPEED %d x  (%d)" % [[1, 2, 4, 8][i], i + 1])
	_clock = FNUI.label("", FNUI.LABEL, FNUI.INK_2, "number")
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.custom_minimum_size = Vector2(40, 0)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.tooltip_text = "War time"
	_clock.mouse_filter = Control.MOUSE_FILTER_PASS
	rh.add_child(_clock)
	_add(rh, &"menu", &"menu", "", "", "GAME MENU  (Esc)\nSave, load, settings, quit.")


func _panel() -> FNPanel:
	var p := FNPanel.new(Color.TRANSPARENT, 2)
	add_child(p)
	return p


func _row(p: FNPanel) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 2)
	p.add_child(h)
	return h


func _add(row: HBoxContainer, id: StringName, icon: StringName, text: String, key: String, tip: String) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(22 if text == "" else 0, H - 4)
	b.add_theme_font_size_override("font_size", FNUI.CAPTION)
	b.add_theme_constant_override("icon_max_width", FNUI.ICON_S)
	b.add_theme_constant_override("h_separation", 4)
	b.text = text.to_upper() + ("  " + key if key != "" else "")
	if icon != &"":
		b.icon = FNIcons.texture(icon, FNUI.ICON_S)
	b.pressed.connect(_on_pressed.bind(id))
	_style(b, false)
	row.add_child(b)
	_buttons[id] = b


func _style(b: Button, on: bool) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var state := StringName(st)
		if on:
			state = &"selected_hover" if st in ["hover", "hover_pressed"] else &"selected"
		elif st == "hover_pressed":
			state = &"pressed"
		var sb := FNUI.state_style(state, 0)
		if not on and st == "normal":
			sb.bg_color = Color.TRANSPARENT
			sb.border_color = Color.TRANSPARENT
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("icon_normal_color", FNUI.ACCENT.lightened(0.2) if on else FNUI.INK_2)
	b.add_theme_color_override("font_color", FNUI.INK if on else FNUI.INK_2)
	b.set_meta("on", on)


func _demo() -> CoreDemo:
	return hud.get_parent() as CoreDemo if hud else null


func entry_ids() -> Array:
	var out := []
	for id in _buttons:
		if (_buttons[id] as Button).visible:
			out.append(id)
	return out


func has_entry(id: StringName) -> bool:
	return _buttons.has(id) and (_buttons[id] as Button).visible


func button_rect(id: StringName) -> Rect2:
	return (_buttons[id] as Button).get_global_rect()


## The two panels' rectangles (left: navigation, right: time).
func left_rect() -> Rect2:
	return _left.get_global_rect()


func right_rect() -> Rect2:
	return _right.get_global_rect()


func bottom() -> float:
	return maxf(_left.position.y + _left.size.y, _right.position.y + _right.size.y) if visible else 0.0


func _on_pressed(id: StringName) -> void:
	var d := _demo()
	if d == null:
		return
	match id:
		&"map":
			d.toggle_map()
		&"build":
			if hud.construction:
				hud.construction.set_active(not hud.construction.active)
		&"development":
			if hud.construction and hud.construction.active:
				hud.construction.set_active(false)
			hud.development.toggle()
		&"base":
			_next_base()
		&"armoury":
			if d.armoury:
				d.armoury.visible = not d.armoury.visible
		&"pause":
			d.set_sim_paused(not d.sim_paused)
		&"menu":
			d.toggle_pause()
		_:
			if String(id).begins_with("speed"):
				d.set_speed_level(int(String(id).trim_prefix("speed")))
	_timer = 0.0


## The player's base buildings in base order: the headquarters / command post of each base, else its first facility.
func _base_buildings() -> Array:
	var out := []
	var pf := hud.rts.player_faction
	for b: Dictionary in hud.sim.logistics.bases.bases_of(pf):
		var best: StructureState = null
		for s: StructureState in hud.sim.state.construction.all():
			if s.faction != pf or s.base_id != int(b.id) or not FacilityDefs.has(s.type_id):
				continue
			if best == null or FacilityDefs.kind_of(s.type_id) == &"hq":
				best = s
		if best:
			out.append(best)
	return out


func _next_base() -> void:
	var list := _base_buildings()
	if list.is_empty():
		return
	_base_i = (_base_i + 1) % list.size()
	var s: StructureState = list[_base_i]
	var rts := hud.rts
	if hud.construction and hud.construction.active:
		hud.construction.set_active(false)
	rts.select([])
	rts.selected_structure = s.id
	rts.selection_changed.emit(rts.selected)
	if hud.game and hud.game.rts_camera:
		hud.game.rts_camera.frame(s.position, hud.game.rts_camera.yaw, maxf(hud.game.rts_camera.zoom, 90.0))


func _process(delta: float) -> void:
	var d := _demo()
	var show: bool = d != null and d.sandbox and hud.game != null and hud.game.mode == GameController.Mode.RTS and hud.war_sim != null and hud.war_sim.enabled
	visible = show
	if not show:
		return
	var vp := get_viewport_rect().size
	_left.position = Vector2(FNUI.EDGE, FNUI.EDGE)
	_left.size = Vector2.ZERO
	_right.size = Vector2.ZERO
	_right.position = Vector2(vp.x - _right.size.x - FNUI.EDGE, FNUI.EDGE)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	# What exists, what can open now, what is open.
	var dev_ok: bool = hud.development.available()
	var b_dev: Button = _buttons[&"development"]
	# A scenario without Military Development has no such screen: no entry.
	b_dev.visible = dev_ok
	var bases := _base_buildings()
	var b_base: Button = _buttons[&"base"]
	b_base.disabled = bases.is_empty()
	b_base.tooltip_text = "BASE\n" + ("Select your base building: recruit squads at the barracks, stores, vehicles.%s" % (" Click again for the next base (%d)." % bases.size() if bases.size() > 1 else "")
		if not bases.is_empty() else "You have no base yet: establish a Command Post (Build).")
	(_buttons[&"armoury"] as Button).visible = d.armoury != null
	var base_on := false
	var st := hud.sim.state.construction.get_structure(hud.rts.selected_structure) if hud.rts.selected_structure >= 0 else null
	if st and FacilityDefs.has(st.type_id):
		base_on = true
	var states := {&"map": d.strategic_map != null and d.strategic_map.visible, &"build": hud.construction != null and hud.construction.active,
		&"development": hud.development.visible, &"base": base_on, &"armoury": d.armoury != null and d.armoury.visible,
		&"pause": d.sim_paused, &"menu": d.menu_open()}
	var lv := [1.0, 2.0, 4.0, 8.0].find(Engine.time_scale)
	for i in 4:
		states[StringName("speed%d" % i)] = not d.sim_paused and lv == i
	for id in states:
		var b: Button = _buttons[id]
		if bool(b.get_meta("on", false)) != bool(states[id]):
			_style(b, states[id])
	(_buttons[&"pause"] as Button).icon = FNIcons.texture(&"play" if d.sim_paused else &"pause", FNUI.ICON_S)
	_clock.text = MainMenu._clock(hud.sim.state.time)
