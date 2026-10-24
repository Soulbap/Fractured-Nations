## GAMEPLAY-04B/04F Military Development screen, part of GameHUD (F2, or the DEVELOPMENT button of the tactical view):
## the three branches as columns of project cards (done / in development with progress / available / locked with the reason
## / future), and the chosen project's details - what it enables, prerequisites met or missing, cost, time - with Start or
## Cancel. Everything is read from and done through MilitaryDevelopment (WarSim.dev); the screen keeps only the selection.
## The game keeps running while it is open (it is the commander's planning view, not a pause).
class_name DevelopmentPanel
extends Control

const W := 820.0
const H := 470.0
const COL_W := 178.0

var hud: GameHUD
var _panel: FNPanel
var _stock: Label
var _running: Label
var _cols := {}
var _cards := {}
var _sel: StringName = &""
var _d_title: Label
var _d_state: FNStatusIndicator
var _d_summary: Label
var _d_body: Label
var _d_unlocks: Label
var _d_reqs: VBoxContainer
var _d_cost: Label
var _d_progress: FNMeter
var _start: Button
var _cancel: Button
var _say: Label
var _timer := 0.0
var _say_until := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	visible = false
	_panel = FNPanel.new(FNUI.ACCENT, FNUI.S5)
	_panel.custom_minimum_size = Vector2(W, H)
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", FNUI.S4)
	_panel.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", FNUI.S3)
	root.add_child(head)
	head.add_child(FNIcons.rect(&"development", FNUI.ICON_M, FNUI.ACCENT))
	head.add_child(FNUI.label("Military Development", FNUI.HEADLINE, FNUI.INK, "caps"))
	_stock = FNUI.label("", FNUI.LABEL, FNUI.INK_2, "body")
	_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_stock)
	head.add_child(FNKeyHint.new("F2", "Close"))
	_running = FNUI.label("", FNUI.LABEL, FNUI.INK, "body")
	root.add_child(_running)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", FNUI.S5)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	for b in DevelopmentDef.BRANCHES:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(COL_W, 0)
		col.add_theme_constant_override("separation", FNUI.S2 + 1)
		body.add_child(col)
		col.add_child(FNSectionHeader.new(DevelopmentDef.BRANCH_NAMES[b]))
		_cols[b] = col
		for d in DevelopmentDef.in_branch(b):
			var card := _make_card(d)
			col.add_child(card)
			_cards[d.id] = card
	body.add_child(_build_details())


func _make_card(d: DevelopmentDef) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(COL_W, 58)
	b.clip_contents = true
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_top = 4
	v.offset_right = -6
	v.offset_bottom = -4
	v.add_theme_constant_override("separation", 1)
	b.add_child(v)
	var name := FNUI.label(d.display_name, FNUI.BODY, FNUI.INK, "title")
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(name)
	var sm := FNUI.label(d.summary, FNUI.CAPTION, FNUI.INK_2, "body")
	sm.clip_text = true
	sm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sm)
	var st := FNStatusIndicator.new(FNUI.ICON_S, FNUI.CAPTION)
	v.add_child(st)
	var m := FNMeter.new("", FNUI.ACCENT)
	m.caption_w = 0.0
	m.custom_minimum_size = Vector2(COL_W - 20.0, 6)
	m.visible = false
	v.add_child(m)
	b.set_meta("status", st)
	b.set_meta("meter", m)
	b.set_meta("name", name)
	var id := d.id
	b.pressed.connect(func() -> void:
		_sel = id
		_refresh())
	return b


func _build_details() -> Control:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel", FNUI.box(Color(0, 0, 0, 0.25), Color(FNUI.LINE, 0.8), 1, 2, FNUI.S4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", FNUI.S3)
	box.add_child(v)
	_d_title = FNUI.label("", FNUI.TITLE + 1, FNUI.INK, "title")
	_d_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_d_title)
	_d_state = FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	v.add_child(_d_state)
	_d_progress = FNMeter.new("Progress", FNUI.ACCENT)
	_d_progress.custom_minimum_size = Vector2(200, 11)
	v.add_child(_d_progress)
	_d_summary = FNUI.label("", FNUI.LABEL, FNUI.INK, "body")
	_d_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_d_summary)
	_d_body = FNUI.label("", FNUI.CAPTION + 1, FNUI.INK_2, "body")
	_d_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_body.custom_minimum_size = Vector2(200, 0)
	v.add_child(_d_body)
	v.add_child(FNSectionHeader.new("Enables"))
	_d_unlocks = FNUI.label("", FNUI.CAPTION + 1, FNUI.INK, "body")
	_d_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_d_unlocks)
	v.add_child(FNSectionHeader.new("Requires"))
	_d_reqs = VBoxContainer.new()
	_d_reqs.add_theme_constant_override("separation", 0)
	v.add_child(_d_reqs)
	_d_cost = FNUI.label("", FNUI.LABEL, FNUI.INK, "body")
	_d_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_d_cost)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", FNUI.S3)
	v.add_child(row)
	_start = FNUI.action_button(&"development", "Start development", "Pay the cost and start the project")
	_start.pressed.connect(_on_start)
	row.add_child(_start)
	_cancel = FNUI.action_button(&"blocked", "Cancel", "Stop the project: its cost is refunded, progress is lost")
	_cancel.pressed.connect(_on_cancel)
	row.add_child(_cancel)
	_say = FNUI.label("", FNUI.CAPTION + 1, FNUI.WARN, "body")
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_say)
	return box


func _dev() -> MilitaryDevelopment:
	return hud.war_sim.dev if hud and hud.war_sim else null


func _faction() -> int:
	return hud.war_sim.war.player_faction


## Whether the screen can open (a war whose scenario uses Military Development).
func available() -> bool:
	return _dev() != null and hud.war_sim.enabled and _dev().enabled()


func toggle() -> void:
	if not available():
		visible = false
		return
	visible = not visible
	if visible:
		if _sel == &"" or DevelopmentDef.by_id(_sel) == null:
			_sel = _first_interesting()
		_refresh()
		if hud.war_sim.war.guide is Dictionary:
			hud.war_sim.war.guide["dev_opened"] = true


func _first_interesting() -> StringName:
	for d in DevelopmentDef.all():
		if _dev().status(_faction(), d.id).state in ["active", "available"]:
			return d.id
	return DevelopmentDef.all()[0].id if not DevelopmentDef.all().is_empty() else &""


func select(dev_id: StringName) -> void:
	_sel = dev_id
	_refresh()


func _on_start() -> void:
	var r := _dev().start(_faction(), _sel)
	_message("" if r.ok else "Cannot start: %s" % r.reason)
	_refresh()


func _on_cancel() -> void:
	_dev().cancel(_faction(), _sel)
	_refresh()


func _message(t: String) -> void:
	_say.text = t
	_say_until = Time.get_ticks_msec() / 1000.0 + 6.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2:
			if hud.game and hud.game.mode == GameController.Mode.RTS:
				toggle()
				get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE and visible:
			visible = false
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if not available() or (hud.game and hud.game.mode != GameController.Mode.RTS):
		visible = false
		return
	var vp := get_viewport_rect().size
	_panel.position = Vector2(roundf((vp.x - _panel.size.x) * 0.5), roundf(maxf((vp.y - _panel.size.y) * 0.5 - 20.0, FNUI.EDGE + 40.0)))
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_refresh()


func _refresh() -> void:
	var dev := _dev()
	if dev == null:
		return
	var f := _faction()
	var st := hud.sim.logistics.bases.faction_stock(f)
	_stock.text = "Supplies %d kg  ·  Ammunition %d kg" % [roundi(st.supplies), roundi(st.ammo)]
	var act: Array = dev.active_of(f)
	if act.is_empty():
		_running.text = "No project running - choose one below (%d at a time)." % dev.slots(f)
		_running.add_theme_color_override("font_color", FNUI.WARN)
	else:
		var parts: Array[String] = []
		for e: Dictionary in act:
			var d := DevelopmentDef.by_id(StringName(e.id))
			if d:
				parts.append("%s %d%%%s" % [d.display_name, roundi(float(e.progress) / maxf(d.time_s, 1.0) * 100.0), (" - " + String(e.why)) if String(e.get("why", "")) != "" else ""])
		_running.text = "In development: " + ", ".join(parts)
		_running.add_theme_color_override("font_color", FNUI.INK)
	for id in _cards:
		var card: Button = _cards[id]
		var s := dev.status(f, id)
		var ind: FNStatusIndicator = card.get_meta("status")
		var m: FNMeter = card.get_meta("meter")
		var name: Label = card.get_meta("name")
		m.visible = s.state == "active"
		match s.state:
			"done":
				ind.set_status(&"check", "Developed", FNUI.OK)
			"active":
				ind.set_status(&"clock", "In development" if String(s.reason) == "" else String(s.reason), FNUI.ACCENT if String(s.reason) == "" else FNUI.WARN)
				m.set_value(float(s.progress), "%d%%" % roundi(float(s.progress) * 100.0))
			"available":
				ind.set_status(&"development", "Available", FNUI.ARMED)
			"future":
				ind.set_status(&"blocked", "Future capability", FNUI.INK_3)
			_:
				ind.set_status(&"locked", String(s.reason), FNUI.INK_3 if not s.get("blocked_by_cost", false) else FNUI.WARN)
		name.add_theme_color_override("font_color", FNUI.INK_3 if s.state in ["future", "locked"] else FNUI.INK)
		var sb := FNUI.state_style(&"selected" if id == _sel else &"normal", 0)
		if id != _sel:
			sb.bg_color = Color(FNUI.BG_RAISED, 0.55)
			sb.border_color = Color(FNUI.OK if s.state == "done" else FNUI.LINE, 0.7)
		for k in ["normal", "hover", "pressed"]:
			card.add_theme_stylebox_override(k, sb)
	_refresh_details(dev, f)
	if Time.get_ticks_msec() / 1000.0 > _say_until:
		_say.text = ""


func _refresh_details(dev: MilitaryDevelopment, f: int) -> void:
	var d := DevelopmentDef.by_id(_sel)
	if d == null:
		return
	var s := dev.status(f, d.id)
	_d_title.text = d.display_name
	_d_summary.text = d.summary
	_d_body.text = d.description
	var u: Array[String] = []
	for sid in d.structures:
		var sd := StructureCatalog.get_def(sid)
		u.append("Build: " + (sd.display_name if sd else String(sid)))
	for wid in d.weapons:
		var wd := hud.sim.combat.weapon(wid)
		u.append("Weapon: " + (wd.display_name if wd else String(wid)))
	for rid in d.roles:
		var rd := InfantryRole.by_id(rid)
		u.append("Role: " + (rd.display_name if rd else String(rid)))
	if d.effects.has("intel_delay_mult"):
		u.append("Reports reach you in %d %% of the time" % roundi(float(d.effects.intel_delay_mult) * 100.0))
	if d.effects.has("dev_slots"):
		u.append("+%d development project at a time" % int(d.effects.dev_slots))
	_d_unlocks.text = "\n".join(u) if not u.is_empty() else "Known from the start."
	for c in _d_reqs.get_children():
		c.queue_free()
	var reqs := dev.requirements(f, d)
	if reqs.is_empty():
		_d_reqs.add_child(FNUI.label("Nothing", FNUI.CAPTION + 1, FNUI.INK_2, "body"))
	for r: Dictionary in reqs:
		var ind := FNStatusIndicator.new(FNUI.ICON_S, FNUI.CAPTION + 1)
		ind.set_status(&"check" if r.ok else &"blocked", String(r.text), FNUI.OK if r.ok else FNUI.WARN)
		ind.text_label.uppercase = false
		_d_reqs.add_child(ind)
	var cost := hud.sim.logistics.bases.cost_text(MilitaryDevelopment._cost(d)) if not d.cost.is_empty() else "free"
	_d_cost.text = "Cost %s  ·  Time %s" % [cost, MilitaryDevelopment._time_text(d.time_s)] if not d.initial else "Known from the start"
	_d_progress.visible = s.state == "active"
	_d_progress.set_value(float(s.progress), "%d%%" % roundi(float(s.progress) * 100.0))
	match s.state:
		"done":
			_d_state.set_status(&"check", "Developed", FNUI.OK)
		"active":
			_d_state.set_status(&"clock", "In development" if String(s.reason) == "" else String(s.reason), FNUI.ACCENT)
		"available":
			_d_state.set_status(&"development", "Available to start", FNUI.ARMED)
		"future":
			_d_state.set_status(&"blocked", "Future capability - cannot be started", FNUI.INK_3)
		_:
			_d_state.set_status(&"locked", "Locked: %s" % s.reason, FNUI.WARN)
	_start.visible = s.state in ["available", "locked"]
	_start.disabled = s.state != "available"
	_cancel.visible = s.state == "active"
