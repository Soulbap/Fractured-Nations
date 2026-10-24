## Authoritative shot and line-of-sight resolution from world data (COMBAT-01a).
##
## Physics only exists near the camera (terrain ~200 m, tree colliders 40 m, structures
## 260 m, soldier bodies 120-150 m; COMBAT-TECH-01), so a shot is resolved against data
## that exists everywhere, giving the same answer wherever the camera is:
##   - structures: the collision boxes of every placed module / building, from the
##     StructureManager records (the same boxes its physics colliders use);
##   - trees and rocks: the vegetation chunk instances that have a collider in the
##     library (same capsule / sphere sizes as InstanceColliderStreamer), minus cleared
##     vegetation, cached per 16 m bucket and walked cell by cell along the shot;
##   - terrain: a march over Terrain3DData heights (includes groundwork edits), refined
##     by bisection;
##   - soldiers: analytic head sphere + torso capsule around each living UnitState
##     (works with or without a physics body).
## Nothing here is a node or a physics query; the result is a plain dictionary.
class_name LineOfFire
extends RefCounted

enum Zone { NONE, BODY, HEAD }

## Soldier hit model (metres, relative to UnitState.position = feet).
const HEAD_Y := 1.62
const HEAD_R := 0.14
const TORSO_R := 0.30
const TORSO_Y0 := 0.30   # lower hemisphere centre
const TORSO_Y1 := 1.20   # upper hemisphere centre (top of torso 1.50)
## Tree bucket size (m).
const BUCKET := 16.0
## Largest trunk / rock radius considered when choosing buckets (m).
const REACH := 4.0
## Terrain march steps (m): fine near the muzzle, coarser beyond.
const STEP_NEAR := 1.0
const STEP_FAR := 2.0
const NEAR_M := 40.0
## Extra length on each side of a line module's box (closes the seams between cells).
const SEAM_M := 0.12
## Steepest terrain gradient assumed by the adaptive march (rise per metre).
const MAX_SLOPE := 1.5

var terrain: Terrain3D
var vegetation: VegetationStreamer
var structures: StructureManager
var state: WorldState

## mesh id -> Vector3(shape 0 capsule / 1 sphere, radius, height) at scale 1
var _solid := {}
## Vector2i bucket -> PackedFloat32Array of [x, z, y, radius, height, shape] per solid
var _buckets := {}
## 128 m vegetation cells already distributed into buckets
var _loaded_cells := {}
## Last trace cost breakdown (usec) for measurements.
var last_cost := {}
## COMBAT-01b sight through foliage (see sight()): a tree whose trunk stands within
## foliage_m of the line counts as one layer of leaves / undergrowth; trees closer than
## foliage_skip_m to either end do not count (a soldier at a forest edge looks past the
## tree next to him); foliage_block layers hide what is behind them.
## COMBAT-02: soldiers near a shot come from this index (CombatBrain's grid) instead of
## a scan over every unit; null = scan (tests, tools).
var unit_index: CombatBrain
## Vegetation cells distributed into trunk buckets so far, and what it cost (a cell is
## filled the first time a line crosses it; CombatBrain warms cells ahead of fights).
var cell_loads := 0
var cell_load_usec := 0
var cell_load_usec_max := 0
var foliage_m := 2.5
var foliage_skip_m := 3.0
var foliage_block := 3


func setup(p_state: WorldState, p_terrain: Terrain3D, p_vegetation: VegetationStreamer, p_structures: StructureManager) -> void:
	state = p_state
	terrain = p_terrain
	vegetation = p_vegetation
	structures = p_structures
	_solid.clear()
	if vegetation and vegetation.library:
		for d in vegetation.library.meshes:
			if d.collider.x >= 0.0:
				_solid[d.id] = d.collider
		if not vegetation.clearings_changed.is_connected(_on_clearings_changed):
			vegetation.clearings_changed.connect(_on_clearings_changed)


## Resolves a straight shot. exclude_id: the shooter (never hit). Returns
## {distance, point, blocker ("" / "terrain" / "tree" / "structure" / "unit" / "range"),
##  hit_unit, zone, structure_id}.
func trace(from: Vector3, to: Vector3, exclude_id := -1, hit_units := true) -> Dictionary:
	var length := from.distance_to(to)
	var res := {"distance": length, "point": to, "blocker": "range", "hit_unit": -1, "zone": Zone.NONE, "structure_id": -1}
	if length < 0.001:
		return res
	var t0 := Time.get_ticks_usec()
	var s := _structures_hit(from, to, length)
	var t1 := Time.get_ticks_usec()
	if s.d < res.distance:
		res.distance = s.d
		res.blocker = "structure"
		res.structure_id = s.id
	var te := _terrain_hit(from, to, res.distance)
	var t2 := Time.get_ticks_usec()
	if te < res.distance:
		res.distance = te
		res.blocker = "terrain"
	var tr := _trees_hit(from, to, res.distance)
	var t3 := Time.get_ticks_usec()
	if tr < res.distance:
		res.distance = tr
		res.blocker = "tree"
	if hit_units:
		var u := _units_hit(from, to, res.distance, exclude_id)
		if u.d < res.distance:
			res.distance = u.d
			res.blocker = "unit"
			res.hit_unit = u.id
			res.zone = u.zone
	var t4 := Time.get_ticks_usec()
	res.point = from + (to - from) * (res.distance / length)
	last_cost = {"structures": t1 - t0, "terrain": t2 - t1, "trees": t3 - t2, "units": t4 - t3, "total": t4 - t0}
	return res


## True if nothing in the world blocks the straight line (soldiers ignored).
func clear_line(from: Vector3, to: Vector3) -> bool:
	return trace(from, to, -1, false).blocker == "range"


## COMBAT-01b line of sight: the same world data as a shot (structures, terrain, trunks
## and rocks; soldiers do not hide each other), plus foliage, which stops eyes but not
## bullets. Returns {visible, blocker ("" / "structure" / "terrain" / "tree" /
## "foliage"), distance, foliage}.
func sight(from: Vector3, to: Vector3) -> Dictionary:
	var r := trace(from, to, -1, false)
	if r.blocker != "range":
		return {"visible": false, "blocker": r.blocker, "distance": r.distance, "foliage": 0}
	var f := foliage_layers(from, to, foliage_block)
	return {"visible": f < foliage_block, "blocker": "foliage" if f >= foliage_block else "", "distance": r.distance, "foliage": f}


## Trees (not rocks) whose trunk stands within foliage_m of the segment, below their top,
## ignoring foliage_skip_m at both ends. Stops counting at stop_at.
func foliage_layers(from: Vector3, to: Vector3, stop_at := 1 << 30) -> int:
	if vegetation == null or _solid.is_empty():
		return 0
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var seg_len := a.distance_to(b)
	if seg_len <= foliage_skip_m * 2.0:
		return 0
	var dir2 := (b - a) / seg_len
	var dy_per_m := (to.y - from.y) / seg_len
	var n := 0
	for bucket: Vector2i in _buckets_along(a, b):
		_ensure_cell(Vector2i(floori(bucket.x * BUCKET / vegetation.cell_size_m), floori(bucket.y * BUCKET / vegetation.cell_size_m)))
		var data: PackedFloat32Array = _buckets.get(bucket, PackedFloat32Array())
		for i in range(0, data.size(), 6):
			if data[i + 5] > 0.5:
				continue
			var rel := Vector2(data[i] - a.x, data[i + 1] - a.y)
			var along := rel.dot(dir2)
			if along < foliage_skip_m or along > seg_len - foliage_skip_m:
				continue
			if absf(rel.x * dir2.y - rel.y * dir2.x) > foliage_m + data[i + 3]:
				continue
			if from.y + dy_per_m * along > data[i + 2] + data[i + 4]:
				continue  # the line passes over the tree
			n += 1
			if n >= stop_at:
				return n
	return n


# --- Structures ---------------------------------------------------------------------

## GAMEPLAY-02C: structures with a part within r of p - [{id, d}] (d: distance from p to the nearest collision box of the
## structure, 0 inside). Walks only the StructureManager cells round p.
func structures_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	if structures == null or structures.state == null:
		return out
	var best := {}
	var reach := r + StructureManager.MAX_REACH
	var c0 := Vector2i(floori((p.x - reach) / StructureManager.CELL), floori((p.z - reach) / StructureManager.CELL))
	var c1 := Vector2i(floori((p.x + reach) / StructureManager.CELL), floori((p.z + reach) / StructureManager.CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for e: Vector2i in structures._index.get(Vector2i(cx, cz), []):
				var st := structures.state.get_structure(e.x)
				if st == null or (st.is_line() and st.is_removed(e.y)) or e.y >= st.instances.size():
					continue
				var xf := st.instances[e.y]
				if Vector2(xf.origin.x - p.x, xf.origin.z - p.z).length() > reach:
					continue
				var def := StructureCatalog.get_def(st.type_id)
				if def == null:
					continue
				var lp := xf.affine_inverse() * p
				for box: AABB in def.get_collision_boxes():
					var q := Vector3(clampf(lp.x, box.position.x, box.end.x), clampf(lp.y, box.position.y, box.end.y), clampf(lp.z, box.position.z, box.end.z))
					var d := lp.distance_to(q)
					if d <= r and d < float(best.get(st.id, INF)):
						best[st.id] = d
	for id in best:
		out.append({"id": id, "d": best[id]})
	return out


func _structures_hit(from: Vector3, to: Vector3, length: float) -> Dictionary:
	var best := {"d": INF, "id": -1}
	if structures == null or structures.state == null:
		return best
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var reach := StructureManager.CELL * 0.7072 + StructureManager.MAX_REACH
	for cell: Vector2i in structures._index:
		var cc := Vector2((cell.x + 0.5) * StructureManager.CELL, (cell.y + 0.5) * StructureManager.CELL)
		if _point_segment_dist2d(cc, a, b) > reach:
			continue
		for e: Vector2i in structures._index[cell]:
			var st := structures.state.get_structure(e.x)
			if st == null or (st.is_line() and st.is_removed(e.y)) or e.y >= st.instances.size():
				continue
			var xf := st.instances[e.y]
			if _point_segment_dist2d(Vector2(xf.origin.x, xf.origin.z), a, b) > StructureManager.MAX_REACH + 1.0:
				continue
			var def := StructureCatalog.get_def(st.type_id)
			if def == null:
				continue
			var inv := xf.affine_inverse()
			var lf := inv * from
			var lt := inv * to
			for b0: AABB in def.get_collision_boxes() + def.ramps:
				var box := b0
				# COMBAT-02: a line places round(length / module_length) cells, so they
				# stand a few centimetres apart (3 cm on a 12 m HESCO line) and shots
				# passed through the seams. Cells of a line are closed along it.
				if def.linear:
					box.position.x -= SEAM_M
					box.size.x += SEAM_M * 2.0
				var d := INF
				if box.has_point(lf):
					d = 0.0
				else:
					var hit: Variant = box.intersects_segment(lf, lt)
					if hit != null:
						d = from.distance_to(xf * (hit as Vector3))
				if d < best.d:
					best.d = d
					best.id = st.id
	return best


# --- Trees and rocks ----------------------------------------------------------------

func _trees_hit(from: Vector3, to: Vector3, limit: float) -> float:
	if vegetation == null or _solid.is_empty():
		return INF
	var best := INF
	var length := from.distance_to(to)
	var end := from + (to - from) * (minf(limit, length) / length)
	var a := Vector2(from.x, from.z)
	var b := Vector2(end.x, end.z)
	var seg := b - a
	var seg_len := seg.length()
	var dir2 := seg / seg_len if seg_len > 0.0001 else Vector2.ZERO
	var dy_per_m := (end.y - from.y) / maxf(seg_len, 0.0001)
	for bucket: Vector2i in _buckets_along(a, b):
		_ensure_cell(Vector2i(floori(bucket.x * BUCKET / vegetation.cell_size_m), floori(bucket.y * BUCKET / vegetation.cell_size_m)))
		var data: PackedFloat32Array = _buckets.get(bucket, PackedFloat32Array())
		for i in range(0, data.size(), 6):
			var r: float = data[i + 3]
			var rel := Vector2(data[i] - a.x, data[i + 1] - a.y)
			var along := rel.dot(dir2)
			if along < -r or along > seg_len + r:
				continue
			var off := absf(rel.x * dir2.y - rel.y * dir2.x)
			if off > r + 0.001:
				continue
			# Entry point into the circle along the 2D line, then the height there.
			var half := sqrt(maxf(r * r - off * off, 0.0))
			var t := maxf(along - half, 0.0)
			var y := from.y + dy_per_m * t
			var base: float = data[i + 2]
			var h: float = data[i + 4]
			var top := base + h
			if data[i + 5] > 0.5:  # sphere (rocks): centre at base + 0.3 r, height test by sphere
				var c := Vector3(data[i], base + r * 0.3, data[i + 1])
				var hs := Geometry3D.segment_intersects_sphere(from, end, c, r)
				if not hs.is_empty():
					best = minf(best, from.distance_to(hs[0]))
				continue
			if y < base - 0.05 or y > top:
				# The line may enter the trunk's height range further along inside the circle.
				var t_exit := minf(along + half, seg_len)
				var y2 := from.y + dy_per_m * t_exit
				if (y < base and y2 < base) or (y > top and y2 > top):
					continue
			var d3 := t * sqrt(1.0 + dy_per_m * dy_per_m)
			best = minf(best, d3)
	return best


## 16 m buckets crossed by the 2D segment (grid walk), plus a one-bucket margin for
## trunks whose centre lies just outside a crossed bucket.
func _buckets_along(a: Vector2, b: Vector2) -> Array:
	var out := {}
	var seg := b - a
	var n := seg.normalized() if seg.length() > 0.001 else Vector2.RIGHT
	var side := Vector2(-n.y, n.x) * REACH
	var steps := maxi(1, ceili(seg.length() / (BUCKET * 0.25)))
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		for q: Vector2 in [p, p + side, p - side]:
			out[Vector2i(floori(q.x / BUCKET), floori(q.y / BUCKET))] = true
	# Trunk centres up to REACH beyond the ends.
	for q: Vector2 in [a - n * REACH, b + n * REACH]:
		out[Vector2i(floori(q.x / BUCKET), floori(q.y / BUCKET))] = true
	return out.keys()


## Vegetation cells (128 m) a line from `from` to `to` reads, including the trunk margin.
func cells_along(from: Vector3, to: Vector3) -> Array:
	if vegetation == null or _solid.is_empty():
		return []
	var out := {}
	var cs: float = vegetation.cell_size_m
	for bucket: Vector2i in _buckets_along(Vector2(from.x, from.z), Vector2(to.x, to.z)):
		out[Vector2i(floori(bucket.x * BUCKET / cs), floori(bucket.y * BUCKET / cs))] = true
	return out.keys()


func cell_ready(cell: Vector2i) -> bool:
	return vegetation == null or _loaded_cells.has(cell)


## Fills one vegetation cell now (CombatBrain spreads these over frames).
func warm(cell: Vector2i) -> void:
	_ensure_cell(cell)


func _ensure_cell(cell: Vector2i) -> void:
	if _loaded_cells.has(cell):
		return
	var t0 := Time.get_ticks_usec()
	_fill_cell(cell)
	var dt := Time.get_ticks_usec() - t0
	cell_loads += 1
	cell_load_usec += dt
	cell_load_usec_max = maxi(cell_load_usec_max, dt)


func _fill_cell(cell: Vector2i) -> void:
	_loaded_cells[cell] = true
	# COMBAT-02: collect per bucket first, then store once. Appending to the packed array
	# held in _buckets copied the whole bucket for every trunk (copy on write), which
	# made the first line through a forest cell cost several milliseconds.
	var fresh := {}
	for inst in vegetation.get_cell_instances(cell, _solid.keys()):
		var xf: Transform3D = inst[1]
		var spec: Vector3 = _solid[inst[0]]
		var sc := xf.basis.get_scale()
		var r := spec.y * sc.x
		var h := maxf(spec.z * sc.y, 2.0 * r) if spec.x < 0.5 else r * 2.0
		var key := Vector2i(floori(xf.origin.x / BUCKET), floori(xf.origin.z / BUCKET))
		if not fresh.has(key):
			fresh[key] = []
		fresh[key].append_array([xf.origin.x, xf.origin.z, xf.origin.y, r, h, spec.x])
	for key: Vector2i in fresh:
		var arr: PackedFloat32Array = _buckets.get(key, PackedFloat32Array())
		arr.append_array(PackedFloat32Array(fresh[key]))
		_buckets[key] = arr


## Construction cleared vegetation: forget the affected cells (and their buckets).
func _on_clearings_changed(cells: Array) -> void:
	var per := int(round(vegetation.cell_size_m / BUCKET))
	for cell: Vector2i in cells:
		if not _loaded_cells.has(cell):
			continue
		_loaded_cells.erase(cell)
		for bx in range(cell.x * per, cell.x * per + per):
			for bz in range(cell.y * per, cell.y * per + per):
				_buckets.erase(Vector2i(bx, bz))


# --- Terrain ------------------------------------------------------------------------

func _terrain_hit(from: Vector3, to: Vector3, limit: float) -> float:
	if terrain == null or terrain.data == null:
		return INF
	var length := from.distance_to(to)
	var end_d := minf(limit, length)
	var dir := (to - from) / length
	var h0: float = terrain.data.get_height(from)
	if not is_nan(h0) and h0 > from.y:
		return 0.0
	var prev := 0.0
	var d := 0.0
	var clearance := from.y - (h0 if not is_nan(h0) else from.y)
	while d < end_d:
		# The line cannot reach the ground sooner than its height above it allows on
		# terrain up to MAX_SLOPE steep: step by that, never less than the base step.
		var base := STEP_NEAR if d < NEAR_M else STEP_FAR
		var safe := clearance / (MAX_SLOPE + maxf(-dir.y, 0.0) / maxf(Vector2(dir.x, dir.z).length(), 0.05)) if clearance > 0.0 else 0.0
		d = minf(d + maxf(base, minf(safe, 40.0)), end_d)
		var p := from + dir * d
		var h: float = terrain.data.get_height(p)
		clearance = p.y - h if not is_nan(h) else 10.0
		if not is_nan(h) and h > p.y:
			var lo := prev
			var hi := d
			for k in 8:
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				var hm: float = terrain.data.get_height(q)
				if not is_nan(hm) and hm > q.y:
					hi = mid
				else:
					lo = mid
			return hi
		prev = d
	return INF


# --- Soldiers -----------------------------------------------------------------------

func _units_hit(from: Vector3, to: Vector3, limit: float, exclude_id: int) -> Dictionary:
	var best := {"d": INF, "id": -1, "zone": Zone.NONE}
	if state == null:
		return best
	var length := from.distance_to(to)
	var end := from + (to - from) * (minf(limit, length) / length)
	var a := Vector2(from.x, from.z)
	var b := Vector2(end.x, end.z)
	var candidates: Array = unit_index.units_near_segment(a, b, 0.6) if unit_index else state.units.values()
	for u: UnitState in candidates:
		if u.id == exclude_id or not u.alive or u.kind != UnitState.Kind.SOLDIER:
			continue
		var p := u.position
		if _point_segment_dist2d(Vector2(p.x, p.z), a, b) > 0.6:
			continue
		var h := unit_hit(from, end, p)
		if h.d < best.d:
			best.d = h.d
			best.id = u.id
			best.zone = h.zone
	return best


## Hit of a segment on one soldier standing at feet position p: {d, zone}.
static func unit_hit(from: Vector3, to: Vector3, p: Vector3) -> Dictionary:
	var best := {"d": INF, "zone": Zone.NONE}
	var hs := Geometry3D.segment_intersects_sphere(from, to, p + Vector3(0, HEAD_Y, 0), HEAD_R)
	if not hs.is_empty():
		best.d = from.distance_to(hs[0])
		best.zone = Zone.HEAD
	var bd := segment_vertical_capsule(from, to, p + Vector3(0, TORSO_Y0, 0), p + Vector3(0, TORSO_Y1, 0), TORSO_R)
	if bd >= 0.0 and bd < best.d:
		best.d = bd
		best.zone = Zone.BODY
	return best


## Distance along the segment to a vertical capsule between centres a (low) and b (high),
## or -1. Geometry3D's cylinder runs along Z, so Y and Z are swapped (distances kept).
static func segment_vertical_capsule(from: Vector3, to: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var best := -1.0
	var m := (a + b) * 0.5
	var f := from - m
	var t := to - m
	var c := Geometry3D.segment_intersects_cylinder(Vector3(f.x, f.z, f.y), Vector3(t.x, t.z, t.y), b.y - a.y, r)
	if not c.is_empty():
		var h: Vector3 = c[0]
		best = from.distance_to(Vector3(h.x, h.z, h.y) + m)
	for cap: Vector3 in [a, b]:
		var s := Geometry3D.segment_intersects_sphere(from, to, cap, r)
		if not s.is_empty():
			var d := from.distance_to(s[0])
			if best < 0.0 or d < best:
				best = d
	return best


static func _point_segment_dist2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
