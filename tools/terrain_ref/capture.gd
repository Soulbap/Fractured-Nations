## Screenshot tool for reference worlds (WORLD-TERRAIN-01). Needs a window (GUI binary).
##
##   Godot.exe --path . --script res://tools/terrain_ref/capture.gd -- \
##       --scene=res://scenes/world/ref_20km.tscn --out=res://docs/terrain01/shots \
##       [--topdown=4x2048] [--shots=res://tools/terrain_ref/shots_ref03.json] [--only=name,name]
##
## --topdown=NxPX renders the whole map as N x N orthographic tiles of PX pixels (camera
##   straight down, vegetation off, fog off, sun from the north-west like the reference)
##   and assembles topdown_full.png (N*PX square, north up).
## --shots renders perspective views {name, pos:[x,y,z] or ref_km:[x,y] + height, look...}
##   with the full scene (streamed vegetation, grass, water); "height" is metres above the
##   terrain at the camera position.
extends SceneTree

var _world: Node3D
var _terrain: Terrain3D
var _veg: VegetationStreamer
var _grass: Node
var _cam: Camera3D
var _env: Environment


func _init() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func _run() -> void:
	var o := _args()
	var scene: PackedScene = load(o.get("scene", "res://scenes/world/ref_20km.tscn"))
	_world = scene.instantiate()
	get_root().add_child(_world)
	_terrain = _world.get_node("Terrain3D")
	_veg = _world.get_node_or_null("Vegetation")
	_grass = _world.get_node_or_null("Grass")
	for n in ["Player", "WorldDiagnostics"]:
		var x := _world.get_node_or_null(n)
		if x:
			x.process_mode = Node.PROCESS_MODE_DISABLED
			if x is Node3D:
				x.visible = false
	var we: WorldEnvironment = _world.get_node_or_null("WorldEnvironment")
	_env = we.environment if we else null
	# The root viewport renders, so the vegetation streamer and the grass follow this
	# camera exactly as they follow the game cameras.
	_cam = Camera3D.new()
	_cam.far = 60000.0
	_world.add_child(_cam)
	_cam.current = true
	_terrain.set_camera(_cam)
	get_root().msaa_3d = Viewport.MSAA_4X
	var out_dir: String = o.get("out", "res://docs/terrain01/shots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	await _frames(10)
	if o.has("topdown"):
		var parts: PackedStringArray = String(o.topdown).split("x")
		await _topdown(out_dir, int(parts[0]), int(parts[1]), o.has("topdown-veg"))
	if o.has("shots"):
		var only: PackedStringArray = String(o.get("only", "")).split(",", false)
		await _shots(out_dir, o.shots, only)
	quit()


func _set_size(sz: Vector2i) -> void:
	DisplayServer.window_set_size(sz)
	get_root().size = sz
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _settle(max_frames := 400) -> void:
	await _frames(8)
	var k := 0
	while k < max_frames:
		if _veg == null or not _veg.is_inside_tree() or _veg.is_settled():
			break
		await process_frame
		k += 1
	await _frames(12)


func _topdown(out_dir: String, n: int, px: int, with_veg := false) -> void:
	var cfg: WorldConfig = _world.get_node("WorldBuilder").config
	var size := cfg.snapped_size()
	var hs := size * 0.5
	var tile := size / n
	await _set_size(Vector2i(px, px))
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = tile
	_cam.near = 10.0
	_cam.far = 8000.0
	var alt := 4000.0
	var saved_ranges := []
	if _veg and with_veg:
		# Far LODs (impostors with top cards, building boxes) over the whole tile: the
		# streamer measures 3D distance, so fly lower and extend the ranges temporarily.
		alt = 1600.0
		for d in _veg.library.meshes:
			saved_ranges.append([d, d.near_range, d.max_range])
			d.near_range = 0.0
			d.max_range = 1600.0 + tile * 0.75
		_veg.chunks.clear()
		_veg.refresh()
	elif _veg:
		_veg.process_mode = Node.PROCESS_MODE_DISABLED
		_veg.visible = false
	if _grass:
		_grass.process_mode = Node.PROCESS_MODE_DISABLED
		_grass.visible = false
	var fog := false
	if _env:
		fog = _env.fog_enabled
		_env.fog_enabled = false
	var sun: DirectionalLight3D = _world.get_node_or_null("Sun")
	var sun_xf := sun.transform if sun else Transform3D()
	if sun:
		# Light from the north-west, ~40 degrees up (the reference's illumination).
		sun.rotation_degrees = Vector3(-32, 135, 0)
		sun.directional_shadow_max_distance = 6000.0
	var mosaic := Image.create_empty(px * n, px * n, false, Image.FORMAT_RGB8)
	for ty in n:
		for tx in n:
			var cx := -hs + (tx + 0.5) * tile
			var cz := -hs + (ty + 0.5) * tile
			_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(cx, alt, cz))
			if _veg and with_veg:
				await _settle(2000)
			else:
				await _frames(30)
			var img := get_root().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			mosaic.blit_rect(img, Rect2i(0, 0, px, px), Vector2i(tx * px, ty * px))
			print("CAPTURE tile %d,%d" % [tx, ty])
	var tag := "topdown_veg" if with_veg else "topdown"
	mosaic.save_jpg(ProjectSettings.globalize_path(out_dir.path_join(tag + "_full.jpg")), 0.92)
	var small := mosaic.duplicate()
	small.resize(2048, 2048, Image.INTERPOLATE_LANCZOS)
	small.save_png(ProjectSettings.globalize_path(out_dir.path_join(tag + "_2048.png")))
	print("CAPTURE topdown %d px written" % (px * n))
	for r in saved_ranges:
		r[0].near_range = r[1]
		r[0].max_range = r[2]
	if _env:
		_env.fog_enabled = fog
	if sun:
		sun.transform = sun_xf
		sun.directional_shadow_max_distance = 350.0
	if _veg:
		_veg.process_mode = Node.PROCESS_MODE_INHERIT
		_veg.visible = true
	if _grass:
		_grass.process_mode = Node.PROCESS_MODE_INHERIT
		_grass.visible = true


func _ground(x: float, z: float) -> float:
	var h := _terrain.data.get_height(Vector3(x, 0, z))
	return 0.0 if is_nan(h) else h


func _shots(out_dir: String, path: String, only: PackedStringArray) -> void:
	var list = JSON.parse_string(FileAccess.get_file_as_string(path))
	await _set_size(Vector2i(1600, 900))
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.near = 0.1
	_cam.far = 12000.0
	for s in list:
		if only.size() > 0 and not only.has(s.name):
			continue
		var p := Vector3.ZERO
		if s.has("ref_km"):
			p = Vector3(s.ref_km[0] * 1000.0 - 10000.0, 0, 10000.0 - s.ref_km[1] * 1000.0)
		else:
			p = Vector3(s.pos[0], 0, s.pos[2])
		p.y = _ground(p.x, p.z) + float(s.get("height", 1.7))
		var look := p + Vector3(0, 0, -100)
		if s.has("look_km"):
			look = Vector3(s.look_km[0] * 1000.0 - 10000.0, 0, 10000.0 - s.look_km[1] * 1000.0)
			look.y = _ground(look.x, look.z) + float(s.get("look_up", 0.0))
		elif s.has("yaw_deg"):
			var yaw := deg_to_rad(float(s.yaw_deg))
			var pitch := deg_to_rad(float(s.get("pitch_deg", -5.0)))
			look = p + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * 100.0
		_cam.fov = float(s.get("fov", 70.0))
		_cam.global_transform = Transform3D(Basis.looking_at((look - p).normalized(), Vector3.UP), p)
		await _settle()
		var img := get_root().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var f := out_dir.path_join("%s.jpg" % s.name)
		img.save_jpg(ProjectSettings.globalize_path(f), 0.9)
		var st := _veg.get_stats() if _veg else {}
		print("CAPTURE shot %s at %s veg=%s fps_ms=%.2f" % [s.name, p, JSON.stringify(st), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
