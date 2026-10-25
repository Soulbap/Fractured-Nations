## GAMEPLAY-04A road shoulders: the terrain beside every world road is eased into the road surface in memory at game start,
## like the settlement layer's heights (never saved; the world files and their manifest are untouched).
##
## Why: the generated terrain leaves ditches up to ~1 m deep, 40-45 degree banks and a lip of 0.25-0.7 m between the terrain
## and the road surface. The navmesh (baked from the terrain) and the abstract tier walk soldiers straight over them while the
## bodies stand against the edge; next to the New Game start soldiers stopped at the road for the rest of their order.
##
## What: a band beside the road edge becomes an even ramp from the road surface to the original terrain at the band's outer
## edge (ditches filled, banks laid back); the band is SHOULDER_M wide, wider (up to SHOULDER_MAX_M) where the height to
## bridge is large, so the ramp stays near SLOPE; under the road surface itself the terrain lies UNDER_M below it (no lip). Bridge spans and their approaches are left alone. Every reader of the
## terrain - collision, AreaNavigation, StrategicRoutes, the abstract tier - sees the eased ground, so the tiers agree.
## The heights are computed once per world and road set and cached in user:// (RoadShoulders.CACHE).
class_name RoadShoulders
extends RefCounted

const SHOULDER_M := 7.0
const SHOULDER_MAX_M := 14.0
const SLOPE := 0.3
const UNDER_M := 0.08
const MIN_CHANGE_M := 0.03
## GAMEPLAY-05B: the road meshes (RoadManager) are wider than RoadNetwork's width - measured 1.9-2.0 m more on each side of the
## secondary roads - and fall ~0.28 m towards their edge. The ramp began at RoadNetwork's edge, so the terrain dropped away under
## the outer two metres of the mesh and its edge stood a median 0.46 m (up to 1.1 m) above the ground: soldiers in the ditch
## stood against it (navinf_04, the player's squads beside cut roads). The terrain now follows the mesh's cross-fall out to its
## edge and the ramp starts there.
const MESH_EDGE_M := 2.0
const MESH_EDGE_DROP_M := 0.28
const BRIDGE_SKIP_M := 15.0
const CACHE := "user://terrain/%s_road_shoulders_%s.bin"
## Vegetation cells (VegetationChunk cell size) whose ground was eased, and the terrain: instances there are put back on the
## ground when their chunk loads (fix_chunk).
const VEG_CELL_M := 128.0
static var touched := {}
static var _terrain: Terrain3D


## Applies the eased heights to the terrain (computing them on the first run). Returns {vertices, ms, cached}.
static func apply(terrain: Terrain3D, roads: RoadNetwork, world: String, spacing: float) -> Dictionary:
	if terrain == null or terrain.data == null or roads == null:
		return {}
	var t0 := Time.get_ticks_msec()
	var sig := _signature(roads, spacing)
	var path := CACHE % [world, sig]
	var keys := PackedVector2Array()
	var heights := PackedFloat32Array()
	var cached := false
	if FileAccess.file_exists(path):
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f:
			var n := f.get_32()
			keys = bytes_to_var(f.get_buffer(f.get_32())) as PackedVector2Array
			heights = bytes_to_var(f.get_buffer(f.get_32())) as PackedFloat32Array
			f.close()
			cached = keys.size() == n and heights.size() == n
	if not cached:
		var res := compute(terrain, roads, spacing)
		keys = res.keys
		heights = res.heights
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if f:
			var kb := var_to_bytes(keys)
			var hb := var_to_bytes(heights)
			f.store_32(keys.size())
			f.store_32(kb.size())
			f.store_buffer(kb)
			f.store_32(hb.size())
			f.store_buffer(hb)
			f.close()
	var regions := {}
	touched.clear()
	_terrain = terrain
	for i in keys.size():
		var p := Vector3(keys[i].x, 0.0, keys[i].y)
		terrain.data.set_height(p, heights[i])
		regions[terrain.data.get_region_location(p)] = true
		touched[Vector2i(floori(p.x / VEG_CELL_M), floori(p.z / VEG_CELL_M))] = true
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, false, false)
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(false)
	var out := {"vertices": keys.size(), "ms": Time.get_ticks_msec() - t0, "cached": cached}
	print("RoadShoulders: ", out)
	return out


## Puts the vegetation of the eased cells back on the ground: every instance there was generated on the terrain with an offset
## of 0 to -0.15 m (ReferenceWorldBuilder); it keeps that offset on the eased ground. Chunks are fixed in memory when they
## load (VegetationStreamer._store_chunk); already loaded ones by refix_loaded. Returns the instances moved.
static func fix_chunk(ch: VegetationChunk) -> int:
	if touched.is_empty() or _terrain == null or ch == null:
		return 0
	var moved := 0
	var fpi := VegetationChunk.FLOATS_PER_INSTANCE
	for cell in ch.cells:
		if not touched.has(cell):
			continue
		var by_mesh: Dictionary = ch.cells[cell]
		for mesh_id in by_mesh:
			var buf: PackedFloat32Array = by_mesh[mesh_id]
			var changed := false
			for i in buf.size() / fpi:
				var k := i * fpi
				var h: float = _terrain.data.get_height(Vector3(buf[k + 3], 0.0, buf[k + 11]))
				if is_nan(h):
					continue
				var off := buf[k + 7] - h
				if off > 0.02 or off < -0.2:
					buf[k + 7] = h + clampf(off, -0.15, 0.0)
					changed = true
					moved += 1
			if changed:
				by_mesh[mesh_id] = buf
	return moved


## The chunks loaded before the shoulders were applied: fixed, and their cells drawn again.
static func refix_loaded(veg: VegetationStreamer) -> int:
	if veg == null:
		return 0
	var moved := 0
	for loc in veg.chunks:
		moved += fix_chunk(veg.chunks[loc])
	if moved > 0:
		veg.overrides_changed(touched.keys())
	return moved


## The eased heights of every terrain vertex near a world road: {keys: PackedVector2Array (x, z), heights}.
static func compute(terrain: Terrain3D, roads: RoadNetwork, spacing: float) -> Dictionary:
	var keys := PackedVector2Array()
	var heights := PackedFloat32Array()
	var seen := {}
	for r: RoadNetwork.Road in roads.world:
		var pts := r.points
		if pts.size() < 2:
			continue
		var hw := r.width * 0.5
		var hw_mesh := hw + MESH_EDGE_M
		var reach := hw_mesh + SHOULDER_MAX_M
		for i in pts.size() - 1:
			if _near_bridge(r, pts, i):
				continue
			var a := pts[i]
			var b := pts[i + 1]
			var a2 := Vector2(a.x, a.z)
			var b2 := Vector2(b.x, b.z)
			var lo := a2.min(b2) - Vector2(reach, reach)
			var hi := a2.max(b2) + Vector2(reach, reach)
			for gx in range(ceili(lo.x / spacing), floori(hi.x / spacing) + 1):
				for gz in range(ceili(lo.y / spacing), floori(hi.y / spacing) + 1):
					var q := Vector2(gx * spacing, gz * spacing)
					var ab := b2 - a2
					var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var d := q.distance_to(a2 + ab * t)
					if d > reach:
						continue
					# The nearest segment of this road decides (bends are covered by two segments).
					if i > 0 and _seg_dist(q, pts[i - 1], pts[i]) < d - 0.01:
						continue
					if i + 2 < pts.size() and _seg_dist(q, pts[i + 1], pts[i + 2]) < d - 0.01:
						continue
					var key := Vector2i(gx, gz)
					if seen.has(key):
						continue
					var p := Vector3(q.x, 0.0, q.y)
					var h: float = terrain.data.get_height(p)
					if is_nan(h):
						continue
					var road_y := lerpf(a.y, b.y, t)
					var nh := road_y - UNDER_M
					var edge_y := road_y - UNDER_M - MESH_EDGE_DROP_M
					if d > hw and d <= hw_mesh:
						# Under the mesh's shoulder: its cross-fall.
						nh = lerpf(road_y - UNDER_M, edge_y, (d - hw) / MESH_EDGE_M)
					elif d > hw_mesh:
						# The ramp across the band, along the perpendicular through this vertex, ends on the original terrain.
						var foot := a2 + ab * t
						var nrm := (q - foot) / d
						var outer: float = terrain.data.get_height(Vector3(foot.x + nrm.x * (hw_mesh + SHOULDER_M), 0.0, foot.y + nrm.y * (hw_mesh + SHOULDER_M)))
						var band := SHOULDER_M
						if not is_nan(outer):
							band = clampf(absf(outer - edge_y) / SLOPE, SHOULDER_M, SHOULDER_MAX_M)
							outer = terrain.data.get_height(Vector3(foot.x + nrm.x * (hw_mesh + band), 0.0, foot.y + nrm.y * (hw_mesh + band)))
						var e := d - hw_mesh
						if is_nan(outer) or e >= band:
							continue
						var u := e / band
						nh = lerpf(edge_y, outer, lerpf(u, smoothstep(0.0, 1.0, u), 0.5))
					if absf(nh - h) < MIN_CHANGE_M:
						continue
					seen[key] = true
					keys.append(q)
					heights.append(nh)
	return {"keys": keys, "heights": heights}


static func _seg_dist(q: Vector2, a: Vector3, b: Vector3) -> float:
	var a2 := Vector2(a.x, a.z)
	var ab := Vector2(b.x, b.z) - a2
	var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return q.distance_to(a2 + ab * t)


## True when segment i lies on a bridge span or within BRIDGE_SKIP_M of one (decks and their ramps keep their own ground).
static func _near_bridge(r: RoadNetwork.Road, pts: PackedVector3Array, i: int) -> bool:
	for span: Array in r.bridges:
		var first := int(span[0])
		var last := int(span[1])
		if i + 1 >= first and i <= last:
			return true
		var p := Vector2(pts[i].x, pts[i].z)
		if p.distance_to(Vector2(pts[first].x, pts[first].z)) < BRIDGE_SKIP_M or p.distance_to(Vector2(pts[last].x, pts[last].z)) < BRIDGE_SKIP_M:
			return true
	return false


## A short signature of the road set and the rules (the cache is rebuilt when either changes).
static func _signature(roads: RoadNetwork, spacing: float) -> String:
	var h := hash([SHOULDER_M, SHOULDER_MAX_M, SLOPE, UNDER_M, MIN_CHANGE_M, BRIDGE_SKIP_M, MESH_EDGE_M, MESH_EDGE_DROP_M, spacing, roads.world.size()])
	for r: RoadNetwork.Road in roads.world:
		if r.points.size() > 0:
			h = hash([h, r.points.size(), r.points[0], r.points[r.points.size() - 1], r.width])
	return "%08x" % (h & 0xffffffff)
