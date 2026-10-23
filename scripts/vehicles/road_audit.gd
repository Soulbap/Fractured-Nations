## Road network audit (AI-WAR-LOGISTICS-01): checks the one road graph vehicles actually route on.
##
## No second graph: the audit reads VehicleRouter's own AStar3D (built from RoadNetwork - the world's roads.json plus the roads
## built in construction) and RoadNetwork's polylines, so whatever a vehicle can drive is exactly what is measured, and a
## road added or edited at runtime is covered the next time `run` is called (the router syncs built roads itself).
##
## What it reports (all as plain data, `describe` turns it into text, `RoadAuditOverlay` draws it):
##   * nodes, edges, connected components (size, roads, length, bounding box, centre);
##   * isolated roads: roads that are a component of their own (a track nobody can reach, or a broken junction);
##   * broken intersections: two roads whose lines cross (or touch within JOIN_GAP_M) without any linked vertices pair, and road
##     ends that stop a short distance (10.5 .. JOIN_GAP_M) from another road's line - the near misses that look connected;
##   * invalid geometry: zero-length segments, NaN points, grades above the vehicle limit, turns tighter than a truck can take;
##   * strategic locations (objectives, bases, settlements, bridges): the nearest road node, its component, whether a vehicle
##     can *enter* the road from the location (the cross-country leg), and whether routes between all pairs can be planned,
##     each failure with the planner's reason and where it happened;
##   * intentional isolation: a location or road may be listed in `intentional` (name -> reason) and is then reported apart from
##     the broken ones, so isolated places that are meant to be isolated do not count as failures. Autonomous operations treat
##     any unreachable destination through the planner's refusal (OpTransport falls back to a foot march).
class_name RoadAudit
extends RefCounted

## Roads whose lines come this close without a linked vertex pair are reported as a near miss.
const JOIN_GAP_M := 45.0
## A vertical separation above this makes a crossing a bridge / overpass, not a missing junction.
const OVERPASS_M := 5.0
## Turns with a radius below this (m) are reported (a 6x6 truck needs about 8 m).
const MIN_RADIUS_M := 9.0

var sim: WorldSim
var router: VehicleRouter
var net: RoadNetwork
## name -> why it is meant to be isolated (roads or locations); filled by the caller or a world file.
var intentional := {}


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	router = sim.vehicles.router
	net = sim.state.roads


## Components of the router graph: [{id, nodes, roads: [names], length_m, bbox: Rect2, center: Vector3, road_keys}], largest first.
func components() -> Array:
	router.ensure_built()
	var astar := router.astar
	var seen := {}
	var out: Array = []
	for id: int in astar.get_point_ids():
		if seen.has(id):
			continue
		var stack: Array[int] = [id]
		seen[id] = true
		var nodes := 0
		var roads := {}
		var length := 0.0
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var sum := Vector3.ZERO
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			nodes += 1
			var p := astar.get_point_position(cur)
			sum += p
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
			var rd: RoadNetwork.Road = router._node_road[cur]
			if rd != null:
				roads[rd.key] = rd
			for nb: int in astar.get_point_connections(cur):
				var q := astar.get_point_position(nb)
				if router._node_road[nb] == rd:
					length += Vector2(p.x - q.x, p.z - q.z).length() * 0.5
				if not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		var names: Array = []
		var keys: Array = []
		for k in roads:
			names.append(roads[k].name)
			keys.append(k)
		out.append({"nodes": nodes, "roads": names, "road_keys": keys, "length_m": length, "bbox": Rect2(lo, hi - lo), "center": sum / maxf(nodes, 1.0)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.nodes > b.nodes)
	for i in out.size():
		out[i]["id"] = i
	return out


## component index of every road key
static func component_of_roads(comps: Array) -> Dictionary:
	var out := {}
	for c: Dictionary in comps:
		for k in c.road_keys:
			out[k] = c.id
	return out


## The audit of the road graph itself (no locations): counts, components, isolated roads, broken intersections, geometry.
func audit_graph(max_issue_list := 40) -> Dictionary:
	router.ensure_built()
	var comps := components()
	var comp_of := component_of_roads(comps)
	var edges := 0
	for id: int in router.astar.get_point_ids():
		edges += router.astar.get_point_connections(id).size()
	edges /= 2
	var out := {"repaired_gaps": router.repaired_gaps.size(), "repaired_gap_list": router.repaired_gaps.slice(0, 80).map(func(g: Dictionary) -> Dictionary: return {"road": g.road, "to_road": g.to_road, "gap_m": snappedf(g.gap_m, 0.1), "at": _xz(g.at)}),
		"roads": net.all_roads().size(), "nodes": router.node_count(), "edges": edges, "components": comps.size(),
		"component_list": comps.slice(0, 12).map(func(c: Dictionary) -> Dictionary: return {"id": c.id, "nodes": c.nodes, "roads": c.roads.size(), "length_km": snappedf(c.length_m / 1000.0, 0.01),
			"center": [snappedf(c.center.x, 1.0), snappedf(c.center.z, 1.0)], "names": c.roads.slice(0, 4)})}
	var main_nodes := int(comps[0].nodes) if not comps.is_empty() else 0
	out["main_component_share"] = snappedf(float(main_nodes) / maxf(router.node_count(), 1.0), 0.001)
	# Isolated roads: a component that is one road.
	var isolated: Array = []
	for c: Dictionary in comps:
		if c.roads.size() == 1:
			var rd: RoadNetwork.Road = net.world[-(int(c.road_keys[0]) + 1)] if int(c.road_keys[0]) < 0 else net.built.get(int(c.road_keys[0]))
			var tag: String = intentional.get(rd.name, "")
			isolated.append({"name": rd.name, "class": String(rd.cls), "length_m": snappedf(c.length_m, 1.0), "from": _xz(rd.points[0]), "to": _xz(rd.points[rd.points.size() - 1]),
				"intentional": tag})
	out["isolated_roads"] = isolated.slice(0, max_issue_list)
	out["isolated_road_count"] = isolated.size()
	out["isolated_unexplained"] = isolated.filter(func(r: Dictionary) -> bool: return r.intentional == "").size()
	# Geometry.
	var geom := _geometry(max_issue_list)
	out.merge(geom)
	# Intersections.
	out.merge(_intersections(comp_of, max_issue_list))
	return out


static func _xz(p: Vector3) -> Array:
	return [snappedf(p.x, 1.0), snappedf(p.z, 1.0)]


func _geometry(max_list: int) -> Dictionary:
	var zero := 0
	var nan := 0
	var steep: Array = []
	var tight: Array = []
	var d := VehicleDefs.get_def(VehicleDefs.TRUCK)
	for r: RoadNetwork.Road in net.all_roads():
		var pts := r.points
		for k in pts.size():
			if is_nan(pts[k].x) or is_nan(pts[k].y) or is_nan(pts[k].z):
				nan += 1
				continue
			if k > 0:
				var l := Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
				if l < 0.05:
					zero += 1
				elif l > 0.5 and absf(pts[k].y - pts[k - 1].y) / l > d.max_grade and not _on_bridge(r, k):
					if steep.size() < max_list:
						steep.append({"road": r.name, "at": _xz(pts[k]), "grade": snappedf(absf(pts[k].y - pts[k - 1].y) / l, 0.01)})
			if k >= 2 and k % 3 == 0:
				var rad := VehicleSim._radius(pts, k - 2, k - 1, k)
				if is_finite(rad) and rad < MIN_RADIUS_M and Vector2(pts[k].x - pts[k - 2].x, pts[k].z - pts[k - 2].z).length() > 1.0 and tight.size() < max_list:
					tight.append({"road": r.name, "at": _xz(pts[k - 1]), "radius_m": snappedf(rad, 0.1)})
	return {"zero_length_segments": zero, "nan_points": nan, "steep_segments": steep, "tight_turns": tight, "tight_turn_count": tight.size()}


static func _on_bridge(r: RoadNetwork.Road, k: int) -> bool:
	for sp: Array in r.bridges:
		if k >= int(sp[0]) and k <= int(sp[1]):
			return true
	return false


## Roads crossing without a junction and near misses. For each pair of roads of different keys whose polyline segments cross
## or come within JOIN_GAP_M the nearest vertices are looked at: linked (same component through a direct junction link) is fine.
func _intersections(comp_of: Dictionary, max_list: int) -> Dictionary:
	var astar := router.astar
	# Spatial hash of road vertices: cell -> [node id]
	var broken: Array = []
	var near_miss: Array = []
	var checked := {}
	var roads := net.all_roads()
	var cell := 40.0
	var grid := {}
	for id: int in astar.get_point_ids():
		var p := astar.get_point_position(id)
		var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
		if not grid.has(c):
			grid[c] = []
		grid[c].append(id)
	for id: int in astar.get_point_ids():
		var rd: RoadNetwork.Road = router._node_road[id]
		if rd == null:
			continue
		var p := astar.get_point_position(id)
		var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for other: int in grid.get(c + Vector2i(dx, dz), []):
					var rr: RoadNetwork.Road = router._node_road[other]
					if rr == null or rr == rd or rr.key < rd.key:
						continue
					var q := astar.get_point_position(other)
					var dist := Vector2(p.x - q.x, p.z - q.z).length()
					if dist > JOIN_GAP_M or absf(p.y - q.y) > OVERPASS_M:
						continue
					var pair := "%d/%d" % [rd.key, rr.key]
					var best: Dictionary = checked.get(pair, {"d": INF})
					if dist < best.d:
						checked[pair] = {"d": dist, "a": p, "b": q, "ra": rd.name, "rb": rr.name, "linked": astar.are_points_connected(id, other), "ka": rd.key, "kb": rr.key}
	for pair: String in checked:
		var e: Dictionary = checked[pair]
		# A pair of roads that is joined anywhere within the neighbourhood is fine; judge by the closest approach.
		if e.d <= router.LINK_M:
			continue  # linked by the router (within LINK_M the vertices are joined automatically)
		var same: bool = comp_of.get(e.ka, -1) == comp_of.get(e.kb, -2)
		var entry := {"road_a": e.ra, "road_b": e.rb, "gap_m": snappedf(e.d, 0.1), "at": _xz((e.a + e.b) * 0.5), "same_component": same}
		# Only reported when they would be joined by a sensible junction: a short gap between roads that are not otherwise connected.
		if not same and e.d <= JOIN_GAP_M:
			near_miss.append(entry)
	near_miss.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.gap_m < b.gap_m)
	# Crossings of segments in XZ with a different component on each side and no link within LINK_M of the crossing.
	var crossings := _segment_crossings(roads, comp_of, max_list)
	return {"near_misses": near_miss.slice(0, max_list), "near_miss_count": near_miss.size(), "crossings_without_junction": crossings.list.slice(0, max_list), "crossing_count": crossings.count}


func _segment_crossings(roads: Array, comp_of: Dictionary, max_list: int) -> Dictionary:
	var cell := 64.0
	var seg_grid := {}
	var segs: Array = []
	for r: RoadNetwork.Road in roads:
		for k in range(1, r.points.size()):
			var a := r.points[k - 1]
			var b := r.points[k]
			var s := [r, k, Vector2(a.x, a.z), Vector2(b.x, b.z), a.y, b.y]
			var idx := segs.size()
			segs.append(s)
			var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
			var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
			for gx in range(floori(lo.x / cell), floori(hi.x / cell) + 1):
				for gz in range(floori(lo.y / cell), floori(hi.y / cell) + 1):
					var key := Vector2i(gx, gz)
					if not seg_grid.has(key):
						seg_grid[key] = []
					seg_grid[key].append(idx)
	var found := {}
	var list: Array = []
	var unlinked := 0
	for key: Vector2i in seg_grid:
		var ids: Array = seg_grid[key]
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var s1: Array = segs[ids[i]]
				var s2: Array = segs[ids[j]]
				var r1: RoadNetwork.Road = s1[0]
				var r2: RoadNetwork.Road = s2[0]
				if r1 == r2:
					continue
				var hit: Variant = Geometry2D.segment_intersects_segment(s1[2], s1[3], s2[2], s2[3])
				if hit == null:
					continue
				var pair := "%d/%d@%d,%d" % [mini(r1.key, r2.key), maxi(r1.key, r2.key), roundi(hit.x / 30.0), roundi(hit.y / 30.0)]
				if found.has(pair):
					continue
				var h1: float = lerpf(s1[4], s1[5], 0.5)
				var h2: float = lerpf(s2[4], s2[5], 0.5)
				if absf(h1 - h2) > OVERPASS_M:
					continue  # an overpass / a bridge over a road
				found[pair] = true
				# Linked if a vertex of each road within LINK_M of the crossing is joined in the graph.
				if _linked_near(hit, r1, r2):
					continue
				unlinked += 1
				if list.size() < max_list:
					list.append({"road_a": r1.name, "road_b": r2.name, "at": [snappedf(hit.x, 1.0), snappedf(hit.y, 1.0)],
						"same_component": comp_of.get(r1.key, -1) == comp_of.get(r2.key, -2)})
	return {"list": list, "count": unlinked}


## True when some vertex of road a and some vertex of road b, both within LINK_M * 2 of p, are joined in the router graph.
func _linked_near(p: Vector2, a: RoadNetwork.Road, b: RoadNetwork.Road) -> bool:
	var ids_a: Array = []
	var ids_b: Array = []
	for id: int in router._ids_of.get(a.key, []):
		var q := router.astar.get_point_position(id)
		if Vector2(q.x - p.x, q.z - p.y).length() <= router.LINK_M * 2.5:
			ids_a.append(id)
	for id: int in router._ids_of.get(b.key, []):
		var q := router.astar.get_point_position(id)
		if Vector2(q.x - p.x, q.z - p.y).length() <= router.LINK_M * 2.5:
			ids_b.append(id)
	for ia: int in ids_a:
		for ib: int in ids_b:
			if router.astar.are_points_connected(ia, ib):
				return true
	return false


# --- Locations ---------------------------------------------------------------------------------------------------------------------

## Strategic locations of the world: objectives, bases' docks, settlements and bridges. [{name, kind, pos}].
func locations(world_src := "") -> Array:
	var out: Array = []
	var war := sim.state.war
	for o: ObjectiveState in war.all_objectives():
		out.append({"name": o.obj_name, "kind": "objective:%s" % o.kind, "pos": o.position})
	for b: Dictionary in sim.state.construction.bases.values():
		out.append({"name": "base " + String(b.name), "kind": "base", "pos": b.anchor})
	for s in sim.state.construction.all():
		if FacilityDefs.has(s.type_id) and FacilityDefs.is_store(s.type_id):
			out.append({"name": "%s #%d" % [FacilityDefs.display_name(s.type_id), s.id], "kind": "dock", "pos": FacilityDefs.dock_point(s, 0)})
	if world_src != "":
		var sites: Variant = JSON.parse_string(FileAccess.get_file_as_string(world_src + "sites.json"))
		if sites is Dictionary:
			for st: Dictionary in sites.get("settlements", []):
				out.append({"name": String(st.name), "kind": "settlement", "pos": Vector3(st.pos[0], st.pos[1], st.pos[2])})
	if sim.war and sim.war.routes:
		var i := 0
		for b: Vector3 in sim.war.routes.bridges:
			out.append({"name": "bridge %d" % i, "kind": "bridge", "pos": b})
			i += 1
	for l: Dictionary in out:
		l.pos = Vector3(l.pos.x, sim.vehicles.ground_at(l.pos), l.pos.z)
	return out


## For one location: nearest road node, its component, and whether a truck can enter the road from there.
func probe_location(l: Dictionary, comp_of_node: Dictionary, def: VehicleDefs.Def) -> Dictionary:
	var near := router.nearest_nodes(l.pos, 1, 2500.0)
	if near.is_empty():
		return {"name": l.name, "kind": l.kind, "pos": _xz(l.pos), "road_dist_m": -1.0, "component": -1, "enter": "no road within 2.5 km"}
	var n: Dictionary = near[0]
	var acc := router.access_to_road(l.pos, def)
	var main_d := router.main_network_distance(l.pos, 12000.0)
	return {"name": l.name, "kind": l.kind, "pos": _xz(l.pos), "road": n.road.name, "road_dist_m": snappedf(n.dist, 1.0), "component": comp_of_node.get(n.id, -1),
		"enter": "ok" if acc.ok else acc.reason, "enter_ok": acc.ok, "main_network_m": snappedf(main_d, 1.0)}


## Component id per router node id.
func node_components() -> Dictionary:
	var out := {}
	var comps_seen := {}
	var next := 0
	var astar := router.astar
	for id: int in astar.get_point_ids():
		if comps_seen.has(id):
			continue
		var stack: Array[int] = [id]
		comps_seen[id] = true
		var members: Array[int] = []
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			members.append(cur)
			for nb: int in astar.get_point_connections(cur):
				if not comps_seen.has(nb):
					comps_seen[nb] = true
					stack.append(nb)
		for m in members:
			out[m] = next
		next += 1
	return out


## Full audit: the graph, every location, and the routes between all pairs of the given location kinds. `pairs` limits the
## routing to locations whose kind is in the list (default: everything important). The planner is the real VehicleRouter.plan.
## Returns the report; progress is reported through `step` (a Callable called between route plans, to await frames).
func run(world_src := "", pair_kinds: Array = ["objective:hq", "objective:town", "objective:village", "objective:bridge", "base", "dock"], step := Callable()) -> Dictionary:
	var rep := audit_graph()
	var d := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var comp_of_node := node_components()
	# component id by size for the report: nodes' component ids from node_components() are in discovery order, so use the sizes.
	var sizes := {}
	for id in comp_of_node:
		sizes[comp_of_node[id]] = int(sizes.get(comp_of_node[id], 0)) + 1
	var locs := locations(world_src)
	var probes: Array = []
	var no_access := 0
	for l: Dictionary in locs:
		var pr := probe_location(l, comp_of_node, d)
		pr["component_nodes"] = sizes.get(pr.get("component", -1), 0)
		pr["intentional"] = String(intentional.get(l.name, ""))
		if not pr.get("enter_ok", false):
			no_access += 1
		probes.append(pr)
	rep["locations"] = probes.size()
	rep["location_probes"] = probes
	rep["locations_without_road_entry"] = probes.filter(func(p: Dictionary) -> bool: return not p.get("enter_ok", false) and p.intentional == "").map(func(p: Dictionary) -> Dictionary: return {"name": p.name, "kind": p.kind, "pos": p.pos, "why": p.enter, "road_dist_m": p.road_dist_m})
	var main_comp_id := -1
	var best_sz := 0
	for k in sizes:
		if int(sizes[k]) > best_sz:
			best_sz = int(sizes[k])
			main_comp_id = int(k)
	var enter_ok := {}
	var cut_off := {}  # places farther from the main road network than a vehicle is routed across country: isolated by distance
	for pr in probes:
		enter_ok[pr.name] = pr.get("enter_ok", false)
		if int(pr.get("component", -1)) != main_comp_id and int(pr.get("component", -1)) >= 0:
			cut_off[pr.name] = "isolated: only the settlement's own streets are connected; the nearest road of the main network is %d m away across ground a truck cannot drive" % roundi(float(pr.get("main_network_m", -1.0)))
		if float(pr.get("main_network_m", 0.0)) > router.MAIN_SNAP_RADIUS or float(pr.get("main_network_m", 0.0)) < 0.0:
			cut_off[pr.name] = "isolated: the nearest road of the main network is %d m away (only the settlement's own streets)" % roundi(float(pr.get("main_network_m", -1.0)))
	# Routes between the important pairs.
	var important: Array = locs.filter(func(l: Dictionary) -> bool: return pair_kinds.has(String(l.kind)) or String(l.kind).begins_with("objective") and pair_kinds.has("objective"))
	var routes_ok := 0
	var failures: Array = []
	var total := 0
	var road_frac := 0.0
	var long_routes: Array = []
	for i in important.size():
		for j in important.size():
			if i == j:
				continue
			var a: Dictionary = important[i]
			var b: Dictionary = important[j]
			if _flat(a.pos, b.pos) < 60.0:
				continue
			total += 1
			var res := router.plan(a.pos, b.pos, d)
			if res.ok:
				routes_ok += 1
				road_frac += float(res.road_m) / maxf(float(res.length_m), 1.0)
				if long_routes.size() < 5 and float(res.length_m) > 6000.0:
					long_routes.append({"from": a.name, "to": b.name, "km": snappedf(float(res.length_m) / 1000.0, 0.1), "road_share": snappedf(float(res.road_m) / maxf(float(res.length_m), 1.0), 0.01)})
			else:
				# A place a vehicle cannot even get onto a road from (a village centre on a steep bank, in water) is a terrain fact, not a
				# road fault: it is reported apart (route_failures_terrain) and autonomous operations fall back to a foot march there.
				var tag := String(intentional.get(a.name, intentional.get(b.name, "")))
				if tag == "":
					tag = String(cut_off.get(a.name, cut_off.get(b.name, "")))
				if tag == "" and (not enter_ok.get(a.name, true) or not enter_ok.get(b.name, true)):
					tag = "terrain: the place cannot be entered by truck"
				failures.append({"from": a.name, "to": b.name, "from_pos": _xz(a.pos), "to_pos": _xz(b.pos), "reason": res.reason, "why": res.get("why", []),
					"intentional": tag})
			if step.is_valid():
				await step.call()
	rep["routes_planned"] = total
	rep["routes_ok"] = routes_ok
	var by_to := {}
	var by_from := {}
	for f in failures:
		by_to[f.to] = int(by_to.get(f.to, 0)) + 1
		by_from[f["from"]] = int(by_from.get(f["from"], 0)) + 1
	rep["route_failures_by_destination"] = by_to
	rep["route_failures_by_origin"] = by_from
	rep["route_failures"] = failures.slice(0, 60)
	rep["route_failure_count"] = failures.size()
	rep["route_failures_unexplained"] = failures.filter(func(f: Dictionary) -> bool: return f.intentional == "").size()
	rep["mean_road_share"] = snappedf(road_frac / maxf(routes_ok, 1.0), 0.01)
	rep["sample_long_routes"] = long_routes
	rep["plan_ms_max"] = snappedf(router.plan_ms_max, 0.1)
	return rep


## Why does a route between two places fail? The end candidates, the raw road path and the road vertices on it that a structure
## blocks (with where they are), for the log and the report. Reads the real router; changes nothing (disabled vertices are restored).
func diagnose_route(from: Vector3, to: Vector3, def: VehicleDefs.Def = null) -> Dictionary:
	if def == null:
		def = VehicleDefs.get_def(VehicleDefs.TRUCK)
	router.ensure_built()
	var out := {"from": _xz(from), "to": _xz(to)}
	var st := sim.structures
	var free := func(_id: int, pos: Vector3) -> bool:
		return st == null or not st.blocks_point(Vector2(pos.x, pos.z), router.road_clear_r(def))
	for tag in ["start", "end"]:
		var p: Vector3 = from if tag == "start" else to
		var raw := router.nearest_nodes(p, 3, router.SNAP_RADIUS)
		var fr := router.nearest_nodes(p, 3, router.SNAP_RADIUS, free)
		out[tag + "_raw"] = raw.map(func(n: Dictionary) -> Dictionary: return {"road": n.road.name, "dist": snappedf(n.dist, 1.0), "blocked": st != null and st.blocks_point(Vector2(n.pos.x, n.pos.z), router.road_clear_r(def))})
		out[tag + "_free"] = fr.map(func(n: Dictionary) -> Dictionary: return {"road": n.road.name, "dist": snappedf(n.dist, 1.0)})
		out[tag + "_leg_ok"] = router._leg(p, fr[0].pos, def).ok if not fr.is_empty() else false
	var a := router.nearest_nodes(from, 1, router.SNAP_RADIUS, free)
	var b := router.nearest_nodes(to, 1, router.SNAP_RADIUS, free)
	if not a.is_empty() and not b.is_empty():
		var raw_path := router.astar.get_id_path(a[0].id, b[0].id)
		out["raw_path_nodes"] = raw_path.size()
		var blocked := []
		for id in raw_path:
			var q := router.astar.get_point_position(id)
			if st != null and st.blocks_point(Vector2(q.x, q.z), router.road_clear_r(def)):
				blocked.append([snappedf(q.x, 1.0), snappedf(q.z, 1.0), router._node_road[id].name])
		out["blocked_on_path"] = blocked.size()
		out["blocked_samples"] = blocked.slice(0, 6)
		out["blocked_last"] = blocked.slice(-3)
	return out


## Why a straight cross-country line a -> b cannot be driven: the first sample that is wet, inside a structure, steeper than the
## vehicle's limit or off the terrain, with its position, and the height profile summary.
func leg_diagnosis(a: Vector3, b: Vector3, def: VehicleDefs.Def = null) -> Dictionary:
	if def == null:
		def = VehicleDefs.get_def(VehicleDefs.TRUCK)
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, ceili(d / 2.5))
	var prev_h := NAN
	var out := {"length_m": snappedf(d, 1.0), "wet_samples": 0, "blocked_samples": 0, "steep_samples": 0, "first_problem": "", "max_grade": 0.0}
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var h := router._height(p.x, p.z)
		var why := ""
		if is_nan(h):
			why = "off the terrain"
		else:
			if sim.structures and sim.structures.is_wet(p.x, p.z):
				out.wet_samples += 1
				why = "water"
			if sim.structures and sim.structures.blocks_point(Vector2(p.x, p.z), def.circle_r):
				out.blocked_samples += 1
				why = why if why != "" else "structure"
			if not is_nan(prev_h):
				var g := absf(h - prev_h) / maxf(d / n, 0.1)
				out.max_grade = maxf(out.max_grade, g)
				if g > def.max_grade:
					out.steep_samples += 1
					why = why if why != "" else "steep (%.2f)" % g
			prev_h = h
		if why != "" and out.first_problem == "":
			out.first_problem = "%s at (%.0f, %.0f) after %.0f m" % [why, p.x, p.z, d * float(k) / n]
	out.max_grade = snappedf(out.max_grade, 0.01)
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## A few lines of text for the log and the report.
func describe(rep: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Road graph: %d roads, %d nodes, %d edges, %d components (the largest holds %.1f %% of the nodes)" % [rep.roads, rep.nodes, rep.edges, rep.components, rep.main_component_share * 100.0])
	out.append("Isolated roads: %d (%d unexplained); near misses between roads: %d; crossings without a junction: %d" % [rep.isolated_road_count, rep.isolated_unexplained, rep.near_miss_count, rep.crossing_count])
	out.append("Geometry: %d zero-length segments, %d NaN points, %d steep segments listed, %d tight turns" % [rep.zero_length_segments, rep.nan_points, rep.steep_segments.size(), rep.tight_turn_count])
	if rep.has("locations"):
		out.append("Locations: %d, without a way onto a road: %d; routes %d/%d planned, failures %d (%d unexplained)" % [rep.locations, rep.locations_without_road_entry.size(), rep.routes_ok, rep.routes_planned, rep.route_failure_count, rep.route_failures_unexplained])
	return out


# --- NAV-PERF-01C: connectivity of what the running game navigates on ------------------------------------------------------------

## The router graph after its gap repairs and soft links, every bridge, and the strategic (infantry) grid:
##   * graph: components, the repaired gaps and soft links that join roads the data leaves apart, places off the main network;
##   * bridges: span vertices present and switched on, a path across the span through them, the deck known along its length,
##     the strategic cells open under it, an infantry route across laid on the deck, the walker's own test along the deck, the
##     vehicle types that fit;
##   * strategic grid: passable areas (4-connected), the places that lie outside the largest one.
## `places`: name -> position. Read-only: nothing in the world is changed.
func connectivity(places: Dictionary) -> Dictionary:
	router.ensure_built()
	var out := {}
	var comps := components()
	out["graph"] = {"nodes": router.astar.get_point_count(), "components": comps.size(), "main_nodes": comps[0].nodes if not comps.is_empty() else 0,
		"repaired_gaps": router.repaired_gaps.size(), "soft_links": router._soft.size(),
		"small_components": comps.slice(1, 12).map(func(c: Dictionary) -> Dictionary: return {"nodes": c.nodes, "roads": (c.roads as Array).slice(0, 4), "center": _xz(c.center)})}
	var off_main := []
	for n: String in places:
		var p: Vector3 = places[n]
		var d := router.main_network_distance(p, 12000.0)
		if d < 0.0 or d > 400.0:
			off_main.append({"place": n, "main_network_m": snappedf(d, 1.0)})
	out["places_far_from_main_network"] = off_main
	out["bridges"] = bridges_check()
	out["strategic_grid"] = strategic_components(places)
	return out


func bridges_check() -> Array:
	var rows := []
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	for b: RoadNetwork.Bridge in net.bridges:
		var rd: RoadNetwork.Road = net.world[-b.road_key - 1]
		var pts := rd.points
		var row := {"id": b.id, "name": b.name, "state": b.state_name(), "width_m": snappedf(b.width, 0.1), "length_m": snappedf(b.length_m, 0.1)}
		# Router: the span's vertices exist and are on; a path across goes through them.
		var ids: PackedInt32Array = router._ids_of.get(b.road_key, PackedInt32Array())
		var span_ok := ids.size() == pts.size()
		var off := 0
		for k in range(b.first, b.last + 1):
			if span_ok and router.astar.is_point_disabled(ids[k]):
				off += 1
		row["graph_vertices"] = span_ok
		row["graph_vertices_off"] = off
		var k0 := maxi(b.first - 12, 0)
		var k1 := mini(b.last + 12, pts.size() - 1)
		var across := PackedInt64Array()
		if span_ok:
			across = router.astar.get_id_path(ids[k0], ids[k1])
		var through := 0
		for id in across:
			if router._node_bridge.get(id) == b:
				through += 1
		row["graph_path_across"] = not across.is_empty() and through > 0
		# The deck along its centre line (every 2 m).
		var gaps := 0
		var samples := 0
		for k in range(b.first, b.last):
			var a := pts[k]
			var c := pts[k + 1]
			var n := maxi(1, ceili(Vector2(c.x - a.x, c.z - a.z).length() / 2.0))
			for j in n:
				samples += 1
				if is_nan(net.deck_height(a.lerp(c, float(j) / n))):
					gaps += 1
		row["deck_samples"] = samples
		row["deck_gaps"] = gaps
		# Infantry: the strategic cells under the span are open, a route across is laid on the deck, the walker can walk the deck.
		if routes:
			var closed_cells := 0
			for i: int in routes._bridge_cells.get(b.id, PackedInt32Array()):
				if routes.solid[i] == 1:
					closed_cells += 1
			row["strategic_cells_closed"] = closed_cells
			var a2 := pts[k0]
			var b2 := pts[k1]
			var r := routes.route(a2, b2, sim.terrain)
			var on_deck := 0
			for p in r:
				if net.bridge_at(p, 2.0) == b:
					on_deck += 1
			row["infantry_route_waypoints_on_deck"] = on_deck
			row["infantry_route_m"] = snappedf(routes.route_length(r), 1.0)
		var blocked_steps := 0
		for k in range(b.first, b.last):
			var a3 := pts[k]
			var c3 := pts[k + 1]
			var dir := Vector3(c3.x - a3.x, 0.0, c3.z - a3.z)
			var l3 := dir.length()
			if l3 < 0.01:
				continue
			dir /= l3
			for j in ceili(l3):
				var p3 := a3 + dir * float(j)
				p3.y = net.deck_height(p3) if not is_nan(net.deck_height(p3)) else p3.y
				if sim._step_blocked(p3, dir, 0.1):
					blocked_steps += 1
		row["walker_blocked_steps"] = blocked_steps
		row["fits"] = [VehicleDefs.TRUCK, VehicleDefs.APC].filter(func(t: StringName) -> bool: return b.admits(VehicleDefs.get_def(t).width))
		row["traversable"] = span_ok and off == 0 and row.graph_path_across and gaps == 0 and int(row.get("strategic_cells_closed", 0)) == 0 \
			and int(row.get("infantry_route_waypoints_on_deck", 1)) > 0 and blocked_steps == 0 and not (row.fits as Array).is_empty()
		rows.append(row)
	return rows


## Passable areas of the strategic grid (4-connected flood fill over `solid`), the places in each.
func strategic_components(places: Dictionary) -> Dictionary:
	var routes: StrategicRoutes = sim.war.routes if sim.war else null
	if routes == null or not routes.ready:
		return {}
	var nx := routes.size.x
	var nz := routes.size.y
	var comp := PackedInt32Array()
	comp.resize(nx * nz)
	comp.fill(-1)
	var sizes: Array[int] = []
	for start in nx * nz:
		if routes.solid[start] == 1 or comp[start] >= 0:
			continue
		var cid := sizes.size()
		var n := 0
		var stack := PackedInt32Array([start])
		comp[start] = cid
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			var x := i % nx
			var z := i / nx
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, z) + d
				if q.x < 0 or q.y < 0 or q.x >= nx or q.y >= nz:
					continue
				var j := q.y * nx + q.x
				if routes.solid[j] == 0 and comp[j] < 0:
					comp[j] = cid
					stack.append(j)
		sizes.append(n)
	var main := 0
	for c in sizes.size():
		if sizes[c] > sizes[main]:
			main = c
	var outside := []
	for nm: String in places:
		var cell := routes.nearest_passable(places[nm])
		var c2 := comp[cell.y * nx + cell.x] if cell.x >= 0 else -1
		if c2 != main:
			outside.append({"place": nm, "component_cells": sizes[c2] if c2 >= 0 else 0})
	var big := sizes.duplicate()
	big.sort()
	big.reverse()
	return {"passable_cells": sizes.reduce(func(a: int, b: int) -> int: return a + b, 0), "areas": sizes.size(), "largest": big.slice(0, 6),
		"main_share": snappedf(float(sizes[main]) / maxf(float(sizes.reduce(func(a: int, b: int) -> int: return a + b, 0)), 1.0), 0.001), "places_outside_main": outside}


## A vehicle route checked point by point (every route point, ~3 m): water off an open deck, structure footprints, grades over
## the vehicle's limit off decks, a closed deck. Returns counts and the first few places.
func vehicle_route_check(pts: PackedVector3Array, def: VehicleDefs.Def) -> Dictionary:
	var wet := 0
	var inside := 0
	var steep := 0
	var closed := 0
	var where := []
	var st := sim.structures
	for i in pts.size():
		var p := pts[i]
		var deck := not is_nan(net.deck_height(p))
		if deck and not net.deck_open(p):
			closed += 1
		if not deck and st and st.is_wet(p.x, p.z):
			wet += 1
			if where.size() < 5:
				where.append(["wet", _xz(p)])
		if st and st.blocks_point(Vector2(p.x, p.z), def.circle_r * 0.75):
			inside += 1
			if where.size() < 5:
				where.append(["structure", _xz(p)])
		# Grade over ~6 m (two route steps) with the median of three nearby height reads: Terrain3D's height query has 1 cm bands
		# 1-1.5 m off beside some vertices (NAV-INF-01), which a single 3 m step turns into a 50 % "slope".
		if i > 1 and not deck and is_nan(net.deck_height(pts[i - 2])):
			var q := pts[i - 2]
			var l := Vector2(p.x - q.x, p.z - q.z).length()
			var h1 := sim._infantry_height_robust(p.x, p.z)
			var h0 := sim._infantry_height_robust(q.x, q.z)
			if l > 1.0 and not is_nan(h0) and not is_nan(h1) and absf(h1 - h0) / l > def.max_grade * 1.15:
				steep += 1
				if where.size() < 5:
					where.append(["steep", _xz(p), snappedf(absf(h1 - h0) / l, 0.01)])
	return {"points": pts.size(), "wet": wet, "in_structure": inside, "steep": steep, "closed_deck": closed, "where": where,
		"ok": wet == 0 and inside == 0 and steep == 0 and closed == 0}
