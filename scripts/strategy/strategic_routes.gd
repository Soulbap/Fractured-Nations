## World-scale route planning for infantry (WORLD-SANDBOX-01).
##
## A 50 m passability grid over the whole 20 x 20 km map, built once from the world's own
## data and cached:
##   - terrain: Terrain3D heights; a cell steeper than max_slope_deg anywhere inside it
##     is impassable, gentler slopes cost more;
##   - water: the lakes (water.json outlines) and the river (centre line and width) are
##     impassable, except along the road bridges (roads.json bridge spans);
##   - roads: cheaper to walk (forces prefer them, as columns on the march do). Roads come
##     from the world's RoadNetwork (WORLD-PLAYTEST-01): the generated roads and the roads
##     the player builds, re-marked when the network changes (paved areas are not roads).
## Routes come from Godot's native AStarGrid2D on that grid (8 directions, no corner
## cutting past impassable cells), and are reduced to waypoints a squad can walk in
## straight lines: every straight leg is re-checked against the grid, so a leg never
## crosses water or a cliff that the cell path avoided. Squads then walk the waypoints
## with ordinary squad Move orders (SquadControl), bodies on the local navmesh near the
## camera, records in the abstract tier elsewhere.
##
## No navmesh for the world: the grid is 160 000 cells (two packed arrays), a long route
## costs a few milliseconds.
class_name StrategicRoutes
extends RefCounted

const CELL := 50.0
## Cache version: change when the grid rules change.
const VERSION := 4
var max_slope_deg := 32.0
## Road cells cost this much per metre; open ground 1.0, slopes more.
var road_cost := 0.45
var river_margin_m := 12.0

var size := Vector2i.ZERO
var origin := Vector2.ZERO
## 1 = impassable
var solid := PackedByteArray()
var weight := PackedFloat32Array()
## 1 = road / bridge cell (map display, statistics)
var road := PackedByteArray()
## 1 = water (lake / river)
var water := PackedByteArray()
var astar := AStarGrid2D.new()
var ready := false
var build_ms := 0.0
var loaded_from_cache := false
## Last route's cost (ms) and statistics.
var last_route_ms := 0.0
var routes_planned := 0
var route_ms_total := 0.0
var route_ms_max := 0.0
## NAVIGATION N1 diagnostics. A failed request is counted as a plan and retains only
## its reason and rounded endpoints; this is runtime instrumentation, not saved state.
var routes_failed := 0
var failure_reasons := {}
var last_failure := {}
var bridges: Array[Vector3] = []
## NAVIGATION N1-C1: bridge id -> PackedInt32Array of the grid cells under the bridge span. A closed or disabled bridge makes
## them impassable again (the river under the deck is water); the state itself lives in RoadNetwork.Bridge only.
var _bridge_cells := {}
## Grid cell index -> id of the bridge whose span lies in it (route() lays the deck itself as waypoints there).
var _cell_bridge := {}
## WORLD-PLAYTEST-01: the road network the grid follows, and the grid as built from the
## world alone (terrain, water, world roads), so built roads can be added and removed.
var network: RoadNetwork
var _base_solid := PackedByteArray()
var _base_weight := PackedFloat32Array()
var _base_road := PackedByteArray()
## Identity of the world data the cache was built from (file times and sizes).
var _fingerprint := ""


## Builds (or loads) the grid. half: half the map size (m); src: the world's source
## folder (roads.json, water.json); cache_path: user:// file.
## p_network: the world's roads (loaded from src when null or empty).
func setup(terrain: Terrain3D, half: float, src: String, cache_path: String, p_network: RoadNetwork = null) -> void:
	var t0 := Time.get_ticks_usec()
	var n := ceili(half * 2.0 / CELL)
	size = Vector2i(n, n)
	origin = Vector2(-half, -half)
	network = p_network if p_network else RoadNetwork.new()
	if network.world.is_empty():
		network.load_world(src)
	_read_bridges()
	# WORLD-PLAYTEST-01: a regenerated world (new terrain, roads or water) must not reuse a
	# grid cached from the old one.
	_fingerprint = fingerprint(src)
	if not _load_cache(cache_path):
		_build(terrain, src)
		_save_cache(cache_path)
	_base_solid = solid.duplicate()
	_base_weight = weight.duplicate()
	_base_road = road.duplicate()
	_setup_astar()
	_mark_built(Rect2(origin, Vector2(size) * CELL))
	_index_bridges()
	if not network.changed.is_connected(_on_roads_changed):
		network.changed.connect(_on_roads_changed)
	if not network.bridge_changed.is_connected(_on_bridge_changed):
		network.bridge_changed.connect(_on_bridge_changed)
	for b: RoadNetwork.Bridge in network.blocked_bridges():
		_on_bridge_changed(b)
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ready = true


## Times and sizes of the files the grid is derived from.
static func fingerprint(src: String) -> String:
	var parts := []
	for f in ["roads.json", "water.json", "height.r32"]:
		var path: String = src + f
		var sz := -1
		if FileAccess.file_exists(path):
			var fa := FileAccess.open(path, FileAccess.READ)
			if fa:
				sz = fa.get_length()
				fa.close()
		parts.append("%s:%d:%d" % [f, FileAccess.get_modified_time(path), sz])
	return ",".join(parts)


## Roads were built or removed in rect: the cells there go back to the world grid and the
## built roads crossing them are marked again.
func _on_roads_changed(rect: Rect2) -> void:
	if not ready:
		return
	var c0 := world_to_cell(Vector3(rect.position.x - CELL, 0, rect.position.y - CELL))
	var c1 := world_to_cell(Vector3(rect.end.x + CELL, 0, rect.end.y + CELL))
	for z in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
		for x in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
			var i := z * size.x + x
			solid[i] = _base_solid[i]
			weight[i] = _base_weight[i]
			road[i] = _base_road[i]
	_mark_built(rect.grow(CELL))
	# N1-C1: closed bridges stay closed when the cells under them were reset to the world grid.
	for b: RoadNetwork.Bridge in network.blocked_bridges():
		for i: int in _bridge_cells.get(b.id, PackedInt32Array()):
			solid[i] = 1
	for z in range(maxi(c0.y, 0), mini(c1.y, size.y - 1) + 1):
		for x in range(maxi(c0.x, 0), mini(c1.x, size.x - 1) + 1):
			_sync_point(Vector2i(x, z))


## Marks the built roads touching rect (the world roads are part of the cached grid).
func _mark_built(rect: Rect2) -> int:
	var n := 0
	for r: RoadNetwork.Road in network.roads_in(rect):
		if r.built:
			n += _mark_line(r.points, r.travel_cost, [], true)
	return n


## The grid cells under every bridge span, sampled like _mark_line samples the road (at least every quarter cell).
func _index_bridges() -> void:
	_bridge_cells.clear()
	_cell_bridge.clear()
	for b: RoadNetwork.Bridge in network.bridges:
		var idx := -b.road_key - 1
		if idx < 0 or idx >= network.world.size():
			continue
		var pts: PackedVector3Array = network.world[idx].points
		var seen := {}
		for k in range(b.first, mini(b.last, pts.size() - 1) + 1):
			var a := pts[k]
			var seg := 0.0 if k + 1 >= pts.size() else Vector2(pts[k + 1].x - a.x, pts[k + 1].z - a.z).length()
			var n := maxi(1, ceili(seg / (CELL * 0.25)))
			for j in n:
				var p := a if k + 1 >= pts.size() else a.lerp(pts[k + 1], float(j) / n)
				var c := world_to_cell(p)
				if _in(c):
					seen[c.y * size.x + c.x] = true
		_bridge_cells[b.id] = PackedInt32Array(seen.keys())
		for i: int in seen:
			_cell_bridge[i] = b.id


## A bridge was opened, closed or disabled: its cells are impassable (closed) or back to the world grid (open).
func _on_bridge_changed(b: RoadNetwork.Bridge) -> void:
	if not ready:
		return
	for i: int in _bridge_cells.get(b.id, PackedInt32Array()):
		solid[i] = _base_solid[i] if b.is_open() else 1
		_sync_point(Vector2i(i % size.x, i / size.x))


func _sync_point(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	astar.set_point_solid(c, solid[i] == 1)
	if solid[i] == 0:
		astar.set_point_weight_scale(c, weight[i])


func _setup_astar() -> void:
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for z in size.y:
		for x in size.x:
			var i := z * size.x + x
			if solid[i]:
				astar.set_point_solid(Vector2i(x, z), true)
			else:
				astar.set_point_weight_scale(Vector2i(x, z), weight[i])


# --- Build ---------------------------------------------------------------------------

func _build(terrain: Terrain3D, src: String) -> void:
	var count := size.x * size.y
	solid.resize(count)
	weight.resize(count)
	road.resize(count)
	water.resize(count)
	solid.fill(0)
	road.fill(0)
	water.fill(0)
	weight.fill(1.0)
	var tmax := tan(deg_to_rad(max_slope_deg))
	var h := CELL * 0.5
	for z in size.y:
		for x in size.x:
			var i := z * size.x + x
			var c := cell_center(Vector2i(x, z))
			var hc: float = terrain.data.get_height(c)
			if is_nan(hc):
				solid[i] = 1
				continue
			# Steepest of the eight half-cell steps from the centre.
			var steep := 0.0
			for d: Vector2 in [Vector2(h, 0), Vector2(-h, 0), Vector2(0, h), Vector2(0, -h), Vector2(h, h) * 0.7071, Vector2(-h, h) * 0.7071, Vector2(h, -h) * 0.7071, Vector2(-h, -h) * 0.7071]:
				var hh: float = terrain.data.get_height(c + Vector3(d.x, 0.0, d.y))
				if is_nan(hh):
					continue
				steep = maxf(steep, absf(hh - hc) / h)
			if steep > tmax:
				solid[i] = 1
			else:
				var s := steep / tmax
				weight[i] = 1.0 + 2.5 * s * s
	_mark_water(src)
	_mark_roads()


func _mark_water(src: String) -> void:
	var w: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "water.json"))
	if not w is Dictionary:
		return
	for lake: Dictionary in w.get("lakes", []):
		var poly := PackedVector2Array()
		for p: Array in lake.outline:
			poly.append(Vector2(p[0], p[1]))
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			bb = bb.expand(p)
		var c0 := world_to_cell(Vector3(bb.position.x - CELL, 0, bb.position.y - CELL))
		var c1 := world_to_cell(Vector3(bb.end.x + CELL, 0, bb.end.y + CELL))
		for z in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				if not _in(Vector2i(x, z)):
					continue
				var c := cell_center(Vector2i(x, z))
				var q := Vector2(c.x, c.z)
				if Geometry2D.is_point_in_polygon(q, poly) or _dist_to_poly(q, poly) < CELL * 0.5:
					_set_water(Vector2i(x, z))
	var river: Dictionary = w.get("river", {})
	var pts: Array = river.get("points", [])
	var widths: Array = river.get("width", [])
	for k in range(pts.size() - 1):
		var a := Vector2(pts[k][0], pts[k][1])
		var b := Vector2(pts[k + 1][0], pts[k + 1][1])
		var half_w: float = float(widths[k]) * 0.5 + river_margin_m if k < widths.size() else 30.0
		var c0 := world_to_cell(Vector3(minf(a.x, b.x) - half_w - CELL, 0, minf(a.y, b.y) - half_w - CELL))
		var c1 := world_to_cell(Vector3(maxf(a.x, b.x) + half_w + CELL, 0, maxf(a.y, b.y) + half_w + CELL))
		for z in range(c0.y, c1.y + 1):
			for x in range(c0.x, c1.x + 1):
				if not _in(Vector2i(x, z)):
					continue
				var c := cell_center(Vector2i(x, z))
				# A cell is water when the river covers any part of it (centre within
				# half width + half a cell diagonal): no gap for a path to slip through.
				if LineOfFire._point_segment_dist2d(Vector2(c.x, c.z), a, b) <= half_w + CELL * 0.35:
					_set_water(Vector2i(x, z))


func _set_water(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	solid[i] = 1
	water[i] = 1


## The world's roads (RoadNetwork.world, i.e. roads.json).
func _mark_roads() -> void:
	for rd: RoadNetwork.Road in network.world:
		_mark_line(rd.points, minf(road_cost, rd.travel_cost), rd.bridges, false)


## Marks the cells of one road polyline, sampled at least every quarter cell (world roads
## come every ~10 m, built roads every ~2 m). Bridge spans (with their approaches) open the
## river; elsewhere a road along the bank does not. Returns the number of cells marked.
func _mark_line(pts: PackedVector3Array, cost: float, spans: Array, sync_astar: bool) -> int:
	var n := 0
	var last := Vector2i(-1, -1)
	for k in pts.size():
		var samples: Array[Vector3] = [pts[k]]
		if k + 1 < pts.size():
			var seg := Vector2(pts[k + 1].x - pts[k].x, pts[k + 1].z - pts[k].z).length()
			var extra := floori(seg / (CELL * 0.25))
			for j in range(1, extra + 1):
				samples.append(pts[k].lerp(pts[k + 1], float(j) / (extra + 1)))
		var on_bridge := false
		for sp: Array in spans:
			if k >= int(sp[0]) - 3 and k <= int(sp[1]) + 3:
				on_bridge = true
		for p in samples:
			var c := world_to_cell(p)
			if not _in(c) or c == last:
				continue
			last = c
			var i := c.y * size.x + c.x
			if water[i] and not on_bridge:
				continue  # a road along the bank does not open the river
			if on_bridge:
				# The deck and its approach: passable across the river.
				solid[i] = 0
				water[i] = 0
			elif solid[i]:
				solid[i] = 0  # roads are cut into slopes: walkable
			road[i] = 1
			weight[i] = minf(weight[i], cost)
			n += 1
			if sync_astar:
				_sync_point(c)
	return n


func _read_bridges() -> void:
	bridges.clear()
	for rd: RoadNetwork.Road in network.world:
		for sp: Array in rd.bridges:
			var a := rd.points[int(sp[0])]
			var b := rd.points[int(sp[1])]
			if Vector2(a.x - b.x, a.z - b.z).length() >= 50.0:
				bridges.append((a + b) * 0.5)


# --- Cache --------------------------------------------------------------------------

func _load_cache(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = f.get_var()
	f.close()
	if not d is Dictionary or d.get("version", 0) != VERSION or d.get("size", Vector2i.ZERO) != size \
			or d.get("fingerprint", "") != _fingerprint:
		return false
	solid = d.solid
	weight = d.weight
	road = d.road
	water = d.water
	loaded_from_cache = true
	return true


func _save_cache(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_var({"version": VERSION, "size": size, "fingerprint": _fingerprint, "solid": solid, "weight": weight, "road": road, "water": water})
		f.close()


# --- Queries ------------------------------------------------------------------------

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.z - origin.y) / CELL))


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * CELL, 0.0, origin.y + (c.y + 0.5) * CELL)


func _in(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func passable(p: Vector3) -> bool:
	var c := world_to_cell(p)
	return _in(c) and solid[c.y * size.x + c.x] == 0


func is_water(p: Vector3) -> bool:
	var c := world_to_cell(p)
	return _in(c) and water[c.y * size.x + c.x] == 1


## The nearest passable cell to p (spiral search up to max_r cells).
func nearest_passable(p: Vector3, max_r := 12) -> Vector2i:
	var c := world_to_cell(p)
	if _in(c) and solid[c.y * size.x + c.x] == 0:
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := c + Vector2i(dx, dz)
				if _in(q) and solid[q.y * size.x + q.x] == 0:
					var d := Vector2(dx, dz).length()
					if d < best_d:
						best_d = d
						best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Waypoints (ground heights from the terrain) from `from` to `to`, the last one being
## `to` itself when it is passable. Empty when no route exists.
var native_astar_max_ms := 0.0


func route(from: Vector3, to: Vector3, terrain: Terrain3D) -> PackedVector3Array:
	var t0 := Time.get_ticks_usec()
	var out := PackedVector3Array()
	var a := nearest_passable(from)
	var b := nearest_passable(to)
	if a.x < 0 or b.x < 0:
		_fail_count(t0, from, to, "no passable endpoint")
		return out
	var astar_started := Time.get_ticks_usec()
	var cells := astar.get_id_path(a, b)
	native_astar_max_ms = maxf(native_astar_max_ms, (Time.get_ticks_usec() - astar_started) / 1000.0)
	if cells.is_empty():
		_fail_count(t0, from, to, "disconnected passable cells")
		return out
	# NAVIGATION N1-C1: where the cell path crosses a bridge, the waypoints are the deck itself (its road points), not the centres
	# of the 50 m cells under it - those lie up to 25 m beside the deck, in the river, where a walker cannot go. Everything
	# else is reduced as before: corners and every 4th cell, then each straight leg is re-checked against the grid and a leg
	# that crosses an impassable cell gets the cell path's midpoint inserted.
	var deck_flags := PackedByteArray()
	var i := 0
	var piece_start := 0
	while i < cells.size():
		var bid: String = _cell_bridge.get(cells[i].y * size.x + cells[i].x, "")
		if bid == "":
			i += 1
			continue
		var j := i
		while j + 1 < cells.size() and _cell_bridge.get(cells[j + 1].y * size.x + cells[j + 1].x, "") == bid:
			j += 1
		var deck := _deck_waypoints(bid, cells, i, j, from, to)
		if deck.is_empty():
			i = j + 1
			continue
		_simplify_cells(cells, piece_start, i - 1, out)
		deck_flags.resize(out.size())
		for p in deck:
			out.append(p)
		deck_flags.resize(out.size())
		for k in range(out.size() - deck.size(), out.size()):
			deck_flags[k] = 1
		piece_start = j + 1
		i = j + 1
	_simplify_cells(cells, piece_start, cells.size() - 1, out)
	deck_flags.resize(out.size())
	# Exact end points instead of cell centres where they are passable.
	if passable(from):
		out[0] = from
	if passable(to):
		out[out.size() - 1] = to
	for k in out.size():
		var q := out[k]
		var hh: float = terrain.data.get_height(q) if terrain else NAN
		out[k] = Vector3(q.x, q.y if is_nan(hh) else (maxf(hh, q.y) if deck_flags[k] == 1 else hh), q.z)
	_count(t0)
	return out


## Waypoints of a cell path piece cells[i0..i1] (inclusive) appended to out: corners and every 4th cell, refined where a straight
## leg would cross an impassable cell.
func _simplify_cells(cells: Array[Vector2i], i0: int, i1: int, out: PackedVector3Array) -> void:
	if i1 < i0:
		return
	var keep: Array[int] = [i0]
	for i in range(i0 + 1, i1):
		var d0 := cells[i] - cells[i - 1]
		var d1 := cells[i + 1] - cells[i]
		if d0 != d1 or i - keep[-1] >= 4:
			keep.append(i)
	if i1 > i0:
		keep.append(i1)
	var fixed: Array[int] = [keep[0]]
	for k in range(1, keep.size()):
		_refine(cells, fixed[-1], keep[k], fixed)
	for i in fixed:
		out.append(cell_center(cells[i]))


## The deck of bridge `bid` as waypoints in travel order when the cell run cells[i..j] crosses it (the path enters at one end
## and leaves at the other); an empty array when the path only touches the bridge's cells.
func _deck_waypoints(bid: String, cells: Array[Vector2i], i: int, j: int, from: Vector3, to: Vector3) -> PackedVector3Array:
	var b := network.get_bridge(bid)
	var out := PackedVector3Array()
	if b == null or network.world.size() < -b.road_key:
		return out
	var pts: PackedVector3Array = network.world[-b.road_key - 1].points
	var prev := from if i == 0 else cell_center(cells[i - 1])
	var nxt := to if j == cells.size() - 1 else cell_center(cells[j + 1])
	var first := pts[b.first]
	var last := pts[b.last]
	var enter_first := Vector2(prev.x - first.x, prev.z - first.z).length() < Vector2(prev.x - last.x, prev.z - last.z).length()
	var leave_first := Vector2(nxt.x - first.x, nxt.z - first.z).length() < Vector2(nxt.x - last.x, nxt.z - last.z).length()
	if enter_first == leave_first:
		return out
	var idx: Array[int] = []
	if enter_first:
		for k in range(b.first, b.last + 1):
			idx.append(k)
	else:
		for k in range(b.last, b.first - 1, -1):
			idx.append(k)
	var last_kept := Vector3.INF
	for n in idx.size():
		var p := pts[idx[n]]
		if n == 0 or n == idx.size() - 1 or Vector2(p.x - last_kept.x, p.z - last_kept.z).length() >= 25.0:
			out.append(p)
			last_kept = p
	return out


func _refine(cells: Array[Vector2i], i0: int, i1: int, out: Array[int]) -> void:
	if i1 - i0 <= 1 or _leg_clear(cell_center(cells[i0]), cell_center(cells[i1])):
		out.append(i1)
		return
	var m := (i0 + i1) / 2
	_refine(cells, i0, m, out)
	_refine(cells, m, i1, out)


## True when the straight leg crosses no impassable cell (sampled every quarter cell).
func _leg_clear(a: Vector3, b: Vector3) -> bool:
	var n := maxi(1, ceili(Vector2(a.x - b.x, a.z - b.z).length() / (CELL * 0.25)))
	for k in n + 1:
		if not passable(a.lerp(b, float(k) / n)):
			return false
	return true


func route_length(r: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, r.size()):
		l += Vector2(r[i].x - r[i - 1].x, r[i].z - r[i - 1].z).length()
	return l


func _count(t0: int) -> void:
	last_route_ms = (Time.get_ticks_usec() - t0) / 1000.0
	routes_planned += 1
	route_ms_total += last_route_ms
	route_ms_max = maxf(route_ms_max, last_route_ms)


func _fail_count(t0: int, from: Vector3, to: Vector3, reason: String) -> void:
	_count(t0)
	routes_failed += 1
	failure_reasons[reason] = int(failure_reasons.get(reason, 0)) + 1
	last_failure = {
		"reason": reason,
		"from": [snappedf(from.x, 0.1), snappedf(from.z, 0.1)],
		"to": [snappedf(to.x, 0.1), snappedf(to.z, 0.1)],
		"ms": snappedf(last_route_ms, 0.01),
		"closed_bridges": network.blocked_bridges().map(func(b: RoadNetwork.Bridge) -> String: return b.id),
	}


static func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, LineOfFire._point_segment_dist2d(p, poly[i], poly[(i + 1) % poly.size()]))
	return best


## NAV-PERF-01B: one route() as a RouteService job ("infantry"). Measured on ref_20km the whole search is 0.4-2.5 ms for 3-27 km
## routes (the native A* over the 50 m grid 0.05-1.5 ms of it), so it is one step and not split further; the service runs as many
## of them per frame as its budget holds. Result: {ok, route, reason}.
class Runner:
	var routes: StrategicRoutes
	var from: Vector3
	var to: Vector3
	var terrain: Terrain3D
	var result := {}

	func _init(p_routes: StrategicRoutes, p_from: Vector3, p_to: Vector3, p_terrain: Terrain3D) -> void:
		routes = p_routes
		from = p_from
		to = p_to
		terrain = p_terrain

	func step(_deadline_us: int) -> bool:
		var r := routes.route(from, to, terrain)
		result = {"ok": r.size() >= 2, "route": r, "reason": "" if r.size() >= 2 else String(routes.last_failure.get("reason", "no route"))}
		return true

	func reset() -> void:
		result = {}


## The dedupe key of a route search: requests from the same 50 m cell to the same 50 m cell are one search.
func job_key(from: Vector3, to: Vector3) -> String:
	var a := world_to_cell(from)
	var b := world_to_cell(to)
	return "inf:%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]
