## WorldBuilder for reference-based worlds (WORLD-TERRAIN-01).
##
## The geography is generated offline by tools/terrain_ref/generate.py from a layout traced
## from the reference map. This builder only moves that data into the existing pipeline:
##   - height, control (texture ids + blends) and colour maps -> Terrain3D import;
##   - primary/secondary roads -> Road Generator RoadPoints and RoadIntersections (graded
##     profile from the generator, flattened by the Terrain3D connector, river channel
##     restored under bridges); local roads and tracks are terrain paint + grading only;
##   - river and lakes -> water meshes;
##   - trees, shrubs, deadwood and rocks -> VegetationChunk cells, species chosen from the
##     vegetation maps (forest density, pine/birch/spruce shares, wetness, rockiness);
##   - bridges, culverts and settlement props -> scene nodes / vegetation cells.
## Everything else (streaming, grass, colliders, FPS/RTS) is the unchanged WORLD-TECH-02
## and WORLD-CORE architecture.
@tool
class_name ReferenceWorldBuilder
extends WorldBuilder

const TEX_FOREST := 4
const TEX_GRAVEL := 5
const TEX_BOG := 6
const TEX_ASPHALT := 7

## Mesh ids of the Nordic vegetation library (assets/environment/nordic_library.tres).
const M_PINE_A := 1
const M_PINE_B := 2
const M_SPRUCE_A := 3
const M_SPRUCE_B := 4
const M_BIRCH_A := 5
const M_BIRCH_B := 6
const M_JUNIPER := 7
const M_SHRUB := 8
const M_BOULDER_A := 9
const M_BOULDER_B := 10
const M_ROCKS_SMALL := 11
const M_OUTCROP := 12
const M_LOG := 13
const M_STUMP := 14
const M_FERN := 15
const M_HOUSE := 16
const M_BARN := 17
const M_SHED := 18
const M_FENCE := 19
const M_MAILBOX := 20
const M_ROADPOST := 21
const ALL_MESHES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]

const WATER_SHADER := "res://shaders/world/water.gdshader"

## Distance from an intersection centre to its edge RoadPoints, metres.
const REF_JUNCTION_ARM_M := 14.0
## Road Generator validates a whole container per RoadPoint change (O(n^2)); keep them small.
const MAX_RP_PER_CONTAINER := 48

var _height_src: Image
## Planned buildings and roadside props: cell -> [[mesh id, Transform3D, Color], ...].
var _props_by_cell := {}
## Building footprints for tree clearance: cell -> [[Vector2 centre, radius], ...].
var _bld_by_cell := {}
## Road index of the paved (mesh) roads only: wider clearance for trees.
var _sc_major: _RoadIndex
var _major_polylines: Array = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# Per-world render setting: the directional shadow atlas at 2048 instead of the
	# project's 4096. Alpha-card forests are shadow fill-rate bound; measured at the FPS
	# station this halves the shadow cost (docs/WORLD-TERRAIN-01_REPORT.md, performance).
	RenderingServer.directional_shadow_atlas_set_size(2048, true)


func _generator() -> WorldTerrainGenerator:
	if _gen == null or _gen.cfg != config:
		_gen = ReferenceTerrainGenerator.new(config)
	return _gen


func _ref() -> ReferenceTerrainGenerator:
	return _generator() as ReferenceTerrainGenerator


func _src() -> String:
	return (config as ReferenceWorldConfig).source_directory


func _json(file_name: String) -> Variant:
	var txt := FileAccess.get_file_as_string(_src().path_join(file_name))
	if txt.is_empty():
		push_error("ReferenceWorldBuilder: %s missing in %s" % [file_name, _src()])
		return null
	return JSON.parse_string(txt)


# ------------------------------------------------------------------------------
# Terrain
# ------------------------------------------------------------------------------

func setup_terrain() -> void:
	super.setup_terrain()
	# The control map carries explicit texture ids and blends (rock on slopes is baked in).
	terrain.material.auto_shader = false
	terrain.material.set_shader_param("blend_sharpness", 0.6)
	terrain.collision_radius = 96


func make_assets() -> Terrain3DAssets:
	var a := super.make_assets()
	var tex_dir := "res://assets/terrain/textures/"
	a.set_texture(WorldTerrainGenerator.TEX_GRASS, _tex(WorldTerrainGenerator.TEX_GRASS, "Meadow", tex_dir + "ground037", Color(0.70, 0.84, 0.52), 0.11))
	a.set_texture(WorldTerrainGenerator.TEX_ROCK, _tex(WorldTerrainGenerator.TEX_ROCK, "Rock", tex_dir + "rock023", Color(0.92, 0.92, 0.9), 0.06))
	a.set_texture(WorldTerrainGenerator.TEX_DIRT, _tex(WorldTerrainGenerator.TEX_DIRT, "Dirt", tex_dir + "dirt_proc", Color(0.95, 0.9, 0.85), 0.18))
	a.set_texture(WorldTerrainGenerator.TEX_DRY_GRASS, _tex(WorldTerrainGenerator.TEX_DRY_GRASS, "Field / heath", tex_dir + "ground037", Color(0.96, 0.98, 0.70), 0.09))
	a.set_texture(TEX_FOREST, _tex(TEX_FOREST, "Forest floor", tex_dir + "forest_floor", Color.WHITE, 0.16))
	a.set_texture(TEX_GRAVEL, _tex(TEX_GRAVEL, "Gravel", tex_dir + "gravel", Color(0.72, 0.70, 0.66), 0.3))
	a.set_texture(TEX_BOG, _tex(TEX_BOG, "Bog", tex_dir + "bog", Color.WHITE, 0.1))
	a.set_texture(TEX_ASPHALT, _tex(TEX_ASPHALT, "Asphalt", tex_dir + "asphalt", Color.WHITE, 0.25))
	return a


func generate_terrain() -> void:
	var t0 := Time.get_ticks_msec()
	var imgs := _generator().generate_images()
	if imgs.size() < 3:
		return
	var t1 := Time.get_ticks_msec()
	for region in terrain.data.get_regions_active():
		terrain.data.remove_region(region, false)
	var hs := config.half_size()
	terrain.data.import_images([imgs[0], imgs[1], imgs[2]], Vector3(-hs, 0, -hs), 0.0, 1.0)
	terrain.data.calc_height_range(true)
	# Colour maps need mipmaps or distant terrain shimmers.
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var cm := region.get_color_map()
		if cm and not cm.has_mipmaps():
			cm.generate_mipmaps()
			region.set_color_map(cm)
		region.set_modified(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, true, true)
	_height_src = imgs[0]
	print("ReferenceWorldBuilder: loaded %dx%d maps in %d ms, imported in %d ms (%d regions)" % [
		imgs[0].get_width(), imgs[0].get_height(), t1 - t0, Time.get_ticks_msec() - t1,
		terrain.data.get_region_count()])


## The colour map comes from the generator (fields, forests, heath); nothing to bake.
func bake_forest_tint(_mask: VegetationMask = null) -> void:
	pass


# ------------------------------------------------------------------------------
# Roads
# ------------------------------------------------------------------------------

func build_roads(scene_owner: Node) -> void:
	for c in road_parent.get_children():
		road_parent.remove_child(c)
		c.free()
	var data = _json("roads.json")
	if data == null:
		return
	var manager: Node3D = RoadManagerScript.new()
	manager.name = "RoadManager"
	road_parent.add_child(manager)
	manager.owner = scene_owner
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()

	_collect_road_polylines()
	var roads: Array = []
	for r in data.roads:
		if r.mesh:
			roads.append(r)
	# Junctions: waypoints shared by paved roads (from the generator) and the ends of
	# paved roads, merged within 6 m.
	var junctions: Array[Vector3] = []
	var cand: Array = data.get("junctions", []).duplicate()
	for r in roads:
		cand.append(r.points[0])
		cand.append(r.points[r.points.size() - 1])
	for p in cand:
		var v := Vector3(p[0], p[1], p[2])
		var found := false
		for j in junctions:
			if Vector2(j.x, j.z).distance_to(Vector2(v.x, v.z)) < 6.0:
				found = true
				break
		if not found:
			junctions.append(v)
	# Split every paved road at the junctions it passes through.
	var pieces: Array = [] # {pts: Array[Vector3], lane, shoulder, start_j, end_j}
	# Bridge span ends become RoadPoints, so the road runs straight over the bridge deck.
	var pinned := {}
	for r in roads:
		for span in r.bridges:
			for k in [int(span[0]), int(span[1])]:
				pinned[Vector3i(roundi(float(r.points[k][0]) * 10.0), 0, roundi(float(r.points[k][2]) * 10.0))] = true
	var degree := {}
	for r in roads:
		var pts: Array[Vector3] = []
		for p in r.points:
			pts.append(Vector3(p[0], p[1], p[2]))
		var splits := {} # point index -> junction index
		for ji in junctions.size():
			var j := junctions[ji]
			var best := -1
			var best_d := 6.0
			for i in pts.size():
				var d := Vector2(pts[i].x, pts[i].z).distance_to(Vector2(j.x, j.z))
				if d < best_d:
					best_d = d
					best = i
			if best >= 0:
				splits[best] = ji
		var idx: Array = splits.keys()
		idx.sort()
		var cuts: Array = [0] + idx + [pts.size() - 1]
		for k in cuts.size() - 1:
			var a: int = cuts[k]
			var b: int = cuts[k + 1]
			if b - a < 2:
				continue
			var piece := {"pts": pts.slice(a, b + 1), "lane": float(r.lane_m), "shoulder": float(r.shoulder_m),
				"start_j": splits.get(a, -1), "end_j": splits.get(b, -1), "name": r.name}
			for key in ["start_j", "end_j"]:
				if piece[key] >= 0:
					degree[piece[key]] = degree.get(piece[key], 0) + 1
			pieces.append(piece)

	# One RoadContainer per road piece and per junction. Road Generator re-validates the
	# whole container whenever one of its RoadPoints enters the tree (O(n^2) in the
	# container size, on every scene load too), so small containers keep both the build
	# and loading fast. Pieces meet the junction containers at coincident edge RoadPoints
	# (cross-container connections).
	var containers: Array = []
	var inters := {} # junction index -> [container, RoadIntersection]
	for ji in degree:
		if degree[ji] >= 2:
			var jc: Node3D = RoadContainerScript.new()
			jc.name = "Junction_%02d" % ji
			manager.add_child(jc)
			jc.owner = scene_owner
			var inter: Node3D = RoadIntersectionScript.new()
			inter.name = "Intersection"
			jc.add_child(inter)
			inter.owner = scene_owner
			inter.position = junctions[ji] + Vector3.UP * 0.2
			inters[ji] = [jc, inter]
			containers.append(jc)
	printerr("ReferenceWorldBuilder: roads split into %d pieces in %d ms" % [pieces.size(), Time.get_ticks_msec() - t0])
	var chains: Array = []
	var joins: Array = [] # [last RoadPoint of a chunk, first RoadPoint of the next chunk]
	var n_rp := 0
	for pi in pieces.size():
		var piece: Dictionary = pieces[pi]
		var pts: Array[Vector3] = piece.pts
		if inters.has(piece.start_j):
			pts = _trim_start(pts, REF_JUNCTION_ARM_M)
		if inters.has(piece.end_j):
			pts.reverse()
			pts = _trim_start(pts, REF_JUNCTION_ARM_M)
			pts.reverse()
		var simple := _simplify(pts, 0.8, 0.25, 90.0, pinned)
		# Long pieces are cut into chunks of at most MAX_RP_PER_CONTAINER RoadPoints; a
		# chunk's last RoadPoint and the next chunk's first are coincident and joined
		# across containers.
		var n_chunks := ceili(float(simple.size() - 1) / float(MAX_RP_PER_CONTAINER - 1))
		var prev_last: Node3D = null
		for k in n_chunks:
			var i0 := k * (MAX_RP_PER_CONTAINER - 1)
			var i1 := mini(i0 + MAX_RP_PER_CONTAINER - 1, simple.size() - 1)
			var pc: Node3D = RoadContainerScript.new()
			pc.name = "Road_%03d_%02d" % [pi, k]
			manager.add_child(pc)
			pc.owner = scene_owner
			containers.append(pc)
			var nodes: Array = []
			for i in range(i0, i1 + 1):
				var p: Vector3 = simple[i]
				var prev: Vector3 = simple[maxi(i - 1, 0)]
				var nxt: Vector3 = simple[mini(i + 1, simple.size() - 1)]
				nodes.append(_add_rp3(pc, scene_owner, p, (nxt - prev).normalized(), piece.lane, piece.shoulder,
					p.distance_to(prev), p.distance_to(nxt)))
			n_rp += nodes.size()
			if prev_last:
				joins.append([prev_last, nodes[0]])
			prev_last = nodes[nodes.size() - 1]
			chains.append([nodes, {"start_j": piece.start_j if k == 0 else -1,
				"end_j": piece.end_j if k == n_chunks - 1 else -1}])
	printerr("ReferenceWorldBuilder: %d RoadPoints created at %d ms" % [n_rp, Time.get_ticks_msec() - t0])
	await get_tree().process_frame
	for c in containers:
		c._auto_refresh = false
	var links: Array = [] # [piece RoadPoint, its open dir, stub RoadPoint, stub open dir]
	var stubs: Array = [] # [intersection, stub]
	for ch in chains:
		var nodes: Array = ch[0]
		var piece: Dictionary = ch[1]
		_connect_chain(nodes)
		for end in [[piece.start_j, nodes[0], RoadPoint.PointInit.PRIOR, RoadPoint.PointInit.NEXT],
				[piece.end_j, nodes[nodes.size() - 1], RoadPoint.PointInit.NEXT, RoadPoint.PointInit.PRIOR]]:
			var ji: int = end[0]
			if not inters.has(ji):
				continue
			var stub := _add_stub(inters[ji][0], scene_owner, end[1])
			stubs.append([inters[ji][1], stub])
			links.append([end[1], end[2], stub, end[3]])
	printerr("ReferenceWorldBuilder: chains connected at %d ms" % (Time.get_ticks_msec() - t0))
	await get_tree().process_frame
	for st in stubs:
		st[0].add_branch(st[1])
	for c in containers:
		c.update_edges()
	var failed := 0
	for l in links:
		if not l[0].connect_container(l[1], l[2], l[3]):
			failed += 1
	for jn in joins:
		if not jn[0].connect_container(RoadPoint.PointInit.NEXT, jn[1], RoadPoint.PointInit.PRIOR):
			failed += 1
	var t1 := Time.get_ticks_msec()
	for c in containers:
		c._auto_refresh = true
		c.rebuild_segments(true)
	printerr("ReferenceWorldBuilder: %d containers, %d RoadPoints, %d junctions; assembled in %d ms, segments in %d ms, %d failed links" % [
		containers.size(), n_rp + stubs.size(), inters.size(), t1 - t0, Time.get_ticks_msec() - t1, failed])
	var connector: Node = ConnectorScript.new()
	connector.name = "Terrain3DRoadConnector"
	road_parent.add_child(connector)
	connector.owner = scene_owner
	connector.road_manager = manager
	connector.terrain = terrain
	connector.edge_margin = 1.0
	connector.edge_falloff = 4.0


## Edge RoadPoint of a junction container, coincident with a piece's end RoadPoint.
func _add_stub(jc: Node, scene_owner: Node, rp: Node3D) -> Node3D:
	var stub: Node3D = RoadPointScript.new()
	stub.name = "Arm_%d" % jc.get_child_count()
	var dirs: Array[RoadPoint.LaneDir] = [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD]
	var lane_types: Array[RoadPoint.LaneType] = [RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.TWO_WAY]
	stub.traffic_dir = dirs
	stub.lanes = lane_types
	stub.lane_width = rp.lane_width
	stub.shoulder_width_l = rp.shoulder_width_l
	stub.shoulder_width_r = rp.shoulder_width_r
	stub.prior_mag = 4.0
	stub.next_mag = 4.0
	jc.add_child(stub)
	stub.owner = scene_owner
	stub.global_transform = rp.global_transform
	return stub


func _trim_start(pts: Array[Vector3], dist: float) -> Array[Vector3]:
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[i - 1].x, pts[i - 1].z))
		if acc >= dist:
			return pts.slice(i)
	return pts.slice(pts.size() - 2)


## Douglas-Peucker on the dense profile: horizontal and vertical tolerances, plus a
## maximum spacing so long straights still get RoadPoints for terrain following.
func _simplify(pts: Array[Vector3], tol_h: float, tol_v: float, max_len: float, pinned := {}) -> Array[Vector3]:
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack := []
	var fixed: Array = [0]
	for i in range(1, pts.size() - 1):
		if pinned.has(Vector3i(roundi(pts[i].x * 10.0), 0, roundi(pts[i].z * 10.0))):
			keep[i] = 1
			fixed.append(i)
	fixed.append(pts.size() - 1)
	for k in fixed.size() - 1:
		stack.append([fixed[k], fixed[k + 1]])
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		if b - a < 2:
			continue
		var pa := pts[a]
		var pb := pts[b]
		var worst := -1
		var worst_e := 0.0
		var len_ab := Vector2(pa.x, pa.z).distance_to(Vector2(pb.x, pb.z))
		for i in range(a + 1, b):
			var q := Geometry2D.get_closest_point_to_segment(Vector2(pts[i].x, pts[i].z), Vector2(pa.x, pa.z), Vector2(pb.x, pb.z))
			var eh := q.distance_to(Vector2(pts[i].x, pts[i].z)) / tol_h
			var t := 0.0 if len_ab < 0.01 else Vector2(pa.x, pa.z).distance_to(q) / len_ab
			var ev := absf(lerpf(pa.y, pb.y, t) - pts[i].y) / tol_v
			var e := maxf(eh, ev)
			if e > worst_e:
				worst_e = e
				worst = i
		if worst_e > 1.0 or len_ab > max_len:
			if worst < 0:
				worst = (a + b) / 2
			keep[worst] = 1
			stack.append([a, worst])
			stack.append([worst, b])
	var out: Array[Vector3] = []
	for i in pts.size():
		if keep[i]:
			out.append(pts[i])
	return out


func _add_rp3(container: Node, scene_owner: Node, pos: Vector3, fwd: Vector3, lane_w: float, shoulder: float,
		d_prior: float, d_next: float) -> Node3D:
	var rp: Node3D = RoadPointScript.new()
	rp.name = "RP_%04d" % container.get_child_count()
	var dirs: Array[RoadPoint.LaneDir] = [RoadPoint.LaneDir.REVERSE, RoadPoint.LaneDir.FORWARD]
	var lane_types: Array[RoadPoint.LaneType] = [RoadPoint.LaneType.TWO_WAY, RoadPoint.LaneType.TWO_WAY]
	rp.traffic_dir = dirs
	rp.lanes = lane_types
	rp.lane_width = lane_w
	rp.shoulder_width_l = shoulder
	rp.shoulder_width_r = shoulder
	rp.prior_mag = clampf(d_prior * 0.35, 2.0, 40.0)
	rp.next_mag = clampf(d_next * 0.35, 2.0, 40.0)
	container.add_child(rp)
	rp.owner = scene_owner
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	rp.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), pos + Vector3.UP * 0.2)
	return rp


## All roads (paved and unpaved) as polylines with their full widths, for the grass mask
## and the vegetation clearance.
func _collect_road_polylines() -> void:
	road_polylines.clear()
	road_widths.clear()
	_major_polylines.clear()
	var data = _json("roads.json")
	if data == null:
		return
	for r in data.roads:
		var line := PackedVector3Array()
		for p in r.points:
			line.append(Vector3(p[0], p[1], p[2]))
		road_polylines.append(line)
		road_widths.append(float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m))
		if r.mesh:
			_major_polylines.append(line)


## After the connector flattened the terrain under the roads, put the river channel back
## under bridge decks (the connector fills it up to the deck height otherwise).
## WORLD-PLAYTEST-01: the connector only queues the flattening and runs it in its next
## physics frame, so restoring right away was undone afterwards: every bridge stood on an
## earth dam across the river. Wait for the connector first.
func flatten_roads() -> void:
	super.flatten_roads()
	var connector := road_parent.get_node_or_null("Terrain3DRoadConnector")
	for i in 60:
		await get_tree().physics_frame
		if connector == null or connector._next_refresh_parents.is_empty():
			break
	await get_tree().physics_frame
	restore_bridge_channels()


func restore_bridge_channels() -> void:
	if _height_src == null:
		var bytes := FileAccess.get_file_as_bytes(_src().path_join("height.r32"))
		var res := (config as ReferenceWorldConfig).source_resolution
		_height_src = Image.create_from_data(res, res, false, Image.FORMAT_RF, bytes)
	var data = _json("roads.json")
	var sp := config.vertex_spacing
	var hs := config.half_size()
	var restored := 0
	for r in data.roads:
		var half: float = float(r.lane_m) * float(r.lanes) * 0.5 + float(r.shoulder_m) + 8.0
		for span in r.bridges:
			var pts: Array[Vector2] = []
			for i in range(int(span[0]), int(span[1]) + 1):
				pts.append(Vector2(r.points[i][0], r.points[i][2]))
			var lo := pts[0]
			var hi := pts[0]
			for p in pts:
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			lo -= Vector2(half, half)
			hi += Vector2(half, half)
			var x := snappedf(lo.x, sp)
			while x <= hi.x:
				var z := snappedf(lo.y, sp)
				while z <= hi.y:
					var q := Vector2(x, z)
					var d := INF
					for i in pts.size() - 1:
						d = minf(d, q.distance_to(Geometry2D.get_closest_point_to_segment(q, pts[i], pts[i + 1])))
					if d < half:
						var px := clampi(roundi((x + hs) / sp), 0, _height_src.get_width() - 1)
						var pz := clampi(roundi((z + hs) / sp), 0, _height_src.get_height() - 1)
						var h0 := _height_src.get_pixel(px, pz).r
						var pos := Vector3(x, 0, z)
						if terrain.data.get_height(pos) > h0 + 0.3:
							terrain.data.set_height(pos, h0)
							restored += 1
					z += sp
				x += sp
	terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, true, false)
	print("ReferenceWorldBuilder: restored %d terrain vertices under bridges" % restored)


# ------------------------------------------------------------------------------
# Water, bridges, culverts, settlement props
# ------------------------------------------------------------------------------

## Builds the water meshes and places bridge/culvert scenes. Called by build_world.gd
## after the roads (and by the editor button below).
func build_extras(scene_owner: Node) -> void:
	build_water(scene_owner)
	place_structures(scene_owner)
	# Clearer air than the WORLD-TECH test maps: the RTS camera works at 150-1500 m and the
	# 20 km landscape should stay readable (per-world environment, built by build_world.gd).
	var we: WorldEnvironment = scene_owner.get_node_or_null("WorldEnvironment")
	if we and we.environment:
		we.environment.fog_density = 0.00006
		we.environment.fog_aerial_perspective = 0.15
		we.environment.fog_sky_affect = 0.1


func build_water(scene_owner: Node) -> void:
	var data = _json("water.json")
	if data == null:
		return
	var root := scene_owner.get_node_or_null("Water")
	if root:
		root.free()
	root = Node3D.new()
	root.name = "Water"
	scene_owner.add_child(root)
	root.owner = scene_owner
	var dir := "res://worlds/%s/water" % config.world_name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var river_mat := water_material(true)
	var lake_mat := water_material(false)

	# River: ribbon in ~2 km pieces (so off-screen parts are culled).
	var pts: Array = data.river.points
	var widths: Array = data.river.width
	var levels: Array = data.river.level
	var piece := 80
	var k := 0
	var s_acc := 0.0
	while k < pts.size() - 1:
		var k1 := mini(k + piece, pts.size() - 1)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(k, k1 + 1):
			var p := Vector2(pts[i][0], pts[i][1])
			var a := Vector2(pts[maxi(i - 1, 0)][0], pts[maxi(i - 1, 0)][1])
			var b := Vector2(pts[mini(i + 1, pts.size() - 1)][0], pts[mini(i + 1, pts.size() - 1)][1])
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x)
			var w: float = widths[i] * 0.5
			var y: float = levels[i]
			if i > k:
				s_acc += p.distance_to(Vector2(pts[i - 1][0], pts[i - 1][1]))
			for side: float in [-1.0, 1.0]:
				var q: Vector2 = p + n * w * side
				st.set_uv(Vector2(s_acc / 20.0, side * w / 20.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(q.x, y, q.y))
		var rows := k1 - k + 1
		for i in rows - 1:
			var v := i * 2
			st.add_index(v)
			st.add_index(v + 2)
			st.add_index(v + 1)
			st.add_index(v + 1)
			st.add_index(v + 2)
			st.add_index(v + 3)
		st.generate_tangents()
		var mesh := st.commit()
		var path := dir + "/river_%02d.res" % (k / piece)
		ResourceSaver.save(mesh, path)
		mesh.take_over_path(path)
		_water_instance(root, scene_owner, "River_%02d" % (k / piece), mesh, river_mat)
		k = k1
	# Lakes: flat polygons at the water level.
	for lake in data.lakes:
		var poly := PackedVector2Array()
		for p in lake.outline:
			poly.append(Vector2(p[0], p[1]))
		var tri := Geometry2D.triangulate_polygon(poly)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in poly:
			st.set_uv(p / 20.0)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, lake.level, p.y))
		for i in tri:
			st.add_index(i)
		st.generate_tangents()
		var mesh := st.commit()
		var path: String = dir + "/lake_%s.res" % String(lake.name).validate_filename()
		ResourceSaver.save(mesh, path)
		mesh.take_over_path(path)
		_water_instance(root, scene_owner, "Lake_" + String(lake.name), mesh, lake_mat)
	print("ReferenceWorldBuilder: water meshes built (%d lakes)" % data.lakes.size())


func _water_instance(root: Node, scene_owner: Node, node_name: String, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.owner = scene_owner


func water_material(flowing: bool) -> ShaderMaterial:
	var path := "res://assets/environment/water/%s.tres" % ("water_river" if flowing else "water_lake")
	if ResourceLoader.exists(path):
		return load(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var m := ShaderMaterial.new()
	m.shader = load(WATER_SHADER)
	for i in 2:
		var noise := FastNoiseLite.new()
		noise.seed = 7 + i
		noise.frequency = 0.02 if i == 0 else 0.045
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.width = 512
		tex.height = 512
		tex.seamless = true
		tex.as_normal_map = true
		tex.bump_strength = 6.0 if i == 0 else 3.0
		tex.noise = noise
		m.set_shader_parameter("normal_a" if i == 0 else "normal_b", tex)
	m.set_shader_parameter("flow_speed", 0.6 if flowing else 0.0)
	m.set_shader_parameter("wind_speed", 0.012 if flowing else 0.02)
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	return m


## Bridges over the river for every road crossing (12 m concrete modules with wall piers
## for paved roads, 6 m timber modules for local roads and tracks) and culverts on both
## sides of road fills over streams. Scenes come from the Blender environment pipeline;
## missing scenes are skipped (the paved road deck still spans the river).
func place_structures(scene_owner: Node) -> void:
	var data = _json("roads.json")
	var root := scene_owner.get_node_or_null("RoadStructures")
	if root:
		root.free()
	root = Node3D.new()
	root.name = "RoadStructures"
	scene_owner.add_child(root)
	root.owner = scene_owner
	var scenes := {}
	for key in ["bridge_concrete", "bridge_pier", "bridge_timber", "culvert"]:
		var path := "res://assets/environment/scenes/%s.tscn" % key
		if ResourceLoader.exists(path):
			scenes[key] = load(path)
	var n_br := 0
	var n_cv := 0
	for r in data.roads:
		var paved: bool = r.mesh
		var deck_w: float = float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)
		var module_key := "bridge_concrete" if paved else "bridge_timber"
		var module_len := 12.0 if paved else 6.0
		var module_w := 10.0 if paved else 4.6
		for span in r.bridges:
			if not scenes.has(module_key):
				break
			var a: Array = r.points[int(span[0])]
			var b: Array = r.points[int(span[1])]
			var pa := Vector3(a[0], a[1], a[2])
			var pb := Vector3(b[0], b[1], b[2])
			var flat := Vector3(pb.x - pa.x, 0, pb.z - pa.z)
			var length := flat.length() + 8.0
			var dir := flat.normalized()
			var n := maxi(1, ceili(length / module_len))
			var step := length / n
			# WORLD-PLAYTEST-01: the deck follows the road across the span (the road surface
			# runs straight from one end RoadPoint to the other). A level deck at the higher
			# end left the lower end of a sloping bridge metres above the road, with the road
			# visible beside and under it.
			var grade := (pb.y - pa.y) / maxf(flat.length(), 0.1)
			var lift := 0.12 if paved else 0.05
			var basis := Basis.looking_at(dir, Vector3.UP)
			basis = basis * Basis(Vector3.RIGHT, atan(grade))
			var start := (pa + pb) * 0.5 - dir * length * 0.5
			var br := Node3D.new()
			br.name = "Bridge_%02d" % n_br
			root.add_child(br)
			br.owner = scene_owner
			for k in n:
				var m: Node3D = scenes[module_key].instantiate()
				m.name = "Module_%d" % k
				var c := start + dir * (step * (k + 0.5))
				var cy := (pa.y + pb.y) * 0.5 + grade * (step * (k + 0.5) - length * 0.5) + lift
				# Local-axis scale (Basis.scaled() would scale in world axes and shear the deck).
				m.transform = Transform3D(basis * Basis.from_scale(Vector3(deck_w / module_w, 1.0, step / module_len / cos(atan(grade)))), Vector3(c.x, cy, c.z))
				br.add_child(m)
				m.owner = scene_owner
				# Wall piers at every second joint (paved), under the girders.
				if paved and scenes.has("bridge_pier") and k > 0 and k % 2 == 0:
					var pier: Node3D = scenes["bridge_pier"].instantiate()
					var j := start + dir * (step * k)
					var jy := (pa.y + pb.y) * 0.5 + grade * (step * k - length * 0.5) + lift
					# Piers stand upright under the sloping deck.
					pier.transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis.from_scale(Vector3(deck_w / module_w, 1.0, 1.0)), Vector3(j.x, jy, j.z))
					br.add_child(pier)
					pier.owner = scene_owner
			n_br += 1
		if scenes.has("culvert"):
			for k in r.get("culverts", []):
				var i := int(k)
				var p := Vector3(r.points[i][0], r.points[i][1], r.points[i][2])
				var q: Array = r.points[mini(i + 1, r.points.size() - 1)]
				var t := Vector3(q[0] - p.x, 0, q[2] - p.z).normalized()
				var side := Vector3(-t.z, 0, t.x)
				for sgn: float in [-1.0, 1.0]:
					var o := p + side * sgn * (deck_w * 0.5 + 2.5)
					o.y = terrain.data.get_height(o)
					if is_nan(o.y):
						continue
					var cv: Node3D = scenes["culvert"].instantiate()
					cv.name = "Culvert_%03d" % n_cv
					# The culvert mouth faces its local +Z: point it away from the road.
					cv.transform = Transform3D(Basis.looking_at(-side * sgn, Vector3.UP), o - Vector3(0, 0.15, 0))
					root.add_child(cv)
					cv.owner = scene_owner
					n_cv += 1
	print("ReferenceWorldBuilder: placed %d bridges and %d culvert ends" % [n_br, n_cv])


# ------------------------------------------------------------------------------
# Vegetation
# ------------------------------------------------------------------------------

func build_mask() -> VegetationMask:
	var hs := config.half_size()
	var texel := maxf(2.0, ceilf(hs * 2.0 / 4096.0))
	return VegetationMask.build(hs, texel, road_polylines, road_widths, [], MASK_ROAD_MARGIN_M, MASK_EDGE_M)


func ensure_vegetation_nodes(scene_owner: Node) -> void:
	super.ensure_vegetation_nodes(scene_owner)
	var lib_path := (config as ReferenceWorldConfig).vegetation_library_path
	if ResourceLoader.exists(lib_path):
		vegetation.library = load(lib_path)
	if grass:
		_setup_grass_tufts()


## Per-world grass look on the unchanged GrassLayer: crossed tuft cards with a meadow
## texture instead of the WORLD-TECH-02 ribbon blade, smaller scale, and no grass under
## closed canopy (the shared resources in assets/vegetation stay as they are).
func _setup_grass_tufts() -> void:
	var dir := "res://assets/environment/"
	var mesh_path := dir + "meshes/grass_tuft.res"
	var mat_path := dir + "materials/grass_tuft.tres"
	var proc_path := dir + "materials/grass_process_ref.tres"
	if not ResourceLoader.exists(mesh_path):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 3:
			var a := k * PI / 3.0
			var s := Vector3(cos(a), 0, sin(a)) * 0.5
			var n := Vector3(-sin(a), 0, cos(a))
			var quad := [[-s + Vector3(0, -0.45, 0), Vector2(0, 1)], [s + Vector3(0, -0.45, 0), Vector2(1, 1)],
				[s + Vector3(0, 0.55, 0), Vector2(1, 0)], [-s + Vector3(0, 0.55, 0), Vector2(0, 0)]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n)
				st.set_uv(quad[idx][1])
				st.add_vertex(quad[idx][0])
		ResourceSaver.save(st.commit(), mesh_path)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/environment/grass_tuft.gdshader")
	sm.set_shader_parameter("tuft_tex", load(dir + "textures/grass_tuft_alb.png"))
	sm.set_shader_parameter("forest_tex", load(dir + "textures/dwarf_shrub_alb.png"))
	ResourceSaver.save(sm, mat_path)
	var pm: ShaderMaterial = (load("res://assets/vegetation/grass_process_material.tres") as ShaderMaterial).duplicate(true)
	pm.set_shader_parameter("min_scale", Vector3(0.45, 0.32, 0.45))
	pm.set_shader_parameter("max_scale", Vector3(0.75, 0.6, 0.75))
	pm.set_shader_parameter("clod_scale_boost", 0.35)
	# Keep ~45 % of the tufts under closed canopy (they render as dwarf shrubs there).
	pm.set_shader_parameter("forest_thinning", 0.55)
	ResourceSaver.save(pm, proc_path)
	grass.mesh = load(mesh_path)
	grass.mesh_material_override = load(mat_path)
	grass.process_material = load(proc_path)


func scatter_vegetation() -> void:
	if road_polylines.is_empty():
		_collect_road_polylines()
	prepare_scatter()
	super.scatter_vegetation()


## Shared state for _scatter_cell_task: road indexes, loaded maps and the planned
## buildings/props (also used by tools/test_vegetation.gd before re-scattering a cell).
func prepare_scatter() -> void:
	if road_polylines.is_empty():
		_collect_road_polylines()
	_sc_major = _RoadIndex.new(_major_polylines, 32.0)
	_sc_road = _RoadIndex.new(road_polylines, 32.0)
	_ref() # load the maps on this thread before the workers read them
	_plan_props()
	# super() cleared only the legacy Terrain3D ids; nothing else is stored there.


## Deterministic placement of settlement buildings (houses, barns, sheds facing the
## nearest road), mailboxes, road snow poles and skigard fences. Stored per vegetation
## cell and appended in _scatter_cell_task, so they stream like everything else.
func _plan_props() -> void:
	_props_by_cell.clear()
	_bld_by_cell.clear()
	var gen := _ref()
	var data := terrain.data
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([config.world_seed, "props"])
	var sites = _json("sites.json")
	var placed: Array = [] # [Vector2, radius]
	var counts := {}
	var house_tints := [Color(1, 1, 1), Color(1, 1, 1), Color(1.0, 0.86, 0.52), Color(0.95, 0.45, 0.36), Color(0.82, 0.86, 0.9)]
	for st in sites.settlements:
		var c := Vector2(st.pos[0], st.pos[2])
		var r: float = st.radius_m
		var town: bool = st.kind == "town"
		# Towns: one building per ~1,500 m^2 of the core, villages one per ~3,000 m^2.
		var target := int(PI * r * r / (1500.0 if town else 3000.0))
		var tries := 0
		var n := 0
		while n < target and tries < target * 40:
			tries += 1
			var a := rng.randf() * TAU
			var dist := sqrt(rng.randf()) * r * (0.95 if town else 1.15)
			var p2 := c + Vector2(cos(a), sin(a)) * dist
			var p := Vector3(p2.x, 0, p2.y)
			var d := _sc_road.distance(p)
			if d < 9.0 or d > (26.0 if town else 40.0):
				continue
			var nrm := data.get_normal(p)
			if not nrm.is_finite() or nrm.y < 0.95 or gen.info_at(p.x, p.z).a > 0.1:
				continue
			var roll := rng.randf()
			var mesh_id := M_HOUSE
			var rad := 9.0
			if roll > (0.85 if town else 0.5):
				mesh_id = M_BARN if roll < (0.9 if town else 0.82) else M_SHED
				rad = 13.0 if mesh_id == M_BARN else 4.5
			var ok := true
			for q in placed:
				if p2.distance_to(q[0]) < rad + q[1] + 3.0:
					ok = false
					break
			if not ok:
				continue
			# Face the road: long axis parallel to it (gradient of the road distance).
			var gx := _sc_road.distance(p + Vector3(2, 0, 0)) - _sc_road.distance(p - Vector3(2, 0, 0))
			var gz := _sc_road.distance(p + Vector3(0, 0, 2)) - _sc_road.distance(p - Vector3(0, 0, 2))
			var g2 := Vector2(gx, gz)
			# Degenerate gradient (equidistant to two roads): same yaw (0) as before, no warning.
			var away := g2.normalized() if g2.length_squared() > 1e-8 else Vector2(0, 1)
			var yaw := atan2(away.x, away.y) + (PI * 0.5 if rng.randf() < 0.5 else 0.0)
			p.y = data.get_height(p) - 0.05
			var col: Color = house_tints[rng.randi() % house_tints.size()] if mesh_id == M_HOUSE else _tint(rng, 0.06)
			var xf := Transform3D(Basis(Vector3.UP, yaw), p)
			_add_prop(mesh_id, xf, col)
			placed.append([p2, rad])
			_add_building(p2, rad)
			n += 1
			counts[mesh_id] = counts.get(mesh_id, 0) + 1
			# Mailbox at the road edge for houses.
			if mesh_id == M_HOUSE and rng.randf() < 0.6:
				var mb := p2 - away * (d - 6.5)
				var mp := Vector3(mb.x, data.get_height(Vector3(mb.x, 0, mb.y)), mb.y)
				if mp.is_finite():
					_add_prop(M_MAILBOX, Transform3D(Basis(Vector3.UP, yaw), mp), Color.WHITE)
	# Snow poles along paved roads and fences near settlements.
	var data_r = _json("roads.json")
	for rd in data_r.roads:
		if rd["class"] == "street":
			continue
		var spacing := 50.0 if rd.mesh else 75.0
		var off: float = float(rd.lane_m) * float(rd.lanes) * 0.5 + float(rd.shoulder_m) + 0.9
		var acc := 0.0
		var side := 1.0
		var pts: Array = rd.points
		var in_bridge := PackedByteArray()
		in_bridge.resize(pts.size())
		for span in rd.bridges:
			for k in range(int(span[0]) - 2, int(span[1]) + 3):
				if k >= 0 and k < pts.size():
					in_bridge[k] = 1
		for i in range(1, pts.size()):
			var a3 := Vector3(pts[i - 1][0], pts[i - 1][1], pts[i - 1][2])
			var b3 := Vector3(pts[i][0], pts[i][1], pts[i][2])
			var seg := Vector2(b3.x - a3.x, b3.z - a3.z)
			acc += seg.length()
			if acc < spacing or in_bridge[i]:
				continue
			acc = 0.0
			side = -side
			var t := seg.normalized()
			var nrm2 := Vector2(-t.y, t.x) * side
			var q := Vector3(b3.x + nrm2.x * off, 0, b3.z + nrm2.y * off)
			q.y = data.get_height(q)
			if not is_finite(q.y):
				continue
			_add_prop(M_ROADPOST, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), q), Color.WHITE)
			counts[M_ROADPOST] = counts.get(M_ROADPOST, 0) + 1
			# Skigard along roads close to settlements (every ~4 m section, both sides).
			if _settle_near(gen, q) and rng.randf() < 0.5:
				var yaw := atan2(t.x, t.y)
				for k in range(-5, 6):
					var f2 := Vector2(b3.x, b3.z) + t * (k * 4.0) + Vector2(-t.y, t.x) * side * (off + 3.5)
					var fp := Vector3(f2.x, 0, f2.y)
					if _near_building(fp, 3.0):
						continue
					fp.y = data.get_height(fp)
					if is_finite(fp.y):
						_add_prop(M_FENCE, Transform3D(Basis(Vector3.UP, yaw), fp), _tint(rng, 0.08))
						counts[M_FENCE] = counts.get(M_FENCE, 0) + 1
	print("ReferenceWorldBuilder: planned props ", counts)


func _settle_near(gen: ReferenceTerrainGenerator, p: Vector3) -> bool:
	return gen.info_at(p.x, p.z).b > 0.05 or gen.vegetation_at(p.x, p.z).r < 0.05 and gen.info_at(p.x, p.z).g > 0.5


func _add_prop(mesh_id: int, xf: Transform3D, col: Color) -> void:
	var cell := Vector2i(floori(xf.origin.x / CELL_M), floori(xf.origin.z / CELL_M))
	if not _props_by_cell.has(cell):
		_props_by_cell[cell] = []
	_props_by_cell[cell].append([mesh_id, xf, col])


func _add_building(p: Vector2, r: float) -> void:
	var cell := Vector2i(floori(p.x / CELL_M), floori(p.y / CELL_M))
	if not _bld_by_cell.has(cell):
		_bld_by_cell[cell] = []
	_bld_by_cell[cell].append([p, r])


func _near_building(p: Vector3, margin: float) -> bool:
	if _bld_by_cell.is_empty():
		return false
	var q := Vector2(p.x, p.z)
	var cell := Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for b in _bld_by_cell.get(cell + Vector2i(dx, dz), []):
				if q.distance_to(b[0]) < b[1] + margin:
					return true
	return false


## One cell of scatter (worker thread, read-only access to shared data).
func _scatter_cell_task(i: int) -> void:
	var cell := _sc_cells[i]
	var gen := _gen as ReferenceTerrainGenerator
	var data := terrain.data
	var cfg := _sc_cfg
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cfg.seed, cell.x, cell.y])
	var by_mesh := {}
	var x0 := cell.x * CELL_M
	var z0 := cell.y * CELL_M
	var x1 := x0 + CELL_M
	var z1 := z0 + CELL_M
	var lim := _sc_hs
	var cos_tree := _sc_max_slope

	# Trees.
	var s: float = cfg.tree_s
	var z := ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.48, 0.48) * s, 0, z + rng.randf_range(-0.48, 0.48) * s)
			x += s
			var roll := rng.randf()
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var v := gen.vegetation_at(p.x, p.z)
			var info := gen.info_at(p.x, p.z)
			var dens := v.r
			if info.b > 0.5:
				# Garden and street trees in settlements (kept clear of the buildings).
				dens = 0.14
			if roll > dens or info.a > 0.25:
				continue
			if _sc_road.distance(p) < 5.0 or _sc_major.distance(p) < 9.0 or _near_building(p, 9.0):
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < cos_tree:
				continue
			p.y = data.get_height(p) - 0.15
			var sp := rng.randf()
			var mesh_id := M_SPRUCE_A
			var smin := 0.7
			var smax := 1.25
			if sp < v.g:
				mesh_id = M_PINE_A if rng.randf() < 0.75 else M_PINE_B
				smin = 0.8
				smax = 1.25
			elif sp < v.g + v.b:
				mesh_id = M_BIRCH_A if rng.randf() < 0.6 else M_BIRCH_B
				smin = 0.75
				smax = 1.2
			else:
				# Smaller spruce at forest edges and as understorey.
				mesh_id = M_SPRUCE_B if (dens < 0.5 and rng.randf() < 0.5) or rng.randf() < 0.18 else M_SPRUCE_A
				smin = 0.65
				smax = 1.3
			# Trees near the treeline and on rock grow smaller.
			var stunt := 1.0 - 0.35 * info.r
			VegetationChunk.append_to(by_mesh, mesh_id, _xf(rng, p, smin * stunt, smax * stunt, Vector3.UP), _tint(rng, 0.1))
		z += s

	# Understorey: juniper, deciduous shrubs, ferns; also along roads and field edges.
	s = cfg.bush_s
	z = ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var v := gen.vegetation_at(p.x, p.z)
			var info := gen.info_at(p.x, p.z)
			if info.a > 0.25 or info.b > 0.6 or info.g > 0.5:
				continue
			var d := _sc_road.distance(p)
			if d < 4.0 or _sc_major.distance(p) < 7.0:
				continue
			var edge := v.r * (1.0 - v.r) * 4.0 # 1 at half density
			var c_jun := 0.06 + 0.25 * v.g * edge + 0.15 * info.r * (1.0 - v.r)
			var c_shrub := 0.04 + 0.3 * v.a * (1.0 - info.r) + 0.2 * edge * v.b + (0.35 if d < 14.0 else 0.0)
			var c_fern := 0.25 * v.r * (1.0 - v.g) * (1.0 - info.r)
			var roll := rng.randf()
			var mesh_id := -1
			if roll < c_jun:
				mesh_id = M_JUNIPER
			elif roll < c_jun + c_shrub:
				mesh_id = M_SHRUB
			elif roll < c_jun + c_shrub + c_fern:
				mesh_id = M_FERN
			if mesh_id < 0:
				continue
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < 0.72:
				continue
			p.y = data.get_height(p) - 0.05
			VegetationChunk.append_to(by_mesh, mesh_id, _xf(rng, p, 0.6, 1.4, Vector3.UP), _tint(rng, 0.12))
		z += s

	# Deadwood in the forest: fallen logs and stumps.
	s = 15.0
	z = ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var v := gen.vegetation_at(p.x, p.z)
			if v.r < 0.45 or _sc_road.distance(p) < 5.0 or _sc_major.distance(p) < 8.0:
				continue
			var roll := rng.randf()
			var n := data.get_normal(p)
			if not n.is_finite() or n.y < 0.8:
				continue
			p.y = data.get_height(p)
			if roll < 0.16:
				p.y -= 0.12
				VegetationChunk.append_to(by_mesh, M_LOG, _xf(rng, p, 0.7, 1.25, n), _tint(rng, 0.1))
			elif roll < 0.34:
				p.y -= 0.05
				VegetationChunk.append_to(by_mesh, M_STUMP, _xf(rng, p, 0.7, 1.3, Vector3.UP), _tint(rng, 0.1))
		z += s

	# Rocks: erratic boulders in forests and pastures, small stones, outcrops on rocky ground.
	s = cfg.rock_s
	z = ceilf(z0 / s) * s
	while z < z1:
		var x := ceilf(x0 / s) * s
		while x < x1:
			var p := Vector3(x + rng.randf_range(-0.5, 0.5) * s, 0, z + rng.randf_range(-0.5, 0.5) * s)
			x += s
			if absf(p.x) > lim or absf(p.z) > lim:
				continue
			var info := gen.info_at(p.x, p.z)
			if info.a > 0.2 or info.b > 0.5 or _sc_road.distance(p) < 6.0 or _sc_major.distance(p) < 9.0:
				continue
			var n := data.get_normal(p)
			if not n.is_finite():
				continue
			var steep := 1.0 - n.y
			var field := info.g > 0.5
			var c_boulder := 0.02 if field else 0.05 + 0.25 * info.r
			var c_small := 0.0 if field else 0.06 + 0.35 * info.r + steep * 1.5
			var c_out := 0.0 if field else info.r * 0.35 * smoothstep(0.03, 0.12, steep)
			var roll := rng.randf()
			p.y = data.get_height(p)
			if roll < c_out:
				p.y -= 0.6
				VegetationChunk.append_to(by_mesh, M_OUTCROP, _xf(rng, p, 0.7, 1.8, n.lerp(Vector3.UP, 0.4).normalized()), _tint(rng, 0.06))
			elif roll < c_out + c_boulder:
				p.y -= 0.35
				VegetationChunk.append_to(by_mesh, M_BOULDER_A if rng.randf() < 0.5 else M_BOULDER_B, _xf(rng, p, 0.5, 1.7, Vector3.UP), _tint(rng, 0.06))
			elif roll < c_out + c_boulder + c_small:
				p.y -= 0.1
				VegetationChunk.append_to(by_mesh, M_ROCKS_SMALL, _xf(rng, p, 0.7, 1.4, n), _tint(rng, 0.06))
		z += s

	for item in _props_by_cell.get(cell, []):
		VegetationChunk.append_to(by_mesh, item[0], item[1], item[2])

	_sc_lock.lock()
	_sc_results[i] = by_mesh
	_sc_lock.unlock()
