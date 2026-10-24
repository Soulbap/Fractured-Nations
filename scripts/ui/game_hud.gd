## Minimal HUD: mode, controls, selection, unit summary, crosshair and drag box.
class_name GameHUD
extends CanvasLayer

@export var game: GameController
@export var rts: RTSController
@export var sim: WorldSim
@export var detail: DetailManager
@export var construction: ConstructionController

var _label: Label
var _overlay: Overlay
## UNIT-01A squad list (tactical view only).
var squad_panel: SquadPanel
## AI-SQUAD-01: tactical orders for the selected squads (bottom centre, only with a selection).
var tactical_panel: TacticalPanel
## LOGISTICS-01: selected vehicle / facility actions (tactical view).
var logistics_panel: LogisticsPanel
## COMBAT-01a first-person weapon panel (UI-01C: FPSHud) and feedback timers (seconds of real time).
var _fps: FPSHud
var hit_until := 0.0
var hit_kill := false
var hurt_until := 0.0
var death_note_until := 0.0
## Hits / kills the possessed soldier scored (tests read these).
var hits_seen := 0
var kills_seen := 0
## COMBAT-01b optional AI overlay (F4): state, target, sight and why a soldier is not
## firing, for every soldier near the camera, plus the brain's cost counters.
var combat_debug := false
## WORLD-SANDBOX-01: the war (null outside the sandbox) and its recent notifications.
var war_sim: WarSim:
	set(v):
		war_sim = v
		if v and not v.event_logged.is_connected(_on_war_event):
			v.event_logged.connect(_on_war_event)
var _notes: Array = []
var _notes_box: VBoxContainer
## WORLD-SANDBOX-01B: in the war the bottom text is short by default; F1 shows every
## control, F3 the technical counters (units, bodies, structures, detail tier).
var show_controls := false
var show_debug := false
## The player's faction, top centre (war only; first person and driving - in the tactical view the
## faction heads the Task Force roster).
var _badge: Label
## UI-01C: the tactical view's key hints, bottom left while nothing is selected (the command panel
## carries its own keys).
var _hints: FNPanel
## GAMEPLAY-01B: supply strip, next-step hint, cache and construction-site markers.
var economy: EconomyHud


class Overlay extends Control:
	var hud: GameHUD

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if hud.combat_debug:
			_draw_combat_debug()
		if hud.game and hud.game.mode == GameController.Mode.FPS:
			_draw_fps()
		elif hud.rts:
			_draw_squads()
			if hud.rts.dragging:
				var r := Rect2(hud.rts.drag_start, hud.rts.drag_current - hud.rts.drag_start).abs()
				draw_rect(r, Color(1, 1, 1, 0.12), true)
				draw_rect(r, Color(1, 1, 1, 0.85), false, 1.5)

	## COMBAT-01b debug: one tag per soldier within 400 m of the camera (name, AI state,
	## target, seen / remembered, reason it is not firing) and a line to its target: red
	## while visible, grey to the last known position while hidden.
	func _draw_combat_debug() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var font := ThemeDB.fallback_font
		var st := hud.sim.state
		var placed: Array[Vector2] = []
		var cols := {UnitState.AiState.ENGAGING: Color(1, 0.35, 0.3), UnitState.AiState.OBSERVING: Color(1, 0.9, 0.4),
			UnitState.AiState.LOST_TARGET: Color(1, 0.6, 0.2), UnitState.AiState.RELOADING: Color(0.4, 0.9, 1),
			UnitState.AiState.IDLE: Color(0.8, 0.8, 0.8), UnitState.AiState.DEAD: Color(0.4, 0.4, 0.4), UnitState.AiState.PLAYER: Color(0.6, 1, 0.6)}
		for u: UnitState in st.units.values():
			if u.kind != UnitState.Kind.SOLDIER or u.position.distance_to(cam.global_position) > 400.0:
				continue
			var head := u.position + Vector3.UP * 2.1
			if cam.is_position_behind(head):
				continue
			var p := cam.unproject_position(head)
			var col: Color = cols.get(u.ai_state, Color.WHITE)
			var t := st.get_unit(u.target_id)
			if t and u.alive:
				var a := u.position + Vector3.UP * 1.4
				var b := (t.position if u.target_visible else u.target_last_pos) + Vector3.UP * 1.2
				if b.is_finite() and not cam.is_position_behind(a) and not cam.is_position_behind(b):
					draw_line(cam.unproject_position(a), cam.unproject_position(b), Color(1, 0.2, 0.2, 0.7) if u.target_visible else Color(0.7, 0.7, 0.7, 0.5), 1.5)
			# Tags that would overlap one already drawn become a coloured dot.
			var crowded := false
			for q in placed:
				if absf(q.x - p.x) < 150.0 and absf(q.y - p.y) < 16.0:
					crowded = true
					break
			if crowded:
				draw_circle(p, 3.5, col)
				continue
			placed.append(p)
			# COMBAT-02: threat direction (orange, short), chosen cover (green ring) and the
			# temporary reaction goal (dashed line) - only for living soldiers near the camera.
			if u.alive:
				var base := u.position + Vector3.UP * 1.0
				if u.threat_pos.is_finite() and u.under_fire_until >= st.time:
					var tdir := (u.threat_pos - u.position)
					tdir.y = 0.0
					var tip := base + tdir.normalized() * 6.0
					if not cam.is_position_behind(base) and not cam.is_position_behind(tip):
						draw_line(cam.unproject_position(base), cam.unproject_position(tip), Color(1.0, 0.55, 0.1, 0.9), 2.0)
				if u.cover_pos.is_finite() and not cam.is_position_behind(u.cover_pos):
					var cp := cam.unproject_position(u.cover_pos + Vector3.UP * 0.1)
					draw_arc(cp, 6.0, 0.0, TAU, 12, Color(0.3, 1.0, 0.4, 0.9), 2.0)
				if u.is_reacting() and u.react_state == UnitState.ReactState.MOVING and not cam.is_position_behind(u.react_target):
					draw_dashed_line(cam.unproject_position(base), cam.unproject_position(u.react_target + Vector3.UP * 0.1), Color(0.3, 1.0, 0.4, 0.7), 1.5, 4.0)
			var text := "%s %s" % [u.unit_name, u.ai_state_name()]
			if u.alive and u.tactic != UnitState.Tactic.NONE:
				text += " / " + u.tactic_name()
			if u.alive and u.is_reacting():
				text += " (AI reaction)"
			elif u.alive and u.order == UnitState.Order.MOVE:
				text += " (order)"
			if t and u.alive:
				text += " > %s %s" % [t.unit_name, "seen" if u.target_visible else "mem %.0fs" % (st.time - u.target_seen_at)]
			if u.alive and u.ai_reason != "" and u.ai_reason != "no target":
				text += " [%s]" % u.ai_reason
			if u.alive and u.weapon_id != &"":
				text += " %d/%d" % [u.mag, u.reserve]
			if u.alive and u.cover_note != "" and u.tactic != UnitState.Tactic.NONE:
				text += " {%s}" % u.cover_note
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_rect(Rect2(p + Vector2(-w * 0.5 - 3, -12), Vector2(w + 6, 15)), Color(0, 0, 0, 0.45), true)
			draw_string(font, p + Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		var s := hud.sim.brain.summary()
		var lines := ["COMBAT AI (F4)  states %s" % JSON.stringify(s.states),
			"sight checks %d (%.2f / frame, %.0f us each)  update %.0f us avg, %d us max" % [s.sight_checks, s.sight_checks_per_frame, s.sight_us_avg, s.update_us_avg, s.update_us_max],
			"AI shots %d  acquisitions %d  switches %d  dropped %d  friendly holds %d" % [s.ai_shots, s.acquisitions, s.switches, s.dropped, s.friendly_holds],
			"tactics %s  cover searches %d, found %d, none %d, unreachable %d" % [JSON.stringify(s.tactics), s.cover.searches, s.cover.found, s.cover.none, s.cover.unreachable]]
		var y := 18.0
		for line: String in lines:
			var lw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_rect(Rect2(Vector2(size.x - lw - 20, y - 13), Vector2(lw + 12, 17)), Color(0, 0, 0, 0.55), true)
			draw_string(font, Vector2(size.x - lw - 14, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 0.8))
			y += 18.0

	## Crosshair opened by the current spread, hit marker, damage flash (COMBAT-01a).
	func _draw_fps() -> void:
		var c := size * 0.5
		var now := Time.get_ticks_msec() / 1000.0
		var gap := 3.0
		var u := hud.sim.state.get_unit(hud.game.possessed_id)
		var body := hud.game.possessed_body()
		if u and body and u.weapon_id != &"":
			var def := hud.sim.combat.weapon(u.weapon_id)
			var spread := hud.sim.combat.current_spread(u, def)
			var fov := deg_to_rad(body.camera.fov)
			gap = clampf(tan(deg_to_rad(spread)) / tan(fov * 0.5) * size.y * 0.5, 2.0, 60.0) + 2.0
		var col := Color(1, 1, 1, 0.9)
		draw_line(c + Vector2(-gap - 8, 0), c + Vector2(-gap, 0), col, 1.5)
		draw_line(c + Vector2(gap, 0), c + Vector2(gap + 8, 0), col, 1.5)
		draw_line(c + Vector2(0, -gap - 8), c + Vector2(0, -gap), col, 1.5)
		draw_line(c + Vector2(0, gap), c + Vector2(0, gap + 8), col, 1.5)
		if now < hud.hit_until:
			var hc := Color(1.0, 0.25, 0.2) if hud.hit_kill else Color.WHITE
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					draw_line(c + Vector2(sx, sy) * 6.0, c + Vector2(sx, sy) * 13.0, hc, 2.0)
		if now < hud.hurt_until:
			# UI-01C.1: a thin edge that fades inwards (bands that do not overlap, so the corners are not
			# darker), strong enough to notice, never covering the HUD.
			var a := clampf((hud.hurt_until - now) / 0.4, 0.0, 1.0) * 0.32
			var w := 36.0
			for k in 4:
				var f := 1.0 - k / 4.0
				var band := Color(0.75, 0.05, 0.03, a * f * f)
				var e := k * w / 4.0
				var t := w / 4.0
				draw_rect(Rect2(e, e, size.x - 2.0 * e, t), band, true)
				draw_rect(Rect2(e, size.y - e - t, size.x - 2.0 * e, t), band, true)
				draw_rect(Rect2(e, e + t, t, size.y - 2.0 * (e + t)), band, true)
				draw_rect(Rect2(size.x - e - t, e + t, t, size.y - 2.0 * (e + t)), band, true)

	## Selected squads: name tag over the leader, and while moving a marker on every
	## member's formation slot with a thin line from the soldier to it.
	## UI-01C squad markers. Selected squads: corner brackets around their soldiers on screen, the
	## field tag (callsign, status, hold fire) on top, and while moving a dot on every member's
	## formation slot with a thin line to it. Other friendly squads near the camera: only a small,
	## faint callsign over them. Soldiers themselves carry small dots (UnitVisuals).
	func _draw_squads() -> void:
		var cam := hud.rts.rig.camera if hud.rts.rig else null
		if cam == null or not cam.current:
			return
		var selected := hud.rts.selected_squads()
		for sq: SquadState in hud.sim.state.all_squads():
			if selected.has(sq.id) or sq.members.is_empty() or not hud.rts._can_command(sq.leader_id):
				continue
			var box := _squad_box(cam, sq)
			if box.size.x <= 0.0:
				continue
			var cf := FNUI.caps_font()
			var t := sq.squad_name.to_upper()
			var tw := cf.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION).x
			var tp := Vector2(roundf(box.get_center().x - tw * 0.5), roundf(box.position.y - 4.0))
			draw_string_outline(cf, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, 3, Color(FNUI.BG, 0.6))
			draw_string(cf, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION, Color(FNUI.INK, 0.62))
		for sid in selected:
			var sq := hud.sim.state.get_squad(sid)
			var col := WorldState.faction_color(sq.faction).lerp(Color.WHITE, 0.35)
			for id in sq.members:
				var u := hud.sim.state.get_unit(id)
				if u == null or u.order != UnitState.Order.MOVE or sq.is_detached(id):
					continue
				var a := u.position + Vector3.UP * 0.3
				var b := u.order_target + Vector3.UP * 0.1
				if cam.is_position_behind(a) or cam.is_position_behind(b):
					continue
				var pa := cam.unproject_position(a)
				var pb := cam.unproject_position(b)
				draw_line(pa, pb, Color(col, 0.3), 1.0)
				draw_circle(pb, 2.5, Color(col, 0.8))
			var box := _squad_box(cam, sq)
			if box.size.x <= 0.0:
				continue
			_brackets(box, Color(FNUI.ACCENT, 0.95))
			# The field tag: callsign and status (the roster's words), hold fire flagged.
			var st := SquadPanel.squad_status(hud.sim, sq)
			var nf := FNUI.font("semibold")
			var cf := FNUI.caps_font()
			var status: String = st.text
			if sq.roe == SquadState.Roe.HOLD_FIRE:
				status += "  ·  HOLD FIRE"
			var nw := nf.get_string_size(sq.squad_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.BODY).x
			var sw := cf.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1).x
			var w := nw + sw + 6.0 + 11.0
			var r := Rect2(Vector2(roundf(box.get_center().x - w * 0.5), roundf(box.position.y - 19.0)), Vector2(w, 14))
			r.position.x = clampf(r.position.x, 4.0, size.x - w - 4.0)
			r.position.y = maxf(r.position.y, 4.0)
			draw_rect(r, Color(FNUI.BG, 0.82), true)
			draw_rect(r, Color(FNUI.ACCENT, 0.9), false, 1.0)
			draw_rect(Rect2(r.position, Vector2(2, r.size.y)), col, true)
			draw_string(nf, r.position + Vector2(6, 11), sq.squad_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.BODY, FNUI.INK)
			draw_string(cf, r.position + Vector2(6 + nw + 5, 10.5), status, HORIZONTAL_ALIGNMENT_LEFT, -1, FNUI.CAPTION - 1,
				FNUI.ARMED if sq.roe == SquadState.Roe.HOLD_FIRE else st.color)

	## Screen rectangle around a squad's attached living soldiers (padded); empty when none is in front
	## of the camera or the squad is far away (> 900 m), so distant squads do not crowd the view.
	func _squad_box(cam: Camera3D, sq: SquadState) -> Rect2:
		var box := Rect2()
		var first := true
		for id in sq.members:
			var u := hud.sim.state.get_unit(id)
			if u == null or not u.alive or sq.is_detached(id):
				continue
			var p := u.position + Vector3.UP * 0.9
			if cam.is_position_behind(p) or cam.global_position.distance_to(p) > 900.0:
				continue
			var sp := cam.unproject_position(p)
			if first:
				box = Rect2(sp, Vector2.ZERO)
				first = false
			else:
				box = box.expand(sp)
		if first:
			return Rect2()
		return box.grow(9.0).abs()

	## Four corner brackets (a quarter of the shorter side, 5-12 px) around r.
	func _brackets(r: Rect2, col: Color) -> void:
		var l := clampf(minf(r.size.x, r.size.y) * 0.25, 5.0, 12.0)
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var sx := 1.0 if c.x == r.position.x else -1.0
			var sy := 1.0 if c.y == r.position.y else -1.0
			draw_line(c, c + Vector2(l * sx, 0), col, 1.5)
			draw_line(c, c + Vector2(0, l * sy), col, 1.5)


func _ready() -> void:
	layer = 40
	_overlay = Overlay.new()
	_overlay.hud = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.position = Vector2(12, 0)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.add_theme_stylebox_override("normal", FNUI.panel_style(FNUI.S3))
	_label.add_theme_font_override("font", FNUI.font("regular", false))
	_label.add_theme_font_size_override("font_size", FNUI.BODY)
	_label.add_theme_color_override("font_color", FNUI.INK)
	add_child(_label)
	_hints = FNPanel.new(Color.TRANSPARENT, FNUI.S3)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", FNUI.S5)
	for k: Array in [["LMB", "Select"], ["RMB", "Move"], ["B", "Build"], ["M", "Map"], ["Tab", "First person"], ["F1", "Controls"]]:
		hb.add_child(FNKeyHint.new(k[0], k[1]))
	_hints.add_child(hb)
	_hints.visible = false
	add_child(_hints)
	_fps = FPSHud.new()
	_fps.visible = false
	add_child(_fps)
	squad_panel = SquadPanel.new()
	squad_panel.position = Vector2(FNUI.EDGE, FNUI.EDGE)
	squad_panel.visible = false
	add_child(squad_panel)
	tactical_panel = TacticalPanel.new()
	tactical_panel.visible = false
	add_child(tactical_panel)
	logistics_panel = LogisticsPanel.new()
	add_child(logistics_panel)
	economy = EconomyHud.new()
	economy.hud = self
	add_child(economy)
	_notes_box = VBoxContainer.new()
	_notes_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notes_box.add_theme_constant_override("separation", 3)
	add_child(_notes_box)
	_badge = Label.new()
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.position = Vector2(12, 12)  # moved to the top centre in _process
	_badge.add_theme_font_size_override("font_size", FNUI.LABEL)
	_badge.add_theme_font_override("font", FNUI.caps_font())
	_badge.visible = false
	add_child(_badge)


## A war event the player's faction learns about: a short notification at the top of the
## screen (RTS and FPS) for 9 s.
func _on_war_event(e: Dictionary) -> void:
	if war_sim == null or (e.faction >= 0 and e.faction != war_sim.war.player_faction):
		return
	if e.kind in ["op_start", "info"] and e.faction < 0:
		return
	# GAMEPLAY-01B: income is shown in the supply strip (and kept in the war log), not as a toast every minute.
	if e.kind == "income":
		return
	# UI-01C: a kit toast - status colour on the left edge and the icon, the text in ink.
	var col := FNUI.NEUTRAL
	var icon := &"idle"
	match e.kind:
		"captured":
			col = FNUI.WARN
			icon = &"objective"
		"contested", "threat", "attack":
			col = FNUI.ALERT
			icon = &"under_fire"
		"op_done", "reinforcements", "cache_taken", "build_done":
			col = FNUI.OK
			icon = &"check"
		"cache", "build":
			col = FNUI.ARMED
			icon = &"cargo" if e.kind == "cache" else &"build"
		"op_failed":
			col = FNUI.DANGER
			icon = &"blocked"
	var l := PanelContainer.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var epos: Vector3 = e.get("pos", Vector3.INF)
	if epos.is_finite() and e.kind in ["threat", "attack", "contested", "captured", "base", "garrison"]:
		# GAMEPLAY-01D: the warning's place - a click moves the tactical camera there.
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.tooltip_text = "Click: go there"
		l.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and game and game.rts_camera:
				game.rts_camera.frame(epos, game.rts_camera.yaw, 120.0))
	var sb := FNUI.panel_style(FNUI.S3)
	sb.border_width_left = 2
	sb.border_color = col
	l.add_theme_stylebox_override("panel", sb)
	var st := FNStatusIndicator.new(FNUI.ICON_S, FNUI.LABEL)
	st.set_status(icon, e.text, col)
	st.text_label.uppercase = false
	st.text_label.clip_text = false
	st.text_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	st.text_label.add_theme_font_override("font", FNUI.font("medium", false))
	st.text_label.add_theme_color_override("font_color", FNUI.INK)
	l.add_child(st)
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_notes_box.add_child(l)
	_notes.append([l, Time.get_ticks_msec() / 1000.0 + 9.0])
	while _notes.size() > 4:
		_notes[0][0].queue_free()
		_notes.pop_front()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F4:
				combat_debug = not combat_debug
				get_viewport().set_input_as_handled()
			KEY_F1:
				show_controls = not show_controls
				get_viewport().set_input_as_handled()
			KEY_F3:
				# Not consumed: the same key toggles WorldDiagnostics' frame-time overlay.
				show_debug = not show_debug


func _process(_delta: float) -> void:
	var now_s := Time.get_ticks_msec() / 1000.0
	while not _notes.is_empty() and _notes[0][1] < now_s:
		_notes[0][0].queue_free()
		_notes.pop_front()
	var vp := get_viewport().get_visible_rect().size
	if logistics_panel.rts == null and rts:
		logistics_panel.rts = rts
		logistics_panel.sim = sim
		logistics_panel.game = game
		logistics_panel.construction = construction
	logistics_panel.enabled = not (construction and construction.active)
	if squad_panel.rts == null and rts:
		squad_panel.rts = rts
		squad_panel.sim = sim
	if tactical_panel.rts == null and rts:
		tactical_panel.rts = rts
		tactical_panel.sim = sim
	# UI-01C layout of the tactical view: Task Force top left (below the F3 overlay), the selection and
	# command panel bottom centre while squads are selected, otherwise the key hints bottom left; the
	# text box (messages, F1 controls, F3 counters) sits above whichever is at the bottom.
	var in_rts: bool = rts != null and game != null and game.mode == GameController.Mode.RTS and not (construction and construction.active)
	var war_on: bool = war_sim != null and war_sim.enabled
	squad_panel.visible = in_rts and not sim.state.squads.is_empty()
	var top := float(FNUI.EDGE)
	if game and game.diagnostics:
		top = maxf(top, game.diagnostics.overlay_bottom() + 8.0)
	squad_panel.position = Vector2(FNUI.EDGE, top)
	var squads_selected: bool = rts != null and not rts.selected_squads().is_empty()
	tactical_panel.visible = squads_selected and in_rts
	_hints.visible = in_rts and war_on and not tactical_panel.visible
	var floor_y := vp.y - 12.0
	squad_panel.max_bottom = vp.y - FNUI.EDGE
	if tactical_panel.visible:
		tactical_panel.position = Vector2(maxf(roundf((vp.x - tactical_panel.size.x) * 0.5), 8.0), vp.y - tactical_panel.size.y - FNUI.EDGE)
		floor_y = tactical_panel.position.y - 8.0
		if tactical_panel.position.x < squad_panel.position.x + squad_panel.size.x + 12.0:
			squad_panel.max_bottom = tactical_panel.position.y - 12.0
	elif construction and construction.active and construction.panel._context.visible:
		floor_y = construction.panel._context.position.y - 8.0
	elif _hints.visible:
		_hints.position = Vector2(FNUI.EDGE, vp.y - _hints.size.y - FNUI.EDGE)
		floor_y = _hints.position.y - 8.0
		squad_panel.max_bottom = _hints.position.y - 12.0
	_update_ammo()
	UnitVisuals.markers_visible = game == null or game.mode == GameController.Mode.RTS
	# The faction badge: driving only (the tactical view shows the side in the roster, first person in
	# the squad card).
	_badge.visible = war_on and game != null and game.mode == GameController.Mode.DRIVE
	if war_on and _badge.text == "":
		var pf := war_sim.war.player_faction
		var col := WorldState.faction_color(pf)
		_badge.text = "YOU ARE %s" % WorldState.faction_name(pf).to_upper()
		_badge.add_theme_color_override("font_color", col.lightened(0.35))
		var bsb := FNUI.panel_style(FNUI.S2)
		bsb.border_width_left = 2
		bsb.border_color = col
		bsb.content_margin_left = 8
		bsb.content_margin_right = 8
		_badge.add_theme_stylebox_override("normal", bsb)
	if _badge.visible:
		_badge.position = Vector2(vp.x * 0.5 - _badge.size.x * 0.5, 12)
	var notes_y := 54.0 if _badge.visible else float(FNUI.EDGE)
	if economy._strip.visible:
		notes_y = economy._strip.position.y + economy._strip.size.y + 6.0
		if economy._hint.visible:
			notes_y = economy._hint.position.y + economy._hint.size.y + 6.0
	_notes_box.position = Vector2(vp.x * 0.5 - _notes_box.size.x * 0.5, notes_y)
	if Engine.get_process_frames() % 6 == 0:
		var text := _text()
		if text != _label.text:
			_label.text = text
			_label.size = Vector2.ZERO
		_label.visible = text != ""
	_label.position = Vector2(FNUI.EDGE if in_rts else 12.0, floor_y - _label.size.y)
	if _label.visible:
		squad_panel.max_bottom = minf(squad_panel.max_bottom, _label.position.y - 8.0)


## COMBAT-01a: shots, hits and damage that concern the possessed soldier.
func on_shot(shot: Dictionary) -> void:
	if game and shot.shooter == game.possessed_id and shot.hit_unit > 0:
		hit_until = Time.get_ticks_msec() / 1000.0 + (0.35 if shot.killed else 0.18)
		hit_kill = shot.killed
		hits_seen += 1
		if shot.killed:
			kills_seen += 1


func on_damaged(u: UnitState, _amount: float, _zone: int, _source: int) -> void:
	if game and u.id == game.possessed_id:
		hurt_until = Time.get_ticks_msec() / 1000.0 + 0.4


func on_possessed_died(_id: int) -> void:
	death_note_until = Time.get_ticks_msec() / 1000.0 + 6.0


## UI-01C: the first-person HUD (weapon, health, squad, prompt) while a soldier is possessed.
func _update_ammo() -> void:
	var u := sim.state.get_unit(game.possessed_id) if game and sim else null
	var show := u != null and game.mode == GameController.Mode.FPS
	_fps.visible = show
	if show:
		_fps.update(sim, u)


## WORLD-SANDBOX-01B: the war's bottom text - what the player needs, short; F1 adds every
## control, F3 the technical counters.
func _war_text() -> String:
	var war := war_sim.war
	var pf := war.player_faction
	var lines: Array[String] = []
	if game.mode == GameController.Mode.FPS:
		# UI-01C: soldier, squad and weapon are in the first-person HUD; only F1 adds text here.
		if show_controls:
			lines.append("LMB fire, R reload, V semi/auto, RMB aim, G grenade, X launcher | WASD move, Shift sprint, Space jump, Esc release mouse, F fly")
			lines.append("Tab tactical view  ·  M strategic map  ·  F1 hide controls")
	elif game.mode == GameController.Mode.DRIVE:
		var du := sim.state.get_unit(game.driving_id)
		lines.append("DRIVING  %s" % (sim.vehicles.describe(du) if du else "-"))
		lines.append("W/S DRIVE  ·  A/D STEER  ·  SPACE BRAKE  ·  TAB TACTICAL")
	elif construction and construction.active:
		# UI-01C: the build menu and its context panel carry the keys; F1 adds the full construction help.
		if show_controls:
			lines.append_array(construction.status_lines())
	else:
		var back := sim.state.get_unit(game.possessed_id)
		if Time.get_ticks_msec() / 1000.0 < death_note_until and back and not back.alive:
			lines.append("%s was killed. Select a living soldier and press P to take over." % back.unit_name)
		if show_controls:
			lines.append("Camera: WASD pan, Q/E rotate, wheel zoom, middle-drag rotate")
			lines.append("LMB select / drag box, Shift add, Ctrl+click squad, Ctrl+A all, RMB move, H hold, P or double-click possess (soldier) / drive (vehicle), B construction")
			lines.append("Squads: F + click follow, G regroup (Shift+G at cursor), V line / column, [ ] spacing, Y weapons free / hold fire · T board a selected vehicle, U unload (squad + vehicle selected: RMB = transport there) | F4 AI debug, F3 stats")
			lines.append("Tactics (at the cursor, or arm from the bar and click): Z assault, K suppress, L flank, J defend, Backspace withdraw, Shift+RMB move by bounds · Shift+V formations (auto / line / column / wedge ...) | F7 fire teams, posts and missions")
		# UI-01C: selected squads, their orders and the controller's messages are in the command panel,
		# the keys in the hint bar; this box only carries what has no other place.
		var panel_up := not rts.selected_squads().is_empty()
		var loose := rts.loose_selected().size()
		if loose > 0 and not panel_up:
			lines.append("Selected: %d soldier%s (not a whole squad)" % [loose, "" if loose == 1 else "s"])
		if rts.current_message() != "" and not panel_up:
			lines.append(rts.current_message())
		if show_controls:
			lines.append("F1 hide controls")
	var parts: Array[String] = []
	for fs: FactionState in war.factions.values():
		parts.append("%s %d" % [fs.faction_name, war.owned_by(fs.id).size()])
	if show_controls:
		lines.append("WAR  objectives %s · your operations %d · speed %s (, .) · F5 save · F9 load" % [
			" / ".join(parts), war.active_operations(pf).size(), TimeCompression.label()])
	if construction and construction.message != "" and Time.get_ticks_msec() / 1000.0 < construction._message_until:
		lines.append(construction.message)
	if show_debug:
		var st := sim.stats()
		lines.append("Units %d (%d soldiers)  moving %d  bodies %d / abstract %d  sim time %.0f s  |  F3 hide" % [
			st.units, sim.state.count_of(UnitState.Kind.SOLDIER), st.moving, st.bodies, sim.proxies.size(), st.time])
		if construction and construction.structures:
			var cs := construction.structures.stats()
			lines.append("Structures %d (%d modules)  drawn cells %d  collision cells %d" % [cs.structures, cs.instances, cs.visible_cells, cs.collision_cells])
	return "\n".join(lines)


func _text() -> String:
	if game == null or sim == null:
		return ""
	if war_sim and war_sim.enabled:
		return _war_text()
	var st := sim.stats()
	var lines: Array[String] = []
	if game.mode == GameController.Mode.FPS:
		var u := sim.state.get_unit(game.possessed_id)
		var who := "%s (%s)" % [u.unit_name, WorldState.faction_name(u.faction)] if u else "-"
		lines.append("%s  ·  TAB TACTICAL  ·  M MAP" % who.to_upper())
		var sq := sim.state.squad_of(u.id) if u else null
		if sq:
			lines.append("Squad %s (%d%s) order: %s - the others keep their orders" % [sq.squad_name, sq.members.size(), ", you lead" if sq.leader_id == u.id else "", sq.order_name()])
		lines.append("LMB FIRE  ·  R RELOAD  ·  V FIRE MODE  ·  F1 MORE CONTROLS")
	elif construction and construction.active:
		lines.append("CONSTRUCTION  ·  B CLOSE  ·  F1 HELP")
	else:
		var back := sim.state.get_unit(game.possessed_id)
		lines.append("TACTICAL COMMAND")
		if Time.get_ticks_msec() / 1000.0 < death_note_until and back and not back.alive:
			lines.append("%s was killed. Select a living soldier and press P to take over." % back.unit_name)
		lines.append("LMB SELECT  ·  RMB MOVE  ·  B BUILD  ·  M MAP  ·  TAB %s" % (back.unit_name.to_upper() if back and back.alive else "FIRST PERSON"))
		var sel: Array[String] = []
		var moving := 0
		for id in rts.selected:
			var s := sim.state.get_unit(id)
			if s:
				sel.append(s.unit_name)
				if s.move_state == UnitState.MoveState.MOVING:
					moving += 1
		var sq_names: Array[String] = []
		for sid in rts.selected_squads():
			sq_names.append(sim.state.get_squad(sid).squad_name)
		var shown := ", ".join(sel) if sel.size() <= 6 else "%s ... (%d soldiers)" % [", ".join(sel.slice(0, 6)), sel.size()]
		lines.append("Selected: %s%s%s" % [("squads " + ", ".join(sq_names) + " | ") if not sq_names.is_empty() else "",
			shown if not sel.is_empty() else "none", "  (%d moving)" % moving if moving > 0 else ""])
		if rts.current_message() != "":
			lines.append(rts.current_message())
	if show_debug:
		lines.append("Units %d (%d soldiers, %d vehicles)  moving %d  bodies %d  sim time %.0f s" % [
			st.units, sim.state.count_of(UnitState.Kind.SOLDIER), sim.state.count_of(UnitState.Kind.VEHICLE), st.moving, st.bodies, st.time])
	if show_debug and construction and construction.structures:
		var cs := construction.structures.stats()
		lines.append("Structures %d (%d modules)  drawn cells %d  collision cells %d" % [cs.structures, cs.instances, cs.visible_cells, cs.collision_cells])
	if construction and construction.message != "" and not construction.active:
		lines.append(construction.message)
	if war_sim and war_sim.enabled:
		var war := war_sim.war
		var pf := war.player_faction
		var f := war.faction(pf)
		var soldiers := 0
		for sq: SquadState in war_sim.squads_of(pf):
			soldiers += sq.members.size()
		var parts: Array[String] = []
		for fs: FactionState in war.factions.values():
			parts.append("%s %d" % [fs.faction_name, war.owned_by(fs.id).size()])
		lines.append("WAR  you: %s · %d soldiers, %d reserve, %d fallen · objectives %s · %d operations · speed %dx  |  M strategic map, , . time speed" % [
			f.faction_name, soldiers, f.reserves, f.casualties, " / ".join(parts), war.active_operations(pf).size(), int(Engine.time_scale)])
	if detail:
		var u := sim.state.get_unit(game.possessed_id)
		var where := "-"
		if u:
			where = "(%.0f, %.0f)" % [u.position.x, u.position.z]
			for i in game.sites.size():
				var d := Vector2(u.position.x - game.sites[i].position.x, u.position.z - game.sites[i].position.z).length()
				if d < 400.0:
					where += "  near %s" % game.sites[i].name
		lines.append("Detail: %d bodies, %d abstract  |  1/2/3 jump to site, N next soldier anywhere  |  last unit %s" % [
			sim.bodies.size(), sim.proxies.size(), where])
	return "\n".join(lines)


static func _fmt(p: Vector3) -> String:
	return "(%.0f, %.0f)" % [p.x, p.z]
