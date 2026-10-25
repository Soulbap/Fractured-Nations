extends Node3D
## VEHICLE-ASSETS-01 vehicle lab: validates and photographs the imported vehicle pack in Godot.
##
## Run (see tools/vehicle_assets/run_vehicle_lab.sh):
##   Godot --path . --fullscreen res://tools/vehicle_assets/vehicle_lab.tscn -- <mode> [ids]
## Modes:
##   --validate [ids]  parts / pivots against the sidecar, LOD meshes and visibility ranges, library
##                     materials, bounds (scale + orientation), collision shapes, markers
##                     -> benchmarks/vehicle_assets01/validate.json (exit 1 on failures)
##   --shots [ids]     per vehicle: front 3/4, rear 3/4, side, elevated 3/4 (1920x1080 each, 2 x 2
##                     sheet), an articulation sheet (turret / gun / doors / hatches / rotors moved
##                     about their pivots), a LOD sheet, and a line-up of all vehicles with a 1.8 m
##                     figure -> docs/vehicle_assets01/godot/
## ids: comma list; empty = every vehicle in assets/military/vehicles/<id>/.

const VEH_DIR := "res://assets/military/vehicles/"
const MAT_DIR := "res://assets/military/materials/"
const SHOT_DIR := "res://docs/vehicle_assets01/godot/"
const OUT_JSON := "res://benchmarks/vehicle_assets01/validate.json"
const IDS := ["iveco_lmv", "patria_6x6", "cv9030n", "scania_military", "leopard_2a8_nor", "nh90_tth"]

var cam: Camera3D
var sun: DirectionalLight3D
var failures: Array[String] = []


func _ready() -> void:
	_setup_world()
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "--validate"
	var ids: Array = IDS.duplicate()
	if args.size() > 1 and not args[1].begins_with("--"):
		ids = Array(args[1].split(","))
	print("VL mode=%s vehicles=%d" % [mode, ids.size()])
	match mode:
		"--validate":
			_validate(ids)
		"--shots":
			await _shots(ids)
		_:
			push_error("unknown mode " + mode)
	print("VL done failures=%d" % failures.size())
	for fl in failures:
		print("VL FAIL ", fl)
	get_tree().quit(1 if failures.size() > 0 else 0)


# ----------------------------------------------------------------------------- world


func _setup_world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var psky := ProceduralSkyMaterial.new()
	psky.sky_top_color = Color(0.36, 0.50, 0.70)
	psky.sky_horizon_color = Color(0.70, 0.74, 0.78)
	psky.ground_horizon_color = Color(0.55, 0.53, 0.50)
	psky.ground_bottom_color = Color(0.25, 0.23, 0.20)
	sky.sky_material = psky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 140, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 2400)
	ground.mesh = pm
	var gm: StandardMaterial3D = (load(MAT_DIR + "Dirt.tres") as StandardMaterial3D).duplicate()
	gm.uv1_scale = Vector3(600, 600, 1)
	gm.vertex_color_use_as_albedo = false
	ground.material_override = gm
	ground.position.y = -0.01
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 40
	cam.far = 4000
	add_child(cam)
	cam.make_current()


func _sidecar(id: String) -> Dictionary:
	var path := VEH_DIR + id + "/" + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _spawn(id: String, pos := Vector3.ZERO) -> Node3D:
	var ps := load(VEH_DIR + id + "/" + id + ".glb") as PackedScene
	if ps == null:
		failures.append("%s: cannot load the GLB" % id)
		return null
	var inst := ps.instantiate() as Node3D
	inst.position = pos
	add_child(inst)
	return inst


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	return out


static func lod_of(mi: MeshInstance3D) -> int:
	var nm := String(mi.name)
	return int(nm.get_slice("_LOD", 1)) if nm.contains("_LOD") else -1


func _aabb(root: Node3D, lod := 0) -> AABB:
	var box := AABB()
	var first := true
	for mi in meshes(root):
		if lod_of(mi) != lod:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _show_only(root: Node3D, lod: int) -> void:
	for mi in meshes(root):
		mi.visible = lod_of(mi) == lod
		mi.visibility_range_begin = 0
		mi.visibility_range_end = 0


# ----------------------------------------------------------------------------- validate


func _validate(ids: Array) -> void:
	var report := {}
	for id in ids:
		var meta := _sidecar(id)
		var r := {"checks": {}, "fail": []}
		if meta.is_empty():
			failures.append("%s: no sidecar" % id)
			continue
		var root := _spawn(id)
		if root == null:
			continue
		var fail: Array = r["fail"]
		# Parts: every sidecar part is a Node3D at its pivot, under its parent, with LOD meshes.
		var parts: Array = meta.get("parts", [])
		var npart := 0
		for p in parts:
			var n := root.find_child(String(p["name"]), true, false) as Node3D
			if n == null:
				fail.append("part %s missing" % p["name"])
				continue
			npart += 1
			var want := Vector3(p["pivot_godot"][0], p["pivot_godot"][1], p["pivot_godot"][2])
			if n.global_position.distance_to(want) > 0.005:
				fail.append("part %s pivot %s != %s" % [p["name"], n.global_position, want])
			var par := String(p["parent"])
			if par != "" and String(n.get_parent().name) != par:
				fail.append("part %s parent %s != %s" % [p["name"], n.get_parent().name, par])
			var lods := {}
			for c in n.get_children():
				if c is MeshInstance3D:
					lods[lod_of(c)] = c
			if not lods.has(0):
				fail.append("part %s has no LOD0 mesh" % p["name"])
		r["checks"]["parts"] = npart
		# Meshes: visibility ranges, library materials, vertex colours.
		var surfaces := 0
		var nonlib := {}
		var no_range := 0
		var tris := [0, 0, 0]
		for mi in meshes(root):
			var k := lod_of(mi)
			if k < 0:
				continue
			if mi.visibility_range_end <= 0.0:
				no_range += 1
			for s in mi.mesh.get_surface_count():
				surfaces += 1
				var m := mi.mesh.surface_get_material(s)
				if m == null or not m.resource_path.begins_with(MAT_DIR):
					nonlib[m.resource_name if m else "<none>"] = true
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris[k] += idx.size() / 3
				if arr[Mesh.ARRAY_COLOR] == null:
					nonlib["no vertex colour on " + String(mi.name)] = true
		if no_range > 0:
			fail.append("%d LOD meshes without a visibility range" % no_range)
		if not nonlib.is_empty():
			fail.append("non-library materials / missing colours: %s" % ", ".join(nonlib.keys()))
		if not (tris[0] >= tris[1] and tris[1] >= tris[2]):
			fail.append("triangles rise across LODs %s" % [tris])
		r["checks"]["tris_godot"] = tris
		r["checks"]["surfaces"] = surfaces
		# Bounds: Blender (x, y, z) -> Godot (x, z, -y); front (+Y) must be Godot -Z.
		var bmin: Array = meta["bounds_min"]
		var bmax: Array = meta["bounds_max"]
		var want_min := Vector3(bmin[0], bmin[2], -bmax[1])
		var want_max := Vector3(bmax[0], bmax[2], -bmin[1])
		var box := _aabb(root, 0)
		var err := maxf(box.position.distance_to(want_min), box.end.distance_to(want_max))
		if err > 0.03:
			fail.append("LOD0 bounds %s..%s != sidecar %s..%s" % [box.position, box.end, want_min, want_max])
		r["checks"]["size_m"] = [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)]
		r["checks"]["bounds_err_m"] = snappedf(err, 0.001)
		# Collision: one StaticBody3D + convex shape per sidecar box.
		var shapes := root.find_children("*", "CollisionShape3D", true, false).size()
		var want_cols: int = meta.get("collision_boxes_godot", []).size()
		if shapes != want_cols:
			fail.append("collision shapes %d != %d" % [shapes, want_cols])
		r["checks"]["collision_shapes"] = shapes
		# Markers.
		var missing := []
		for m in meta.get("markers", []):
			if root.find_child(String(m["name"]), true, false) == null:
				missing.append(m["name"])
		if not missing.is_empty():
			fail.append("markers missing: %s" % [missing])
		r["checks"]["markers"] = meta.get("markers", []).size() - missing.size()
		for fl in fail:
			failures.append("%s: %s" % [id, fl])
		r["pass"] = fail.is_empty()
		report[id] = r
		print("VL validate %s %s %s" % [id, "OK" if fail.is_empty() else "FAIL", JSON.stringify(r["checks"])])
		root.queue_free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_JSON.get_base_dir()))
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))


# ----------------------------------------------------------------------------- shots


func _look(center: Vector3, dist: float, az_deg: float, el_deg: float) -> void:
	# Azimuth 0 = in front of the vehicle (Godot -Z side), positive turns to the vehicle's left.
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(-sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	cam.global_position = center + dir * dist
	cam.look_at(center, Vector3.UP)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _settle(frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame


func _sheet(imgs: Array, cols: int, scale := 0.5) -> Image:
	var w := int(imgs[0].get_width() * scale)
	var h := int(imgs[0].get_height() * scale)
	var rows := int(ceil(imgs.size() / float(cols)))
	var out := Image.create(w * cols, h * rows, false, Image.FORMAT_RGB8)
	for i in imgs.size():
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGB8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	return out


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	img.save_jpg(SHOT_DIR + name + ".jpg", 0.9)
	print("VL shot ", SHOT_DIR + name + ".jpg")


func _frame(root: Node3D) -> Array:
	var box := _aabb(root, 0)
	var c := box.get_center()
	c.y = box.position.y + box.size.y * 0.42
	var r := box.size.length() * 0.5
	return [c, r / sin(deg_to_rad(cam.fov) * 0.5) * 0.92]


## Moves every articulated part about its pivot: turret / RWS yaw, guns up, doors and
## hatches open, ramp down, rotors turned, wheels steered. Visual proof of the pivots. Doors
## and hatches open to the side that moves them up / away from the hull (sign picked by test).
func _articulate(root: Node3D, meta: Dictionary) -> void:
	var centre := _aabb(root, 0).get_center()
	for p in meta.get("parts", []):
		var n := root.find_child(String(p["name"]), true, false) as Node3D
		if n == null:
			continue
		var nm := String(p["name"])
		var axis := String(p["axis"])
		if nm == "Turret":
			n.rotation_degrees.y += 35.0
		elif nm.begins_with("RWS") and axis == "z":
			n.rotation_degrees.y -= 60.0
		elif nm == "Gun" or nm.ends_with("_Gun"):
			n.rotation_degrees.x += 12.0
		elif nm.begins_with("Door_Slide"):
			n.position.z += 1.6
		elif nm.begins_with("Door") or nm.begins_with("Hatch"):
			var deg := 70.0 if nm.begins_with("Door") else 105.0
			var ax := Vector3.UP
			if axis == "x":
				ax = Vector3.RIGHT
			elif axis == "y":
				ax = Vector3.BACK
			_open(n, ax, deg, centre, nm.begins_with("Hatch"))
		elif nm == "Ramp":
			n.rotation_degrees.x += 32.0
		elif nm == "MainRotor":
			n.rotation_degrees.y += 30.0
		elif nm == "TailRotor":
			n.rotation_degrees.x += 30.0
		elif nm.begins_with("Wheel_") and nm.ends_with("1"):
			n.rotation_degrees.y += 25.0


func _part_centre(n: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi in meshes(n):
		if lod_of(mi) != 0:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center()


## Rotates n about its local axis by +deg or -deg, whichever raises a hatch / moves a door
## away from the vehicle centre.
func _open(n: Node3D, ax: Vector3, deg: float, centre: Vector3, up: bool) -> void:
	var base := n.transform
	var best := 0.0
	var best_score := -INF
	for sgn in [1.0, -1.0]:
		n.transform = base.rotated_local(ax, deg_to_rad(deg * sgn))
		var c := _part_centre(n)
		var score := c.y if up else Vector2(c.x - centre.x, c.z - centre.z).length()
		if score > best_score:
			best_score = score
			best = sgn
	n.transform = base.rotated_local(ax, deg_to_rad(deg * best))


func _shots(ids: Array) -> void:
	var views := [["front34", 38, 12], ["rear34", 218, 12], ["side", 90, 3], ["top34", 35, 38]]
	for id in ids:
		var root := _spawn(id)
		if root == null:
			continue
		_show_only(root, 0)
		await _settle(10)
		var fr := _frame(root)
		var imgs := []
		for v in views:
			_look(fr[0], fr[1], v[1], v[2])
			await _settle(4)
			imgs.append(await _grab())
		_save(_sheet(imgs, 2), id)
		# articulation
		_articulate(root, _sidecar(id))
		await _settle(4)
		var art := []
		for v in [["a_front", 30, 14], ["a_rear", 205, 18], ["a_left", 70, 10], ["a_top", 150, 45]]:
			_look(fr[0], fr[1] * 0.62, v[1], v[2])
			await _settle(4)
			art.append(await _grab())
		_save(_sheet(art, 2), id + "_articulation")
		# close-up of the running gear / wheels (left side, sun side)
		var gear := _aabb(root, 0)
		_look(Vector3(gear.position.x, gear.position.y + gear.size.y * 0.25, gear.get_center().z), gear.size.z * 0.55, 80, 6)
		await _settle(4)
		_save(await _grab(), id + "_closeup")
		root.queue_free()
		await _settle(2)
		# LOD sheet: each LOD from the same view
		root = _spawn(id)
		var lods := []
		for k in 3:
			_show_only(root, k)
			_look(fr[0], fr[1], 38, 12)
			await _settle(4)
			lods.append(await _grab())
		_save(_sheet(lods, 3, 0.4), id + "_lods")
		root.queue_free()
		await _settle(2)
	# line-up for relative scale, with a 1.8 m figure
	var x := 0.0
	var nodes := []
	var order := ["iveco_lmv", "scania_military", "patria_6x6", "cv9030n", "leopard_2a8_nor", "nh90_tth"]
	for id in order:
		if not id in ids:
			continue
		var meta := _sidecar(id)
		# side by side along X, each turned to show its left side: spacing by length
		var w: float = float(meta["size_above_ground"][1]) if not meta.is_empty() else 6.0
		if id == "nh90_tth":
			w = 17.0
		x += w * 0.5 + 1.0
		var r := _spawn(id, Vector3(x, 0, 0))
		if r:
			r.rotation_degrees.y = -90.0
			nodes.append(r)
		x += w * 0.5 + 1.0
	var fig := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.25
	cm.height = 1.8
	fig.mesh = cm
	fig.position = Vector3(1.0, 0.9, 3.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.85, 0.35, 0.1)
	fig.material_override = fm
	add_child(fig)
	await _settle(10)
	var cx := x * 0.5
	cam.fov = 40
	cam.global_position = Vector3(cx, 5.0, x * 0.82)
	cam.look_at(Vector3(cx, 1.0, 0), Vector3.UP)
	await _settle(6)
	var a := await _grab()
	cam.global_position = Vector3(cx - x * 0.10, 22.0, x * 0.72)
	cam.look_at(Vector3(cx, 0.5, 0), Vector3.UP)
	await _settle(6)
	var b := await _grab()
	_save(a, "lineup")
	_save(b, "lineup_above")
