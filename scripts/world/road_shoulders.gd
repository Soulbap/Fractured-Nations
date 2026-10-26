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
##
## ROAD-QUALITY-01: the paved roads are fitted to their Road Generator collider, not to RoadNetwork's line: the mesh is 2 m wider on
## each side (its gutter), stands 0.2 m above the line and leaves it in bends and at junctions, so the terrain eased to the line
## left the mesh edge hanging up to 1-4 m over the ground (worst beside junction surfaces and where two roads run side by side).
## Rays measure the edge every STATION_M; under the collider the terrain lies just below it, beyond the edge a short landing keeps
## the 1.95 m vertex grid from sagging under the edge, between two roads the terrain runs from edge to edge. Natural banks beyond
## the band stay as they are (steep cuts and fills are obstacles, not defects). Tracks and streets keep the GAMEPLAY-04A rule.
class_name RoadShoulders
extends RefCounted

const SHOULDER_M := 7.0
const SHOULDER_MAX_M := 14.0
const SLOPE := 0.3
const UNDER_M := 0.08
const MIN_CHANGE_M := 0.03
## GAMEPLAY-05B: the road meshes (Road Generator) are wider than RoadNetwork's width: its default gutter adds 2 m on each side,
## falling 0.5 m. ROAD-QUALITY-01: only the fallback where the collider cannot be measured (no physics space).
const MESH_EDGE_M := 2.0
const MESH_EDGE_DROP_M := 0.28
## ROAD-QUALITY-01: meshed roads are fitted to their collider. Stations along the centre line where the edge is measured; how far
## a junction surface is searched; the terrain under the carriageway (0.28 m below the mesh = 0.08 m below RoadNetwork's line,
## as before) and at the edge; beyond the edge at most LANDING_GRADE for LANDING_M; culvert channels kept within CULVERT_KEEP_M.
const STATION_M := 2.0
const EDGE_SEARCH_M := 24.0
const BURY_IN := 0.28
const BURY_EDGE := 0.04
const LANDING_M := 3.0
const LANDING_GRADE := 0.35
const CULVERT_KEEP_M := 8.0
## Vegetation instances standing on a vertex under a road collider are put this far below the ground (under the asphalt).
const UNDER_ROAD_SINK_M := 1.5
## The grass mask covers vertices at least 1 m inside the edge (their bury); nearer the edge the 2 m mask texels would clear a
## strip of the verge beside the road too.
const BURY_INNER_GRASS := 0.16
const BRIDGE_SKIP_M := 15.0
const CACHE := "user://terrain/%s_road_shoulders_%s.bin"
## ROAD-QUALITY-01: version of the cache layout (keys, heights, under-road flags) and of compute(); raise it when either changes.
const CACHE_VERSION := 7
## Vegetation cells (VegetationChunk cell size) whose ground was eased, and the terrain: instances there are put back on the
## ground when their chunk loads (fix_chunk).
const VEG_CELL_M := 128.0
static var touched := {}
## ROAD-QUALITY-01: terrain vertices under a road collider; true at least 1 m inside its edge, where plants are kept below the road
## surface and the grass is masked (nearer the edge the verge keeps its plants).
static var under_road := {}
static var _terrain: Terrain3D
static var _spacing := 1.0
## WORLD-COVER-01.1: the eased vertices (x, z) of the last apply, kept only while TerrainRelief builds (its features keep clear).
static var kept_keys := PackedVector2Array()


## Applies the eased heights to the terrain (computing them on the first run). road_root: the node holding the Road Generator
## roads (their colliders are measured; null: the mesh model). Returns {vertices, ms, cached, signature, stats}.
static func apply(terrain: Terrain3D, roads: RoadNetwork, world: String, spacing: float, road_root: Node = null) -> Dictionary:
	if terrain == null or terrain.data == null or roads == null:
		return {}
	var t0 := Time.get_ticks_msec()
	var meshes := _road_meshes(road_root)
	var sig := _signature(roads, spacing, meshes)
	var path := CACHE % [world, sig]
	var keys := PackedVector2Array()
	var heights := PackedFloat32Array()
	var under := PackedByteArray()
	var cached := false
	if FileAccess.file_exists(path):
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f:
			var n := f.get_32()
			keys = bytes_to_var(f.get_buffer(f.get_32())) as PackedVector2Array
			heights = bytes_to_var(f.get_buffer(f.get_32())) as PackedFloat32Array
			under = bytes_to_var(f.get_buffer(f.get_32())) as PackedByteArray
			f.close()
			cached = keys.size() == n and heights.size() == n and under.size() == n
	var stats := {}
	if not cached:
		var space: PhysicsDirectSpaceState3D = null
		if not meshes.is_empty() and terrain.is_inside_tree():
			space = terrain.get_world_3d().direct_space_state
		var res := compute(terrain, roads, spacing, space)
		stats = res.stats
		keys = res.keys
		heights = res.heights
		under = res.under
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
			var ub := var_to_bytes(under)
			f.store_32(ub.size())
			f.store_buffer(ub)
			f.close()
	var regions := {}
	touched.clear()
	under_road.clear()
	_terrain = terrain
	_spacing = spacing
	if "--build-terrain-relief" in OS.get_cmdline_user_args():
		kept_keys = keys
	for i in keys.size():
		var p := Vector3(keys[i].x, 0.0, keys[i].y)
		terrain.data.set_height(p, heights[i])
		if under[i] > 0:
			under_road[Vector2i(roundi(p.x / spacing), roundi(p.z / spacing))] = under[i] == 2
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
	var out := {"vertices": keys.size(), "ms": Time.get_ticks_msec() - t0, "cached": cached, "signature": sig, "meshes": meshes.size(), "stats": stats}
	print("RoadShoulders: ", out)
	return out


## ROAD-QUALITY-01: the grass layer's exclusion mask is painted from RoadNetwork's widths, narrower than the road meshes (gutters,
## junction surfaces); with the ground now just below the surface the grass there grew through the asphalt. The texels under a
## road collider are excluded too (in memory, before StructureManager copies the mask). Returns the texels painted.
static func mask_grass(grass: GrassLayer) -> int:
	if grass == null or grass.mask == null or grass.mask.image == null or under_road.is_empty():
		return 0
	var mask := grass.mask
	var img := mask.image
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	for key: Vector2i in under_road:
		if not under_road[key]:
			continue
		var px := int((key.x * _spacing - mask.origin.x) / mask.texel_m)
		var pz := int((key.y * _spacing - mask.origin.y) / mask.texel_m)
		if px < 0 or pz < 0 or px >= w or pz >= h or img.get_pixel(px, pz).r >= 0.99:
			continue
		img.set_pixel(px, pz, Color(1, 1, 1))
		n += 1
	grass.apply_mask()
	return n


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
				if under_road.get(Vector2i(roundi(buf[k + 3] / _spacing), roundi(buf[k + 11] / _spacing)), false):
					# Under a road surface the ground lies just below the mesh now: keep the plant under the asphalt as before.
					if off > -UNDER_ROAD_SINK_M + 0.01:
						buf[k + 7] = h - UNDER_ROAD_SINK_M
						changed = true
						moved += 1
				elif off > 0.02 or off < -0.2:
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


## The eased heights of every terrain vertex near a world road: {keys: PackedVector2Array (x, z), heights, stats}.
## ROAD-QUALITY-01: roads with a mesh are fitted to their collider (space: the physics space holding it), found by rays: where its
## edge is, how high, and its surface over each vertex under it. Without a space (tools) they fall back to the mesh model.
static func compute(terrain: Terrain3D, roads: RoadNetwork, spacing: float, space: PhysicsDirectSpaceState3D = null) -> Dictionary:
	var c := Candidates.new()
	var stats := {"stations": 0, "edges": 0, "no_edge": 0, "rays": 0, "inside": 0, "landing": 0, "culvert_kept": 0, "blended": 0}
	for ri in roads.world.size():
		var r: RoadNetwork.Road = roads.world[ri]
		if r.points.size() < 2:
			continue
		if r.mesh:
			_fit_mesh_road(terrain, roads, r, ri, spacing, space, c, stats)
		else:
			_fit_plain_road(terrain, r, ri, spacing, c)
	var keys := PackedVector2Array()
	var heights := PackedFloat32Array()
	var under := PackedByteArray()
	for key: Vector2i in c.idx:
		var i: int = c.idx[key]
		var nh := c.h1[i]
		# Beside two roads (parallel or converging at different heights): the terrain runs straight from one edge to the other
		# (each vertex given to its nearer road left a step at the farther one, every other vertex a different road).
		# Within LANDING_M of the higher road's edge its landing is kept, so that edge never hangs over the slope; the lower road's
		# edge is covered by the bank instead (where the two edges are close and far apart in height the bank is steep: natural).
		if c.r2[i] >= 0 and c.s1[i] >= 0.0 and c.s2[i] < 1000.0:
			var ws := c.s1[i] + c.s2[i]
			nh = (c.h1[i] + c.h2[i]) * 0.5 if ws < 0.01 else (c.h1[i] * c.s2[i] + c.h2[i] * c.s1[i]) / ws
			if c.s1[i] <= LANDING_M:
				nh = maxf(nh, c.h1[i])
			if c.s2[i] <= LANDING_M:
				nh = maxf(nh, c.h2[i])
			stats.blended += 1
		var q := Vector2(key.x * spacing, key.y * spacing)
		var h: float = terrain.data.get_height(Vector3(q.x, 0.0, q.y))
		if is_nan(h) or absf(nh - h) < MIN_CHANGE_M:
			continue
		keys.append(q)
		heights.append(nh)
		# 1: under a road collider; 2: at least 1 m inside its edge (bury >= BURY_INNER_GRASS; the grass is masked there).
		under.append(0 if c.s1[i] >= 0.0 else (2 if c.s1[i] <= -10.0 - BURY_INNER_GRASS else 1))
	return {"keys": keys, "heights": heights, "under": under, "stats": stats}


## Per vertex the best height offered by each of the two nearest roads (score: lower is better; under a road surface < 0, beside
## a meshed road the distance from its edge, beside a plain road 1000 + distance).
class Candidates:
	var idx := {}
	var h1 := PackedFloat32Array()
	var s1 := PackedFloat32Array()
	var r1 := PackedInt32Array()
	var h2 := PackedFloat32Array()
	var s2 := PackedFloat32Array()
	var r2 := PackedInt32Array()

	func offer(key: Vector2i, h: float, score: float, road: int) -> void:
		var i: int = idx.get(key, -1)
		if i < 0:
			idx[key] = h1.size()
			h1.append(h)
			s1.append(score)
			r1.append(road)
			h2.append(0.0)
			s2.append(INF)
			r2.append(-1)
			return
		if road == r1[i]:
			if score < s1[i]:
				h1[i] = h
				s1[i] = score
			return
		if score < s1[i]:
			if score < 0.0 or s1[i] < 0.0:
				r2[i] = -1
			else:
				h2[i] = h1[i]
				s2[i] = s1[i]
				r2[i] = r1[i]
			h1[i] = h
			s1[i] = score
			r1[i] = road
		elif s1[i] >= 0.0 and score >= 0.0 and score < s2[i]:
			h2[i] = h
			s2[i] = score
			r2[i] = road


## GAMEPLAY-04A rule for roads without a mesh (tracks, local roads, settlement streets): the surface is RoadNetwork's line and
## width; the terrain lies UNDER_M below it and an even ramp beyond the edge meets the original terrain.
static func _fit_plain_road(terrain: Terrain3D, r: RoadNetwork.Road, ri: int, spacing: float, c: Candidates) -> void:
	var pts := r.points
	var hw := r.width * 0.5
	var reach := hw + SHOULDER_MAX_M
	for i in pts.size() - 1:
		if _near_bridge(r, pts, i):
			continue
		var a := pts[i]
		var b := pts[i + 1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var lo := a2.min(a2 + ab) - Vector2(reach, reach)
		var hi := a2.max(a2 + ab) + Vector2(reach, reach)
		for gx in range(ceili(lo.x / spacing), floori(hi.x / spacing) + 1):
			for gz in range(ceili(lo.y / spacing), floori(hi.y / spacing) + 1):
				var q := Vector2(gx * spacing, gz * spacing)
				var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := q.distance_to(a2 + ab * t)
				if d > reach or _not_nearest(q, d, pts, i):
					continue
				var road_y := lerpf(a.y, b.y, t)
				var nh := road_y - UNDER_M
				if d > hw:
					var foot := a2 + ab * t
					nh = _ramp(terrain, foot, (q - foot) / d, hw, d - hw, road_y - UNDER_M, 0.0)
					if is_nan(nh):
						continue
				c.offer(Vector2i(gx, gz), nh, 1000.0 + maxf(d - hw, 0.0), ri)


## A road with a Road Generator mesh, fitted to its collider. Its centre line is RoadNetwork's; every STATION_M along it rays find
## the collider's edge on both sides (the mesh is wider than RoadNetwork's width by the gutter and does not follow the line
## exactly in bends and at junctions). A vertex under the collider lies just below its surface, BURY_IN under the carriageway and
## BURY_EDGE at the edge, so the edge meets the ground; beyond the edge the terrain falls at most LANDING_GRADE for LANDING_M before
## the ramp to the original terrain begins (with the ramp starting at the edge, a vertex 1.95 m out on a steep ramp left the edge
## hanging up to 0.5 m over the ground between the two vertices). Bridge decks are left alone, their approaches only raised,
## culvert channels kept.
static func _fit_mesh_road(terrain: Terrain3D, roads: RoadNetwork, r: RoadNetwork.Road, ri: int, spacing: float, space: PhysicsDirectSpaceState3D,
		c: Candidates, stats: Dictionary) -> void:
	var pts := r.points
	var hw := r.width * 0.5
	# Cumulative length and the stations' edges on the right (-) and left (+) side: offset and height (NAN: none found).
	var cum := PackedFloat32Array([0.0])
	for i in pts.size() - 1:
		cum.append(cum[i] + Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length())
	var n_st := int(cum[cum.size() - 1] / STATION_M) + 1
	var em := PackedFloat32Array()
	var eym := PackedFloat32Array()
	var ep := PackedFloat32Array()
	var eyp := PackedFloat32Array()
	em.resize(n_st)
	eym.resize(n_st)
	ep.resize(n_st)
	eyp.resize(n_st)
	var seg := 0
	for k in n_st:
		var s := k * STATION_M
		while seg < pts.size() - 2 and cum[seg + 1] < s:
			seg += 1
		var a := pts[seg]
		var b := pts[seg + 1]
		var u := clampf((s - cum[seg]) / maxf(cum[seg + 1] - cum[seg], 0.001), 0.0, 1.0)
		var p := a.lerp(b, u)
		var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var nrm := Vector3(-t.z, 0.0, t.x)
		var fm := Vector2(NAN, NAN)
		var fp := Vector2(NAN, NAN)
		if space and roads.bridge_at(p, 1.0) == null:
			fm = _edge(space, p, -nrm, hw, stats)
			fp = _edge(space, p, nrm, hw, stats)
		em[k] = fm.x
		eym[k] = fm.y
		ep[k] = fp.x
		eyp[k] = fp.y
	stats.stations += n_st
	var culverts: Array[Vector2] = []
	for ci in r.culverts:
		culverts.append(Vector2(pts[int(ci)].x, pts[int(ci)].z))
	var reach := hw + MESH_EDGE_M + 1.0 + LANDING_M + SHOULDER_MAX_M
	for i in pts.size() - 1:
		var approach := _near_bridge(r, pts, i)
		var a := pts[i]
		var b := pts[i + 1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var seg_len := ab.length()
		var lo := a2.min(a2 + ab) - Vector2(reach, reach)
		var hi := a2.max(a2 + ab) + Vector2(reach, reach)
		for gx in range(ceili(lo.x / spacing), floori(hi.x / spacing) + 1):
			for gz in range(ceili(lo.y / spacing), floori(hi.y / spacing) + 1):
				var q := Vector2(gx * spacing, gz * spacing)
				var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var d := q.distance_to(a2 + ab * t)
				if d > reach or _not_nearest(q, d, pts, i):
					continue
				var q3 := Vector3(q.x, 0.0, q.y)
				if roads.bridge_at(q3, 2.0) != null:
					continue
				var foot := a2 + ab * t
				var nrm := Vector2.ZERO if d < 0.001 else (q - foot) / d
				# Left of the centre line = the +nrm side of the stations (nrm = (-t.z, t.x)).
				var left := (ab.x * (q.y - a2.y) - ab.y * (q.x - a2.x)) > 0.0
				var road_y := lerpf(a.y, b.y, t)
				# The station's edge on this side (the nearest station with one; else the mesh model).
				var k0 := clampi(roundi((cum[i] + t * seg_len) / STATION_M), 0, n_st - 1)
				var e := NAN
				var ey := NAN
				for dk: int in [0, 1, -1, 2, -2]:
					var k := k0 + dk
					if k < 0 or k >= n_st:
						continue
					var ek: float = ep[k] if left else em[k]
					if not is_nan(ek):
						e = ek
						ey = eyp[k] if left else eym[k]
						break
				if is_nan(e):
					e = hw + MESH_EDGE_M
					ey = road_y + 0.2 - 0.5
				var key := Vector2i(gx, gz)
				if space and d <= e + 1.5:
					var y := _road_y(space, q.x, q.y, road_y)
					stats.rays += 1
					if not is_nan(y):
						# Distance inside the edge; a hit just past the measured edge is the same edge (the stations are 2 m apart).
						var din := maxf(e - d, 0.0)
						var bury := lerpf(BURY_EDGE, BURY_IN, clampf(din / 2.0, 0.0, 1.0))
						var nh_in := y - bury
						if approach:
							nh_in = maxf(nh_in, terrain.data.get_height(q3))
						stats.inside += 1
						c.offer(key, nh_in, -10.0 - bury, ri)
						continue
				elif not space and d <= e:
					# Mesh model (no physics): carriageway at road_y + 0.2, gutter falling 0.5 m to the edge.
					var f := clampf((d - hw) / maxf(e - hw, 0.01), 0.0, 1.0)
					c.offer(key, lerpf(road_y + 0.2, ey, f) - lerpf(BURY_IN, BURY_EDGE, f), -10.0, ri)
					continue
				var out := maxf(d - e, 0.0)
				if _near_culvert(q, culverts):
					stats.culvert_kept += 1
					continue
				var start := ey - BURY_EDGE
				var nh := NAN
				if approach:
					if out > LANDING_M:
						continue
					nh = maxf(start - LANDING_GRADE * out, terrain.data.get_height(q3))
				else:
					nh = _ramp(terrain, foot, nrm, e, out, start, LANDING_GRADE)
					if is_nan(nh):
						continue
					if out < LANDING_M and absf(nh - (start - LANDING_GRADE * out)) < 0.001:
						stats.landing += 1
				c.offer(key, nh, out, ri)


## Height at `out` metres beyond an edge at lateral offset `edge` (start: the height there) along nrm from foot: an even ramp to
## the original terrain at the band's end (band SHOULDER_M .. SHOULDER_MAX_M, nearer SLOPE where the height is large). A falling
## ramp whose start would be steeper than max_grade (0: no limit) first falls at max_grade for LANDING_M. NAN: past the band.
static func _ramp(terrain: Terrain3D, foot: Vector2, nrm: Vector2, edge: float, out: float, start: float, max_grade: float) -> float:
	var outer := _h_at(terrain, foot + nrm * (edge + SHOULDER_M))
	var band := SHOULDER_M
	if not is_nan(outer):
		band = clampf(absf(outer - start) / SLOPE, SHOULDER_M, SHOULDER_MAX_M)
		outer = _h_at(terrain, foot + nrm * (edge + band))
	if is_nan(outer):
		return NAN
	# The ramp's grade at its start is half its mean (lerp of linear and smoothstep).
	if max_grade > 0.0 and (start - outer) * 0.5 / band > max_grade:
		if out <= LANDING_M:
			return start - max_grade * out
		var e2 := edge + LANDING_M
		var s2 := start - max_grade * LANDING_M
		var outer2 := _h_at(terrain, foot + nrm * (e2 + SHOULDER_M))
		var band2 := SHOULDER_M
		if not is_nan(outer2):
			band2 = clampf(absf(outer2 - s2) / SLOPE, SHOULDER_M, SHOULDER_MAX_M)
			outer2 = _h_at(terrain, foot + nrm * (e2 + band2))
		if is_nan(outer2) or out - LANDING_M >= band2:
			return NAN
		var u2 := (out - LANDING_M) / band2
		return lerpf(s2, outer2, lerpf(u2, smoothstep(0.0, 1.0, u2), 0.5))
	if out >= band:
		return NAN
	var u := out / band
	return lerpf(start, outer, lerpf(u, smoothstep(0.0, 1.0, u), 0.5))


static func _h_at(terrain: Terrain3D, p: Vector2) -> float:
	return terrain.data.get_height(Vector3(p.x, 0.0, p.y))


## Where the road collider ends going out from the centre line at p along dir: Vector2(offset, edge height); NAN when there is no
## surface at the start or it goes on past EDGE_SEARCH_M (a junction surface is searched to its far edge).
static func _edge(space: PhysicsDirectSpaceState3D, p: Vector3, dir: Vector3, hw: float, stats: Dictionary) -> Vector2:
	var s := maxf(hw - 0.5, 0.0)
	var y := _road_y(space, p.x + dir.x * s, p.z + dir.z * s, p.y + 0.2)
	stats.rays += 1
	if is_nan(y):
		return Vector2(NAN, NAN)
	var last := s
	var last_y := y
	var miss := -1.0
	# Most edges lie ~2 m beyond RoadNetwork's width (the gutter): start stepping 1.25 m beyond it when the surface reaches there.
	var y_far := _road_y(space, p.x + dir.x * (hw + 1.25), p.z + dir.z * (hw + 1.25), y)
	stats.rays += 1
	if not is_nan(y_far):
		s = hw + 1.25
		last = s
		last_y = y_far
	while s < hw + EDGE_SEARCH_M:
		s += 0.25
		y = _road_y(space, p.x + dir.x * s, p.z + dir.z * s, last_y)
		stats.rays += 1
		if is_nan(y):
			miss = s
			break
		last = s
		last_y = y
	if miss < 0.0:
		stats.no_edge += 1
		return Vector2(NAN, NAN)
	var lo := last
	var hi := miss
	for k in 5:
		var mid := (lo + hi) * 0.5
		y = _road_y(space, p.x + dir.x * mid, p.z + dir.z * mid, last_y)
		stats.rays += 1
		if is_nan(y):
			hi = mid
		else:
			lo = mid
			last_y = y
	stats.edges += 1
	return Vector2(lo, last_y)


## Height of a road collider (Road Generator road or intersection) at (x, z), NAN where there is none; terrain pieces and
## structures in the way are looked through.
static func _road_y(space: PhysicsDirectSpaceState3D, x: float, z: float, y_ref: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_ref + 25.0, z), Vector3(x, y_ref - 25.0, z))
	var ex: Array[RID] = []
	for k in 4:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return NAN
		if is_road_collider(hit.collider):
			return float(hit.position.y)
		ex.append(hit.rid)
		q.exclude = ex
	return NAN


## The StaticBody Road Generator makes for a road segment's or an intersection's mesh (create_trimesh_collision: "<mesh>_col").
static func is_road_collider(c: Object) -> bool:
	if not c is Node:
		return false
	var n := String((c as Node).name)
	return n.begins_with("road_mesh") or n.begins_with("intersection_mesh")


## True when another segment of the same road lies nearer q (the nearest segment decides; bends are covered by two).
static func _not_nearest(q: Vector2, d: float, pts: PackedVector3Array, i: int) -> bool:
	if i > 0 and _seg_dist(q, pts[i - 1], pts[i]) < d - 0.01:
		return true
	return i + 2 < pts.size() and _seg_dist(q, pts[i + 1], pts[i + 2]) < d - 0.01


static func _near_culvert(q: Vector2, culverts: Array[Vector2]) -> bool:
	for c in culverts:
		if q.distance_squared_to(c) < CULVERT_KEEP_M * CULVERT_KEEP_M:
			return true
	return false


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


## The Road Generator meshes (roads and intersections) below road_root.
static func _road_meshes(road_root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if road_root == null:
		return out
	var stack: Array[Node] = [road_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (String(n.name) == "road_mesh" or String(n.name) == "intersection_mesh"):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


## A short signature of the road set, the road meshes and the rules (the cache is rebuilt when any changes).
static func _signature(roads: RoadNetwork, spacing: float, meshes: Array[MeshInstance3D] = []) -> String:
	var h := hash([CACHE_VERSION, SHOULDER_M, SHOULDER_MAX_M, SLOPE, UNDER_M, MIN_CHANGE_M, BRIDGE_SKIP_M, MESH_EDGE_M, MESH_EDGE_DROP_M, STATION_M,
		EDGE_SEARCH_M, BURY_IN, BURY_EDGE, LANDING_M, LANDING_GRADE, CULVERT_KEEP_M, BURY_INNER_GRASS, spacing, roads.world.size(), meshes.size()])
	for mi in meshes:
		h = hash([h, mi.global_transform * mi.get_aabb()])
	for r: RoadNetwork.Road in roads.world:
		if r.points.size() > 0:
			h = hash([h, r.points.size(), r.points[0], r.points[r.points.size() - 1], r.width])
	return "%08x" % (h & 0xffffffff)
