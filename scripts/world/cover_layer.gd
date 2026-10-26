## WORLD-COVER-01 natural cover layer: boulders, rock groups and ridges, thick fallen logs, wind-thrown root plates, dry stone
## field walls and timber stacks placed over the world by rules, as a read-only WorldOverrides layer
## (res://worlds/cover/<world>.cover.json, "added" records of library ids 24-30). Like the settlement layer it never touches the
## generated chunks or the manifest; VegetationStreamer loads it under the settlement layer and the user's own overrides, so
## every system that reads vegetation - drawing, LineOfFire, InstanceColliderStreamer, StructureManager, AreaNavigation,
## CombatBrain cover search - sees the objects. `--no-natural-cover` switches it off for comparison.
##
## Built in the running game (so the terrain is the one soldiers walk: settlement heights and road shoulders applied, the road
## network with the settlement roads, water, bridges, objectives and bases known):
##   Godot.exe --path . res://scenes/game/world_ref_20km.tscn -- --scenario=dev --no-natural-cover --build-cover-layer [--area=x,z,r]
## (--no-natural-cover: the old layer must not be loaded while the new one is placed.)
## --area builds (and replaces) only that disc; the rest of the file stays.
##
## Placement, deterministic per 25 m cell (a hash of the cell): the cell's ground decides what may lie there, from the world's
## own maps (vegetation.png forest density and wetness, info.png rockiness / fields / settlement) and the terrain slope -
##   dense forest     logs, root plates, rock groups, some boulders (more on rocky ground)
##   open woodland    boulders, logs, rock groups, a few root plates
##   meadow / open    rare boulders and rock groups (open ground stays open)
##   rocky ground     ridges, boulders, rock groups
##   field edges      dry stone walls along the edge of the field (where the field map drops off)
##   forest roads     timber stacks beside the road, parallel to it
## and nothing on roads and their shoulders, in water or within 10 m of it, near bridges, inside settlements, on objective
## centres and base areas, on ground steeper than infantry walks, over an existing tree or rock, or within 8 m of another
## cover object. Objects sit on the lowest ground under their footprint (embedded, not floating).
class_name CoverLayer
extends RefCounted

const DIR := "res://worlds/cover/"
const IDS := {"boulder": 24, "rockgroup": 25, "ridge": 26, "log": 27, "rootplate": 28, "wall": 29, "timber": 30}
## Half length / half depth of each kind's footprint (m, scale 1): the box colliders' (boulder: its sphere).
const FOOT := {24: Vector2(1.15, 1.15), 25: Vector2(1.35, 0.78), 26: Vector2(2.75, 1.9), 27: Vector2(3.7, 0.38),
	28: Vector2(0.55, 1.6), 29: Vector2(3.0, 0.48), 30: Vector2(2.15, 0.88)}
const CELL := 25.0
const MIN_GAP := 8.0


static func path(world: String) -> String:
	return DIR + world + ".cover.json"


static func enabled() -> bool:
	return not "--no-natural-cover" in OS.get_cmdline_user_args()


# --- Builder -------------------------------------------------------------------------------------------------------------

var demo: CoreDemo
var stats := {}
var _veg: Image
var _info: Image
var _half := 10000.0
var _placed := {}  # 16 m hash -> [Vector2]
var _excl: Array = []  # [Vector2 centre, radius]


func _init(p_demo: CoreDemo) -> void:
	demo = p_demo


func run(args: PackedStringArray) -> void:
	var area := Rect2()
	var disc := Vector3.INF
	for a in args:
		if a.begins_with("--area="):
			var v := a.trim_prefix("--area=").split(",")
			disc = Vector3(float(v[0]), float(v[1]), float(v[2]))
	await demo.get_tree().create_timer(2.0).timeout
	if enabled():
		# The layer being rebuilt would count its own old objects as occupied ground.
		push_error("CoverLayer: build with --no-natural-cover (the current layer is loaded and would block itself)")
		print("COVER_LAYER {\"error\": \"run with --no-natural-cover\"}")
		demo.get_tree().quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var world: String = demo.config.world_name
	var src: String = demo.config.source_directory if "source_directory" in demo.config else "res://worlds/%s/source/" % world
	_veg = Image.load_from_file(ProjectSettings.globalize_path(src.path_join("vegetation.png")))
	_info = Image.load_from_file(ProjectSettings.globalize_path(src.path_join("info.png")))
	_half = demo.config.half_size()
	if disc.is_finite():
		area = Rect2(disc.x - disc.z, disc.y - disc.z, disc.z * 2.0, disc.z * 2.0)
	else:
		area = Rect2(-_half + 50.0, -_half + 50.0, _half * 2.0 - 100.0, _half * 2.0 - 100.0)
	_exclusions()
	var records := {}
	var old: Dictionary = {}
	var out_path := path(world)
	if disc.is_finite() and FileAccess.file_exists(out_path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if j is Dictionary:
			old = j.get("records", {})
			for id: String in old:
				var o: Array = old[id].transform
				if Vector2(o[9] - disc.x, o[11] - disc.y).length() > disc.z:
					records[id] = old[id]
					_mark(Vector2(o[9], o[11]))
	var n := 0
	var cx0 := floori(area.position.x / CELL)
	var cz0 := floori(area.position.y / CELL)
	var cx1 := floori(area.end.x / CELL)
	var cz1 := floori(area.end.y / CELL)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var c := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
			if disc.is_finite() and c.distance_to(Vector2(disc.x, disc.y)) > disc.z:
				continue
			var placed := _cell(Vector2i(cx, cz))
			if not placed.is_empty():
				records["c:%d_%d" % [cx, cz]] = placed
				n += 1
		if cz % 40 == 0:
			await demo.get_tree().process_frame
	n += _timber(records, area, disc)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "records": records}))
	f.close()
	stats["records"] = records.size()
	stats["new"] = n
	stats["ms"] = Time.get_ticks_msec() - t0
	print("COVER_LAYER ", JSON.stringify(stats))
	demo.get_tree().quit()


func _count(k: String) -> void:
	stats[k] = int(stats.get(k, 0)) + 1


## Objective centres (60 m) and bases (their reach + 40 m): no permanent obstacles; settlements (0.7 of their radius).
func _exclusions() -> void:
	var war := demo.sim.state.war
	for o: ObjectiveState in war.all_objectives():
		_excl.append([Vector2(o.position.x, o.position.z), 60.0])
	for b: Dictionary in demo.sim.state.construction.bases.values():
		_excl.append([Vector2(b.anchor.x, b.anchor.z), float(b.get("radius", 120.0)) + 40.0])
	var sites: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s/source/sites.json" % demo.config.world_name))
	if sites is Dictionary:
		for s: Dictionary in sites.get("settlements", []):
			_excl.append([Vector2(s.pos[0], s.pos[2]), float(s.radius_m) * 0.7])
	for p: Vector3 in demo.config.base_sites:
		_excl.append([Vector2(p.x, p.z), 260.0])


func _map(img: Image, x: float, z: float) -> Color:
	var w := img.get_width()
	var u := clampi(int((x + _half) / (_half * 2.0) * w), 0, w - 1)
	var v := clampi(int((z + _half) / (_half * 2.0) * w), 0, w - 1)
	return img.get_pixel(u, v)


static func _hash(c: Vector2i, salt: int) -> int:
	var h := (c.x * 73856093) ^ (c.y * 19349663) ^ (salt * 83492791)
	return absi(h)


## What lies in one 25 m cell (a record or {}).
func _cell(c: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(c, 3031)
	var p := Vector2((c.x + rng.randf()) * CELL, (c.y + rng.randf()) * CELL)
	var veg := _map(_veg, p.x, p.y)
	var info := _map(_info, p.x, p.y)
	var forest := veg.r
	var wet := veg.a
	var rocky := info.r
	var field := info.g
	var settled := info.b
	if settled > 0.25 or wet > 0.6:
		return {}
	# Field edges: stone walls (the field map drops off within 25 m).
	if field > 0.45:
		var lo := INF
		var dir := Vector2.ZERO
		for d: Vector2 in [Vector2(25, 0), Vector2(-25, 0), Vector2(0, 25), Vector2(0, -25)]:
			var f2 := _map(_info, p.x + d.x, p.y + d.y).g
			if f2 < lo:
				lo = f2
				dir = d
		if lo < 0.25 and rng.randf() < 0.32:
			# Along the edge: the wall's long axis is across the direction the field ends.
			var yaw := atan2(-dir.x, dir.y) + rng.randf_range(-0.12, 0.12)
			return _place(IDS.wall, p + dir.normalized() * 6.0, yaw, 1.0, rng, "wall")
		return {}
	var pick := -1
	var r := rng.randf()
	if rocky > 0.45:
		pick = IDS.ridge if r < 0.07 else (IDS.boulder if r < 0.19 else (IDS.rockgroup if r < 0.27 else -1))
	elif forest > 0.55:
		var rk := rocky * 0.12
		pick = IDS.log if r < 0.09 else (IDS.rootplate if r < 0.105 else (IDS.rockgroup if r < 0.135 + rk else (IDS.boulder if r < 0.155 + rk * 2.0 else -1)))
	elif forest > 0.2:
		var rk := rocky * 0.15
		pick = IDS.boulder if r < 0.045 + rk else (IDS.log if r < 0.095 + rk else (IDS.rockgroup if r < 0.135 + rk else (IDS.rootplate if r < 0.143 + rk else -1)))
	else:
		pick = IDS.boulder if r < 0.012 + rocky * 0.05 else (IDS.rockgroup if r < 0.022 + rocky * 0.06 else -1)
	if pick < 0:
		return {}
	var scale := rng.randf_range(0.85, 1.18) if pick in [IDS.boulder, IDS.rockgroup, IDS.ridge] else rng.randf_range(0.88, 1.1)
	return _place(pick, p, rng.randf() * TAU, scale, rng, "")


## A record for mesh id at p if the place is free and suitable ({} otherwise).
func _place(id: int, p: Vector2, yaw: float, scale: float, rng: RandomNumberGenerator, why: String) -> Dictionary:
	var foot: Vector2 = FOOT[id] * scale
	var reach := maxf(foot.x, foot.y)
	for e: Array in _excl:
		if p.distance_to(e[0]) < float(e[1]) + reach:
			_count("rejected_area")
			return {}
	if _near_placed(p, MIN_GAP + reach):
		_count("rejected_gap")
		return {}
	var roads := demo.sim.state.roads
	var n := roads.nearest(Vector3(p.x, 0, p.y), 40.0, 0, 0.0)
	if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + (6.0 if id == IDS.timber else 9.0 + reach):
		_count("rejected_road")
		return {}
	if roads.bridge_at(Vector3(p.x, 0, p.y), 60.0) != null:
		_count("rejected_bridge")
		return {}
	var st := demo.sim.structures
	# Footprint corners and centre: ground heights, water, slope, existing solids.
	var axis := Vector2(cos(yaw), -sin(yaw))
	var side := Vector2(-axis.y, axis.x)
	var lo := INF
	var hi := -INF
	for q: Vector2 in [p, p + axis * foot.x + side * foot.y, p + axis * foot.x - side * foot.y, p - axis * foot.x + side * foot.y, p - axis * foot.x - side * foot.y]:
		var h: float = demo.sim.terrain.data.get_height(Vector3(q.x, 0, q.y))
		if is_nan(h):
			return {}
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if st._wet(q.x, q.y, h + 0.1):
			_count("rejected_water")
			return {}
	if hi - lo > (0.7 if id in [IDS.wall, IDS.log, IDS.ridge, IDS.timber] else 1.1) * scale:
		_count("rejected_slope")
		return {}
	# 10 m clear of water all round.
	for k in 8:
		var q := p + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * (reach + 10.0)
		var hq: float = demo.sim.terrain.data.get_height(Vector3(q.x, 0, q.y))
		if not is_nan(hq) and st._wet(q.x, q.y, hq + 0.1):
			_count("rejected_water")
			return {}
	var nrm: Vector3 = demo.sim.terrain.data.get_normal(Vector3(p.x, 0, p.y))
	if nrm.is_finite() and nrm.y < 0.82:
		_count("rejected_slope")
		return {}
	if st.blocks_trunk(p, reach + 0.8) or st.blocks_point(p, reach + 0.5):
		_count("rejected_occupied")
		return {}
	_mark(p)
	_count("placed_%d" % id)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	var y := lo + 0.02
	var xf := Transform3D(basis, Vector3(p.x, y, p.y))
	var tint := rng.randf_range(0.9, 1.04)
	return {"kind": "added", "mesh": id, "removed": false, "color": [tint, tint, tint], "transform": [
		snappedf(xf.basis.x.x, 0.0001), snappedf(xf.basis.x.y, 0.0001), snappedf(xf.basis.x.z, 0.0001),
		snappedf(xf.basis.y.x, 0.0001), snappedf(xf.basis.y.y, 0.0001), snappedf(xf.basis.y.z, 0.0001),
		snappedf(xf.basis.z.x, 0.0001), snappedf(xf.basis.z.y, 0.0001), snappedf(xf.basis.z.z, 0.0001),
		snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01)]}


## Timber stacks beside forest roads: every ~250 m of a world road through forest, sometimes, 10-12 m off its edge, parallel.
func _timber(records: Dictionary, area: Rect2, disc: Vector3) -> int:
	var n := 0
	var rng := RandomNumberGenerator.new()
	for rd: RoadNetwork.Road in demo.sim.state.roads.world:
		var pts := rd.points
		var walked := 0.0
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var seg := a.distance_to(b)
			walked += seg
			if walked < 250.0:
				continue
			walked = 0.0
			if not area.has_point(a) or (disc.is_finite() and a.distance_to(Vector2(disc.x, disc.y)) > disc.z):
				continue
			rng.seed = _hash(Vector2i(roundi(a.x), roundi(a.y)), 77)
			if rng.randf() > 0.45 or _map(_veg, a.x, a.y).r < 0.45:
				continue
			var d := (b - a).normalized()
			var off := Vector2(-d.y, d.x) * (rd.width * 0.5 + 12.0) * (1.0 if rng.randf() < 0.5 else -1.0)
			var yaw := atan2(-d.y, d.x)
			var rec := _place_timber(a + d * seg * 0.5 + off, yaw, rng)
			if not rec.is_empty():
				records["t:%d_%d" % [roundi(a.x), roundi(a.y)]] = rec
				n += 1
	return n


## A timber stack is allowed nearer the road than other cover (that is where it is stacked): its own checks.
func _place_timber(p: Vector2, yaw: float, rng: RandomNumberGenerator) -> Dictionary:
	for e: Array in _excl:
		if p.distance_to(e[0]) < float(e[1]):
			return {}
	var roads := demo.sim.state.roads
	var n := roads.nearest(Vector3(p.x, 0, p.y), 30.0, 0, 0.0)
	if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + 6.0:
		return {}
	if roads.bridge_at(Vector3(p.x, 0, p.y), 60.0) != null:
		return {}
	return _place(IDS.timber, p, yaw, 1.0, rng, "timber") if not _near_placed(p, MIN_GAP) else {}


func _mark(p: Vector2) -> void:
	var k := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	if not _placed.has(k):
		_placed[k] = []
	_placed[k].append(p)


func _near_placed(p: Vector2, r: float) -> bool:
	var k0 := Vector2i(floori((p.x - r) / 16.0), floori((p.y - r) / 16.0))
	var k1 := Vector2i(floori((p.x + r) / 16.0), floori((p.y + r) / 16.0))
	for kx in range(k0.x, k1.x + 1):
		for kz in range(k0.y, k1.y + 1):
			for q: Vector2 in _placed.get(Vector2i(kx, kz), []):
				if q.distance_to(p) < r:
					return true
	return false
