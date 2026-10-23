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
##     other structures, tree trunks and units), ray picking and navmesh obstacles;
##   - grass clearing: footprints are painted into the in-memory grass exclusion mask
##     (never saved to the world's mask file) so grass does not grow through floors and
##     walls; removed structures restore the original texels;
##   - groundwork (WORLD-INTEGRATION-01): buildings level the terrain under their footprint
##     to a pad that blends into the surroundings, so they can stand on sloped and uneven
##     ground. The pads are derived from the building records (no extra saved data), the
##     terrain files are never written, and removing a building restores the ground.
## Not a streaming framework: it only toggles nodes per cell.
class_name StructureManager
extends Node3D

## Emitted after structures were added or removed inside this XZ rectangle (navigation).
signal area_changed(rect: Rect2)
## Emitted after groundwork changed terrain heights inside this XZ rectangle (navigation
## must re-read the terrain faces there).
signal terrain_edited(rect: Rect2)

const CELL := 128.0
## Largest distance (m) from an instance origin to the edge of its footprint.
const MAX_REACH := 10.0
## Grid size (m) of the water triangle index.
const WATER_CELL := 64.0

@export var terrain: Terrain3D
@export var vegetation: VegetationStreamer
@export var sim: WorldSim
## Map half size; nothing is built closer than 5 m to the edge.
@export var map_half_size := 0.0
## Terrain below this height counts as water (a sea level). Rivers and lakes come from
## set_water().
@export var water_level := -INF
@export var render_radius := 1800.0
@export var collision_radius := 260.0
@export var update_interval := 0.2
## Extra clearance around tree trunks for placement.
@export var tree_margin := 0.35
## Navmesh obstacles are this much larger on every side than the collision boxes: the
## 0.75 m navmesh raster otherwise lets paths clip wall corners. 0.3 m (WORLD-BASE-01) left
## about 0.3 m worst-case clearance, less than the 0.35 m soldier capsule; a soldier got
## stuck on a command post corner after an area re-centre (WORLD-INTEGRATION-01).
@export var nav_margin := 0.5
## Grass layer whose exclusion mask structures paint into (optional).
@export var grass: GrassLayer
## Grass-free margin around footprints (m), on top of half a mask texel.
@export var grass_margin := 1.0
## Vegetation that placement may clear inside a footprint when clearing is on (trees,
## juniper, shrubs, stones, logs, stumps, ferns of the Nordic library). Boulders,
## outcrops and the settlement buildings and props are never cleared and keep blocking.
@export var clearable_ids := PackedInt32Array([1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 14, 15])
## Ids without a collider that are always removed under a footprint (they would poke
## through floors); trees only go when clearing is on.
@export var undergrowth_ids := PackedInt32Array([7, 8, 11, 13, 14, 15])
## Cleared margin around footprints (m).
@export var clear_margin := 1.0
## Groundwork: buildings level the ground under them (cut and fill to one pad height).
@export var level_ground := true
## Steepest average terrain slope a building can be levelled on.
@export var level_max_slope_deg := 20.0
## Largest cut or fill (m) between the pad and the terrain anywhere under the footprint.
@export var level_max_depth := 2.5
## Width (m) of the zone around a pad where the levelled ground blends back into the terrain.
@export var level_blend := 4.0
## Largest cut or fill allowed when the groundwork would touch a road (road meshes follow
## the original terrain).
@export var level_max_depth_near_road := 0.3
## WORLD-PLAYTEST-01 roads and paved areas: width (m) of the zone beyond their edge where
## the grading blends into the ground, of the painted dirt verge, the tightest curve a road
## may have (a truck's turning circle) and the largest paved area.
@export var surface_blend := 5.0
@export var surface_verge := 1.6
@export var min_road_radius := 9.0
@export var max_area_m2 := 40000.0

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
## NAVIGATION N1-B: solid vegetation bucketed in TRUNK_SUB metre sub-cells per vegetation cell, built on first query.
var _trunk_sub := {}
var _trunk_max_r := 4.0
const TRUNK_SUB := 8.0
## Vector2i water cell -> Array of [a, b, c] world-space triangles (set_water).
var _water := {}
## Groundwork: original terrain height of every vertex a pad changed (Vector2i -> float).
var _orig_heights := {}
## Original grass mask texels (copy of the world mask image) and the pending dirty area.
var _mask_original: Image
var _mask_dirty := Rect2()
var _mask_has_dirty := false
var _mask_timer := 0.0
## Last cost of the deferred work (ms), for the HUD / tests.
var timings := {"grass_ms": 0.0, "cells_ms": 0.0}
## WORLD-PLAYTEST-01 ground surfaces (roads, paved areas): id -> StructureState. They are
## not in the structure index (no mesh, no collision box, never an obstacle).
var _surfaces := {}
## Blocking footprints for blocks_point(): Vector2i (BLOCK_CELL m) -> Array of boxes.
const BLOCK_CELL := 8.0
var _block_grid := {}
var _block_dirty := true
## NAVIGATION N1-C1: structure id -> [[obb, [Vector2i cells]], ...] for what the structure put into _block_grid. A placement, change
## or removal updates the fine grid for that structure only; the full rebuild (every module of every base, 100-200 ms) is left to
## the first use and to _on_cleared.
var _block_of := {}
## Original control-map value of every vertex a surface painted (Vector2i -> int).
var _orig_control := {}


func bind_state(p_state: ConstructionState) -> void:
	if state:
		state.structure_added.disconnect(_on_added)
		state.structure_removed.disconnect(_on_removed)
		state.structure_changed.disconnect(_on_changed)
		state.cleared.disconnect(_on_cleared)
		state.clearings_changed.disconnect(_apply_clearings)
	state = p_state
	state.structure_added.connect(_on_added)
	state.structure_removed.connect(_on_removed)
	state.structure_changed.connect(_on_changed)
	state.cleared.connect(_on_cleared)
	state.clearings_changed.connect(_apply_clearings)
	_on_cleared()
	for s in state.all():
		_on_added(s)
	_apply_clearings(true)


func _process(delta: float) -> void:
	if _mask_has_dirty:
		_mask_timer -= delta
		if _mask_timer <= 0.0:
			_update_grass_mask()
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
	return {"structures": state.count(), "surfaces": _surfaces.size(), "instances": modules, "indexed_cells": _index.size(),
		"visible_cells": _visual.size(), "multimeshes": mmis, "drawn_instances": inst,
		"collision_cells": _bodies.size(), "collision_shapes": shapes}


# --- Placement checks -------------------------------------------------------------

## Fits a building to the terrain and validates it.
## Returns {ok: bool, reason: String, xform: Transform3D}.
func check_building(def: StructureDef, pos: Vector3, yaw: float, ignore_id := -1, clear_trees := false) -> Dictionary:
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
			if _wet(w.x, w.z, h):
				reason = "water"
			hmin = minf(hmin, h)
			hmax = maxf(hmax, h)
			sxh += lx * h
			szh += lz * h
			sxx += lx * lx
			szz += lz * lz
		if reason == "outside the terrain":
			break
	var levelled := level_ground and terrain != null and hmax > -INF
	# Groundwork: the pad sits halfway between the lowest and highest ground, so cut and
	# fill are equal. Without it the building rests on the highest point.
	var pad_y := (hmin + hmax) * 0.5 if levelled else hmax
	var xform := Transform3D(basis, Vector3(pos.x, (pad_y if hmax > -INF else pos.y) - def.sink, pos.z))
	var depth := (hmax - hmin) * 0.5 if levelled else 0.0
	if reason == "" and not _inside_map(xform.origin, b.size.length() * 0.5 + (level_blend if levelled else 0.0)):
		reason = "outside the map"
	if reason == "":
		var gx := sxh / maxf(sxx, 0.001)
		var gz := szh / maxf(szz, 0.001)
		var slope := rad_to_deg(atan(sqrt(gx * gx + gz * gz)))
		var max_slope := maxf(def.max_slope_deg, level_max_slope_deg) if levelled else def.max_slope_deg
		if slope > max_slope:
			reason = "too steep (%.0f° > %.0f°)" % [slope, max_slope]
		elif not levelled and hmax - hmin > def.max_ground_gap:
			reason = "uneven ground (%.1f m)" % (hmax - hmin)
		elif levelled and depth > level_max_depth:
			reason = "too uneven to level (%.1f m cut / fill > %.1f m)" % [depth, level_max_depth]
		elif levelled and depth > level_max_depth_near_road and _near_road(_obb(def, xform), level_blend):
			reason = "too uneven to level next to a road (%.1f m cut / fill)" % depth
	if reason == "":
		reason = _blocked(def, _obb(def, xform), ignore_id, -1, clear_trees)
	return {"ok": reason == "", "reason": reason, "xform": xform, "level_m": snappedf(depth, 0.01)}


## Fits every module of a line and validates each one.
## Returns {modules: [{xform, ok, reason}], ok_count, length_m}.
func check_line(def: StructureDef, points: PackedVector3Array, ignore_id := -1, clear_trees := false) -> Dictionary:
	var mods := ModularLine.modules(def, points)
	var out := []
	var ok_count := 0
	for i in mods.size():
		var m: Dictionary = mods[i]
		var r := fit_module(def, m.center, m.dir, i)
		if r.ok:
			r.reason = _blocked(def, _obb(def, r.xform), ignore_id, -1, clear_trees)
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
	if hmin < water_level or _wet(c.x, c.y, hc) or _wet(p1.x, p1.y, h1) or _wet(p2.x, p2.y, h2):
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
## Only ground-touching collision boxes (walls, not roofs). Non-blocking types (gates) carve
## their boxes too, which are only the posts: the opening between them stays walkable, and
## paths no longer run into the posts (WORLD-INTEGRATION-01).
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
		# The record holds the fitted transform (pad height - sink); refitting would read
		# ground that this building's own groundwork has already changed.
		s.instances.append(Transform3D(Basis(Vector3.UP, s.yaw), s.position))


func _on_added(s: StructureState) -> void:
	if _is_surface(s):
		_block_dirty = true
		_surface_changed(s, true)
		return
	_resolve(s)
	_block_update(s)
	for i in s.instances.size():
		var c := _cell_of(s.instances[i].origin)
		if not _index.has(c):
			_index[c] = []
		_index[c].append(Vector2i(s.id, i))
		_dirty_cells[c] = true
	if _is_pad(s):
		_relevel(_rect_of(s).grow(level_blend))
	_grass_dirty(_rect_of(s))
	area_changed.emit(_rect_of(s))


func _on_removed(s: StructureState) -> void:
	if _surfaces.has(s.id):
		_block_dirty = true
		_surface_changed(s, false)
		return
	_block_forget(s.id)
	for i in s.instances.size():
		var c := _cell_of(s.instances[i].origin)
		var list: Array = _index.get(c, [])
		list.erase(Vector2i(s.id, i))
		if list.is_empty():
			_index.erase(c)
		_dirty_cells[c] = true
	if _is_pad(s):
		_relevel(_rect_of(s).grow(level_blend))
	_grass_dirty(_rect_of(s))
	area_changed.emit(_rect_of(s))


func _on_changed(s: StructureState) -> void:
	_block_update(s)
	for i in s.instances.size():
		_dirty_cells[_cell_of(s.instances[i].origin)] = true
	_grass_dirty(_rect_of(s))
	area_changed.emit(_rect_of(s))


func _on_cleared() -> void:
	_block_dirty = true
	_block_of.clear()
	for c in _visual.keys():
		_free_visual(c)
	for c in _bodies.keys():
		_bodies[c].queue_free()
	_bodies.clear()
	_index.clear()
	_dirty_cells.clear()
	_surfaces.clear()
	_restore_all_ground()
	_restore_all_paint()
	if _mask_original and grass and grass.mask:
		grass.mask.image.copy_from(_mask_original)
		grass.apply_mask()


func _rect_of(s: StructureState) -> Rect2:
	var r := Rect2()
	var first := true
	for xf in s.instances:
		var p := Vector2(xf.origin.x, xf.origin.z)
		r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
		first = false
	return r.grow(MAX_REACH)


# --- Grass clearing ---------------------------------------------------------------

func _grass_dirty(rect: Rect2, delay := 0.3) -> void:
	if grass == null or grass.mask == null or grass.mask.image == null:
		return
	_mask_dirty = rect if not _mask_has_dirty else _mask_dirty.merge(rect)
	_mask_has_dirty = true
	_mask_timer = delay


## Restores the dirty area from the original mask, repaints every structure there and
## pushes the mask to the grass shader (one texture upload).
func _update_grass_mask() -> void:
	var t0 := Time.get_ticks_usec()
	_mask_has_dirty = false
	var mask := grass.mask
	if _mask_original == null:
		_mask_original = mask.image.duplicate()
	var t := mask.texel_m
	var area := _mask_dirty.grow(grass_margin + t)
	var w := mask.image.get_width()
	var h := mask.image.get_height()
	var x0 := clampi(floori((area.position.x - mask.origin.x) / t), 0, w - 1)
	var z0 := clampi(floori((area.position.y - mask.origin.y) / t), 0, h - 1)
	var x1 := clampi(ceili((area.end.x - mask.origin.x) / t), 0, w - 1)
	var z1 := clampi(ceili((area.end.y - mask.origin.y) / t), 0, h - 1)
	mask.image.blit_rect(_mask_original, Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1), Vector2i(x0, z0))
	var reach := grass_margin + t * 0.5
	var seen := {}
	for c in _cells_around(area.get_center(), maxf(area.size.x, area.size.y) * 0.5 + MAX_REACH):
		for e: Vector2i in _index.get(c, []):
			var s: StructureState = state.get_structure(e.x)
			if s == null or (s.is_line() and s.is_removed(e.y)) or seen.has(e):
				continue
			seen[e] = true
			var obb := _obb(StructureCatalog.get_def(s.type_id), s.instances[e.y])
			var r: float = (obb[3] as Vector2).length() + reach
			var oc: Vector2 = obb[0]
			for pz in range(maxi(floori((oc.y - r - mask.origin.y) / t), 0), mini(ceili((oc.y + r - mask.origin.y) / t), h - 1) + 1):
				for px in range(maxi(floori((oc.x - r - mask.origin.x) / t), 0), mini(ceili((oc.x + r - mask.origin.x) / t), w - 1) + 1):
					var p := mask.origin + Vector2(px + 0.5, pz + 0.5) * t
					if _obb_circle(obb, p, reach):
						mask.image.set_pixel(px, pz, Color.WHITE)
	# Closed perimeters (a line ending on its start) clear the whole compound.
	for sid in _ids_in(area):
		var s: StructureState = state.get_structure(sid)
		if not s.is_line() or s.points.size() < 4 or Vector2(s.points[0].x - s.points[-1].x, s.points[0].z - s.points[-1].z).length() > 0.1:
			continue
		var poly := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in s.points:
			poly.append(Vector2(p.x, p.z))
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
		for pz in range(maxi(floori((lo.y - mask.origin.y) / t), 0), mini(ceili((hi.y - mask.origin.y) / t), h - 1) + 1):
			for px in range(maxi(floori((lo.x - mask.origin.x) / t), 0), mini(ceili((hi.x - mask.origin.x) / t), w - 1) + 1):
				if Geometry2D.is_point_in_polygon(mask.origin + Vector2(px + 0.5, pz + 0.5) * t, poly):
					mask.image.set_pixel(px, pz, Color.WHITE)
	# WORLD-PLAYTEST-01: roads and paved areas are grass-free like the world's own roads.
	for sf: StructureState in _surfaces_in(area):
		var sdef := StructureCatalog.get_def(sf.type_id)
		if sdef.surface == StructureDef.Surface.ROAD:
			var hw := sdef.surface_width * 0.5 + t * 0.5
			for i in sf.profile.size() - 1:
				var a := Vector2(sf.profile[i].x, sf.profile[i].z)
				var b := Vector2(sf.profile[i + 1].x, sf.profile[i + 1].z)
				var lo := a.min(b) - Vector2(hw, hw)
				var hi := a.max(b) + Vector2(hw, hw)
				for pz in range(maxi(floori((lo.y - mask.origin.y) / t), 0), mini(ceili((hi.y - mask.origin.y) / t), h - 1) + 1):
					for px in range(maxi(floori((lo.x - mask.origin.x) / t), 0), mini(ceili((hi.x - mask.origin.x) / t), w - 1) + 1):
						if LineOfFire._point_segment_dist2d(mask.origin + Vector2(px + 0.5, pz + 0.5) * t, a, b) <= hw:
							mask.image.set_pixel(px, pz, Color.WHITE)
		else:
			var poly := PackedVector2Array()
			var lo := Vector2(INF, INF)
			var hi := -lo
			for v in sf.points:
				poly.append(Vector2(v.x, v.z))
				lo = lo.min(Vector2(v.x, v.z))
				hi = hi.max(Vector2(v.x, v.z))
			for pz in range(maxi(floori((lo.y - mask.origin.y) / t), 0), mini(ceili((hi.y - mask.origin.y) / t), h - 1) + 1):
				for px in range(maxi(floori((lo.x - mask.origin.x) / t), 0), mini(ceili((hi.x - mask.origin.x) / t), w - 1) + 1):
					if Geometry2D.is_point_in_polygon(mask.origin + Vector2(px + 0.5, pz + 0.5) * t, poly):
						mask.image.set_pixel(px, pz, Color.WHITE)
	var t1 := Time.get_ticks_usec()
	grass.apply_mask()
	timings["grass_paint_ms"] = (t1 - t0) / 1000.0
	timings["grass_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


## Ids of structures with an instance in the cells covering rect.
func _ids_in(rect: Rect2) -> Array:
	var ids := {}
	for c in _cells_around(rect.get_center(), maxf(rect.size.x, rect.size.y) * 0.5 + MAX_REACH):
		for e: Vector2i in _index.get(c, []):
			ids[e.x] = true
	return ids.keys()


# --- Cells: visuals and collision ---------------------------------------------------

func _refresh_cells() -> void:
	var t0 := Time.get_ticks_usec()
	var rebuilt := not _dirty_cells.is_empty()
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
	if rebuilt:
		timings["cells_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


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


# --- Groundwork --------------------------------------------------------------------

func _levels(def: StructureDef) -> bool:
	return level_ground and terrain != null and def != null and not def.linear


func _is_pad(s: StructureState) -> bool:
	return not s.is_line() and _levels(StructureCatalog.get_def(s.type_id)) and not s.instances.is_empty()


## Margin around a footprint that placement clears of vegetation.
func _clear_reach(def: StructureDef) -> float:
	return maxf(clear_margin, level_blend) if _levels(def) else clear_margin


## The groundwork zone of a footprint touches a road (the world's original grass mask).
func _near_road(obb: Array, reach: float) -> bool:
	if grass == null or grass.mask == null or grass.mask.image == null:
		return false
	if _mask_original == null:
		_mask_original = grass.mask.image.duplicate()
	var m := grass.mask
	var r: float = (obb[3] as Vector2).length() + reach
	var c: Vector2 = obb[0]
	var steps := ceili(r / m.texel_m)
	for iz in range(-steps, steps + 1):
		for ix in range(-steps, steps + 1):
			var p := c + Vector2(ix, iz) * m.texel_m
			if not _obb_circle(obb, p, reach):
				continue
			var px := int((p.x - m.origin.x) / m.texel_m)
			var pz := int((p.y - m.origin.y) / m.texel_m)
			if px >= 0 and pz >= 0 and px < _mask_original.get_width() and pz < _mask_original.get_height() and _mask_original.get_pixel(px, pz).r >= 0.5:
				return true
	return false


## Pads touching rect: [obb, pad height] of every levelling building.
func _pads_in(rect: Rect2) -> Array:
	var out := []
	for sid in _ids_in(rect.grow(level_blend)):
		var s: StructureState = state.get_structure(sid)
		if s == null or not _is_pad(s):
			continue
		var def := StructureCatalog.get_def(s.type_id)
		out.append([_obb(def, s.instances[0]), s.instances[0].origin.y + def.sink])
	return out


## Recomputes the terrain heights inside rect from the original ground and every pad
## there: inside a footprint the pad height, in the blend zone a smooth mix (weights^4 so
## neighbouring pads barely pull on each other's edges), elsewhere the original height.
## Then uploads the height maps, patches the physics shapes and refits lines in the area.
func _relevel(rect: Rect2) -> void:
	if terrain == null or terrain.data == null:
		return
	var t0 := Time.get_ticks_usec()
	var sp: float = terrain.vertex_spacing
	var pads := _pads_in(rect)
	var x0 := floori(rect.position.x / sp)
	var z0 := floori(rect.position.y / sp)
	var x1 := ceili(rect.end.x / sp)
	var z1 := ceili(rect.end.y / sp)
	var changed := 0
	var regions := {}
	# WORLD-PLAYTEST-01: the vertices to recompute are those near a pad, inside a road or
	# area corridor, or changed before (to restore); a long road's bounding rectangle would
	# otherwise mean hundreds of thousands of untouched vertices.
	var field := _surface_field(rect)
	var keys := {}
	for k: Vector2i in field:
		keys[k] = true
	for k: Vector2i in _orig_heights:
		if k.x >= x0 and k.x <= x1 and k.y >= z0 and k.y <= z1:
			keys[k] = true
	for pad: Array in pads:
		var reach: float = (pad[0][3] as Vector2).length() + level_blend
		var c: Vector2 = pad[0][0]
		for iz in range(maxi(floori((c.y - reach) / sp), z0), mini(ceili((c.y + reach) / sp), z1) + 1):
			for ix in range(maxi(floori((c.x - reach) / sp), x0), mini(ceili((c.x + reach) / sp), x1) + 1):
				keys[Vector2i(ix, iz)] = true
	for key: Vector2i in keys:
		var ix := key.x
		var iz := key.y
		var p := Vector2(ix * sp, iz * sp)
		var px := _pixel_pos(ix, iz, sp)
		var orig: float = _orig_heights[key] if _orig_heights.has(key) else terrain.data.get_pixel(Terrain3DRegion.TYPE_HEIGHT, px).r
		var w_max := 0.0
		var core := NAN
		var sw := 0.0
		var swy := 0.0
		for pad: Array in pads:
			var d := _obb_distance(pad[0], p)
			if d <= 0.0:
				core = pad[1]
				break
			if d >= level_blend:
				continue
			var w := 1.0 - smoothstep(0.0, level_blend, d)
			w_max = maxf(w_max, w)
			var w4 := w * w * w * w
			sw += w4
			swy += w4 * float(pad[1])
		# Roads and paved areas: their surface height inside, a blend outside (pads win).
		var e: Array = field.get(key, [])
		if not e.is_empty() and is_nan(core):
			if e[0] <= 0.0:
				core = e[1]
			else:
				var w := 1.0 - smoothstep(0.0, e[2], e[0])
				w_max = maxf(w_max, w)
				var w4 := w * w * w * w
				sw += w4
				swy += w4 * float(e[1])
		var h := orig
		if not is_nan(core):
			h = core
		elif w_max > 0.0:
			h = lerpf(orig, swy / sw, w_max)
		var cur: float = terrain.data.get_pixel(Terrain3DRegion.TYPE_HEIGHT, px).r
		if absf(h - cur) < 0.0005:
			if h == orig and _orig_heights.has(key) and is_nan(core) and w_max == 0.0:
				_orig_heights.erase(key)
			continue
		if not _orig_heights.has(key):
			_orig_heights[key] = orig
		terrain.data.set_pixel(Terrain3DRegion.TYPE_HEIGHT, px, Color(h, 0.0, 0.0, 1.0))
		if is_nan(core) and w_max == 0.0:
			_orig_heights.erase(key)
		changed += 1
		regions[terrain.data.get_region_location(px)] = true
	if changed > 0:
		for loc in regions:
			var region: Terrain3DRegion = terrain.data.get_region(loc)
			if region:
				region.set_edited(true)
		terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false, false)
		for loc in regions:
			var region: Terrain3DRegion = terrain.data.get_region(loc)
			if region:
				region.set_edited(false)
		timings["level_shapes"] = _patch_collision(rect)
		_refit_lines(rect)
		terrain_edited.emit(rect)
	timings["level_vertices"] = changed
	timings["level_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


## Puts every changed vertex back (all structures cleared).
func _restore_all_ground() -> void:
	if terrain == null or _orig_heights.is_empty():
		return
	var sp: float = terrain.vertex_spacing
	var lo := Vector2(INF, INF)
	var hi := -lo
	for key: Vector2i in _orig_heights:
		var px := _pixel_pos(key.x, key.y, sp)
		terrain.data.set_pixel(Terrain3DRegion.TYPE_HEIGHT, px, Color(_orig_heights[key], 0.0, 0.0, 1.0))
		terrain.data.get_regionp(px).set_edited(true)
		lo = lo.min(Vector2(key) * sp)
		hi = hi.max(Vector2(key) * sp)
	_orig_heights.clear()
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false, false)
	for r: Terrain3DRegion in terrain.data.get_regions_active():
		r.set_edited(false)
	var rect := Rect2(lo, hi - lo).grow(2.0)
	_patch_collision(rect)
	terrain_edited.emit(rect)


## Position that addresses the height pixel of vertex (ix, iz) (a quarter cell inside it,
## safe for both floor and round pixel lookups).
static func _pixel_pos(ix: int, iz: int, sp: float) -> Vector3:
	return Vector3((ix + 0.25) * sp, 0.0, (iz + 0.25) * sp)


## Distance from p to an oriented rectangle (0 inside).
static func _obb_distance(a: Array, p: Vector2) -> float:
	var d := p - (a[0] as Vector2)
	var lx: float = absf(d.dot(a[1])) - a[3].x
	var lz: float = absf(d.dot(a[2])) - a[3].y
	return Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()


## Terrain3D builds its collision from the height data only when shapes move or on a full
## rebuild (~0.4 s for the 200 m radius). Instead, the heightfield shapes overlapping rect
## get their data re-read from the edited terrain. Returns the number of patched shapes.
func _patch_collision(rect: Rect2) -> int:
	if terrain.collision == null or not terrain.collision.is_enabled():
		return 0
	var body := terrain.collision.get_rid()
	if not body.is_valid():
		return 0
	var n := 0
	var delta := 0.0
	for i in PhysicsServer3D.body_get_shape_count(body):
		var shape := PhysicsServer3D.body_get_shape(body, i)
		if PhysicsServer3D.shape_get_type(shape) != PhysicsServer3D.SHAPE_HEIGHTMAP:
			continue
		var xf := PhysicsServer3D.body_get_shape_transform(body, i)
		var data: Dictionary = PhysicsServer3D.shape_get_data(shape)
		var w: int = data.width
		var dpt: int = data.depth
		var half := Vector3((w - 1) * 0.5, 0.0, (dpt - 1) * 0.5)
		var a := xf * (-half)
		var b := xf * half
		var srect := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z)))
		if not srect.intersects(rect):
			continue
		var heights: PackedFloat32Array = data.heights
		var sy := xf.basis.y.length()
		var lo := INF
		var hi := -INF
		for iz in dpt:
			for ix in w:
				var wp := xf * Vector3(ix - half.x, 0.0, iz - half.z)
				var h: float = terrain.data.get_height(Vector3(wp.x, 0.0, wp.z))
				if is_nan(h):
					continue
				var lh := (h - xf.origin.y) / sy
				delta = maxf(delta, absf(heights[iz * w + ix] - lh) * sy)
				heights[iz * w + ix] = lh
				lo = minf(lo, lh)
				hi = maxf(hi, lh)
		data.heights = heights
		data.min_height = minf(data.get("min_height", lo), lo)
		data.max_height = maxf(data.get("max_height", hi), hi)
		PhysicsServer3D.shape_set_data(shape, data)
		n += 1
	# Largest height change written (m); on unedited ground this checks that the shapes
	# are read back exactly as Terrain3D built them.
	timings["collision_patch_delta_m"] = delta
	return n


## Line structures in rect follow the ground: refit their modules after groundwork.
func _refit_lines(rect: Rect2) -> void:
	for sid in _ids_in(rect):
		var s: StructureState = state.get_structure(sid)
		if s == null or not s.is_line():
			continue
		var before := s.instances.duplicate()
		_resolve(s)
		if s.instances != before:
			_block_update(s)
			for xf in s.instances:
				_dirty_cells[_cell_of(xf.origin)] = true


# --- Ground surfaces: roads and paved areas (WORLD-PLAYTEST-01) ----------------------

## Surfaces (roads, paved areas) are built into the terrain itself, like the world's own
## unpaved roads and streets: graded (the groundwork above, from the record's profile) and
## painted into the Terrain3D control map with the world's road textures. The terrain
## files are never written; original heights and control values are kept and restored
## when a surface is removed. Roads also feed the RoadNetwork (WorldState.roads), which the
## strategic routes follow; paved areas do not (no navigation shortcut).

func _is_surface(s: StructureState) -> bool:
	var def := StructureCatalog.get_def(s.type_id)
	return def != null and def.is_surface()


func surface_count() -> int:
	return _surfaces.size()


func _surface_changed(s: StructureState, added: bool) -> void:
	if added:
		if s.profile.is_empty():
			push_warning("StructureManager: surface %d has no profile" % s.id)
			return
		_surfaces[s.id] = s
	else:
		_surfaces.erase(s.id)
	var rect := _surface_rect(s)
	var t0 := Time.get_ticks_usec()
	_relevel(rect)
	_repaint(rect)
	timings["surface_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_grass_dirty(rect)
	area_changed.emit(rect)


## XZ bounds of a surface including its blend zone.
func _surface_rect(s: StructureState) -> Rect2:
	var def := StructureCatalog.get_def(s.type_id)
	var pts := s.profile if def.surface == StructureDef.Surface.ROAD else s.points
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	return Rect2(lo, hi - lo).grow(def.surface_width * 0.5 + surface_blend + terrain_spacing())


func terrain_spacing() -> float:
	return terrain.vertex_spacing if terrain else 2.0


func _surfaces_in(rect: Rect2) -> Array:
	var out := []
	for s: StructureState in _surfaces.values():
		if _surface_rect(s).intersects(rect):
			out.append(s)
	# Areas first, then roads (a road across a yard is painted over it), each by id.
	out.sort_custom(func(a: StructureState, b: StructureState) -> bool:
		var ra := StructureCatalog.get_def(a.type_id).surface == StructureDef.Surface.ROAD
		var rb := StructureCatalog.get_def(b.type_id).surface == StructureDef.Surface.ROAD
		return a.id < b.id if ra == rb else rb)
	return out


## Influence of every surface on the terrain vertices inside rect:
## Vector2i vertex -> [distance outside the surface edge (<= 0 inside), surface height,
## blend width, StructureDef]. Where surfaces overlap the one reaching deepest wins.
func _surface_field(rect: Rect2) -> Dictionary:
	var out := {}
	if _surfaces.is_empty() or terrain == null:
		return out
	var sp := terrain_spacing()
	var blend := surface_blend
	for s: StructureState in _surfaces_in(rect):
		var def := StructureCatalog.get_def(s.type_id)
		if def.surface == StructureDef.Surface.ROAD:
			var half := def.surface_width * 0.5
			var reach := half + blend
			var pts := s.profile
			for i in pts.size() - 1:
				var a := Vector2(pts[i].x, pts[i].z)
				var b := Vector2(pts[i + 1].x, pts[i + 1].z)
				var ab := b - a
				var l2 := maxf(ab.length_squared(), 1e-6)
				var lo := a.min(b) - Vector2(reach, reach)
				var hi := a.max(b) + Vector2(reach, reach)
				lo = lo.max(rect.position)
				hi = hi.min(rect.end)
				for iz in range(ceili(lo.y / sp), floori(hi.y / sp) + 1):
					for ix in range(ceili(lo.x / sp), floori(hi.x / sp) + 1):
						var q := Vector2(ix * sp, iz * sp)
						var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0)
						var d := q.distance_to(a + ab * t)
						if d > reach:
							continue
						var key := Vector2i(ix, iz)
						var dout := d - half
						var e: Array = out.get(key, [])
						if e.is_empty() or dout < e[0]:
							out[key] = [dout, lerpf(pts[i].y, pts[i + 1].y, t), blend, def]
		else:
			var poly := PackedVector2Array()
			var lo := Vector2(INF, INF)
			var hi := -lo
			for p in s.points:
				poly.append(Vector2(p.x, p.z))
				lo = lo.min(Vector2(p.x, p.z))
				hi = hi.max(Vector2(p.x, p.z))
			var c: Vector3 = s.profile[0]
			var g: Vector3 = s.profile[1] if s.profile.size() > 1 else Vector3.ZERO
			lo = (lo - Vector2(blend, blend)).max(rect.position)
			hi = (hi + Vector2(blend, blend)).min(rect.end)
			for iz in range(ceili(lo.y / sp), floori(hi.y / sp) + 1):
				for ix in range(ceili(lo.x / sp), floori(hi.x / sp) + 1):
					var q := Vector2(ix * sp, iz * sp)
					var d := StrategicRoutes._dist_to_poly(q, poly)
					var dout := -d if Geometry2D.is_point_in_polygon(q, poly) else d
					if dout > blend:
						continue
					var key := Vector2i(ix, iz)
					var e: Array = out.get(key, [])
					if e.is_empty() or dout < e[0]:
						out[key] = [dout, c.y + g.x * (q.x - c.x) + g.z * (q.y - c.z), blend, def]
	return out


## Paints the control map inside rect from the surfaces there (surface textures inside, a
## dirt verge outside the edge) and restores the original paint where none is left.
func _repaint(rect: Rect2) -> void:
	if terrain == null or terrain.data == null:
		return
	var sp := terrain_spacing()
	var field := _surface_field(rect)
	var keys := {}
	for k: Vector2i in field:
		keys[k] = true
	var x0 := floori(rect.position.x / sp)
	var z0 := floori(rect.position.y / sp)
	var x1 := ceili(rect.end.x / sp)
	var z1 := ceili(rect.end.y / sp)
	for k: Vector2i in _orig_control:
		if k.x >= x0 and k.x <= x1 and k.y >= z0 and k.y <= z1:
			keys[k] = true
	var regions := {}
	var changed := 0
	for key: Vector2i in keys:
		var pos := Vector3(key.x * sp, 0.0, key.y * sp)
		var cur: int = terrain.data.get_control(pos)
		var orig: int = _orig_control.get(key, cur)
		var val := orig
		var e: Array = field.get(key, [])
		if not e.is_empty():
			var def: StructureDef = e[3]
			var n := _hash01(key)
			if e[0] <= 0.0:
				val = _control(orig, def.surface_texture, def.surface_overlay, clampf(def.surface_blend + 0.12 * (n - 0.5), 0.0, 1.0))
			elif e[0] < surface_verge:
				# Verge: the original ground with worn dirt fading out from the edge.
				val = _control(orig, orig >> 27 & 0x1F, WorldTerrainGenerator.TEX_DIRT, (1.0 - e[0] / surface_verge) * (0.45 + 0.2 * n))
		if val == cur:
			if e.is_empty():
				_orig_control.erase(key)
			continue
		if not _orig_control.has(key):
			_orig_control[key] = orig
		terrain.data.set_control(pos, val)
		if e.is_empty():
			_orig_control.erase(key)
		changed += 1
		regions[terrain.data.get_region_location(pos)] = true
	if changed > 0:
		_upload(regions, Terrain3DRegion.TYPE_CONTROL)
	timings["paint_vertices"] = changed


func _upload(regions: Dictionary, map_type: int) -> void:
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(true)
	terrain.data.update_maps(map_type, false, false)
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(false)


## Control value with new base / overlay textures and blend; the other bits (UV rotation
## and scale, hole, navigation, auto-shader) are kept. Same layout as the world generator.
static func _control(orig: int, base: int, over: int, blend: float) -> int:
	var b8 := clampi(roundi(blend * 255.0), 0, 255)
	return (orig & 0x3FFF) | ((base & 0x1F) << 27) | ((over & 0x1F) << 22) | (b8 << 14)


static func _hash01(k: Vector2i) -> float:
	var h := (k.x * 73856093) ^ (k.y * 19349663)
	return float(absi(h) % 1000) / 1000.0


func _restore_all_paint() -> void:
	if terrain == null or _orig_control.is_empty():
		return
	var sp := terrain_spacing()
	var regions := {}
	for key: Vector2i in _orig_control:
		var pos := Vector3(key.x * sp, 0.0, key.y * sp)
		terrain.data.set_control(pos, _orig_control[key])
		regions[terrain.data.get_region_location(pos)] = true
	_orig_control.clear()
	_upload(regions, Terrain3DRegion.TYPE_CONTROL)


## Ground height before any groundwork (the world's own terrain).
func original_height(x: float, z: float) -> float:
	var sp := terrain_spacing()
	var key := Vector2i(roundi(x / sp), roundi(z / sp))
	if _orig_heights.has(key) and absf(x - key.x * sp) < 0.01 and absf(z - key.y * sp) < 0.01:
		return _orig_heights[key]
	return _height(x, z)


## Validates a road through control points and grades it.
## start / end: RoadNetwork.nearest() results the ends are snapped to ({} = free end).
## Returns {ok, reason, profile (graded centre line), length_m, max_cut_m, grade, radius_m,
## bad: PackedInt32Array of profile indices that fail (preview)}.
func check_road(def: StructureDef, ctrl: PackedVector3Array, start := {}, end := {}, clear_trees := true) -> Dictionary:
	var out := {"ok": false, "reason": "", "profile": PackedVector3Array(), "length_m": 0.0, "max_cut_m": 0.0,
		"grade": 0.0, "radius_m": INF, "bad": PackedInt32Array()}
	if ctrl.size() < 2:
		out.reason = "click at least two points"
		return out
	var line := RoadNetwork.spline(ctrl, 2.0)
	var n := line.size()
	for i in n:
		var h := _height(line[i].x, line[i].z)
		if is_nan(h):
			out.reason = "outside the terrain"
			out.bad.append(i)
			return out
		line[i].y = h
	var pins := {}
	if not start.is_empty():
		pins[0] = (start.pos as Vector3).y
	if not end.is_empty():
		pins[n - 1] = (end.pos as Vector3).y
	var prof := RoadNetwork.grade(line, def.max_grade, pins)
	out.profile = prof
	out.length_m = RoadNetwork.length_of(prof)
	out.radius_m = RoadNetwork.min_radius(prof)
	var half := def.surface_width * 0.5
	var reason := ""
	if out.length_m < 4.0:
		reason = "too short"
	elif out.radius_m < min_road_radius:
		reason = "curve too tight (radius %.0f m < %.0f m)" % [out.radius_m, min_road_radius]
	var max_cut := 0.0
	var steep := 0.0
	for i in n:
		var p := prof[i]
		var bad := ""
		var cut := absf(p.y - line[i].y)
		max_cut = maxf(max_cut, cut)
		if i > 0:
			var ds := maxf(Vector2(p.x - prof[i - 1].x, p.z - prof[i - 1].z).length(), 0.05)
			steep = maxf(steep, absf(p.y - prof[i - 1].y) / ds)
		if not _inside_map(p, half + 2.0):
			bad = "outside the map"
		elif _wet(p.x, p.z, line[i].y) or _wet(p.x, p.z, p.y):
			bad = "water (roads cannot cross rivers or lakes; use a bridge)"
		elif cut > def.max_cut:
			bad = "too steep for the ground (%.1f m %s > %.1f m)" % [cut, "fill" if p.y > line[i].y else "cut", def.max_cut]
		if bad != "":
			out.bad.append(i)
			if reason == "":
				reason = bad
	out.max_cut_m = snappedf(max_cut, 0.01)
	out.grade = snappedf(steep, 0.001)
	if reason == "" and steep > def.max_grade + 0.01:
		reason = "too steep at the junction (%.0f %% > %.0f %%)" % [steep * 100.0, def.max_grade * 100.0]
	# Structures and solid vegetation along the corridor (every ~4 m).
	if reason == "":
		var k := 0
		while k < n - 1:
			var k2 := mini(k + 2, n - 1)
			var a := Vector2(prof[k].x, prof[k].z)
			var b := Vector2(prof[k2].x, prof[k2].z)
			var dir := (b - a).normalized() if b.distance_to(a) > 0.01 else Vector2.RIGHT
			var obb := [(a + b) * 0.5, dir, Vector2(-dir.y, dir.x), Vector2(a.distance_to(b) * 0.5 + 0.2, half)]
			var why := _surface_blocked(obb, clear_trees)
			if why != "":
				reason = why
				for j in range(k, k2 + 1):
					out.bad.append(j)
				break
			k = k2
	out.reason = reason
	out.ok = reason == ""
	return out


## Validates a paved area (polygon corners, XZ) and grades it to one plane.
## Returns {ok, reason, profile ([centroid with height, gradient]), area_m2, max_cut_m, grade}.
func check_area(def: StructureDef, poly3: PackedVector3Array, clear_trees := true) -> Dictionary:
	var out := {"ok": false, "reason": "", "profile": PackedVector3Array(), "area_m2": 0.0, "max_cut_m": 0.0, "grade": 0.0}
	if poly3.size() < 3:
		out.reason = "click at least three corners"
		return out
	var poly := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in poly3:
		poly.append(Vector2(p.x, p.z))
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	if Geometry2D.triangulate_polygon(poly).is_empty():
		out.reason = "the outline crosses itself"
		return out
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	area = absf(area) * 0.5
	out.area_m2 = snappedf(area, 0.1)
	if area < 16.0:
		out.reason = "too small"
		return out
	if area > max_area_m2:
		out.reason = "too large (%.0f m² > %.0f m²)" % [area, max_area_m2]
		return out
	# Ground samples every 2 m inside: least-squares plane, gradient limited to max_grade.
	var samples := []
	var step := 2.0
	var y := lo.y
	while y <= hi.y:
		var x := lo.x
		while x <= hi.x:
			var q := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(q, poly):
				var h := _height(x, y)
				if is_nan(h):
					out.reason = "outside the terrain"
					return out
				if _wet(x, y, h):
					out.reason = "water"
					return out
				samples.append(Vector3(x, h, y))
			x += step
		y += step
	for p in poly3:
		samples.append(Vector3(p.x, _height(p.x, p.z), p.z))
	var c := Vector3.ZERO
	for p: Vector3 in samples:
		c += p
	c /= samples.size()
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxh := 0.0
	var szh := 0.0
	for p: Vector3 in samples:
		var dx := p.x - c.x
		var dz := p.z - c.z
		var dh := p.y - c.y
		sxx += dx * dx
		szz += dz * dz
		sxz += dx * dz
		sxh += dx * dh
		szh += dz * dh
	var det := sxx * szz - sxz * sxz
	var g := Vector2.ZERO
	if absf(det) > 1e-6:
		g = Vector2((sxh * szz - szh * sxz) / det, (szh * sxx - sxh * sxz) / det)
	if g.length() > def.max_grade:
		g = g.normalized() * def.max_grade
	var max_cut := 0.0
	for p: Vector3 in samples:
		max_cut = maxf(max_cut, absf(c.y + g.x * (p.x - c.x) + g.y * (p.z - c.z) - p.y))
	out.max_cut_m = snappedf(max_cut, 0.01)
	out.grade = snappedf(g.length(), 0.001)
	out.profile = PackedVector3Array([c, Vector3(g.x, 0.0, g.y)])
	var reason := ""
	if not _inside_map(Vector3(lo.x, 0, lo.y), surface_blend) or not _inside_map(Vector3(hi.x, 0, hi.y), surface_blend):
		reason = "outside the map"
	elif max_cut > def.max_cut:
		reason = "too uneven (%.1f m cut / fill > %.1f m)" % [max_cut, def.max_cut]
	if reason == "":
		# Solid vegetation and blocking structures in 6 m tiles over the outline.
		var ty := lo.y
		while ty <= hi.y and reason == "":
			var tx := lo.x
			while tx <= hi.x and reason == "":
				var tc := Vector2(tx + 3.0, ty + 3.0)
				if Geometry2D.is_point_in_polygon(tc, poly) or StrategicRoutes._dist_to_poly(tc, poly) < 3.0:
					reason = _surface_blocked([tc, Vector2.RIGHT, Vector2.DOWN, Vector2(3.0, 3.0)], clear_trees, false)
				tx += 6.0
			ty += 6.0
	out.reason = reason
	out.ok = reason == ""
	return out


## Why a piece of road / area footprint cannot be built ("" = free): blocking structures
## (walls, buildings; gates and other surfaces are fine) and solid vegetation that is not
## cleared. Units are no obstacle: they step aside.
func _surface_blocked(obb: Array, clear_trees: bool, structures_block := true) -> String:
	var c: Vector2 = obb[0]
	var reach: float = (obb[3] as Vector2).length()
	if structures_block:
		for cell in _cells_around(c, reach + MAX_REACH):
			for e: Vector2i in _index.get(cell, []):
				var s: StructureState = state.get_structure(e.x)
				if s == null or (s.is_line() and s.is_removed(e.y)):
					continue
				var odef := StructureCatalog.get_def(s.type_id)
				if not odef.blocks_navigation:
					continue
				var o := s.instances[e.y].origin
				if Vector2(o.x - c.x, o.z - c.y).length() > reach + MAX_REACH:
					continue
				if _obb_overlap(obb, _obb(odef, s.instances[e.y])):
					return "blocked by %s" % odef.display_name.to_lower()
	if vegetation and vegetation.library:
		var cs: float = vegetation.cell_size_m
		var r := reach + 3.0
		var c0 := VegetationChunk.cell_of(Vector3(c.x - r, 0, c.y - r), cs)
		var c1 := VegetationChunk.cell_of(Vector3(c.x + r, 0, c.y + r), cs)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				for t: Array in _trees_in(Vector2i(cx, cz)):
					var tp := Vector2(t[0], t[1])
					if tp.distance_to(c) > r + t[2]:
						continue
					if clear_trees and clearable_ids.has(t[3]):
						continue
					if _obb_circle(obb, tp, t[2] + tree_margin):
						return "blocked by %s" % _obstacle_name(t[3])
	return ""


## Clearing records for a surface: pieces of ~8 m along a road, 8 m tiles over an area,
## each covering the surface plus its blend zone (the grading moves the ground there).
func _surface_clearings(s: StructureState, trees: bool) -> Array:
	var out := []
	var def := StructureCatalog.get_def(s.type_id)
	if def.surface == StructureDef.Surface.ROAD:
		var pts := s.profile
		var half := def.surface_width * 0.5 + minf(surface_blend, 3.0)
		var i := 0
		while i < pts.size() - 1:
			var j := mini(i + 4, pts.size() - 1)
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[j].x, pts[j].z)
			var mid := (a + b) * 0.5
			var ang := (b - a).angle()
			out.append({"c": [snappedf(mid.x, 0.01), snappedf(mid.y, 0.01)], "yaw": snappedf(ang, 0.0001),
				"h": [snappedf(a.distance_to(b) * 0.5 + 0.5, 0.01), snappedf(half, 0.01)], "trees": trees})
			i = j
	else:
		var poly := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in s.points:
			poly.append(Vector2(p.x, p.z))
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
		var y := lo.y - 2.0
		while y <= hi.y + 2.0:
			var x := lo.x - 2.0
			while x <= hi.x + 2.0:
				var q := Vector2(x + 4.0, y + 4.0)
				if Geometry2D.is_point_in_polygon(q, poly) or StrategicRoutes._dist_to_poly(q, poly) < 6.0:
					out.append({"c": [snappedf(q.x, 0.01), snappedf(q.y, 0.01)], "yaw": 0.0, "h": [4.2, 4.2], "trees": trees})
				x += 8.0
			y += 8.0
	return out


## The surface under a ground point: a road within its half width (+1 m) or an area
## containing it. Returns the structure id or -1.
func pick_surface(p: Vector3) -> int:
	if not p.is_finite():
		return -1
	var q := Vector2(p.x, p.z)
	var best := -1
	var best_d := INF
	for s: StructureState in _surfaces.values():
		var def := StructureCatalog.get_def(s.type_id)
		if def.surface == StructureDef.Surface.ROAD:
			for i in s.profile.size() - 1:
				var a := Vector2(s.profile[i].x, s.profile[i].z)
				var b := Vector2(s.profile[i + 1].x, s.profile[i + 1].z)
				var d := LineOfFire._point_segment_dist2d(q, a, b)
				if d <= def.surface_width * 0.5 + 1.0 and d < best_d:
					best_d = d
					best = s.id
		else:
			var poly := PackedVector2Array()
			for v in s.points:
				poly.append(Vector2(v.x, v.z))
			if Geometry2D.is_point_in_polygon(q, poly) and best_d > 0.5:
				best_d = 0.5
				best = s.id
	return best


# --- Water ------------------------------------------------------------------------

## Indexes the water surfaces of a world (the reference world's river ribbons and lake
## polygons under its Water node) so placement can reject points under water.
func set_water(root: Node) -> void:
	_water.clear()
	if root == null:
		return
	var tris := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else mi.transform
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
			var tri := [a, b, c]
			for gx in range(floori(lo.x / WATER_CELL), floori(hi.x / WATER_CELL) + 1):
				for gz in range(floori(lo.y / WATER_CELL), floori(hi.y / WATER_CELL) + 1):
					var k := Vector2i(gx, gz)
					if not _water.has(k):
						_water[k] = []
					_water[k].append(tri)
			tris += 1
	print("StructureManager: water index %d triangles in %d cells" % [tris, _water.size()])


## Water surface height at (x, z), or -INF where there is no water.
func water_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	for tri: Array in _water.get(Vector2i(floori(x / WATER_CELL), floori(z / WATER_CELL)), []):
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
			return maxf(a.y, maxf(b.y, c.y))
	return -INF


## LOGISTICS-01: the ground at (x, z) is under water (vehicle routing and driving).
func is_wet(x: float, z: float) -> bool:
	var h := _height(x, z)
	return not is_nan(h) and _wet(x, z, h)


## Terrain height h at (x, z) is below the water level or under a water surface.
func _wet(x: float, z: float, h: float) -> bool:
	return h < water_level or h < water_height(x, z) + 0.15


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
func _blocked(def: StructureDef, obb: Array, ignore_id: int, _ignore_index: int, clear_trees := false) -> String:
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
			var o := s.instances[e.y].origin
			if Vector2(o.x - c.x, o.z - c.y).length() > reach + MAX_REACH:
				continue  # cheap reject before building the oriented box
			var odef := StructureCatalog.get_def(s.type_id)
			var same := def.connect_group != &"" and odef.connect_group == def.connect_group
			var other := _obb(odef, s.instances[e.y], 0.2 if same else 0.0)
			var mine := obb
			if same:
				mine = [obb[0], obb[1], obb[2], Vector2(maxf(obb[3].x - 0.2, 0.05), maxf(obb[3].y - 0.2, 0.05))]
			if _obb_overlap(mine, other):
				return "blocked by %s" % odef.display_name.to_lower()
	# Tree trunks, rocks and settlement buildings (vegetation instances with a collider).
	if vegetation and vegetation.library:
		var cs: float = vegetation.cell_size_m
		var r := reach + 3.0
		var c0 := VegetationChunk.cell_of(Vector3(c.x - r, 0, c.y - r), cs)
		var c1 := VegetationChunk.cell_of(Vector3(c.x + r, 0, c.y + r), cs)
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				for t: Array in _trees_in(Vector2i(cx, cz)):
					var tp := Vector2(t[0], t[1])
					if tp.distance_to(c) > r + t[2]:
						continue
					if clear_trees and clearable_ids.has(t[3]) and _obb_circle(obb, tp, _clear_reach(def) - 0.05):
						continue  # trunk inside the cleared area (footprint + margin / groundwork)
					# Groundwork moves the ground under anything standing in its blend zone.
					var keep := maxf(t[2] + tree_margin, level_blend if _levels(def) else 0.0)
					if _obb_circle(obb, tp, keep):
						return "blocked by %s" % _obstacle_name(t[3])
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


## Solid vegetation of one vegetation cell as [x, z, radius, mesh_id], cached until
## clearings change.
func _trees_in(cell: Vector2i) -> Array:
	if _tree_cache.has(cell):
		return _tree_cache[cell]
	# Built here, not on first placement: a lookup before any placement check must not
	# cache empty cells.
	if _tree_radii.is_empty():
		for d in vegetation.library.meshes:
			if d.collider.x >= 0.0:
				_tree_radii[d.id] = maxf(d.collider.y, 0.25)
	var out := []
	for inst in vegetation.get_cell_instances(cell, _tree_radii.keys()):
		var xf: Transform3D = inst[1]
		out.append([xf.origin.x, xf.origin.z, _tree_radii[inst[0]] * xf.basis.get_scale().x, inst[0]])
	_tree_cache[cell] = out
	return out


## True when a circle (XZ) touches a solid vegetation instance: tree trunk, rock or settlement collider. Vehicles use it (the
## router's cross-country legs); the same instances are the physical colliders next to the camera. False without vegetation.
func blocks_trunk(p: Vector2, radius := 0.4) -> bool:
	if vegetation == null or vegetation.library == null:
		return false
	var reach := radius + _trunk_max_r
	var cs: float = vegetation.cell_size_m
	var c0 := VegetationChunk.cell_of(Vector3(p.x - reach, 0.0, p.y - reach), cs)
	var c1 := VegetationChunk.cell_of(Vector3(p.x + reach, 0.0, p.y + reach), cs)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			var sub: Dictionary = _trunk_sub.get(cell, {})
			if sub.is_empty() and not _trunk_sub.has(cell):
				sub = _build_trunk_sub(cell)
			if sub.is_empty():
				continue
			for gx in range(floori((p.x - reach) / TRUNK_SUB), floori((p.x + reach) / TRUNK_SUB) + 1):
				for gz in range(floori((p.y - reach) / TRUNK_SUB), floori((p.y + reach) / TRUNK_SUB) + 1):
					for t: Array in sub.get(Vector2i(gx, gz), []):
						var dx: float = t[0] - p.x
						var dz: float = t[1] - p.y
						var rr: float = t[2] + radius
						if dx * dx + dz * dz < rr * rr:
							return true
	return false


## Appends [x, z, radius] of every solid vegetation instance whose centre lies in `rect` (XZ) to `out` (flat array, 3 per instance).
func trunks_in_rect(rect: Rect2, out: PackedFloat32Array) -> void:
	if vegetation == null or vegetation.library == null:
		return
	var cs: float = vegetation.cell_size_m
	var c0 := VegetationChunk.cell_of(Vector3(rect.position.x - _trunk_max_r, 0.0, rect.position.y - _trunk_max_r), cs)
	var c1 := VegetationChunk.cell_of(Vector3(rect.end.x + _trunk_max_r, 0.0, rect.end.y + _trunk_max_r), cs)
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			var sub: Dictionary = _trunk_sub.get(cell, {})
			if sub.is_empty() and not _trunk_sub.has(cell):
				sub = _build_trunk_sub(cell)
			if sub.is_empty():
				continue
			for gx in range(floori((rect.position.x - _trunk_max_r) / TRUNK_SUB), floori((rect.end.x + _trunk_max_r) / TRUNK_SUB) + 1):
				for gz in range(floori((rect.position.y - _trunk_max_r) / TRUNK_SUB), floori((rect.end.y + _trunk_max_r) / TRUNK_SUB) + 1):
					for t: Array in sub.get(Vector2i(gx, gz), []):
						if t[0] >= rect.position.x - 6.0 and t[0] <= rect.end.x + 6.0 and t[1] >= rect.position.y - 6.0 and t[1] <= rect.end.y + 6.0:
							out.append(t[0])
							out.append(t[1])
							out.append(t[2])


func _build_trunk_sub(cell: Vector2i) -> Dictionary:
	var sub := {}
	for t: Array in _trees_in(cell):
		var k := Vector2i(floori(t[0] / TRUNK_SUB), floori(t[1] / TRUNK_SUB))
		if not sub.has(k):
			sub[k] = []
		sub[k].append(t)
		_trunk_max_r = maxf(_trunk_max_r, t[2])
	_trunk_sub[cell] = sub
	return sub


func _obstacle_name(mesh_id: int) -> String:
	var d := vegetation.library.get_def(mesh_id)
	var n := d.name.to_lower() if d else "vegetation"
	if clearable_ids.has(mesh_id):
		return "a tree (%s; C turns clearing on)" % n
	return "a %s" % n


# --- Vegetation clearing ----------------------------------------------------------

## Clearing records for the built footprints of a structure: the oriented footprint plus
## clear_margin. trees: also remove trees (the clearing toggle); undergrowth always goes.
func clearings_for(s: StructureState, trees: bool) -> Array:
	var out := []
	var def := StructureCatalog.get_def(s.type_id)
	if def == null:
		return out
	if def.is_surface():
		return _surface_clearings(s, trees)
	for i in s.instances.size():
		if s.is_line() and s.is_removed(i):
			continue
		var obb := _obb(def, s.instances[i])
		var ax: Vector2 = obb[1]
		var m := _clear_reach(def)
		var half: Vector2 = obb[3] + Vector2(m, m)
		var oc: Vector2 = obb[0]
		out.append({"c": [snappedf(oc.x, 0.01), snappedf(oc.y, 0.01)], "yaw": snappedf(atan2(ax.y, ax.x), 0.0001),
			"h": [snappedf(half.x, 0.01), snappedf(half.y, 0.01)], "trees": trees})
	return out


## Pushes the state's clearings to the vegetation streamer (which filters rendering,
## colliders and navigation obstructions) and drops the cached trunks. NAVIGATION N1-C1: only the vegetation cells whose clearings
## changed lose their cached trunks (the streamer reports them), not the whole world - the first route after a placement used to
## rebuild every cell it touched (50-300 ms). `full`: the state was bound or replaced, everything goes.
func _apply_clearings(full := false) -> void:
	if full or vegetation == null or state == null:
		_tree_cache.clear()
		_trunk_sub.clear()
	if vegetation == null or state == null:
		return
	if not vegetation.clearings_changed.is_connected(_on_vegetation_cells_changed):
		vegetation.clearings_changed.connect(_on_vegetation_cells_changed)
	var all_ids := {}
	for id in clearable_ids:
		all_ids[id] = true
	var under := {}
	for id in undergrowth_ids:
		under[id] = true
	var list := []
	for r: Dictionary in state.clearings:
		var a: float = r.get("yaw", 0.0)
		var ax := Vector2(cos(a), sin(a))
		list.append([Vector2(r.c[0], r.c[1]), ax, Vector2(-ax.y, ax.x), Vector2(r.h[0], r.h[1]),
			all_ids if r.get("trees", true) else under])
	vegetation.set_clearings(list)


## The streamer changed the clearings of these vegetation cells: their cached solid instances are stale, all others stay valid.
func _on_vegetation_cells_changed(cells: Array) -> void:
	for c in cells:
		_tree_cache.erase(c)
		_trunk_sub.erase(c)


# --- Abstract tier ----------------------------------------------------------------

## True if a soldier-sized circle at p (XZ) overlaps a navigation-blocking structure
## (walls, HESCO, fences, building walls; gates and ramps stay passable). Used by the
## abstract tier, which has no physics, so units do not walk through bases.
## WORLD-PLAYTEST-01: the footprints are kept in a fine grid (BLOCK_CELL) built once per
## change, so a test touches the few boxes near p; scanning every module of a 128 m cell
## (a base perimeter has hundreds) cost 6-7 ms per simulation tick with units moving
## inside a base and capped time compression. Same boxes, same answer.
func blocks_point(p: Vector2, radius := 0.4) -> bool:
	if _block_dirty:
		_rebuild_block_grid()
	for gx in range(floori((p.x - radius) / BLOCK_CELL), floori((p.x + radius) / BLOCK_CELL) + 1):
		for gz in range(floori((p.y - radius) / BLOCK_CELL), floori((p.y + radius) / BLOCK_CELL) + 1):
			for obb: Array in _block_grid.get(Vector2i(gx, gz), []):
				if _obb_circle(obb, p, radius):
					return true
	return false


## The blocking boxes ([centre, axis x, axis z, half size]) that a circle touches: what blocks_point found (diagnostics).
func blocking_boxes(p: Vector2, radius := 0.4) -> Array:
	if _block_dirty:
		_rebuild_block_grid()
	var out: Array = []
	for gx in range(floori((p.x - radius) / BLOCK_CELL), floori((p.x + radius) / BLOCK_CELL) + 1):
		for gz in range(floori((p.y - radius) / BLOCK_CELL), floori((p.y + radius) / BLOCK_CELL) + 1):
			for obb: Array in _block_grid.get(Vector2i(gx, gz), []):
				if _obb_circle(obb, p, radius) and not out.has(obb):
					out.append(obb)
	return out


func _rebuild_block_grid() -> void:
	_block_dirty = false
	_block_grid.clear()
	_block_of.clear()
	if state == null:
		return
	for s: StructureState in state.structures.values():
		_block_add(s)


## The structure's footprints put into the fine grid (and remembered in _block_of).
func _block_add(s: StructureState) -> void:
	var def := StructureCatalog.get_def(s.type_id)
	if def == null or not def.blocks_navigation or def.is_surface():
		return
	var entries := []
	for i in s.instances.size():
		if s.is_line() and s.is_removed(i):
			continue
		var xf := s.instances[i]
		var ax := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
		var az := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
		for box in def.get_collision_boxes():
			if box.position.y > 1.0:
				continue
			var bc := box.get_center()
			var w := xf * Vector3(bc.x, 0.0, bc.z)
			var half := Vector2(box.size.x, box.size.z) * 0.5
			if def.linear:
				half.x = def.module_length * 0.5
			var obb := [Vector2(w.x, w.z), ax, az, half]
			var r := half.length()
			var cells: Array[Vector2i] = []
			for gx in range(floori((w.x - r) / BLOCK_CELL), floori((w.x + r) / BLOCK_CELL) + 1):
				for gz in range(floori((w.z - r) / BLOCK_CELL), floori((w.z + r) / BLOCK_CELL) + 1):
					var k := Vector2i(gx, gz)
					if not _block_grid.has(k):
						_block_grid[k] = []
					_block_grid[k].append(obb)
					cells.append(k)
			entries.append([obb, cells])
	if not entries.is_empty():
		_block_of[s.id] = entries


## Takes a structure's footprints out of the fine grid.
func _block_forget(sid: int) -> void:
	if _block_dirty:
		return
	for e: Array in _block_of.get(sid, []):
		for k: Vector2i in e[1]:
			var list: Array = _block_grid.get(k, [])
			list.erase(e[0])
			if list.is_empty():
				_block_grid.erase(k)
	_block_of.erase(sid)


## The structure was added or changed: its footprints are replaced in the fine grid (nothing to do while the grid is still
## to be built in full).
func _block_update(s: StructureState) -> void:
	if _block_dirty:
		return
	_block_forget(s.id)
	_block_add(s)


## True when any blocking footprint touches rect (XZ): a route planner then skips the per-cell footprint tests of its whole grid.
func blocks_in_rect(rect: Rect2) -> bool:
	if _block_dirty:
		_rebuild_block_grid()
	for gx in range(floori(rect.position.x / BLOCK_CELL), floori(rect.end.x / BLOCK_CELL) + 1):
		for gz in range(floori(rect.position.y / BLOCK_CELL), floori(rect.end.y / BLOCK_CELL) + 1):
			if _block_grid.has(Vector2i(gx, gz)):
				return true
	return false


## The highest water surface that can lie in rect (XZ): water_level or the top of the water triangles of the cells it touches.
## Ground more than a metre above it is dry, which is all a planner needs to skip the exact test.
func water_top_in_rect(rect: Rect2) -> float:
	var top := water_level
	for gx in range(floori(rect.position.x / WATER_CELL), floori(rect.end.x / WATER_CELL) + 1):
		for gz in range(floori(rect.position.y / WATER_CELL), floori(rect.end.y / WATER_CELL) + 1):
			for tri: Array in _water.get(Vector2i(gx, gz), []):
				top = maxf(top, maxf(tri[0].y, maxf(tri[1].y, tri[2].y)))
	return top
