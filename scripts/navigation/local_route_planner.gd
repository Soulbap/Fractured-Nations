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
static var native_astar_max_ms := 0.0


static func plan(a: Vector3, b: Vector3, cell: float, max_cells: int, max_grade: float,
		height_at: Callable, blocked_at: Callable, margin_min := 45.0,
		margin_factor := 0.35, sample_corners := false, string_pull := true,
		walk_check := Callable(), walk_step := 1.0) -> Dictionary:
	var s := Search.new(a, b, cell, max_cells, max_grade, height_at, blocked_at, margin_min, margin_factor, sample_corners,
		string_pull, walk_check, walk_step)
	while not s.step(0):
		pass
	return s.result


## NAV-PERF-01B: the same search, resumable. `step(deadline_us)` works until the deadline (Time.get_ticks_usec(); 0 = no deadline)
## and returns true when `result` is final. The grid is built a few dozen cells at a time (heights, then the blocked cells), the
## native A* runs on the finished grid (one call), and the walker's check and the repairs run between checkpoints too. The answer
## is the one plan() always gave: plan() is this object run without a deadline. Used as a RouteService runner (WorldSim).
class Search:
	## Work between two deadline checks in the grid loops (cells): heights are one read each, a blocked cell up to five obstacle
	## tests (near the river a water test walks many triangles).
	const CHUNK := 48
	const CHUNK_CELLS := 8
	var a: Vector3
	var b: Vector3
	var cell: float
	var max_cells: int
	var max_grade: float
	var height_at: Callable
	var blocked_at: Callable
	var margin_min: float
	var margin_factor: float
	var sample_corners: bool
	var string_pull: bool
	var walk_check: Callable
	var walk_step: float
	var result := {}
	## Grid rectangle (XZ) the search reads.
	var area: Rect2
	var _phase := 0
	var _i := 0
	var _lo := Vector2.ZERO
	var _nx := 0
	var _nz := 0
	var _heights := PackedFloat32Array()
	var _blocked := PackedByteArray()
	var _grid: AStarGrid2D
	var _ca := Vector2i(-1, -1)
	var _cb := Vector2i(-1, -1)
	var _pts := PackedVector3Array()
	var _repairs := 0
	var _work_us := 0
	var _walk: Walk = null
	var _end_a: EndCell = null
	var _end_b: EndCell = null
	var _cq: Array = []
	var _cseen := {}
	var _cclosed := 0
	var _cnode := Vector2i.ZERO
	var _cn := 0
	var _cprobe := 0
	var _cactive := false

	func _init(p_a: Vector3, p_b: Vector3, p_cell: float, p_max_cells: int, p_max_grade: float, p_height_at: Callable,
			p_blocked_at: Callable, p_margin_min := 45.0, p_margin_factor := 0.35, p_sample_corners := false, p_string_pull := true,
			p_walk_check := Callable(), p_walk_step := 1.0) -> void:
		a = p_a
		b = p_b
		cell = p_cell
		max_cells = p_max_cells
		max_grade = p_max_grade
		height_at = p_height_at
		blocked_at = p_blocked_at
		margin_min = p_margin_min
		margin_factor = p_margin_factor
		sample_corners = p_sample_corners
		string_pull = p_string_pull
		walk_check = p_walk_check
		walk_step = p_walk_step
		area = area_for(a, b, cell, margin_min, margin_factor)
		_lo = area.position
		_nx = roundi(area.size.x / cell)
		_nz = roundi(area.size.y / cell)

	## The grid rectangle (XZ) a search from a to b reads: the box round both ends plus the margin, in whole cells.
	static func area_for(p_a: Vector3, p_b: Vector3, p_cell: float, p_margin_min: float, p_margin_factor: float) -> Rect2:
		var lo := Vector2(minf(p_a.x, p_b.x), minf(p_a.z, p_b.z))
		var hi := Vector2(maxf(p_a.x, p_b.x), maxf(p_a.z, p_b.z))
		var margin := maxf(p_margin_min, Vector2(p_b.x - p_a.x, p_b.z - p_a.z).length() * p_margin_factor)
		lo -= Vector2.ONE * margin
		hi += Vector2.ONE * margin
		var nx := maxi(1, ceili((hi.x - lo.x) / p_cell))
		var nz := maxi(1, ceili((hi.y - lo.y) / p_cell))
		return Rect2(lo, Vector2(nx, nz) * p_cell)

	## Back to the beginning (the world changed under the search).
	func reset() -> void:
		_phase = 0
		_i = 0
		_heights = PackedFloat32Array()
		_blocked = PackedByteArray()
		_grid = null
		_pts = PackedVector3Array()
		_repairs = 0
		_work_us = 0
		_walk = null
		_end_a = null
		_end_b = null
		_cq = []
		_cseen = {}
		_cclosed = 0
		_cn = 0
		_cprobe = 0
		_cactive = false
		result = {}

	func cells() -> int:
		return _nx * _nz

	## Where the search stands (RouteService diagnostics).
	func debug_state() -> Dictionary:
		return {"phase": _phase, "i": _i, "cells": _nx * _nz, "repairs": _repairs, "close_queue": _cq.size(), "closed": _cclosed}

	func step(deadline_us: int) -> bool:
		var t0 := Time.get_ticks_usec()
		var done := _run(deadline_us)
		_work_us += Time.get_ticks_usec() - t0
		if done:
			result["ms"] = _work_us / 1000.0
		return done

	func _late(deadline_us: int) -> bool:
		return deadline_us > 0 and Time.get_ticks_usec() >= deadline_us

	func _run(deadline_us: int) -> bool:
		var nx := _nx
		var nz := _nz
		var lo := _lo
		while true:
			match _phase:
				0:
					if nx * nz > max_cells:
						result = LocalRoutePlanner._failed("cell budget exceeded", 0, nx * nz)
						return true
					_heights.resize((nx + 1) * (nz + 1))
					_i = 0
					_phase = 1
				1:
					# Heights at the cell corners.
					var n := (nx + 1) * (nz + 1)
					while _i < n:
						var end := mini(_i + CHUNK, n)
						for k in range(_i, end):
							_heights[k] = float(height_at.call(lo.x + (k % (nx + 1)) * cell, lo.y + (k / (nx + 1)) * cell))
						_i = end
						if _i < n and _late(deadline_us):
							return false
					_grid = AStarGrid2D.new()
					_grid.region = Rect2i(0, 0, nx, nz)
					_grid.cell_size = Vector2(cell, cell)
					_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
					_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
					_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
					_grid.update()
					_blocked.resize(nx * nz)
					_i = 0
					_phase = 2
				2:
					# Blocked cells: too steep between corners, or the caller's obstacle test at the centre (and corners).
					var n2 := nx * nz
					var max_dh := max_grade * cell
					var off := cell * 0.42
					while _i < n2:
						var end2 := mini(_i + CHUNK_CELLS, n2)
						for k in range(_i, end2):
							var x := k % nx
							var z := k / nx
							var h00 := _heights[z * (nx + 1) + x]
							var h10 := _heights[z * (nx + 1) + x + 1]
							var h01 := _heights[(z + 1) * (nx + 1) + x]
							var bad := is_nan(h00) or absf(h10 - h00) > max_dh or absf(h01 - h00) > max_dh
							var cx := lo.x + (x + 0.5) * cell
							var cz := lo.y + (z + 0.5) * cell
							if not bad:
								bad = bool(blocked_at.call(cx, cz))
							if not bad and sample_corners:
								bad = bool(blocked_at.call(cx - off, cz - off)) or bool(blocked_at.call(cx + off, cz - off)) \
									or bool(blocked_at.call(cx - off, cz + off)) or bool(blocked_at.call(cx + off, cz + off))
							if bad:
								_blocked[k] = 1
								_grid.set_point_solid(Vector2i(x, z), true)
						_i = end2
						if _i < n2 and _late(deadline_us):
							return false
					_phase = 3
					if _late(deadline_us):
						return false
				3:
					# The cells the ends enter the grid through (walker-checked rings round each end, resumable).
					if _end_a == null:
						_end_a = EndCell.new(_blocked, nx, nz, lo, cell, a, walk_check, true)
						_end_b = EndCell.new(_blocked, nx, nz, lo, cell, b, walk_check, false)
					if not _end_a.step(deadline_us) or not _end_b.step(deadline_us):
						return false
					_ca = _end_a.result
					_cb = _end_b.result
					_end_a = null
					_end_b = null
					if _ca.x < 0 or _cb.x < 0:
						result = LocalRoutePlanner._failed("endpoint enclosed", 0, nx * nz)
						return true
					_phase = 4
					if _late(deadline_us):
						return false
				4:
					var astar_started := Time.get_ticks_usec()
					var path := _grid.get_id_path(_ca, _cb)
					LocalRoutePlanner.native_astar_max_ms = maxf(LocalRoutePlanner.native_astar_max_ms, (Time.get_ticks_usec() - astar_started) / 1000.0)
					if path.is_empty():
						result = LocalRoutePlanner._failed("no walkable local passage" if _repairs > 0 else "no local passage", 0, nx * nz)
						return true
					# String-pull the grid path. The conservative line test keeps adjacent blocked cells
					# out of the shortcut, important for vehicles and infantry beside thin walls.
					var kept: Array[Vector2i] = []
					if string_pull:
						kept.append(path[0])
						var i := 0
						while i < path.size() - 1:
							var j := path.size() - 1
							while j > i + 1 and not LocalRoutePlanner._grid_clear(_blocked, nx, nz, path[i], path[j]):
								j -= 1
							kept.append(path[j])
							i = j
					else:
						for c in path:
							kept.append(c)
					_pts = PackedVector3Array([a])
					for c in kept:
						var p := Vector3(lo.x + (c.x + 0.5) * cell, 0.0, lo.y + (c.y + 0.5) * cell)
						p.y = float(height_at.call(p.x, p.z))
						_pts.append(p)
					_pts.append(b)
					if not walk_check.is_valid():
						_done()
						return true
					_phase = 5
					if _late(deadline_us):
						return false
				5:
					# The walker's own test along the route, a few dozen samples between deadline checks.
					if _walk == null:
						_walk = Walk.new(_pts, walk_check, walk_step)
					if not _walk.step(deadline_us):
						return false
					var bad := _walk.bad
					_walk = null
					if not bad.is_finite():
						_done()
						return true
					_repairs += 1
					if _repairs > LocalRoutePlanner.MAX_REPAIRS:
						result = LocalRoutePlanner._failed("route crosses steep ground", 0, nx * nz)
						return true
					var bc := Vector2i(clampi(int((bad.x - lo.x) / cell), 0, nx - 1), clampi(int((bad.z - lo.y) / cell), 0, nz - 1))
					# Close the steep ground there (LocalRoutePlanner._close_steep, one neighbour cell per deadline check).
					LocalRoutePlanner._mark(_grid, _blocked, nx, bc)
					_cq = [bc]
					_cseen = {bc: true}
					_cclosed = 0
					_phase = 6
				6:
					# The breadth-first walk of _close_steep: a node's eight neighbours, each tested with _cell_steep's 64 probes, a few
					# probes between deadline checks; a test cut by the deadline goes on from its next probe.
					while _cactive or (not _cq.is_empty() and _cclosed < LocalRoutePlanner.MAX_CLOSE_CELLS):
						if not _cactive:
							_cnode = _cq.pop_front()
							_cclosed += 1
							_cactive = true
							_cn = 0
						while _cn < 9:
							var nb: Vector2i = _cnode + Vector2i(_cn % 3 - 1, _cn / 3 - 1)
							if _cprobe == 0:
								if nb == _cnode or _cseen.has(nb) or nb.x < 0 or nb.y < 0 or nb.x >= nx or nb.y >= nz:
									_cn += 1
									continue
								_cseen[nb] = true
								if _blocked[nb.y * nx + nb.x] == 1:
									_cn += 1
									continue
							var steep := false
							while _cprobe < 64:
								var pi := _cprobe
								_cprobe += 1
								var pr := Vector3(lo.x + (nb.x + (pi / 4 % 4 + 0.5) / 4.0) * cell, 0.0, lo.y + (nb.y + (pi / 16 + 0.5) / 4.0) * cell)
								if bool(walk_check.call(pr, LocalRoutePlanner.STEEP_DIRS[pi % 4], 0.1)):
									steep = true
									break
								if _cprobe % 8 == 0 and _cprobe < 64 and _late(deadline_us):
									return false
							_cprobe = 0
							_cn += 1
							if steep:
								LocalRoutePlanner._mark(_grid, _blocked, nx, nb)
								_cq.append(nb)
							if _late(deadline_us):
								return false
						_cactive = false
					_cq = []
					# The endpoints may now sit in closed ground: the nearest open cell takes over, as at the start.
					_phase = 3
					if _late(deadline_us):
						return false
		return true

	func _done() -> void:
		result = {"ok": true, "pts": _pts, "reason": "", "cells": _nx * _nz, "repairs": _repairs}


## NAV-PERF-01B: _end_cell() resumable: the same rings, the same order, the same answer (`result`); `step(deadline_us)` returns true
## when it is final.
class EndCell:
	var blocked: PackedByteArray
	var nx: int
	var nz: int
	var lo: Vector2
	var cell: float
	var p: Vector3
	var walk_check: Callable
	var outward: bool
	var result := Vector2i(-1, -1)
	var _r := 0
	var _k := 0
	var _best := Vector2i(-1, -1)
	var _best_d := INF
	var _done := false

	func _init(p_blocked: PackedByteArray, p_nx: int, p_nz: int, p_lo: Vector2, p_cell: float, p_p: Vector3, p_walk_check: Callable,
			p_outward: bool) -> void:
		blocked = p_blocked
		nx = p_nx
		nz = p_nz
		lo = p_lo
		cell = p_cell
		p = p_p
		walk_check = p_walk_check
		outward = p_outward

	func step(deadline_us: int) -> bool:
		if _done:
			return true
		var c0 := Vector2i(clampi(int((p.x - lo.x) / cell), 0, nx - 1), clampi(int((p.z - lo.y) / cell), 0, nz - 1))
		var checks := 0
		while _r < 6:
			var side := 2 * _r + 1
			while _k < side * side:
				var dz := _k / side - _r
				var dx := _k % side - _r
				_k += 1
				if maxi(absi(dx), absi(dz)) != _r:
					continue
				var q := c0 + Vector2i(dx, dz)
				if q.x < 0 or q.y < 0 or q.x >= nx or q.y >= nz or blocked[q.y * nx + q.x] != 0:
					continue
				var centre := Vector3(lo.x + (q.x + 0.5) * cell, 0.0, lo.y + (q.y + 0.5) * cell)
				var d := Vector2(centre.x - p.x, centre.z - p.z).length()
				if d >= _best_d:
					continue
				if walk_check.is_valid():
					var leg := PackedVector3Array([p, centre] if outward else [centre, p])
					checks += 1
					var unwalkable := LocalRoutePlanner.first_unwalkable(leg, walk_check, 1.0).is_finite()
					if deadline_us > 0 and Time.get_ticks_usec() >= deadline_us:
						if not unwalkable:
							_best = q
							_best_d = d
						return false
					if unwalkable:
						continue
				_best = q
				_best_d = d
			if _best.x >= 0:
				result = _best
				_done = true
				return true
			_r += 1
			_k = 0
		_done = true
		return true


## NAV-PERF-01B: first_unwalkable() resumable: `step(deadline_us)` walks the route until the deadline (0: to the end) and returns true
## when `bad` is final (the first place the walker's test refuses, or INF).
class Walk:
	var pts: PackedVector3Array
	var walk_check: Callable
	var walk_step: float
	var bad := Vector3.INF
	var _i := 0
	var _k := 0

	func _init(p_pts: PackedVector3Array, p_walk_check: Callable, p_step: float) -> void:
		pts = p_pts
		walk_check = p_walk_check
		walk_step = p_step

	func step(deadline_us: int) -> bool:
		var n := 0
		while _i < pts.size() - 1:
			var pa := pts[_i]
			var dv := Vector3(pts[_i + 1].x - pa.x, 0.0, pts[_i + 1].z - pa.z)
			var seg_len := dv.length()
			if seg_len < 0.01:
				_i += 1
				_k = 0
				continue
			dv /= seg_len
			var ns := maxi(1, ceili(seg_len / walk_step))
			while _k < ns:
				var p := pa + dv * minf(_k * walk_step, seg_len)
				_k += 1
				if bool(walk_check.call(p, dv, 0.1)):
					bad = p
					return true
				n += 1
				if n % 4 == 0 and deadline_us > 0 and Time.get_ticks_usec() >= deadline_us:
					return false
			_i += 1
			_k = 0
		return true


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


const STEEP_DIRS: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]


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
