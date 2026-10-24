## Performance overlay plus scripted benchmark / screenshot capture.
##
## F3 toggles the overlay. Command-line modes (pass after "--"):
##   --benchmark          fly a fixed route and write res://benchmarks/raw/<world>_<time>.json
##   --screenshots        capture named viewpoints to res://docs/screenshots/<world>_<name>.png
##   --quit-after-load    record load time and memory, then quit
##   --fps-test           scripted controller checks (see FPSSelfTest)
## Nothing here is gameplay code; it exists to produce real measurements from Godot.
class_name WorldDiagnostics
extends CanvasLayer

@export var terrain: Terrain3D
@export var player: FPSController
@export var collider_streamer: InstanceColliderStreamer
@export var config: WorldConfig

## Screenshot viewpoints: [name, from (normalized xz), height above ground,
## look-at (normalized xz), look-at height above ground].
var viewpoints: Array = [
	["overview", Vector2(-0.98, 0.98), 420.0, Vector2(0.15, -0.15), 0.0],
	["valley_road", Vector2(-0.30, 0.05), 25.0, Vector2(0.10, 0.12), 0.0],
	["intersection", Vector2(0.02, 0.18), 18.0, Vector2(0.05, 0.10), 0.0],
	["forest_edge", Vector2(-0.52, -0.25), 2.0, Vector2(-0.50, -0.45), 6.0],
	["base_site_fields", Vector2(-0.42, 0.40), 60.0, Vector2(-0.52, 0.58), 0.0],
	["mountains", Vector2(0.20, -0.05), 20.0, Vector2(0.60, -0.55), 80.0],
	["fps_ground", Vector2(-0.40, 0.21), 1.7, Vector2(-0.20, 0.20), 1.0],
]

var _label: Label
var _frames := PackedFloat32Array()
var _samples: Array = []
var _first_frame_msec := -1


func _ready() -> void:
	layer = 50
	_label = Label.new()
	_label.position = Vector2(12, 10)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	var args := OS.get_cmdline_user_args()
	if "--benchmark" in args or "--screenshots" in args or "--quit-after-load" in args or "--fps-test" in args:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_label.visible = "--benchmark" in args
		_run_automation.call_deferred(args)


## WORLD-SANDBOX-01B: the war starts with the overlay hidden (F3 shows it).
func set_overlay_visible(v: bool) -> void:
	_label.visible = v


## Lowest screen y of the overlay text (0 when hidden), so the HUD can stay clear of it.
func overlay_bottom() -> float:
	return _label.get_rect().end.y if _label.visible else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F3:
		_label.visible = not _label.visible


func _process(delta: float) -> void:
	if _first_frame_msec < 0:
		_first_frame_msec = Time.get_ticks_msec()
	_frames.append(delta)
	if _label.visible and Engine.get_process_frames() % 10 == 0:
		_label.text = _overlay_text()


func _overlay_text() -> String:
	var p := player.global_position if player else Vector3.ZERO
	return "FPS %d  (%.2f ms)\nDraw calls %d  Primitives %.2fM\nVRAM %.0f MB  Tex %.0f MB  RAM %.0f MB\nPos %.0f, %.0f, %.0f  %s\nInstance colliders %d  Cells indexed %d\nWASD move, Shift sprint, Space jump, F fly, F3 overlay" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		p.x, p.y, p.z, "FLY" if player and player.flying else "WALK",
		collider_streamer.active_count if collider_streamer else 0,
		collider_streamer.indexed_regions if collider_streamer else 0]


func _snapshot() -> Dictionary:
	return {
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"texture_mem_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"buffer_mem_mb": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		"static_mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"physics_process_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	}


func _run_automation(args: PackedStringArray) -> void:
	var spawn := player.global_position
	player.player_controlled = false
	player.set_flying(true)
	for i in 10:
		await get_tree().process_frame
	var load_info := {"first_frame_msec_since_start": _first_frame_msec, "after_10_frames": _snapshot()}
	print("DIAG load: ", JSON.stringify(load_info))
	if "--fps-test" in args:
		var report := await FPSSelfTest.new(player, terrain, collider_streamer).run(spawn)
		print("DIAG fps-test: ", JSON.stringify(report))
		player.set_flying(true)
	if "--screenshots" in args:
		await _capture_screenshots()
	if "--benchmark" in args:
		await _benchmark(load_info)
	get_tree().quit()


func _ground(n: Vector2) -> Vector3:
	var p := n * config.half_size()
	var h: float = terrain.data.get_height(Vector3(p.x, 0, p.y))
	return Vector3(p.x, 0.0 if is_nan(h) else h, p.y)


func _place_camera(from: Vector3, to: Vector3) -> void:
	player.teleport(from - Vector3.UP * player.head.position.y)
	var d := (to - from).normalized()
	player.rotation.y = atan2(-d.x, -d.z)
	player.head.rotation.x = asin(clampf(d.y, -1.0, 1.0))


func _capture_screenshots() -> void:
	var dir := "res://docs/screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for vp in viewpoints:
		var from: Vector3 = _ground(vp[1]) + Vector3.UP * float(vp[2])
		var to: Vector3 = _ground(vp[3]) + Vector3.UP * float(vp[4])
		_place_camera(from, to)
		# Let terrain LOD, instancer and dynamic collision settle.
		for i in 45:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_%s.png" % [dir, config.world_name, vp[0]]
		img.save_png(ProjectSettings.globalize_path(path))
		print("DIAG screenshot: ", path, " draw_calls=", _snapshot().draw_calls)


## Flies two routes: low (2 m above ground along the main road, worst case for
## vegetation and terrain detail) and high (250 m overview sweep).
func _benchmark(load_info: Dictionary) -> void:
	var results := {
		"world": config.world_name,
		"world_size_m": config.snapped_size(),
		"vertex_spacing": config.vertex_spacing,
		"regions": terrain.data.get_region_count(),
		"godot": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_driver_name() + " / " + RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_driver": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(),
		"window_size": DisplayServer.window_get_size(),
		"render_size": get_viewport().get_texture().get_size(),
		"load": load_info,
		"phases": [],
	}
	var road: Array[Vector3] = []
	for n in config.main_road:
		road.append(_ground(n) + Vector3.UP * 2.0)
	var high: Array[Vector3] = []
	for n in [Vector2(-0.9, 0.9), Vector2(0.9, 0.9), Vector2(0.9, -0.9), Vector2(-0.9, -0.9), Vector2(-0.9, 0.85)]:
		var g := _ground(n)
		high.append(Vector3(g.x, 250.0 + config.base_height, g.z))
	results.phases.append(await _fly_route("low_road", road, 40.0, 1500.0))
	results.phases.append(await _fly_route("high_overview", high, config.snapped_size() / 16.0, INF))
	var dir := "res://benchmarks/raw"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/%s_%s.json" % [dir, config.world_name, Time.get_datetime_string_from_system().replace(":", "-")]
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("DIAG benchmark: ", path)
	print("DIAG result: ", JSON.stringify(results))


func _fly_route(phase_name: String, pts: Array[Vector3], speed: float, max_dist: float) -> Dictionary:
	var frame_ms := PackedFloat32Array()
	var total := 0.0
	var peak := {"draw_calls": 0.0, "primitives": 0.0, "video_mem_mb": 0.0}
	var t0 := Time.get_ticks_msec()
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dist := a.distance_to(b)
		var travelled := 0.0
		while travelled < dist and total < max_dist:
			var dt := get_process_delta_time()
			travelled += speed * dt
			total += speed * dt
			var p := a.lerp(b, clampf(travelled / dist, 0.0, 1.0))
			if phase_name == "low_road":
				var h: float = terrain.data.get_height(p)
				if not is_nan(h):
					p.y = h + 2.0
			_place_camera(p, p + (b - a).normalized() * 50.0 + Vector3.DOWN * (0.0 if phase_name == "low_road" else 60.0))
			await get_tree().process_frame
			frame_ms.append(get_process_delta_time() * 1000.0)
			var s := _snapshot()
			for k in peak:
				peak[k] = maxf(peak[k], s[k])
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var sum := 0.0
	for v in frame_ms:
		sum += v
	var n := sorted.size()
	return {
		"phase": phase_name,
		"speed_mps": speed,
		"distance_m": minf(total, max_dist),
		"duration_s": (Time.get_ticks_msec() - t0) / 1000.0,
		"frames": n,
		"avg_fps": 1000.0 / (sum / n),
		"frame_ms_avg": sum / n,
		"frame_ms_p50": sorted[n / 2],
		"frame_ms_p95": sorted[int(n * 0.95)],
		"frame_ms_p99": sorted[int(n * 0.99)],
		"frame_ms_max": sorted[n - 1],
		"peak": peak,
		"end": _snapshot(),
	}
