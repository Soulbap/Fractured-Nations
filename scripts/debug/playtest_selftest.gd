## Scripted checks of WORLD-PLAYTEST-01 on ref_20km (the problems found in the first manual
## playtest): navigation across the river and around obstacles, player-built roads and
## areas, the strategic map camera indicator and middle mouse, RTS tilt, time compression.
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --playtest-test [--shots] [--only a,b]
##
## Checks: nav_river, nav_long, nav_base, roads, camera, timescale. Prints
## "PLAYTEST <check> <json>", writes res://benchmarks/raw/playtest_test.json and (with
## --shots) docs/playtest01/pt01_*.jpg. Every scenario fails when its precondition is
## missing (no river between start and goal, no road to snap to ...).
class_name PlaytestSelfTest
extends SandboxSelfTest


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/playtest01"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	brain = demo.sim.brain
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_pause_ai(true)
	_log("setup", {"roads_world": demo.sim.state.roads.world.size(), "road_km": snappedf(demo.sim.state.roads.total_length_m() / 1000.0, 0.1),
		"grid_cached": ws.routes.loaded_from_cache, "grid_ms": snappedf(ws.routes.build_ms, 0.1)})
	if _want("camera"):
		_log("camera", await _camera())
	if _want("roads"):
		_log("roads", await _roads())
	if _want("nav_river"):
		_log("nav_river", await _nav_river())
	if _want("nav_long"):
		_log("nav_long", await _nav_long())
	if _want("nav_base"):
		_log("nav_base", await _nav_base())
	if _want("timescale"):
		_log("timescale", await _timescale())
	TimeCompression.reset()
	# A structure / road change schedules a navmesh rebake a moment later (debounced); a
	# bake still running on a worker thread when the engine quits crashes it. Let every
	# scheduled bake start and finish first.
	await _seconds(1.5)
	while demo.navigation.has_pending_bake() or demo.detail._rebake_in >= 0.0:
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


func _want(n: String) -> bool:
	return only.is_empty() or only.has(n)


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("PLAYTEST %s %s" % [check, JSON.stringify(data)])


func _shot(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/pt01_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("PLAYTEST shot: ", path)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/playtest_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("PLAYTEST %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.shutdown_cleanup()
	tree.quit()


func _hq() -> Vector3:
	return war.objective(war.faction(0).hq_objective).position


# --- Navigation -----------------------------------------------------------------------

## Watches a squad walking to `goal` (an RTS move order, like a right click) and records
## water, impassable cells, arrival and the longest time a soldier made no progress.
func _walk(sq: SquadState, goal: Vector3, sim_s: float, scale: float, arrive_m := 25.0) -> Dictionary:
	var rts := demo.rts
	rts.select_squads([sq.id])
	var ordered := rts.order_move(goal)
	var track := {"wet": 0, "wet_at": [], "shallow_max_m": 0.0, "water_cell": 0, "bad": 0, "n": 0, "stall_max_s": 0.0}
	var last := {}
	var t_last := {}
	var w := await _warp(sim_s, scale, 200.0, func() -> bool:
		var now := demo.sim.state.time
		var done := true
		for id in sq.members:
			var u := _u(id)
			if u == null or not u.alive:
				continue
			track.n += 1
			# Wading: the water surface more than 0.5 m above the soldier's feet (a soldier on
			# a bridge deck stands in a grid cell marked as river, but above the water; the
			# water ribbon reaches 3 m over the banks, ankle-deep at its edge).
			var depth := sm.water_height(u.position.x, u.position.z) - u.position.y
			if depth > 0.05:
				track.shallow_max_m = maxf(track.shallow_max_m, snappedf(depth, 0.01))
			if depth > 0.5:
				track.wet += 1
				if track.wet_at.size() < 6 and (track.wet_at.is_empty() or _flat(track.wet_at[-1][0], u.position) > 20.0):
					var nb := INF
					for bp in ws.routes.bridges:
						nb = minf(nb, _flat(bp, u.position))
					track.wet_at.append([u.position, snappedf(nb, 1.0), "body" if u.has_body else "abstract",
						snappedf(sm.water_height(u.position.x, u.position.z) - u.position.y, 0.01)])
			elif ws.routes.is_water(u.position):
				track.water_cell += 1
			elif not ws.routes.passable(u.position):
				track.bad += 1
			var prev: Vector3 = last.get(id, Vector3.INF)
			if not prev.is_finite() or _flat(prev, u.position) > 1.0:
				last[id] = u.position
				t_last[id] = now
			elif u.has_order():
				track.stall_max_s = maxf(track.stall_max_s, now - t_last[id])
			if _flat(u.position, goal) > arrive_m:
				done = false
		return done)
	var dists := []
	for id in sq.members:
		dists.append(snappedf(_flat(_u(id).position, goal), 0.1))
	dists.sort()
	var arrived := 0
	for d: float in dists:
		if d <= arrive_m:
			arrived += 1
	track.stall_max_s = snappedf(track.stall_max_s, 0.1)
	return {"ordered": ordered, "arrived": arrived, "of": sq.members.size(), "dist_m": dists, "warp": w, "track": track,
		"route_waypoints": sq.route.size(), "route_skips": demo.sim.squads.route_skips}


## Point on the river centre line closest to z, and the river half width there.
func _river_at(z: float) -> Dictionary:
	var w = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s/source/water.json" % demo.config.world_name))
	var best := {}
	var bd := INF
	for k in w.river.points.size():
		var p: Array = w.river.points[k]
		if absf(p[1] - z) < bd:
			bd = absf(p[1] - z)
			best = {"x": float(p[0]), "z": float(p[1]), "half": float(w.river.width[k]) * 0.5}
	return best


## A move order straight across the river, far from any bridge: the squad must use a
## bridge (or report it cannot get there), never wade through the water. Camera close
## (bodies on the navmesh) and far (abstract tier).
func _nav_river() -> Dictionary:
	var out := {}
	for tier in ["bodies", "abstract"]:
		# The middle of the river, between Fv sentrum-øst (z ~ -1170) and Rv1 (z ~ 4530).
		var z := 1500.0 if tier == "bodies" else 2600.0
		var r := _river_at(z)
		var west := demo.on_ground(r.x - r.half - 140.0, z, 0.0)
		var east := demo.on_ground(r.x + r.half + 140.0, z, 0.0)
		var near_bridge := INF
		for b in ws.routes.bridges:
			near_bridge = minf(near_bridge, _flat(b, Vector3(r.x, 0, z)))
		_expect(ws.routes.is_water(Vector3(r.x, 0, z)) and near_bridge > 1500.0, "nav_river precondition: river at x=%.0f, nearest bridge %.0f m" % [r.x, near_bridge])
		var sq := _spawn(0, west, 6)
		if tier == "bodies":
			demo.rts_camera.frame(west, PI * 0.5, 120.0)
		else:
			demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
		await _seconds(1.0)
		var res := await _walk(sq, east, 2400.0, 16.0)
		res["bridge_dist_m"] = snappedf(near_bridge, 1.0)
		out[tier] = res
		_expect(res.track.wet == 0, "nav_river %s: soldiers waded through the river (%d samples)" % [tier, res.track.wet])
		_expect(res.arrived == res.of, "nav_river %s: %d of %d arrived on the far bank" % [tier, res.arrived, res.of])
		await _shot("nav_river_%s" % tier)
		await _despawn(sq)
	return out


## A 2.5 km move order over hills and forest in the abstract tier: no water, no cliffs,
## arrives.
func _nav_long() -> Dictionary:
	var a := _hq() + Vector3(60, 0, 60)
	var goal := demo.on_ground(a.x - 1800.0, a.z + 1700.0, 0.0)
	var c := ws.routes.nearest_passable(goal)
	goal = demo.on_ground(ws.routes.cell_center(c).x, ws.routes.cell_center(c).z, 0.0)
	var sq := _spawn(0, demo.on_ground(a.x, a.z, 0.0), 6)
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(1.0)
	var res := await _walk(sq, goal, 3600.0, 16.0)
	res["straight_km"] = snappedf(_flat(a, goal) / 1000.0, 0.01)
	_expect(res.track.wet == 0 and res.arrived == res.of, "nav_long: %s" % JSON.stringify(res))
	await _despawn(sq)
	return res


## Local obstacles: a HESCO wall with a gap between the squad and its goal. Camera close
## (bodies, navmesh with the wall carved out) and far (abstract tier, which slides along
## structures). The squad must get round through the gap. Arrival allows for the width of
## the squad's line formation around the goal.
func _nav_base() -> Dictionary:
	var out := {}
	var c := _hq() + Vector3(-120, 0, 140)
	c = demo.on_ground(c.x, c.z, 0.0)
	var def := StructureCatalog.get_def(&"hesco_tall")
	# A 60 m wall across the way, the gap at its east end.
	var pts := PackedVector3Array([demo.on_ground(c.x - 40.0, c.z, 0.0), demo.on_ground(c.x + 20.0, c.z, 0.0)])
	var chk := sm.check_line(def, pts, -1, true)
	var removed := PackedInt32Array()
	for i in chk.modules.size():
		if not chk.modules[i].ok:
			removed.append(i)
	var wall := cs.add_line(def.id, pts, removed)
	cs.add_clearings(sm.clearings_for(wall, true))
	out["wall_modules"] = chk.modules.size() - removed.size()
	for tier in ["bodies", "abstract"]:
		var start := demo.on_ground(c.x - 15.0, c.z - 25.0, 0.0)
		var goal := demo.on_ground(c.x - 15.0, c.z + 25.0, 0.0)
		var sq := _spawn(0, start, 6)
		if tier == "bodies":
			demo.rts_camera.frame(c, 0.0, 90.0)
		else:
			demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
		await _seconds(2.0)
		var res := await _walk(sq, goal, 300.0, 4.0, 6.0 + sq.spacing * sq.members.size() * 0.5)
		# On the goal side of the wall (south of it) and through the gap, not over the wall.
		var south := 0
		for id in sq.members:
			if _u(id).position.z > c.z + 1.0:
				south += 1
		res["south_of_wall"] = south
		out[tier] = res
		if tier == "bodies":
			await _shot("nav_base")
		_expect(res.arrived == res.of and south == res.of, "nav_base %s: %d of %d got round the wall" % [tier, res.arrived, res.of])
		await _despawn(sq)
	cs.remove(wall.id)
	return out


func _despawn(sq: SquadState) -> void:
	for id in sq.members.duplicate():
		demo.sim.state.remove_unit(id)
	await _physics(2)


# --- Roads ----------------------------------------------------------------------------

## Drives the construction tool like the player: select a type, move the cursor to world
## points (snapping as the mouse would), click, finish.
func _tool_click(p: Vector3) -> void:
	con.cursor = demo.on_ground(p.x, p.z, 0.0)
	con.snap = con._road_snap(con.cursor) if con.def.surface == StructureDef.Surface.ROAD else {}
	con._refresh_surface_check()
	con.add_surface_point()


func _roads() -> Dictionary:
	var out := {}
	var net: RoadNetwork = demo.sim.state.roads
	var routes := ws.routes
	con.set_active(true)
	var hq := _hq()
	var near := net.nearest(hq, 1500.0, 0, 0.0)
	_expect(not near.is_empty(), "roads precondition: no world road within 1.5 km of the HQ")
	if near.is_empty():
		return out
	# Like a player: try stretches of that road at least 500 m from the HQ with no
	# structure within 300 m (bases have HESCO perimeters, farms have barns; roads may not
	# cross either), curving out to one side, until the tool shows the road as buildable.
	var w0 := Vector3.INF
	var attempts := 0
	var pts_road := (near.road as RoadNetwork.Road).points
	con.select_type(&"road_gravel")
	for qi in range(0, pts_road.size(), 15):
		var q := pts_road[qi]
		if _flat(q, hq) < 500.0 or not sm._ids_in(Rect2(Vector2(q.x, q.z), Vector2.ZERO).grow(300.0)).is_empty():
			continue
		var nxt := pts_road[mini(qi + 1, pts_road.size() - 1)]
		var along := Vector2(nxt.x - q.x, nxt.z - q.z).normalized()
		for sgn in [1.0, -1.0]:
			attempts += 1
			var side: Vector2 = Vector2(-along.y, along.x) * sgn
			var p1 := Vector3(q.x + side.x * 120.0 + along.x * 60.0, 0, q.z + side.y * 120.0 + along.y * 60.0)
			var p2 := Vector3(q.x + side.x * 260.0 - along.x * 20.0, 0, q.z + side.y * 260.0 - along.y * 20.0)
			con.cancel()
			await _tool_click(q)
			await _tool_click(p1)
			con.cursor = demo.on_ground(p2.x, p2.z, 0.0)
			con.snap = {}
			con._refresh_surface_check()
			if con.check.get("ok", false):
				await _tool_click(p2)
				w0 = q
				break
		if w0.is_finite() or attempts > 40:
			break
	out["attempts"] = attempts
	_expect(w0.is_finite(), "roads precondition: no buildable stretch next to %s" % (near.road as RoadNetwork.Road).name)
	if not w0.is_finite():
		return out
	out["world_road"] = (near.road as RoadNetwork.Road).name
	var chk: Dictionary = con.check.duplicate()
	var start_snapped: bool = not con.point_snaps.is_empty() and not (con.point_snaps[0] as Dictionary).is_empty()
	var r1 := con.finish_surface()
	out["road1"] = {"built": r1 != null, "reason": chk.get("reason", ""), "length_m": snappedf(chk.get("length_m", 0.0), 0.1),
		"grade": chk.get("grade", 0.0), "max_cut_m": chk.get("max_cut_m", 0.0), "radius_m": snappedf(chk.get("radius_m", 0.0), 0.1),
		"start_snapped": start_snapped}
	_expect(r1 != null, "roads: curved gravel road from the world road not built (%s)" % chk.get("reason", ""))
	if r1 == null:
		con.set_active(false)
		return out
	await _physics(5)
	# Terrain follows the profile, the centre is painted gravel, the network and the route
	# grid know the road.
	var prof := r1.profile
	var dev := 0.0
	var gravel := 0
	for i in range(0, prof.size(), 5):
		dev = maxf(dev, absf(demo.terrain.data.get_height(prof[i]) - prof[i].y))
		if demo.terrain.data.get_control_base_id(prof[i]) == ReferenceWorldBuilder.TEX_GRAVEL:
			gravel += 1
	var cells := 0
	var road_cells := 0
	for i in range(0, prof.size(), 10):
		cells += 1
		var c := routes.world_to_cell(prof[i])
		if routes.road[c.y * routes.size.x + c.x] == 1:
			road_cells += 1
	out["road1"]["terrain_dev_m"] = snappedf(dev, 0.01)
	out["road1"]["painted_share"] = snappedf(float(gravel) / ceilf(prof.size() / 5.0), 0.01)
	out["road1"]["grid_road_cells"] = "%d/%d" % [road_cells, cells]
	out["road1"]["network_built"] = net.built.size()
	_expect(dev < 0.15, "roads: terrain %.2f m off the road profile" % dev)
	_expect(road_cells == cells, "roads: route grid marks %d of %d cells of the built road" % [road_cells, cells])
	# Junction with the world road: the start sits on the world road's surface.
	out["road1"]["junction_step_m"] = snappedf(absf(prof[0].y - demo.terrain.data.get_height(w0)), 0.01)
	# 2. An asphalt road continuing from the gravel road's end (snap to the end) with a bend.
	var e1 := prof[prof.size() - 1]
	var dir := Vector2(e1.x - prof[prof.size() - 6].x, e1.z - prof[prof.size() - 6].z).normalized()
	var q1 := Vector3(e1.x + dir.x * 90.0 + dir.y * 40.0, 0, e1.z + dir.y * 90.0 - dir.x * 40.0)
	var q2 := Vector3(e1.x + dir.x * 160.0 + dir.y * 120.0, 0, e1.z + dir.y * 160.0 - dir.x * 120.0)
	con.select_type(&"road_asphalt")
	await _tool_click(e1)
	var snapped_to_end: bool = not con.point_snaps.is_empty() and not (con.point_snaps[0] as Dictionary).is_empty() and con.point_snaps[0].end == 1
	await _tool_click(q1)
	await _tool_click(q2)
	var chk2: Dictionary = con.check.duplicate()
	var r2 := con.finish_surface()
	await _physics(3)
	out["trunks_on_roads"] = _trunks_on(r1) + (_trunks_on(r2) if r2 else 0)
	_expect(out.trunks_on_roads == 0, "roads: %d tree trunks left on the built roads" % out.trunks_on_roads)
	out["road2"] = {"built": r2 != null, "reason": chk2.get("reason", ""), "snapped_to_road_end": snapped_to_end,
		"junction_step_m": snappedf(absf(r2.profile[0].y - e1.y), 0.01) if r2 else -1.0}
	_expect(r2 != null and snapped_to_end, "roads: connecting asphalt road (%s)" % JSON.stringify(out.road2))
	# 3. A gravel yard next to the asphalt road: graded and painted, not a road.
	var cells_before := net.built.size()
	var yc := Vector3(q1.x + dir.y * 40.0, 0, q1.z - dir.x * 40.0)
	con.select_type(&"area_gravel")
	for o in [Vector2(-22, -16), Vector2(22, -16), Vector2(24, 18), Vector2(-20, 16)]:
		await _tool_click(Vector3(yc.x + o.x, 0, yc.z + o.y))
	var chk3: Dictionary = con.check.duplicate()
	var a1 := con.finish_surface()
	out["yard"] = {"built": a1 != null, "reason": chk3.get("reason", ""), "area_m2": chk3.get("area_m2", 0.0), "grade": chk3.get("grade", 0.0),
		"max_cut_m": chk3.get("max_cut_m", 0.0), "is_road": net.built.size() != cells_before,
		"grid_road_cell": routes.road[routes.world_to_cell(yc).y * routes.size.x + routes.world_to_cell(yc).x] == 1 and not routes.road[routes.world_to_cell(yc).y * routes.size.x + routes.world_to_cell(yc).x] == 0}
	_expect(a1 != null and net.built.size() == cells_before, "roads: gravel yard (%s)" % JSON.stringify(out.yard))
	# 4. A road into the river is refused.
	var r := _river_at(2000.0)
	con.select_type(&"road_dirt")
	await _tool_click(Vector3(r.x - r.half - 60.0, 0, 2000.0))
	await _tool_click(Vector3(r.x + r.half + 60.0, 0, 2000.0))
	var bad: Dictionary = con.check.duplicate()
	var rb := con.finish_surface()
	con.cancel()
	out["river_refused"] = {"built": rb != null, "reason": bad.get("reason", "")}
	_expect(rb == null and String(bad.get("reason", "")).begins_with("water"), "roads: a road across the river was not refused (%s)" % bad.get("reason", ""))
	# 5. Routes prefer the built roads: a route from the world road to the asphalt road's end.
	var route := routes.route(demo.on_ground(w0.x, w0.z, 0.0), demo.on_ground(q2.x, q2.z, 0.0), demo.terrain)
	var on := 0
	for i in range(1, route.size()):
		for t in [0.25, 0.5, 0.75]:
			var m := route[i - 1].lerp(route[i], t)
			if net.on_road(m, 30.0):
				on += 1
	out["route_on_roads"] = "%d/%d" % [on, maxi((route.size() - 1) * 3, 0)]
	_expect(route.size() >= 2 and on >= (route.size() - 1) * 3 * 0.6, "roads: route does not follow the built roads (%s)" % out.route_on_roads)
	# Screenshot of the new roads.
	con.set_active(false)
	demo.rts_camera.frame(demo.on_ground(e1.x, e1.z, 0.0), 0.6, 140.0)
	await _seconds(2.5)
	await _shot("roads_built")
	# Closer: the junction of the two built roads and the yard.
	demo.rts_camera.frame(demo.on_ground(q1.x, q1.z, 0.0), atan2(q1.x - e1.x, q1.z - e1.z), 55.0)
	await _seconds(2.5)
	await _shot("roads_built_close")
	# 6. Save / load: the same roads, terrain and network come back.
	var h_before := demo.terrain.data.get_height(prof[prof.size() / 2])
	var saved := cs.to_dict()
	cs.clear()
	await _physics(3)
	var h_cleared := demo.terrain.data.get_height(prof[prof.size() / 2])
	var built_after_clear := net.built.size()
	cs.from_dict(saved)
	await _physics(3)
	var h_after := demo.terrain.data.get_height(prof[prof.size() / 2])
	out["persist"] = {"surfaces": sm.surface_count(), "network_built": net.built.size(), "network_after_clear": built_after_clear,
		"height_before": snappedf(h_before, 0.01), "height_cleared": snappedf(h_cleared, 0.01), "height_after": snappedf(h_after, 0.01)}
	_expect(sm.surface_count() == 3 and net.built.size() == 2 and built_after_clear == 0 and absf(h_after - h_before) < 0.02,
		"roads: save/load (%s)" % JSON.stringify(out.persist))
	# 7. Removal restores the ground.
	var sp := sm.terrain_spacing()
	var v5 := Vector3(roundf(prof[5].x / sp) * sp, 0.0, roundf(prof[5].z / sp) * sp)
	var g0 := sm.original_height(v5.x, v5.z)
	for s: StructureState in cs.all():
		if StructureCatalog.get_def(s.type_id).is_surface():
			cs.remove(s.id)
	await _physics(3)
	out["removed"] = {"network_built": net.built.size(), "ground_restored_m": snappedf(absf(demo.terrain.data.get_height(v5) - g0), 0.01)}
	_expect(net.built.size() == 0 and out.removed.ground_restored_m < 0.01, "roads: removal (%s)" % JSON.stringify(out.removed))
	# Built roads back for the screenshots of the report (the test world is not saved).
	cs.from_dict(saved)
	await _physics(3)
	out["timings"] = sm.timings.duplicate()
	return out


## Solid vegetation (tree trunks, rocks) standing on a built road's surface, as the
## vegetation streamer reports it after the clearings (what collides and renders).
func _trunks_on(s: StructureState) -> int:
	var def := StructureCatalog.get_def(s.type_id)
	var half := def.surface_width * 0.5
	var n := 0
	var seen := {}
	for p in s.profile:
		var c := VegetationChunk.cell_of(p, demo.vegetation.cell_size_m)
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var cell := c + Vector2i(dx, dz)
				if seen.has(cell):
					continue
				seen[cell] = true
				for inst in demo.vegetation.get_cell_instances(cell, [1, 2, 3, 4, 5, 6]):
					var o: Vector3 = (inst[1] as Transform3D).origin
					var best := INF
					for i in s.profile.size() - 1:
						best = minf(best, LineOfFire._point_segment_dist2d(Vector2(o.x, o.z), Vector2(s.profile[i].x, s.profile[i].z), Vector2(s.profile[i + 1].x, s.profile[i + 1].z)))
					if best < half:
						n += 1
	return n


# --- Camera -----------------------------------------------------------------------------

func _camera() -> Dictionary:
	var out := {}
	var rig := demo.rts_camera
	rig.frame(_hq(), 0.4, 120.0)
	await _frames(3)
	# RTS tilt: middle-drag up / down changes the pitch within limits; yaw keeps working.
	var p0 := rad_to_deg(rig.pitch())
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	ev.relative = Vector2(40, 120)
	rig._unhandled_input(ev)
	var p1 := rad_to_deg(rig.pitch())
	ev.relative = Vector2(0, -4000)
	rig._unhandled_input(ev)
	var p_min := rad_to_deg(rig.pitch())
	ev.relative = Vector2(0, 8000)
	rig._unhandled_input(ev)
	var p_max := rad_to_deg(rig.pitch())
	rig.pitch_offset = 0.0
	rig.frame(rig.focus, rig.yaw)
	out["rts_tilt"] = {"pitch_start": snappedf(p0, 0.1), "after_drag_down": snappedf(p1, 0.1), "min": snappedf(p_min, 0.1), "max": snappedf(p_max, 0.1)}
	_expect(p1 > p0 + 5.0 and absf(p_min - rig.pitch_min_deg) < 0.1 and absf(p_max - rig.pitch_max_deg) < 0.1, "camera: tilt %s" % JSON.stringify(out.rts_tilt))
	# Strategic map: the wedge follows the camera; a middle click moves the camera, a
	# middle drag pans the map only.
	demo.toggle_map()
	await _frames(5)
	var map := demo.strategic_map
	map.zoom = 0.12
	map.view_center = Vector2(rig.focus.x, rig.focus.z)
	await _frames(5)
	await _shot("map_camera_wedge")
	var target_s := map.to_screen(rig.focus) + Vector2(220, -120)
	# The release point (a hand moves a little while clicking) is where the camera goes.
	var target_w := map.to_world(target_s + Vector2(2, 1))
	var vc0 := map.view_center
	_mouse(map, MOUSE_BUTTON_MIDDLE, true, target_s)
	_mouse(map, MOUSE_BUTTON_MIDDLE, false, target_s + Vector2(2, 1))
	var moved_now := _flat(rig.focus, target_w)
	await _frames(3)
	var moved := _flat(rig.focus, target_w)
	var cam_h := rig.camera.global_position.y - demo.terrain.data.get_height(rig.camera.global_position)
	out["middle_click"] = {"focus_to_target_m": snappedf(moved, 0.1), "focus_to_target_at_click_m": snappedf(moved_now, 0.1), "map_moved_px": snappedf((map.view_center - vc0).length() * map.zoom, 0.1),
		"camera_above_ground_m": snappedf(cam_h, 0.1)}
	_expect(moved < 3.0 and (map.view_center - vc0).length() * map.zoom < 1.0 and cam_h > 2.0, "camera: middle click %s" % JSON.stringify(out.middle_click))
	await _shot("map_after_middle_click")
	var focus0 := rig.focus
	_mouse(map, MOUSE_BUTTON_MIDDLE, true, target_s)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	for k in 6:
		mm.position = target_s + Vector2(10 * (k + 1), 0)
		mm.relative = Vector2(10, 0)
		map._gui_input(mm)
	_mouse(map, MOUSE_BUTTON_MIDDLE, false, target_s + Vector2(60, 0))
	await _frames(3)
	out["middle_drag"] = {"camera_moved_m": snappedf(_flat(focus0, rig.focus), 0.1), "map_panned_px": snappedf((map.view_center - vc0).length() * map.zoom, 0.1)}
	_expect(_flat(focus0, rig.focus) < 0.01 and absf((map.view_center - vc0).length() * map.zoom - 60.0) < 1.5, "camera: middle drag %s" % JSON.stringify(out.middle_drag))
	# Rotating the camera turns the wedge (the map redraws from the camera every 0.1 s).
	rig.frame(rig.focus, rig.yaw + PI * 0.5)
	await _seconds(0.3)
	await _shot("map_camera_rotated")
	demo.toggle_map()
	await _frames(3)
	return out


func _mouse(c: Control, button: MouseButton, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	c._gui_input(e)


# --- Time compression ---------------------------------------------------------------------

## Requested vs reached speed with the player's own settings (TimeCompression.apply(k)),
## war running, in the RTS view over the HQ and with the strategic map open.
func _timescale() -> Dictionary:
	_pause_ai(false)
	var out := {}
	demo.rts_camera.frame(_hq(), 0.4, 120.0)
	await _seconds(2.0)
	for view in ["rts", "map"]:
		if view == "map":
			demo.toggle_map()
			await _frames(5)
		var rows := {}
		for k in [2.0, 4.0, 8.0, 16.0, 32.0]:
			TimeCompression.apply(k)
			await _seconds_real(1.0)
			var t0 := demo.sim.state.time
			var r0 := Time.get_ticks_usec()
			var frames := 0
			var phys_ms := 0.0
			var proc_ms := 0.0
			var ticks0 := Engine.get_physics_frames()
			for k2 in demo.sim.tick_usec:
				demo.sim.tick_usec[k2] = 0
			while Time.get_ticks_usec() - r0 < 6.0e6:
				await tree.process_frame
				frames += 1
				phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			var real := (Time.get_ticks_usec() - r0) / 1.0e6
			var reached := (demo.sim.state.time - t0) / real
			var ticks := Engine.get_physics_frames() - ticks0
			# Per rendered frame: physics (one tick's time, the monitor, times the ticks),
			# process (scripts); the rest is rendering and engine overhead.
			var frame_ms := real * 1000.0 / maxi(frames, 1)
			rows["%dx" % int(k)] = {"reached": snappedf(reached, 0.1), "share": snappedf(reached / k, 0.01), "fps": snappedf(frames / real, 0.1),
				"ticks_per_frame": snappedf(float(ticks) / maxi(frames, 1), 0.1), "frame_ms": snappedf(frame_ms, 0.1),
				"process_ms": snappedf(proc_ms / maxi(frames, 1), 0.1), "max_steps": Engine.max_physics_steps_per_frame,
				"tick_real_ms": snappedf(maxf(frame_ms - proc_ms / maxi(frames, 1), 0.0) / maxf(float(ticks) / maxi(frames, 1), 0.01), 0.01),
				"sim_us_per_tick": _tick_breakdown(), "bodies": demo.sim.bodies.size(), "units": demo.sim.state.units.size()}
			TimeCompression.reset()
		out[view] = rows
		if view == "map":
			demo.toggle_map()
			await _frames(3)
	_pause_ai(true)
	return out


func _tick_breakdown() -> Dictionary:
	var out := {}
	var n: int = maxi(demo.sim.tick_usec.ticks, 1)
	for k in demo.sim.tick_usec:
		if k != "ticks":
			out[k] = roundi(float(demo.sim.tick_usec[k]) / n)
	return out


func _seconds_real(s: float) -> void:
	var r0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - r0 < s * 1000.0:
		await tree.process_frame
