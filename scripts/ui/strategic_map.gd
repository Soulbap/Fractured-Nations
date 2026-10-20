## The strategic map (WORLD-SANDBOX-01): the whole 20 x 20 km world from above, for
## commanding the player's faction. It is a view of the same WorldState as the RTS and
## FPS cameras, not a separate simulation: markers are drawn from unit, squad, objective
## and operation records, and every order goes through WarSim / SquadControl.
##
## Shows the terrain (the world's own macro preview: forests, fields, roads, river,
## lakes), territory (each objective's area of control in its owner's colour), objectives
## with owner, capture progress and contested state, the player's squads, enemy forces
## the player's faction knows about (WarSim intelligence - never every enemy), the
## player's operations with their routes, and fights.
##
## Controls: M / Esc close; wheel zoom; middle-drag or WASD pan; LMB select a squad or an
## objective (Shift adds, drag = box); RMB order the selected squads: on an enemy or
## neutral objective ATTACK, on an own objective REINFORCE, on open ground MOVE; buttons
## for Defend / Cancel; G (or "View") jumps the tactical camera there; , and . change
## the time compression.
class_name StrategicMap
extends Control

signal closed

var sim: WorldSim
var demo: CoreDemo
var faction := 0
## World metres per screen pixel = 1 / zoom; view_center in world x / z.
var zoom := 0.04
var view_center := Vector2.ZERO
var selected_squads: Array[int] = []
var selected_objective := -1
var _bg: Texture2D
var _territory: ImageTexture
var _territory_key := ""
var _drag_from := Vector2.INF
var _pan_from := Vector2.INF
var _box := false
var _panel: VBoxContainer
var _info: RichTextLabel
var _ops_box: VBoxContainer
var _log: RichTextLabel
var _buttons := {}
var _redraw_t := 0.0
var half := 10000.0
const PANEL_W := 360.0
## Squads standing at an objective are drawn in a row beside it (not on its label).
var _marker_slots := {}
var _drawn_at := {}
const TERRITORY_RES := 160


func setup(p_demo: CoreDemo) -> void:
	demo = p_demo
	sim = demo.sim
	faction = sim.state.war.player_faction
	half = demo.config.half_size()
	var path := "res://worlds/%s/source/preview_macro.png" % demo.config.world_name
	if ResourceLoader.exists(path):
		_bg = load(path)
	_build_panel()
	fit_all()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## Whole map in view.
func fit_all() -> void:
	var vs := get_viewport_rect().size if is_inside_tree() else Vector2(1600, 900)
	zoom = minf((vs.x - PANEL_W - 40.0) / (half * 2.0), (vs.y - 60.0) / (half * 2.0))
	view_center = Vector2(0.0, 0.0)


func map_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size.x - PANEL_W, size.y))


func to_screen(p: Vector3) -> Vector2:
	var r := map_rect()
	return r.get_center() + (Vector2(p.x, p.z) - view_center) * zoom


func to_world(s: Vector2) -> Vector3:
	var r := map_rect()
	var w := view_center + (s - r.get_center()) / zoom
	var h: float = sim.terrain.data.get_height(Vector3(w.x, 0, w.y)) if sim.terrain else 0.0
	return Vector3(w.x, 0.0 if is_nan(h) else h, w.y)


# --- Panel ------------------------------------------------------------------------------

func _build_panel() -> void:
	var bg := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.09, 1.0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	bg.add_theme_stylebox_override("panel", sb)
	bg.anchor_left = 1.0
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_left = -PANEL_W
	add_child(bg)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	bg.add_child(_panel)
	_info = _label(13)
	_info.custom_minimum_size = Vector2(PANEL_W - 24, 190)
	_panel.add_child(_info)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	_panel.add_child(row)
	for b: Array in [["attack", "Attack"], ["defend", "Defend"], ["reinforce", "Reinforce"], ["move", "Move"], ["cancel", "Cancel op"], ["view", "View (G)"]]:
		var btn := Button.new()
		btn.text = b[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		var key: String = b[0]
		btn.pressed.connect(func() -> void: _button(key))
		row.add_child(btn)
		_buttons[key] = btn
	var h1 := _label(14)
	h1.text = "[b]Operations[/b]"
	h1.custom_minimum_size = Vector2(0, 22)
	_panel.add_child(h1)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_W - 24, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_ops_box = VBoxContainer.new()
	_ops_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ops_box)
	var h2 := _label(14)
	h2.text = "[b]War log[/b]"
	h2.custom_minimum_size = Vector2(0, 22)
	_panel.add_child(h2)
	_log = _label(12)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_log)


func _label(fs: int) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", fs)
	l.add_theme_font_size_override("bold_font_size", fs)
	return l


func _process(delta: float) -> void:
	if not visible:
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if pan != Vector2.ZERO:
		view_center += pan * delta * 700.0 / zoom * 0.05
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.05
		_refresh_panel()
		queue_redraw()


func _refresh_panel() -> void:
	var war := sim.state.war
	var t := sim.state.time
	var lines: Array[String] = []
	lines.append("[b]STRATEGIC MAP[/b]  %s  ·  war time %d:%02d  ·  speed %dx" % [_fac(faction), int(t / 3600.0), int(t / 60.0) % 60, int(Engine.time_scale)])
	for f: FactionState in war.factions.values():
		var objs := war.owned_by(f.id).size()
		if f.id == faction:
			var soldiers := 0
			for sq: SquadState in sim.war.squads_of(f.id):
				soldiers += sq.members.size()
			lines.append("%s  %d objectives · %d soldiers · %d reserve · %d fallen" % [_fac(f.id), objs, soldiers, f.reserves, f.casualties])
		else:
			lines.append("%s  %d objectives · %s" % [_fac(f.id), objs, "AI " + sim.war.profile(f).display_name.to_lower()])
	lines.append("")
	if not selected_squads.is_empty():
		var n := 0
		var names: Array[String] = []
		for sid in selected_squads:
			var sq := sim.state.get_squad(sid)
			if sq:
				n += sq.members.size()
				var op := war.operation(sq.op_id)
				names.append("%s (%d%s)" % [sq.squad_name, sq.members.size(), (", " + op.type_name() + " #%d" % op.id) if op else ""])
		lines.append("[b]Selected[/b]: %d squads, %d soldiers" % [names.size(), n])
		lines.append(", ".join(names.slice(0, 6)) + (" ..." if names.size() > 6 else ""))
		lines.append("[color=#aab]RMB: enemy/neutral objective = attack, own = reinforce, ground = move[/color]")
	elif selected_objective >= 0:
		var o := war.objective(selected_objective)
		if o:
			lines.append("[b]%s[/b] (%s, value %d)" % [o.obj_name, o.kind, o.value])
			lines.append("Owner: %s%s" % [_fac(o.owner) if o.owner >= 0 else "nobody", "  [color=#ff6]CONTESTED[/color]" if o.contested else ""])
			if o.capture_faction >= 0:
				lines.append("Being taken by %s: %d %%" % [_fac(o.capture_faction), int(o.capture_progress * 100)])
			var own: int = o.presence.get(faction, 0)
			lines.append("Own soldiers there: %d · known enemies near: %d" % [own, sim.war.known_near(faction, o.position, o.radius + 300.0)])
	else:
		lines.append("[color=#aab]Click a squad or an objective. Drag a box to select squads.[/color]")
	_info.text = "\n".join(lines)
	_refresh_ops()
	var log_lines: Array[String] = []
	for e: Dictionary in sim.war.events_for(faction, 12):
		var col := "#ddd"
		match e.kind:
			"captured":
				col = "#ffd060"
			"contested", "threat", "attack":
				col = "#ff8a70"
			"op_done", "reinforcements":
				col = "#90e090"
			"op_failed":
				col = "#ff6060"
		log_lines.append("[color=#889]%02d:%02d[/color] [color=%s]%s[/color]" % [int(e.t / 3600.0) % 24, int(e.t / 60.0) % 60, col, e.text])
	_log.text = "\n".join(log_lines)
	var has_sel := not selected_squads.is_empty()
	for k in ["attack", "defend", "reinforce", "move"]:
		_buttons[k].disabled = not has_sel
	_buttons["cancel"].disabled = not has_sel or not selected_squads.any(func(s: int) -> bool: return sim.state.get_squad(s) != null and sim.state.get_squad(s).op_id >= 0)


func _refresh_ops() -> void:
	var ops := sim.state.war.active_operations(faction)
	var key := str(ops.map(func(o: OperationState) -> String: return "%d%d%d" % [o.id, o.phase, o.squads.size()]))
	if _ops_box.get_meta("key", "") == key:
		return
	_ops_box.set_meta("key", key)
	for c in _ops_box.get_children():
		c.queue_free()
	if ops.is_empty():
		var l := _label(12)
		l.text = "[color=#889]No operations. Select squads, then RMB on a target.[/color]"
		_ops_box.add_child(l)
	for op: OperationState in ops:
		var row := HBoxContainer.new()
		var l := _label(12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var obj := sim.state.war.objective(op.target_objective)
		var soldiers := 0
		for sid in op.squads:
			var sq := sim.state.get_squad(sid)
			if sq:
				soldiers += sq.members.size()
		l.text = "#%d [b]%s[/b] %s · %s · %d sq / %d" % [op.id, op.type_name(), obj.obj_name if obj else "point", op.phase_name(), op.squads.size(), soldiers]
		row.add_child(l)
		for b: Array in [["Go", func() -> void: go_to(op.target_pos)], ["✕", func() -> void: sim.war.cancel(op.id, "cancelled by the player")]]:
			var btn := Button.new()
			btn.text = b[0]
			btn.focus_mode = Control.FOCUS_NONE
			btn.add_theme_font_size_override("font_size", 12)
			btn.pressed.connect(b[1])
			row.add_child(btn)
		_ops_box.add_child(row)


static func _fac(f: int) -> String:
	return "[color=#%s]%s[/color]" % [WorldState.faction_color(f).to_html(false), WorldState.faction_name(f)]


# --- Orders -----------------------------------------------------------------------------

func _button(key: String) -> void:
	match key:
		"attack":
			if selected_objective >= 0:
				order(OperationState.Type.ATTACK, selected_objective)
		"defend":
			if selected_objective >= 0:
				order(OperationState.Type.DEFEND, selected_objective)
		"reinforce":
			if selected_objective >= 0:
				order(OperationState.Type.REINFORCE, selected_objective)
		"move":
			pass  # RMB on the ground
		"cancel":
			for sid in selected_squads:
				var sq := sim.state.get_squad(sid)
				if sq and sq.op_id >= 0:
					sim.war.cancel(sq.op_id, "cancelled by the player")
		"view":
			go_to_selection()


## Gives the selected squads an operation (the player's command): they leave whatever
## they were doing.
func order(type: OperationState.Type, objective_id := -1, point := Vector3.INF) -> OperationState:
	if selected_squads.is_empty():
		return null
	return sim.war.start_operation(faction, type, selected_squads.duplicate(), objective_id, point, true)


func _order_at(sp: Vector2) -> void:
	if selected_squads.is_empty():
		return
	var oid := _objective_at(sp)
	var war := sim.state.war
	if oid >= 0:
		var o := war.objective(oid)
		order(OperationState.Type.REINFORCE if o.owner == faction else OperationState.Type.ATTACK, oid)
	else:
		order(OperationState.Type.MOVE, -1, to_world(sp))


func go_to(p: Vector3) -> void:
	demo.rts_camera.frame(p, demo.rts_camera.yaw, 120.0)
	close()


func go_to_selection() -> void:
	if not selected_squads.is_empty():
		var sq := sim.state.get_squad(selected_squads[0])
		if sq:
			demo.rts.select_squads(selected_squads.duplicate())
			go_to(sim.war.squad_center(sq))
			return
	var o := sim.state.war.objective(selected_objective)
	if o:
		go_to(o.position)


func close() -> void:
	visible = false
	closed.emit()


# --- Input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not map_rect().has_point(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var before := to_world(mb.position)
				zoom = clampf(zoom * (1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 0.03, 1.5)
				var after := to_world(mb.position)
				view_center += Vector2(before.x - after.x, before.z - after.z)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_from = mb.position if mb.pressed else Vector2.INF
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.position
				_box = false
			else:
				if _box:
					_box_select(Rect2(_drag_from, mb.position - _drag_from).abs(), mb.shift_pressed)
				else:
					_click(mb.position, mb.shift_pressed)
				_drag_from = Vector2.INF
				_box = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_order_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_from.is_finite():
			view_center -= mm.relative / zoom
		elif _drag_from.is_finite() and mm.position.distance_to(_drag_from) > 6.0:
			_box = true
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_G:
				go_to_selection()
				accept_event()
			KEY_HOME:
				fit_all()
				accept_event()


func _click(sp: Vector2, add: bool) -> void:
	var sid := _squad_at(sp)
	if sid >= 0:
		if not add:
			selected_squads.clear()
		if not selected_squads.has(sid):
			selected_squads.append(sid)
		selected_objective = -1
		return
	var oid := _objective_at(sp)
	if not add:
		selected_squads.clear()
	selected_objective = oid


func _box_select(r: Rect2, add: bool) -> void:
	if not add:
		selected_squads.clear()
	for sq: SquadState in sim.war.squads_of(faction):
		if r.has_point(to_screen(sim.war.squad_center(sq))) and not selected_squads.has(sq.id):
			selected_squads.append(sq.id)
	selected_objective = -1


func _squad_at(sp: Vector2) -> int:
	var best := -1
	var bd := 16.0
	for sq: SquadState in sim.war.squads_of(faction):
		var at: Vector2 = _drawn_at.get(sq.id, to_screen(sim.war.squad_center(sq)))
		var d := at.distance_to(sp)
		if d < bd:
			bd = d
			best = sq.id
	return best


func _objective_at(sp: Vector2) -> int:
	var best := -1
	var bd := 18.0
	for o: ObjectiveState in sim.state.war.objectives.values():
		var d := to_screen(o.position).distance_to(sp)
		if d < maxf(bd, o.radius * zoom):
			bd = d
			best = o.id
	return best


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var r := map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.07))
	var tl := to_screen(Vector3(-half, 0, -half))
	var br := to_screen(Vector3(half, 0, half))
	var map_area := Rect2(tl, br - tl)
	if _bg:
		draw_texture_rect(_bg, map_area, false, Color(0.82, 0.86, 0.82))
	_update_territory()
	if _territory:
		draw_texture_rect(_territory, map_area, false, Color(1, 1, 1, 0.42))
	_draw_grid(map_area)
	var font := ThemeDB.fallback_font
	var war := sim.state.war
	# Operations of the player's faction: routes and arrows.
	for op: OperationState in war.active_operations(faction):
		_draw_operation(op, font)
	# Objectives.
	for o: ObjectiveState in war.all_objectives():
		_draw_objective(o, font)
	# Known enemy forces (clusters), then own squads on top.
	_draw_known_enemies(font)
	_marker_slots.clear()
	for sq: SquadState in sim.war.squads_of(faction):
		_draw_squad(sq, font)
	# The tactical camera / possessed soldier.
	var cam := to_screen(demo.rts_camera.focus)
	draw_arc(cam, 9.0, 0.0, TAU, 16, Color(1, 1, 1, 0.8), 1.5)
	draw_line(cam + Vector2(-13, 0), cam + Vector2(-6, 0), Color.WHITE, 1.5)
	draw_line(cam + Vector2(6, 0), cam + Vector2(13, 0), Color.WHITE, 1.5)
	if _box and _drag_from.is_finite():
		var m := get_local_mouse_position()
		var br2 := Rect2(_drag_from, m - _drag_from).abs()
		draw_rect(br2, Color(1, 1, 1, 0.1), true)
		draw_rect(br2, Color(1, 1, 1, 0.8), false, 1.0)
	# Scale bar and help.
	var km := 1000.0 * zoom
	var sb_at := Vector2(20, size.y - 28)
	draw_line(sb_at, sb_at + Vector2(km, 0), Color.WHITE, 2.0)
	draw_string(font, sb_at + Vector2(0, -6), "1 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	draw_string(font, Vector2(20, 24), "M / Esc close · wheel zoom · MMB-drag / WASD pan · Home whole map · LMB select (drag box) · RMB order · G view in 3D · , . time speed",
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 40, 13, Color(0.9, 0.92, 0.85))


func _draw_grid(area: Rect2) -> void:
	var c := Color(1, 1, 1, 0.06)
	for k in range(-10, 11, 2):
		var x := to_screen(Vector3(k * 1000.0, 0, 0)).x
		var y := to_screen(Vector3(0, 0, k * 1000.0)).y
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), c, 1.0)
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), c, 1.0)


## Territory: each 100 m cell belongs to the nearest objective within its reach
## (1.6 km + 0.6 km per value point), coloured by that objective's owner; boundaries
## between owners are drawn darker. Rebuilt only when ownership changes.
func _update_territory() -> void:
	var war := sim.state.war
	var key := ""
	for o: ObjectiveState in war.all_objectives():
		key += "%d:%d," % [o.id, o.owner]
	if key == _territory_key and _territory:
		return
	_territory_key = key
	var n := TERRITORY_RES
	var owner := PackedInt32Array()
	owner.resize(n * n)
	var objs := war.all_objectives()
	for z in n:
		for x in n:
			var p := Vector2(-half + (x + 0.5) * half * 2.0 / n, -half + (z + 0.5) * half * 2.0 / n)
			var best := -1
			var bd := INF
			for o: ObjectiveState in objs:
				var d := p.distance_to(Vector2(o.position.x, o.position.z)) - (1600.0 + 600.0 * o.value)
				var raw := p.distance_to(Vector2(o.position.x, o.position.z))
				if d < 0.0 and raw < bd:
					bd = raw
					best = o.owner
			owner[z * n + x] = best
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for z in n:
		for x in n:
			var f := owner[z * n + x]
			if f < 0:
				img.set_pixel(x, z, Color(0, 0, 0, 0))
				continue
			var c := WorldState.faction_color(f)
			var edge := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, z) + d
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and owner[q.y * n + q.x] != f:
					edge = true
			img.set_pixel(x, z, Color(c.r, c.g, c.b, 0.95 if edge else 0.45))
	_territory = ImageTexture.create_from_image(img)


func _draw_objective(o: ObjectiveState, font: Font) -> void:
	var p := to_screen(o.position)
	var col := WorldState.faction_color(o.owner) if o.owner >= 0 else Color(0.85, 0.85, 0.85)
	var rr := maxf(o.radius * zoom, 7.0 + o.value * 2.0)
	draw_circle(p, rr, Color(col, 0.25))
	draw_arc(p, rr, 0.0, TAU, 32, Color(col, 0.9), 2.0)
	var s := 6.0 + o.value * 2.0
	match o.kind:
		&"hq":
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), Color(0.08, 0.08, 0.08, 0.9), true)
			draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), col, false, 2.5)
			_star(p, s * 0.7, col)
		&"bridge":
			draw_rect(Rect2(p - Vector2(s, s * 0.45), Vector2(s * 2.0, s * 0.9)), Color(0.08, 0.08, 0.08, 0.9), true)
			draw_line(p + Vector2(-s, -s * 0.45), p + Vector2(s, -s * 0.45), col, 2.0)
			draw_line(p + Vector2(-s, s * 0.45), p + Vector2(s, s * 0.45), col, 2.0)
		&"town":
			draw_circle(p, s, Color(0.08, 0.08, 0.08, 0.9))
			draw_arc(p, s, 0.0, TAU, 20, col, 2.5)
			draw_circle(p, s * 0.4, col)
		_:
			var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
			draw_colored_polygon(pts, Color(0.08, 0.08, 0.08, 0.9))
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
	if o.capture_faction >= 0 and o.capture_progress > 0.0:
		draw_arc(p, rr + 5.0, -PI * 0.5, -PI * 0.5 + TAU * o.capture_progress, 32, WorldState.faction_color(o.capture_faction), 4.0)
	if o.contested:
		var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		draw_arc(p, rr + 10.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.2, 0.5 + 0.5 * blink), 2.5)
	if o.id == selected_objective:
		draw_arc(p, rr + 14.0, 0.0, TAU, 32, Color(1, 1, 0.4), 2.0)
	var label := o.obj_name
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var lp := p + Vector2(-w * 0.5, rr + 17.0)
	draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
	draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))


func _star(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * TAU / 10.0
		pts.append(p + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


## Screen position of a squad's marker: its centre, or - when it stands at an objective -
## the next free place in a row to the right of the objective's symbol.
func squad_marker_pos(sq: SquadState, c: Vector3) -> Vector2:
	var p := to_screen(c)
	for o: ObjectiveState in sim.state.war.objectives.values():
		if Vector2(o.position.x - c.x, o.position.z - c.z).length() <= o.radius:
			var k: int = _marker_slots.get(o.id, 0)
			_marker_slots[o.id] = k + 1
			var op := to_screen(o.position)
			p = op + Vector2(28.0 + 38.0 * (k % 3), -12.0 + 32.0 * (k / 3))
			break
	_drawn_at[sq.id] = p
	return p


## NATO-style infantry symbol: a framed rectangle with a cross, strength under it.
func _draw_squad(sq: SquadState, font: Font) -> void:
	var c := sim.war.squad_center(sq)
	var p := squad_marker_pos(sq, c)
	var col := WorldState.faction_color(sq.faction)
	var sel := selected_squads.has(sq.id)
	var rect := Rect2(p - Vector2(11, 7), Vector2(22, 14))
	draw_rect(rect, Color(col.darkened(0.55), 0.95), true)
	draw_rect(rect, Color(1, 1, 0.4) if sel else col.lightened(0.3), false, 2.5 if sel else 1.5)
	draw_line(rect.position, rect.end, col.lightened(0.4), 1.2)
	draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), col.lightened(0.4), 1.2)
	var fighting := false
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and (u.ai_state == UnitState.AiState.ENGAGING or u.under_fire_until > sim.state.time):
			fighting = true
			break
	if fighting:
		_swords(p + Vector2(15, -11), Color(1.0, 0.45, 0.3))
	var t := "%s·%d" % [sq.squad_name, sq.members.size()]
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string_outline(font, p + Vector2(-tw * 0.5, 19), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
	draw_string(font, p + Vector2(-tw * 0.5, 19), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _swords(p: Vector2, col: Color) -> void:
	draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), col, 2.0)
	draw_line(p + Vector2(5, -5), p + Vector2(-5, 5), col, 2.0)


## Enemy soldiers the player's faction knows about (WarSim.known), grouped into clusters
## of 150 m; older sightings fade.
func _draw_known_enemies(font: Font) -> void:
	var k: Dictionary = sim.war.known.get(faction, {})
	var clusters := []
	for id in k:
		var e: Array = k[id]
		var u := sim.state.get_unit(id)
		if u == null:
			continue
		var placed := false
		for c: Dictionary in clusters:
			if c.f == u.faction and Vector2(c.p.x - e[0].x, c.p.z - e[0].z).length() < 150.0:
				c.n += 1
				c.t = maxf(c.t, e[1])
				placed = true
				break
		if not placed:
			clusters.append({"p": e[0], "f": u.faction, "n": 1, "t": e[1]})
	for c: Dictionary in clusters:
		var p := to_screen(c.p)
		var age: float = sim.state.time - c.t
		var a := clampf(1.0 - age / sim.war.intel_forget_s, 0.25, 1.0)
		var col := WorldState.faction_color(c.f)
		var pts := PackedVector2Array([p + Vector2(0, -11), p + Vector2(11, 0), p + Vector2(0, 11), p + Vector2(-11, 0), p + Vector2(0, -11)])
		draw_colored_polygon(pts, Color(col.darkened(0.5), 0.85 * a))
		draw_polyline(pts, Color(col, a), 2.0)
		var t := "%d%s" % [c.n, "" if age < 5.0 else "?"]
		draw_string_outline(font, p + Vector2(-6, 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, a))
		draw_string(font, p + Vector2(-6, 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, a))


func _draw_operation(op: OperationState, font: Font) -> void:
	var col := WorldState.faction_color(op.faction).lightened(0.25)
	if op.type == OperationState.Type.ATTACK:
		col = Color(1.0, 0.45, 0.35)
	for sid in op.squads:
		var sq := sim.state.get_squad(sid)
		if sq == null:
			continue
		var pts := PackedVector2Array([to_screen(sim.war.squad_center(sq))])
		for i in range(sq.route_i, sq.route.size()):
			pts.append(to_screen(sq.route[i]))
		if pts.size() < 2:
			pts.append(to_screen(op.target_pos))
		for i in range(pts.size() - 1):
			if i % 2 == 0:
				draw_line(pts[i], pts[i + 1], Color(col, 0.85), 2.0)
	var tp := to_screen(op.target_pos)
	var label := "%s #%d · %s" % [op.type_name().to_upper(), op.id, op.phase_name()]
	draw_string_outline(font, tp + Vector2(14, -14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.85))
	draw_string(font, tp + Vector2(14, -14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
