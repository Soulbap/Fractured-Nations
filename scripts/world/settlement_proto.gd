## WORLD-SETTLEMENT-01: an isolated settlement prototype on top of the canonical world.
##
## Started with `-- --settlement-proto=<name>` (e.g. haugen); without the flag nothing here runs and
## the world is exactly the canonical one. The prototype is data in res://worlds/settlement_proto/:
##   <name>.json            local roads (removed world streets by name, new roads in roads.json form),
##                          written by tools/settlement_proto/design_<name>.py;
##   <name>.overrides.json  the world overrides file used instead of the canonical one (old settlement
##                          buildings removed, new ones added), written by build_overrides.gd.
## The roads go into the one RoadNetwork (load_world), the buildings through the one WorldOverrides; the
## ground paint is changed in memory only (Terrain3D region data is never saved), no terrain is graded.
class_name SettlementProto
extends RefCounted

const DIR := "res://worlds/settlement_proto/"

const TEX_GRASS := 0
const TEX_DIRT := 2
const TEX_FIELD := 3
const TEX_GRAVEL := 5
const TEX_ASPHALT := 7


## Name of the active prototype ("" = none).
static func active() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--settlement-proto="):
			return a.get_slice("=", 1)
	return ""


static func data() -> Dictionary:
	var n := active()
	if n.is_empty() or not FileAccess.file_exists(DIR + n + ".json"):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + n + ".json"))
	return d if d is Dictionary else {}


static func overrides_path() -> String:
	var n := active()
	return "" if n.is_empty() else DIR + n + ".overrides.json"


## roads.json data with the prototype applied. Removed roads keep their slot (empty points) so the
## indices, road keys and bridge ids of all other roads stay the same.
static func patch_roads(roads: Dictionary) -> Dictionary:
	var d := data()
	if d.is_empty():
		return roads
	var removed: Array = d.get("remove_roads", [])
	for r: Dictionary in roads.roads:
		if removed.has(r.name):
			r.points = []
			r.bridges = []
	for r: Dictionary in d.get("roads", []):
		roads.roads.append(r)
	print("SettlementProto: %s, %d world streets removed, %d local roads added" % [active(), removed.size(), d.get("roads", []).size()])
	return roads


## Ground paint of the prototype, in memory. The generator gave every settlement a round patch of mown
## grass with a pale colour-map tint (the disc that gave the old villages their geometric outline). That
## disc, and the removed streets, are filled from the fields round it: each disc vertex copies texture and
## tint of the nearest of a ring of samples just outside (wavy Voronoi parcels), mown grass only remains as
## gardens round the new buildings. The new roads get asphalt or gravel with worn verges (same encoding as
## tools/terrain_ref/generate.py).
static func paint(terrain: Terrain3D, world_roads: Dictionary) -> void:
	var d := data()
	if d.is_empty() or terrain == null or terrain.data == null:
		return
	var t0 := Time.get_ticks_msec()
	var sp: float = terrain.get_vertex_spacing()
	var center := Vector2(d.center[0], d.center[1])
	var clear_r: float = float(d.clear_radius_m) + 30.0
	var removed: Array = d.get("remove_roads", [])
	var old_streets: Array = [] # [PackedVector2Array, half width]
	var keep_roads: Array = []
	for r: Dictionary in world_roads.roads:
		var pts := _line(r.points)
		if pts.is_empty():
			continue
		var hw := (float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)) * 0.5
		if removed.has(r.name):
			old_streets.append([pts, hw])
		elif _near(pts, center, clear_r + 700.0):
			keep_roads.append([pts, hw])
	var new_roads: Array = []
	for r: Dictionary in d.roads:
		new_roads.append([_line(r.points), (float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)) * 0.5, r.paint])
	# Area to visit: the settlement disc plus every new road.
	var rect := Rect2(center - Vector2(clear_r, clear_r), Vector2(clear_r, clear_r) * 2.0)
	for r in new_roads:
		for p: Vector2 in r[0]:
			rect = rect.expand(p)
	rect = rect.grow(12.0)
	var g := _Grid.new(rect, sp)
	# Distance fields (m outside the surface), rasterised along the lines only.
	for r in keep_roads:
		g.stamp("keep", r[0], r[1], 8.0)
	for r in old_streets:
		g.stamp("old", r[0], r[1], 6.0)
	for i in new_roads.size():
		g.stamp("new", new_roads[i][0], new_roads[i][1], 4.0, i)
	for b: Dictionary in d.buildings:
		g.stamp("garden", PackedVector2Array([Vector2(b.x, b.z), Vector2(b.x, b.z) + Vector2(0.01, 0)]), 0.0, 45.0)
	var d_keep: PackedFloat32Array = g.fields.keep
	var d_old: PackedFloat32Array = g.fields.old
	var d_new: PackedFloat32Array = g.fields.new
	var garden: PackedFloat32Array = g.fields.garden
	var which: PackedInt32Array = g.tag
	# Ring of samples outside the disc (open ground only; forest and roads are skipped).
	var seeds: Array = [] # [Vector2, control, Color]
	for i in 18:
		var a := TAU * (i + 0.6 * _noise(i, 7)) / 18.0
		var dir := Vector2(cos(a), sin(a))
		for step in 90:
			var q := center + dir * (100.0 + step * 3.0)
			var pos := Vector3(q.x, 0.0, q.y)
			var c: Color = terrain.data.get_color(pos)
			var ctl: int = terrain.data.get_control(pos)
			var b := ctl >> 27 & 0x1F
			if _disc(c):
				continue
			if b == TEX_FIELD or b == TEX_GRASS:
				var gk := g.index(q)
				if gk < 0 or g.fields.keep[gk] > 6.0:
					seeds.append([q + dir * 12.0, ctl, c])
			break
	var regions := {}
	var changed := 0
	for k in d_new.size():
		var xi := g.x0 + k % g.w
		var zi := g.z0 + k / g.w
		var q := Vector2(xi * sp, zi * sp)
		var pos := Vector3(q.x, 0.0, q.y)
		var cur: int = terrain.data.get_control(pos)
		var n := _noise(xi, zi)
		var val := cur
		var col: Color = terrain.data.get_color(pos)
		var new_col := col
		# 1. The disc and the old streets: the field of the nearest outside sample, gardens round houses.
		if not seeds.is_empty() and d_keep[k] > 3.0 and (_disc(col) or d_old[k] <= 4.5) and q.distance_to(center) < clear_r + 60.0:
			var qw := q + Vector2(sin(q.y / 37.0) + 0.5 * sin(q.x / 13.0), cos(q.x / 41.0) + 0.5 * cos(q.y / 17.0)) * 14.0
			var best: Array = seeds[0]
			for sd: Array in seeds:
				if qw.distance_squared_to(sd[0]) < qw.distance_squared_to(best[0]):
					best = sd
			val = (cur & 0x3FFF) | (int(best[1]) & ~0x3FFF)
			new_col = best[2]
			new_col.a = col.a
			var garden_w := 1.0 - smoothstep(14.0, 30.0, garden[k] + 8.0 * (n - 0.5))
			if garden_w > 0.02:
				val = _control(val, TEX_GRASS, val >> 27 & 0x1F, clampf(0.15 + 0.25 * n + (1.0 - garden_w) * 0.6, 0.0, 1.0))
				new_col = new_col.lerp(Color(0.66, 0.78, 0.52, col.a), garden_w * 0.6)
		# 3. New roads: surface and worn verge.
		if d_new[k] < 3.5:
			var hw: float = new_roads[which[k]][1]
			if d_new[k] < -0.3 + 0.4 * n:
				if new_roads[which[k]][2] == "asphalt":
					val = _control(cur, TEX_ASPHALT, TEX_GRAVEL, clampf(0.1 + 0.1 * n, 0.0, 1.0))
				else:
					val = _control(cur, TEX_DIRT, TEX_GRAVEL, clampf(0.55 + 0.12 * n, 0.0, 0.68))
			else:
				var vb := 1.0 - smoothstep(hw - 0.5, hw + 3.0, d_new[k] + hw)
				val = _control(val, val >> 27 & 0x1F, TEX_DIRT, vb * (0.6 + 0.3 * n))
		if new_col != col:
			terrain.data.set_color(pos, new_col)
			regions[terrain.data.get_region_location(pos)] = true
		if val != cur:
			terrain.data.set_control(pos, val)
			regions[terrain.data.get_region_location(pos)] = true
			changed += 1
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_CONTROL, false, false)
	terrain.data.update_maps(Terrain3DRegion.TYPE_COLOR, false, false)
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(false)
	# No particle grass on the new roads (the grass layer's exclusion mask, in memory).
	var grass := terrain.get_parent().get_node_or_null("Grass") as GrassLayer
	if grass and grass.mask and grass.mask.image:
		for r in new_roads:
			var pts: PackedVector2Array = r[0]
			for i in pts.size() - 1:
				VegetationMask._paint(grass.mask.image, grass.mask, pts[i], pts[i + 1], float(r[1]) + 0.3, 1.5)
		grass.apply_mask()
	print("SettlementProto: painted %d vertices (%d field samples) in %d ms" % [changed, seeds.size(), Time.get_ticks_msec() - t0])


## The generator's pale settlement tint in the colour map (fields and forest are far less blue).
static func _disc(c: Color) -> bool:
	return c.r > 0.74 and c.g > 0.76 and c.b > 0.68 and absf(c.r - c.g) < 0.06


static func _line(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points:
		out.append(Vector2(p[0], p[2]))
	return out


static func _near(pts: PackedVector2Array, c: Vector2, r: float) -> bool:
	for p in pts:
		if p.distance_to(c) < r:
			return true
	return false


## Vertex grid over a rect with distance fields stamped along polylines.
class _Grid:
	var x0 := 0
	var z0 := 0
	var w := 0
	var h := 0
	var sp := 1.0

	func _init(rect: Rect2, spacing: float) -> void:
		sp = spacing
		x0 = floori(rect.position.x / sp)
		z0 = floori(rect.position.y / sp)
		w = ceili(rect.end.x / sp) - x0 + 1
		h = ceili(rect.end.y / sp) - z0 + 1
		_init_fields()

	## name -> PackedFloat32Array (w * h), metres outside the nearest stamped surface.
	var fields := {}
	## Index of the nearest line stamped into "new".
	var tag := PackedInt32Array()

	func _init_fields() -> void:
		for n in ["keep", "old", "new", "garden"]:
			var f := PackedFloat32Array()
			f.resize(w * h)
			f.fill(1e9)
			fields[n] = f
		tag.resize(w * h)

	func index(q: Vector2) -> int:
		var xi := roundi(q.x / sp) - x0
		var zi := roundi(q.y / sp) - z0
		return -1 if xi < 0 or zi < 0 or xi >= w or zi >= h else zi * w + xi

	## Writes min(distance to the line - half_w) within half_w + reach of the line (tags "new" with idx).
	func stamp(name: String, pts: PackedVector2Array, half_w: float, reach: float, idx := 0) -> void:
		var f: PackedFloat32Array = fields[name]
		var band := half_w + reach
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(band, band)
			var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(band, band)
			for zi in range(maxi(floori(lo.y / sp), z0), mini(ceili(hi.y / sp), z0 + h - 1) + 1):
				for xi in range(maxi(floori(lo.x / sp), x0), mini(ceili(hi.x / sp), x0 + w - 1) + 1):
					var q := Vector2(xi * sp, zi * sp)
					var dd := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b)) - half_w
					var k := (zi - z0) * w + (xi - x0)
					if dd < f[k]:
						f[k] = dd
						if name == "new":
							tag[k] = idx
		fields[name] = f


static func _noise(x: int, z: int) -> float:
	var h := (x * 73856093) ^ (z * 19349663)
	return float(absi(h) % 1000) / 1000.0


## Same layout as StructureManager._control / the world generator.
static func _control(orig: int, base: int, over: int, blend: float) -> int:
	var b8 := clampi(roundi(blend * 255.0), 0, 255)
	return (orig & 0x3FFF) | ((base & 0x1F) << 27) | ((over & 0x1F) << 22) | (b8 << 14)
