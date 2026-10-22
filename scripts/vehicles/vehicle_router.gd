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
## Right-hand traffic: road points shift this far (m, at most one fifth of the road width) to the right of the travel direction,
## on roads at least LANE_MIN_WIDTH wide.
const LANE_OFFSET_M := 1.9
const LANE_MIN_WIDTH := 6.0
## Road candidates tried at each end, and how far a road may be from the endpoint (m).
const CANDIDATES := 3
const BYPASS_CLEARANCE_M := 1.8
const SNAP_RADIUS := 700.0
## How far a place may be from the main road network and still be routed to it (across country) when its own nearest roads
## are isolated segments.
const MAIN_SNAP_RADIUS := 1500.0
## A dangling road end this close (m) to a vertex of another road is joined to it: the generated village streets stop 10-30 m
## short of the road they belong to (found by RoadAudit), and a vehicle simply drives the few metres across.
const GAP_FIX_M := 32.0
## ... and only when the two heights differ by less than this (m): no join between a road and the one under or over it.
const GAP_FIX_DY := 4.0
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
## NAVIGATION N1 diagnostics; none of these fields affect planning.
var failed_plans := 0
var failure_reasons := {}
var last_failure := {}
var graph_builds := 0
var graph_rebuilds := 0
var graph_ms_total := 0.0
var graph_ms_max := 0.0
var last_rebuild_reason := "initial"

var _next_id := 0
## node id -> Road (null once removed)
var _node_road: Array = []
## Vector2i -> Array[int]
var _cells := {}
## road key -> PackedInt32Array of node ids
var _ids_of := {}
var _dirty := false
## Road vertices switched off because a structure (a wall across the road) blocks them.
var _disabled: Array[int] = []
## Roads narrower than this (vehicle width + 1 m of margin) cost far more.
var min_width := 4.5
## Parked vehicles (not the one being planned) as circles [x, z, radius]: cross-country legs
## and the yard grid steer round them. Set by VehicleSim before every plan.
var parked_circles: Array = []
## Joins made by the gap repair: [{road, to_road, gap_m, at: Vector3}] (RoadAudit reports and draws them).
var repaired_gaps: Array = []
## Connected component of every graph vertex (id -> component number) and the number of the largest one: a place whose nearest
## roads are only a few stray street segments is also offered the nearest vertices of the main network.
var _comp_of := {}
var _main_comp := -1
## Failed plans (see plan()).
var _fail_cache := {}
const FAIL_CACHE_S := 90
## Extra clearance (m) added to the footprint circle while a bypass leg is planned (VehicleSim._try_bypass): a detour has to pass
## with room to spare, not touch the corner of what it goes round.
var _extra := 0.0
var debug_legs := false
var last_leg_debug := ""


func setup(p_net: RoadNetwork, p_routes: StrategicRoutes, p_terrain: Terrain3D, p_structures: StructureManager) -> void:
	net = p_net
	routes = p_routes
	terrain = p_terrain
	structures = p_structures
	if not net.changed.is_connected(_on_changed):
		net.changed.connect(_on_changed)
	if structures and not structures.area_changed.is_connected(_on_structures_changed):
		structures.area_changed.connect(_on_structures_changed)


func _on_changed(_rect: Rect2) -> void:
	_dirty = true
	last_rebuild_reason = "road network changed"
	_fail_cache.clear()


## Structures were built or removed: road vertices disabled because a structure stood on them
## are tried again.
func _on_structures_changed(_rect: Rect2) -> void:
	last_rebuild_reason = "structure area changed"
	_fail_cache.clear()
	for id in _disabled:
		if astar.has_point(id):
			astar.set_point_disabled(id, false)
	_disabled.clear()


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
		repaired_gaps.clear()
		for r: RoadNetwork.Road in net.all_roads():
			_repair_gap_ends(r)
		_compute_components()
		built = true
		_dirty = false
		build_ms = (Time.get_ticks_usec() - t0) / 1000.0
		graph_builds += 1
		graph_ms_total += build_ms
		graph_ms_max = maxf(graph_ms_max, build_ms)
	elif _dirty:
		var t0 := Time.get_ticks_usec()
		_sync_built()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		graph_rebuilds += 1
		graph_ms_total += ms
		graph_ms_max = maxf(graph_ms_max, ms)


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
			_repair_gap_ends(r)
	_compute_components()


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


## Components of the graph (BFS over the AStar3D connections), the largest is the main network.
func _compute_components() -> void:
	_comp_of.clear()
	var sizes := {}
	var next := 0
	for id: int in astar.get_point_ids():
		if _comp_of.has(id):
			continue
		var stack: Array[int] = [id]
		_comp_of[id] = next
		var n := 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			n += 1
			for nb: int in astar.get_point_connections(cur):
				if not _comp_of.has(nb):
					_comp_of[nb] = next
					stack.append(nb)
		sizes[next] = n
		next += 1
	_main_comp = -1
	var best := 0
	for k in sizes:
		if sizes[k] > best:
			best = sizes[k]
			_main_comp = k


## A road end (first / last vertex) that is not joined to any other road: the nearest vertex of another road within GAP_FIX_M
## (and GAP_FIX_DY in height) gets a link. The router graph only; the road meshes stay as generated.
func _repair_gap_ends(r: RoadNetwork.Road) -> void:
	var ids: PackedInt32Array = _ids_of.get(r.key, PackedInt32Array())
	if ids.size() < 2:
		return
	for end_id: int in [ids[0], ids[ids.size() - 1]]:
		var joined := false
		for nb: int in astar.get_point_connections(end_id):
			if _node_road[nb] != r:
				joined = true
		if joined:
			continue
		var p := astar.get_point_position(end_id)
		var c := Vector2i(floori(p.x / HASH), floori(p.z / HASH))
		var best := -1
		var best_d := GAP_FIX_M
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				for other: int in _cells.get(c + Vector2i(dx, dz), []):
					var rr: RoadNetwork.Road = _node_road[other]
					if rr == null or rr == r:
						continue
					var q := astar.get_point_position(other)
					if absf(q.y - p.y) > GAP_FIX_DY:
						continue
					var d := Vector2(p.x - q.x, p.z - q.z).length()
					if d < best_d:
						best_d = d
						best = other
		if best >= 0:
			astar.connect_points(end_id, best, true)
			var rr2: RoadNetwork.Road = _node_road[best]
			repaired_gaps.append({"road": r.name, "to_road": rr2.name, "gap_m": best_d, "at": (p + astar.get_point_position(best)) * 0.5})


## The closest graph vertices to p, at most `count`, on different roads, within `radius`
## (flat distance): [{id, pos, dist, road}]. `accept` (optional Callable(id, pos) -> bool) filters vertices first.
func nearest_nodes(p: Vector3, count: int, radius: float, accept := Callable(), distinct := true) -> Array:
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
				if accept.is_valid() and not accept.call(id, q):
					continue  # filtered here, so the early stop below counts only usable vertices
				cand.append([Vector2(p.x - q.x, p.z - q.z).length(), id])
		# Stop once enough candidates exist and every farther ring is beyond the best of them.
		if cand.size() >= count * 4:
			break
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e: Array in cand:
		if e[0] > radius:
			break
		var rd: RoadNetwork.Road = _node_road[e[1]]
		if rd == null or (distinct and seen_roads.has(rd.key)):
			continue
		seen_roads[rd.key] = true
		found.append({"id": e[1], "pos": astar.get_point_position(e[1]), "dist": e[0], "road": rd})
		if found.size() >= count:
			break
	return found


## Vertices a vehicle may enter the roads from near p: the nearest on distinct roads (as before) and a few more along the
## nearest road, spaced 30 m apart within 300 m - the vertex 16 m away may sit below a bank the vehicle cannot climb while the one
## 50 m along the road is easy.
func _enter_candidates(p: Vector3, free: Callable) -> Array:
	var out := nearest_nodes(p, CANDIDATES, SNAP_RADIUS, free)
	var more := nearest_nodes(p, 40, 160.0, free, false)
	for m: Dictionary in more:
		var far_enough := true
		for o: Dictionary in out:
			if Vector2(o.pos.x - m.pos.x, o.pos.z - m.pos.z).length() < 30.0:
				far_enough = false
				break
		if far_enough and out.size() < CANDIDATES + 4:
			out.append(m)
	return out


## The candidate list always holds a vertex of the main road network when one lies within MAIN_SNAP_RADIUS: a village at the end of a
## few unconnected streets is reached through the nearest road of the network, the last stretch is driven across country.
func _with_main(list: Array, p: Vector3, free: Callable) -> Array:
	if _main_comp < 0:
		return list
	for n: Dictionary in list:
		if _comp_of.get(n.id, -1) == _main_comp:
			return list
	var main_only := func(id: int, pos: Vector3) -> bool:
		return _comp_of.get(id, -1) == _main_comp and free.call(id, pos)
	return list + nearest_nodes(p, 2, MAIN_SNAP_RADIUS, main_only)


## Distance (m) from p to the nearest vertex of the main road network, -1 when it is farther than max_m.
func main_network_distance(p: Vector3, max_m: float) -> float:
	ensure_built()
	var main_only := func(id: int, _pos: Vector3) -> bool:
		return _comp_of.get(id, -1) == _main_comp
	var near := nearest_nodes(p, 1, max_m, main_only)
	return near[0].dist if not near.is_empty() else -1.0


## Can a vehicle get from p onto the road network (the cross-country leg to one of the nearest road vertices)? A road route is
## worth nothing if the vehicle cannot enter it: this is the check for a parking spot, a dock or an assembly point.
## {ok, dist, node, pos} or {ok: false, reason}.
func access_to_road(p: Vector3, def: VehicleDefs.Def) -> Dictionary:
	ensure_built()
	var free := func(_id: int, pos: Vector3) -> bool:
		return structures == null or not structures.blocks_point(Vector2(pos.x, pos.z), def.collide_r + 0.3)
	var cands := _with_main(_enter_candidates(p, free), p, free)
	if cands.is_empty():
		return {"ok": false, "reason": "no road within %d m" % roundi(SNAP_RADIUS)}
	for a: Dictionary in cands:
		var leg := _leg(p, a.pos, def)
		if leg.ok:
			return {"ok": true, "dist": a.dist, "node": a.id, "pos": a.pos, "leg_m": _length(leg.pts)}
	return {"ok": false, "reason": "no drivable way onto the road (nearest road %d m away: water, cliffs or structures in the way)" % roundi(cands[0].dist)}


# --- Planning ---------------------------------------------------------------------------

## Plans a route for a vehicle type. Result: {ok, reason, points, caps, length_m, road_m,
## offroad_m, bridges, roads: [names], ms}.
func plan(from: Vector3, to: Vector3, def: VehicleDefs.Def) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	ensure_built()
	# A route that failed is not searched again for FAIL_CACHE_S (a failed search costs up to a second on bad ground: every
	# leg attempt is a grid search); the key is the two places on a 25 m grid and the vehicle type. Cleared when roads or
	# structures change.
	var key := "%d,%d>%d,%d:%s" % [roundi(from.x / 25.0), roundi(from.z / 25.0), roundi(to.x / 25.0), roundi(to.z / 25.0), def.id]
	var now_ms := Time.get_ticks_msec()
	if _fail_cache.has(key) and now_ms - int(_fail_cache[key].t) < FAIL_CACHE_S * 1000:
		var cached: Dictionary = _fail_cache[key].res.duplicate()
		cached["ms"] = 0.0
		cached["cached"] = true
		_count_plan(cached, from, to, def)
		return cached
	var res := _plan(from, to, def)
	if not res.ok:
		_fail_cache[key] = {"t": now_ms, "res": res}
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_count_plan(res, from, to, def)
	return res


func _count_plan(res: Dictionary, from: Vector3, to: Vector3, def: VehicleDefs.Def) -> void:
	last_plan_ms = float(res.ms)
	plans += 1
	plan_ms_total += last_plan_ms
	plan_ms_max = maxf(plan_ms_max, last_plan_ms)
	if not res.ok:
		failed_plans += 1
		var reason := String(res.get("reason", "unknown"))
		failure_reasons[reason] = int(failure_reasons.get(reason, 0)) + 1
		last_failure = {
			"reason": reason,
			"from": [snappedf(from.x, 0.1), snappedf(from.z, 0.1)],
			"to": [snappedf(to.x, 0.1), snappedf(to.z, 0.1)],
			"vehicle": String(def.id),
			"ms": snappedf(last_plan_ms, 0.01),
		}


func _plan(from: Vector3, to: Vector3, def: VehicleDefs.Def) -> Dictionary:
	if structures and structures.blocks_point(Vector2(to.x, to.z), def.circle_r):
		return _fail("The destination is inside a structure")
	if _wet(to):
		return _fail("The destination is in the water")
	var cands: Array = []
	# 1. Cross-country all the way.
	var direct := _leg(from, to, def)
	if direct.ok:
		cands.append({"cost": _length(direct.pts) * def.offroad_factor, "legs": [direct], "road": [], "names": []})
	# 2. Via roads: a few road vertices near each end, cheapest road cost first.
	# Road vertices inside a structure (a base's perimeter or buildings stand on the road that leads into it) cannot be entered
	# from, or left to: the nearest *free* vertices are the candidates, the cross-country leg (which knows the footprints and
	# finds a gate) does the rest.
	var free := func(_id: int, pos: Vector3) -> bool:
		return structures == null or not structures.blocks_point(Vector2(pos.x, pos.z), def.collide_r + 0.3)
	var a_list := _with_main(_enter_candidates(from, free), from, free)
	var b_list := _with_main(_enter_candidates(to, free), to, free)
	var combos: Array = []
	for a: Dictionary in a_list:
		for b: Dictionary in b_list:
			var rp := _road_path(a.id, b.id, def)
			if rp.is_empty():
				continue
			var ids: PackedInt64Array = rp.ids
			var cost: float = _path_cost(ids) + (a.dist + b.dist) * def.offroad_factor + float(rp.gap_m) * def.offroad_factor
			combos.append({"cost": cost, "ids": ids, "gaps": rp.gaps, "a": a, "b": b})
	combos.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.cost < y.cost)
	var tried := 0
	var bad_a := {}  # vertices whose cross-country leg already failed: the other combos using them are skipped
	var bad_b := {}
	var why: Array = ["direct %s" % direct.ok, "road candidates %d/%d, combos %d" % [a_list.size(), b_list.size(), combos.size()]]
	for cb: Dictionary in combos:
		if tried >= 4:
			break
		if bad_a.has(cb.a.id) or bad_b.has(cb.b.id):
			continue
		tried += 1
		var la := _leg(from, cb.a.pos, def)
		if not la.ok:
			bad_a[cb.a.id] = true
			why.append("start leg %.0f m failed" % cb.a.dist)
			continue
		var lb := _leg(cb.b.pos, to, def)
		if not lb.ok:
			bad_b[cb.b.id] = true
			why.append("end leg %.0f m failed" % cb.b.dist)
			continue
		var road_pts := PackedVector3Array()
		var names: Array = []
		for id: int in cb.ids:
			road_pts.append(astar.get_point_position(id))
			var rd: RoadNetwork.Road = _node_road[id]
			if rd and not names.has(rd.name):
				names.append(rd.name)
		var cost: float = _path_cost(cb.ids) + (_length(la.pts) + _length(lb.pts)) * def.offroad_factor
		cands.append({"cost": cost, "legs": [la, lb], "road": cb.ids, "gaps": cb.gaps, "names": names, "road_pts": road_pts})
		break
	if cands.is_empty():
		var f := _fail("No drivable route (water, cliffs or structures in the way)")
		f["why"] = why
		return f
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.cost < y.cost)
	return _assemble(cands[0], from, to, def)


## The cheapest road path a -> b. Road vertices inside a structure (a wall across the road, a base's buildings) are not a dead
## end: the vehicle leaves the road before them and rejoins it behind them, so each blocked stretch is replaced by a
## cross-country leg between the free vertices on both sides (the leg planner knows the footprints and finds a gate or goes
## round). {ids, gaps: [{from, to, pts}], gap_m}, or {} when a stretch cannot be bypassed.
func _road_path(a: int, b: int, def: VehicleDefs.Def) -> Dictionary:
	var ids := astar.get_id_path(a, b)
	if ids.is_empty():
		return {}
	var n := ids.size()
	var blocked := PackedByteArray()
	blocked.resize(n)
	if structures != null:
		for k in n:
			var p := astar.get_point_position(ids[k])
			if structures.blocks_point(Vector2(p.x, p.z), def.collide_r + 0.3):
				blocked[k] = 1
	var gaps: Array = []
	var gap_m := 0.0
	var k := 0
	while k < n:
		if blocked[k] == 0:
			k += 1
			continue
		var j := k
		while j + 1 < n and blocked[j + 1] == 1:
			j += 1
		if k == 0 or j == n - 1:
			return {}
		var leg := _leg(astar.get_point_position(ids[k - 1]), astar.get_point_position(ids[j + 1]), def)
		if not leg.ok:
			return {}
		gaps.append({"from": k - 1, "to": j + 1, "pts": leg.pts})
		gap_m += _length(leg.pts)
		k = j + 1
	return {"ids": ids, "gaps": gaps, "gap_m": gap_m}


## A cross-country leg a -> b for a vehicle that has to get round something on its way (VehicleSim bypass): {ok, pts}.
func bypass_leg(a: Vector3, b: Vector3, def: VehicleDefs.Def, clearance := BYPASS_CLEARANCE_M) -> Dictionary:
	_extra = clearance
	var r := _leg(a, b, def)
	_extra = 0.0
	return r


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
	var lane_idx: Array = []  # [index in ctrl, road] of road points that may move to the right-hand lane
	if not cand.road.is_empty():
		var ids: PackedInt64Array = cand.road
		var gap_from := {}
		var gap_to := {}
		for g: Dictionary in cand.get("gaps", []):
			gap_from[int(g.from)] = g
			gap_to[int(g.to)] = true
		var i := 0
		var last_p := Vector3.INF
		while i < ids.size():
			var rd: RoadNetwork.Road = _node_road[ids[i]]
			var c: float = def.class_speed.get(rd.cls, 12.0) if not rd.built else 9.0
			var p := astar.get_point_position(ids[i])
			if ctrl.size() > 0 and Vector2(ctrl[-1].x - p.x, ctrl[-1].z - p.z).length() < 1.0:
				cap[cap.size() - 1] = maxf(cap[cap.size() - 1], c)
			else:
				ctrl.append(p)
				cap.append(c)
				if last_p.is_finite() and not gap_to.has(i):
					road_m += Vector2(p.x - last_p.x, p.z - last_p.z).length()
				var near_end := i < 2 or i >= ids.size() - 2 or gap_to.has(i) or gap_from.has(i) or gap_to.has(i - 1) or gap_from.has(i + 1)
				if not near_end:
					lane_idx.append([ctrl.size() - 1, rd])
			last_p = p
			if gap_from.has(i):
				var g: Dictionary = gap_from[i]
				_append(ctrl, cap, g.pts, off_cap)
				off_m += _length(g.pts)
				last_p = Vector3.INF
				i = int(g.to)
				continue
			i += 1
		_append(ctrl, cap, legs[1].pts, off_cap)
		off_m += _length(legs[1].pts)
	# Drive on the right: road points move to the right of the direction of travel (half a lane, at most 2 m) on roads wide
	# enough for two lanes, so two vehicles meeting on a road pass each other instead of blocking each other.
	var shifted := ctrl.duplicate()
	for e: Array in lane_idx:
		var idx: int = e[0]
		var rd2: RoadNetwork.Road = e[1]
		if rd2.width < LANE_MIN_WIDTH or idx <= 0 or idx >= ctrl.size() - 1:
			continue
		var f := Vector3(ctrl[idx + 1].x - ctrl[idx - 1].x, 0.0, ctrl[idx + 1].z - ctrl[idx - 1].z)
		if f.length() < 0.5:
			continue
		f = f.normalized()
		var lane := minf(rd2.width * 0.2, LANE_OFFSET_M)
		shifted[idx] = ctrl[idx] + Vector3(-f.z, 0.0, f.x) * lane
	ctrl = shifted
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
		if structures and (structures.blocks_point(Vector2(p.x, p.z), def.circle_r + _extra) or structures.is_wet(p.x, p.z)):
			return false
		if _near_parked(p.x, p.z, def.circle_r + _extra):
			return false
	return true


func _near_parked(x: float, z: float, r: float) -> bool:
	for c: Array in parked_circles:
		var dx: float = c[0] - x
		var dz: float = c[1] - z
		var rr: float = c[2] + r
		if dx * dx + dz * dz < rr * rr:
			return true
	return false


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
				bad = structures.blocks_point(Vector2(cx, cz), def.circle_r + _extra) or structures.is_wet(cx, cz)
			if not bad and not parked_circles.is_empty():
				bad = _near_parked(cx, cz, def.circle_r + _extra)
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
