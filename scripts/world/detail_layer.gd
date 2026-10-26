## WORLD-DETAIL-02 man-made detail layer: the cover and clutter of an inhabited landscape - garden walls and fences at the
## plots, firewood against the houses, round bales, pallets and containers at the farms, builder's yards and container yards
## in the town and the works (Verket), transformer kiosks, road depots and guardrails along the roads, sandbag / HESCO
## checkpoints on the roads into the objectives - placed by rules as a read-only WorldOverrides layer
## (res://worlds/detail/<world>.detail.json, "added" records of library ids 31-49 plus a few natural ids). Like the cover layer
## it never touches the generated chunks or the manifest; VegetationStreamer loads it after the cover layer, so every system
## that reads vegetation solids (drawing, LineOfFire, InstanceColliderStreamer, StructureManager, AreaNavigation, the
## CombatBrain cover search) sees the objects. `--no-world-detail` switches it off for comparison.
##
## The kit (ids, footprints, solid or drawn only) is assets/environment/detail_kit.json, written with the library entries by
## tools/world_detail/make_detail_library.py from the asset sidecars.
##
## Built in the running game, so the ground is the one soldiers walk on and the roads, buildings (chunks plus the settlement
## layer), water, bridges, objectives and bases are known:
##   Godot.exe --path . res://scenes/game/world_ref_20km.tscn -- --scenario=dev --no-world-detail --build-detail-layer [--area=x,z,r]
## --area rebuilds only that disc; the rest of the file stays.
##
## Deterministic: every choice comes from a hash of the building / cell / road position. Never placed: on or within ~3 m of a
## road surface (the road mesh is 2 m wider than RoadNetwork's width), within 40 m of a bridge, in water, on ground that rises
## more than ~0.6 m under the footprint, over a tree, rock, structure or building, or closer than 1.2 m to another object
## (a soldier passes between); nothing on objective centres or base areas (checkpoints stand on the roads leading in).
class_name DetailLayer
extends RefCounted

const DIR := "res://worlds/detail/"
const KIT := "res://assets/environment/detail_kit.json"
const ID := {"bales": 31, "firewood": 32, "garden_wall": 33, "picket": 34, "blocks": 35, "pipes": 36, "skip": 37, "kiosk": 38,
	"materials": 39, "barrier": 40, "hesco": 41, "sandbags": 42, "twall": 43, "container": 44, "container_mil": 45,
	"guardrail": 46, "chainlink": 47, "goods": 48, "logs": 49, "boulder": 24, "rockgroup": 25, "timber": 30}
## Footprint half length / depth of the natural ids reused here (CoverLayer.FOOT).
const NATURAL := {24: Vector2(1.15, 1.15), 25: Vector2(1.35, 0.78), 30: Vector2(2.15, 0.88)}
## Building footprints (half x, half z at scale 1) of the library's house, barn and shed (tools/blender/env/make_structures.py).
const BUILDING := {16: Vector2(3.9, 5.7), 17: Vector2(5.2, 10.2), 18: Vector2(1.7, 2.4)}
## A soldier passes between two objects.
const GAP := 1.2


static func path(world: String) -> String:
	return DIR + world + ".detail.json"


static func enabled() -> bool:
	return not "--no-world-detail" in OS.get_cmdline_user_args()


var demo: CoreDemo
var stats := {}
var records := {}
var _kit := {}
var _veg: Image
var _info: Image
var _half := 10000.0
var _disc := Vector3.INF
var _placed := {}     # 16 m cell -> [[Vector2, reach]]
var _excl: Array = []  # [Vector2, radius]
var _buildings: Array = []  # [Vector2 centre, yaw, Vector2 half size, mesh]
var _bgrid := {}      # 32 m cell -> [index into _buildings]
var _sites: Array = []  # [Vector2 centre, radius, type]
var _n := 0


func _init(p_demo: CoreDemo) -> void:
	demo = p_demo


func run(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--area="):
			var v := a.trim_prefix("--area=").split(",")
			_disc = Vector3(float(v[0]), float(v[1]), float(v[2]))
	await demo.get_tree().create_timer(2.0).timeout
	if enabled():
		push_error("DetailLayer: build with --no-world-detail (the current layer is loaded and would block itself)")
		print("DETAIL_LAYER {\"error\": \"run with --no-world-detail\"}")
		demo.get_tree().quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var world: String = demo.config.world_name
	var src := "res://worlds/%s/source/" % world
	_veg = Image.load_from_file(ProjectSettings.globalize_path(src.path_join("vegetation.png")))
	_info = Image.load_from_file(ProjectSettings.globalize_path(src.path_join("info.png")))
	_half = demo.config.half_size()
	var kj: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT))
	for k: String in kj:
		_kit[int(k)] = kj[k]
	var out_path := path(world)
	if _disc.is_finite() and FileAccess.file_exists(out_path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if j is Dictionary:
			for id: String in j.get("records", {}):
				var o: Array = j.records[id].transform
				if Vector2(o[9] - _disc.x, o[11] - _disc.y).length() > _disc.z:
					records[id] = j.records[id]
					_mark(Vector2(o[9], o[11]), 1.0)
	_exclusions()
	_load_sites(world)
	await _collect_buildings()
	stats["buildings"] = _buildings.size()
	_houses()
	_barns()
	await demo.get_tree().process_frame
	_approaches()
	_yards()
	await demo.get_tree().process_frame
	_roadside()
	_checkpoints()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "records": records}))
	f.close()
	stats["records"] = records.size()
	stats["ms"] = Time.get_ticks_msec() - t0
	print("DETAIL_LAYER ", JSON.stringify(stats))
	demo.get_tree().quit()


func _count(k: String) -> void:
	stats[k] = int(stats.get(k, 0)) + 1


# --- World data ----------------------------------------------------------------------------------------------------------

## Objective centres (40 m) and bases (their reach + 30 m, base sites 220 m): kept free for fighting positions and building.
func _exclusions() -> void:
	var war := demo.sim.state.war
	for o: ObjectiveState in war.all_objectives():
		_excl.append([Vector2(o.position.x, o.position.z), 40.0])
	for b: Dictionary in demo.sim.state.construction.bases.values():
		_excl.append([Vector2(b.anchor.x, b.anchor.z), float(b.get("radius", 120.0)) + 30.0])
	for p: Vector3 in demo.config.base_sites:
		_excl.append([Vector2(p.x, p.z), 220.0])


## Settlements of the settlement layer: centre, radius and type (A hamlet / farm cluster, B village, C town, D scattered,
## I industrial).
func _load_sites(world: String) -> void:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/settlements/%s.json" % world))
	if j is Dictionary:
		for s: Dictionary in j.get("sites", []):
			_sites.append([Vector2(s.center[0], s.center[1]), float(s.radius_m), String(s.type).left(1)])


func _site_of(p: Vector2) -> Array:
	for s: Array in _sites:
		if p.distance_to(s[0]) < float(s[1]):
			return s
	return []


## Houses, barns and sheds of the whole map from the chunks with the overrides (settlement layer) applied, one chunk at a
## time (unloaded again: the builder must not hold the whole world's vegetation).
func _collect_buildings() -> void:
	var veg := demo.vegetation
	var cs := veg.cell_size_m
	var per := int(veg.chunk_size_m / cs)
	var c0 := floori(-_half / veg.chunk_size_m)
	var c1 := floori((_half - 1.0) / veg.chunk_size_m)
	for cz in range(c0, c1 + 1):
		for cx in range(c0, c1 + 1):
			var loc := Vector2i(cx, cz)
			if _disc.is_finite():
				var r := Rect2(cx * veg.chunk_size_m, cz * veg.chunk_size_m, veg.chunk_size_m, veg.chunk_size_m)
				if r.grow(_disc.z + 300.0).has_point(Vector2(_disc.x, _disc.y)) == false:
					continue
			for j in per:
				for i in per:
					for inst: Array in veg.get_cell_instances(Vector2i(cx * per + i, cz * per + j), [16, 17, 18]):
						var xf: Transform3D = inst[1]
						var c := Vector2(xf.origin.x, xf.origin.z)
						var k := Vector2i(floori(c.x / 32.0), floori(c.y / 32.0))
						if not _bgrid.has(k):
							_bgrid[k] = []
						_bgrid[k].append(_buildings.size())
						_buildings.append([c, VegetationMeshDef.yaw_of(xf), BUILDING[int(inst[0])] * xf.basis.get_scale().x, int(inst[0]), xf.origin.y])
			veg.unload_chunk(loc)
		await demo.get_tree().process_frame


func _map(img: Image, x: float, z: float) -> Color:
	var w := img.get_width()
	var u := clampi(int((x + _half) / (_half * 2.0) * w), 0, w - 1)
	var v := clampi(int((z + _half) / (_half * 2.0) * w), 0, w - 1)
	return img.get_pixel(u, v)


static func _hash(c: Vector2i, salt: int) -> int:
	return absi((c.x * 73856093) ^ (c.y * 19349663) ^ (salt * 83492791))


func _rng(p: Vector2, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _hash(Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0)), salt)
	return rng


## Local x axis of a yaw (the objects' long axis) in the XZ plane, and the side axis (local z).
static func _axis(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


static func _side(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func _yaw_of_dir(d: Vector2) -> float:
	return atan2(-d.y, d.x)


# --- Placement -----------------------------------------------------------------------------------------------------------

func _foot(id: int) -> Vector2:
	if NATURAL.has(id):
		return NATURAL[id]
	var f: Array = _kit[id].foot
	return Vector2(f[0], f[1])


## Places mesh id at p with yaw if the place is free and suitable; returns the record id ("" when rejected).
## opts: gap (m to other objects, default GAP), road (clearance beyond the road mesh edge, default 2.5), slope (max rise under
## the footprint), bld (clearance to buildings, default 1.5), excl (false: ignore objective / base exclusions), bridge (keep-off
## distance from bridge decks, default 40), y (stack height: no ground checks), why (stats tag).
func _place(id: int, p: Vector2, yaw: float, opts := {}) -> String:
	var why: String = opts.get("why", "obj")
	var foot := _foot(id)
	var reach := foot.length()
	if _disc.is_finite() and p.distance_to(Vector2(_disc.x, _disc.y)) > _disc.z:
		return ""
	_count("try_" + why)
	if absf(p.x) > _half - 60.0 or absf(p.y) > _half - 60.0:
		return ""
	var ax := _axis(yaw)
	var sd := _side(yaw)
	var corners: Array[Vector2] = [p + ax * foot.x + sd * foot.y, p + ax * foot.x - sd * foot.y, p - ax * foot.x + sd * foot.y,
		p - ax * foot.x - sd * foot.y]
	var y := 0.0
	if opts.has("y"):
		y = float(opts.y)
	else:
		if opts.get("excl", true):
			for e: Array in _excl:
				if p.distance_to(e[0]) < float(e[1]) + reach:
					_count("rejected_area")
					return ""
		if _near_placed(p, reach, float(opts.get("gap", GAP))):
			_count("rejected_gap")
			return ""
		if _near_building(corners + [p], float(opts.get("bld", 1.5))):
			_count("rejected_building")
			return ""
		var roads := demo.sim.state.roads
		var clear := float(opts.get("road", 2.5)) + 2.0
		for q: Vector2 in corners + [p, (corners[0] + corners[2]) * 0.5, (corners[1] + corners[3]) * 0.5]:
			var n := roads.nearest(Vector3(q.x, 0, q.y), 30.0, 0, 0.0)
			if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + clear:
				_count("rejected_road")
				return ""
		if roads.bridge_at(Vector3(p.x, 0, p.y), float(opts.get("bridge", 40.0))) != null:
			_count("rejected_bridge")
			return ""
		var st := demo.sim.structures
		var lo := INF
		var hi := -INF
		for q: Vector2 in corners + [p]:
			var h: float = demo.sim.terrain.data.get_height(Vector3(q.x, 0, q.y))
			if is_nan(h):
				return ""
			lo = minf(lo, h)
			hi = maxf(hi, h)
			if st._wet(q.x, q.y, h + 0.1):
				_count("rejected_water")
				return ""
			if st.blocks_trunk(q, 0.35) or st.blocks_point(q, 0.35):
				_count("rejected_occupied")
				return ""
		if hi - lo > float(opts.get("slope", 0.6)):
			_count("rejected_slope")
			return ""
		# Trunks, rocks and structures inside the footprint: probes along both long edges and the centre line every 1.5 m (a
		# circle round the whole footprint would also hit the round colliders of the buildings beside which yard things stand).
		var steps := maxi(1, ceili(foot.x * 2.0 / 1.5))
		for k in steps + 1:
			var t := -foot.x + foot.x * 2.0 * k / steps
			for w: float in [-foot.y, 0.0, foot.y]:
				var q := p + ax * t + sd * w
				if st.blocks_trunk(q, 0.35) or st.blocks_point(q, 0.35):
					_count("rejected_occupied")
					return ""
		y = lo + 0.02
	_mark(p, reach)
	_count("placed_" + why)
	_n += 1
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, Vector3(p.x, y, p.y))
	var key := "w:%d" % _n if not _disc.is_finite() else "w:%d_%d_%d" % [roundi(_disc.x), roundi(_disc.y), _n]
	records[key] = {"kind": "added", "mesh": id, "removed": false, "color": [1, 1, 1], "transform": [
		snappedf(xf.basis.x.x, 0.0001), snappedf(xf.basis.x.y, 0.0001), snappedf(xf.basis.x.z, 0.0001),
		snappedf(xf.basis.y.x, 0.0001), snappedf(xf.basis.y.y, 0.0001), snappedf(xf.basis.y.z, 0.0001),
		snappedf(xf.basis.z.x, 0.0001), snappedf(xf.basis.z.y, 0.0001), snappedf(xf.basis.z.z, 0.0001),
		snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01)]}
	return key


func _height_of(key: String) -> float:
	return float(records[key].transform[10])


func _mark(p: Vector2, reach: float) -> void:
	var k := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	if not _placed.has(k):
		_placed[k] = []
	_placed[k].append([p, reach])


func _near_placed(p: Vector2, reach: float, gap: float) -> bool:
	var r := reach + gap + 8.0
	for kx in range(floori((p.x - r) / 16.0), floori((p.x + r) / 16.0) + 1):
		for kz in range(floori((p.y - r) / 16.0), floori((p.y + r) / 16.0) + 1):
			for e: Array in _placed.get(Vector2i(kx, kz), []):
				# Footprints as circles round their long side would keep walls far apart: half the reach is the honest
				# middle for the elongated kit.
				if p.distance_to(e[0]) < (reach + float(e[1])) * 0.62 + gap:
					return true
	return false


func _near_building(pts: Array, margin: float) -> bool:
	var p0: Vector2 = pts[pts.size() - 1]
	for kx in range(floori(p0.x / 32.0) - 1, floori(p0.x / 32.0) + 2):
		for kz in range(floori(p0.y / 32.0) - 1, floori(p0.y / 32.0) + 2):
			for bi: int in _bgrid.get(Vector2i(kx, kz), []):
				var b: Array = _buildings[bi]
				var ax := _axis(b[1])
				var sd := _side(b[1])
				var hs: Vector2 = b[2]
				for q: Vector2 in pts:
					var d: Vector2 = q - b[0]
					if absf(d.dot(ax)) < hs.x + margin and absf(d.dot(sd)) < hs.y + margin:
						return true
	return false


## A row of n pieces of id along dir from p (centred), each `step` apart; returns the number placed. Pieces of one row touch
## (no gap between them) but keep the usual gap to everything else.
func _row(id: int, p: Vector2, dir: Vector2, n: int, step: float, opts := {}) -> int:
	var placed := 0
	var yaw := _yaw_of_dir(dir)
	var o := opts.duplicate()
	for k in n:
		var q := p + dir * (k - (n - 1) * 0.5) * step
		o["gap"] = float(opts.get("gap", GAP)) if placed == 0 else -_foot(id).length() * 0.62 * 2.0 + step * 0.9
		if _place(id, q, yaw, o) != "":
			placed += 1
	return placed


func _nearest_road(p: Vector2, r: float) -> Dictionary:
	return demo.sim.state.roads.nearest(Vector3(p.x, 0, p.y), r, 0, 0.0)


# --- Rules ---------------------------------------------------------------------------------------------------------------

## Houses: a boundary towards the road (garden wall or picket fence with a gate gap), firewood against a side wall, now and
## then a skip or a pallet stack of a renovation.
func _houses() -> void:
	for b: Array in _buildings:
		if int(b[3]) != 16:
			continue
		var c: Vector2 = b[0]
		var rng := _rng(c, 16)
		var site := _site_of(c)
		var kind: String = site[2] if not site.is_empty() else "F"
		var walls: float = {"C": 0.5, "B": 0.4, "A": 0.3, "I": 0.3}.get(kind, 0.15)
		var fences: float = {"C": 0.25, "B": 0.3, "A": 0.3, "I": 0.1}.get(kind, 0.2)
		var n := _nearest_road(c, 45.0)
		if not n.is_empty():
			var rd: RoadNetwork.Road = n.road
			var rp: Vector3 = n.pos
			var dir: Vector2 = n.dir
			var to_house := (c - Vector2(rp.x, rp.z))
			var dist := to_house.length()
			var off := rd.width * 0.5 + 2.0 + 3.0
			if dist > off + 6.0:
				var nrm := to_house.normalized()
				var line := Vector2(rp.x, rp.z) + nrm * off
				var r := rng.randf()
				if r < walls:
					_row(ID.garden_wall, line + dir * 3.9, dir, 1, 6.0, {"why": "garden_wall"})
					_row(ID.garden_wall, line - dir * 3.9, dir, 1, 6.0, {"why": "garden_wall"})
				elif r < walls + fences:
					_row(ID.picket, line + dir * 5.0, dir, 2, 4.0, {"why": "picket", "gap": 0.5})
					_row(ID.picket, line - dir * 5.0, dir, 2, 4.0, {"why": "picket", "gap": 0.5})
		# Firewood along a long wall (local z side of the house is its long side).
		if rng.randf() < (0.5 if kind in ["F", "A", "D"] else 0.3):
			var s := 1.0 if rng.randf() < 0.5 else -1.0
			var ax := _axis(b[1])
			var hs: Vector2 = b[2]
			var q: Vector2 = c + ax * s * (hs.x + 1.1) + _side(b[1]) * rng.randf_range(-2.0, 2.0)
			_place(ID.firewood, q, float(b[1]) + PI * 0.5, {"why": "firewood", "bld": 0.3, "gap": 0.8})
		var r2 := rng.randf()
		if r2 < (0.06 if kind in ["C", "B", "I"] else 0.025):
			_near(b, ID.skip, rng, "skip")
		elif r2 < (0.12 if kind in ["C", "B", "I"] else 0.06):
			_near(b, ID.materials, rng, "materials")


## Something beside a building: 3-8 m off a random side, parallel to it.
func _near(b: Array, id: int, rng: RandomNumberGenerator, why: String) -> String:
	var c: Vector2 = b[0]
	var hs: Vector2 = b[2]
	for t in 3:
		var a := rng.randi_range(0, 3)
		var ax := _axis(b[1])
		var sd := _side(b[1])
		var dir: Vector2 = [ax, -ax, sd, -sd][a]
		var reach: float = hs.x if a < 2 else hs.y
		var q := c + dir * (reach + rng.randf_range(3.0, 8.0)) + (sd if a < 2 else ax) * rng.randf_range(-3.0, 3.0)
		var key := _place(id, q, float(b[1]) + (PI * 0.5 if a < 2 else 0.0) + rng.randf_range(-0.1, 0.1), {"why": why})
		if key != "":
			return key
	return ""


## Farms (barns): round bales in a row towards the fields, a timber or firewood stack, pallets and goods by the barn, a
## silage bin of concrete blocks, sometimes a container used as a store.
func _barns() -> void:
	for b: Array in _buildings:
		if int(b[3]) != 17:
			continue
		var c: Vector2 = b[0]
		var rng := _rng(c, 17)
		var ax := _axis(b[1])
		var sd := _side(b[1])
		var hs: Vector2 = b[2]
		# Bales: 12-30 m off the side away from the nearest road, along the barn.
		if rng.randf() < 0.8:
			var away := sd
			var n := _nearest_road(c, 80.0)
			if not n.is_empty():
				var rp: Vector3 = n.pos
				away = (c - Vector2(rp.x, rp.z)).normalized()
			for k in rng.randi_range(1, 2):
				var q := c + away * (hs.length() + rng.randf_range(8.0, 22.0)) + away.orthogonal() * rng.randf_range(-12.0, 12.0)
				var d := away.orthogonal().rotated(rng.randf_range(-0.3, 0.3))
				_row(ID.bales, q, d, rng.randi_range(1, 2), 5.2, {"why": "bales"})
		if rng.randf() < 0.45:
			_near(b, ID.goods, rng, "farm_goods")
		if rng.randf() < 0.3:
			_near(b, ID.materials, rng, "farm_materials")
		if rng.randf() < 0.3:
			_near(b, ID.firewood if rng.randf() < 0.6 else ID.timber, rng, "farm_wood")
		if rng.randf() < 0.18:
			_near(b, ID.blocks, rng, "farm_blocks")
		if rng.randf() < 0.15:
			_near(b, ID.container, rng, "farm_container")


## The last 100-200 m into a settlement: open fields and meadows round it get bale rows, rock piles cleared from the fields
## and the odd timber stack, sparse (one object per few 30 m cells) so an approach has bounds to take, not a safe lane.
func _approaches() -> void:
	for s: Array in _sites:
		var ctr: Vector2 = s[0]
		var r0: float = float(s[1]) * 0.85
		var r1: float = float(s[1]) + 200.0
		var cell := 30.0
		for cz in range(floori((ctr.y - r1) / cell), floori((ctr.y + r1) / cell) + 1):
			for cx in range(floori((ctr.x - r1) / cell), floori((ctr.x + r1) / cell) + 1):
				var rng := RandomNumberGenerator.new()
				rng.seed = _hash(Vector2i(cx, cz), 2002)
				var p := Vector2((cx + rng.randf()) * cell, (cz + rng.randf()) * cell)
				var d := p.distance_to(ctr)
				if d < r0 or d > r1:
					continue
				var veg := _map(_veg, p.x, p.y)
				var info := _map(_info, p.x, p.y)
				if veg.r > 0.5 or veg.a > 0.6:
					continue  # forest is cover already; wet ground stays clear
				var r := rng.randf()
				var yaw := rng.randf() * TAU
				if info.g > 0.45:
					if r < 0.05:
						_row(ID.bales, p, _axis(yaw), 1, 5.2, {"why": "approach_bales"})
					elif r < 0.09:
						_place(ID.rockgroup, p, yaw, {"why": "approach_rocks"})
				elif r < 0.04:
					_place(ID.rockgroup if rng.randf() < 0.6 else ID.boulder, p, yaw, {"why": "approach_rocks"})
				elif r < 0.06:
					_place(ID.timber, p, yaw, {"why": "approach_timber"})


## Yards: the works (type I) and the town (C) get builder's / container yards - containers in rows, sometimes stacked, block
## walls, pipe stacks, pallets, skips and goods, a chain-link fence along one side. Villages (B) get one small yard.
func _yards() -> void:
	for s: Array in _sites:
		var kind: String = s[2]
		var count: int = {"I": 9, "C": 7, "B": 1}.get(kind, 0)
		var rng := _rng(s[0], 4040)
		for k in count:
			for t in 12:
				var a := rng.randf() * TAU
				var p: Vector2 = s[0] + Vector2(cos(a), sin(a)) * float(s[1]) * sqrt(rng.randf()) * (0.85 if kind == "I" else 0.75)
				if _yard(p, rng, kind):
					break


func _yard(p: Vector2, rng: RandomNumberGenerator, kind: String) -> bool:
	var yaw := rng.randf() * TAU
	var n := _nearest_road(p, 40.0)
	if not n.is_empty():
		yaw = _yaw_of_dir(n.dir)  # yards line up with the street
	var ax := _axis(yaw)
	var sd := _side(yaw)
	var first := ""
	var r := rng.randf()
	if kind == "I" and r < 0.55:
		# Container row: 2-4 side by side (their long axis across the row), one stacked on top now and then.
		var m := rng.randi_range(2, 4)
		for i in m:
			var q := p + ax * (i - (m - 1) * 0.5) * 2.6
			var key := _place(ID.container, q, yaw + PI * 0.5, {"why": "yard_container", "gap": GAP if i == 0 else -1.8,
				"slope": 0.45})
			if key == "":
				continue
			if first == "":
				first = key
			if rng.randf() < 0.3:
				_place(ID.container, q, yaw + PI * 0.5, {"why": "yard_stacked", "y": _height_of(key) + 2.59})
	else:
		first = _place(ID.blocks if rng.randf() < 0.5 else ID.materials, p, yaw, {"why": "yard_main"})
	if first == "":
		return false
	# Around it: pipes, goods, a skip, pallets, a block wall.
	var extras := [ID.pipes, ID.goods, ID.skip, ID.materials, ID.blocks, ID.goods]
	for i in rng.randi_range(2, 4):
		var id: int = extras[rng.randi_range(0, extras.size() - 1)]
		var q := p + sd * rng.randf_range(6.0, 11.0) * (1.0 if rng.randf() < 0.6 else -1.0) + ax * rng.randf_range(-8.0, 8.0)
		_place(id, q, yaw + (PI * 0.5 if rng.randf() < 0.3 else 0.0), {"why": "yard_extra"})
	if kind == "I" and rng.randf() < 0.6:
		_row(ID.chainlink, p - sd * 8.0, ax, 5, 3.0, {"why": "yard_fence", "gap": 0.6})
	return true


## Along the roads: a transformer kiosk at each settlement, road works depots on the main roads, guardrails where the road
## runs along a drop and on the approaches to bridges (drawn only).
func _roadside() -> void:
	var roads := demo.sim.state.roads
	for s: Array in _sites:
		var rng := _rng(s[0], 3838)
		var want := 1 + int(float(s[1]) / 200.0)
		var got := 0
		for t in 20:
			if got >= want:
				break
			var a := rng.randf() * TAU
			var p: Vector2 = s[0] + Vector2(cos(a), sin(a)) * float(s[1]) * rng.randf_range(0.3, 1.0)
			var n := _nearest_road(p, 60.0)
			if n.is_empty():
				continue
			var rp: Vector3 = n.pos
			var to := (p - Vector2(rp.x, rp.z)).normalized()
			var q := Vector2(rp.x, rp.z) + to * ((n.road as RoadNetwork.Road).width * 0.5 + 6.5)
			if _place(ID.kiosk, q, _yaw_of_dir(n.dir), {"why": "kiosk"}) != "":
				got += 1
	for rd: RoadNetwork.Road in roads.world:
		var pts := rd.points
		var walked := 0.0
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var seg := a.distance_to(b)
			if seg < 0.01:
				continue
			var d := (b - a) / seg
			var nrm := d.orthogonal()
			# Guardrail on the main (meshed) roads: where the ground falls away steeply beside the edge (1.5 m down 4 m out, 4 m
			# down 9 m out: a real embankment or a hillside drop), and on the approaches to bridges.
			for side: float in [-1.0, 1.0]:
				if not rd.mesh or rd.width < 6.0:
					break
				var e := a + nrm * side * (rd.width * 0.5 + 2.6)
				var mid := a + nrm * side * (rd.width * 0.5 + 6.0)
				var far := a + nrm * side * (rd.width * 0.5 + 11.0)
				var hm: float = demo.sim.terrain.data.get_height(Vector3(mid.x, 0, mid.y))
				var hf: float = demo.sim.terrain.data.get_height(Vector3(far.x, 0, far.y))
				var near_bridge := roads.bridge_at(Vector3(a.x, 0, a.y), 30.0) != null and roads.bridge_at(Vector3(a.x, 0, a.y), 0.0) == null
				if (not is_nan(hm) and not is_nan(hf) and pts[i].y - hm > 1.5 and pts[i].y - hf > 4.0) or near_bridge:
					var steps := maxi(1, floori(seg / 4.0))
					for k in steps:
						var q := e + d * (k + 0.5) * seg / steps
						_place(ID.guardrail, q, _yaw_of_dir(d), {"why": "guardrail", "road": -1.9, "gap": -1.0, "slope": 1.2,
							"excl": false, "bridge": 0.0})
			walked += seg
			# Road works depot every ~2.5 km of a main road, sometimes: a pull-off 14-22 m from the edge.
			if walked > 2500.0 and rd.width >= 6.0:
				walked = 0.0
				var rng := _rng(a, 909)
				if rng.randf() < 0.45:
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					var p := a + nrm * side * (rd.width * 0.5 + rng.randf_range(14.0, 22.0))
					var yaw := _yaw_of_dir(d)
					if _place(ID.pipes, p, yaw, {"why": "depot"}) != "":
						_place(ID.blocks, p + d * 6.0, yaw, {"why": "depot"})
						_place(ID.materials, p - d * 6.0, yaw, {"why": "depot"})
						if rng.randf() < 0.5:
							_place(ID.skip, p + nrm * side * 5.0, yaw, {"why": "depot"})
	return


## Checkpoints on the roads leading into the objectives (bridges, villages, towns): 70-110 m out, on both shoulders, sandbag
## walls and HESCO / concrete barriers staggered beside (never on) the carriageway, a T-wall, sometimes a military container.
## Not every road and not every objective: the hash decides.
func _checkpoints() -> void:
	var roads := demo.sim.state.roads
	for o: ObjectiveState in demo.sim.state.war.all_objectives():
		if not o.kind in [&"bridge", &"village", &"town"]:
			continue
		var ctr := Vector2(o.position.x, o.position.z)
		var rng := _rng(ctr, 7070)
		if rng.randf() > 0.65:
			continue
		var done := 0
		for k in 16:
			if done >= 2:
				break
			var a := k * TAU / 16.0 + rng.randf() * 0.2
			var p := ctr + Vector2(cos(a), sin(a)) * rng.randf_range(75.0, 110.0)
			var n := roads.nearest(Vector3(p.x, 0, p.y), 15.0, 0, 0.0)
			if n.is_empty():
				continue
			var rd: RoadNetwork.Road = n.road
			var rp: Vector3 = n.pos
			var c := Vector2(rp.x, rp.z)
			var d: Vector2 = n.dir
			var nrm := d.orthogonal()
			var yaw := _yaw_of_dir(d)
			var off := rd.width * 0.5 + 3.7
			var opts := {"why": "checkpoint", "excl": false, "road": 0.9, "gap": 0.6}
			var placed := 0
			for side: float in [-1.0, 1.0]:
				var base := c + nrm * side * off
				# Facing out of the objective: sandbags across the shoulder end, HESCO along it.
				var outward := (c - ctr).normalized()
				var sgn := signf(d.dot(outward))
				# Two 2 m sandbag walls side by side across the shoulder (a 4 m wall facing the road out), its inner end
				# clear of the road edge.
				var across := base + nrm * side * 1.3 + d * sgn * 5.0
				if _place(ID.sandbags, across, yaw + PI * 0.5, opts) != "":
					placed += 1
				if _place(ID.sandbags, across + nrm * side * 2.05, yaw + PI * 0.5, opts.merged({"gap": -0.6})) != "":
					placed += 1
				var wall := ID.hesco if rng.randf() < 0.6 else ID.barrier
				if _place(wall, base - d * sgn * (2.0 + 3.0 * float(side > 0.0)), yaw, opts) != "":
					placed += 1
				if rng.randf() < 0.5 and _place(ID.twall, base + nrm * side * 2.4, yaw, opts) != "":
					placed += 1
			if rng.randf() < 0.4:
				_place(ID.container_mil, c + nrm * (off + 7.0) * (1.0 if rng.randf() < 0.5 else -1.0), yaw, opts)
			if placed > 0:
				done += 1
				_count("checkpoints")
