## Generates placeholder vegetation meshes, materials and textures for WORLD-TECH-01.
##
## These are stand-in assets so the vegetation pipeline (Terrain3D instancer, LODs,
## shadows, collision streaming) can be evaluated before real art exists. Replace the
## generated scenes in res://assets/vegetation/ with authored models later; the
## Terrain3D mesh assets reference the scenes by path, so swapping is non-destructive.
##
## Run headless:
##   Godot_console.exe --headless --path . --script res://tools/make_vegetation_assets.gd
extends SceneTree

const OUT_DIR := "res://assets/vegetation"
const TEX_DIR := "res://assets/terrain/textures"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var bark := _mat(Color(0.30, 0.22, 0.15), 0.95, "bark")
	var needles := _mat(Color(0.16, 0.27, 0.13), 0.9, "needles")
	var leaves := _mat(Color(0.25, 0.38, 0.16), 0.85, "leaves")
	var shrub := _mat(Color(0.24, 0.33, 0.15), 0.9, "shrub")
	var rock := _rock_material()

	_save_lod_scene("conifer", [
		_conifer(12, 5, 1.0), _conifer(7, 4, 1.0), _conifer(4, 2, 1.0)], bark, needles)
	_save_lod_scene("broadleaf", [
		_broadleaf(12, 6), _broadleaf(7, 4), _broadleaf(4, 3)], bark, leaves)
	_save_lod_scene("bush", [_bush(10, 5), _bush(5, 3)], null, shrub)
	_save_rock_scenes(rock)
	_make_grass_texture()
	_make_dirt_textures()
	print("Vegetation assets written to ", OUT_DIR)
	quit()


func _mat(color: Color, roughness: float, mat_name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = color
	m.roughness = roughness
	# Instance colors from the Terrain3D instancer tint each tree individually.
	m.vertex_color_use_as_albedo = true
	ResourceSaver.save(m, "%s/M_%s.tres" % [OUT_DIR, mat_name])
	return load("%s/M_%s.tres" % [OUT_DIR, mat_name])


func _rock_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "rock"
	m.albedo_texture = load(TEX_DIR + "/rock023_alb_ht.png")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = true
	ResourceSaver.save(m, OUT_DIR + "/M_rock.tres")
	return load(OUT_DIR + "/M_rock.tres")


## Returns [trunk_mesh, crown_mesh] pairs as ArrayMesh surfaces (surface 0 trunk, 1 crown).
func _conifer(segments: int, tiers: int, _scale: float) -> Array:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.28
	trunk.height = 4.0
	trunk.radial_segments = maxi(segments / 2, 4)
	trunk.rings = 1
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_y := 2.0
	for i in tiers:
		var t := float(i) / maxf(tiers - 1, 1)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = lerpf(2.6, 0.9, t)
		cone.height = lerpf(4.5, 3.0, t)
		cone.radial_segments = segments
		cone.rings = 1
		var y := base_y + i * (10.5 / tiers) + cone.height * 0.5
		crown.append_from(cone, 0, Transform3D(Basis(), Vector3(0, y, 0)))
	return [_to_surface(trunk, Transform3D(Basis(), Vector3(0, 2.0, 0))), crown.commit_to_arrays()]


func _broadleaf(segments: int, rings: int) -> Array:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.32
	trunk.height = 5.0
	trunk.radial_segments = maxi(segments / 2, 4)
	trunk.rings = 1
	var crown := SurfaceTool.new()
	crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs := [Vector4(0, 7.0, 0, 3.2), Vector4(1.6, 6.2, 0.8, 2.3),
			Vector4(-1.4, 6.4, -0.9, 2.4), Vector4(0.3, 8.6, -0.4, 2.2)]
	for b in blobs:
		var s := SphereMesh.new()
		s.radius = b.w
		s.height = b.w * 1.7
		s.radial_segments = segments
		s.rings = rings
		crown.append_from(s, 0, Transform3D(Basis(), Vector3(b.x, b.y, b.z)))
	return [_to_surface(trunk, Transform3D(Basis(), Vector3(0, 2.5, 0))), crown.commit_to_arrays()]


func _bush(segments: int, rings: int) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in [Vector4(0, 0.5, 0, 0.9), Vector4(0.7, 0.4, 0.3, 0.65), Vector4(-0.6, 0.45, -0.35, 0.7)]:
		var s := SphereMesh.new()
		s.radius = b.w
		s.height = b.w * 1.4
		s.radial_segments = segments
		s.rings = rings
		st.append_from(s, 0, Transform3D(Basis(), Vector3(b.x, b.y, b.z)))
	return [null, st.commit_to_arrays()]


func _to_surface(prim: PrimitiveMesh, xf: Transform3D) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(prim, 0, xf)
	return st.commit_to_arrays()


## Saves a scene whose MeshInstance3D children are named <name>_LOD0.._LODn, which is
## the naming convention Terrain3D uses to discover LODs in a mesh asset scene.
func _save_lod_scene(asset_name: String, lods: Array, trunk_mat: Material, crown_mat: Material) -> void:
	var root := Node3D.new()
	root.name = asset_name
	for i in lods.size():
		var mesh := ArrayMesh.new()
		var pair: Array = lods[i]
		if pair[0] != null:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pair[0])
			mesh.surface_set_material(mesh.get_surface_count() - 1, trunk_mat)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pair[1])
		mesh.surface_set_material(mesh.get_surface_count() - 1, crown_mat)
		var mi := MeshInstance3D.new()
		mi.name = "%s_LOD%d" % [asset_name, i]
		mi.mesh = mesh
		root.add_child(mi)
		mi.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	ResourceSaver.save(ps, "%s/%s.tscn" % [OUT_DIR, asset_name])
	root.free()


func _save_rock_scenes(rock_mat: Material) -> void:
	for n in ["RockA", "RockB", "RockC"]:
		var src: Node = load("res://assets/props/rocks/%s.glb" % n).instantiate()
		var meshes := src.find_children("*", "MeshInstance3D", true, false)
		var root := Node3D.new()
		root.name = n
		var mi := MeshInstance3D.new()
		mi.name = n + "_LOD0"
		mi.mesh = (meshes[0] as MeshInstance3D).mesh
		mi.material_override = rock_mat
		root.add_child(mi)
		mi.owner = root
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, "%s/%s.tscn" % [OUT_DIR, n.to_lower()])
		root.free()
		src.free()


## Grass card texture: tapered blades with alpha, used by a Terrain3D texture-card mesh asset.
func _make_grass_texture() -> void:
	var w := 256
	var img := Image.create_empty(w, w, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for b in 70:
		var x0 := rng.randf_range(8, w - 8)
		var lean := rng.randf_range(-40, 40)
		var h := rng.randf_range(0.45, 1.0) * w
		var base_w := rng.randf_range(3.0, 6.0)
		var c := Color.from_hsv(rng.randf_range(0.20, 0.27), rng.randf_range(0.45, 0.7), rng.randf_range(0.35, 0.6))
		for yi in int(h):
			var t := yi / h
			var cx := x0 + lean * t * t
			var half := base_w * (1.0 - t)
			for xi in range(int(cx - half), int(cx + half) + 1):
				if xi >= 0 and xi < w:
					img.set_pixel(xi, w - 1 - yi, c.lerp(Color(0.75, 0.8, 0.45), t * 0.4))
	img.generate_mipmaps()
	img.save_png(OUT_DIR + "/grass_blades.png")


## Dirt ground texture in Terrain3D's packed format (albedo+height, normal+roughness), 1024px
## to match the ambientCG textures so the texture array stays uniform.
func _make_dirt_textures() -> void:
	var size := 1024
	var fnl := FastNoiseLite.new()
	fnl.seed = 7
	fnl.frequency = 0.01
	fnl.fractal_octaves = 5
	var fine := FastNoiseLite.new()
	fine.seed = 11
	fine.frequency = 0.08
	var alb := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			# Seamless tiling: sample a torus in 4D-ish by blending wrapped coords.
			var n := _tile_noise(fnl, x, y, size) * 0.7 + _tile_noise(fine, x, y, size) * 0.3
			var h := clampf(n * 0.5 + 0.5, 0.0, 1.0)
			heights[y * size + x] = h
			var c := Color.from_hsv(0.08, 0.32, lerpf(0.32, 0.55, h))
			c.a = h
			alb.set_pixel(x, y, c)
	alb.save_png(TEX_DIR + "/dirt_proc_alb_ht.png")
	var nrm := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var hl := heights[y * size + (x - 1 + size) % size]
			var hr := heights[y * size + (x + 1) % size]
			var hu := heights[((y - 1 + size) % size) * size + x]
			var hd := heights[((y + 1) % size) * size + x]
			var n := Vector3((hl - hr) * 4.0, (hu - hd) * 4.0, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 0.92))
	nrm.save_png(TEX_DIR + "/dirt_proc_nrm_rgh.png")


func _tile_noise(n: FastNoiseLite, x: float, y: float, size: float) -> float:
	var u := x / size * TAU
	var v := y / size * TAU
	var r := size / TAU
	return n.get_noise_3d(cos(u) * r, sin(u) * r + cos(v) * r, sin(v) * r)
