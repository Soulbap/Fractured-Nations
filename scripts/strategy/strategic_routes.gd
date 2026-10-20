## World-scale route planning for infantry (WORLD-SANDBOX-01).
##
## A 50 m passability grid over the whole 20 x 20 km map, built once from the world's own
## data and cached:
##   - terrain: Terrain3D heights; a cell steeper than max_slope_deg anywhere inside it
##     is impassable, gentler slopes cost more;
##   - water: the lakes (water.json outlines) and the river (centre line and width) are
##     impassable, except along the road bridges (roads.json bridge spans);
##   - roads: cheaper to walk (forces prefer them, as columns on the march do).
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
const VERSION := 3
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
var bridges: Array[Vector3] = []


## Builds (or loads) the grid. half: half the map size (m); src: the world's source
## folder (roads.json, water.json); cache_path: user:// file.
func setup(terrain: Terrain3D, half: float, src: String, cache_path: String) -> void:
	var t0 := Time.get_ticks_usec()
	var n := ceili(half * 2.0 / CELL)
	size = Vector2i(n, n)
	origin = Vector2(-half, -half)
	_read_bridges(src)
	if not _load_cache(cache_path):
		_build(terrain, src)
		_save_cache(cache_path)
	_setup_astar()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ready = true


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
	_mark_roads(src)


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


func _mark_roads(src: String) -> void:
	var r: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "roads.json"))
	if not r is Dictionary:
		return
	for rd: Dictionary in r.roads:
		var pts: Array = rd.points
		var spans: Array = rd.get("bridges", [])
		for k in pts.size():
			var p := Vector3(pts[k][0], pts[k][1], pts[k][2])
			var c := world_to_cell(p)
			if not _in(c):
				continue
			var i := c.y * size.x + c.x
			var on_bridge := false
			for s: Array in spans:
				if k >= int(s[0]) - 3 and k <= int(s[1]) + 3:
					on_bridge = true
			if water[i] and not on_bridge:
				continue  # a road along the bank does not open the river
			if on_bridge:
				# The deck and its approach: passable across the river.
				solid[i] = 0
				water[i] = 0
			elif solid[i]:
				solid[i] = 0  # roads are cut into slopes: walkable
			road[i] = 1
			weight[i] = minf(weight[i], road_cost)


func _read_bridges(src: String) -> void:
	bridges.clear()
	var r: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "roads.json"))
	if not r is Dictionary:
		return
	for rd: Dictionary in r.roads:
		for s: Array in rd.get("bridges", []):
			var a: Array = rd.points[int(s[0])]
			var b: Array = rd.points[int(s[1])]
			if Vector2(a[0] - b[0], a[2] - b[2]).length() >= 50.0:
				bridges.append(Vector3((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5))


# --- Cache --------------------------------------------------------------------------

func _load_cache(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = f.get_var()
	f.close()
	if not d is Dictionary or d.get("version", 0) != VERSION or d.get("size", Vector2i.ZERO) != size:
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
		f.store_var({"version": VERSION, "size": size, "solid": solid, "weight": weight, "road": road, "water": water})
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
func route(from: Vector3, to: Vector3, terrain: Terrain3D) -> PackedVector3Array:
	var t0 := Time.get_ticks_usec()
	var out := PackedVector3Array()
	var a := nearest_passable(from)
	var b := nearest_passable(to)
	if a.x < 0 or b.x < 0:
		return out
	var cells := astar.get_id_path(a, b)
	if cells.is_empty():
		_count(t0)
		return out
	# Keep corners and every 4th cell, then re-check each straight leg on the grid; a
	# leg that crosses an impassable cell gets the cell path's midpoint inserted.
	var keep: Array[int] = [0]
	for i in range(1, cells.size() - 1):
		var d0 := cells[i] - cells[i - 1]
		var d1 := cells[i + 1] - cells[i]
		if d0 != d1 or i - keep[-1] >= 4:
			keep.append(i)
	if cells.size() > 1:
		keep.append(cells.size() - 1)
	var fixed: Array[int] = [keep[0]]
	for k in range(1, keep.size()):
		_refine(cells, fixed[-1], keep[k], fixed)
	for i in fixed:
		var p := cell_center(cells[i])
		out.append(p)
	# Exact end points instead of cell centres where they are passable.
	if passable(from):
		out[0] = from
	if passable(to):
		out[out.size() - 1] = to
	for i in out.size():
		var q := out[i]
		var hh: float = terrain.data.get_height(q) if terrain else NAN
		out[i] = Vector3(q.x, q.y if is_nan(hh) else hh, q.z)
	_count(t0)
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


static func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, LineOfFire._point_segment_dist2d(p, poly[i], poly[(i + 1) % poly.size()]))
	return best
