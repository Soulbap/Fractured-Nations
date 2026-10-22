## Bounded local A* adapter for movement systems that need to refine a short route.
##
## The caller owns world knowledge through two callbacks: height_at(x, z) and
## blocked_at(x, z). This keeps vehicle dimensions, infantry clearance and dynamic
## obstacle rules out of the planner. N1-A uses it for abstract infantry; the API stays
## profile-neutral so another existing movement owner can adopt it later without a copy.
class_name LocalRoutePlanner
extends RefCounted


static func plan(a: Vector3, b: Vector3, cell: float, max_cells: int, max_grade: float,
		height_at: Callable, blocked_at: Callable, margin_min := 45.0,
		margin_factor := 0.35, sample_corners := false, string_pull := true) -> Dictionary:
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

	var ca := Vector2i(clampi(int((a.x - lo.x) / cell), 0, nx - 1), clampi(int((a.z - lo.y) / cell), 0, nz - 1))
	var cb := Vector2i(clampi(int((b.x - lo.x) / cell), 0, nx - 1), clampi(int((b.z - lo.y) / cell), 0, nz - 1))
	ca = _free_cell(blocked, nx, nz, ca)
	cb = _free_cell(blocked, nx, nz, cb)
	if ca.x < 0 or cb.x < 0:
		return _failed("endpoint enclosed", started, nx * nz)
	var path := grid.get_id_path(ca, cb)
	if path.is_empty():
		return _failed("no local passage", started, nx * nz)

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
	var pts := PackedVector3Array([a])
	for c in kept:
		var p := Vector3(lo.x + (c.x + 0.5) * cell, 0.0, lo.y + (c.y + 0.5) * cell)
		p.y = float(height_at.call(p.x, p.z))
		pts.append(p)
	pts.append(b)
	return {"ok": true, "pts": pts, "reason": "", "cells": nx * nz,
		"ms": (Time.get_ticks_usec() - started) / 1000.0}


static func _failed(reason: String, started: int, cells: int) -> Dictionary:
	return {"ok": false, "pts": PackedVector3Array(), "reason": reason, "cells": cells,
		"ms": (Time.get_ticks_usec() - started) / 1000.0}


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
