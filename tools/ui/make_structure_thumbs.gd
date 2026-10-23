## UI-01C: renders a thumbnail of every StructureCatalog type from its real mesh (the same GLB the game
## places) for the construction menu's building cards. Surfaces (roads, paved areas) have no mesh and
## keep the category icon.
##
##   Godot_v4.7.2-stable_win64.exe --path . --script res://tools/ui/make_structure_thumbs.gd
##
## Needs a rendering device (not --headless). Writes assets/ui/thumbs/<id>.png (THUMB px, transparent
## background, three-quarter view from the front-right, lit by a fixed key / fill light) and prints one
## line per type. Re-run after adding or changing building assets; the cards fall back to the
## category icon when a thumbnail is missing.
extends SceneTree

const THUMB := Vector2i(192, 144)
const OUT := "res://assets/ui/thumbs"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := SubViewport.new()
	vp.size = THUMB
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.70)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-48, 32, 0)
	key.shadow_enabled = true
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, -140, 0)
	vp.add_child(fill)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	var mi := MeshInstance3D.new()
	vp.add_child(mi)
	var done := 0
	for def: StructureDef in StructureCatalog.all():
		if def.is_surface():
			continue
		var mesh := StructureCatalog.mesh_of(def)
		if mesh == null:
			continue
		mi.mesh = mesh
		# Frame the mesh: a three-quarter view from the front-right, distance from the bounding sphere.
		var b := mesh.get_aabb()
		var c := b.get_center()
		var r := maxf(b.size.length() * 0.5, 0.5)
		var dir := Vector3(0.62, 0.52, 0.80).normalized()
		var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 0.70
		cam.look_at_from_position(c + dir * dist, c, Vector3.UP)
		cam.near = maxf(dist - r * 2.0, 0.05)
		cam.far = dist + r * 2.0
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := "%s/%s.png" % [OUT, def.id]
		img.save_png(ProjectSettings.globalize_path(path))
		done += 1
		print("THUMB %s %s" % [def.id, path])
	print("THUMB done %d" % done)
	quit()
