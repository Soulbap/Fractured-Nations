## The look of a vehicle (LOGISTICS-01): the body GLB, separate wheels instanced at its
## WHEEL_* markers, LOD ranges, faction paint, and the pose each frame (wheel spin and
## steering, ground contact and body tilt from ground samples).
##
## Pure presentation: it reads the UnitState/VehicleState record and never writes it. Used by
## VehicleBody (all LODs, wheels) and by UnitProxy (LOD2 hull only, far from the camera).
##
## ASSET-INTEGRATION-01: an articulated type (VehicleDefs.Def.articulated, the VEHICLE-ASSETS-01 pack) brings its running
## gear and moving parts in its own GLB as pivots listed in the JSON sidecar; the same pose() spins and steers its wheels,
## spins road wheels / sprockets / idlers / rollers, opens doors, hatches and ramps (about the axis the sidecar gives) while
## the transport boards or unloads, turns the turret, gun and remote weapon station to turret_yaw / gun_pitch, and spins
## rotors. Those inputs are presentation only (no vehicle weapons or crew exist in the simulation yet); the development
## armoury sets them.
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
	if def.articulated:
		_build_parts(far)
	elif not far:
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
	if v != null and def.articulated:
		_pose_parts(v, dt, ground)
		return
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


# --- ASSET-INTEGRATION-01: articulated bodies (VEHICLE-ASSETS-01) -------------------------------------------------------

## Presentation inputs: turret / RWS yaw and gun / RWS pitch (rad, + = left / up), doors (-1 = follow the transport phase,
## else 0..1 open), rotor speed (rad/s; NAN = idling while anyone is aboard or boarding).
var turret_yaw := 0.0
var gun_pitch := 0.0
var rws_yaw := 0.0
var rws_pitch := 0.0
var doors_open := -1.0
var rotor_rate := NAN
## [{node, rest: Transform3D, kind: "wheel" | "track" | "door" | "slide" | "turret" | "gun" | "rws" | "rws_gun" | "rotor" |
## "tail_rotor" | "steering", r (rolling radius), steer (share of the steering angle), axis, angle (hinge, open)}]
var parts: Array[Dictionary] = []
## Seats of the type (SEAT_* markers, body space): where transport could show its passengers (they are hidden aboard).
var seats := {}
var _dist := 0.0
var _open := 0.0
var _rotor := 0.0
var _tail := 0.0
var _rotor_speed := 0.0

const DOOR_ANGLE := {"Door": 1.25, "Hatch": 1.7, "Ramp": 0.55}
const SLIDE_M := 1.3


func _build_parts(far: bool) -> void:
	for mi: MeshInstance3D in UnitVisuals.mesh_instances(body):
		if far:
			if not String(mi.name).ends_with("_LOD2"):
				mi.queue_free()
		elif mi.visibility_range_end <= 0.0 and mi.visibility_range_begin <= 0.0:
			# the library import sets the sidecar's ranges; a mesh without them gets the shared ones
			_set_lod(mi, false)
		else:
			lod_count += 1
	for nm: String in markers:
		if nm.begins_with("SEAT_"):
			seats[nm] = markers[nm]
	if far:
		return
	var axes := {}
	var sc_path := def.body_glb.get_basename() + ".json"
	if FileAccess.file_exists(sc_path):
		var sc: Variant = JSON.parse_string(FileAccess.get_file_as_string(sc_path))
		if sc is Dictionary:
			for p: Dictionary in sc.get("parts", []):
				axes[String(p.name)] = String(p.get("axis", ""))
	for pname: String in axes:
		var n := body.find_child(pname, true, false) as Node3D
		if n == null or pname == "Body":
			continue
		var e := {"node": n, "rest": n.transform, "kind": "", "r": 0.5, "steer": 0.0}
		if pname.begins_with("Wheel_"):
			e.kind = "wheel"
			e.r = _radius_of(n, def.wheel_radius)
			e.steer = float(def.steer_axles.get(int(pname.right(1)), 0.0))
		elif pname.begins_with("RoadWheel_") or pname.begins_with("Sprocket_") or pname.begins_with("Idler_") or pname.begins_with("Roller_"):
			e.kind = "track"
			e.r = _radius_of(n, def.wheel_radius)
		elif pname in ["Turret", "Gun", "RWS", "RWS_Gun", "MainRotor", "TailRotor", "SteeringWheel"]:
			e.kind = {"Turret": "turret", "Gun": "gun", "RWS": "rws", "RWS_Gun": "rws_gun", "MainRotor": "rotor",
				"TailRotor": "tail_rotor", "SteeringWheel": "steering"}[pname]
		elif pname.begins_with("Door_") or pname.begins_with("Hatch_") or pname == "Ramp":
			var ax: String = axes[pname]
			if ax.begins_with("slide"):
				e.kind = "slide"
				# Blender -Y (aft) is Godot +Z
				e.axis = Vector3(0, 0, 1) if ax.ends_with("-y") else Vector3(0, 0, -1)
			else:
				e.kind = "door"
				# Blender axes: x = Godot X, y (forward) = Godot Z, z (up) = Godot Y
				e.axis = {"x": Vector3.RIGHT, "y": Vector3.BACK, "z": Vector3.UP}.get(ax, Vector3.UP)
				e.angle = _open_angle(n, e.axis, DOOR_ANGLE.get(pname.get_slice("_", 0), 1.25), pname == "Ramp")
		else:
			continue
		parts.append(e)


## Rolling radius of a wheel pivot: half its LOD0 mesh's height (fallback: the type's wheel radius).
static func _radius_of(n: Node3D, fallback: float) -> float:
	for c in n.get_children():
		if c is MeshInstance3D and String(c.name).ends_with("_LOD0"):
			var h := (c as MeshInstance3D).get_aabb().size.y
			if h > 0.05:
				return h * 0.5
	return fallback


## The signed opening angle of a hinged part: the sign that swings the part's middle away from the hull (doors about the
## vertical), up (hatches) or down (a ramp).
static func _open_angle(n: Node3D, axis: Vector3, mag: float, down: bool) -> float:
	var c := Vector3.ZERO
	for m in n.get_children():
		if m is MeshInstance3D and String(m.name).ends_with("_LOD0"):
			c = (m as MeshInstance3D).get_aabb().get_center()
	var best := mag
	var score := -INF
	for sgn: float in [1.0, -1.0]:
		var q := n.position + Basis(axis, sgn * mag) * (n.basis * c)
		var sc: float = Vector2(q.x, q.z).length() if axis == Vector3.UP else (-q.y if down else q.y)
		if sc > score:
			score = sc
			best = sgn * mag
	return best


func _pose_parts(v: VehicleState, dt: float, ground: Callable) -> void:
	_dist += v.speed * dt
	# Ride the ground: pitch, roll and lift from the ground under the footprint's corners.
	var gt := global_transform
	var hw := def.width * 0.5 - 0.2
	var hl := minf(def.length * 0.5 - 0.5, 4.0)
	var hs: Array[float] = []
	for p in [Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(-hw, 0, hl), Vector3(hw, 0, hl)]:
		hs.append(float(ground.call(gt * p)))
	var front := (hs[0] + hs[1]) * 0.5
	var rear := (hs[2] + hs[3]) * 0.5
	var k := clampf(12.0 * dt, 0.0, 1.0)
	_tilt = _tilt.lerp(Vector2(atan2(front - rear, hl * 2.0), atan2((hs[1] + hs[3]) * 0.5 - (hs[0] + hs[2]) * 0.5, hw * 2.0)), k)
	_lift = lerpf(_lift, (front + rear) * 0.5 - global_position.y, k)
	body.position.y = _lift
	body.rotation = Vector3(_tilt.x, 0.0, _tilt.y)
	# Doors follow the transport (open while it boards / unloads at a stop) unless the armoury holds them.
	var want := doors_open
	if want < 0.0:
		var busy := v.phase == VehicleState.Phase.BOARDING or v.phase == VehicleState.Phase.UNLOADING
		want = 1.0 if busy and absf(v.speed) < 0.5 else 0.0
	_open = move_toward(_open, want, dt * 0.8)
	var rate := rotor_rate
	if is_nan(rate):
		rate = 4.0 if not v.occupants.is_empty() or v.phase == VehicleState.Phase.BOARDING else 0.0
	_rotor_speed = move_toward(_rotor_speed, rate, dt * 3.0)
	_rotor = fposmod(_rotor + _rotor_speed * dt, TAU)
	_tail = fposmod(_tail + _rotor_speed * dt * 5.0, TAU)
	var s := smoothstep(0.0, 1.0, _open)
	for e: Dictionary in parts:
		var n: Node3D = e.node
		var rest: Transform3D = e.rest
		match String(e.kind):
			"wheel":
				var spin := Basis(Vector3.RIGHT, -fposmod(_dist / float(e.r), TAU))
				n.transform = Transform3D(Basis(Vector3.UP, v.steer * float(e.steer)) * spin * rest.basis, rest.origin)
			"track":
				n.transform = Transform3D(Basis(Vector3.RIGHT, -fposmod(_dist / float(e.r), TAU)) * rest.basis, rest.origin)
			"turret":
				n.transform = Transform3D(Basis(Vector3.UP, turret_yaw) * rest.basis, rest.origin)
			"gun":
				n.transform = Transform3D(Basis(Vector3.RIGHT, gun_pitch) * rest.basis, rest.origin)
			"rws":
				n.transform = Transform3D(Basis(Vector3.UP, rws_yaw) * rest.basis, rest.origin)
			"rws_gun":
				n.transform = Transform3D(Basis(Vector3.RIGHT, rws_pitch) * rest.basis, rest.origin)
			"rotor":
				n.transform = Transform3D(Basis(Vector3.UP, _rotor) * rest.basis, rest.origin)
			"tail_rotor":
				n.transform = Transform3D(Basis(Vector3.RIGHT, _tail) * rest.basis, rest.origin)
			"steering":
				n.transform = Transform3D(Basis(rest.basis.z.normalized(), -v.steer * 6.0) * rest.basis, rest.origin)
			"door":
				n.transform = Transform3D(Basis(e.axis, float(e.angle) * s) * rest.basis, rest.origin)
			"slide":
				n.transform = Transform3D(rest.basis, rest.origin + (e.axis as Vector3) * SLIDE_M * s)


## Part entries of one kind (tests, inspection).
func parts_of(kind: String) -> Array:
	return parts.filter(func(e: Dictionary) -> bool: return e.kind == kind)


## How far the doors are open now (0..1; tests).
func doors_amount() -> float:
	return _open
