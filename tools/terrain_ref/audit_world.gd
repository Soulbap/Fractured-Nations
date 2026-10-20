## World geometry audit on the BUILT reference world (WORLD-PLAYTEST-01): reads the
## Terrain3D data exactly as the game loads it, plus the world's roads.json / water.json.
##
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/audit_world.gd -- \
##       [--scene=res://scenes/world/ref_20km.tscn] [--out=res://docs/playtest01/audit_world.json]
##
## Checks
##   - river: terrain under the river centre line is below the water surface every 20 m
##     (a dam or a filled channel blocks the river; bridges once stood on earth dams);
##   - lakes: the terrain inside each outline is below the lake level;
##   - bridges: the channel under every span is open, the deck ends sit on the terrain;
##   - roads: the terrain under every road follows the road profile (paved roads: the
##     Road Generator surface may not be buried or float; painted roads: graded terrain);
##   - navigation: the strategic passability grid (StrategicRoutes, the same grid the AI
##     plans on) marks every road, opens every bridge and plans a route across each one.
## Prints a summary and writes the findings as JSON. Exit code 1 on error-level findings.
extends SceneTree

var _terrain: Terrain3D
var _findings: Array = []


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
	var world: Node3D = scene.instantiate()
	# Only the terrain matters: drop the gameplay and vegetation nodes before they run.
	for n in ["Player", "WorldDiagnostics", "Vegetation", "Grass", "InstanceColliderStreamer"]:
		var x := world.get_node_or_null(n)
		if x:
			x.free()
	get_root().add_child(world)
	_terrain = world.get_node("Terrain3D")
	for i in 5:
		await process_frame
	var cfg: WorldConfig = world.get_node("WorldBuilder").config
	var src: String = (cfg as ReferenceWorldConfig).source_directory + "/"
	var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + "roads.json"))
	var water: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src + "water.json"))
	var t0 := Time.get_ticks_msec()
	var stats := {}
	stats["river"] = _check_river(water.river)
	stats["lakes"] = _check_lakes(water.lakes)
	stats["bridges"] = _check_bridges(roads.roads, water.river)
	stats["roads"] = _check_roads(roads.roads)
	stats["navigation"] = _check_navigation(cfg, src, roads.roads)
	var errors := 0
	var warnings := 0
	for f: Dictionary in _findings:
		if f.level == "error":
			errors += 1
		elif f.level == "warn":
			warnings += 1
	stats["errors"] = errors
	stats["warnings"] = warnings
	stats["ms"] = Time.get_ticks_msec() - t0
	print("AUDIT ", JSON.stringify(stats))
	for f: Dictionary in _findings:
		if f.level != "info":
			print("  %-5s %-10s %-24s %s %s" % [f.level, f.kind, f.what, f.msg, f.pos])
	var out_path: String = o.get("out", "")
	if out_path != "":
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"stats": stats, "findings": _findings}, " "))
		fa.close()
	quit(1 if errors > 0 else 0)


func _add(level: String, kind: String, what: String, msg: String, pos := Vector2.INF) -> void:
	_findings.append({"level": level, "kind": kind, "what": what, "msg": msg,
		"pos": [] if pos == Vector2.INF else [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)]})


func _h(x: float, z: float) -> float:
	return _terrain.data.get_height(Vector3(x, 0.0, z))


# --- Water ---------------------------------------------------------------------------

func _check_river(river: Dictionary) -> Dictionary:
	var pts: Array = river.points
	var lv: Array = river.level
	var blocked := 0
	var worst := -INF
	var acc := 0.0
	var n := 0
	var run_start := Vector2.INF
	for k in pts.size():
		if k > 0:
			acc += Vector2(pts[k][0], pts[k][1]).distance_to(Vector2(pts[k - 1][0], pts[k - 1][1]))
			if acc < 20.0:
				continue
		acc = 0.0
		n += 1
		var h := _h(pts[k][0], pts[k][1])
		if is_nan(h):
			continue  # the river enters/leaves beyond the map edge
		var above: float = h - float(lv[k])
		worst = maxf(worst, above)
		if above > -0.3:
			blocked += 1
			if run_start == Vector2.INF:
				run_start = Vector2(pts[k][0], pts[k][1])
		elif run_start != Vector2.INF:
			_add("error", "river", "channel", "terrain at/above the water surface (dam or filled channel)", run_start)
			run_start = Vector2.INF
	if run_start != Vector2.INF:
		_add("error", "river", "channel", "terrain at/above the water surface (dam or filled channel)", run_start)
	return {"samples": n, "blocked": blocked, "worst_terrain_above_water_m": snappedf(worst, 0.01)}


func _check_lakes(lakes: Array) -> Dictionary:
	var out := {}
	for lake: Dictionary in lakes:
		var poly := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p: Array in lake.outline:
			poly.append(Vector2(p[0], p[1]))
			lo = lo.min(Vector2(p[0], p[1]))
			hi = hi.max(Vector2(p[0], p[1]))
		var dry := 0
		var n := 0
		var x := lo.x
		while x <= hi.x:
			var z := lo.y
			while z <= hi.y:
				var q := Vector2(x, z)
				# Inner samples only (the outline sits a little past the shore).
				if Geometry2D.is_point_in_polygon(q, poly) and StrategicRoutes._dist_to_poly(q, poly) > 25.0:
					n += 1
					if _h(x, z) > float(lake.level) - 0.2:
						dry += 1
				z += 20.0
			x += 20.0
		out[lake.name] = {"samples": n, "dry": dry}
		if n > 0 and dry > n * 0.02:
			_add("warn", "lake", lake.name, "%d of %d inner samples above the water" % [dry, n])
	return out


# --- Bridges -------------------------------------------------------------------------

func _check_bridges(roads: Array, river: Dictionary) -> Dictionary:
	var rp: Array = river.points
	var n := 0
	var dams := 0
	for r: Dictionary in roads:
		for span: Array in r.bridges:
			n += 1
			var a := Vector3(r.points[int(span[0])][0], r.points[int(span[0])][1], r.points[int(span[0])][2])
			var b := Vector3(r.points[int(span[1])][0], r.points[int(span[1])][1], r.points[int(span[1])][2])
			var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
			var lvl := _river_level(rp, river.level, mid)
			var length := Vector2(b.x - a.x, b.z - a.z).length()
			var under_max := -INF
			for k in range(1, 20):
				var t := float(k) / 20.0
				var p := a.lerp(b, t)
				if Vector2(p.x - a.x, p.z - a.z).length() < 15.0 or Vector2(p.x - b.x, p.z - b.z).length() < 15.0:
					continue
				var d := _river_dist(rp, Vector2(p.x, p.z))
				if d > 20.0:
					continue
				under_max = maxf(under_max, _h(p.x, p.z) - lvl)
			if under_max > -0.3:
				dams += 1
				_add("error", "bridge", r.name, "channel under the bridge filled: terrain %.1f m vs water" % under_max, mid)
			for e in [a, b]:
				var gap: float = e.y - _h(e.x, e.z)
				if absf(gap) > 1.2:
					_add("warn", "bridge", r.name, "deck end %.1f m %s the terrain" % [absf(gap), "above" if gap > 0 else "below"], Vector2(e.x, e.z))
			var deck: float = maxf(a.y, b.y) - lvl
			_add("info", "bridge", r.name, "span %.0f m, deck %.1f m above water" % [length, deck], mid)
	return {"bridges": n, "dammed": dams}


func _river_dist(rp: Array, q: Vector2) -> float:
	var best := INF
	for k in range(0, rp.size(), 2):
		best = minf(best, q.distance_to(Vector2(rp[k][0], rp[k][1])))
	return best


func _river_level(rp: Array, lv: Array, q: Vector2) -> float:
	var best := INF
	var out := 0.0
	for k in rp.size():
		var d := q.distance_to(Vector2(rp[k][0], rp[k][1]))
		if d < best:
			best = d
			out = lv[k]
	return out


# --- Roads ---------------------------------------------------------------------------

func _check_roads(roads: Array) -> Dictionary:
	var n := 0
	var buried := 0
	var floating := 0
	var worst_buried := 0.0
	var worst_float := 0.0
	for r: Dictionary in roads:
		var pts: Array = r.points
		var in_bridge := PackedByteArray()
		in_bridge.resize(pts.size())
		for span: Array in r.bridges:
			for k in range(maxi(int(span[0]) - 2, 0), mini(int(span[1]) + 3, pts.size())):
				in_bridge[k] = 1
		# Paved roads: Road Generator surface 0.2 m above the RoadPoint profile, terrain
		# flattened 0.25 m below the surface. Painted roads: the terrain is the road.
		var paved: bool = r.mesh
		var surface_off := 0.2 if paved else 0.0
		var road_bad_b := 0
		var road_bad_f := 0
		var first_b := Vector2.INF
		var first_f := Vector2.INF
		for k in range(0, pts.size(), 2):
			if in_bridge[k]:
				continue
			var p: Array = pts[k]
			var h := _h(p[0], p[2])
			if is_nan(h):
				continue
			n += 1
			var surf: float = float(p[1]) + surface_off
			var diff := h - surf
			# Paved: terrain above the surface buries it; terrain far below leaves it floating.
			if diff > (0.15 if paved else 0.6):
				road_bad_b += 1
				worst_buried = maxf(worst_buried, diff)
				if first_b == Vector2.INF:
					first_b = Vector2(p[0], p[2])
			elif diff < (-1.0 if paved else -0.6):
				road_bad_f += 1
				worst_float = minf(worst_float, diff)
				if first_f == Vector2.INF:
					first_f = Vector2(p[0], p[2])
		buried += road_bad_b
		floating += road_bad_f
		if road_bad_b > 0:
			_add("warn" if road_bad_b < 5 else "error", "road", r.name, "%d samples: terrain above the road surface" % road_bad_b, first_b)
		if road_bad_f > 0:
			_add("warn" if road_bad_f < 5 else "error", "road", r.name, "%d samples: road above the terrain" % road_bad_f, first_f)
	return {"samples": n, "buried": buried, "floating": floating,
		"worst_buried_m": snappedf(worst_buried, 0.01), "worst_floating_m": snappedf(worst_float, 0.01)}


# --- Navigation ----------------------------------------------------------------------

func _check_navigation(cfg: WorldConfig, src: String, roads: Array) -> Dictionary:
	var routes := StrategicRoutes.new()
	routes.setup(_terrain, cfg.half_size(), src, "user://strategic/audit_grid_%d.bin" % Time.get_ticks_msec())
	# Road coverage: every road sample lies in a road cell.
	var samples := 0
	var missing := 0
	for r: Dictionary in roads:
		for k in range(0, r.points.size(), 3):
			var p := Vector3(r.points[k][0], 0, r.points[k][2])
			var c := routes.world_to_cell(p)
			if not routes._in(c):
				continue
			samples += 1
			if routes.road[c.y * routes.size.x + c.x] == 0:
				missing += 1
	if missing > 0:
		_add("warn", "nav", "roads", "%d of %d road samples not marked as road in the strategic grid" % [missing, samples])
	# Bridges: a route between the two banks crosses at the bridge.
	var crossed := 0
	var n := 0
	for r: Dictionary in roads:
		for span: Array in r.bridges:
			var i0 := maxi(int(span[0]) - 25, 0)
			var i1 := mini(int(span[1]) + 25, r.points.size() - 1)
			var a := Vector3(r.points[i0][0], r.points[i0][1], r.points[i0][2])
			var b := Vector3(r.points[i1][0], r.points[i1][1], r.points[i1][2])
			var m: Array = r.points[(int(span[0]) + int(span[1])) / 2]
			var mid := Vector2(m[0], m[2])
			n += 1
			var route := routes.route(a, b, _terrain)
			var best := INF
			for q in route:
				best = minf(best, Vector2(q.x, q.z).distance_to(mid))
			# Legs between waypoints: sample them too.
			for k in range(1, route.size()):
				for t in [0.25, 0.5, 0.75]:
					var q := route[k - 1].lerp(route[k], t)
					best = minf(best, Vector2(q.x, q.z).distance_to(mid))
			if route.is_empty():
				_add("error", "nav", r.name, "no strategic route across the bridge", mid)
			elif best > 60.0:
				_add("error", "nav", r.name, "route between the banks does not use the bridge (%.0f m away)" % best, mid)
			else:
				crossed += 1
	return {"road_samples": samples, "road_samples_unmarked": missing, "bridges": n, "bridge_routes_ok": crossed,
		"grid_ms": snappedf(routes.build_ms, 0.1)}
