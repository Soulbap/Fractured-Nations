## Renders the imported construction assets in Godot (not Blender) for visual checks.
##
##   Godot.exe --path . --resolution 1400x900 --script res://tools/preview_structures.gd -- [--only=hesco,fence]
##
## Builds a small lit scene (sun, sky, dusty ground), shows every StructureCatalog type
## (lines as a few repeated modules with a corner), and saves views from several angles
## to assets/structures/previews/godot_<type>_<view>.jpg. Uses the same mesh loading
## (StructureCatalog.mesh_of) and MultiMesh path as the game.
extends SceneTree

var _root: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	_root = Node3D.new()
	root.add_child(_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.38, 0.52, 0.72)
	psm.sky_horizon_color = Color(0.72, 0.74, 0.76)
	psm.ground_horizon_color = Color(0.6, 0.58, 0.54)
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 170, 0)  # lights the assets' fronts (-Z)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	_root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.38, 0.3)
	gm.roughness = 1.0
	ground.material_override = gm
	_root.add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 55
	_root.add_child(_cam)
	_cam.make_current()
	var out_dir := ProjectSettings.globalize_path("res://assets/structures/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for def in StructureCatalog.all():
		if not only.is_empty() and not String(def.id) in only:
			continue
		var holder := Node3D.new()
		_root.add_child(holder)
		var mesh := StructureCatalog.mesh_of(def)
		var xforms: Array[Transform3D] = []
		if def.linear:
			var pts := PackedVector3Array([Vector3(-def.module_length * 4, 0, 0), Vector3(def.module_length * 2, 0, 0), Vector3(def.module_length * 2, 0, def.module_length * 3)])
			var mods := ModularLine.modules(def, pts)
			for i in mods.size():
				var b := Basis(Vector3.UP, ModularLine.yaw_of(mods[i].dir))
				if i % 2 == 1:
					b = b * Basis.from_scale(Vector3(1.0, 1.004, 1.004))
				xforms.append(Transform3D(b, Vector3(mods[i].center.x, -def.sink, mods[i].center.y)))
		else:
			xforms.append(Transform3D(Basis.IDENTITY, Vector3(0, -def.sink, 0)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		holder.add_child(mmi)
		var b := def.bounds()
		var r := maxf(maxf(b.size.x, b.size.z), def.size.y) * (3.2 if def.linear else 1.7) + 2.0
		var c := Vector3(0, def.size.y * 0.45, 0) if not def.linear else Vector3(-def.module_length, def.size.y * 0.5, def.module_length)
		# Azimuth 180 = in front of the asset (its front faces -Z).
		var views := {"front": [150.0, 14.0], "back": [-30.0, 22.0], "close": [125.0, 8.0], "top": [150.0, 70.0]}
		for v in views:
			var az := deg_to_rad(views[v][0])
			var el := deg_to_rad(views[v][1])
			var dist := r * (0.45 if v == "close" else 1.0)
			_cam.global_position = c + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist
			_cam.look_at(c, Vector3.UP)
			for f in 8:
				await process_frame
			var img := root.get_texture().get_image()
			img.save_jpg(out_dir.path_join("godot_%s_%s.jpg" % [def.id, v]), 0.88)
		var surf := []
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as BaseMaterial3D
			if m:
				surf.append("%s(tex=%s, vcol=%s, alpha=%d)" % [m.resource_name, m.albedo_texture != null, m.vertex_color_use_as_albedo, m.transparency])
		var tris := 0
		for i in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(i) / 3 if mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_INDEX == 0 else mesh.surface_get_array_index_len(i) / 3
		print("PREVIEW %s tris=%d surfaces=%s" % [def.id, tris, ", ".join(surf)])
		holder.queue_free()
		await process_frame
	quit()
