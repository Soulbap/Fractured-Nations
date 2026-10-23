## NAV-INF-01: brings the terrain up to the road surface. The Road Generator terrain connector sinks the terrain 0.25 m under every
## road (`offset = -0.25`, a z-fighting guard), which leaves a 12-25 cm sharp lip along both edges of the road mesh collider;
## infantry (a capsule without a step) stood against it. This raises the terrain in the road footprint and its falloff to 3 cm under
## the road surface, only where it lies lower than that, and never near a bridge span (the channels under the bridges stay as built).
## Before that the terrain beside the roads is smoothed (a low-pass of the height maps blended in by distance to the road: weight 0 on
## the road bed, rising to 1 from 10 m, fading out at 45 m; nothing within 25 m of a bridge span or a culvert) because banks and
## cuts of 40-50 degrees next to the roads stopped infantry that the navmesh sent up them.
## The roads, bridges, vegetation and sources are not touched; the terrain regions are saved in place.
##
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/flush_roads.gd -- [--apply] [--scene=res://scenes/world/ref_20km.tscn]
##
## Without --apply nothing is written; the run only prints what it would change.
extends SceneTree

const BELOW_ROAD_M := 0.03
const EDGE_MARGIN_M := 1.0
const FALLOFF_M := 4.0
const BRIDGE_CLEAR_M := 8.0
const MAX_RAISE_M := 0.32


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://scenes/world/ref_20km.tscn"
	var apply := false
	var smooth := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.trim_prefix("--scene=")
		elif a == "--apply":
			apply = true
		elif a == "--no-smooth":
			smooth = false
	var root: Node3D = (load(path) as PackedScene).instantiate()
	get_root().add_child(root)
	for i in 5:
		await process_frame
	var builder: ReferenceWorldBuilder = root.get_node("WorldBuilder")
	var terrain: Terrain3D = builder.terrain
	var sp: float = terrain.vertex_spacing
	var data = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://worlds/ref_20km/source/roads.json")))
	var smoothed := _smooth_beside_roads(terrain, data, apply) if smooth else 0
	var changes := {}
	var stats := {"roads": 0, "vertices": 0, "raised": 0, "sum_raise": 0.0, "max_raise": 0.0, "skipped_bridge": 0, "skipped_other": 0}
	for r in data.roads:
		if not r.mesh:
			continue
		stats.roads += 1
		var pts: Array = r.points
		var in_bridge := PackedByteArray()
		in_bridge.resize(pts.size())
		for span in r.bridges:
			for i in range(int(span[0]), int(span[1]) + 1):
				in_bridge[i] = 1
		var half: float = float(r.lane_m) * float(r.lanes) * 0.5 + float(r.shoulder_m)
		var reach := half + EDGE_MARGIN_M + FALLOFF_M
		for i in pts.size() - 1:
			var a := Vector3(pts[i][0], pts[i][1], pts[i][2])
			var b := Vector3(pts[i + 1][0], pts[i + 1][1], pts[i + 1][2])
			if in_bridge[i] == 1 or in_bridge[i + 1] == 1:
				continue
			var lo := Vector2(minf(a.x, b.x) - reach, minf(a.z, b.z) - reach)
			var hi := Vector2(maxf(a.x, b.x) + reach, maxf(a.z, b.z) + reach)
			var x := ceilf(lo.x / sp) * sp
			while x <= hi.x:
				var z := ceilf(lo.y / sp) * sp
				while z <= hi.y:
					var q := Vector2(x, z)
					var a2 := Vector2(a.x, a.z)
					var b2 := Vector2(b.x, b.z)
					var c := Geometry2D.get_closest_point_to_segment(q, a2, b2)
					var d := q.distance_to(c)
					if d <= reach:
						var seg := a2.distance_to(b2)
						var t := 0.0 if seg < 0.001 else c.distance_to(a2) / seg
						var road_y := lerpf(a.y, b.y, t)
						var key := Vector2i(roundi(x / sp), roundi(z / sp))
						var w := 1.0 if d <= half + EDGE_MARGIN_M else 1.0 - (d - half - EDGE_MARGIN_M) / FALLOFF_M
						var cur: Vector3 = changes.get(key, Vector3(0.0, -INF, 0.0))
						# Keep the strongest claim on a vertex (nearest road): weight, target height.
						if w > cur.x:
							changes[key] = Vector3(w, road_y - BELOW_ROAD_M, 0.0)
					z += sp
				x += sp
	# Bridge clearance: nothing within BRIDGE_CLEAR_M of a span's deck points.
	var bridge_pts: Array[Vector2] = []
	for r in data.roads:
		for span in r.bridges:
			for i in range(int(span[0]), int(span[1]) + 1):
				bridge_pts.append(Vector2(r.points[i][0], r.points[i][2]))
	for key: Vector2i in changes.keys():
		stats.vertices += 1
		var p := Vector3(key.x * sp, 0.0, key.y * sp)
		var near_bridge := false
		for bp in bridge_pts:
			if bp.distance_squared_to(Vector2(p.x, p.z)) < pow(BRIDGE_CLEAR_M + 6.0, 2.0):
				near_bridge = true
				break
		if near_bridge:
			stats.skipped_bridge += 1
			continue
		var h: float = terrain.data.get_height(p)
		var ch: Vector3 = changes[key]
		var rise: float = ch.y - h
		if is_nan(h) or rise <= 0.02 or rise > MAX_RAISE_M:
			stats.skipped_other += 1
			continue
		var delta: float = rise * ch.x
		stats.raised += 1
		stats.sum_raise += delta
		stats.max_raise = maxf(stats.max_raise, delta)
		if apply:
			terrain.data.set_height(p, h + delta)
	stats["smoothed_vertices"] = smoothed
	print("FLUSH ", JSON.stringify(stats), " mean_raise=", snappedf(stats.sum_raise / maxf(stats.raised, 1.0), 0.001))
	if apply:
		terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, true, false)
		terrain.data.calc_height_range(true)
		terrain.data.save_directory(terrain.data_directory)
		print("FLUSH saved terrain data to ", terrain.data_directory)
	quit(0)


const SMOOTH_FROM_M := 10.0
const SMOOTH_FULL_M := 14.0
const SMOOTH_TO_M := 45.0
const SMOOTH_CLEAR_M := 25.0
const EDGE_PX := 6


func _smooth_beside_roads(terrain: Terrain3D, data: Dictionary, apply: bool) -> int:
	var sp: float = terrain.vertex_spacing
	var size: int = terrain.get_region_size()
	var span := float(size) * sp
	# 1. Weight per vertex (strongest claim of any road), as a dictionary region -> PackedFloat32Array.
	var weights := {}
	var keep_out: Array[Vector2] = []
	for r in data.roads:
		for span_b in r.bridges:
			for i in range(int(span_b[0]), int(span_b[1]) + 1):
				keep_out.append(Vector2(r.points[i][0], r.points[i][2]))
		for ci in r.culverts:
			keep_out.append(Vector2(r.points[int(ci)][0], r.points[int(ci)][2]))
	for r in data.roads:
		if not r.mesh:
			continue
		var half: float = float(r.lane_m) * float(r.lanes) * 0.5 + float(r.shoulder_m)
		var pts: Array = r.points
		for i in pts.size() - 1:
			var a2 := Vector2(pts[i][0], pts[i][2])
			var b2 := Vector2(pts[i + 1][0], pts[i + 1][2])
			var lo := Vector2(minf(a2.x, b2.x) - SMOOTH_TO_M, minf(a2.y, b2.y) - SMOOTH_TO_M)
			var hi := Vector2(maxf(a2.x, b2.x) + SMOOTH_TO_M, maxf(a2.y, b2.y) + SMOOTH_TO_M)
			var x := ceilf(lo.x / sp) * sp
			while x <= hi.x:
				var z := ceilf(lo.y / sp) * sp
				while z <= hi.y:
					var q := Vector2(x, z)
					var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a2, b2))
					if d <= SMOOTH_TO_M:
						var ix := roundi(x / sp)
						var iz := roundi(z / sp)
						var loc := Vector2i(floori(float(ix) / size), floori(float(iz) / size))
						var px := ix - loc.x * size
						var pz := iz - loc.y * size
						if px >= EDGE_PX and pz >= EDGE_PX and px < size - EDGE_PX and pz < size - EDGE_PX:
							if not weights.has(loc):
								var arr := PackedFloat32Array()
								arr.resize(size * size)
								arr.fill(INF)
								weights[loc] = arr
							var wa: PackedFloat32Array = weights[loc]
							# The distance to the nearest road (the road's own half width taken off).
							if d - half < wa[pz * size + px]:
								wa[pz * size + px] = d - half
								weights[loc] = wa
					z += sp
				x += sp
	for loc: Vector2i in weights.keys():
		var wa: PackedFloat32Array = weights[loc]
		for k in wa.size():
			var e := wa[k]
			var w := 0.0
			if e < INF:
				if e < SMOOTH_FROM_M:
					w = 0.0
				elif e < SMOOTH_FULL_M:
					w = (e - SMOOTH_FROM_M) / (SMOOTH_FULL_M - SMOOTH_FROM_M)
				elif e > SMOOTH_TO_M - 20.0:
					w = maxf(0.0, (SMOOTH_TO_M - e) / 20.0)
				else:
					w = 1.0
			wa[k] = w
		weights[loc] = wa
	# 2. Clear the vertices near bridges and culverts.
	var cleared := 0
	for loc: Vector2i in weights.keys():
		var wa: PackedFloat32Array = weights[loc]
		for k in keep_out:
			var ix0 := roundi(k.x / sp) - loc.x * size
			var iz0 := roundi(k.y / sp) - loc.y * size
			var rad := ceili(SMOOTH_CLEAR_M / sp)
			for dz in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var px := ix0 + dx
					var pz := iz0 + dz
					if px >= 0 and pz >= 0 and px < size and pz < size and Vector2(dx, dz).length() * sp <= SMOOTH_CLEAR_M:
						if wa[pz * size + px] > 0.0:
							wa[pz * size + px] = 0.0
							cleared += 1
		weights[loc] = wa
	# 3. Blend each region's height map towards its low-pass (down and up again, twice).
	var total := 0
	var max_change := 0.0
	for loc: Vector2i in weights.keys():
		var region = terrain.data.get_region(loc)
		if region == null:
			continue
		var img: Image = region.get_height_map()
		var low := img.duplicate() as Image
		for pass_n in 2:
			low.resize(size / 8, size / 8, Image.INTERPOLATE_BILINEAR)
			low.resize(size, size, Image.INTERPOLATE_BILINEAR)
		var wa: PackedFloat32Array = weights[loc]
		for pz in size:
			for px in size:
				var w := wa[pz * size + px]
				if w > 0.0:
					var h0 := img.get_pixel(px, pz).r
					var h1 := low.get_pixel(px, pz).r
					var nh := lerpf(h0, h1, w)
					max_change = maxf(max_change, absf(nh - h0))
					total += 1
					if apply:
						img.set_pixel(px, pz, Color(nh, 0.0, 0.0, 1.0))
		if apply:
			region.set_modified(true)
			terrain.data.set_region_modified(loc, true)
	print("FLUSH smoothing: regions=", weights.size(), " vertices=", total, " cleared_near_bridges_culverts=", cleared, " max_change_m=", snappedf(max_change, 0.01))
	if apply:
		terrain.data.update_maps(Terrain3DRegion.TYPE_HEIGHT, true, false)
	return total
