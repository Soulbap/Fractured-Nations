## GPU cost attribution at a ground station: measures the viewport GPU render time with
## everything on, then with each vegetation mesh type (and the grass, water, structures)
## hidden in turn. Diagnostic only.
##   Godot.exe --path . --resolution 1600x900 --script res://tools/terrain_ref/probe_perf.gd -- [--scene=...] [--at=x,z]
extends SceneTree

var world: Node3D
var veg: VegetationStreamer
var cam: Camera3D
var vp_rid: RID


func _init() -> void:
	_run.call_deferred()


func _gpu_ms(frames := 90) -> float:
	for i in 20:
		await process_frame
	var acc := 0.0
	for i in frames:
		await process_frame
		acc += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	return acc / frames


func _set_mesh_visible(id: int, on: bool) -> void:
	for key in veg.active:
		if key.z == id:
			veg.active[key].visible = on


func _run() -> void:
	var scene_path := "res://scenes/world/ref_20km.tscn"
	var at := Vector2.INF
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--at="):
			var p := a.substr(5).split(",")
			at = Vector2(float(p[0]), float(p[1]))
	world = load(scene_path).instantiate()
	get_root().add_child(world)
	var terrain: Terrain3D = world.get_node("Terrain3D")
	veg = world.get_node("Vegetation")
	var grass: Node3D = world.get_node_or_null("Grass")
	var cfg: WorldConfig = world.get_node("WorldBuilder").config
	for n in ["Player", "WorldDiagnostics"]:
		var x := world.get_node_or_null(n)
		if x:
			x.process_mode = Node.PROCESS_MODE_DISABLED
	cam = Camera3D.new()
	cam.far = 12000.0
	world.add_child(cam)
	cam.current = true
	terrain.set_camera(cam)
	vp_rid = get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	if at == Vector2.INF:
		var w := cfg.main_road[4] * cfg.half_size()
		at = w
	var h: float = terrain.data.get_height(Vector3(at.x, 0, at.y))
	var pos := Vector3(at.x, h + 1.8, at.y)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(60, 0.5 - 1.8, 8).normalized(), Vector3.UP), pos)
	for i in 400:
		await process_frame
		if veg.is_settled() and i > 60:
			break
	var base := await _gpu_ms()
	print("PROBE all on: %.2f ms gpu, %s" % [base, JSON.stringify(veg.get_stats())])
	var ids: Array = veg.library.ids()
	for id in ids:
		_set_mesh_visible(id, false)
		var t := await _gpu_ms(60)
		_set_mesh_visible(id, true)
		var d: VegetationMeshDef = veg.library.get_def(id)
		var n := 0
		for key in veg.active:
			if key.z == id:
				n += 1
		print("PROBE hide %-12s (%3d MMIs): %.2f ms  (saves %.2f)" % [d.name, n, t, base - t])
	for node_name in ["Grass", "Water", "Structures", "Roads"]:
		var nd: Node3D = world.get_node_or_null(node_name)
		if nd:
			nd.visible = false
			var t := await _gpu_ms(60)
			nd.visible = true
			print("PROBE hide %-12s: %.2f ms  (saves %.2f)" % [node_name, t, base - t])
	veg.visible = false
	for key in veg.active:
		veg.active[key].visible = false
	var t2 := await _gpu_ms(60)
	print("PROBE all vegetation hidden: %.2f ms" % t2)
	var sun: DirectionalLight3D = world.get_node_or_null("Sun")
	veg.visible = true
	for key in veg.active:
		veg.active[key].visible = true
	if sun:
		sun.shadow_enabled = false
		print("PROBE sun shadows off: %.2f ms" % await _gpu_ms(60))
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		print("PROBE 2 splits: %.2f ms" % await _gpu_ms(60))
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		print("PROBE 2 splits + 2048 atlas: %.2f ms" % await _gpu_ms(60))
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		print("PROBE 4 splits + 2048 atlas: %.2f ms" % await _gpu_ms(60))
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
		sun.directional_shadow_max_distance = 150.0
		print("PROBE 4 splits 4096, max 150 m: %.2f ms" % await _gpu_ms(60))
		sun.directional_shadow_max_distance = 350.0
	# Near-LOD range: switch all tree types to the impostor beyond 40 m.
	for d in veg.library.meshes:
		if d.id <= 6:
			d.near_range = 40.0
	veg.refresh()
	for i in 120:
		await process_frame
	print("PROBE trees near_range 40: %.2f ms, %s" % [await _gpu_ms(60), JSON.stringify(veg.get_stats())])
	quit()
