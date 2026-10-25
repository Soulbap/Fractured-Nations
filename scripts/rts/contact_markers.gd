## COMBAT-01 RTS contact markers: what the selected squad's soldiers know of the enemy, and nothing more.
##
## Read only from the soldiers' own perception records (CombatBrain writes them): an enemy a soldier sees right now
## (target_visible, target_last_pos - written at the sighting) is a solid red diamond; once nobody of the squad sees it
## the marker stays where it was last seen as a hollow diamond and fades over remember_s; where a soldier was fired on
## from (threat_pos, already blurred by CombatBrain) is a small hollow orange triangle that fades over fire_s. A hidden
## enemy is never followed: a remembered marker moves only when a soldier of the squad sees that enemy again. No enemy
## record is read here. Shown in the tactical view for the selected squads (and loose selected soldiers); the markers
## keep their size on screen, merge when they overlap, and are capped (max_markers) in a large fight.
class_name ContactMarkers
extends Node3D

@export var remember_s := 20.0
@export var fire_s := 8.0
@export var max_markers := 40
## Marker size as a share of the camera distance (constant on screen), never smaller than min_size_m.
@export var screen_size := 0.016
@export var min_size_m := 0.6
@export var merge_m := 4.0

var sim: WorldSim
var rts: RTSController
var game: GameController
## squad id (or -unit id for loose soldiers) -> {enemy id: [position, last seen]}
var _memory := {}
var _pool: Array[MeshInstance3D] = []
var _mats := {}
var shown := {"seen": 0, "remembered": 0, "fired_from": 0}


func _ready() -> void:
	for kind in ["seen", "remembered", "fired_from"]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.render_priority = 3
		m.albedo_texture = _texture(kind)
		m.albedo_color = Color(1.0, 0.22, 0.18) if kind != "fired_from" else Color(1.0, 0.62, 0.15)
		_mats[kind] = m
	for i in max_markers:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_pool.append(mi)


func _process(_delta: float) -> void:
	for mi in _pool:
		mi.visible = false
	shown = {"seen": 0, "remembered": 0, "fired_from": 0}
	if sim == null or rts == null or (game and game.mode != GameController.Mode.RTS):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var now := sim.state.time
	var marks: Array = []   # [position, kind, alpha]
	for key: int in _groups():
		var units: Array = _units_of(key)
		var mem: Dictionary = _memory.get(key, {})
		var seen_ids := {}
		for u: UnitState in units:
			if not u.alive:
				continue
			# Seen now or remembered by the soldier: only the position its perception wrote.
			if u.target_id > 0 and u.target_last_pos.is_finite():
				var e: Array = mem.get(u.target_id, [u.target_last_pos, u.target_seen_at])
				if u.target_seen_at >= float(e[1]):
					mem[u.target_id] = [u.target_last_pos, u.target_seen_at]
				if u.target_visible and now - u.target_seen_at < 0.8:
					seen_ids[u.target_id] = true
			if u.threat_pos.is_finite() and now - u.threat_at < fire_s and not (u.target_visible and u.target_id > 0):
				marks.append([u.threat_pos, "fired_from", 1.0 - (now - u.threat_at) / fire_s])
		for id: int in mem.keys():
			var e: Array = mem[id]
			var age := now - float(e[1])
			if age > remember_s:
				mem.erase(id)
				continue
			if seen_ids.has(id):
				marks.append([e[0], "seen", 1.0])
			else:
				marks.append([e[0], "remembered", clampf(1.0 - age / remember_s, 0.15, 0.85)])
		_memory[key] = mem
	# Merge overlapping marks (a group of enemies reads as one), the most certain kind wins.
	var rank := {"seen": 0, "remembered": 1, "fired_from": 2}
	marks.sort_custom(func(a: Array, b: Array) -> bool: return rank[a[1]] < rank[b[1]] or (rank[a[1]] == rank[b[1]] and float(a[2]) > float(b[2])))
	var placed: Array = []
	for m: Array in marks:
		if placed.size() >= _pool.size():
			break
		var p: Vector3 = m[0]
		var dup := false
		for q: Array in placed:
			if Vector2(p.x - q[0].x, p.z - q[0].z).length() < merge_m * maxf(1.0, cam.global_position.distance_to(p) / 150.0):
				dup = true
				break
		if dup:
			continue
		placed.append(m)
	for i in placed.size():
		var m: Array = placed[i]
		var mi := _pool[i]
		var p: Vector3 = m[0] + Vector3.UP * 2.2
		var size := maxf(cam.global_position.distance_to(p) * screen_size, min_size_m)
		mi.material_override = _mats[m[1]]
		mi.transparency = 1.0 - clampf(float(m[2]), 0.0, 1.0)
		mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size * (0.8 if m[1] == "fired_from" else 1.0)), p)
		mi.visible = true
		shown[m[1]] += 1


## Selected squads (by squad id) and loose selected soldiers (by -unit id).
func _groups() -> Array:
	var out: Array = rts.selected_squads()
	for id in rts.loose_selected():
		out.append(-int(id))
	return out


func _units_of(key: int) -> Array:
	var out: Array = []
	if key < 0:
		var u := sim.state.get_unit(-key)
		if u:
			out.append(u)
		return out
	var sq := sim.state.get_squad(key)
	if sq:
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u:
				out.append(u)
	return out


static func _texture(kind: String) -> ImageTexture:
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := 0.0
			if kind == "fired_from":
				# hollow triangle pointing down
				var inside := v > -0.7 and v < 0.75 and absf(u) < (0.75 - v) * 0.62
				var inner := v > -0.45 and v < 0.45 and absf(u) < (0.45 - v) * 0.5
				a = 1.0 if inside and not inner else 0.0
			else:
				var d := absf(u) + absf(v)
				if kind == "seen":
					a = 1.0 if d < 0.8 else (0.0 if d > 0.95 else 0.35)
				else:
					a = 1.0 if d < 0.85 and d > 0.58 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
