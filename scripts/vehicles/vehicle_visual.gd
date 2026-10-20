## The look of a vehicle (LOGISTICS-01): the body GLB, separate wheels instanced at its
## WHEEL_* markers, LOD ranges, faction paint, and the pose each frame (wheel spin and
## steering, ground contact and body tilt from ground samples).
##
## Pure presentation: it reads the UnitState/VehicleState record and never writes it. Used by
## VehicleBody (all LODs, wheels) and by UnitProxy (LOD2 hull only, far from the camera).
class_name VehicleVisual
extends Node3D

const PAINT := {1: "res://assets/military/materials/Paint_Tan.tres", 2: "res://assets/military/materials/Paint_Grey.tres"}

var def: VehicleDefs.Def
var body: Node3D
## Collision shapes taken from the GLB (COL_* children), for the owning body to adopt.
var collision_shapes: Array[CollisionShape3D] = []
## [{steer, spin, flip, rest: Vector3 (wheel centre, local), factor, axle}]
var wheels: Array[Dictionary] = []
var markers := {}
var lod_count := 0

var _spin := 0.0
var _tilt := Vector2.ZERO
var _lift := 0.0
var _wheel_dy := PackedFloat32Array()


## near: wheels and all LODs; far: the LOD2 hull only (the strategic distance).
func build(type_id: StringName, faction: int, far := false) -> void:
	def = VehicleDefs.get_def(type_id)
	body = (load(def.body_glb) as PackedScene).instantiate()
	add_child(body)
	for c in body.get_children():
		if c is Node3D and not (c is MeshInstance3D) and not String(c.name).begins_with("COL_"):
			markers[String(c.name)] = (c as Node3D).position
	for c in body.get_children():
		if String(c.name).begins_with("COL_"):
			for s in c.get_children():
				if s is CollisionShape3D:
					var sh := s as CollisionShape3D
					var copy := CollisionShape3D.new()
					copy.shape = sh.shape
					copy.transform = sh.transform
					collision_shapes.append(copy)
			c.queue_free()
	for c in body.get_children():
		if c is MeshInstance3D:
			_set_lod(c as MeshInstance3D, far)
	_paint(body, faction)
	if not far:
		_build_wheels(faction)


func _set_lod(mi: MeshInstance3D, far: bool) -> void:
	var nm := String(mi.name)
	var k := -1
	for i in 3:
		if nm.ends_with("_LOD%d" % i):
			k = i
	if k < 0:
		return
	if far:
		if k != 2:
			mi.queue_free()
		return
	var r := VehicleDefs.LOD_RANGES[k]
	mi.visibility_range_begin = r.x
	mi.visibility_range_end = r.y
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	lod_count += 1


func _paint(root: Node, faction: int) -> void:
	if not PAINT.has(faction):
		return
	var m := load(PAINT[faction]) as Material
	for mi: MeshInstance3D in UnitVisuals.mesh_instances(root):
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat and mat.resource_name == "Paint_Green":
				mi.set_surface_override_material(s, m)


func _build_wheels(faction: int) -> void:
	var scene := load(def.wheel_glb) as PackedScene
	var names := markers.keys()
	names.sort()
	for nm: String in names:
		if not nm.begins_with("WHEEL_"):
			continue
		var axle := int(nm.substr(6, 1))
		var pos: Vector3 = markers[nm]
		var steer := Node3D.new()
		steer.name = "Steer_" + nm
		steer.position = pos
		add_child(steer)
		var spin := Node3D.new()
		steer.add_child(spin)
		var flip := Node3D.new()
		spin.add_child(flip)
		if pos.x < 0.0:
			flip.rotation.y = PI
		var w := scene.instantiate() as Node3D
		flip.add_child(w)
		# The wheel asset's origin is on the ground under its axle: the axle marker is at (0, r, 0).
		w.position = Vector3(0.0, -def.wheel_radius, 0.0)
		for c in w.get_children():
			if c is MeshInstance3D:
				_set_lod(c as MeshInstance3D, false)
		wheels.append({"steer": steer, "spin": spin, "rest": pos, "factor": def.steer_axles.get(axle, 0.0), "axle": axle})
	_wheel_dy.resize(wheels.size())
	_paint_wheels(faction)


func _paint_wheels(faction: int) -> void:
	for w in wheels:
		_paint(w.steer, faction)


## Poses the vehicle for this frame from its record. `ground` maps a world position to the
## ground height there (terrain or bridge deck). dt: seconds since the last pose.
func pose(u: UnitState, dt: float, ground: Callable) -> void:
	var v := u.veh
	if v == null or wheels.is_empty():
		return
	_spin += v.speed * dt / def.wheel_radius
	var gt := global_transform
	var n := wheels.size()
	var hs := PackedFloat32Array()
	hs.resize(n)
	var mean_h := 0.0
	var front := 0.0
	var rear := 0.0
	var zf := 0.0
	var zr := 0.0
	var nf := 0
	var nr := 0
	var left := 0.0
	var right := 0.0
	var nl := 0
	var nrt := 0
	var zmin := INF
	var zmax := -INF
	var xmax := 0.0
	for i in n:
		var rest: Vector3 = wheels[i].rest
		zmin = minf(zmin, rest.z)
		zmax = maxf(zmax, rest.z)
		xmax = maxf(xmax, absf(rest.x))
	var zmid := (zmin + zmax) * 0.5
	for i in n:
		var rest: Vector3 = wheels[i].rest
		var wp := gt * Vector3(rest.x, 0.0, rest.z)
		var h: float = ground.call(wp)
		hs[i] = h
		mean_h += h
		if rest.z < zmid:
			front += h
			zf += rest.z
			nf += 1
		else:
			rear += h
			zr += rest.z
			nr += 1
		if rest.x < 0.0:
			left += h
			nl += 1
		else:
			right += h
			nrt += 1
	mean_h /= n
	var pitch := 0.0
	if nf > 0 and nr > 0:
		pitch = atan2(front / nf - rear / nr, maxf(zr / nr - zf / nf, 1.0))
	var roll := atan2(right / maxi(nrt, 1) - left / maxi(nl, 1), xmax * 2.0) if nl > 0 and nrt > 0 else 0.0
	var k := clampf(12.0 * dt, 0.0, 1.0)
	_tilt = _tilt.lerp(Vector2(pitch, roll), k)
	var lift := mean_h - global_position.y
	_lift = lerpf(_lift, lift, k)
	body.position.y = _lift
	body.rotation = Vector3(_tilt.x, 0.0, _tilt.y)
	for i in n:
		var w: Dictionary = wheels[i]
		var rest: Vector3 = w.rest
		# Where the tilted body plane is over this wheel, and how far the ground deviates.
		var tilt_term := (zmid - rest.z) * tan(_tilt.x) + rest.x * tan(_tilt.y)
		var dy := clampf(hs[i] - (mean_h + tilt_term), -0.22, 0.22)
		_wheel_dy[i] = lerpf(_wheel_dy[i], dy, k)
		var steer: Node3D = w.steer
		steer.position = Vector3(rest.x, rest.y + _lift + tilt_term + _wheel_dy[i], rest.z)
		steer.rotation.y = v.steer * float(w.factor)
		(w.spin as Node3D).rotation.x = fposmod(-_spin, TAU)
