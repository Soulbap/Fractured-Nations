extends Node3D
## WEAPON-ASSETS-01 weapon lab: validates and photographs the imported weapon pack in Godot.
##
## Run (see tools/weapon_assets/run_weapon_lab.sh):
##   Godot --path . --fullscreen res://tools/weapon_assets/weapon_lab.tscn -- <mode> [ids]
## Modes:
##   --validate [ids]  parts / pivots against the sidecar, LOD meshes per part, materials known to
##                     InfantryMaterials.TABLE, bounds (scale + orientation: muzzle towards Godot -Z),
##                     markers, the InfantryEquipment resource -> benchmarks/weapon_assets01/validate.json
##   --shots [ids]     per weapon: left, right, front 3/4, rear 3/4 (2 x 2 sheet) and first person
##                     (the game's Viewmodel holding the weapon at HIP and ADS) + LOD1 / LOD2, each frame
##                     1920x1080 -> docs/weapon_assets01/godot/
##   --showcase        all weapons on a rack (NATO / Russian), two overview shots; with no arguments
##                     (opened in the editor) the showcase stays open.
## ids: comma list of ids without the "weapon_" prefix; empty = all 16.

const WPN_DIR := "res://assets/weapons/"
const SHOT_DIR := "res://docs/weapon_assets01/godot/"
const OUT_JSON := "res://benchmarks/weapon_assets01/validate.json"
const NATO := ["hk416", "hk417", "fn_minimi", "fn_mag", "glock_17", "axmc", "carl_gustaf_m4", "m72_law"]
const RUS := ["ak12", "ak74m", "rpk74m", "svd", "pkp_pecheneg", "mp443", "rpg7", "rpg26"]
## Same camera as the game's first person (COMBAT-01 shots were taken at 75 degrees).
const FPS_FOV := 75.0

var cam: Camera3D
var failures: Array[String] = []
var stay_open := false


func _ready() -> void:
	_setup_world()
	var args := OS.get_cmdline_user_args()
	stay_open = args.is_empty()
	var mode := args[0] if args.size() > 0 else "--showcase"
	var ids: Array = NATO + RUS
	if args.size() > 1 and not args[1].begins_with("--"):
		ids = Array(args[1].split(","))
	print("WL mode=%s weapons=%d" % [mode, ids.size()])
	match mode:
		"--validate":
			_validate(ids)
		"--shots":
			await _shots(ids)
		"--showcase":
			await _showcase()
		_:
			push_error("unknown mode " + mode)
	if stay_open:
		return
	print("WL done failures=%d" % failures.size())
	for fl in failures:
		print("WL FAIL ", fl)
	get_tree().quit(1 if failures.size() > 0 else 0)


# ----------------------------------------------------------------------------- world


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.38, 0.40)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_radius = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	# Key light from above the weapon's left side (the side the views and the showcase show), fill from the right.
	sun.rotation_degrees = Vector3(-35, -125, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 20.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 55, 0)
	fill.light_energy = 0.9
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 30
	cam.near = 0.01
	add_child(cam)
	cam.make_current()


static func folder(id: String) -> String:
	return WPN_DIR + ("russian/" if id in RUS else "nato/") + id + "/"


func _sidecar(id: String) -> Dictionary:
	var path := folder(id) + "weapon_" + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


## The weapon as a character holds it: library materials by name (InfantryMaterials), one LOD shown.
func _spawn(id: String, lod := 0) -> Node3D:
	var ps := load(folder(id) + "weapon_" + id + ".glb") as PackedScene
	if ps == null:
		failures.append("%s: cannot load the GLB" % id)
		return null
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	for mi in meshes(inst):
		mi.visible = lod_of(mi) == lod
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m:
				mi.set_surface_override_material(s, InfantryMaterials.get_material(m.resource_name, 0))
	return inst


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		out.append(n)
	return out


static func lod_of(mi: Node) -> int:
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


# ----------------------------------------------------------------------------- validate


func _validate(ids: Array) -> void:
	var report := {}
	for id in ids:
		var wid := "weapon_" + String(id)
		var meta := _sidecar(id)
		if meta.is_empty():
			failures.append("%s: no sidecar" % id)
			continue
		var root := _spawn(id)
		if root == null:
			continue
		var fail: Array = []
		var checks := {}
		# Parts: pivot node at the sidecar pivot, LOD meshes named <wid>[_<Part>]_LOD<k> wherever the part has triangles.
		var names := {}
		for mi in meshes(root):
			names[String(mi.name)] = mi
		for p in meta.get("parts", []):
			var pn := String(p["name"])
			var node_name := String(p["node"])
			if node_name != "":
				var n := root.find_child(node_name, true, false) as Node3D
				if n == null:
					fail.append("part %s: pivot node %s missing" % [pn, node_name])
				else:
					var want := Vector3(p["pivot_godot"][0], p["pivot_godot"][1], p["pivot_godot"][2])
					if n.global_position.distance_to(want) > 0.002:
						fail.append("part %s pivot %s != %s" % [pn, n.global_position, want])
			var prefix := wid if pn == "Body" else "%s_%s" % [wid, pn]
			for k in 3:
				if int(p["tris"][k]) > 0 and not names.has("%s_LOD%d" % [prefix, k]):
					fail.append("part %s: mesh %s_LOD%d missing" % [pn, prefix, k])
		checks["parts"] = meta.get("parts", []).size()
		# Materials: every surface name must resolve in the character material table (else it renders grey).
		var unknown := {}
		var tris := [0, 0, 0]
		for mi in meshes(root):
			var k := lod_of(mi)
			if k < 0 or k > 2:
				fail.append("mesh %s has no LOD suffix" % mi.name)
				continue
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				var mn := m.resource_name if m else "<none>"
				if not InfantryMaterials.TABLE.has(mn):
					unknown[mn] = true
				tris[k] += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		if not unknown.is_empty():
			fail.append("materials not in InfantryMaterials.TABLE: %s" % ", ".join(unknown.keys()))
		if not (tris[0] > tris[1] and tris[1] > tris[2] and tris[2] > 0):
			fail.append("LOD triangles not decreasing %s" % [tris])
		checks["tris_godot"] = tris
		# Bounds: Blender (x, y, z) -> Godot (x, z, -y); the muzzle (+Y) must point to Godot -Z.
		var bmin: Array = meta["bounds_min"]
		var bmax: Array = meta["bounds_max"]
		var want_min := Vector3(bmin[0], bmin[2], -bmax[1])
		var want_max := Vector3(bmax[0], bmax[2], -bmin[1])
		var box := _aabb(root, 0)
		var err := maxf(box.position.distance_to(want_min), box.end.distance_to(want_max))
		if err > 0.01:
			fail.append("LOD0 bounds %s..%s != sidecar %s..%s" % [box.position, box.end, want_min, want_max])
		checks["size_m"] = [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)]
		# Scale: the overall length against the published figure (launcher: muzzle to breech markers).
		var dims: Dictionary = meta.get("dimensions_m", {})
		for key in ["overall", "length", "launcher", "extended"]:
			if dims.has(key):
				var want_len := float(dims[key])
				var got := box.size.z
				if key == "launcher":
					got = absf(_marker_pos(root, "ATT_Muzzle").z - _marker_pos(root, "ATT_Breech").z)
				checks["length_m"] = [snappedf(got, 0.001), want_len]
				if absf(got - want_len) > maxf(0.015, want_len * 0.04):
					fail.append("length %.3f m vs published %.3f m (%s)" % [got, want_len, key])
				break
		# Markers: present, at the sidecar position; muzzle ahead of the grip; grip at the origin.
		var missing := []
		for m in meta.get("markers", []):
			var n := root.find_child(String(m["name"]), true, false) as Node3D
			if n == null:
				missing.append(m["name"])
				continue
			var want := Vector3(m["pos_godot"][0], m["pos_godot"][1], m["pos_godot"][2])
			if n.global_position.distance_to(want) > 0.002:
				fail.append("marker %s at %s != %s" % [m["name"], n.global_position, want])
		if not missing.is_empty():
			fail.append("markers missing: %s" % [missing])
		var muzzle := _marker_pos(root, "ATT_Muzzle")
		if muzzle.z > -0.08:
			fail.append("ATT_Muzzle %s is not ahead of the grip (-Z)" % muzzle)
		if _marker_pos(root, "GRIP_Main").length() > 0.001:
			fail.append("GRIP_Main is not at the origin")
		checks["markers"] = meta.get("markers", []).size() - missing.size()
		# Equipment resource used by loadouts.
		var eq := load(folder(id) + wid + ".tres") as InfantryEquipment
		if eq == null or eq.id != wid or eq.scene == null or eq.attach != "ATT_Weapon":
			fail.append("InfantryEquipment %s.tres missing or wrong" % wid)
		for fl in fail:
			failures.append("%s: %s" % [id, fl])
		report[id] = {"pass": fail.is_empty(), "checks": checks, "fail": fail}
		print("WL validate %s %s %s" % [id, "OK" if fail.is_empty() else "FAIL", JSON.stringify(checks)])
		root.queue_free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_JSON.get_base_dir()))
	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, " "))


func _marker_pos(root: Node3D, nm: String) -> Vector3:
	var n := root.find_child(nm, true, false) as Node3D
	return n.global_position if n else Vector3.ZERO


# ----------------------------------------------------------------------------- shots


func _look_at_box(box: AABB, az_deg: float, el_deg: float, fov := 30.0) -> void:
	# Azimuth 0 = the weapon's left side (Godot -X), positive towards the muzzle (-Z).
	var c := box.get_center()
	var r := box.size.length() * 0.5
	var dist := r / sin(deg_to_rad(fov * 0.5)) * 0.92
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(-cos(az) * cos(el), sin(el), -sin(az) * cos(el))
	cam.fov = fov
	cam.position = c + dir * dist
	cam.look_at(c, Vector3.UP)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


static func sheet(imgs: Array) -> Image:
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var out := Image.create(w, h, false, imgs[0].get_format())
	for i in imgs.size():
		var im: Image = imgs[i].duplicate()
		im.resize(w / 2, h / 2, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(im, Rect2i(0, 0, w / 2, h / 2), Vector2i((i % 2) * (w / 2), (i / 2) * (h / 2)))
	return out


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	img.save_jpg(ProjectSettings.globalize_path(SHOT_DIR + name), 0.9)
	print("WL shot ", name)


func _shots(ids: Array) -> void:
	for id in ids:
		var root := _spawn(id)
		if root == null:
			continue
		var box := _aabb(root, 0)
		var views := []
		for v in [[0.0, 0.0], [180.0, 0.0], [35.0, 18.0], [-140.0, 18.0]]:
			_look_at_box(box, v[0], v[1])
			views.append(await _grab())
		_save(sheet(views), "weapon_%s_views.jpg" % id)
		_save(views[2], "weapon_%s_front34.jpg" % id)
		root.queue_free()
		# First person: the game's Viewmodel holding this weapon (held_scene), at the hip and aiming.
		var fps := []
		cam.position = Vector3.ZERO
		cam.rotation = Vector3.ZERO
		cam.fov = FPS_FOV
		var vm := Viewmodel.new()
		vm.held_scene = load(folder(id) + "weapon_" + id + ".glb")
		cam.add_child(vm)
		for aiming in [false, true]:
			vm.aiming = aiming
			for i in 30:
				await get_tree().process_frame
			fps.append(await _grab())
		vm.queue_free()
		await get_tree().process_frame
		# LOD1 / LOD2 at the distance the character switches to them (12 m / 28 m), seen through a long lens
		# so the frame is comparable.
		for lod in [1, 2]:
			var r2 := _spawn(id, lod)
			var c := _aabb(r2, lod).get_center()
			var d := 14.0 if lod == 1 else 30.0
			cam.fov = clampf(rad_to_deg(2.0 * atan(_aabb(r2, lod).size.length() * 0.6 / d)), 1.0, 60.0)
			cam.position = c + Vector3(-0.55, 0.25, -0.8).normalized() * d
			cam.look_at(c, Vector3.UP)
			fps.append(await _grab())
			r2.queue_free()
		_save(sheet(fps), "weapon_%s_fps_lods.jpg" % id)


func _showcase() -> void:
	# A wall rack: NATO on the left half, Russian on the right, four columns of four, each weapon upright with its left
	# side to the viewer (camera on -Z) and the muzzle to the viewer's left.
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 3.2, 0.04)
	wall.mesh = bm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.30, 0.29, 0.26)
	tm.roughness = 0.9
	wall.material_override = tm
	wall.position = Vector3(2.5, 1.2, 0.30)
	add_child(wall)
	var all: Array = NATO + RUS
	for i in all.size():
		var root := _spawn(all[i])
		if root == null:
			continue
		root.rotation_degrees = Vector3(0, -90, 0)
		var box := _aabb(root, 0)
		var col := i / 4
		var row := i % 4
		# the camera looks along +Z, so screen-left is +X: NATO columns at the high X end
		var slot := Vector3(5.0 - col * 1.55 - (0.35 if col >= 2 else 0.0), 2.25 - row * 0.62, 0.0)
		root.position = slot - box.get_center() + Vector3(0, 0, root.position.z)
		root.position.z = 0.30 - 0.02 - box.end.z
	await get_tree().process_frame
	var views := [[Vector3(2.5, 1.32, -4.9), Vector3(2.5, 1.32, 0.3), 45.0, "all"], [Vector3(4.22, 1.32, -3.0), Vector3(4.22, 1.32, 0.3), 45.0, "nato"],
			[Vector3(0.78, 1.32, -3.0), Vector3(0.78, 1.32, 0.3), 45.0, "russian"]]
	if stay_open:
		cam.fov = views[0][2]
		cam.position = views[0][0]
		cam.look_at(views[0][1], Vector3.UP)
		return
	for v in views:
		cam.fov = v[2]
		cam.position = v[0]
		cam.look_at(v[1], Vector3.UP)
		_save(await _grab(), "showcase_%s.jpg" % v[3])
