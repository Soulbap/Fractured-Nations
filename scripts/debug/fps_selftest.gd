## Scripted in-engine checks of the FPS controller against real Terrain3D and Jolt
## collision. Run with:  Godot.exe --path . <world scene> -- --fps-test
## Drives the controller through its move intent (no simulated keyboard) and prints
## a JSON report. Thresholds are deliberately loose; the report records the raw values.
class_name FPSSelfTest
extends RefCounted

var tree: SceneTree
var player: FPSController
var terrain: Terrain3D
var streamer: InstanceColliderStreamer
var results := {}


func _init(p_player: FPSController, p_terrain: Terrain3D, p_streamer: InstanceColliderStreamer) -> void:
	player = p_player
	terrain = p_terrain
	streamer = p_streamer
	tree = player.get_tree()


func run(spawn: Vector3) -> Dictionary:
	player.player_controlled = false
	player.set_flying(false)

	# 1. Landing and ground contact at spawn.
	await _place(spawn + Vector3.UP * 3.0)
	await _frames(90)
	var ground := _h(player.global_position)
	results.landing = {"on_floor": player.is_on_floor(), "feet_minus_terrain_m": player.global_position.y - ground}

	# 2. Walk and sprint speeds on the road.
	results.walk = await _move_for(Vector2(0, 1), false, 2.0)
	results.sprint = await _move_for(Vector2(0, 1), true, 2.0)

	# 3. Jump apex.
	await _frames(20)
	var y0 := player.global_position.y
	var apex := y0
	player.jump_intent = true
	for i in 90:
		await tree.physics_frame
		apex = maxf(apex, player.global_position.y)
	results.jump = {"apex_height_m": apex - y0, "landed": player.is_on_floor()}

	# 4. Slopes: climb a moderate slope, fail on a steep one.
	var moderate = _find_slope(15.0, 30.0)
	var steep = _find_slope(50.0, 75.0)
	if moderate:
		results.moderate_slope = await _climb(moderate)
	if steep:
		results.steep_slope = await _climb(steep)

	# 5. Collision with an instanced tree via the collider streamer.
	results.tree_collision = await _walk_into_tree()

	# 6. Far from origin (map corner) — same walk test, checks precision/jitter.
	var hs := terrain.region_size * terrain.vertex_spacing * sqrt(float(terrain.data.get_region_count())) * 0.5
	var corner := Vector3(hs - 40.0, 0, hs - 40.0)
	corner.y = _h(corner) + 2.0
	await _place(corner)
	await _frames(60)
	results.far_corner = await _move_for(Vector2(0, 1), false, 2.0)
	results.far_corner.position = player.global_position
	return results


func _h(p: Vector3) -> float:
	var h: float = terrain.data.get_height(p)
	return 0.0 if is_nan(h) else h


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _place(p: Vector3, yaw := 0.0) -> void:
	player.teleport(p, yaw)
	# Let Terrain3D dynamic collision and the instance colliders catch up.
	await _frames(10)


func _move_for(intent: Vector2, sprint: bool, seconds: float) -> Dictionary:
	var start := player.global_position
	var frames := int(seconds * Engine.physics_ticks_per_second)
	var floor_frames := 0
	player.sprint_intent = sprint
	player.move_intent = intent
	for i in frames:
		await tree.physics_frame
		if player.is_on_floor():
			floor_frames += 1
	player.move_intent = Vector2.ZERO
	player.sprint_intent = false
	var d := player.global_position - start
	return {"horizontal_speed_mps": Vector2(d.x, d.z).length() / seconds,
		"vertical_change_m": d.y, "on_floor_ratio": float(floor_frames) / frames}


## Finds a point whose slope (degrees) is in range, plus the uphill direction.
func _find_slope(min_deg: float, max_deg: float):
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var hs := terrain.region_size * terrain.vertex_spacing * 0.9
	for i in 20000:
		var p := Vector3(rng.randf_range(-hs, hs), 0, rng.randf_range(-hs, hs))
		var n: Vector3 = terrain.data.get_normal(p)
		if not n.is_finite():
			continue
		var deg := rad_to_deg(acos(clampf(n.y, -1, 1)))
		if deg < min_deg or deg > max_deg:
			continue
		# Require a consistent slope a few meters uphill so the test is meaningful.
		var up := -Vector3(n.x, 0, n.z).normalized()
		var n2: Vector3 = terrain.data.get_normal(p + up * 3.0)
		if not n2.is_finite() or rad_to_deg(acos(clampf(n2.y, -1, 1))) < min_deg:
			continue
		p.y = _h(p)
		return {"pos": p, "uphill": up, "slope_deg": deg}
	return null


func _climb(s: Dictionary) -> Dictionary:
	var up: Vector3 = s.uphill
	var start: Vector3 = s.pos - up * 1.0
	start.y = _h(start) + 0.2
	await _place(start, atan2(-up.x, -up.z))
	await _frames(20)
	var r := await _move_for(Vector2(0, 1), false, 2.0)
	r.slope_deg = s.slope_deg
	r.max_walkable_deg = player.max_slope_deg
	return r


func _walk_into_tree() -> Dictionary:
	# Find a conifer/broadleaf instance near the spawn region using the streamer index.
	var target := Vector3.INF
	var best := INF
	streamer._index_near(player.global_position)
	var origin := player.global_position
	var trees: Array[Vector3] = []
	for key in streamer._buckets:
		for entry in streamer._buckets[key]:
			if entry[0] == 1 or entry[0] == 2:
				trees.append((entry[1] as Transform3D).origin)
	# Nearest tree on gentle ground whose 6 m approach from the west is clear.
	for t in trees:
		var d := t.distance_to(origin)
		if d >= best:
			continue
		var start_xz := t - Vector3(6, 0, 0)
		if terrain.data.get_normal(t).y < 0.97 or terrain.data.get_normal(start_xz).y < 0.97:
			continue
		var clear := true
		for o in trees:
			if o != t and o.x > t.x - 7.0 and o.x < t.x and absf(o.z - t.z) < 1.5:
				clear = false
				break
		if clear:
			best = d
			target = t
	if target == Vector3.INF:
		return {"skipped": "no tree instances indexed"}
	# Approach from 6 m away along a clear line (check nothing else is closer).
	var dir := Vector3(1, 0, 0)
	var start := target - dir * 6.0
	start.y = _h(start) + 0.3
	await _place(start, atan2(-dir.x, -dir.z))
	streamer._last_center = Vector3.INF
	await _frames(15)
	var nearest_shape := INF
	var shape_info := ""
	for cs in streamer._pool:
		if cs.disabled:
			continue
		var d := Vector2(cs.global_position.x - target.x, cs.global_position.z - target.z).length()
		if d < nearest_shape:
			nearest_shape = d
			shape_info = "%s at %s" % [cs.shape, cs.global_position]
	# Walk at the trunk for 3 s and track the closest approach: blocked means the body
	# came close (< 1.5 m, trunk + body radius) but never entered the trunk (> 0.3 m).
	# On slopes the body may slide around the trunk and continue; that still counts.
	var min_dist := INF
	player.move_intent = Vector2(0, 1)
	for i in int(3.0 * Engine.physics_ticks_per_second):
		await tree.physics_frame
		var q := player.global_position
		min_dist = minf(min_dist, Vector2(q.x - target.x, q.z - target.z).length())
	player.move_intent = Vector2.ZERO
	var p := player.global_position
	var dist := Vector2(p.x - target.x, p.z - target.z).length()
	return {"tree_at": target, "final_center_distance_m": dist, "closest_approach_m": min_dist,
		"blocked": min_dist > 0.3 and min_dist < 1.5,
		"active_colliders": streamer.active_count, "nearest_collider_to_tree_m": nearest_shape,
		"collider": shape_info, "start": start}
