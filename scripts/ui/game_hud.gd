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


class Overlay extends Control:
	var hud: GameHUD

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if hud.game and hud.game.mode == GameController.Mode.FPS:
			var c := size * 0.5
			draw_line(c + Vector2(-10, 0), c + Vector2(-3, 0), Color.WHITE, 1.5)
			draw_line(c + Vector2(3, 0), c + Vector2(10, 0), Color.WHITE, 1.5)
			draw_line(c + Vector2(0, -10), c + Vector2(0, -3), Color.WHITE, 1.5)
			draw_line(c + Vector2(0, 3), c + Vector2(0, 10), Color.WHITE, 1.5)
		elif hud.rts:
			_draw_squads()
			if hud.rts.dragging:
				var r := Rect2(hud.rts.drag_start, hud.rts.drag_current - hud.rts.drag_start).abs()
				draw_rect(r, Color(1, 1, 1, 0.12), true)
				draw_rect(r, Color(1, 1, 1, 0.85), false, 1.5)

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
	squad_panel = SquadPanel.new()
	squad_panel.position = Vector2(12, 250)
	squad_panel.visible = false
	add_child(squad_panel)


func _process(_delta: float) -> void:
	if squad_panel.rts == null and rts:
		squad_panel.rts = rts
		squad_panel.sim = sim
	squad_panel.visible = rts != null and game != null and game.mode == GameController.Mode.RTS and not (construction and construction.active) and not sim.state.squads.is_empty()
	if Engine.get_process_frames() % 6 == 0:
		_label.text = _text()
		_label.position = Vector2(12, get_viewport().get_visible_rect().size.y - _label.size.y - 12)


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
			lines.append("Squad %s (%d)%s: %s, the others keep their orders" % [sq.squad_name, sq.members.size(), " leader" if sq.leader_id == u.id else "", sq.order_name()])
		lines.append("Tab tactical view | WASD move, Shift sprint, Space jump, Esc release mouse, F fly, F3 stats")
	elif construction and construction.active:
		lines.append_array(construction.status_lines())
	else:
		var back := sim.state.get_unit(game.possessed_id)
		lines.append("TACTICAL  WASD pan, Q/E rotate, wheel zoom, middle-drag rotate")
		lines.append("LMB select / drag box, Shift add, Ctrl+click squad, Ctrl+A all, RMB move, H hold, P or double-click possess, B construction, Tab back to %s" % (back.unit_name if back else "soldier"))
		lines.append("Squads: F + click follow, G regroup (Shift+G at cursor), V line / column, [ ] spacing")
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
