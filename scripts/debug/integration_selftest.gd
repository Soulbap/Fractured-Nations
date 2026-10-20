## Scripted checks of WORLD-INTEGRATION-01: the WORLD-BASE-01 construction system on the
## reference world ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file wi01.log res://scenes/game/world_ref_20km.tscn -- --integration-test [--shots]
##
## Finds five kinds of terrain by measuring the map (open meadow, forest clearing, gentle
## slope, next to a road, next to a settlement; nothing predefined) and builds there
## through the real construction input. Then: vegetation clearing inside footprints
## (off: trees block; on: they are removed, also from colliders and the navmesh), water
## refusal, a larger base on open ground, a soldier walking out through a gate, abstract
## units stopped by walls, a long trip and back, save / clear / load (structures and
## clearings), and frame times (dense forest FPS, inside the base, RTS heights, placement
## and removal, long jumps, vegetation streaming after construction).
## Prints "WI01 <check> <json>", writes res://benchmarks/raw/integration_test.json and
## (with --shots) docs/integration01/wi01_*.jpg.
class_name IntegrationSelfTest
extends BaseSelfTest

## Road centre-line samples bucketed by 64 m cells, settlement centres and radii.
var _road_grid := {}
var _settlements := []
var spots := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/integration01"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	tree.create_timer(900.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 900 s")
		_finish())
	var game := demo.game
	var rig := demo.rts_camera
	var veg := demo.vegetation
	await _physics(60)
	_load_world_data()

	# 0. Startup on the reference world: main scene, spawn, possession, zoom limits.
	_log("startup", {"main_scene": ProjectSettings.get_setting("application/run/main_scene"), "world": demo.config.world_name,
		"world_m": demo.config.snapped_size(), "units": demo.sim.state.units.size(), "possessed": game.possessed_id,
		"mode": game.mode, "zoom_min": rig.zoom_min, "zoom_max": rig.zoom_max, "water_cells": sm._water.size(),
		"roads_cells": _road_grid.size(), "settlements": _settlements.size()})
	_expect(demo.config.world_name == "ref_20km" and game.possessed_body() != null, "game did not start possessing a soldier on ref_20km")
	_expect(is_equal_approx(rig.zoom_min, 15.0) and is_equal_approx(rig.zoom_max, 300.0), "RTS zoom limits are not 15..300 m")
	_expect(sm._water.size() > 0, "no water surfaces indexed for placement")
	_press(KEY_TAB)
	await _physics(3)

	# 1. Measure the map for the five environments around the playable sites.
	var origin: Vector3 = demo.sites[0].position
	var t_search := Time.get_ticks_msec()
	spots.meadow = _find_spot("meadow", origin)
	spots.forest = _find_spot("forest", origin)
	spots.slope = _find_spot("slope", origin)
	spots.road = _find_spot("road", origin)
	spots.settlement = _find_settlement_spot(origin)
	var found := {}
	for k in spots:
		found[k] = _describe(spots[k]) if spots[k].is_finite() else null
	found["search_ms"] = Time.get_ticks_msec() - t_search
	_log("environments", found)
	if "--search-only" in args:
		_finish()
		return
	for k in spots:
		_expect(spots[k].is_finite(), "no %s spot found" % k)

	_press(KEY_B)
	await _frames(3)
	_expect(con.active, "B did not enter construction mode on the reference world")

	if "--groundwork-only" in args:
		_log("groundwork", await _groundwork(origin))
		_finish()
		return

	# 2. Water: a building on the river is refused.
	var wet := _find_water(origin)
	var wet_check := sm.check_building(StructureCatalog.get_def(&"barracks"), wet, 0.0) if wet.is_finite() else {}
	_log("water", {"spot": _v(wet), "water_h": snappedf(sm.water_height(wet.x, wet.z), 0.01) if wet.is_finite() else null,
		"terrain_h": snappedf(demo.ground_height(wet), 0.01) if wet.is_finite() else null, "reason": wet_check.get("reason", "")})
	_expect(wet.is_finite() and wet_check.get("reason", "") == "water", "a building in the river was not refused as water")

	# 3. Forest clearing: clearing off -> trees block; on -> small base, trees removed.
	var forest: Vector3 = spots.forest
	var forest_res := {}
	if forest.is_finite():
		forest_res = await _forest_base(forest)
	_log("forest_clearing", forest_res)

	var quick := "--quick" in args
	if quick:
		_press(KEY_B)
		await _frames(2)
		if "--away" in args:
			rig.frame(spots.meadow if spots.meadow.is_finite() else demo.sites[1].position, 0.0, 150.0)
			await _seconds(3.0)
		if forest_res.has("inside"):
			_log("soldier_through_gate", await _walk_out(forest_res.inside, forest_res.outside, forest_res.fence_ids, "soldier_around_barrier"))
		_finish()
		return

	# 4. Gentle slope, near a road, near a settlement: a building and a line each.
	for k: String in ["slope", "road", "settlement"]:
		if spots[k].is_finite():
			_log("env_" + k, await _small_build(k, spots[k]))

	# 4b. Groundwork: a building on sloped, uneven ground the old rules refused.
	var gw := await _groundwork(origin)
	_log("groundwork", gw)

	# 5. Larger base on open terrain (meadow).
	var meadow: Vector3 = spots.meadow
	var big := {}
	if meadow.is_finite():
		big = await _open_base(meadow)
	_log("open_base", big.get("info", {}))

	# 6. A soldier walks from inside the forest base out through its gate.
	_press(KEY_B)
	await _frames(2)
	if forest_res.has("inside"):
		_log("soldier_through_gate", await _walk_out(forest_res.inside, forest_res.outside, forest_res.fence_ids, "soldier_around_barrier"))
	if big.has("inside"):
		_log("soldier_out_of_open_base", await _walk_out(big.inside, big.outside, [big.perim_id], "soldier_around_hesco"))

	# 7. Performance: dense forest FPS, inside the base, RTS heights, placement / removal.
	var perf := {}
	if big.has("inside"):
		perf.merge(await _perf_base(big))
	perf.merge(await _perf_forest(origin))
	_log("performance", perf)

	# 8. Abstract units (camera far away) do not walk through the HESCO wall.
	if big.has("perim_id"):
		_log("abstract_blocking", await _abstract_wall(big))

	# 9. Trip of several km and back: structures and clearings unchanged and re-streamed.
	if forest_res.has("inside"):
		_log("travel_and_return", await _travel(forest_res, big))

	# 10. Save, clear, load: structures and clearings.
	if forest_res.has("inside"):
		_log("save_load", await _save_load(forest_res))
	_finish()


# --- Environments -------------------------------------------------------------------

func _load_world_data() -> void:
	var src := "res://worlds/%s/source/" % demo.config.world_name
	var roads: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "roads.json"))
	if roads is Dictionary:
		for r: Dictionary in roads.roads:
			var pts: Array = r.points
			for i in range(0, pts.size() - 1):
				var a := Vector2(pts[i][0], pts[i][2])
				var b := Vector2(pts[i + 1][0], pts[i + 1][2])
				var n := maxi(1, ceili(a.distance_to(b) / 8.0))
				for k in n:
					var q := a.lerp(b, float(k) / n)
					var key := Vector2i(floori(q.x / 64.0), floori(q.y / 64.0))
					if not _road_grid.has(key):
						_road_grid[key] = []
					_road_grid[key].append(q)
	var sites: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "sites.json"))
	if sites is Dictionary:
		for s: Dictionary in sites.settlements:
			_settlements.append([Vector2(s.pos[0], s.pos[2]), float(s.radius_m), String(s.name)])


func _road_dist(p: Vector3) -> float:
	var best := INF
	var c := Vector2i(floori(p.x / 64.0), floori(p.z / 64.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for q: Vector2 in _road_grid.get(c + Vector2i(dx, dz), []):
				best = minf(best, q.distance_to(Vector2(p.x, p.z)))
	return best


## Distance to the nearest settlement edge (negative inside) and its name.
func _settlement_dist(p: Vector3) -> Array:
	var best := INF
	var name := ""
	for s: Array in _settlements:
		var d: float = (s[0] as Vector2).distance_to(Vector2(p.x, p.z)) - s[1]
		if d < best:
			best = d
			name = s[2]
	return [best, name]


## Solid vegetation within r of p: {trees, houses, rocks}.
func _solids(p: Vector3, r: float, r_min := 0.0) -> Dictionary:
	var out := {"trees": 0, "houses": 0, "rocks": 0}
	var c0 := VegetationChunk.cell_of(p - Vector3(r, 0, r), 128.0)
	var c1 := VegetationChunk.cell_of(p + Vector3(r, 0, r), 128.0)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for t: Array in sm._trees_in(Vector2i(cx, cz)):
				var d := Vector2(t[0] - p.x, t[1] - p.z).length()
				if d > r or d < r_min:
					continue
				var id: int = t[3]
				if id <= 6:
					out.trees += 1
				elif id >= 16:
					out.houses += 1
				else:
					out.rocks += 1
	return out


func _height_range(p: Vector3, half: float) -> float:
	var lo := INF
	var hi := -INF
	for ix in range(-4, 5):
		for iz in range(-4, 5):
			var h := demo.ground_height(p + Vector3(ix * half / 4.0, 0, iz * half / 4.0))
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return hi - lo


func _dry(p: Vector3, half: float) -> bool:
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			var q := p + Vector3(ix * half / 2.0, 0, iz * half / 2.0)
			if sm._wet(q.x, q.z, demo.ground_height(q)):
				return false
	return true


## First spot of a kind on rings around center (up to 6 km), measured from the map data.
func _find_spot(kind: String, center: Vector3) -> Vector3:
	for r: float in [150.0, 300.0, 500.0, 750.0, 1000.0, 1400.0, 1900.0, 2500.0, 3200.0, 4000.0, 5000.0, 6000.0]:
		var n := clampi(int(r / 25.0), 24, 160)
		for k in n:
			var a := k * TAU / n + r * 0.001
			var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			if absf(p.x) > 9500.0 or absf(p.z) > 9500.0:
				continue
			if _matches(kind, p):
				return p
	return Vector3.INF


## Rings around the settlement centres, nearest settlement to center first.
func _find_settlement_spot(center: Vector3) -> Vector3:
	var order := _settlements.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as Vector2).distance_to(Vector2(center.x, center.z)) < (b[0] as Vector2).distance_to(Vector2(center.x, center.z)))
	for s: Array in order:
		var sc: Vector2 = s[0]
		var r: float = 40.0
		while r < s[1] + 40.0:
			var n := clampi(int(r / 12.0), 12, 96)
			for k in n:
				var a := k * TAU / n
				var p := demo.on_ground(sc.x + cos(a) * r, sc.y + sin(a) * r, 0.0)
				if _matches("settlement", p):
					return p
			r += 30.0
	return Vector3.INF


func _matches(kind: String, p: Vector3) -> bool:
	var road := _road_dist(p)
	var sd: Array = _settlement_dist(p)
	match kind:
		"meadow":
			if road < 60.0 or sd[0] < 150.0 or _slope_at(p, 20.0) > 2.5 or _height_range(p, 50.0) > 3.0:
				return false
			var s := _solids(p, 70.0)
			return s.trees + s.houses + s.rocks == 0 and _dry(p, 60.0)
		"forest":
			# A small natural opening (few trunks within 10 m) inside dense forest.
			if road < 40.0 or sd[0] < 100.0 or _slope_at(p, 12.0) > 6.0 or _height_range(p, 18.0) > 2.5:
				return false
			var inner := _solids(p, 7.0)
			if inner.trees > 3 or inner.rocks > 0 or inner.houses > 0:
				return false
			var ring := _solids(p, 24.0, 7.0)
			return ring.trees >= 10 and ring.rocks <= 1 and ring.houses == 0 and _dry(p, 25.0)
		"slope":
			if road < 40.0 or sd[0] < 100.0:
				return false
			var s1 := _slope_at(p, 14.0)
			if s1 < 3.5 or s1 > 6.0 or _slope_at(p, 4.0) > 6.5:
				return false
			var s := _solids(p, 30.0)
			return s.trees <= 1 and s.rocks == 0 and s.houses == 0 and _dry(p, 30.0)
		"road":
			if road < 15.0 or road > 24.0 or sd[0] < 60.0 or _slope_at(p, 8.0) > 4.0:
				return false
			var s := _solids(p, 16.0)
			return s.rocks == 0 and s.houses == 0 and _dry(p, 20.0)
		"settlement":
			if sd[0] > 40.0 or road < 10.0 or _slope_at(p, 8.0) > 4.5:
				return false
			var near := _solids(p, 11.0)
			var around := _solids(p, 80.0)
			return near.trees + near.houses + near.rocks == 0 and around.houses >= 2 and _dry(p, 20.0)
	return false


func _describe(p: Vector3) -> Dictionary:
	var sd: Array = _settlement_dist(p)
	return {"pos": _v(p), "slope_deg": snappedf(_slope_at(p, 10.0), 0.1), "height_range_40m": snappedf(_height_range(p, 20.0), 0.01),
		"road_m": snappedf(_road_dist(p), 0.1), "settlement": sd[1], "settlement_edge_m": snappedf(sd[0], 1.0),
		"solids_30m": _solids(p, 30.0), "solids_60m": _solids(p, 60.0)}


func _find_water(center: Vector3) -> Vector3:
	for r: float in [200.0, 500.0, 900.0, 1500.0, 2200.0, 3000.0, 4000.0, 5500.0, 7000.0]:
		for k in 96:
			var a := k * TAU / 96.0
			var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			var w := sm.water_height(p.x, p.z)
			if w > -INF and p.y < w - 0.3:
				return p
	return Vector3.INF


# --- Builds -------------------------------------------------------------------------

## Trunks of clearable trees inside a structure's footprint (+ margin) right now.
func _trunks_inside(s: StructureState, margin: float) -> int:
	var def := StructureCatalog.get_def(s.type_id)
	var n := 0
	for i in s.instances.size():
		if s.is_line() and s.is_removed(i):
			continue
		var obb := StructureManager._obb(def, s.instances[i])
		var c: Vector2 = obb[0]
		var c0 := VegetationChunk.cell_of(Vector3(c.x - 15, 0, c.y - 15), 128.0)
		var c1 := VegetationChunk.cell_of(Vector3(c.x + 15, 0, c.y + 15), 128.0)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				for inst in demo.vegetation.get_cell_instances(Vector2i(cx, cz), [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15]):
					var o: Vector3 = (inst[1] as Transform3D).origin
					if StructureManager._obb_circle(obb, Vector2(o.x, o.z), margin):
						n += 1
	return n


## Clearable trunks and undergrowth inside a square (local half size h) around c.
func _trunks_in_square(c: Vector3, basis: Basis, h: float) -> int:
	var inv := basis.inverse()
	var n := 0
	for cell in StructureManager._cells_around(Vector2(c.x, c.z), h * 1.5):
		for inst in demo.vegetation.get_cell_instances(cell, [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15]):
			var o: Vector3 = (inst[1] as Transform3D).origin
			var l := inv * Vector3(o.x - c.x, 0, o.z - c.z)
			if absf(l.x) <= h and absf(l.z) <= h:
				n += 1
	return n


## Active MultiMesh instances in the vegetation cells under a structure (what is drawn).
func _drawn_in_cells(s: StructureState) -> int:
	var cells := {}
	for xf in s.instances:
		cells[VegetationChunk.cell_of(xf.origin, 128.0)] = true
	var n := 0
	for key: Vector3i in demo.vegetation.active:
		if cells.has(Vector2i(key.x, key.y)):
			n += (demo.vegetation.active[key] as MultiMeshInstance3D).multimesh.instance_count
	return n


func _forest_base(c: Vector3) -> Dictionary:
	var out := {}
	var rig := demo.rts_camera
	var yaw := 0.3
	var basis := Basis(Vector3.UP, yaw)
	var at := func(x: float, z: float) -> Vector3:
		var q: Vector3 = c + basis * Vector3(x, 0, z)
		return demo.on_ground(q.x, q.z, 0.0)
	# Clearing off: a barracks among the trees is refused.
	if con.clear_trees:
		_press(KEY_C)
		await _frames(2)
	out.clearing_toggle_off = not con.clear_trees
	# The barracks goes on a tree trunk west of the centre (so clearing is exercised).
	var bk_spot: Vector3 = at.call(-6.0, 5.0)
	var best := INF
	var inv := basis.inverse()
	for cell in StructureManager._cells_around(Vector2(c.x, c.z), 20.0):
		for t: Array in sm._trees_in(cell):
			if t[3] > 6:
				continue
			var l := inv * Vector3(t[0] - c.x, 0, t[1] - c.z)
			if l.x < -11.0 or l.x > -2.0 or absf(l.z) > 9.0:
				continue
			var d := Vector2(l.x + 7.0, l.z - 2.0).length()
			if d < best:
				best = d
				bk_spot = demo.on_ground(t[0], t[1], 0.0)
	out.barracks_on_trunk = best < INF
	var blocked: StructureState = await _place(&"barracks", bk_spot, 0, false)
	out.off_built = blocked != null
	out.off_reason = con.check.get("reason", "")
	_expect(blocked == null and String(out.off_reason).contains("tree"), "with clearing off a barracks in the forest was not blocked by trees (%s)" % out.off_reason)
	if blocked:
		cs.remove(blocked.id)
	_press(KEY_C)
	await _frames(2)
	out.clearing_toggle_on = con.clear_trees
	# Clearing on: command post, barracks, fence square with a gate.
	var n_clear := cs.clearings.size()
	out.square_trunks_before = _trunks_in_square(c, basis, 15.0)
	var cp: StructureState = await _place(&"command_post", at.call(4.0, -3.0), 0)
	var bk: StructureState = await _place(&"barracks", bk_spot, 0)
	var h := 15.0
	# Fence square open on the north side: gate snapped to the last end, then a second
	# fence from the gate's far post back to the first fence's start.
	var f1: StructureState = await _draw_line(&"fence", [at.call(-6.0, h), at.call(-h, h), at.call(-h, -h), at.call(h, -h), at.call(h, h), at.call(3.0, h)], true)
	var gate: StructureState = null
	var f_end := f1.points[-1] if f1 else Vector3.INF
	if f1:
		con.select_type(&"fence_gate")
		rig.frame(f_end, 0.0, 50.0)
		await _frames(3)
		await _cursor_at(f_end + basis * Vector3(-1.6, 0, 0.6))
		if con.check.get("ok", false) and not con.snap.is_empty():
			var n := cs.count()
			_click(MOUSE_BUTTON_LEFT, _screen(con.cursor))
			await _frames(2)
			if cs.count() > n:
				gate = cs.all()[-1]
		else:
			out.gate_reason = con.check.get("reason", "no snap")
		con.clear_tool()
	var f2: StructureState = null
	if gate:
		var gdef := StructureCatalog.get_def(&"fence_gate")
		var p0 := gate.instances[0] * gdef.snap_points[0]
		var p1 := gate.instances[0] * gdef.snap_points[1]
		var far_post := p1 if _flat(p0, f_end) < _flat(p1, f_end) else p0
		out.gate_post_to_fence_end_m = snappedf(minf(_flat(p0, f_end), _flat(p1, f_end)), 0.001)
		f2 = await _draw_line(&"fence", [far_post, f1.points[0]], true)
		out.fence2 = _line_info(f2)
	var tw: StructureState = await _place(&"guard_tower", at.call(h - 4.0, -h + 4.0), 0)
	con.clear_tool()
	out.built = {"command_post": cp != null, "barracks": bk != null, "fence": _line_info(f1), "gate": gate != null, "tower": tw != null}
	out.clearings_added = cs.clearings.size() - n_clear
	await _seconds(1.0)
	var inside := 0
	for s: StructureState in [cp, bk, gate, tw]:
		if s:
			inside += _trunks_inside(s, 0.0)
	out.trunks_left_in_footprints = inside
	out.square_trunks_after = _trunks_in_square(c, basis, 15.0)
	_expect(out.square_trunks_after < out.square_trunks_before, "no vegetation was cleared inside the forest base")
	out.drawn_instances_base_cells = _drawn_in_cells(bk) if bk else -1
	out.solids_15m_after = _solids(c, 15.0)
	out.collider_count_near = demo.detail.collider_streamer.active_count if demo.detail and demo.detail.collider_streamer else -1
	_expect(cp != null and bk != null and f1 != null and gate != null, "forest base not complete (cp %s, barracks %s, fence %s, gate %s)" % [cp != null, bk != null, f1 != null, gate != null])
	_expect(out.clearings_added > 0 and inside == 0, "trees remain inside cleared footprints (%d)" % inside)
	_expect(f2 != null, "fence from the gate back to the start was not built")
	out.fence_ids = [f1.id if f1 else -1, f2.id if f2 else -1]
	out.inside = at.call(7.0, -10.0)
	out.outside = at.call(-14.0, h + 3.0)
	out.check_struct = bk.id if bk else -1
	out.center = c
	out.yaw = yaw
	if shots:
		rig.frame(c, 0.5, 70.0)
		await _seconds(2.0)
		_shot("forest_clearing_base_rts")
		rig.frame(f_end, 2.6, 32.0)
		await _seconds(1.0)
		_shot("forest_gate_rts")
	return out


## Terrain heights on a 2 m grid in a square of half size h around c.
func _grid(c: Vector3, h: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(h / 2.0)
	for iz in range(-n, n + 1):
		for ix in range(-n, n + 1):
			out.append(demo.ground_height(c + Vector3(ix * 2.0, 0, iz * 2.0)))
	return out


static func _max_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var worst := 0.0
	for i in mini(a.size(), b.size()):
		worst = maxf(worst, absf(a[i] - b[i]))
	return worst


func _ray_ground(x: float, z: float) -> float:
	var space := demo.get_viewport().world_3d.direct_space_state
	var top := demo.ground_height(Vector3(x, 0, z)) + 30.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, top - 60.0, z))
	var hit := space.intersect_ray(q)
	return hit.position.y if not hit.is_empty() else NAN


func _groundwork(origin: Vector3) -> Dictionary:
	var out := {}
	var rig := demo.rts_camera
	var def := StructureCatalog.get_def(&"barracks")
	var spot := Vector3.INF
	var chk := {}
	for r: float in [300.0, 600.0, 900.0, 1300.0, 1800.0, 2400.0, 3000.0, 3800.0, 4600.0]:
		for k in 64:
			var a := k * TAU / 64.0
			var p := demo.on_ground(origin.x + cos(a) * r, origin.z + sin(a) * r, 0.0)
			if absf(p.x) > 9500.0 or absf(p.z) > 9500.0 or _road_dist(p) < 40.0 or _settlement_dist(p)[0] < 60.0:
				continue
			var sl := _slope_at(p, 5.0)
			if sl < 9.0 or sl > 17.0:
				continue
			var so := _solids(p, 14.0)
			if so.trees + so.rocks + so.houses > 0 or not _dry(p, 12.0):
				continue
			var c := sm.check_building(def, p, 0.0, -1, true)
			if c.ok and c.level_m >= 0.6:
				spot = p
				chk = c
				break
		if spot.is_finite():
			break
	if not spot.is_finite():
		_expect(false, "no sloped spot for the groundwork check")
		return out
	out.spot = _describe(spot)
	out.slope_5m_deg = snappedf(_slope_at(spot, 5.0), 0.1)
	out.check = {"level_m": chk.level_m, "pad_y": snappedf(chk.xform.origin.y + def.sink, 0.01)}
	var gap: float = chk.level_m * 2.0
	out.old_rule = "refused (uneven %.1f m > %.1f m)" % [gap, def.max_ground_gap] if gap > def.max_ground_gap else "accepted"
	rig.frame(spot, 0.6, 60.0)
	await _seconds(3.0)
	# Physics read-back on untouched ground: the shape layout is understood exactly.
	sm._patch_collision(Rect2(spot.x - 12.0, spot.z - 12.0, 24.0, 24.0))
	out.collision_readback_delta_m = snappedf(sm.timings.get("collision_patch_delta_m", -1.0), 0.0001)
	_expect(out.collision_readback_delta_m >= 0.0 and out.collision_readback_delta_m < 0.02, "terrain collision read-back does not match Terrain3D (%.3f m)" % out.collision_readback_delta_m)
	var before := _grid(spot, 18.0)
	# A fence through the future blend zone first: it must follow the ground afterwards.
	var fence: StructureState = await _draw_line(&"fence", [spot + Vector3(-14, 0, 5.5), spot + Vector3(14, 0, 5.5)], true)
	var t_place := Time.get_ticks_usec()
	var b: StructureState = await _place(&"barracks", spot, 0)
	out.place_call_ms = (Time.get_ticks_usec() - t_place) / 1000.0
	out.built = b != null
	out.timings = sm.timings.duplicate()
	_expect(b != null, "barracks not built on uneven ground with groundwork (%s)" % con.check.get("reason", ""))
	if b == null:
		return out
	var pad_y := b.instances[0].origin.y + def.sink
	var obb := StructureManager._obb(def, b.instances[0])
	var corner_err := 0.0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var q: Vector2 = obb[0] + (obb[1] as Vector2) * sx * (obb[3].x - 0.3) + (obb[2] as Vector2) * sz * (obb[3].y - 0.3)
			corner_err = maxf(corner_err, absf(demo.ground_height(Vector3(q.x, 0, q.y)) - pad_y))
	out.footprint_corner_error_m = snappedf(corner_err, 0.001)
	_expect(corner_err < 0.05, "terrain under the footprint is not at the pad height (%.2f m)" % corner_err)
	# Collision in the blend zone (outside the building's own boxes) follows the new ground.
	await _physics(3)
	var col_err := 0.0
	var probes := 0
	for k in 8:
		var a := k * TAU / 8.0
		var q: Vector2 = obb[0] + Vector2(cos(a), sin(a)) * ((obb[3] as Vector2).length() + 2.0)
		var ray := _ray_ground(q.x, q.y)
		if is_nan(ray):
			continue
		probes += 1
		col_err = maxf(col_err, absf(ray - demo.ground_height(Vector3(q.x, 0, q.y))))
	out.blend_collision_error_m = snappedf(col_err, 0.001)
	out.blend_collision_probes = probes
	_expect(probes >= 6 and col_err < 0.15, "terrain collision does not follow the levelled ground (%.2f m, %d probes)" % [col_err, probes])
	var fence_gap := _max_gap(fence) if fence else -1.0
	out.fence_ground_gap_after_m = snappedf(fence_gap, 0.01)
	_expect(fence != null and fence_gap < 0.2, "fence in the groundwork zone does not follow the levelled ground (%.2f m)" % fence_gap)
	out.max_terrain_change_m = snappedf(_max_diff(before, _grid(spot, 18.0)), 0.01)
	# The navmesh's cached terrain faces were patched in place: compare with a fresh copy.
	var nav := demo.navigation
	if not nav._faces_key.is_empty():
		var nh := nav.area_size * 0.5
		var fresh := demo.terrain.generate_nav_mesh_source_geometry(AABB(Vector3(nav.area_center.x - nh, -2000.0, nav.area_center.z - nh), Vector3(nav.area_size, 6000.0, nav.area_size)), false)
		var fd := 0.0
		if fresh.size() == nav._faces.size():
			for i in fresh.size():
				fd = maxf(fd, absf(fresh[i].y - nav._faces[i].y))
		else:
			fd = INF
		out.nav_faces_patch_error_m = snappedf(fd, 0.001) if fd < INF else -1.0
		_expect(fd < 0.01, "patched navmesh terrain faces differ from Terrain3D (%.3f m)" % fd)
	else:
		out.nav_faces_patch_error_m = -2.0
	con.clear_tool()
	if shots:
		rig.frame(spot, 0.9, 30.0)
		await _seconds(1.5)
		_shot("groundwork_slope_rts")
	# Removal restores the ground; building again re-levels it.
	cs.remove(b.id)
	await _physics(3)
	out.restored_max_diff_m = snappedf(_max_diff(before, _grid(spot, 18.0)), 0.001)
	_expect(out.restored_max_diff_m < 0.01, "removing the building did not restore the ground (%.3f m)" % out.restored_max_diff_m)
	b = await _place(&"barracks", spot, 0)
	out.rebuilt = b != null
	out.center = spot
	return out


func _small_build(kind: String, c: Vector3) -> Dictionary:
	var rig := demo.rts_camera
	var out := {"spot": _describe(c)}
	var b: StructureState = await _place(&"barracks", c, 0)
	out.building = b != null
	out.building_reason = "" if b else con.check.get("reason", "")
	var line_type := &"hesco" if kind == "slope" else &"fence"
	var pts := [c + Vector3(-14, 0, -10), c + Vector3(14, 0, -10), c + Vector3(14, 0, 12)]
	var ln: StructureState = await _draw_line(line_type, pts, true)
	out.line = _line_info(ln)
	if kind == "slope":
		var f2: StructureState = await _draw_line(&"fence", [c + Vector3(-14, 0, 14), c + Vector3(-14, 0, -6)], true)
		out.fence = _line_info(f2)
		out.max_module_ground_gap_m = snappedf(_max_gap(ln), 0.01)
	if ln:
		var gaps := []
		for i in ln.instances.size():
			gaps.append(snappedf(ln.instances[i].origin.y - demo.ground_height(ln.instances[i].origin), 0.01))
		out.line_y_minus_ground = [gaps.min(), gaps.max()]
	_expect(b != null, "%s: barracks not placed (%s)" % [kind, out.building_reason])
	_expect(ln != null and ln.built_count() > 0, "%s: %s line not built" % [kind, line_type])
	if shots:
		rig.frame(c + Vector3(0, 0, 2), 0.8 if kind != "slope" else 1.6, 60.0 if kind != "slope" else 45.0)
		await _seconds(1.5)
		_shot("env_%s_rts" % kind)
	return out


## Largest vertical distance between a line module's ends and the terrain below.
func _max_gap(s: StructureState) -> float:
	if s == null:
		return -1.0
	var def := StructureCatalog.get_def(s.type_id)
	var worst := 0.0
	for i in s.instances.size():
		var xf := s.instances[i]
		for sx: float in [-0.5, 0.5]:
			var p := xf * Vector3(sx * def.module_length, def.sink, 0)
			worst = maxf(worst, absf(p.y - demo.ground_height(p)))
	return worst


func _open_base(c: Vector3) -> Dictionary:
	var rig := demo.rts_camera
	var info := {}
	var placed := {}
	var hx := 45.0
	var hz := 35.0
	var corners := [c + Vector3(-hx, 0, -hz), c + Vector3(hx, 0, -hz), c + Vector3(hx, 0, hz), c + Vector3(-hx, 0, hz), c + Vector3(-hx, 0, -hz)]
	var perim: StructureState = await _draw_line(&"hesco", corners, false)
	info.perimeter = _line_info(perim)
	_expect(perim != null and perim.points.size() == 5, "open base HESCO perimeter did not close")
	# Entrance: 6 cells in the middle of the south wall.
	if perim:
		var seg2: Array[int] = []
		var mods := ModularLine.modules(StructureCatalog.get_def(&"hesco"), perim.points)
		for i in mods.size():
			if mods[i].segment == 2:
				seg2.append(i)
		var mid := seg2.size() / 2
		for k in range(mid - 3, mid + 3):
			cs.remove_module(perim.id, seg2[k])
	placed.cp = await _place(&"command_post", c + Vector3(0, 0, -16), 0)
	placed.b1 = await _place(&"barracks", c + Vector3(-28, 0, -6), 6)
	placed.b2 = await _place(&"barracks", c + Vector3(-28, 0, 4), 6)
	placed.b3 = await _place(&"barracks", c + Vector3(-28, 0, 14), 6)
	placed.storage = await _place(&"supply_storage", c + Vector3(24, 0, 14), 0)
	placed.shelter = await _place(&"vehicle_shelter", c + Vector3(26, 0, -12), 0)
	placed.t1 = await _place(&"guard_tower", c + Vector3(-hx + 5, 0, -hz + 5), 0)
	placed.t2 = await _place(&"guard_tower", c + Vector3(hx - 5, 0, -hz + 5), 0)
	var chic: StructureState = await _draw_line(&"concrete_barrier", [c + Vector3(-12, 0, hz + 8), c + Vector3(-3, 0, hz + 8), c + Vector3(-3, 0, hz + 13)], true)
	info.placed = placed.keys().filter(func(k: String) -> bool: return placed[k] != null)
	info.concrete = _line_info(chic)
	info.structures = cs.count()
	_expect(placed.values().all(func(s: Variant) -> bool: return s != null), "a building of the open base could not be placed")
	if shots:
		rig.frame(c + Vector3(0, 0, 4), 0.65, 210.0)
		await _seconds(2.0)
		_shot("open_base_rts")
	return {"info": info, "perim_id": perim.id if perim else -1, "center": c, "placed": placed,
		"inside": demo.on_ground(c.x + 14.0, c.z + 24.0, 0.25), "outside": demo.on_ground(c.x + 30.0, c.z + hz + 22.0, 0.25),
		"wall_north": demo.on_ground(c.x + 10.0, c.z - hz - 25.0, 0.25)}


## A soldier record placed inside walks out; the detailed tier gives it a body and a
## navmesh path. Checks it never enters the given line structures.
func _walk_out(inside: Vector3, outside: Vector3, line_ids: Array, shot_name: String) -> Dictionary:
	var rig := demo.rts_camera
	rig.frame(inside.lerp(outside, 0.5), 0.0, 90.0)
	await _seconds(2.0)
	var map := demo.navigation.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, inside, outside, true)
	var plen := 0.0
	for i in path.size() - 1:
		plen += path[i].distance_to(path[i + 1])
	var walker := demo.sim.state.add_unit(UnitState.Kind.SOLDIER, 0, inside, 0.0, "N-Walker")
	await _physics(10)
	demo.sim.state.issue_move(walker.id, outside)
	var in_wall := 0
	var t0 := Time.get_ticks_msec()
	var shot_done := shot_name == ""
	var worst := 0.0
	var trail := []
	var next_sample := 0
	while Time.get_ticks_msec() - t0 < 40000 and walker.move_state == UnitState.MoveState.MOVING:
		var tf := Time.get_ticks_usec()
		await tree.physics_frame
		worst = maxf(worst, (Time.get_ticks_usec() - tf) / 1000.0)
		if Time.get_ticks_msec() - t0 >= next_sample:
			next_sample += 2000
			trail.append([snappedf(walker.position.x - inside.x, 0.1), snappedf(walker.position.z - inside.z, 0.1)])
		for id in line_ids:
			var s := cs.get_structure(id)
			if s and _inside_line(walker.position, s, 0.1):
				in_wall += 1
		if not shot_done and shots and Time.get_ticks_msec() - t0 > 5000:
			shot_done = true
			demo.rts.select([walker.id])
			rig.frame(walker.position, 0.4, 24.0)
			await _frames(20)
			_shot(shot_name)
	var out := {"path_points": path.size(), "path_len_m": snappedf(plen, 0.1), "straight_m": snappedf(_flat(inside, outside), 0.1),
		"has_body": walker.has_body, "state": walker.move_state, "end_error_m": snappedf(_flat(walker.position, outside), 0.01),
		"frames_inside_walls": in_wall, "seconds": (Time.get_ticks_msec() - t0) / 1000.0, "worst_physics_wait_ms": snappedf(worst, 0.1),
		"structure_obstructions": demo.detail.last_bake.get("structure_obstructions", 0), "trail_rel": trail}
	var wb := demo.sim.body_of(walker.id) as SoldierBody
	if wb:
		var ap := []
		for q in wb.nav.get_current_navigation_path():
			ap.append([snappedf(q.x - inside.x, 0.1), snappedf(q.z - inside.z, 0.1)])
		out["agent_path_rel"] = ap
	var mp := []
	for q in path:
		mp.append([snappedf(q.x - inside.x, 0.1), snappedf(q.z - inside.z, 0.1)])
	out["map_path_rel"] = mp
	if walker.move_state != UnitState.MoveState.ARRIVED and wb:
		# What holds the body: colliders touching a slightly larger capsule around it.
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.7
		cap.height = 1.9
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, wb.global_position + Vector3.UP * 0.95)
		q.exclude = [wb.get_rid()]
		var hits := []
		for hit in demo.get_viewport().world_3d.direct_space_state.intersect_shape(q, 16):
			var col: Object = hit.collider
			var desc := str(col)
			if col is Node:
				desc = "%s/%s" % [(col as Node).get_parent().name if (col as Node).get_parent() else "", (col as Node).name]
			if col is CollisionObject3D:
				var co := col as CollisionObject3D
				var owner_node: Object = co.shape_owner_get_owner(co.shape_find_owner(hit.shape))
				if owner_node is Node3D:
					var sp: Vector3 = (owner_node as Node3D).global_position
					desc += " shape@rel (%.1f, %.1f, %.1f)" % [sp.x - wb.global_position.x, sp.y - wb.global_position.y, sp.z - wb.global_position.z]
			hits.append(desc)
		out["stuck_at"] = _v(wb.global_position)
		out["stuck_colliders"] = hits
		out["stuck_velocity"] = _v(wb.velocity)
	_expect(walker.has_body and walker.move_state == UnitState.MoveState.ARRIVED and in_wall == 0 and plen > _flat(inside, outside) + 2.0,
		"soldier did not walk around the barriers to the target (%s)" % JSON.stringify(out))
	return out


# --- Performance --------------------------------------------------------------------

func _perf_base(big: Dictionary) -> Dictionary:
	var out := {}
	var rig := demo.rts_camera
	var c: Vector3 = big.center
	# Placement and removal hitches (a barracks through the controller, then deleted).
	rig.frame(c, 0.6, 150.0)
	await _seconds(1.5)
	_press(KEY_B)
	await _frames(2)
	con.select_type(&"barracks")
	con.yaw = 0.0
	var g := demo.on_ground(c.x + 8.0, c.z + 4.0, 0.0)
	await _cursor_at(g)
	var n := cs.count()
	_click(MOUSE_BUTTON_LEFT, _screen(g))
	var place_worst := await _worst_frame(1.5)
	var tmp: StructureState = cs.all()[-1] if cs.count() > n else null
	var timings_place := sm.timings.duplicate()
	var remove_worst := -1.0
	if tmp:
		cs.remove(tmp.id)
		remove_worst = await _worst_frame(1.5)
	con.clear_tool()
	_press(KEY_B)
	await _frames(2)
	out.placement = {"worst_frame_ms": place_worst, "timings": timings_place, "nav": demo.detail.last_bake.duplicate()}
	out.removal = {"worst_frame_ms": remove_worst}
	rig.frame(c, 0.6, 150.0)
	out.rts_150m = await _measure(240)
	rig.frame(c, 0.6, 300.0)
	out.rts_300m = await _measure(240)
	rig.frame(c, 0.6, 15.0)
	out.rts_15m = await _measure(120)
	# FPS inside the base (possess a soldier there).
	var u := demo.sim.state.add_unit(UnitState.Kind.SOLDIER, 0, big.inside, 0.0, "N-Inspector")
	rig.frame(big.inside, 0.0, 60.0)
	await _physics(20)
	demo.rts.select([u.id])
	_press(KEY_P)
	await _physics(15)
	var body := demo.game.possessed_body()
	if body:
		body.teleport(demo.on_ground(c.x + 2.0, c.z + 6.0, 0.3), 0.0)
		await _physics(5)
		_aim(body, (big.placed.cp as StructureState).instances[0].origin + Vector3(0, 1.5, 0))
		await _seconds(1.0)
		if shots:
			_shot("fps_inside_open_base")
		out.fps_in_base = await _measure(240)
		# FPS walk into the HESCO wall: stops at it.
		var perim := cs.get_structure(big.perim_id)
		body.teleport(demo.on_ground(c.x + 10.0, c.z - 35.0 + 4.5, 0.3), 0.0)
		await _physics(10)
		Input.action_press("move_forward")
		for i in 3 * Engine.physics_ticks_per_second:
			await tree.physics_frame
		Input.action_release("move_forward")
		out.fps_wall = {"stopped_z_from_wall": snappedf(body.global_position.z - (c.z - 35.0), 0.01), "passed": body.global_position.z < c.z - 35.0}
		_expect(not out.fps_wall.passed, "possessed soldier walked through the HESCO wall on the reference world")
		if shots:
			body.teleport(demo.on_ground(c.x - 40.0, c.z - 29.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, c + Vector3(-45.0, 1.0, -35.0))
			await _seconds(1.0)
			_shot("fps_hesco_corner")
			body.teleport(demo.on_ground(c.x - 2.0, c.z + 35.0 + 14.0, 0.3), 0.0)
			await _physics(5)
			_aim(body, c + Vector3(0, 1.0, 35.0))
			await _seconds(1.0)
			_shot("fps_base_entrance")
		_press(KEY_TAB)
		await _physics(5)
	if shots:
		rig.frame(c + Vector3(0, 0, 4), 2.4, 110.0)
		await _seconds(1.5)
		_shot("rts_same_base")
	return out


func _perf_forest(origin: Vector3) -> Dictionary:
	var out := {}
	var dense := Vector3.INF
	for r: float in [400.0, 800.0, 1200.0, 1800.0, 2500.0, 3500.0]:
		for k in 48:
			var a := k * TAU / 48.0
			var p := demo.on_ground(origin.x + cos(a) * r, origin.z + sin(a) * r, 0.0)
			if _solids(p, 25.0).trees >= 40 and _slope_at(p, 6.0) < 12.0 and _dry(p, 5.0):
				dense = p
				break
		if dense.is_finite():
			break
	out.dense_forest_spot = _describe(dense) if dense.is_finite() else null
	if not dense.is_finite():
		return out
	var u := demo.sim.state.add_unit(UnitState.Kind.SOLDIER, 0, dense + Vector3.UP * 0.3, 0.0, "N-Forester")
	var rig := demo.rts_camera
	var t := Time.get_ticks_usec()
	rig.frame(dense, 0.0, 60.0)
	var jump_worst := await _worst_frame(1.5)
	await _seconds(1.0)
	out.rts_jump_to_forest = {"worst_frame_ms": jump_worst, "dist_m": snappedf(_flat(dense, demo.sites[0].position), 1.0), "nav": demo.detail.last_bake.duplicate()}
	await _physics(20)
	demo.rts.select([u.id])
	_press(KEY_P)
	await _physics(15)
	var body := demo.game.possessed_body()
	if body:
		await _seconds(2.0)
		out.fps_dense_forest = await _measure(240)
		out.fps_dense_forest.veg = demo.vegetation.get_stats()
		if shots:
			_shot("fps_dense_forest")
		_press(KEY_TAB)
		await _physics(5)
	return out


# --- Abstract tier, travel, save / load ---------------------------------------------

func _abstract_wall(big: Dictionary) -> Dictionary:
	var rig := demo.rts_camera
	var c: Vector3 = big.center
	var perim := cs.get_structure(big.perim_id)
	# The camera goes to another site (> 2 km): the base's surroundings become abstract.
	var far: Vector3 = demo.sites[2].position if _flat(demo.sites[2].position, c) > _flat(demo.sites[1].position, c) else demo.sites[1].position
	rig.frame(far, 0.0, 150.0)
	await _seconds(2.0)
	var a := demo.sim.state.add_unit(UnitState.Kind.SOLDIER, 0, big.wall_north, 0.0, "N-Abstract")
	var b := demo.sim.state.add_unit(UnitState.Kind.SOLDIER, 0, demo.on_ground(c.x + 0.5, c.z + 57.0, 0.25), 0.0, "N-Abstract-Gate")
	await _physics(5)
	# a: north of the wall, ordered to the base centre (straight through the wall).
	# b: south of the entrance, ordered straight through the opening.
	demo.sim.state.issue_move(a.id, demo.on_ground(c.x + 10.0, c.z, 0.25))
	demo.sim.state.issue_move(b.id, demo.on_ground(c.x + 0.5, c.z + 10.0, 0.25))
	var in_wall := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000 and (a.move_state == UnitState.MoveState.MOVING or b.move_state == UnitState.MoveState.MOVING):
		await tree.physics_frame
		for u in [a, b]:
			if _inside_line(u.position, perim, 0.0):
				in_wall += 1
	var out := {"camera_dist_m": snappedf(_flat(far, c), 1.0), "a_has_body": a.has_body, "b_has_body": b.has_body,
		"a_state": a.move_state, "a_pos_rel": [snappedf(a.position.x - c.x, 0.1), snappedf(a.position.z - c.z, 0.1)],
		"b_state": b.move_state, "b_pos_rel": [snappedf(b.position.x - c.x, 0.1), snappedf(b.position.z - c.z, 0.1)],
		"frames_inside_wall": in_wall, "seconds": (Time.get_ticks_msec() - t0) / 1000.0}
	_expect(not a.has_body and not b.has_body, "abstract test units got bodies (camera too close)")
	_expect(in_wall == 0, "an abstract soldier walked through the HESCO wall")
	_expect(b.move_state == UnitState.MoveState.ARRIVED, "an abstract soldier did not pass through the base entrance")
	return out


func _travel(forest: Dictionary, big: Dictionary) -> Dictionary:
	var rig := demo.rts_camera
	var snap_before: Dictionary = cs.to_dict()
	var xf_before := _all_instances()
	var check_id: int = forest.get("check_struct", -1)
	var s := cs.get_structure(check_id)
	var trunks_before := _trunks_inside(s, 0.0) if s else -1
	# Far corner of the map, then back to the forest base.
	var far := demo.on_ground(-8500.0 if forest.inside.x > 0 else 8500.0, -8500.0 if forest.inside.z > 0 else 8500.0, 0.0)
	rig.frame(far, 0.0, 150.0)
	var jump_out := await _worst_frame(2.0)
	await _seconds(2.0)
	var away := sm.stats()
	var veg_away := demo.vegetation.get_stats()
	var forest_base_cells_loaded := demo.vegetation.chunks.has(VegetationChunk.chunk_of(forest.inside, 1024.0))
	rig.frame(forest.inside, 0.5, 70.0)
	var jump_back := await _worst_frame(2.0)
	var nav_back := demo.detail.last_bake.duplicate()
	for i in 300:
		await tree.process_frame
		if demo.vegetation.is_settled():
			break
	await _seconds(1.0)
	var back := sm.stats()
	var veg_back := demo.vegetation.get_stats()
	var trunks_after := _trunks_inside(s, 0.0) if s else -1
	var drawn_after := _drawn_in_cells(s) if s else -1
	var same := JSON.stringify(cs.to_dict()) == JSON.stringify(snap_before)
	var out := {"far_dist_m": snappedf(_flat(far, forest.inside), 1.0), "jump_out_worst_ms": jump_out, "jump_back_worst_ms": jump_back,
		"nav_back": nav_back, "away": away, "back": back, "veg_away": veg_away, "veg_back": veg_back, "forest_chunk_unloaded_while_away": not forest_base_cells_loaded,
		"records_identical": same, "instance_transforms_identical": _all_instances() == xf_before,
		"trunks_in_cleared_footprint_before_after": [trunks_before, trunks_after], "drawn_instances_base_cells_after": drawn_after,
		"drawn_instances_base_cells_before": forest.get("drawn_instances_base_cells", -1)}
	_expect(away.visible_cells == 0 and away.collision_cells == 0, "distant bases still have structure nodes")
	_expect(same and back.visible_cells > 0, "construction changed after the trip")
	_expect(trunks_after == 0 and drawn_after == forest.get("drawn_instances_base_cells", -2), "cleared vegetation came back after streaming (%d trunks, drawn %d vs %d)" % [trunks_after, drawn_after, forest.get("drawn_instances_base_cells", -1)])
	if shots:
		await _seconds(1.0)
		_shot("forest_base_after_trip")
	return out


func _save_load(forest: Dictionary) -> Dictionary:
	var snap_before: Dictionary = cs.to_dict()
	var xf_before := _all_instances()
	var sq_basis := Basis(Vector3.UP, forest.yaw)
	var sq_built := _trunks_in_square(forest.center, sq_basis, 15.0)
	var gw_at: Vector3 = results.get("groundwork", {}).get("center", Vector3.INF)
	var gw_saved := _grid(gw_at, 18.0) if gw_at.is_finite() else PackedFloat32Array()
	_press(KEY_F5)
	await _frames(2)
	var saved_text := FileAccess.get_file_as_string(con.save_path)
	cs.clear()
	await _seconds(1.0)
	# Without the base the trees are back (the chunk data was never changed).
	var trunks_cleared_state := _trunks_in_square(forest.center, sq_basis, 15.0)
	var gw_cleared := _grid(gw_at, 18.0) if gw_at.is_finite() else PackedFloat32Array()
	_press(KEY_F9)
	await _seconds(1.0)
	var trunks_loaded := _trunks_in_square(forest.center, sq_basis, 15.0)
	var restored := JSON.stringify(cs.to_dict()) == JSON.stringify(snap_before)
	var gw_loaded := _grid(gw_at, 18.0) if gw_at.is_finite() else PackedFloat32Array()
	var out := {"path": ProjectSettings.globalize_path(con.save_path), "bytes": saved_text.length(), "format": snap_before.get("format"),
		"clearings": snap_before.clearings.size(), "square_trunks_built": sq_built, "square_trunks_after_clear": trunks_cleared_state, "square_trunks_after_load": trunks_loaded,
		"identical_after_load": restored, "max_instance_offset_m": snappedf(_max_offset(_all_instances(), xf_before), 0.0001),
		"groundwork_cleared_vs_saved_m": snappedf(_max_diff(gw_saved, gw_cleared), 0.001), "groundwork_loaded_vs_saved_m": snappedf(_max_diff(gw_saved, gw_loaded), 0.001),
		"nav_structure_obstructions": demo.detail.last_bake.get("structure_obstructions", 0)}
	_expect(restored and _max_offset(_all_instances(), xf_before) < 0.005, "save/load did not restore the bases")
	if gw_at.is_finite():
		_expect(_max_diff(gw_saved, gw_cleared) > 0.3 and _max_diff(gw_saved, gw_loaded) < 0.01, "groundwork not removed by clear / not restored by load")
	_expect(trunks_cleared_state > sq_built and trunks_loaded == sq_built, "clearings were not restored by load (vegetation in the base square %d built, %d cleared state, %d loaded)" % [sq_built, trunks_cleared_state, trunks_loaded])
	return out


# --- Output -------------------------------------------------------------------------

func _shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/wi01_%s.jpg" % [_shot_dir, name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.88)
	print("WI01 shot: ", path)


func _log(name: String, data: Dictionary) -> void:
	results[name] = data
	print("WI01 %s %s" % [name, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("WI01 FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/integration_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("WI01 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()
