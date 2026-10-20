## Route planning for wheeled vehicles (LOGISTICS-01).
##
## One road network: this class does not store roads, it indexes the vertices of
## RoadNetwork (the world's roads and the roads the player built) as an AStar3D graph so a
## vehicle can be routed along them: consecutive vertices are linked, vertices of different
## roads that lie within LINK_M of each other are linked (junctions and crossings), bridges
## are simply vertices of the road. Built roads are added and removed as the network changes.
##
## A route is road legs joined by cross-country legs: from the start to the road, along the
## roads, from the road to the destination. Cross-country legs are straight when the ground
## allows it, else found on a local 3 m grid that knows slopes, water and the footprints of
## structures (so a vehicle finds a base's gate), else on the 50 m strategic grid (rivers and
## cliffs). The cheapest of "cross-country all the way" and a few road candidates wins. The
## result is one dense polyline (about 3 m apart) with a speed ceiling per point; the
## vehicle's curve and braking speed profile is derived from it by VehicleSim.
class_name VehicleRouter
extends RefCounted

const HASH := 12.0
## Vertices of two roads closer than this are one junction.
const LINK_M := 10.5
## Cost units are metres on the fastest road class (weight 1.0 = primary road, whose travel
## cost is 0.4 in RoadNetwork); AStar3D's straight-line estimate then never overestimates.
const ROAD_UNIT := 0.4
const OFFROAD_COST := 3.0
## Road candidates tried at each end, and how far a road may be from the endpoint (m).
const CANDIDATES := 3
const SNAP_RADIUS := 700.0
const LEG_CELL := 3.0
const LEG_MAX_CELLS := 60000

var net: RoadNetwork
var routes: StrategicRoutes
var terrain: Terrain3D
var structures: StructureManager

var astar := AStar3D.new()
var built := false
var build_ms := 0.0
var plans := 0
var plan_ms_total := 0.0
var plan_ms_max := 0.0
var last_plan_ms := 0.0

var _next_id := 0
## node id -> Road (null once removed)
var _node_road: Array = []
## Vector2i -> Array[int]
var _cells := {}
## road key -> PackedInt32Array of node ids
var _ids_of := {}
var _dirty := false
## Roads narrower than this (vehicle width + 1 m of margin) cost far more.
var min_width := 4.5
var debug_legs := false
var last_leg_debug := ""


func setup(p_net: RoadNetwork, p_routes: StrategicRoutes, p_terrain: Terrain3D, p_structures: StructureManager) -> void:
	net = p_net
	routes = p_routes
	terrain = p_terrain
	structures = p_structures
	if not net.changed.is_connected(_on_changed):
		net.changed.connect(_on_changed)


func _on_changed(_rect: Rect2) -> void:
	_dirty = true


## Builds the graph on first use (about half a second for the 124 world roads).
func ensure_built() -> void:
	if not built:
		var t0 := Time.get_ticks_usec()
		astar.clear()
		_next_id = 0
		_node_road.clear()
		_cells.clear()
		_ids_of.clear()
		for r: RoadNetwork.Road in net.world:
			_add_road(r)
		for r: RoadNetwork.Road in net.built.values():
			_add_road(r)
		for r: RoadNetwork.Road in net.all_roads():
			for id in _ids_of[r.key]:
				_link_junctions(id)
		built = true
		_dirty = false
		build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	elif _dirty:
		_sync_built()


func _sync_built() -> void:
	_dirty = false
	for key in _ids_of.keys():
		if key > 0 and not net.built.has(key):
			_remove_road(key)
	for r: RoadNetwork.Road in net.built.values():
		if not _ids_of.has(r.key):
			_add_road(r)
			for id in _ids_of[r.key]:
				_link_junctions(id)


func node_count() -> int:
	return astar.get_point_count()


func _weight(r: RoadNetwork.Road, grade: float) -> float:
	var w := r.travel_cost / ROAD_UNIT
	if r.width < min_width:
		w *= 40.0
	return w * (1.0 + maxf(0.0, grade - 0.10) * 8.0)


func _add_road(r: RoadNetwork.Road) -> void:
	var ids := PackedInt32Array()
	var pts := r.points
	for k in pts.size():
		var id := _next_id
		_next_id += 1
		var grade := 0.0
		for j in [k - 1, k + 1]:
			if j >= 0 and j < pts.size():
				var l := Vector2(pts[j].x - pts[k].x, pts[j].z - pts[k].z).length()
				if l > 0.5:
					grade = maxf(grade, absf(pts[j].y - pts[k].y) / l)
		astar.add_point(id, pts[k], _weight(r, grade))
		_node_road.append(r)
		ids.append(id)
		var c := Vector2i(floori(pts[k].x / HASH), floori(pts[k].z / HASH))
		if not _cells.has(c):
			_cells[c] = []
		_cells[c].append(id)
		if k > 0:
			astar.connect_points(ids[k - 1], id, true)
	_ids_of[r.key] = ids


func _remove_road(key: int) -> void:
	for id in _ids_of[key]:
		var p := astar.get_point_position(id)
		var c := Vector2i(floori(p.x / HASH), floori(p.z / HASH))
		var list: Array = _cells.get(c, [])
		list.erase(id)
		astar.remove_point(id)
		_node_road[id] = null
	_ids_of.erase(key)


func _link_junctions(id: int) -> void:
	var p := astar.get_point_position(id)
	var road: RoadNetwork.Road = _node_road[id]
	var c := Vector2i(floori(p.x / HASH), floori(p.z / HASH))
	var best := {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: int in _cells.get(c + Vector2i(dx, dz), []):
				var rr: RoadNetwork.Road = _node_road[other]
				if rr == road or rr == null:
					continue
				var q := astar.get_point_position(other)
				var d := Vector2(p.x - q.x, p.z - q.z).length()
				if d <= LINK_M and (not best.has(rr.key) or d < best[rr.key][0]):
					best[rr.key] = [d, other]
	for key in best:
		var other: int = best[key][1]
		if not astar.are_points_connected(id, other):
			astar.connect_points(id, other, true)


## The closest graph vertices to p, at most `count`, on different roads, within `radius`
## (flat distance): [{id, pos, dist, road}].
func nearest_nodes(p: Vector3, count: int, radius: float) -> Array:
	var found: Array = []
	var seen_roads := {}
	var rings := ceili(radius / HASH)
	var c := Vector2i(floori(p.x / HASH), floori(p.z / HASH))
	var cand: Array = []
	for r in range(0, rings + 1):
		var offs: Array[Vector2i] = []
		if r == 0:
			offs.append(Vector2i.ZERO)
		else:
			for i in range(-r, r + 1):
				offs.append(Vector2i(i, -r))
				offs.append(Vector2i(i, r))
			for i in range(-r + 1, r):
				offs.append(Vector2i(-r, i))
				offs.append(Vector2i(r, i))
		for o in offs:
			for id: int in _cells.get(c + o, []):
				var q := astar.get_point_position(id)
				cand.append([Vector2(p.x - q.x, p.z - q.z).length(), id])
		# Stop once enough candidates exist and every farther ring is beyond the best of them.
		if cand.size() >= count * 4:
			break
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in cand:
		if e[0] > radius:
			break
		var rd: RoadNetwork.Road = _node_road[e[1]]
		if rd == null or seen_roads.has(rd.key):
			continue
		seen_roads[rd.key] = true
		found.append({"id": e[1], "pos": astar.get_point_position(e[1]), "dist": e[0], "road": rd})
		if found.size() >= count:
			break
	return found


# --- Planning ---------------------------------------------------------------------------

## Plans a route for a vehicle type. Result: {ok, reason, points, caps, length_m, road_m,
## offroad_m, bridges, roads: [names], ms}.
func plan(from: Vector3, to: Vector3, def: VehicleDefs.Def) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	ensure_built()
	var res := _plan(from, to, def)
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	last_plan_ms = res.ms
	plans += 1
	plan_ms_total += res.ms
	plan_ms_max = maxf(plan_ms_max, res.ms)
	return res


func _plan(from: Vector3, to: Vector3, def: VehicleDefs.Def) -> Dictionary:
	if structures and structures.blocks_point(Vector2(to.x, to.z), def.circle_r):
		return _fail("The destination is inside a structure")
	if _wet(to):
		return _fail("The destination is in the water")
	var cands: Array = []
	# 1. Cross-country all the way.
	var direct := _leg(from, to, def)
	if direct.ok:
		cands.append({"cost": _length(direct.pts) * OFFROAD_COST, "legs": [direct], "road": [], "names": []})
	# 2. Via roads: a few road vertices near each end, cheapest road cost first.
	var a_list := nearest_nodes(from, CANDIDATES, SNAP_RADIUS)
	var b_list := nearest_nodes(to, CANDIDATES, SNAP_RADIUS)
	var combos: Array = []
	for a: Dictionary in a_list:
		for b: Dictionary in b_list:
			var ids := astar.get_id_path(a.id, b.id)
			if ids.is_empty():
				continue
			var cost: float = _path_cost(ids) + (a.dist + b.dist) * OFFROAD_COST
			combos.append({"cost": cost, "ids": ids, "a": a, "b": b})
	combos.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.cost < y.cost)
	var tried := 0
	var why: Array = ["direct %s" % direct.ok, "road candidates %d/%d, combos %d" % [a_list.size(), b_list.size(), combos.size()]]
	for cb: Dictionary in combos:
		if tried >= 3:
			break
		tried += 1
		var la := _leg(from, cb.a.pos, def)
		if not la.ok:
			why.append("start leg %.0f m failed" % cb.a.dist)
			continue
		var lb := _leg(cb.b.pos, to, def)
		if not lb.ok:
			why.append("end leg %.0f m failed" % cb.b.dist)
			continue
		var road_pts := PackedVector3Array()
		var names: Array = []
		for id: int in cb.ids:
			road_pts.append(astar.get_point_position(id))
			var rd: RoadNetwork.Road = _node_road[id]
			if rd and not names.has(rd.name):
				names.append(rd.name)
		var cost: float = _path_cost(cb.ids) + (_length(la.pts) + _length(lb.pts)) * OFFROAD_COST
		cands.append({"cost": cost, "legs": [la, lb], "road": cb.ids, "names": names, "road_pts": road_pts})
		break
	if cands.is_empty():
		var f := _fail("No drivable route (water, cliffs or structures in the way)")
		f["why"] = why
		return f
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.cost < y.cost)
	return _assemble(cands[0], from, to, def)


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "points": PackedVector3Array(), "caps": PackedFloat32Array()}


func _path_cost(ids: PackedInt64Array) -> float:
	var total := 0.0
	for i in range(1, ids.size()):
		var a := astar.get_point_position(ids[i - 1])
		var b := astar.get_point_position(ids[i])
		total += Vector2(a.x - b.x, a.z - b.z).length() * astar.get_point_weight_scale(ids[i])
	return total


func _length(pts: PackedVector3Array) -> float:
	return RoadNetwork.length_of(pts)


## Builds the final polyline of a chosen candidate: control points with speed ceilings,
## spline-resampled to about 3 m, heights from the ground (and bridge decks).
func _assemble(cand: Dictionary, from: Vector3, to: Vector3, def: VehicleDefs.Def) -> Dictionary:
	var ctrl := PackedVector3Array()
	var cap := PackedFloat32Array()
	var legs: Array = cand.legs
	var road_m := 0.0
	var off_m := 0.0
	var off_cap := def.offroad_speed
	_append(ctrl, cap, legs[0].pts, off_cap)
	off_m += _length(legs[0].pts)
	if not cand.road.is_empty():
		var ids: PackedInt64Array = cand.road
		for i in ids.size():
			var rd: RoadNetwork.Road = _node_road[ids[i]]
			var c: float = def.class_speed.get(rd.cls, 12.0) if not rd.built else 9.0
			var p := astar.get_point_position(ids[i])
			if ctrl.size() > 0 and Vector2(ctrl[-1].x - p.x, ctrl[-1].z - p.z).length() < 1.0:
				cap[cap.size() - 1] = maxf(cap[cap.size() - 1], c)
				continue
			ctrl.append(p)
			cap.append(c)
			if i > 0:
				road_m += Vector2(p.x - astar.get_point_position(ids[i - 1]).x, p.z - astar.get_point_position(ids[i - 1]).z).length()
		_append(ctrl, cap, legs[1].pts, off_cap)
		off_m += _length(legs[1].pts)
	# Cross-country points that coincide with a road vertex take the road's ceiling.
	var pts := PackedVector3Array()
	var caps := PackedFloat32Array()
	if ctrl.size() < 2:
		ctrl = PackedVector3Array([from, to])
		cap = PackedFloat32Array([off_cap, off_cap])
	var sp := RoadNetwork.spline(ctrl, 3.0)
	var k := 0
	for q in sp:
		# nearest control point at or after the previous one gives the ceiling
		while k + 1 < ctrl.size() and Vector2(q.x - ctrl[k + 1].x, q.z - ctrl[k + 1].z).length() < Vector2(q.x - ctrl[k].x, q.z - ctrl[k].z).length():
			k += 1
		if pts.size() > 0 and Vector2(pts[-1].x - q.x, pts[-1].z - q.z).length() < 0.5:
			continue
		pts.append(q)
		caps.append(cap[k])
	pts[0] = from
	pts[pts.size() - 1] = to
	var bridges := 0
	var on_deck := false
	for i in pts.size():
		var h: float = terrain.data.get_height(pts[i]) if terrain else pts[i].y
		var deck := net.deck_height(pts[i])
		if not is_nan(deck):
			h = deck if is_nan(h) else maxf(h, deck)
			if not on_deck:
				bridges += 1
			on_deck = true
		else:
			on_deck = false
		if not is_nan(h):
			pts[i].y = h
	return {"ok": true, "reason": "", "points": pts, "caps": caps, "length_m": _length(pts), "road_m": road_m,
		"offroad_m": off_m, "bridges": bridges, "roads": cand.names, "cost": cand.cost}


static func _append(ctrl: PackedVector3Array, cap: PackedFloat32Array, pts: PackedVector3Array, c: float) -> void:
	for p in pts:
		if ctrl.size() > 0 and Vector2(ctrl[-1].x - p.x, ctrl[-1].z - p.z).length() < 1.0:
			continue
		ctrl.append(p)
		cap.append(c)


# --- Cross-country legs -----------------------------------------------------------------

func _wet(p: Vector3) -> bool:
	return structures != null and structures.is_wet(p.x, p.z)


func _height(x: float, z: float) -> float:
	return terrain.data.get_height(Vector3(x, 0.0, z)) if terrain else 0.0


## True when a vehicle can drive the straight line a -> b: slopes within the vehicle's grade,
## no water, no structure within its footprint. Bridge decks count as ground.
func line_ok(a: Vector3, b: Vector3, def: VehicleDefs.Def) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, ceili(d / 2.5))
	var prev_h := NAN
	var step := d / n
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var h := _height(p.x, p.z)
		if is_nan(h):
			return false
		if not is_nan(net.deck_height(p)):
			prev_h = NAN
			continue
		if not is_nan(prev_h) and absf(h - prev_h) / maxf(step, 0.1) > def.max_grade:
			return false
		prev_h = h
		if structures and (structures.blocks_point(Vector2(p.x, p.z), def.circle_r) or structures.is_wet(p.x, p.z)):
			return false
	return true


## A cross-country leg a -> b: {ok, pts}.
func _leg(a: Vector3, b: Vector3, def: VehicleDefs.Def) -> Dictionary:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	if d < 1.0:
		return {"ok": true, "pts": PackedVector3Array([a, b])}
	if line_ok(a, b, def):
		return {"ok": true, "pts": PackedVector3Array([a, b])}
	if d <= 500.0:
		var loc := _local_plan(a, b, def)
		if loc.ok:
			return loc
	if d > 150.0 and routes and routes.ready:
		var r := routes.route(a, b, terrain)
		if r.size() >= 2:
			var ok := true
			for i in range(1, r.size()):
				if not line_ok(r[i - 1], r[i], def):
					ok = false
					break
			if ok:
				return {"ok": true, "pts": r}
	return {"ok": false, "pts": PackedVector3Array()}


## A* on a local 3 m grid around the leg: cells are blocked by steep ground, water and
## structure footprints (inflated by the vehicle's collision circle).
func _local_plan(a: Vector3, b: Vector3, def: VehicleDefs.Def) -> Dictionary:
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	var margin := maxf(45.0, Vector2(b.x - a.x, b.z - a.z).length() * 0.35)
	lo -= Vector2.ONE * margin
	hi += Vector2.ONE * margin
	var nx := ceili((hi.x - lo.x) / LEG_CELL)
	var nz := ceili((hi.y - lo.y) / LEG_CELL)
	if nx * nz > LEG_MAX_CELLS:
		return {"ok": false, "pts": PackedVector3Array()}
	var heights := PackedFloat32Array()
	heights.resize((nx + 1) * (nz + 1))
	for z in nz + 1:
		for x in nx + 1:
			heights[z * (nx + 1) + x] = _height(lo.x + x * LEG_CELL, lo.y + z * LEG_CELL)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, nx, nz)
	grid.cell_size = Vector2(LEG_CELL, LEG_CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	var max_dh := def.max_grade * LEG_CELL
	for z in nz:
		for x in nx:
			var h00 := heights[z * (nx + 1) + x]
			var h10 := heights[z * (nx + 1) + x + 1]
			var h01 := heights[(z + 1) * (nx + 1) + x]
			var bad := is_nan(h00) or absf(h10 - h00) > max_dh or absf(h01 - h00) > max_dh
			var cx := lo.x + (x + 0.5) * LEG_CELL
			var cz := lo.y + (z + 0.5) * LEG_CELL
			if not bad and structures:
				bad = structures.blocks_point(Vector2(cx, cz), def.circle_r) or structures.is_wet(cx, cz)
			if bad:
				blocked[z * nx + x] = 1
				grid.set_point_solid(Vector2i(x, z), true)
	var ca := Vector2i(clampi(int((a.x - lo.x) / LEG_CELL), 0, nx - 1), clampi(int((a.z - lo.y) / LEG_CELL), 0, nz - 1))
	var cb := Vector2i(clampi(int((b.x - lo.x) / LEG_CELL), 0, nx - 1), clampi(int((b.z - lo.y) / LEG_CELL), 0, nz - 1))
	ca = _free_cell(blocked, nx, nz, ca)
	cb = _free_cell(blocked, nx, nz, cb)
	if ca.x < 0 or cb.x < 0:
		return {"ok": false, "pts": PackedVector3Array()}
	var path := grid.get_id_path(ca, cb)
	if path.is_empty():
		if debug_legs:
			var rows: Array[String] = []
			for z in nz:
				var row := ""
				for x in nx:
					row += "S" if Vector2i(x, z) == ca else ("G" if Vector2i(x, z) == cb else ("#" if blocked[z * nx + x] == 1 else "."))
				rows.append(row)
			last_leg_debug = "
".join(rows)
		return {"ok": false, "pts": PackedVector3Array()}
	# String-pulling: keep a vertex only where the grid line from the last kept one is blocked.
	var kept: Array[Vector2i] = [path[0]]
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1 and not _grid_clear(blocked, nx, path[i], path[j]):
			j -= 1
		kept.append(path[j])
		i = j
	var pts := PackedVector3Array()
	pts.append(a)
	for c in kept:
		var p := Vector3(lo.x + (c.x + 0.5) * LEG_CELL, 0.0, lo.y + (c.y + 0.5) * LEG_CELL)
		p.y = _height(p.x, p.z)
		pts.append(p)
	pts.append(b)
	# Drop the first/last grid vertex when it only makes a detour back from the end point.
	return {"ok": true, "pts": pts}


static func _free_cell(blocked: PackedByteArray, nx: int, nz: int, c: Vector2i) -> Vector2i:
	if blocked[c.y * nx + c.x] == 0:
		return c
	for r in range(1, 6):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if q.x >= 0 and q.y >= 0 and q.x < nx and q.y < nz and blocked[q.y * nx + q.x] == 0:
					return q
	return Vector2i(-1, -1)


static func _grid_clear(blocked: PackedByteArray, nx: int, a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in range(1, n):
		var t := float(k) / n
		# The line's four neighbouring cells must be free: a 3 m cell grid, 3.3 m vehicles.
		var x := lerpf(a.x, b.x, t)
		var y := lerpf(a.y, b.y, t)
		if blocked[roundi(y) * nx + roundi(x)] == 1:
			return false
		if blocked[floori(y) * nx + floori(x)] == 1 or blocked[ceili(y) * nx + ceili(x)] == 1:
			return false
	return true
