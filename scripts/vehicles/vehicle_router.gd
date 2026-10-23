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
## ... and the nearest vertices of this many distinct roads are collected (the rest only form the second planning stage).
const CANDIDATES_ALL := 6
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
## NAVIGATION N1-B: a dangling road end up to this far (m) from a road of another component is a *soft link*: not a graph edge
## (the ground between may be a bank this vehicle cannot cross) but a short cross-country leg that is checked for the vehicle at
## plan time. Replaces nothing: the permanent joins above stay.
const SOFT_LINK_M := 70.0
const LEG_CELL := 3.0
## Extra clearance (m) the first search of a local leg keeps from structures and trunks, beyond the vehicle's planning circle.
const LEG_MARGIN := 0.9
## ... and the margin a straight line needs before the local search is skipped.
const LEG_STRAIGHT_MARGIN := 0.6
const ROAD_CLEAR_MARGIN := 0.6
const LEG_DENSIFY_M := 8.0
## A trunk blocks this much further than its own radius: the front and rear circles of a vehicle swing out of the centre line in
## a curve, and the route is followed with a tracking error.
const TRUNK_EXTRA_M := 0.4
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
## Largest uninterrupted native A* call observed since this router was created.
var native_road_astar_max_ms := 0.0
var native_local_astar_max_ms := 0.0
## NAVIGATION N1 diagnostics; none of these fields affect planning.
var failed_plans := 0
var failure_reasons := {}
var last_failure := {}
var graph_builds := 0
var graph_rebuilds := 0
var graph_ms_total := 0.0
var graph_ms_max := 0.0
var last_rebuild_reason := "initial"
## NAVIGATION N1-B profile of where planning time goes (diagnostics only): calls and milliseconds per stage.
var prof := {"leg_calls": 0, "leg_ms": 0.0, "local_calls": 0, "local_ms": 0.0, "local_cells": 0, "local_fail": 0,
	"strat_calls": 0, "strat_ms": 0.0, "line_ms": 0.0, "roadpath_ms": 0.0, "assemble_ms": 0.0, "cand_ms": 0.0, "astar_ms": 0.0, "astar_calls": 0}

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
## Soft links: component number -> Array of {a: id, b: id, gap_m} with `a` in that component and `b` in another one.
var _soft := {}
## NAVIGATION N1-B caches. Both are dropped whenever the roads or the structures change (`_epoch`).
## Whole plans by 1 m start / end, vehicle type and the parked vehicles; cross-country legs by 0.5 m ends (not near parked vehicles).
var _plan_cache := {}
var _leg_cache := {}
## NAVIGATION N1-C1: the 64 m cells every cached plan / leg touches (key -> {Vector2i: true}), so a structure change drops only
## the entries near it and a cached route that is still valid stays cached.
var _plan_cells := {}
var _leg_cells := {}
const CACHE_CELL_M := 64.0
## Margin round a changed structure inside which cached routes are dropped (vehicle footprint, clearance tiers, bypass margins).
const CACHE_PAD_M := 24.0
var cache_stats := {"structure_events": 0, "plans_dropped": 0, "plans_kept": 0, "legs_dropped": 0, "legs_kept": 0}
var cache_hits := 0
var leg_cache_hits := 0
var leg_cache_misses := 0
const CACHE_MAX := 160
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
## Local-grid refinements one cross-country leg may spend on a strategic route (set low while a road route already exists: the
## cross-country candidate is then only worth a cheap look).
var _piece_limit := 99
var debug_legs := false
var last_leg_debug := ""
## NAVIGATION N1-C1: graph vertex id -> RoadNetwork.Bridge for the interior vertices of a bridge span, and bridge id -> those
## vertices. A closed or disabled bridge has them switched off in `astar` (the only copy of the state is RoadNetwork.Bridge.state).
var _node_bridge := {}
var _bridge_nodes := {}
## Counters of what bridge events dropped from the caches (tests and the report).
var bridge_stats := {"events": 0, "plans_dropped": 0, "legs_dropped": 0}
## Set by line_ok when the line it accepted ran over a bridge deck (such legs are dropped when a bridge closes).
var _deck_hit := false
## The closed bridge the vehicle being planned stands on (null: none). Its deck stays usable for the plan, so a vehicle on a
## closed bridge can leave it; no other closed deck is.
var _start_bridge: RoadNetwork.Bridge = null
## NAV-PERF-01B: the slice of a resumable plan in progress (PlanRunner): {deadline (usec), memo, work, aborted}; empty for a plan
## that runs to its end at once (every synchronous caller). See PlanRunner.
var _slice := {}


## NAV-PERF-01B checkpoint before a piece of work (a leg, a grid search, the assembly): true when the plan has to stop here - the
## slice's deadline has passed and at least one piece was finished in it. Every caller up the chain then returns at once and caches
## nothing; the runner calls plan() again in the next frame and the finished pieces come from its memo.
func _stop() -> bool:
	if _slice.is_empty():
		return false
	if not _slice.aborted and int(_slice.work) > 0 and Time.get_ticks_usec() >= int(_slice.deadline):
		_slice.aborted = true
	return _slice.aborted


## The same inside a loop whose progress is kept in the memo (a local grid being built): only the deadline counts.
func _late() -> bool:
	if _slice.is_empty():
		return false
	if not _slice.aborted and Time.get_ticks_usec() >= int(_slice.deadline):
		_slice.aborted = true
	return _slice.aborted


## True once the plan in progress stopped at a checkpoint (results seen now are incomplete, not failures).
func _halted() -> bool:
	return not _slice.is_empty() and bool(_slice.aborted)


func _worked(what := "") -> void:
	if not _slice.is_empty():
		_slice.work = int(_slice.work) + 1
		# Diagnostics: the longest stretch between two finished pieces of this slice, and what ended it.
		var now := Time.get_ticks_usec()
		var ms := (now - int(_slice.get("mark", now))) / 1000.0
		_slice["mark"] = now
		if not _slice.has("log"):
			_slice["log"] = []
		_slice.log.append("%s %.2f" % [what, ms])
		if ms > float(_slice.get("piece_ms", 0.0)):
			_slice["piece_ms"] = ms
			_slice["piece"] = what


## The resumable plan's memo (finished pieces by key), or a throwaway dictionary for a plan run at once.
func _memo() -> Dictionary:
	return _slice.memo if not _slice.is_empty() else {}


func setup(p_net: RoadNetwork, p_routes: StrategicRoutes, p_terrain: Terrain3D, p_structures: StructureManager) -> void:
	net = p_net
	routes = p_routes
	terrain = p_terrain
	structures = p_structures
	if not net.changed.is_connected(_on_changed):
		net.changed.connect(_on_changed)
	if not net.bridge_changed.is_connected(_on_bridge_changed):
		net.bridge_changed.connect(_on_bridge_changed)
	if structures and not structures.area_changed.is_connected(_on_structures_changed):
		structures.area_changed.connect(_on_structures_changed)


func _on_changed(_rect: Rect2) -> void:
	_dirty = true
	last_rebuild_reason = "road network changed"
	_fail_cache.clear()
	_clear_route_caches()


func _clear_route_caches() -> void:
	_plan_cache.clear()
	_leg_cache.clear()
	_plan_cells.clear()
	_leg_cells.clear()


## Removes the entries of `cache` whose cells touch `area` (and entries with no recorded cells); returns how many went.
func _drop_in(cache: Dictionary, cells_of: Dictionary, area: Rect2) -> int:
	var covered := {}
	for gx in range(floori(area.position.x / CACHE_CELL_M), floori(area.end.x / CACHE_CELL_M) + 1):
		for gz in range(floori(area.position.y / CACHE_CELL_M), floori(area.end.y / CACHE_CELL_M) + 1):
			covered[Vector2i(gx, gz)] = true
	var dropped := 0
	for key in cache.keys():
		var cs: Dictionary = cells_of.get(key, {})
		var hit := cs.is_empty()
		if not hit:
			for c: Vector2i in covered:
				if cs.has(c):
					hit = true
					break
		if hit:
			cache.erase(key)
			cells_of.erase(key)
			dropped += 1
	return dropped


## The 64 m cells a polyline passes through (segments sampled every half cell).
static func _cells_of_points(pts: PackedVector3Array) -> Dictionary:
	var out := {}
	for i in pts.size():
		var p := pts[i]
		out[Vector2i(floori(p.x / CACHE_CELL_M), floori(p.z / CACHE_CELL_M))] = true
		if i > 0:
			var a := pts[i - 1]
			var d := Vector2(p.x - a.x, p.z - a.z).length()
			var n := ceili(d / (CACHE_CELL_M * 0.5))
			for k in range(1, n):
				var q := a.lerp(p, float(k) / n)
				out[Vector2i(floori(q.x / CACHE_CELL_M), floori(q.z / CACHE_CELL_M))] = true
	return out


## The cells of the area a failed leg a -> b searched (its local grid: the box of both ends and the search margin).
static func _cells_of_search(a: Vector3, b: Vector3) -> Dictionary:
	var margin := maxf(45.0, Vector2(b.x - a.x, b.z - a.z).length() * 0.35) + CACHE_CELL_M
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z)) - Vector2.ONE * margin
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z)) + Vector2.ONE * margin
	var out := {}
	for gx in range(floori(lo.x / CACHE_CELL_M), floori(hi.x / CACHE_CELL_M) + 1):
		for gz in range(floori(lo.y / CACHE_CELL_M), floori(hi.y / CACHE_CELL_M) + 1):
			out[Vector2i(gx, gz)] = true
	return out


## NAVIGATION N1-C1: a bridge was opened, closed or disabled. The vertices of its span are switched off or on in the road graph (no
## rebuild). Closing can only invalidate what used the bridge: cached plans that crossed its deck and cross-country legs that ran
## over it; failed plans stay failed. Opening can make shorter routes possible, so cached plans and failures are dropped.
func _on_bridge_changed(b: RoadNetwork.Bridge) -> void:
	bridge_stats.events += 1
	last_rebuild_reason = "bridge %s %s" % [b.id, b.state_name()]
	if built:
		_apply_bridge_nodes(b)
	if b.is_open():
		_fail_cache.clear()
		_clear_route_caches()
		return
	for key in _plan_cache.keys():
		if (_plan_cache[key].get("bridge_ids", []) as Array).has(b.id):
			_plan_cache.erase(key)
			_plan_cells.erase(key)
			bridge_stats.plans_dropped += 1
	for key in _leg_cache.keys():
		if bool(_leg_cache[key].get("deck", false)):
			_leg_cache.erase(key)
			_leg_cells.erase(key)
			bridge_stats.legs_dropped += 1


func _apply_bridge_nodes(b: RoadNetwork.Bridge) -> void:
	for id: int in _bridge_nodes.get(b.id, PackedInt32Array()):
		if astar.has_point(id):
			astar.set_point_disabled(id, not b.is_open())


## Maps the interior vertices of every bridge span and applies the bridges' current states (called after the graph was built).
func _map_bridges() -> void:
	_node_bridge.clear()
	_bridge_nodes.clear()
	for b: RoadNetwork.Bridge in net.bridges:
		var ids: PackedInt32Array = _ids_of.get(b.road_key, PackedInt32Array())
		if ids.size() <= b.last:
			continue
		var lo := b.first + 1 if b.last - b.first >= 2 else b.first
		var hi := b.last - 1 if b.last - b.first >= 2 else b.last
		var nodes := PackedInt32Array()
		for k in range(lo, hi + 1):
			nodes.append(ids[k])
			_node_bridge[ids[k]] = b
		_bridge_nodes[b.id] = nodes
		_apply_bridge_nodes(b)


## The first bridge on a road path that a vehicle of this width does not fit on, null when it fits all.
func _bridge_unfit(ids: PackedInt64Array, def: VehicleDefs.Def) -> RoadNetwork.Bridge:
	for id in ids:
		var b: RoadNetwork.Bridge = _node_bridge.get(id)
		if b != null and not b.admits(def.width):
			return b
	return null


## Why a road route fails when the cause is a closed bridge: the road graph is searched once more with the blocked bridges
## switched on between the nearest road vertices of both ends. {} when the closed bridges are not the reason.
func _bridge_cause(a_list: Array, b_list: Array) -> Dictionary:
	if net.blocked_bridge_count() == 0:
		return {}
	for b: RoadNetwork.Bridge in net.blocked_bridges():
		for id: int in _bridge_nodes.get(b.id, PackedInt32Array()):
			astar.set_point_disabled(id, false)
	var found := {}
	for a: Dictionary in a_list.slice(0, 3):
		for b: Dictionary in b_list.slice(0, 3):
			var ids := _road_id_path(a.id, b.id)
			if ids.is_empty():
				continue
			var names: Array = []
			var bridge_ids: Array = []
			for id in ids:
				var br: RoadNetwork.Bridge = _node_bridge.get(id)
				if br != null and not br.is_open() and not bridge_ids.has(br.id):
					bridge_ids.append(br.id)
					names.append("%s (%s)" % [br.name, br.state_name()])
			if not bridge_ids.is_empty():
				found = {"names": names, "ids": bridge_ids}
				break
		if not found.is_empty():
			break
	for b: RoadNetwork.Bridge in net.blocked_bridges():
		for id: int in _bridge_nodes.get(b.id, PackedInt32Array()):
			astar.set_point_disabled(id, true)
	return found


## Structures were built or removed: road vertices disabled because a structure stood on them
## are tried again.
func _on_structures_changed(rect: Rect2) -> void:
	last_rebuild_reason = "structure area changed"
	# Failed plans may succeed now (a removed wall): they all go. Plans and legs are dropped only where they pass the changed
	# area - a route elsewhere is exactly as valid as before. (N1-B dropped every cache, and the next plan paid for all of it.)
	_fail_cache.clear()
	var area := rect.grow(CACHE_PAD_M)
	var dp := _drop_in(_plan_cache, _plan_cells, area)
	var dl := _drop_in(_leg_cache, _leg_cells, area)
	cache_stats.structure_events += 1
	cache_stats.plans_dropped += dp
	cache_stats.plans_kept += _plan_cache.size()
	cache_stats.legs_dropped += dl
	cache_stats.legs_kept += _leg_cache.size()
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
		_find_soft_links()
		_map_bridges()
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
	_find_soft_links()


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


## Soft links (see SOFT_LINK_M): for every road end whose component is not the main one, the nearest vertex of another component
## within reach and GAP_FIX_DY * 1.5 in height. Computed once per graph change; ends of built roads count too.
func _find_soft_links() -> void:
	_soft.clear()
	for key in _ids_of.keys():
		var ids: PackedInt32Array = _ids_of[key]
		if ids.size() < 2:
			continue
		for end_id: int in [ids[0], ids[ids.size() - 1]]:
			var comp: int = _comp_of.get(end_id, -1)
			if comp < 0:
				continue
			var p := astar.get_point_position(end_id)
			var c := Vector2i(floori(p.x / HASH), floori(p.z / HASH))
			var best := -1
			var best_d := SOFT_LINK_M
			var rings := ceili(SOFT_LINK_M / HASH)
			for dx in range(-rings, rings + 1):
				for dz in range(-rings, rings + 1):
					for other: int in _cells.get(c + Vector2i(dx, dz), []):
						if _comp_of.get(other, -1) == comp or _node_road[other] == null:
							continue
						var q := astar.get_point_position(other)
						if absf(q.y - p.y) > GAP_FIX_DY * 1.5:
							continue
						var d := Vector2(p.x - q.x, p.z - q.z).length()
						if d < best_d:
							best_d = d
							best = other
			if best >= 0:
				var oc: int = _comp_of[best]
				if not _soft.has(comp):
					_soft[comp] = []
				_soft[comp].append({"a": end_id, "b": best, "gap_m": best_d})
				if not _soft.has(oc):
					_soft[oc] = []
				_soft[oc].append({"a": best, "b": end_id, "gap_m": best_d})


## The road path a -> b over a soft link when they lie in different components: the ids of both parts joined, and the index k
## where the soft link crosses (ids[k] -> ids[k+1] is a cross-country leg to be planned). {} when no link joins the two components.
func _soft_path(a: int, b: int) -> Dictionary:
	var ca: int = _comp_of.get(a, -1)
	var cb: int = _comp_of.get(b, -1)
	if ca < 0 or cb < 0 or ca == cb:
		return {}
	var best := {}
	var best_cost := INF
	for l: Dictionary in _soft.get(ca, []):
		if _comp_of.get(l.b, -1) != cb:
			continue
		var p1 := _memo_path(a, l.a)
		var p2 := _memo_path(l.b, b) if not _halted() else PackedInt64Array()
		if _halted():
			return {}
		if p1.is_empty() or p2.is_empty():
			continue
		var cost := _path_cost(p1) + _path_cost(p2) + float(l.gap_m) * 3.0
		if cost < best_cost:
			best_cost = cost
			var joined := PackedInt64Array(p1)
			joined.append_array(p2)
			best = {"ids": joined, "k": p1.size() - 1}
	return best


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
## NAVIGATION N1-B: a road vertex closer than this to a structure counts as blocked for a vehicle (the stretch is then driven
## on a cross-country leg that keeps its distance). Was collide_r + 0.3: a centre line 1.9 m from a depot corner let the front
## circle of a truck clip it in the turn.
func road_clear_r(def: VehicleDefs.Def) -> float:
	return def.circle_r + ROAD_CLEAR_MARGIN


func nearest_nodes(p: Vector3, count: int, radius: float, accept := Callable(), distinct := true) -> Array:
	var found: Array = []
	var seen_roads := {}
	var rings := ceili(radius / HASH)
	var c := Vector2i(floori(p.x / HASH), floori(p.z / HASH))
	var cand: Array = []
	# NAV-PERF-01B: in a resumable plan the ring scan stops at the deadline (every 4 rings) and goes on from its memo.
	var memo := _memo()
	var nk := "nn:%.1f,%.1f:%d:%.0f:%s" % [p.x, p.z, count, radius, distinct]
	var r0 := 0
	if memo.has(nk):
		r0 = int(memo[nk].r)
		cand = memo[nk].cand
	for r in range(r0, rings + 1):
		if not _slice.is_empty() and r > r0 and (r - r0) % 4 == 0 and _late():
			memo[nk] = {"r": r, "cand": cand}
			return []
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
	var out := nearest_nodes(p, CANDIDATES_ALL, SNAP_RADIUS, free)
	var more := nearest_nodes(p, 40, 160.0, free, false)
	for m: Dictionary in more:
		var far_enough := true
		for o: Dictionary in out:
			if Vector2(o.pos.x - m.pos.x, o.pos.z - m.pos.z).length() < 30.0:
				far_enough = false
				break
		if far_enough and out.size() < CANDIDATES_ALL + 4:
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
	_start_bridge = net.blocking_bridge_at(p, 3.0)
	var res := _access_to_road(p, def)
	_start_bridge = null
	return res


func _access_to_road(p: Vector3, def: VehicleDefs.Def) -> Dictionary:
	var free := func(id: int, pos: Vector3) -> bool:
		return not astar.is_point_disabled(id) and (structures == null or not structures.blocks_point(Vector2(pos.x, pos.z), road_clear_r(def)))
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
	var ckey := "%d,%d>%d,%d:%s:%d" % [roundi(from.x), roundi(from.z), roundi(to.x), roundi(to.z), def.id, parked_circles.hash()]
	if _plan_cache.has(ckey):
		cache_hits += 1
		var hit: Dictionary = _plan_cache[ckey].duplicate()
		hit["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		hit["cached"] = true
		_count_plan(hit, from, to, def)
		return hit
	var res := _plan(from, to, def)
	_start_bridge = null
	if _halted():
		# NAV-PERF-01B: stopped at a checkpoint; nothing is cached or counted, the runner goes on in the next frame.
		return {"ok": false, "halted": true, "reason": "planning", "points": PackedVector3Array(), "caps": PackedFloat32Array()}
	if not res.ok:
		_fail_cache[key] = {"t": now_ms, "res": res}
	else:
		if _plan_cache.size() >= CACHE_MAX:
			_plan_cache.clear()
			_plan_cells.clear()
		_plan_cache[ckey] = res.duplicate()
		_plan_cells[ckey] = _cells_of_points(res.points)
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
	_start_bridge = net.blocking_bridge_at(from, 3.0)
	var dest_bridge := net.blocking_bridge_at(to)
	if dest_bridge != null and dest_bridge != _start_bridge:
		return _fail("The destination is on %s (%s)" % [dest_bridge.name, dest_bridge.state_name()])
	if structures and structures.blocks_point(Vector2(to.x, to.z), def.circle_r):
		return _fail("The destination is inside a structure")
	if _wet(to):
		return _fail("The destination is in the water")
	var cands: Array = []
	var direct := {"ok": false}
	# 1. Via roads (the cross-country all the way candidate is evaluated after them, and only when it can win).
	# 2. Via roads: a few road vertices near each end, cheapest road cost first.
	# Road vertices inside a structure (a base's perimeter or buildings stand on the road that leads into it) cannot be entered
	# from, or left to: the nearest *free* vertices are the candidates, the cross-country leg (which knows the footprints and
	# finds a gate) does the rest.
	var free := func(id: int, pos: Vector3) -> bool:
		return not astar.is_point_disabled(id) and (structures == null or not structures.blocks_point(Vector2(pos.x, pos.z), road_clear_r(def)))
	# NAV-PERF-01B: a resumable plan keeps the candidate lists, road paths, combinations and legs in its memo; a plan run at once
	# gets a throwaway one (the same work as before).
	var memo := _memo()
	for end_i in 2:
		var ck := "cand%d" % end_i
		if memo.has(ck):
			continue
		var tc := Time.get_ticks_usec()
		var at := from if end_i == 0 else to
		var near := _enter_candidates(at, free)
		var lst := _with_main(near, at, free) if not _halted() else []
		prof.cand_ms += (Time.get_ticks_usec() - tc) / 1000.0
		if _halted():
			return _fail("halted")
		memo[ck] = lst
		_worked("candidates")
	var a_list: Array = memo.cand0
	var b_list: Array = memo.cand1
	var why: Array = ["road candidates %d/%d" % [a_list.size(), b_list.size()]]
	if not memo.has("seen_pair"):
		memo["seen_pair"] = {}
		memo["road_blocked"] = {}
		memo["combo_of"] = {}
	var seen_pair: Dictionary = memo.seen_pair
	var combo_of: Dictionary = memo.combo_of
	var bad_a := {}  # vertices whose cross-country leg already failed: the other combos using them are skipped
	var bad_b := {}
	# Candidate paths overlap heavily. Footprints cannot change during one plan (a change restarts a resumable one).
	var road_blocked: Dictionary = memo.road_blocked
	var legs_tried := 0
	var narrow_bridges := false
	for br: RoadNetwork.Bridge in net.bridges:
		if not br.admits(def.width):
			narrow_bridges = true
			break
	# NAVIGATION N1-B: the pure road searches come first and cheap (one A* per end pair, the nearest candidates of each end;
	# the rest only when those found no usable route), and the expensive part - which stretches a structure blocks and the
	# cross-country legs to the road - is only evaluated for the cheapest few combinations, not for all of them.
	for stage in [0, 1]:
		var la_list := _stage_list(a_list, stage)
		var lb_list := _stage_list(b_list, stage)
		var ck := "combos%d" % stage
		var combos: Array = memo.get(ck, [])
		if not memo.has(ck):
			for a: Dictionary in la_list:
				for b: Dictionary in lb_list:
					var pk: int = int(a.id) * 1000003 + int(b.id)
					# A pair an earlier stage examined is not examined again (seen_pair: pair -> its stage).
					if seen_pair.has(pk) and int(seen_pair[pk]) < stage:
						continue
					# A resumable plan keeps each pair's combination (or null: none) so a later slice does not redo its costs.
					if combo_of.has(pk):
						if combo_of[pk] != null:
							combos.append(combo_of[pk])
						continue
					var ids := _memo_path(a.id, b.id)
					if _halted():
						return _fail("halted")
					seen_pair[pk] = stage
					var soft_k := -1
					if ids.is_empty():
						var sp := _soft_path(a.id, b.id)
						if _halted():
							return _fail("halted")
						if sp.is_empty():
							combo_of[pk] = null
							continue
						ids = sp.ids
						soft_k = sp.k
					# N1-C1: a bridge deck narrower than the vehicle (plus DECK_CLEARANCE_M) cannot be used; the combo is dropped.
					if narrow_bridges and _bridge_unfit(ids, def) != null:
						why.append("bridge too narrow for %s" % def.id)
						combo_of[pk] = null
						continue
					combo_of[pk] = {"cost": _path_cost(ids) + (a.dist + b.dist) * def.offroad_factor, "ids": ids, "a": a, "b": b, "soft_k": soft_k}
					combos.append(combo_of[pk])
			combos.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.cost < y.cost)
			memo[ck] = combos
		why.append("stage %d combos %d" % [stage, combos.size()])
		var found := 0
		var scanned := 0
		for cb: Dictionary in combos:
			if legs_tried >= 4 + 2 * stage or found >= 2 or scanned >= 10:
				break
			if bad_a.has(cb.a.id) or bad_b.has(cb.b.id):
				continue
			scanned += 1
			var tr := Time.get_ticks_usec()
			var gk := "gaps:%d:%d:%d" % [int(cb.a.id), int(cb.b.id), int(cb.soft_k)]
			var rp: Dictionary = memo[gk] if memo.has(gk) else _road_gaps(cb.ids, def, int(cb.soft_k), road_blocked)
			prof.roadpath_ms += (Time.get_ticks_usec() - tr) / 1000.0
			if _halted():
				return _fail("halted")
			if not memo.has(gk):
				memo[gk] = rp
				_worked("road gaps %d vertices" % cb.ids.size())
			if rp.is_empty():
				why.append("road blocked, no gap leg" if int(cb.soft_k) < 0 else "soft link not drivable")
				continue
			legs_tried += 1
			var la := _leg(from, cb.a.pos, def)
			if _halted():
				return _fail("halted")
			if not la.ok:
				bad_a[cb.a.id] = true
				why.append("start leg %.0f m failed" % cb.a.dist)
				continue
			var lb := _leg(cb.b.pos, to, def)
			if _halted():
				return _fail("halted")
			if not lb.ok:
				bad_b[cb.b.id] = true
				why.append("end leg %.0f m failed" % cb.b.dist)
				continue
			var names: Array = []
			for id: int in cb.ids:
				var rd: RoadNetwork.Road = _node_road[id]
				if rd and not names.has(rd.name):
					names.append(rd.name)
			var cost: float = _path_cost(cb.ids) + (_length(la.pts) + _length(lb.pts)) * def.offroad_factor + float(rp.gap_m) * def.offroad_factor
			cands.append({"cost": cost, "legs": [la, lb], "road": cb.ids, "gaps": rp.gaps, "names": names})
			found += 1
		if not cands.is_empty() and found > 0:
			break
	# NAVIGATION N1-B: cross-country all the way. Its cost is at least the straight distance times the vehicle's off-road factor, so
	# when a road route is already cheaper than that, the (expensive) search for it is skipped.
	var best_road := INF
	for c: Dictionary in cands:
		best_road = minf(best_road, float(c.cost))
	var d_straight := Vector2(to.x - from.x, to.z - from.z).length()
	if d_straight * def.offroad_factor < best_road:
		_piece_limit = 3 if best_road < INF else 99
		direct = _leg(from, to, def)
		_piece_limit = 99
		if _halted():
			return _fail("halted")
		if direct.ok:
			cands.append({"cost": _length(direct.pts) * def.offroad_factor, "legs": [direct], "road": [], "names": []})
	why.append("direct %s" % direct.ok)
	if cands.is_empty():
		var f := _fail("No drivable route (water, cliffs or structures in the way)")
		# N1-C1: a closed bridge is named when the road graph connects both ends through it.
		var cause := _bridge_cause(a_list, b_list)
		if not cause.is_empty():
			f["reason"] = "No drivable route: %s" % ", ".join(cause.names)
			f["blocked_by_bridges"] = cause.ids
		f["why"] = why
		return f
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.cost < y.cost)
	if _stop():
		return _fail("halted")
	var ta := Time.get_ticks_usec()
	var assembled := _assemble(cands[0], from, to, def)
	prof.assemble_ms += (Time.get_ticks_usec() - ta) / 1000.0
	_worked("assembly %d points" % (assembled.points as PackedVector3Array).size())
	return assembled


## Candidate road vertices of one end for a planning stage: stage 0 the nearest CANDIDATES (and the main-network vertices the
## list was extended with), stage 1 everything.
func _stage_list(list: Array, stage: int) -> Array:
	if stage > 0 or list.size() <= CANDIDATES:
		return list
	var out: Array = list.slice(0, CANDIDATES)
	for n: Dictionary in list.slice(CANDIDATES):
		if _comp_of.get(n.id, -1) == _main_comp and out.size() < CANDIDATES + 2:
			out.append(n)
	return out


## The road vertices of a path inside a structure (a wall across the road, a base's buildings) are not a dead end: the vehicle
## leaves the road before them and rejoins it behind them, so each blocked stretch is replaced by a cross-country leg between
## the free vertices on both sides (the leg planner knows the footprints and finds a gate or goes round).
## {ids, gaps: [{from, to, pts}], gap_m}, or {} when a stretch cannot be bypassed.
func _road_gaps(ids: PackedInt64Array, def: VehicleDefs.Def, soft_k := -1, blocked_cache := {}) -> Dictionary:
	var n := ids.size()
	var blocked := PackedByteArray()
	blocked.resize(n)
	if structures != null:
		for k in n:
			var id := ids[k]
			if not blocked_cache.has(id):
				var p := astar.get_point_position(id)
				blocked_cache[id] = structures.blocks_point(Vector2(p.x, p.z), road_clear_r(def))
			if blocked_cache[id]:
				blocked[k] = 1
	var gaps: Array = []
	var gap_m := 0.0
	if soft_k >= 0:
		# The soft link: ids[soft_k] -> ids[soft_k + 1] is no graph edge, a short cross-country leg planned for this vehicle.
		var sl := _leg(astar.get_point_position(ids[soft_k]), astar.get_point_position(ids[soft_k + 1]), def)
		if not sl.ok or _halted():
			return {}
		gaps.append({"from": soft_k, "to": soft_k + 1, "pts": sl.pts})
		gap_m += _length(sl.pts)
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
		if not leg.ok or _halted():
			return {}
		gaps.append({"from": k - 1, "to": j + 1, "pts": leg.pts})
		gap_m += _length(leg.pts)
		k = j + 1
	return {"ids": ids, "gaps": gaps, "gap_m": gap_m}


## A cross-country leg a -> b for a vehicle that has to get round something on its way (VehicleSim bypass): {ok, pts}.
func bypass_leg(a: Vector3, b: Vector3, def: VehicleDefs.Def, clearance := BYPASS_CLEARANCE_M) -> Dictionary:
	_start_bridge = net.blocking_bridge_at(a, 3.0)
	_extra = clearance
	var r := _leg(a, b, def)
	_extra = 0.0
	_start_bridge = null
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
	# NAV-PERF-01B: three pieces of a resumable plan (control points and lanes; spline and speed ceilings; heights, a few hundred
	# points between deadline checks), kept in the memo between slices. A plan run at once does them in one go as before.
	var memo := _memo()
	if not memo.has("asm"):
		memo["asm"] = {"stage": 0}
	var asm: Dictionary = memo.asm
	var off_cap := def.offroad_speed
	if asm.stage == 0:
		var ctrl := PackedVector3Array()
		var cap := PackedFloat32Array()
		var legs: Array = cand.legs
		var road_m := 0.0
		var off_m := 0.0
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
			# N1-B: a lane that would move the point into a structure or trunk is shortened, down to the road's centre line.
			var side := Vector3(-f.z, 0.0, f.x)
			while lane > 0.2 and structures != null and structures.blocks_point(Vector2(ctrl[idx].x + side.x * lane, ctrl[idx].z + side.z * lane), def.circle_r):
				lane *= 0.5
			if lane <= 0.2:
				continue
			shifted[idx] = ctrl[idx] + side * lane
		asm.merge({"stage": 1, "ctrl": shifted, "cap": cap, "road_m": road_m, "off_m": off_m}, true)
		_worked("assembly lanes %d points" % shifted.size())
		if _stop():
			return _fail("halted")
	if asm.stage == 1:
		# Cross-country points that coincide with a road vertex take the road's ceiling.
		var ctrl: PackedVector3Array = asm.ctrl
		var cap: PackedFloat32Array = asm.cap
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
		asm.merge({"stage": 2, "pts": pts, "caps": caps, "i": 0, "bridges": 0, "on_deck": false, "bridge_ids": []}, true)
		_worked("assembly spline %d points" % pts.size())
		if _stop():
			return _fail("halted")
	var pts2: PackedVector3Array = asm.pts
	asm.pts = PackedVector3Array()
	var bridges: int = asm.bridges
	var on_deck: bool = asm.on_deck
	var bridge_ids: Array = asm.bridge_ids
	var i2: int = asm.i
	while i2 < pts2.size():
		var h: float = terrain.data.get_height(pts2[i2]) if terrain else pts2[i2].y
		var deck := net.deck_height(pts2[i2])
		if not is_nan(deck):
			h = deck if is_nan(h) else maxf(h, deck)
			if not on_deck:
				bridges += 1
			on_deck = true
			var br := net.bridge_at(pts2[i2])
			if br != null and not bridge_ids.has(br.id):
				bridge_ids.append(br.id)
		else:
			on_deck = false
		if not is_nan(h):
			pts2[i2].y = h
		i2 += 1
		if i2 % 256 == 0 and i2 < pts2.size() and _late():
			asm.merge({"pts": pts2, "i": i2, "bridges": bridges, "on_deck": on_deck, "bridge_ids": bridge_ids}, true)
			return _fail("halted")
	memo.erase("asm")
	return {"ok": true, "reason": "", "points": pts2, "caps": asm.caps, "length_m": _length(pts2), "road_m": asm.road_m,
		"offroad_m": asm.off_m, "bridges": bridges, "bridge_ids": bridge_ids, "roads": cand.names, "cost": cand.cost}


## Cross-country control points; a long straight piece gets a point every LEG_DENSIFY_M, so the Catmull-Rom spline of the whole
## route stays on the straight line instead of bowing out of it (the bow put the East fuel point route 0.7 m from a depot corner).
static func _append(ctrl: PackedVector3Array, cap: PackedFloat32Array, pts: PackedVector3Array, c: float) -> void:
	for p in pts:
		if ctrl.size() > 0 and Vector2(ctrl[-1].x - p.x, ctrl[-1].z - p.z).length() < 1.0:
			continue
		if ctrl.size() > 0:
			var last: Vector3 = ctrl[-1]
			var d := Vector2(p.x - last.x, p.z - last.z).length()
			var k := ceili(d / LEG_DENSIFY_M)
			for j in range(1, k):
				ctrl.append(last.lerp(p, float(j) / k))
				cap.append(c)
		ctrl.append(p)
		cap.append(c)


# --- Cross-country legs -----------------------------------------------------------------

func _wet(p: Vector3) -> bool:
	return structures != null and structures.is_wet(p.x, p.z)


func _height(x: float, z: float) -> float:
	return terrain.data.get_height(Vector3(x, 0.0, z)) if terrain else 0.0


## True when a vehicle can drive the straight line a -> b: slopes within the vehicle's grade,
## no water, no structure within its footprint. Bridge decks count as ground (open bridges only).
func line_ok(a: Vector3, b: Vector3, def: VehicleDefs.Def, margin := 0.0, trunks := true) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	# Samples 1.25 m apart (was 2.5): a wall corner passed at 1.9 m was missed between two samples.
	var n := maxi(1, ceili(d / 1.25))
	var prev_h := NAN
	var step := d / n
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var h := _height(p.x, p.z)
		if is_nan(h):
			return false
		if not is_nan(net.deck_height(p)):
			prev_h = NAN
			_deck_hit = true
			# N1-C1: the deck of a closed or disabled bridge is not ground for a new route.
			if not net.deck_open(p) and net.blocking_bridge_at(p) != _start_bridge:
				return false
			# A bridge deck is ground (no slope or water test) but a structure standing on it still blocks the way.
			if structures and structures.blocks_point(Vector2(p.x, p.z), def.circle_r + _extra + margin):
				return false
			if _near_parked(p.x, p.z, def.circle_r + _extra + margin):
				return false
			continue
		if not is_nan(prev_h) and absf(h - prev_h) / maxf(step, 0.1) > def.max_grade:
			return false
		prev_h = h
		if structures and (structures.blocks_point(Vector2(p.x, p.z), def.circle_r + _extra + margin) or structures.is_wet(p.x, p.z) or (trunks and structures.blocks_trunk(Vector2(p.x, p.z), def.circle_r + _extra + margin))):
			return false
		if _near_parked(p.x, p.z, def.circle_r + _extra + margin):
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
	# NAV-PERF-01B: a resumable plan finds the legs it finished in an earlier slice in its memo (also those never cached globally).
	var memo := _memo()
	var mk := "leg:%.2f,%.2f>%.2f,%.2f:%s:%d:%d:%s" % [a.x, a.z, b.x, b.z, def.id, roundi(_extra * 10.0), _piece_limit, _start_bridge.id if _start_bridge else ""]
	if memo.has(mk):
		return memo[mk]
	if _stop():
		return {"ok": false, "pts": PackedVector3Array(), "halted": true}
	var t0 := Time.get_ticks_usec()
	prof.leg_calls += 1
	var lk := ""
	# A leg planned from a closed deck is not cached: its ends are special and the same ends elsewhere are not.
	if _start_bridge == null and not _parked_near(a, b):
		lk = "%d,%d>%d,%d:%s:%d" % [roundi(a.x * 2.0), roundi(a.z * 2.0), roundi(b.x * 2.0), roundi(b.z * 2.0), def.id, roundi(_extra * 10.0)]
		if _leg_cache.has(lk):
			leg_cache_hits += 1
			return _leg_cache[lk]
		leg_cache_misses += 1
	_deck_hit = false
	var res := _leg_inner(a, b, def, d)
	if _halted():
		return {"ok": false, "pts": PackedVector3Array(), "halted": true}
	if _deck_hit:
		res = res.duplicate()
		res["deck"] = true
	if lk != "":
		if _leg_cache.size() >= CACHE_MAX * 4:
			_leg_cache.clear()
			_leg_cells.clear()
		_leg_cache[lk] = res
		_leg_cells[lk] = _cells_of_points(res.pts) if res.ok else _cells_of_search(a, b)
	prof.leg_ms += (Time.get_ticks_usec() - t0) / 1000.0
	memo[mk] = res
	_worked("leg %.0f m" % d)
	return res


## True when a parked vehicle's circle lies within 30 m of the leg a -> b (such legs are never cached: the yard changes).
func _parked_near(a: Vector3, b: Vector3) -> bool:
	if parked_circles.is_empty():
		return false
	var lo_x := minf(a.x, b.x) - 30.0
	var hi_x := maxf(a.x, b.x) + 30.0
	var lo_z := minf(a.z, b.z) - 30.0
	var hi_z := maxf(a.z, b.z) + 30.0
	for c: Array in parked_circles:
		if c[0] > lo_x and c[0] < hi_x and c[1] > lo_z and c[1] < hi_z:
			return true
	return false


func _leg_inner(a: Vector3, b: Vector3, def: VehicleDefs.Def, d: float) -> Dictionary:
	var tl := Time.get_ticks_usec()
	# N1-B: the straight line is taken as it is only with room to spare (LEG_STRAIGHT_MARGIN) - a line that skims a wall at the
	# bare planning radius is what clipped the depot corner at the East fuel point - or when the local search finds nothing better.
	var straight := line_ok(a, b, def, LEG_STRAIGHT_MARGIN if _extra == 0.0 else 0.0)
	prof.line_ms += (Time.get_ticks_usec() - tl) / 1000.0
	if straight:
		return {"ok": true, "pts": PackedVector3Array([a, b])}
	if d <= 500.0:
		var loc := _local_plan(a, b, def)
		if loc.ok or _halted():
			return loc
	if _extra == 0.0 and line_ok(a, b, def):
		return {"ok": true, "pts": PackedVector3Array([a, b])}
	if d > 150.0 and routes and routes.ready:
		prof.strat_calls += 1
		var ts := Time.get_ticks_usec()
		var r := routes.route(a, b, terrain)
		prof.strat_ms += (Time.get_ticks_usec() - ts) / 1000.0
		if r.size() >= 2:
			# N1-B: the strategic route knows slopes and water at 50 m, not trees. Each piece of it is taken as it is when the
			# straight line is clear (trunks included), else it is refined on the local grid (which weaves between trunks);
			# a piece that is neither - dense woods - fails the whole leg and the planner falls back to roads.
			var out := PackedVector3Array([r[0]])
			var ok := true
			var pieces := 0
			for i in range(1, r.size()):
				if line_ok(r[i - 1], r[i], def):
					out.append(r[i])
					continue
				var pd := Vector2(r[i].x - r[i - 1].x, r[i].z - r[i - 1].z).length()
				if pd > 500.0 or not line_ok(r[i - 1], r[i], def, 0.0, false):
					ok = false
					break
				pieces += 1
				if pieces > _piece_limit:
					ok = false
					break
				var piece := _local_plan(r[i - 1], r[i], def, 40.0)
				if _halted():
					return piece
				if not piece.ok:
					ok = false
					break
				for k in range(1, piece.pts.size()):
					out.append(piece.pts[k])
			if ok:
				return {"ok": true, "pts": out}
	return {"ok": false, "pts": PackedVector3Array()}


## A* on a local 3 m grid around the leg: cells are blocked by steep ground, water and
## structure footprints (inflated by the vehicle's collision circle).
func _local_plan(a: Vector3, b: Vector3, def: VehicleDefs.Def, margin_m := -1.0) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	prof.local_calls += 1
	var res := _local_plan_inner(a, b, def, margin_m)
	prof.local_ms += (Time.get_ticks_usec() - t0) / 1000.0
	if not res.ok:
		prof.local_fail += 1
	return res


func _local_plan_inner(a: Vector3, b: Vector3, def: VehicleDefs.Def, margin_m := -1.0) -> Dictionary:
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	var margin := maxf(45.0, Vector2(b.x - a.x, b.z - a.z).length() * 0.35) if margin_m < 0.0 else margin_m
	lo -= Vector2.ONE * margin
	hi += Vector2.ONE * margin
	var nx := ceili((hi.x - lo.x) / LEG_CELL)
	var nz := ceili((hi.y - lo.y) / LEG_CELL)
	if nx * nz > LEG_MAX_CELLS:
		return {"ok": false, "pts": PackedVector3Array()}
	var r0: float = def.circle_r + _extra
	var max_dh := def.max_grade * LEG_CELL
	# NAVIGATION N1-B: two clearance levels from one pass. `tight` is what the vehicle's circles need; `wide` adds LEG_MARGIN so
	# the planned line leaves room for the pure-pursuit tracking error (a route 0.3 m past the footprint clipped a corner in
	# r_exit). The wide grid is searched first and the tight one only when it has no path (a narrow gate).
	var margin_r := LEG_MARGIN if _extra == 0.0 else 0.0
	# N1-C1: the per-cell footprint and water tests are skipped for whole grids and cells that cannot be affected: no blocking
	# footprint within the grid, ground well above any water surface. Same answers, a fraction of the calls.
	var search_rect := Rect2(lo, hi - lo).grow(8.0)
	var any_block := structures != null and structures.blocks_in_rect(search_rect)
	var wet_top: float = (structures.water_top_in_rect(search_rect) + 1.0) if structures != null else -INF
	# NAV-PERF-01B: the grid is built in pieces (heights, cells, trunks) that a resumable plan keeps in its memo between slices; a
	# plan run at once builds it in one go as before. The arrays are taken out of the memo while they are filled (one reference:
	# no copy on write) and put back.
	var memo := _memo()
	var gk := "grid:%.2f,%.2f>%.2f,%.2f:%s:%.2f:%.2f" % [a.x, a.z, b.x, b.z, def.id, margin_m, _extra]
	var g: Dictionary = memo.get(gk, {})
	if g.is_empty():
		prof.local_cells += nx * nz
		g = {"phase": 0, "i": 0, "heights": PackedFloat32Array(), "wide": PackedByteArray(), "tight": PackedByteArray(), "trunks": PackedFloat32Array()}
		memo[gk] = g
	var heights: PackedFloat32Array = g.heights
	var wide: PackedByteArray = g.wide
	var tight: PackedByteArray = g.tight
	g.heights = PackedFloat32Array()
	g.wide = PackedByteArray()
	g.tight = PackedByteArray()
	var i: int = g.i
	var halted := false
	if g.phase == 0:
		heights.resize((nx + 1) * (nz + 1))
		wide.resize(nx * nz)
		tight.resize(nx * nz)
		g.phase = 1
		i = 0
	if g.phase == 1:
		var n := (nx + 1) * (nz + 1)
		while i < n:
			heights[i] = _height(lo.x + (i % (nx + 1)) * LEG_CELL, lo.y + (i / (nx + 1)) * LEG_CELL)
			i += 1
			if i % 96 == 0 and i < n and _late():
				halted = true
				break
		if not halted:
			g.phase = 2
			i = 0
	if not halted and g.phase == 2:
		var n2 := nx * nz
		while i < n2:
			var x := i % nx
			var z := i / nx
			var h00 := heights[z * (nx + 1) + x]
			var h10 := heights[z * (nx + 1) + x + 1]
			var h01 := heights[(z + 1) * (nx + 1) + x]
			var cx := lo.x + (x + 0.5) * LEG_CELL
			var cz := lo.y + (z + 0.5) * LEG_CELL
			var ci := i
			i += 1
			if i % 48 == 0 and i < n2 and _late():
				halted = true
			if is_nan(h00) or absf(h10 - h00) > max_dh or absf(h01 - h00) > max_dh:
				tight[ci] = 1
				wide[ci] = 1
			else:
				var c2 := Vector2(cx, cz)
				var hmin := minf(minf(h00, h10), minf(h01, heights[(z + 1) * (nx + 1) + x + 1]))
				if structures and (((is_nan(hmin) or hmin <= wet_top) and structures.is_wet(cx, cz)) or (any_block and structures.blocks_point(c2, r0))):
					tight[ci] = 1
					wide[ci] = 1
				elif not parked_circles.is_empty() and _near_parked(cx, cz, r0):
					tight[ci] = 1
					wide[ci] = 1
				elif margin_r > 0.0 and any_block and structures.blocks_point(c2, r0 + margin_r):
					wide[ci] = 1
			if halted:
				break
		if not halted:
			g.phase = 3
			i = 0
			# Trunks, rocks and settlement colliders are stamped into the grids: every instance blocks the cells whose centre lies
			# within its radius plus the clearance (one pass over the instances instead of two spatial queries per cell).
			if structures:
				var trunks := PackedFloat32Array()
				structures.trunks_in_rect(Rect2(lo, hi - lo), trunks)
				g.trunks = trunks
	if not halted and g.phase == 3:
		var trunks: PackedFloat32Array = g.trunks
		while i < trunks.size():
			var t := i
			i += 3
			var tr_r: float = trunks[t + 2] + TRUNK_EXTRA_M
			var reach_w: float = tr_r + r0 + margin_r
			var x0 := clampi(floori((trunks[t] - reach_w - lo.x) / LEG_CELL), 0, nx - 1)
			var x1 := clampi(floori((trunks[t] + reach_w - lo.x) / LEG_CELL), 0, nx - 1)
			var z0 := clampi(floori((trunks[t + 1] - reach_w - lo.y) / LEG_CELL), 0, nz - 1)
			var z1 := clampi(floori((trunks[t + 1] + reach_w - lo.y) / LEG_CELL), 0, nz - 1)
			for zz in range(z0, z1 + 1):
				for xx in range(x0, x1 + 1):
					var dx: float = lo.x + (xx + 0.5) * LEG_CELL - trunks[t]
					var dz: float = lo.y + (zz + 0.5) * LEG_CELL - trunks[t + 1]
					var dd := dx * dx + dz * dz
					var ii := zz * nx + xx
					if dd < (tr_r + r0) * (tr_r + r0):
						tight[ii] = 1
						wide[ii] = 1
					elif margin_r > 0.0 and dd < reach_w * reach_w:
						wide[ii] = 1
			if (i / 3) % 64 == 0 and i < trunks.size() and _late():
				halted = true
				break
		if not halted:
			g.phase = 4
			g.trunks = PackedFloat32Array()
	g.i = i
	g.heights = heights
	g.wide = wide
	g.tight = tight
	if halted:
		return {"ok": false, "pts": PackedVector3Array(), "halted": true}
	var ca := Vector2i(clampi(int((a.x - lo.x) / LEG_CELL), 0, nx - 1), clampi(int((a.z - lo.y) / LEG_CELL), 0, nz - 1))
	var cb := Vector2i(clampi(int((b.x - lo.x) / LEG_CELL), 0, nx - 1), clampi(int((b.z - lo.y) / LEG_CELL), 0, nz - 1))
	var best := {}
	var used := tight
	for pass_i in 2:
		if pass_i == 0 and margin_r <= 0.0:
			continue
		var grid_used := wide if pass_i == 0 else tight
		# NAV-PERF-01B: each grid search (a native A* plus the string-pulling line tests) is one piece of work of a resumable plan.
		var pk := "pass%d" % pass_i
		var kept: Array[Vector2i] = []
		if g.has(pk):
			kept = g[pk]
		else:
			if _stop():
				return {"ok": false, "pts": PackedVector3Array(), "halted": true}
			kept = _grid_search(grid_used, nx, nz, ca, cb, lo, r0 + (margin_r * 0.5 if pass_i == 0 else 0.0))
			g[pk] = kept
			_worked("grid search %d cells" % (nx * nz))
		if kept.is_empty():
			continue
		var pts := PackedVector3Array()
		pts.append(a)
		for c in kept:
			var p := Vector3(lo.x + (c.x + 0.5) * LEG_CELL, 0.0, lo.y + (c.y + 0.5) * LEG_CELL)
			p.y = _height(p.x, p.z)
			pts.append(p)
		pts.append(b)
		used = grid_used
		best = {"ok": true, "pts": pts}
		if debug_legs:
			var on_path := {}
			for c in kept:
				on_path[c] = true
			var rows2: Array[String] = []
			for z in nz:
				var row2 := ""
				for x in nx:
					var cell := Vector2i(x, z)
					row2 += "S" if cell == ca else ("G" if cell == cb else ("*" if on_path.has(cell) else ("#" if grid_used[z * nx + x] == 1 else (":" if wide[z * nx + x] == 0 and tight[z * nx + x] == 1 else "."))))
				rows2.append(row2)
			last_leg_debug = "pass %d (0=wide 1=tight) lo=(%.0f,%.0f)\n" % [pass_i, lo.x, lo.y] + "\n".join(rows2)
		# The joins between the real end points and the grid path are straight pieces the grid never saw: when the end point lay
		# in blocked cells (a dock in front of a building) the piece may cross the very thing the grid avoids. Then the next
		# (tighter) search gets its turn; the last result stands.
		if _joins_clear(pts, r0 - 0.3):
			return best
	if not best.is_empty():
		return best
	if debug_legs:
		var cc := _free_cell(used, nx, nz, ca)
		var cd := _free_cell(used, nx, nz, cb)
		var rows: Array[String] = []
		for z in nz:
			var row := ""
			for x in nx:
				row += "S" if Vector2i(x, z) == cc else ("G" if Vector2i(x, z) == cd else ("#" if used[z * nx + x] == 1 else "."))
			rows.append(row)
		last_leg_debug = "\n".join(rows)
	return {"ok": false, "pts": PackedVector3Array()}


## True when the first and last pieces of a leg (end point -> first grid vertex, last grid vertex -> end point) keep `r` metres
## from structures and trunks, ignoring the 3 m next to the end point itself (it may stand close to a wall by definition).
func _joins_clear(pts: PackedVector3Array, r: float) -> bool:
	if pts.size() < 3:
		return true
	for seg: Array in [[pts[0], pts[1]], [pts[pts.size() - 1], pts[pts.size() - 2]]]:
		var from: Vector3 = seg[0]
		var to: Vector3 = seg[1]
		var d := Vector2(to.x - from.x, to.z - from.z).length()
		var n := maxi(1, ceili(d / 1.5))
		for k in range(1, n + 1):
			var q := from.lerp(to, float(k) / n)
			if Vector2(q.x - from.x, q.z - from.z).length() < 3.0:
				continue
			if _solid_at(q.x, q.z, r):
				return false
	return true


## Structure footprint or solid vegetation within r of (x, z).
func _solid_at(x: float, z: float, r: float) -> bool:
	if structures == null:
		return false
	var p := Vector2(x, z)
	return structures.blocks_point(p, r) or structures.blocks_trunk(p, r)


## A* over a blocked-cell array from the free cells nearest ca / cb, string-pulled: [] when there is no path, else the kept cells.
func _grid_search(blocked: PackedByteArray, nx: int, nz: int, ca: Vector2i, cb: Vector2i, lo: Vector2, r_line: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var sa := _free_cell(blocked, nx, nz, ca)
	var sb := _free_cell(blocked, nx, nz, cb)
	if sa.x < 0 or sb.x < 0:
		return out
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, nx, nz)
	grid.cell_size = Vector2(LEG_CELL, LEG_CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for i in blocked.size():
		if blocked[i] == 1:
			grid.set_point_solid(Vector2i(i % nx, i / nx), true)
	var search_started := Time.get_ticks_usec()
	var path := grid.get_id_path(sa, sb)
	native_local_astar_max_ms = maxf(native_local_astar_max_ms, (Time.get_ticks_usec() - search_started) / 1000.0)
	if path.is_empty():
		return out
	# String-pulling: keep a vertex only where the grid line from the last kept one is blocked.
	out.append(path[0])
	var i := 0
	while i < path.size() - 1:
		var j := path.size() - 1
		while j > i + 1 and not (_grid_clear(blocked, nx, path[i], path[j]) and _line_clear(lo, path[i], path[j], r_line)):
			j -= 1
		out.append(path[j])
		i = j
	return out


## NAV-PERF-01B: a road A* path a -> b through the resumable plan's memo (each search one piece of work, a checkpoint before it); a
## plan run at once searches as before.
func _memo_path(a: int, b: int) -> PackedInt64Array:
	var memo := _memo()
	if not memo.has("paths"):
		memo["paths"] = {}
	var key := a * 1000003 + b
	if memo.paths.has(key):
		return memo.paths[key]
	if _stop():
		return PackedInt64Array()
	var tp := Time.get_ticks_usec()
	var ids := _road_id_path(a, b)
	prof.astar_ms += (Time.get_ticks_usec() - tp) / 1000.0
	prof.astar_calls += 1
	memo.paths[key] = ids
	_worked("road A*")
	return ids


func _road_id_path(a: int, b: int) -> PackedInt64Array:
	var started := Time.get_ticks_usec()
	var path := astar.get_id_path(a, b)
	native_road_astar_max_ms = maxf(native_road_astar_max_ms, (Time.get_ticks_usec() - started) / 1000.0)
	return path


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


## The straight piece between two grid cells keeps r_line from structures and trunks (sampled every 1.5 m): the cell test alone
## lets a line pass 1.5 m closer to a wall than the centre of the free cell next to it.
func _line_clear(lo: Vector2, a: Vector2i, b: Vector2i, r_line: float) -> bool:
	var pa := Vector2(lo.x + (a.x + 0.5) * LEG_CELL, lo.y + (a.y + 0.5) * LEG_CELL)
	var pb := Vector2(lo.x + (b.x + 0.5) * LEG_CELL, lo.y + (b.y + 0.5) * LEG_CELL)
	var d := pa.distance_to(pb)
	var n := maxi(1, ceili(d / 1.5))
	for k in range(1, n):
		var q := pa.lerp(pb, float(k) / n)
		if _solid_at(q.x, q.y, r_line):
			return false
	return true


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


## NAV-PERF-01B: one vehicle plan as a RouteService job ("vehicle"). Each step calls plan() with a deadline: the plan runs until a
## checkpoint finds the deadline passed (road candidates, every road A*, every leg, each part of a local grid - heights, cells, trunk
## stamping - each grid search, the assembly) and returns "halted"; the finished pieces wait in `memo` and the next step goes on
## from there. A step always finishes at least one piece, so a plan always ends; the pieces themselves (one native A*, one grid
## search, the assembly) are the unit of work and are not split. The parked vehicles the plan avoids are taken when the job is made
## (VehicleSim._collect_parked) and put in place for each step. reset(): the world changed, start again.
class PlanRunner:
	var router: VehicleRouter
	var from: Vector3
	var to: Vector3
	var def: VehicleDefs.Def
	var parked: Array
	var memo := {}
	var result := {}
	var steps := 0
	## Diagnostics: the longest piece of work seen in a step (ms) and what it was.
	var max_piece_ms := 0.0
	var max_piece := ""
	## Diagnostics: the slowest step (ms) and the pieces it finished, in order.
	var slowest_ms := 0.0
	var slowest_log: Array = []

	func _init(p_router: VehicleRouter, p_from: Vector3, p_to: Vector3, p_def: VehicleDefs.Def, p_parked: Array) -> void:
		router = p_router
		from = p_from
		to = p_to
		def = p_def
		parked = p_parked

	func step(deadline_us: int) -> bool:
		steps += 1
		var saved := router.parked_circles
		router.parked_circles = parked
		router._slice = {"deadline": deadline_us, "memo": memo, "work": 0, "aborted": false, "mark": Time.get_ticks_usec()} if deadline_us > 0 else {}
		var t0 := Time.get_ticks_usec()
		var res := router.plan(from, to, def)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if not router._slice.is_empty() and ms > slowest_ms:
			slowest_ms = ms
			slowest_log = (router._slice.get("log", []) as Array).duplicate()
			slowest_log.append("end %.2f (aborted %s, deadline in %.2f ms at start)" % [(Time.get_ticks_usec() - int(router._slice.mark)) / 1000.0, router._slice.aborted, (deadline_us - t0) / 1000.0])
		if not router._slice.is_empty() and float(router._slice.get("piece_ms", 0.0)) > max_piece_ms:
			max_piece_ms = float(router._slice.piece_ms)
			max_piece = String(router._slice.get("piece", ""))
		router._slice = {}
		router.parked_circles = saved
		if bool(res.get("halted", false)):
			return false
		result = res
		return true

	func reset() -> void:
		memo = {}
		result = {}

	func debug_state() -> Dictionary:
		return {"steps": steps, "memo_keys": memo.size(), "max_piece": max_piece, "max_piece_ms": snappedf(max_piece_ms, 0.01),
			"slowest_ms": snappedf(slowest_ms, 0.01), "slowest": slowest_log}


## The dedupe key of a vehicle plan: the same ends (1 m), vehicle type and parked vehicles are the same search.
func job_key(from: Vector3, to: Vector3, def: VehicleDefs.Def, parked: Array) -> String:
	return "veh:%d,%d>%d,%d:%s:%d" % [roundi(from.x), roundi(from.z), roundi(to.x), roundi(to.z), def.id, parked.hash()]
