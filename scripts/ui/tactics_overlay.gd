## Tactical markers in the 3D world (AI-SQUAD-01).
##
## Normal play: what the player ordered or what their squads are doing - a coloured line from a
## squad to its tactical target, a ring on the target, the flank route, the next leg, a label with
## the tactic and its phase - for the player's own squads that have a tactic. Nothing about enemy
## squads is drawn (no hidden positions are revealed).
##
## Developer view (F7): every squad of every faction - fire teams as coloured discs under the
## soldiers (leaders with a white ring), the post each soldier was given, the fire mission it is
## shooting, cover spots, flank routes, withdrawal destinations, the squad's tactic text. Meant for
## inspecting AI behaviour, off by default; nothing is built while it is off and no squad has a
## player tactic to show.
##
## Reads the squad and unit records only; draws with one ImmediateMesh rebuilt 5 times a second.
class_name TacticsOverlay
extends Node3D

var sim: WorldSim
var rts: RTSController
var terrain: Terrain3D
var player_faction := 0
## F7: all squads of all factions with teams, posts, missions.
var debug := false:
	set(v):
		debug = v
		if not v:
			_clear()

const COLORS := {
	SquadState.Tactic.DEFEND: Color(0.3, 0.85, 1.0),
	SquadState.Tactic.SUPPRESS: Color(1.0, 0.6, 0.15),
	SquadState.Tactic.ASSAULT: Color(1.0, 0.25, 0.2),
	SquadState.Tactic.FLANK: Color(1.0, 0.3, 0.9),
	SquadState.Tactic.BOUND: Color(0.4, 1.0, 0.4),
	SquadState.Tactic.REPOSITION: Color(0.6, 0.7, 1.0),
	SquadState.Tactic.WITHDRAW: Color(1.0, 0.95, 0.3),
	SquadState.Tactic.REGROUP: Color(0.9, 0.9, 0.9),
}
const TEAM_COLORS: Array[Color] = [Color(0.35, 0.65, 1.0), Color(1.0, 0.65, 0.2)]

var _mesh := ImmediateMesh.new()
var _inst: MeshInstance3D
var _labels: Array[Label3D] = []
var _timer := 0.0


func _ready() -> void:
	_inst = MeshInstance3D.new()
	_inst.mesh = _mesh
	_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 10
	_inst.material_override = m
	_inst.extra_cull_margin = 16384.0
	add_child(_inst)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or sim == null:
		return
	_timer = 0.2
	_rebuild()


func _clear() -> void:
	_mesh.clear_surfaces()
	for l in _labels:
		l.visible = false


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var used := 0
	var drew := false
	var selected: Array = rts.selected_squads() if rts else []
	for sq: SquadState in sim.state.squads.values():
		var mine := sq.faction == player_faction
		if not debug and (not mine or sq.tactic == SquadState.Tactic.NONE):
			continue
		if not drew:
			_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = true
		used = _draw_squad(sq, used, selected.has(sq.id))
	if drew:
		_mesh.surface_end()
	for i in range(used, _labels.size()):
		_labels[i].visible = false


func _draw_squad(sq: SquadState, used: int, selected: bool) -> int:
	var units: Array[UnitState] = []
	var c := Vector3.ZERO
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and u.alive and u.vehicle_id < 0:
			units.append(u)
			c += u.position
	if units.is_empty():
		return used
	c /= units.size()
	var col: Color = COLORS.get(sq.tactic, Color(0.8, 0.8, 0.8))
	if sq.tactic != SquadState.Tactic.NONE:
		col.a = 0.95 if (selected or debug) else 0.7
		if sq.tactic_target.is_finite():
			_line(c, sq.tactic_target, col)
			_ring(sq.tactic_target, 5.0, col)
			if sq.tactic == SquadState.Tactic.ASSAULT or sq.tactic == SquadState.Tactic.FLANK or sq.tactic == SquadState.Tactic.SUPPRESS:
				_ring(sq.tactic_target, 2.0, col)
		if sq.tactic_dest.is_finite():
			_ring(sq.tactic_dest, 3.0, Color(col.r, col.g, col.b, 0.8))
			_line(c, sq.tactic_dest, Color(col.r, col.g, col.b, 0.5))
		if sq.tactic_route.size() > 0:
			var prev := c
			for i in sq.tactic_route.size():
				var p: Vector3 = sq.tactic_route[i]
				_line(prev, p, Color(1.0, 0.3, 0.9, 0.9 if i >= sq.tactic_route_i else 0.3))
				_ring(p, 2.5, Color(1.0, 0.3, 0.9, 0.8))
				prev = p
	if debug or selected:
		for u in units:
			var team := sq.team_of(u.id)
			if team >= 0:
				var tc: Color = TEAM_COLORS[team % 2]
				_ring(u.position, 0.9, Color(tc.r, tc.g, tc.b, 0.95))
				if sq.team_leaders.size() > team and sq.team_leaders[team] == u.id:
					_ring(u.position, 1.4, Color(1, 1, 1, 0.9))
			if debug or sq.faction == player_faction:
				if u.post_pos.is_finite() and u.order == UnitState.Order.MOVE:
					_line(u.position, u.post_pos, Color(0.7, 0.7, 0.7, 0.5))
				if u.post_pos.is_finite():
					_cross(u.post_pos, 0.6, Color(col.r, col.g, col.b, 0.7))
			if u.fire_at.is_finite() and sim.state.time < u.fire_until:
				_line(u.position + Vector3.UP * 1.4, u.fire_at, Color(1.0, 0.2, 0.1, 0.35))
			if debug and u.cover_pos.is_finite():
				_cross(u.cover_pos, 0.4, Color(0.4, 1.0, 0.4, 0.6))
	if sq.tactic != SquadState.Tactic.NONE or debug:
		var text := sim.tactics.short_text(sq)
		if debug:
			var a := sim.tactics.assessment(sq)
			var role := ""
			if sq.op_role != SquadState.OpRole.NONE:
				var op := sim.state.war.operation(sq.op_id)
				role = " [%s%s]" % [SquadState.OP_ROLE_NAMES[sq.op_role].to_upper(), (" / " + op.stage_name()) if op else ""]
			elif sq.defence_role != "":
				role = " [%s]" % sq.defence_role.to_upper()
			text = "%s%s %s | eff %.2f supp %.2f" % [sq.squad_name, role, text if text != "" else "-", a.eff if not a.is_empty() else 0.0, a.supp if not a.is_empty() else 0.0]
		elif text != "" and rts and rts.selected_squads().has(sq.id):
			# UI-01C: a selected squad already carries the HUD's field tag with the same words.
			text = ""
		elif text != "":
			text = "%s · %s" % [sq.squad_name.to_upper(), text.to_upper()]
		if text != "":
			_label(used, c + Vector3.UP * 7.0, text, col if sq.tactic != SquadState.Tactic.NONE else Color(0.8, 0.8, 0.8))
			used += 1
	return used


func _label(i: int, at: Vector3, text: String, col: Color) -> void:
	while _labels.size() <= i:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font = FNUI.font("semibold")
		l.font_size = 17
		l.outline_size = 6
		l.outline_modulate = Color(FNUI.BG, 0.85)
		l.render_priority = 11
		add_child(l)
		_labels.append(l)
	var lab := _labels[i]
	lab.text = text
	lab.modulate = col
	lab.global_position = at
	lab.visible = true


func _h(p: Vector3) -> float:
	if terrain:
		var h: float = terrain.data.get_height(p)
		if not is_nan(h):
			return h
	return p.y


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(a.x, maxf(a.y, _h(a)) + 0.5, a.z))
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(Vector3(b.x, maxf(b.y, _h(b)) + 0.5, b.z))


func _ring(p: Vector3, r: float, col: Color) -> void:
	var n := 20
	var prev := Vector3(p.x + r, 0.0, p.z)
	for k in range(1, n + 1):
		var a := k * TAU / n
		var q := Vector3(p.x + cos(a) * r, 0.0, p.z + sin(a) * r)
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(Vector3(prev.x, _h(prev) + 0.35, prev.z))
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(Vector3(q.x, _h(q) + 0.35, q.z))
		prev = q


func _cross(p: Vector3, r: float, col: Color) -> void:
	_line(p + Vector3(-r, 0, 0), p + Vector3(r, 0, 0), col)
	_line(p + Vector3(0, 0, -r), p + Vector3(0, 0, r), col)
