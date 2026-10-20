extends Node3D
## ASSET-PRODUCTION-01 asset lab: renders and validates the imported asset library in Godot.
##
## Run (see benchmarks/asset01/run_lab.sh):
##   Godot --path . --resolution 1600x900 res://scenes/asset_lab/asset_lab.tscn -- <mode> [filter]
## Modes:
##   --shots [filter]     four views per asset (front 3/4, back 3/4, eye level, top) as one
##                        2 x 2 sheet in docs/asset01/godot/<id>.jpg
##   --validate [filter]  structure, materials, LODs, bounds, collision, markers ->
##                        benchmarks/asset01/validate.json (exit code 1 on failures)
##   --lod [filter]       the same asset seen from LOD0 / LOD1 / LOD2 distances (real
##                        visibility ranges) -> docs/asset01/godot/<id>_lodrange.jpg
## filter: comma list of ids, "family:<name>", or empty for every asset in the catalog.

const CATALOG := "res://assets/military/catalog.json"
const MAT_DIR := "res://assets/military/materials/"
const SHOT_DIR := "res://docs/asset01/godot/"
const BENCH_DIR := "res://benchmarks/asset01/"

var catalog := {}
var cam: Camera3D
var sun: DirectionalLight3D
var ground: MeshInstance3D
var failures: Array[String] = []


func _ready() -> void:
	_setup_world()
	var f := FileAccess.open(CATALOG, FileAccess.READ)
	if f:
		catalog = JSON.parse_string(f.get_as_text())
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "--shots"
	var filt := args[1] if args.size() > 1 and not args[1].begins_with("--") else ""
	var ids := _select(filt)
	print("AP lab mode=%s assets=%d" % [mode, ids.size()])
	match mode:
		"--shots":
			await _shots(ids)
		"--validate":
			_validate(ids)
		"--lod":
			await _lod_range(ids)
		_:
			push_error("unknown mode " + mode)
	print("AP done failures=%d" % failures.size())
	for fl in failures:
		print("AP FAIL ", fl)
	get_tree().quit(1 if failures.size() > 0 else 0)


func _select(filt: String) -> Array:
	var out := []
	for id in catalog.keys():
		if filt == "":
			out.append(id)
		elif filt.begins_with("family:"):
			if catalog[id]["family"] == filt.substr(7):
				out.append(id)
		elif id in filt.split(","):
			out.append(id)
	out.sort()
	return out


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
	sun.rotation_degrees = Vector3(-42, 150, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 2400)
	ground.mesh = pm
	var gm: StandardMaterial3D = (load(MAT_DIR + "Dirt.tres") as StandardMaterial3D).duplicate()
	gm.uv1_scale = Vector3(300, 300, 1)
	gm.vertex_color_use_as_albedo = false
	ground.material_override = gm
	ground.position.y = -0.01
	add_child(ground)
	cam = Camera3D.new()
	cam.fov = 50
	cam.far = 4000
	add_child(cam)
	cam.make_current()


func _spawn(id: String) -> Node3D:
	var path: String = catalog[id]["glb"]
	var ps := load(path) as PackedScene
	if ps == null:
		failures.append("%s: cannot load %s" % [id, path])
		return null
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	return inst


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	return out


static func lod_of(mi: MeshInstance3D) -> int:
	var nm := String(mi.name)
	return int(nm.get_slice("_LOD", 1)) if nm.contains("_LOD") else 0


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


func _look(center: Vector3, dist: float, az_deg: float, el_deg: float) -> void:
	# Azimuth 0 = in front of the asset (Godot -Z side), positive turns to the asset's left.
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	cam.global_position = center + dir * dist
	var up := Vector3.UP if el_deg < 85 else Vector3(0, 0, -1)
	cam.look_at(center, up)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _settle(frames := 6) -> void:
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


# ----------------------------------------------------------------------------- modes


func _shots(ids: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for id in ids:
		var inst := _spawn(id)
		if inst == null:
			continue
		_show_only(inst, 0)
		await _settle(3)
		var b := _aabb(inst)
		var c := b.get_center()
		var r := maxf(b.size.length() * 0.5, 0.4)
		var dist := r / tan(deg_to_rad(cam.fov * 0.42))
		sun.directional_shadow_max_distance = maxf(dist * 3.0, 60.0)
		var imgs := []
		for v in [[35.0, 22.0, 1.0, 0.45], [215.0, 18.0, 1.0, 0.45], [70.0, 3.0, 0.8, 0.30], [0.0, 89.0, 1.1, 0.0]]:
			var tc := Vector3(c.x, b.position.y + b.size.y * v[3], c.z)
			_look(tc, dist * v[2], v[0], v[1])
			await _settle(4)
			imgs.append(await _grab())
		_sheet(imgs, 2).save_jpg(SHOT_DIR + id + ".jpg", 0.88)
		print("AP shot ", id)
		inst.queue_free()
		await _settle(2)


func _lod_range(ids: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	for id in ids:
		var inst := _spawn(id)
		if inst == null:
			continue
		var b := _aabb(inst)
		var ranges: Array = []
		for mi in meshes(inst):
			if mi.visible:
				ranges.append([lod_of(mi), mi.visibility_range_begin, mi.visibility_range_end])
		ranges.sort()
		var imgs := []
		var c := b.get_center()
		for rg in ranges:
			# Just inside each LOD's range; camera zoomed so the asset fills the frame.
			# Middle of each LOD's range (outside the hysteresis margins).
			var d: float = (rg[1] + rg[2]) * 0.5 if rg[2] > 0 else rg[1] * 1.25
			d = maxf(d, b.size.length())
			_look(c, d, 35.0, 12.0)
			cam.fov = clampf(rad_to_deg(2.0 * atan(b.size.length() * 0.6 / d)), 2.0, 50.0)
			sun.directional_shadow_max_distance = d + 100.0
			await _settle(8)
			imgs.append(await _grab())
		cam.fov = 50
		_sheet(imgs, imgs.size(), 0.4).save_jpg(SHOT_DIR + id + "_lodrange.jpg", 0.88)
		inst.queue_free()
		await _settle(2)


func _validate(ids: Array) -> void:
	var report := {}
	for id in ids:
		var e := {}
		var errs: Array[String] = []
		var meta := {}
		var glb: String = catalog[id]["glb"]
		var jf := FileAccess.open(glb.get_basename() + ".json", FileAccess.READ)
		if jf:
			meta = JSON.parse_string(jf.get_as_text())
		var ps := load(glb) as PackedScene
		if ps == null:
			failures.append(id + ": does not load")
			continue
		var inst := ps.instantiate() as Node3D
		add_child(inst)
		var ms := meshes(inst)
		# 1. Authored LODs, LOD0 first (StructureCatalog takes the first MeshInstance3D).
		var names := ms.map(func(m): return String(m.name))
		for i in 3:
			if not ("%s_LOD%d" % [id, i]) in names:
				errs.append("missing %s_LOD%d" % [id, i])
		if ms.size() > 0 and String(ms[0].name) != id + "_LOD0":
			errs.append("first mesh is %s, not LOD0" % ms[0].name)
		# 2. Triangles, surfaces and shared library materials per LOD.
		var tris := [0, 0, 0]
		var surfs := [0, 0, 0]
		var mats := {}
		var ranges := []
		for mi in ms:
			var l := lod_of(mi)
			var mesh := mi.mesh as ArrayMesh
			surfs[l] += mesh.get_surface_count()
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris[l] += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				var m := mesh.surface_get_material(s)
				if m == null or not m.resource_path.begins_with(MAT_DIR):
					errs.append("surface %s/%d not a library material (%s)" % [mi.name, s, m.resource_path if m else "none"])
				else:
					mats[m.resource_path.get_file().get_basename()] = true
				if not (arr[Mesh.ARRAY_COLOR] is PackedColorArray) or (arr[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty():
					errs.append("surface %s/%d has no vertex colours" % [mi.name, s])
			ranges.append([l, mi.visibility_range_begin, mi.visibility_range_end])
		ranges.sort()
		if tris[1] >= tris[0] or tris[2] >= tris[1]:
			errs.append("LOD triangle counts do not decrease: %s" % str(tris))
		for i in range(1, ranges.size()):
			if absf(ranges[i][1] - ranges[i - 1][2]) > 0.01:
				errs.append("LOD ranges not contiguous: %s" % str(ranges))
				break
		if ranges.size() > 0 and ranges[0][2] <= 0.0:
			errs.append("LOD0 has no visibility range")
		# 3. Bounds / orientation against the Blender metadata (Blender y -> Godot -z).
		var b := _aabb(inst)
		if meta.has("bounds_min"):
			var mn: Array = meta["bounds_min"]
			var mx: Array = meta["bounds_max"]
			var want := AABB(Vector3(mn[0], mn[2], -mx[1]), Vector3(mx[0] - mn[0], mx[2] - mn[2], mx[1] - mn[1]))
			if b.position.distance_to(want.position) > 0.02 or b.size.distance_to(want.size) > 0.02:
				errs.append("bounds %s differ from metadata %s" % [str(b), str(want)])
		if b.position.y > 0.05:
			errs.append("asset floats: lowest point %.3f m above the origin" % b.position.y)
		# 4. Collision and markers.
		var bodies := inst.find_children("*", "StaticBody3D", true, false)
		var shapes := inst.find_children("*", "CollisionShape3D", true, false)
		var want_cols: int = (meta.get("collision_boxes_godot", []) as Array).size()
		if shapes.size() != want_cols:
			errs.append("collision shapes %d, metadata %d" % [shapes.size(), want_cols])
		var markers := {}
		for m in meta.get("markers", []):
			var n := inst.find_child(m["name"], true, false) as Node3D
			if n == null:
				errs.append("marker %s missing" % m["name"])
			else:
				var p: Array = m["pos"]
				if n.position.distance_to(Vector3(p[0], p[2], -p[1])) > 0.01:
					errs.append("marker %s at %s, expected Blender %s" % [m["name"], str(n.position), str(p)])
				markers[m["name"]] = true
		if not inst.has_meta("fn_asset"):
			errs.append("no fn_asset metadata (post-import script did not run)")
		e = {"tris": tris, "surfaces": surfs, "materials": mats.keys(), "lod_ranges": ranges, "size": [b.size.x, b.size.y, b.size.z],
			"collision_shapes": shapes.size(), "static_bodies": bodies.size(), "markers": markers.size(), "errors": errs}
		report[id] = e
		for er in errs:
			failures.append("%s: %s" % [id, er])
		print("AP validate %s tris=%s surf=%s mats=%d errors=%d" % [id, str(tris), str(surfs), mats.size(), errs.size()])
		inst.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BENCH_DIR))
	var out := FileAccess.open(BENCH_DIR + "validate.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, " ", true))
