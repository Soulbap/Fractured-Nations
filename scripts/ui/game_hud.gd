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
## COMBAT-01a first-person weapon panel and feedback timers (seconds of real time).
var _ammo: Label
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
			var text := "%s %s" % [u.unit_name, u.ai_state_name()]
			if t and u.alive:
				text += " > %s %s" % [t.unit_name, "seen" if u.target_visible else "mem %.0fs" % (st.time - u.target_seen_at)]
			if u.alive and u.ai_reason != "" and u.ai_reason != "no target":
				text += " [%s]" % u.ai_reason
			if u.alive and u.weapon_id != &"":
				text += " %d/%d" % [u.mag, u.reserve]
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_rect(Rect2(p + Vector2(-w * 0.5 - 3, -12), Vector2(w + 6, 15)), Color(0, 0, 0, 0.45), true)
			draw_string(font, p + Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		var s := hud.sim.brain.summary()
		var lines := ["COMBAT AI (F4)  states %s" % JSON.stringify(s.states),
			"sight checks %d (%.2f / frame, %.0f us each)  update %.0f us avg, %d us max" % [s.sight_checks, s.sight_checks_per_frame, s.sight_us_avg, s.update_us_avg, s.update_us_max],
			"AI shots %d  acquisitions %d  switches %d  dropped %d  friendly holds %d" % [s.ai_shots, s.acquisitions, s.switches, s.dropped, s.friendly_holds]]
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
			var a := clampf((hud.hurt_until - now) / 0.4, 0.0, 1.0) * 0.35
			var w := 70.0
			draw_rect(Rect2(0, 0, size.x, w), Color(0.8, 0, 0, a), true)
			draw_rect(Rect2(0, size.y - w, size.x, w), Color(0.8, 0, 0, a), true)
			draw_rect(Rect2(0, 0, w, size.y), Color(0.8, 0, 0, a), true)
			draw_rect(Rect2(size.x - w, 0, w, size.y), Color(0.8, 0, 0, a), true)

	## Selected squads: name tag over the leader, and while moving a marker on every
	## member's formation slot with a thin line from the soldier to it.
	func _draw_squads() -> void:
		var cam := hud.rts.rig.camera if hud.rts.rig else null
		if cam == null or not cam.current:
			return
		var font := ThemeDB.fallback_font
		for sid in hud.rts.selected_squads():
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
				draw_line(pa, pb, Color(col, 0.35), 1.0)
				draw_circle(pb, 4.0, Color(col, 0.85))
			var leader := hud.sim.state.get_unit(sq.leader_id)
			if leader and not cam.is_position_behind(leader.position + Vector3.UP * 2.4):
				var p := cam.unproject_position(leader.position + Vector3.UP * 2.4)
				var text := "%s  %s" % [sq.squad_name, sq.order_name()]
				if sq.roe == SquadState.Roe.HOLD_FIRE:
					text += "  HOLD FIRE"
					col = Color(1.0, 0.7, 0.25)
				var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_rect(Rect2(p + Vector2(-w * 0.5 - 4, -16), Vector2(w + 8, 20)), Color(0, 0, 0, 0.5), true)
				draw_string(font, p + Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
				draw_circle(p + Vector2(0, 10), 3.0, Color(1, 0.9, 0.3))


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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_label.add_theme_stylebox_override("normal", sb)
	add_child(_label)
	_ammo = Label.new()
	_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo.add_theme_font_size_override("font_size", 26)
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var asb := StyleBoxFlat.new()
	asb.bg_color = Color(0, 0, 0, 0.45)
	asb.content_margin_left = 14
	asb.content_margin_right = 14
	asb.content_margin_top = 6
	asb.content_margin_bottom = 6
	_ammo.add_theme_stylebox_override("normal", asb)
	_ammo.visible = false
	add_child(_ammo)
	squad_panel = SquadPanel.new()
	squad_panel.position = Vector2(12, 250)
	squad_panel.visible = false
	add_child(squad_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F4:
		combat_debug = not combat_debug
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if squad_panel.rts == null and rts:
		squad_panel.rts = rts
		squad_panel.sim = sim
	squad_panel.visible = rts != null and game != null and game.mode == GameController.Mode.RTS and not (construction and construction.active) and not sim.state.squads.is_empty()
	_update_ammo()
	if Engine.get_process_frames() % 6 == 0:
		_label.text = _text()
		_label.position = Vector2(12, get_viewport().get_visible_rect().size.y - _label.size.y - 12)


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


func _update_ammo() -> void:
	var u := sim.state.get_unit(game.possessed_id) if game and sim else null
	var show := u != null and game.mode == GameController.Mode.FPS and u.weapon_id != &""
	_ammo.visible = show
	if not show:
		return
	var def := sim.combat.weapon(u.weapon_id)
	var mode := "AUTO" if u.fire_auto else "SEMI"
	var status := ""
	if u.is_reloading():
		var left := u.reload_until - sim.state.time
		var frac := clampf(1.0 - left / def.reload_time, 0.0, 1.0)
		status = "RELOADING %s\n" % ("|".repeat(int(frac * 12)) + ".".repeat(12 - int(frac * 12)))
	elif u.mag == 0:
		status = "EMPTY - R\n" if u.reserve > 0 else "NO AMMO\n"
	_ammo.text = "%s%d / %d   %s\nHP %d" % [status, u.mag, u.reserve, mode, ceili(u.health)]
	var vs := get_viewport().get_visible_rect().size
	_ammo.position = Vector2(vs.x - _ammo.size.x - 16, vs.y - _ammo.size.y - 16)


func _text() -> String:
	if game == null or sim == null:
		return ""
	var st := sim.stats()
	var lines: Array[String] = []
	if game.mode == GameController.Mode.FPS:
		var u := sim.state.get_unit(game.possessed_id)
		var who := "%s (%s)" % [u.unit_name, WorldState.faction_name(u.faction)] if u else "-"
		lines.append("FIRST PERSON  controlling %s" % who)
		if u and u.has_order():
			lines.append("Order: move to %s  (suspended while possessed, resumes on release)" % _fmt(u.order_target))
		var sq := sim.state.squad_of(u.id) if u else null
		if sq:
			lines.append("Squad %s (%d%s) order: %s - the others keep their orders" % [sq.squad_name, sq.members.size(), ", you lead" if sq.leader_id == u.id else "", sq.order_name()])
		lines.append("LMB fire, R reload, V semi/auto, RMB aim | Tab tactical view | WASD move, Shift sprint, Space jump, Esc release mouse, F fly, F4 AI debug")
	elif construction and construction.active:
		lines.append_array(construction.status_lines())
	else:
		var back := sim.state.get_unit(game.possessed_id)
		lines.append("TACTICAL  WASD pan, Q/E rotate, wheel zoom, middle-drag rotate")
		if Time.get_ticks_msec() / 1000.0 < death_note_until and back and not back.alive:
			lines.append("%s was killed. Select a living soldier and press P to take over." % back.unit_name)
		lines.append("LMB select / drag box, Shift add, Ctrl+click squad, Ctrl+A all, RMB move, H hold, P or double-click possess, B construction, Tab back to %s" % (back.unit_name if back and back.alive else "soldier"))
		lines.append("Squads: F + click follow, G regroup (Shift+G at cursor), V line / column, [ ] spacing, Y weapons free / hold fire | F4 AI debug")
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
	lines.append("Units %d (%d soldiers, %d vehicles)  moving %d  bodies %d  sim time %.0f s" % [
		st.units, sim.state.count_of(UnitState.Kind.SOLDIER), sim.state.count_of(UnitState.Kind.VEHICLE), st.moving, st.bodies, st.time])
	if construction and construction.structures:
		var cs := construction.structures.stats()
		lines.append("Structures %d (%d modules)  drawn cells %d  collision cells %d" % [cs.structures, cs.instances, cs.visible_cells, cs.collision_cells])
		if construction.message != "" and not construction.active:
			lines.append(construction.message)
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
