## GAMEPLAY-04A/04F objective tracker, part of GameHUD: a small panel at the top right with the opening's phases (IntroGuide)
## - the situation while the first phase runs, the phases ticked off, the current one with what to do and how, and its
## distance - and a marker on its target in the tactical view. In first person it shrinks to the current objective. The x
## hides the guidance for this game (WarState.guide "off"; nothing in the world depends on it). Reads the records only.
## GAMEPLAY-04E: after the introduction it lists the open opportunities (Opportunities): accepted ones with what to do and a
## marker, offered ones with Accept / put aside.
class_name ObjectiveTracker
extends Control

const W := 268.0

var hud: GameHUD
var _panel: FNPanel
var _title: Label
var _brief: Label
var _list: VBoxContainer
var _foot: Label
var _timer := 0.0
var _sig := ""
## Tests read these: the current phase id and its target.
var current_id := ""
var target := Vector3.INF
var target_label := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = FNUI.theme()
	_panel = FNPanel.new(FNUI.ARMED, FNUI.S4)
	_panel.custom_minimum_size = Vector2(W, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", FNUI.S3)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", FNUI.S3)
	v.add_child(head)
	head.add_child(FNIcons.rect(&"mission", FNUI.ICON_M, FNUI.ARMED))
	_title = FNUI.label("Objectives", FNUI.LABEL, FNUI.INK, "caps")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Hide the guidance for this game (the objectives still count)"
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.pressed.connect(func() -> void:
		if hud.war_sim:
			hud.war_sim.war.guide["off"] = true)
	head.add_child(close)
	_brief = FNUI.label("", FNUI.CAPTION + 1, FNUI.INK_2, "body")
	_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief.custom_minimum_size = Vector2(W - 20.0, 0)
	v.add_child(_brief)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", FNUI.S2)
	v.add_child(_list)
	_foot = FNUI.label("", FNUI.CAPTION, FNUI.INK_3, "caps")
	v.add_child(_foot)
	_panel.visible = false


func _war() -> WarState:
	return hud.war_sim.war if hud and hud.war_sim else null


func _intro() -> IntroGuide:
	return hud.war_sim.intro if hud and hud.war_sim else null


## Shown while there is something to track, guidance is on and nothing else holds the right side of the screen.
func _wanted() -> bool:
	var w := _war()
	if w == null or not w.active or not hud.war_sim.enabled or w.guide.get("off", false) or hud.game == null:
		return false
	if hud.game.mode == GameController.Mode.DRIVE:
		return false
	if hud.construction and hud.construction.active:
		return false
	if hud.development and hud.development.visible:
		return false
	if hud.equipment and hud.equipment.visible:
		return false
	var it := _intro()
	if it.active() and not it.complete():
		return true
	# The closing line stays for a while after the introduction; then the opportunities take the panel (04E).
	if it.complete() and hud.sim.state.time - float(w.guide.get("intro_complete_at", 0.0)) < 25.0:
		return true
	return hud.war_sim.opps != null and not hud.war_sim.opps.open().is_empty()


func _process(delta: float) -> void:
	var w := _war()
	if w and w.active and hud.game:
		if hud.game.mode == GameController.Mode.FPS and not w.guide.get("fps", false):
			w.guide["fps"] = true
	var on := _wanted()
	_panel.visible = on
	queue_redraw()
	if not on:
		current_id = ""
		target = Vector3.INF
		return
	var vp := get_viewport_rect().size
	# First person keeps its squad box at the top right: the tracker goes below it.
	_panel.position = Vector2(vp.x - _panel.size.x - FNUI.EDGE, FNUI.EDGE + (72.0 if hud.game.mode == GameController.Mode.FPS else 0.0))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	_refresh()


func _refresh() -> void:
	var it := _intro()
	var fps := hud.game.mode == GameController.Mode.FPS
	var rows: Array = []
	if it.active() and not it.complete():
		var cur := it.current()
		current_id = String(cur.get("id", ""))
		target = it.target_pos(cur)
		target_label = String(cur.get("title", ""))
		_title.text = "Operation Foothold"
		var first: Dictionary = it.phases()[0] if not it.phases().is_empty() else {}
		_brief.text = String(_war().guide.get("briefing", "")) if not fps and not first.is_empty() and String(first.id) == current_id else ""
		for p: Dictionary in it.phases():
			if bool(p.get("optional", false)):
				continue
			var is_cur := String(p.id) == current_id
			if fps and not is_cur:
				continue
			rows.append({"title": p.title, "state": "done" if it.is_done(p) else ("current" if is_cur else "todo"),
				"text": "" if fps or not is_cur else String(p.get("text", "")), "tips": [] if fps or not is_cur else _tips(it, String(p.id))})
	elif it.complete() and hud.sim.state.time - float(_war().guide.get("intro_complete_at", 0.0)) < 25.0:
		current_id = ""
		target = Vector3.INF
		_title.text = "Foothold established"
		_brief.text = "" if fps else "The introduction is over. Capture ground for income, take up the opportunities offered on the map (M) and develop your force (F2)."
	else:
		current_id = ""
		_title.text = "Opportunities"
		_brief.text = ""
		target = Vector3.INF
		for o: Dictionary in hud.war_sim.opps.accepted():
			rows.append({"title": o.title, "state": "current", "text": "" if fps else String(o.get("text", "")), "tips": [], "opp": int(o.id), "accepted": true})
			if not target.is_finite():
				target = o.pos
				target_label = String(o.title)
		if not fps:
			for o: Dictionary in hud.war_sim.opps.offered():
				rows.append({"title": o.title, "state": "todo", "text": "", "tips": [], "opp": int(o.id), "accepted": false})
	var dist := ""
	if target.is_finite():
		var from := _from()
		if from.is_finite():
			dist = "%s · %d m" % [target_label, roundi(Vector2(target.x - from.x, target.z - from.z).length())]
	_foot.text = dist
	_foot.visible = dist != ""
	_brief.visible = _brief.text != ""
	var sig := str(rows) + _title.text + _brief.text
	if sig == _sig:
		_panel.size = Vector2.ZERO
		return
	_sig = sig
	for c in _list.get_children():
		c.queue_free()
	for r: Dictionary in rows:
		var ind := FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
		match r.state:
			"done":
				ind.set_status(&"check", r.title, FNUI.OK)
			"current":
				ind.set_status(&"objective", r.title, FNUI.ARMED)
			_:
				ind.set_status(&"idle", r.title, FNUI.INK_3)
		ind.text_label.uppercase = false
		ind.text_label.add_theme_font_override("font", FNUI.font("semibold"))
		if r.has("opp"):
			# GAMEPLAY-04E: an opportunity row - accept (tracked and marked) or put aside.
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", FNUI.S2)
			ind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ind.custom_minimum_size = Vector2(W - 110.0, 0)
			line.add_child(ind)
			var oid: int = r.opp
			if not r.accepted:
				var acc := FNUI.action_button(&"check", "Accept", "Track this opportunity (marked on the way). The reward comes whenever it is done, accepted or not")
				acc.pressed.connect(func() -> void:
					hud.war_sim.opps.accept(oid)
					_sig = ""
					_timer = 0.0)
				line.add_child(acc)
			var drop := Button.new()
			drop.text = "×"
			drop.flat = true
			drop.focus_mode = Control.FOCUS_NONE
			drop.tooltip_text = "Put this aside (it is not offered again)"
			drop.pressed.connect(func() -> void:
				hud.war_sim.opps.dismiss(oid)
				_sig = ""
				_timer = 0.0)
			line.add_child(drop)
			_list.add_child(line)
		else:
			_list.add_child(ind)
		if r.text != "":
			var l := FNUI.label(r.text, FNUI.CAPTION + 1, FNUI.INK, "body")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(W - 34.0, 0)
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_left", 16)
			m.add_child(l)
			_list.add_child(m)
		for t: Array in r.tips:
			var ti := FNStatusIndicator.new(FNUI.ICON_S - 2, FNUI.CAPTION)
			ti.set_status(&"check" if t[1] else &"idle", t[0], FNUI.OK if t[1] else FNUI.INK_2)
			ti.text_label.uppercase = false
			var m2 := MarginContainer.new()
			m2.add_theme_constant_override("margin_left", 16)
			m2.add_child(ti)
			_list.add_child(m2)
	_panel.size = Vector2.ZERO


## The optional tips shown under a phase: [text, done] for the optional phases that follow it in the list.
func _tips(it: IntroGuide, after_id: String) -> Array:
	var out := []
	var found := false
	for p: Dictionary in it.phases():
		if String(p.id) == after_id:
			found = true
			continue
		if not found:
			continue
		if not bool(p.get("optional", false)):
			break
		out.append([String(p.title), it.is_done(p)])
	return out


## Where distances are measured from: the possessed soldier, else the selected squad, else the player's first squad.
func _from() -> Vector3:
	if hud.game.mode == GameController.Mode.FPS and hud.game.possessed_body():
		return hud.game.possessed_body().global_position
	if hud.rts and not hud.rts.selected_squads().is_empty():
		var sel := hud.sim.state.get_squad(hud.rts.selected_squads()[0])
		if sel:
			return hud.war_sim.squad_center(sel)
	var sqs := hud.war_sim.squads_of(_war().player_faction)
	return hud.war_sim.squad_center(sqs[0]) if not sqs.is_empty() else Vector3.INF


func _draw() -> void:
	if not _panel.visible or not target.is_finite() or hud.game.mode != GameController.Mode.RTS:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := target + Vector3.UP * 8.0
	if cam.is_position_behind(at):
		return
	var s := cam.unproject_position(at)
	var col := FNUI.ARMED
	var font := FNUI.caps_font()
	draw_colored_polygon(PackedVector2Array([s + Vector2(-9, -14), s + Vector2(9, -14), s]), Color(0, 0, 0, 0.6))
	draw_colored_polygon(PackedVector2Array([s + Vector2(-7, -13), s + Vector2(7, -13), s + Vector2(0, -2)]), col)
	var txt := "OBJECTIVE · %s" % target_label.to_upper()
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL).x
	draw_string_outline(font, s + Vector2(-w * 0.5, -20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL, 3, Color(0, 0, 0, 0.8))
	draw_string(font, s + Vector2(-w * 0.5, -20), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.LABEL, col)
