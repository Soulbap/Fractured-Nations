## Bounded local A* adapter for movement systems that need to refine a short route.
##
## The caller owns world knowledge through two callbacks: height_at(x, z) and
## blocked_at(x, z). This keeps vehicle dimensions, infantry clearance and dynamic
## obstacle rules out of the planner. N1-A uses it for abstract infantry; the API stays
## profile-neutral so another existing movement owner can adopt it later without a copy.
##
## NAV-INF-01: the grid is coarse (5 m cells, grade between nodes), the walker's own test is not (a local 50 degree bank inside a
## cell, a 1 m ledge between two nodes). A route that passes the grid but fails the walker's test is not a route: the walker
## stops at the bank, asks for a new plan and gets the same route again. `walk_check` is that test; the planner walks the
## finished route with it and, where it fails, closes the steep ground it found (the cell and the connected cells that fail
## it too) and plans again, so what leaves the planner is walkable by the rule that will be used to walk it.
class_name LocalRoutePlanner
extends RefCounted

## How many times a route that fails the walker's test is repaired before the planner says the ground is not passable.
const MAX_REPAIRS := 6
## The most cells one repair closes (a bank is closed along its length, not the whole grid).
const MAX_CLOSE_CELLS := 24


static func plan(a: Vector3, b: Vector3, cell: float, max_cells: int, max_grade: float,
		height_at: Callable, blocked_at: Callable, margin_min := 45.0,
		margin_factor := 0.35, sample_corners := false, string_pull := true,
		walk_check := Callable(), walk_step := 1.0) -> Dictionary:
	var started := Time.get_ticks_usec()
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	var margin := maxf(margin_min, Vector2(b.x - a.x, b.z - a.z).length() * margin_factor)
	lo -= Vector2.ONE * margin
	hi += Vector2.ONE * margin
	var nx := maxi(1, ceili((hi.x - lo.x) / cell))
	var nz := maxi(1, ceili((hi.y - lo.y) / cell))
	if nx * nz > max_cells:
		return _failed("cell budget exceeded", started, nx * nz)

	var heights := PackedFloat32Array()
	heights.resize((nx + 1) * (nz + 1))
	for z in nz + 1:
		for x in nx + 1:
			heights[z * (nx + 1) + x] = float(height_at.call(lo.x + x * cell, lo.y + z * cell))

	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, nx, nz)
	grid.cell_size = Vector2(cell, cell)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var blocked := PackedByteArray()
	blocked.resize(nx * nz)
	var max_dh := max_grade * cell
	for z in nz:
		for x in nx:
			var h00 := heights[z * (nx + 1) + x]
			var h10 := heights[z * (nx + 1) + x + 1]
			var h01 := heights[(z + 1) * (nx + 1) + x]
			var bad := is_nan(h00) or absf(h10 - h00) > max_dh or absf(h01 - h00) > max_dh
			var cx := lo.x + (x + 0.5) * cell
			var cz := lo.y + (z + 0.5) * cell
			if not bad:
				bad = bool(blocked_at.call(cx, cz))
			if not bad and sample_corners:
				var off := cell * 0.42
				for d in [Vector2(-off, -off), Vector2(off, -off), Vector2(-off, off), Vector2(off, off)]:
					if bool(blocked_at.call(cx + d.x, cz + d.y)):
						bad = true
						break
			if bad:
				blocked[z * nx + x] = 1
				grid.set_point_solid(Vector2i(x, z), true)

	var ca := _end_cell(blocked, nx, nz, lo, cell, a, walk_check, true)
	var cb := _end_cell(blocked, nx, nz, lo, cell, b, walk_check, false)
	if ca.x < 0 or cb.x < 0:
		return _failed("endpoint enclosed", started, nx * nz)
	var pts := PackedVector3Array()
	var repairs := 0
	while true:
		var path := grid.get_id_path(ca, cb)
		if path.is_empty():
			return _failed("no walkable local passage" if repairs > 0 else "no local passage", started, nx * nz)

		# String-pull the grid path. The conservative line test keeps adjacent blocked cells
		# out of the shortcut, important for vehicles and infantry beside thin walls.
		var kept: Array[Vector2i] = []
		if string_pull:
			kept.append(path[0])
			var i := 0
			while i < path.size() - 1:
				var j := path.size() - 1
				while j > i + 1 and not _grid_clear(blocked, nx, nz, path[i], path[j]):
					j -= 1
				kept.append(path[j])
				i = j
		else:
			for c in path:
				kept.append(c)
		pts = PackedVector3Array([a])
		for c in kept:
			var p := Vector3(lo.x + (c.x + 0.5) * cell, 0.0, lo.y + (c.y + 0.5) * cell)
			p.y = float(height_at.call(p.x, p.z))
			pts.append(p)
		pts.append(b)
		if not walk_check.is_valid():
			break
		var bad := first_unwalkable(pts, walk_check, walk_step)
		if not bad.is_finite():
			break
		repairs += 1
		if repairs > MAX_REPAIRS:
			return _failed("route crosses steep ground", started, nx * nz)
		var bc := Vector2i(clampi(int((bad.x - lo.x) / cell), 0, nx - 1), clampi(int((bad.z - lo.y) / cell), 0, nz - 1))
		_close_steep(grid, blocked, nx, nz, lo, cell, bc, walk_check)
		# The endpoints may now sit in closed ground: the nearest open cell takes over, as at the start.
		ca = _end_cell(blocked, nx, nz, lo, cell, a, walk_check, true)
		cb = _end_cell(blocked, nx, nz, lo, cell, b, walk_check, false)
		if ca.x < 0 or cb.x < 0:
			return _failed("endpoint enclosed", started, nx * nz)
	return {"ok": true, "pts": pts, "reason": "", "cells": nx * nz, "repairs": repairs,
		"ms": (Time.get_ticks_usec() - started) / 1000.0}


static func _failed(reason: String, started: int, cells: int) -> Dictionary:
	return {"ok": false, "pts": PackedVector3Array(), "reason": reason, "cells": cells,
		"ms": (Time.get_ticks_usec() - started) / 1000.0}


## The open cell an endpoint enters the grid through: the nearest one (rings of cells round the endpoint, as _free_cell) whose
## centre the walker can actually reach from `p` (outward) or leave towards `p` (inward). A walker standing at the foot of a bank
## must not be asked to start with a step up the bank because that is where the nearest cell centre happens to lie.
static func _end_cell(blocked: PackedByteArray, nx: int, nz: int, lo: Vector2, cell: float, p: Vector3, walk_check: Callable,
		outward: bool) -> Vector2i:
	var c0 := Vector2i(clampi(int((p.x - lo.x) / cell), 0, nx - 1), clampi(int((p.z - lo.y) / cell), 0, nz - 1))
	for r in range(0, 6):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var q := c0 + Vector2i(dx, dz)
				if q.x < 0 or q.y < 0 or q.x >= nx or q.y >= nz or blocked[q.y * nx + q.x] != 0:
					continue
				var centre := Vector3(lo.x + (q.x + 0.5) * cell, 0.0, lo.y + (q.y + 0.5) * cell)
				var d := Vector2(centre.x - p.x, centre.z - p.z).length()
				if d >= best_d:
					continue
				if walk_check.is_valid():
					var leg := PackedVector3Array([p, centre] if outward else [centre, p])
					if first_unwalkable(leg, walk_check, 1.0).is_finite():
						continue
				best = q
				best_d = d
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


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


static func _grid_clear(blocked: PackedByteArray, nx: int, _nz: int, a: Vector2i, b: Vector2i) -> bool:
	var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
	for k in range(1, n):
		var t := float(k) / n
		var x := lerpf(a.x, b.x, t)
		var y := lerpf(a.y, b.y, t)
		if blocked[roundi(y) * nx + roundi(x)] == 1:
			return false
		if blocked[floori(y) * nx + floori(x)] == 1 or blocked[ceili(y) * nx + ceili(x)] == 1:
			return false
	return true


## The first place along the route (every `step` metres) where the walker's own test says the next metre cannot be walked, or INF.
## walk_check(position, direction, step) -> true when blocked; the same call the walker makes each tick.
static func first_unwalkable(pts: PackedVector3Array, walk_check: Callable, step: float) -> Vector3:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var d := Vector3(pts[i + 1].x - a.x, 0.0, pts[i + 1].z - a.z)
		var seg_len := d.length()
		if seg_len < 0.01:
			continue
		d /= seg_len
		var n := maxi(1, ceili(seg_len / step))
		for k in n:
			var p := a + d * minf(k * step, seg_len)
			if bool(walk_check.call(p, d, 0.1)):
				return p
	return Vector3.INF


## Closes the steep ground at cell `c` and the neighbouring cells that fail the walker's test too (a bank runs on: closing one
## cell would only move the crossing one cell along). A cell is steep when a probe lattice inside it, walked in the four axis
## directions, fails the test.
static func _close_steep(grid: AStarGrid2D, blocked: PackedByteArray, nx: int, nz: int, lo: Vector2, cell: float, c: Vector2i,
		walk_check: Callable) -> void:
	var queue: Array[Vector2i] = [c]
	var seen := {c: true}
	var closed := 0
	_mark(grid, blocked, nx, c)
	while not queue.is_empty() and closed < MAX_CLOSE_CELLS:
		var q: Vector2i = queue.pop_front()
		closed += 1
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := q + Vector2i(dx, dz)
				if (dx == 0 and dz == 0) or seen.has(n) or n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz:
					continue
				seen[n] = true
				if blocked[n.y * nx + n.x] == 1:
					continue
				if _cell_steep(lo, cell, n, walk_check):
					_mark(grid, blocked, nx, n)
					queue.append(n)


static func _mark(grid: AStarGrid2D, blocked: PackedByteArray, nx: int, c: Vector2i) -> void:
	blocked[c.y * nx + c.x] = 1
	grid.set_point_solid(c, true)


static func _cell_steep(lo: Vector2, cell: float, c: Vector2i, walk_check: Callable) -> bool:
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	var n := 4
	for iz in n:
		for ix in n:
			var p := Vector3(lo.x + (c.x + (ix + 0.5) / n) * cell, 0.0, lo.y + (c.y + (iz + 0.5) / n) * cell)
			for d in dirs:
				if bool(walk_check.call(p, d, 0.1)):
					return true
	return false
