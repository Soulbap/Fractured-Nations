## Renders the environment assets in Godot (game shaders, sun, sky, glow) for inspection:
## one image per asset (LOD0 and LOD1 side by side) plus a combined line-up.
##   Godot.exe --path . --script res://tools/terrain_ref/asset_lineup.gd -- [--only=pine_a,boulder_a] [--out=res://docs/terrain01/godot_assets]
extends SceneTree

const SCENES := "res://assets/environment/scenes/"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := []
	var out := "res://docs/terrain01/godot_assets"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_size(Vector2i(1200, 800))
	get_root().size = Vector2i(1200, 800)
	var world := Node3D.new()
	get_root().add_child(world)
	# Same environment settings as the world scenes (tools/build_world.gd).
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.47, 0.70)
	sky_mat.sky_horizon_color = Color(0.68, 0.74, 0.80)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.70)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.34, 0.20)
	ground.material_override = gm
	world.add_child(ground)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	for f in DirAccess.get_files_at(SCENES):
		if not f.ends_with(".tscn"):
			continue
		var asset := f.get_basename()
		if only.size() > 0 and not only.has(asset):
			continue
		var inst: Node3D = load(SCENES + f).instantiate()
		world.add_child(inst)
		var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
		var aabb := AABB()
		for i in meshes.size():
			var mi: MeshInstance3D = meshes[i]
			var ab: AABB = mi.mesh.get_aabb()
			aabb = ab if i == 0 else aabb.merge(ab)
		var w := maxf(aabb.size.x, aabb.size.z)
		var spacing := w * 1.3 + 0.5
		for i in meshes.size():
			meshes[i].position.x = (i - (meshes.size() - 1) * 0.5) * spacing
		var extent := maxf(aabb.size.y, spacing * meshes.size())
		var target := Vector3(0, aabb.position.y + aabb.size.y * 0.45, 0)
		cam.fov = 40.0
		cam.global_transform = Transform3D(Basis.IDENTITY, target + Vector3(0.25, 0.18, 1.0).normalized() * extent * 1.6)
		cam.look_at(target)
		for k in 20:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(ProjectSettings.globalize_path(out.path_join(asset + ".jpg")), 0.9)
		# Count blown-out pixels (NaN/overflow shows as pure white through the glow).
		var hot := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c := img.get_pixel(x, y)
				if c.r > 0.98 and c.g > 0.98 and c.b > 0.98:
					hot += 1
		print("LINEUP %s hot_pixels=%d" % [asset, hot])
		inst.free()
	quit()
