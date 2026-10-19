## Shows, collides, validates and picks the structures of a ConstructionState.
##
## Records are the structures; this node derives everything else from them:
##   - instance transforms, fitted to the terrain once per structure (cached on the record);
##   - a spatial index of 128 m cells (the WORLD-TECH-02 vegetation cell size);
##   - rendering: one MultiMeshInstance3D per (cell, type) for cells within render_radius
##     of the camera, so a 300-module perimeter costs a handful of draw calls and cells
##     kilometres away cost nothing but their records;
##   - collision: one StaticBody3D per cell within collision_radius of the observer
##     (the possessed soldier or the tactical focus, like DetailManager);
##   - placement checks (terrain slope and clearance, water / outside map, overlap with
##     other structures, tree trunks and units), ray picking and navmesh obstacles.
## Not a streaming framework: it only toggles nodes per cell.
class_name StructureManager
extends Node3D

## Emitted after structures were added or removed inside this XZ rectangle (navigation).
signal area_changed(rect: Rect2)

const CELL := 128.0
## Largest distance (m) from an instance origin to the edge of its footprint.
const MAX_REACH := 10.0

@export var terrain: Terrain3D
@export var vegetation: VegetationStreamer
@export var sim: WorldSim
## Map half size; nothing is built closer than 5 m to the edge.
@export var map_half_size := 0.0
## Terrain below this height counts as water (the current maps have no water bodies;
## lakes or a sea level go here).
@export var water_level := -INF
@export var render_radius := 1800.0
@export var collision_radius := 260.0
@export var update_interval := 0.2
## Extra clearance around tree trunks for placement.
@export var tree_margin := 0.35
## Navmesh obstacles are this much larger on every side than the collision boxes: the
## 0.75 m navmesh raster otherwise lets paths clip wall corners by a few centimetres.
@export var nav_margin := 0.3

var state: ConstructionState
## Returns the point physics should exist around (set by the game; default: camera).
var observer_fn: Callable

## Vector2i cell -> Array[Vector2i(id, instance index)]
var _index := {}
## Vector2i cell -> {type_id: MultiMeshInstance3D}
var _visual := {}
## Vector2i cell -> StaticBody3D
var _bodies := {}
var _dirty_cells := {}
var _timer := 0.0
var _tree_cache := {}
var _tree_radii := {}


func bind_state(p_state: ConstructionState) -> void:
	if state:
		state.structure_added.disconnect(_on_added)
		state.structure_removed.disconnect(_on_removed)
		state.structure_changed.disconnect(_on_changed)
		state.cleared.disconnect(_on_cleared)
	state = p_state
	state.structure_added.connect(_on_added)
	state.structure_removed.connect(_on_removed)
	state.structure_changed.connect(_on_changed)
	state.cleared.connect(_on_cleared)
	_on_cleared()
	for s in state.all():
		_on_added(s)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 and _dirty_cells.is_empty():
		return
	_timer = update_interval
	_refresh_cells()


## Rebuilds visuals and collision for the current camera / observer immediately.
func refresh_now() -> void:
	_refresh_cells()


func stats() -> Dictionary:
	var mmis := 0
	var inst := 0
	for c in _visual:
		for t in _visual[c]:
			mmis += 1
			inst += _visual[c][t].multimesh.instance_count
	var shapes := 0
	for c in _bodies:
		shapes += _bodies[c].get_child_count()
	var modules := 0
	for s: StructureState in state.structures.values():
		modules += s.built_count()
	return {"structures": state.count(), "instances": modules, "indexed_cells": _index.size(),
		"visible_cells": _visual.size(), "multimeshes": mmis, "drawn_instances": inst,
		"collision_cells": _bodies.size(), "collision_shapes": shapes}


# --- Placement checks -------------------------------------------------------------

## Fits a building to the terrain and validates it.
## Returns {ok: bool, reason: String, xform: Transform3D}.
func check_building(def: StructureDef, pos: Vector3, yaw: float, ignore_id := -1) -> Dictionary:
	var b := def.bounds()
	var basis := Basis(Vector3.UP, yaw)
	var c := Vector3(b.get_center().x, 0.0, b.get_center().z)
	var steps_x := maxi(2, ceili(b.size.x / 2.0))
	var steps_z := maxi(2, ceili(b.size.z / 2.0))
	var hmin := INF
	var hmax := -INF
	var sxh := 0.0
	var szh := 0.0
	var sxx := 0.0
	var szz := 0.0
	var reason := ""
	for ix in steps_x + 1:
		for iz in steps_z + 1:
			var lx := (float(ix) / steps_x - 0.5) * b.size.x
			var lz := (float(iz) / steps_z - 0.5) * b.size.z
			var w := pos + basis * (c + Vector3(lx, 0, lz))
			var h := _height(w.x, w.z)
			if is_nan(h):
				reason = "outside the terrain"
				break
			if h < water_level:
				reason = "water"
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			sxh += lx * h
			szh += lz * h
			sxx += lx * lx
			szz += lz * lz
		if reason == "outside the terrain":
			break
	var xform := Transform3D(basis, Vector3(pos.x, (hmax if hmax > -INF else pos.y) - def.sink, pos.z))
	if reason == "" and not _inside_map(xform.origin, b.size.length() * 0.5):
		reason = "outside the map"
	if reason == "":
		var gx := sxh / maxf(sxx, 0.001)
		var gz := szh / maxf(szz, 0.001)
		var slope := rad_to_deg(atan(sqrt(gx * gx + gz * gz)))
		if slope > def.max_slope_deg:
			reason = "too steep (%.0f° > %.0f°)" % [slope, def.max_slope_deg]
		elif hmax - hmin > def.max_ground_gap:
			reason = "uneven ground (%.1f m)" % (hmax - hmin)
	if reason == "":
		reason = _blocked(def, _obb(def, xform), ignore_id, -1)
	return {"ok": reason == "", "reason": reason, "xform": xform}


## Fits every module of a line and validates each one.
## Returns {modules: [{xform, ok, reason}], ok_count, length_m}.
func check_line(def: StructureDef, points: PackedVector3Array, ignore_id := -1) -> Dictionary:
	var mods := ModularLine.modules(def, points)
	var out := []
	var ok_count := 0
	for i in mods.size():
		var m: Dictionary = mods[i]
		var r := fit_module(def, m.center, m.dir, i)
		if r.ok:
			r.reason = _blocked(def, _obb(def, r.xform), ignore_id, -1)
			r.ok = r.reason == ""
		out.append(r)
		if r.ok:
			ok_count += 1
	return {"modules": out, "ok_count": ok_count, "length_m": ModularLine.length_of(points)}


## Terrain fit of one module centered at c (XZ) along dir.
## Odd modules are 0.4 % thicker and taller so faces of neighbours that touch or overlap
## (corners, snapped ends) never share a plane and z-fight.
func fit_module(def: StructureDef, c: Vector2, dir: Vector2, index := 0) -> Dictionary:
	var half_l := def.module_length * 0.5
	var half_d := maxf(def.bounds().size.z * 0.5, 0.15)
	var side := Vector2(-dir.y, dir.x)
	var p1 := c - dir * half_l
	var p2 := c + dir * half_l
	var h1 := _height(p1.x, p1.y)
	var h2 := _height(p2.x, p2.y)
	var hc := _height(c.x, c.y)
	var hs1 := _height(c.x + side.x * half_d, c.y + side.y * half_d)
	var hs2 := _height(c.x - side.x * half_d, c.y - side.y * half_d)
	var yaw := ModularLine.yaw_of(dir)
	var basis := Basis(Vector3.UP, yaw)
	var hs := [h1, h2, hc, hs1, hs2]
	for h in hs:
		if is_nan(h):
			return {"ok": false, "reason": "outside the terrain", "xform": Transform3D(basis, Vector3(c.x, 0, c.y))}
	var hmin: float = hs.min()
	var hmax: float = hs.max()
	var slope_along := (h2 - h1) / def.module_length
	var y := 0.0
	var gap := 0.0
	match def.fit:
		StructureDef.Fit.STEP, StructureDef.Fit.LEVEL:
			y = (hmin + hmax) * 0.5
			gap = hmax - hmin
		StructureDef.Fit.PITCH:
			y = (h1 + h2) * 0.5
			basis = basis * Basis(Vector3(0, 0, 1), atan(slope_along))
			gap = maxf(absf(hc - y), absf(hs1 - hs2))
		StructureDef.Fit.SHEAR:
			y = (h1 + h2) * 0.5
			basis.x += Vector3.UP * slope_along
			gap = maxf(absf(hc - y), absf(hs1 - hs2))
	if index % 2 == 1:
		basis = basis * Basis.from_scale(Vector3(1.0, 1.004, 1.004))
	var xform := Transform3D(basis, Vector3(c.x, y - def.sink, c.y))
	var reason := ""
	var slope := rad_to_deg(atan(absf(slope_along)))
	if hmin < water_level:
		reason = "water"
	elif not _inside_map(xform.origin, half_l + 1.0):
		reason = "outside the map"
	elif slope > def.max_slope_deg:
		reason = "too steep (%.0f°)" % slope
	elif gap > def.max_ground_gap:
		reason = "uneven ground (%.1f m)" % gap
	return {"ok": reason == "", "reason": reason, "xform": xform}


## Nearest connection point for a line of `group` within radius of p (XZ):
## {point: Vector3, dir: Vector2 (outward line direction or ZERO), id, index, centered: bool}
## or an empty dictionary. Line ends first, then (HESCO) any module center, then gate posts.
func snap_point(group: StringName, p: Vector3, radius: float, exclude_id := -1) -> Dictionary:
	if group == &"":
		return {}
	var best := {}
	var best_d := radius
	var best_rank := 9
	for cell in _cells_around(Vector2(p.x, p.z), radius + MAX_REACH):
		for e: Vector2i in _index.get(cell, []):
			var s: StructureState = state.get_structure(e.x)
			if s == null or s.id == exclude_id:
				continue
			var def := StructureCatalog.get_def(s.type_id)
			if def == null or def.connect_group != group:
				continue
			var cands := []
			if s.is_line():
				var centered := def.layout == StructureDef.Layout.CENTERED
				if e.y == 0 or e.y == s.instances.size() - 1:
					var is_first := e.y == 0
					var end_p := s.points[0] if is_first else s.points[-1]
					var other := s.points[1] if is_first else s.points[-2]
					cands.append([0, end_p, Vector2(end_p.x - other.x, end_p.z - other.z).normalized(), centered])
				if centered and not s.is_removed(e.y):
					var o := s.instances[e.y].origin
					cands.append([1, Vector3(o.x, o.y + def.sink, o.z), Vector2.ZERO, true])
			else:
				var xf: Transform3D = s.instances[0]
				for sp in def.snap_points:
					var w := xf * sp
					var out_dir := Vector2(w.x - xf.origin.x, w.z - xf.origin.z).normalized()
					cands.append([2, w, out_dir, false])
			for cand in cands:
				var q: Vector3 = cand[1]
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < best_d or (is_equal_approx(d, best_d) and cand[0] < best_rank):
					best_d = d
					best_rank = cand[0]
					best = {"point": q, "dir": cand[2], "id": s.id, "index": e.y, "centered": cand[3]}
	return best


# --- Picking ----------------------------------------------------------------------

## Structure under a ray: {id, index (module, -1 for buildings), distance} or {}.
func pick(from: Vector3, dir: Vector3, max_dist := 3000.0) -> Dictionary:
	var to := from + dir * max_dist
	if terrain:
		var g: Vector3 = terrain.get_intersection(from, dir, false)
		if g.is_finite() and not is_nan(g.x) and g.distance_to(from) < max_dist:
			to = g + dir * 2.0
	var cells := {}
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var n := maxi(1, ceili(a.distance_to(b) / (CELL * 0.5)))
	for i in n + 1:
		var q := a.lerp(b, float(i) / n)
		for c in _cells_around(q, MAX_REACH + 2.0):
			cells[c] = true
	var best := {}
	var best_d := INF
	for c in cells:
		for e: Vector2i in _index.get(c, []):
			var s: StructureState = state.get_structure(e.x)
			if s == null or (s.is_line() and s.is_removed(e.y)):
				continue
			var def := StructureCatalog.get_def(s.type_id)
			var inv := s.instances[e.y].affine_inverse()
			var lf := inv * from
			var lt := inv * to
			var box := def.bounds().grow(0.1)
			var hit: Variant = box.intersects_segment(lf, lt)
			if hit == null:
				continue
			var d := from.distance_to(s.instances[e.y] * (hit as Vector3))
			if d < best_d:
				best_d = d
				best = {"id": s.id, "index": e.y if s.is_line() else -1, "distance": d}
	return best


# --- Navigation -------------------------------------------------------------------

## Obstacles for AreaNavigation.bake_area inside a square: [{position, yaw, size}].
## Only ground-touching collision boxes of blocking types (walls, not roofs; gates and
## stairs stay walkable).
func nav_obstacles(center: Vector3, half: float) -> Array:
	var out := []
	var seen := {}
	for c in _cells_around(Vector2(center.x, center.z), half + MAX_REACH):
		for e: Vector2i in _index.get(c, []):
			if seen.has(e):
				continue
			seen[e] = true
			var s: StructureState = state.get_structure(e.x)
			if s == null or (s.is_line() and s.is_removed(e.y)):
				continue
			var def := StructureCatalog.get_def(s.type_id)
			if not def.blocks_navigation:
				continue
			var xf := s.instances[e.y]
			if absf(xf.origin.x - center.x) > half + MAX_REACH or absf(xf.origin.z - center.z) > half + MAX_REACH:
				continue
			var yaw := atan2(-xf.basis.x.z, xf.basis.x.x)
			for box in def.get_collision_boxes():
				if box.position.y > 1.0:
					continue
				var bc := box.get_center()
				var w := xf * Vector3(bc.x, 0.0, bc.z)
				var size := Vector2(box.size.x, box.size.z)
				if def.linear:
					size.x = def.module_length
				size += Vector2(nav_margin, nav_margin) * 2.0
				out.append({"position": Vector3(w.x, xf.origin.y, w.z), "yaw": yaw, "size": size})
	return out


# --- Records -> instances ---------------------------------------------------------

func _resolve(s: StructureState) -> void:
	var def := StructureCatalog.get_def(s.type_id)
	s.instances.clear()
	if def == null:
		push_warning("StructureManager: unknown structure type %s" % s.type_id)
		return
	if s.is_line():
		var mods := ModularLine.modules(def, s.points)
		for i in mods.size():
			s.instances.append(fit_module(def, mods[i].center, mods[i].dir, i).xform)
	else:
		var r := check_building(def, s.position, s.yaw, s.id)
		s.instances.append(r.xform)


func _on_added(s: StructureState) -> void:
	_resolve(s)
	for i in s.instances.size():
		var c := _cell_of(s.instances[i].origin)
		if not _index.has(c):
			_index[c] = []
		_index[c].append(Vector2i(s.id, i))
		_dirty_cells[c] = true
	area_changed.emit(_rect_of(s))


func _on_removed(s: StructureState) -> void:
	for i in s.instances.size():
		var c := _cell_of(s.instances[i].origin)
		var list: Array = _index.get(c, [])
		list.erase(Vector2i(s.id, i))
		if list.is_empty():
			_index.erase(c)
		_dirty_cells[c] = true
	area_changed.emit(_rect_of(s))


func _on_changed(s: StructureState) -> void:
	for i in s.instances.size():
		_dirty_cells[_cell_of(s.instances[i].origin)] = true
	area_changed.emit(_rect_of(s))


func _on_cleared() -> void:
	for c in _visual.keys():
		_free_visual(c)
	for c in _bodies.keys():
		_bodies[c].queue_free()
	_bodies.clear()
	_index.clear()
	_dirty_cells.clear()


func _rect_of(s: StructureState) -> Rect2:
	var r := Rect2()
	var first := true
	for xf in s.instances:
		var p := Vector2(xf.origin.x, xf.origin.z)
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	return r.grow(MAX_REACH)


# --- Cells: visuals and collision ---------------------------------------------------

func _refresh_cells() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_p := cam.global_position if cam else Vector3.ZERO
	var obs: Vector3 = observer_fn.call() if observer_fn.is_valid() else cam_p
	var want_vis := {}
	var want_col := {}
	var half_diag := CELL * 0.7072
	for c: Vector2i in _index:
		var center := Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)
		if center.distance_to(Vector2(cam_p.x, cam_p.z)) < render_radius + half_diag:
			want_vis[c] = true
		if center.distance_to(Vector2(obs.x, obs.z)) < collision_radius + half_diag:
			want_col[c] = true
	for c in _visual.keys():
		if not want_vis.has(c) or _dirty_cells.has(c):
			_free_visual(c)
	for c in _bodies.keys():
		if not want_col.has(c) or _dirty_cells.has(c):
			_bodies[c].queue_free()
			_bodies.erase(c)
	for c in want_vis:
		if not _visual.has(c):
			_build_visual(c)
	for c in want_col:
		if not _bodies.has(c):
			_build_body(c)
	_dirty_cells.clear()


func _instances_by_type(c: Vector2i) -> Dictionary:
	var by_type := {}
	for e: Vector2i in _index.get(c, []):
		var s: StructureState = state.get_structure(e.x)
		if s == null or (s.is_line() and s.is_removed(e.y)) or e.y >= s.instances.size():
			continue
		if not by_type.has(s.type_id):
			by_type[s.type_id] = []
		by_type[s.type_id].append(s.instances[e.y])
	return by_type


func _build_visual(c: Vector2i) -> void:
	var by_type := _instances_by_type(c)
	var nodes := {}
	for t in by_type:
		var def := StructureCatalog.get_def(t)
		var xforms: Array = by_type[t]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = StructureCatalog.mesh_of(def)
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "S_%d_%d_%s" % [c.x, c.y, t]
		mmi.multimesh = mm
		mmi.visibility_range_end = def.visible_range
		mmi.visibility_range_end_margin = 80.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		nodes[t] = mmi
	_visual[c] = nodes


func _free_visual(c: Vector2i) -> void:
	for t in _visual.get(c, {}):
		_visual[c][t].queue_free()
	_visual.erase(c)


func _build_body(c: Vector2i) -> void:
	var body := StaticBody3D.new()
	body.name = "SC_%d_%d" % [c.x, c.y]
	add_child(body)
	var by_type := _instances_by_type(c)
	for t in by_type:
		var def := StructureCatalog.get_def(t)
		for xf: Transform3D in by_type[t]:
			# Sheared fence panels: physics wants an orthonormal basis.
			var rigid := Transform3D(xf.basis.orthonormalized(), xf.origin)
			for box in def.get_collision_boxes():
				var shape := BoxShape3D.new()
				var size := box.size
				if def.linear and def.fit == StructureDef.Fit.SHEAR:
					size.x = xf.basis.x.length() * box.size.x
				shape.size = size
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.transform = rigid * Transform3D(Basis.IDENTITY, box.get_center())
				body.add_child(cs)
			for ramp in def.ramps:
				var cs := CollisionShape3D.new()
				cs.shape = _wedge(ramp)
				cs.transform = rigid
				body.add_child(cs)
	_bodies[c] = body


## Walkable wedge: bottom face of the box, top edge at min Z.
static func _wedge(b: AABB) -> ConvexPolygonShape3D:
	var x0 := b.position.x
	var x1 := b.end.x
	var y0 := b.position.y
	var y1 := b.end.y
	var z0 := b.position.z
	var z1 := b.end.z
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0)])
	return shape


# --- Geometry helpers -------------------------------------------------------------

func _height(x: float, z: float) -> float:
	if terrain == null:
		return 0.0
	return terrain.data.get_height(Vector3(x, 0.0, z))


func _inside_map(p: Vector3, reach: float) -> bool:
	if map_half_size <= 0.0:
		return true
	var lim := map_half_size - 5.0 - reach
	return absf(p.x) <= lim and absf(p.z) <= lim


static func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func _cells_around(p: Vector2, r: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c0 := Vector2i(floori((p.x - r) / CELL), floori((p.y - r) / CELL))
	var c1 := Vector2i(floori((p.x + r) / CELL), floori((p.y + r) / CELL))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			out.append(Vector2i(x, z))
	return out


## Oriented footprint rectangle of a type at a transform: [center, axis_x, axis_z, half].
static func _obb(def: StructureDef, xf: Transform3D, shrink := 0.0) -> Array:
	var b := def.bounds()
	var ax := Vector2(xf.basis.x.x, xf.basis.x.z)
	var az := Vector2(xf.basis.z.x, xf.basis.z.z)
	var lx := ax.length()
	var lz := az.length()
	var cl := b.get_center()
	var cw := xf * Vector3(cl.x, 0.0, cl.z)
	return [Vector2(cw.x, cw.z), ax / lx, az / lz,
		Vector2(maxf(b.size.x * 0.5 * lx - shrink, 0.05), maxf(b.size.z * 0.5 * lz - shrink, 0.05))]


static func _obb_overlap(a: Array, b: Array) -> bool:
	var d: Vector2 = b[0] - a[0]
	for axis: Vector2 in [a[1], a[2], b[1], b[2]]:
		var ra: float = a[3].x * absf(a[1].dot(axis)) + a[3].y * absf(a[2].dot(axis))
		var rb: float = b[3].x * absf(b[1].dot(axis)) + b[3].y * absf(b[2].dot(axis))
		if absf(d.dot(axis)) > ra + rb:
			return false
	return true


static func _obb_circle(a: Array, p: Vector2, r: float) -> bool:
	var d := p - (a[0] as Vector2)
	var lx := clampf(d.dot(a[1]), -a[3].x, a[3].x)
	var lz := clampf(d.dot(a[2]), -a[3].y, a[3].y)
	var closest: Vector2 = a[0] + (a[1] as Vector2) * lx + (a[2] as Vector2) * lz
	return closest.distance_to(p) < r


## Why a footprint cannot be built here ("" = free): other structures, tree trunks, units.
func _blocked(def: StructureDef, obb: Array, ignore_id: int, _ignore_index: int) -> String:
	var c: Vector2 = obb[0]
	var reach: float = (obb[3] as Vector2).length()
	# Structures. Same connection group (HESCO to HESCO, fence to gate) may touch.
	for cell in _cells_around(c, reach + MAX_REACH):
		for e: Vector2i in _index.get(cell, []):
			if e.x == ignore_id:
				continue
			var s: StructureState = state.get_structure(e.x)
			if s == null or (s.is_line() and s.is_removed(e.y)):
				continue
			var odef := StructureCatalog.get_def(s.type_id)
			var same := def.connect_group != &"" and odef.connect_group == def.connect_group
			var other := _obb(odef, s.instances[e.y], 0.2 if same else 0.0)
			var mine := obb
			if same:
				mine = [obb[0], obb[1], obb[2], Vector2(maxf(obb[3].x - 0.2, 0.05), maxf(obb[3].y - 0.2, 0.05))]
			if _obb_overlap(mine, other):
				return "blocked by %s" % odef.display_name.to_lower()
	# Tree trunks.
	if vegetation and vegetation.library:
		if _tree_radii.is_empty():
			for d in vegetation.library.meshes:
				if d.collider.x >= 0.0:
					_tree_radii[d.id] = maxf(d.collider.y, 0.25)
		var cs: float = vegetation.cell_size_m
		var r := reach + 3.0
		var c0 := VegetationChunk.cell_of(Vector3(c.x - r, 0, c.y - r), cs)
		var c1 := VegetationChunk.cell_of(Vector3(c.x + r, 0, c.y + r), cs)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				for t in _trees_in(Vector2i(cx, cz)):
					var tp := Vector2(t.x, t.y)
					if tp.distance_to(c) > r + t.z:
						continue
					if _obb_circle(obb, tp, t.z + tree_margin):
						return "blocked by a tree"
	# Units standing there (records, so abstract units count too).
	if sim:
		for u: UnitState in sim.state.units.values():
			var up := Vector2(u.position.x, u.position.z)
			if up.distance_to(c) > reach + 4.0:
				continue
			if u.kind == UnitState.Kind.VEHICLE:
				var vb := Basis(Vector3.UP, u.yaw)
				var vobb := [up, Vector2(vb.x.x, vb.x.z), Vector2(vb.z.x, vb.z.z), VehicleBody.FOOTPRINT * 0.5]
				if _obb_overlap(obb, vobb):
					return "vehicle in the way"
			elif _obb_circle(obb, up, 0.4):
				return "soldier in the way"
	return ""


## Tree trunks of one vegetation cell as Vector3(x, z, radius), cached (static data).
func _trees_in(cell: Vector2i) -> Array:
	if _tree_cache.has(cell):
		return _tree_cache[cell]
	var out := []
	for inst in vegetation.get_cell_instances(cell, _tree_radii.keys()):
		var xf: Transform3D = inst[1]
		out.append(Vector3(xf.origin.x, xf.origin.z, _tree_radii[inst[0]] * xf.basis.get_scale().x))
	_tree_cache[cell] = out
	return out
