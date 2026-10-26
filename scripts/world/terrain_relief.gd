## WORLD-COVER-01.1 terrain microrelief: shallow hollows, low earth folds and ridges, roadside drainage ditches, field-edge earth
## banks and patches of uneven ground, laid over the generated terrain in memory at game start like the settlement layer's
## heights and the road shoulders (never saved; the world files and their manifest are untouched). `--no-terrain-relief` switches
## it off for comparison.
##
## Data: res://worlds/relief/<world>.relief.json - a list of features with their parameters (centre, size, depth / height,
## orientation, shape seed; ditches and banks as polylines), written by the builder below and editable by hand. At start every
## feature is evaluated at the terrain vertices it covers (1.953 m grid) and its height *added* to the terrain after the settlement
## heights and the road shoulders, before the strategic route grid, the terrain collision, the navmesh, LineOfFire and the abstract
## tier read it: every reader sees the same ground. Vegetation instances standing on changed ground are moved with it when their
## chunk loads (fix_chunk); the cover layer's objects, the settlements, roads and their shoulder band, bridges, water, objectives and
## bases were kept clear when the features were placed, so the ground under them does not change.
##
## The vertex spacing (1.95 m) sets the scale: a feature narrower than ~6 m cannot be drawn by the mesh (a 2 m ditch would be one
## vertex row, a notch). Hollows are 4-9 m across their radius, folds 6+ m half wide, ditches 2.4-3 m half wide; every feature keeps
## its own gradient under MAX_GRADE so vehicles (truck 0.40) and infantry cross it.
##
## Built in the running game (terrain with settlements and shoulders, road network, water, objectives, bases, cover layer known):
##   Godot.exe --path . res://scenes/game/world_ref_20km.tscn -- --scenario=dev --no-terrain-relief --build-terrain-relief [--area=x,z,r]
## (--no-terrain-relief: the features must be placed on the ground without the old relief.) --area replaces only that disc.
class_name TerrainRelief
extends RefCounted

const DIR := "res://worlds/relief/"
const HOLLOW := 0
const RIDGE := 1
const LINE := 2
## Terrain vertex grid of ref_20km.
const SP := 1.953125
## Steepest gradient a feature may add (rise per metre); the ground it lies on adds at most BASE_GRADE.
const MAX_GRADE := 0.28
const BASE_GRADE := 0.12
## Vegetation cell size (VegetationChunk): instances of these cells are moved with the ground.
const VEG_CELL_M := 128.0
## Spatial index of the features for point queries (fix_chunk, delta_at).
const INDEX_M := 64.0
## The evaluated vertex heights, cached per relief file (its hash) - evaluating ~14 000 features takes seconds, reading them back
## a fraction of that.
const CACHE := "user://terrain/%s_relief_%s.bin"

static var feats: Array = []
static var _index := {}
static var touched := {}
static var signature := ""
static var stats := {}


static func path(world: String) -> String:
	return DIR + world + ".relief.json"


static func enabled(world: String) -> bool:
	return not world.is_empty() and FileAccess.file_exists(path(world)) and not "--no-terrain-relief" in OS.get_cmdline_user_args()


## The world's features, compiled, without applying them (tests compare the same places with the relief switched off).
static func read_features(world: String) -> Array:
	var out: Array = []
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(world))) if FileAccess.file_exists(path(world)) else null
	if j is Dictionary:
		for f: Dictionary in j.get("features", []):
			out.append(_compile(f))
	return out


## Adds the features' heights to the terrain (memory only). Call after SettlementLayer.apply_terrain and RoadShoulders.apply, before
## the route grid, collision and navigation read the terrain. Returns {features, vertices, ms, signature}.
static func apply(terrain: Terrain3D, world: String) -> Dictionary:
	feats.clear()
	_index.clear()
	touched.clear()
	signature = ""
	if not enabled(world) or terrain == null or terrain.data == null:
		return {}
	var t0 := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(path(world))
	var j: Variant = JSON.parse_string(text)
	if not j is Dictionary:
		push_error("TerrainRelief: %s is not a relief file" % path(world))
		return {}
	signature = "%08x" % (hash(text) & 0xFFFFFFFF)
	for f: Dictionary in j.get("features", []):
		feats.append(_compile(f))
	_build_index()
	var keys := PackedInt32Array()
	var vals := PackedFloat32Array()
	var cache := CACHE % [world, signature]
	var cached := false
	if FileAccess.file_exists(cache):
		var cf := FileAccess.open_compressed(cache, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if cf:
			keys = bytes_to_var(cf.get_buffer(cf.get_32())) as PackedInt32Array
			vals = bytes_to_var(cf.get_buffer(cf.get_32())) as PackedFloat32Array
			cf.close()
			cached = keys.size() == vals.size() * 2 and not vals.is_empty()
	if not cached:
		# Every feature evaluated at the vertices of its box; overlapping features add up.
		var deltas := {}
		for fi in feats.size():
			var f: Dictionary = feats[fi]
			var b: Rect2 = f.box
			for iz in range(ceili(b.position.y / SP), floori(b.end.y / SP) + 1):
				for ix in range(ceili(b.position.x / SP), floori(b.end.x / SP) + 1):
					var dv := _eval(f, ix * SP, iz * SP)
					if absf(dv) > 0.004:
						var k := Vector2i(ix, iz)
						deltas[k] = float(deltas.get(k, 0.0)) + dv
		keys.resize(deltas.size() * 2)
		vals.resize(deltas.size())
		var i := 0
		for k: Vector2i in deltas:
			keys[i * 2] = k.x
			keys[i * 2 + 1] = k.y
			vals[i] = deltas[k]
			i += 1
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache.get_base_dir()))
		var wf := FileAccess.open_compressed(cache, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
		if wf:
			var kb := var_to_bytes(keys)
			var vb := var_to_bytes(vals)
			wf.store_32(kb.size())
			wf.store_buffer(kb)
			wf.store_32(vb.size())
			wf.store_buffer(vb)
			wf.close()
	var regions := {}
	for i in vals.size():
		var p := Vector3(keys[i * 2] * SP, 0.0, keys[i * 2 + 1] * SP)
		var h: float = terrain.data.get_height(p)
		if is_nan(h):
			continue
		terrain.data.set_height(p, h + vals[i])
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
	stats = {"features": feats.size(), "vertices": vals.size(), "ms": Time.get_ticks_msec() - t0, "signature": signature, "cached": cached}
	print("TerrainRelief: ", stats)
	return stats


## The height the relief adds at (x, z): the features evaluated at the four surrounding vertices, interpolated (the terrain's
## own heights between vertices).
static func delta_at(x: float, z: float) -> float:
	if feats.is_empty():
		return 0.0
	var cands: Array = _index.get(Vector2i(floori(x / INDEX_M), floori(z / INDEX_M)), [])
	if cands.is_empty():
		return 0.0
	var ix := floori(x / SP)
	var iz := floori(z / SP)
	var fx := x / SP - ix
	var fz := z / SP - iz
	var v := [0.0, 0.0, 0.0, 0.0]
	for fi: int in cands:
		var f: Dictionary = feats[fi]
		v[0] += _eval(f, ix * SP, iz * SP)
		v[1] += _eval(f, (ix + 1) * SP, iz * SP)
		v[2] += _eval(f, ix * SP, (iz + 1) * SP)
		v[3] += _eval(f, (ix + 1) * SP, (iz + 1) * SP)
	return lerpf(lerpf(v[0], v[1], fx), lerpf(v[2], v[3], fx), fz)


## Features whose box comes within r of p (indices into feats).
static func features_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var seen := {}
	for x in range(floori((p.x - r) / INDEX_M), floori((p.x + r) / INDEX_M) + 1):
		for z in range(floori((p.z - r) / INDEX_M), floori((p.z + r) / INDEX_M) + 1):
			for fi: int in _index.get(Vector2i(x, z), []):
				if not seen.has(fi) and (feats[fi].box as Rect2).grow(r).has_point(Vector2(p.x, p.z)):
					seen[fi] = true
					out.append(fi)
	return out


## Moves the instances of a freshly loaded vegetation chunk with the ground under them (once per loaded chunk object).
static func fix_chunk(ch: VegetationChunk) -> int:
	if touched.is_empty() or ch == null or ch.has_meta(&"relief"):
		return 0
	ch.set_meta(&"relief", signature)
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
				var dv := delta_at(buf[k + 3], buf[k + 11])
				if absf(dv) > 0.004:
					buf[k + 7] += dv
					changed = true
					moved += 1
			if changed:
				by_mesh[mesh_id] = buf
	return moved


## The chunks loaded before the relief was applied: moved, and their cells drawn again.
static func refix_loaded(veg: VegetationStreamer) -> int:
	if veg == null or touched.is_empty():
		return 0
	var moved := 0
	for loc in veg.chunks:
		moved += fix_chunk(veg.chunks[loc])
	if moved > 0:
		veg.overrides_changed(touched.keys())
	return moved


# --- Feature shapes ----------------------------------------------------------------------------------------------------------

## A feature from its JSON form, with the values evaluation needs precomputed (box, rotation, polyline lengths).
static func _compile(f: Dictionary) -> Dictionary:
	var out := f.duplicate()
	var t := int(f.type)
	out.type = t
	if t == LINE:
		var pts := PackedVector2Array()
		var raw: Array = f.pts
		for i in range(0, raw.size() - 1, 2):
			pts.append(Vector2(raw[i], raw[i + 1]))
		out.p2 = pts
		var acc := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			acc.append(acc[i - 1] + pts[i - 1].distance_to(pts[i]))
		out.acc = acc
		out.len = acc[acc.size() - 1]
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		out.box = Rect2(lo, hi - lo).grow(float(f.w) + SP)
	else:
		out.cs = cos(float(f.yaw))
		out.sn = sin(float(f.yaw))
		var ext: float
		if t == HOLLOW:
			ext = maxf(float(f.rx), float(f.rz)) * (1.3 * (1.5 if float(f.get("rim", 0.0)) > 0.0 else 1.0))
		else:
			ext = float(f.hl) + absf(float(f.get("bend", 0.0))) + maxf(float(f.wf), float(f.wb))
		out.box = Rect2(Vector2(float(f.x), float(f.z)) - Vector2(ext, ext), Vector2(ext, ext) * 2.0).grow(SP)
	return out


## Height the feature adds at (x, z): negative is a depression.
static func _eval(f: Dictionary, x: float, z: float) -> float:
	if not (f.box as Rect2).has_point(Vector2(x, z)):
		return 0.0
	match int(f.type):
		HOLLOW:
			var dx := x - float(f.x)
			var dz := z - float(f.z)
			var u := (dx * float(f.cs) + dz * float(f.sn)) / float(f.rx)
			var v := (-dx * float(f.sn) + dz * float(f.cs)) / float(f.rz)
			var ang := atan2(v, u)
			var ph := float(f.get("ph", 0.0))
			var lobes := float(f.get("lobes", 3.0))
			# Irregular outline: the radius swells and shrinks with two low harmonics of the bearing.
			var r := sqrt(u * u + v * v) / (1.0 + 0.16 * sin(lobes * ang + ph) + 0.07 * sin((lobes + 2.0) * ang + ph * 2.3))
			var depth := float(f.d)
			if r < 1.0:
				return -depth * (0.5 + 0.5 * cos(PI * r))
			var rim := float(f.get("rim", 0.0))
			if rim > 0.0 and r < 1.5:
				return depth * rim * sin(PI * (r - 1.0) / 0.5)
			return 0.0
		RIDGE:
			var dx := x - float(f.x)
			var dz := z - float(f.z)
			var s := dx * float(f.cs) + dz * float(f.sn)
			var t := -dx * float(f.sn) + dz * float(f.cs)
			var hl := float(f.hl)
			var a := absf(s) / hl
			if a >= 1.0:
				return 0.0
			# Curved crest line, a level middle and tapered ends, the crest height varying a little along it.
			var tt := t - float(f.get("bend", 0.0)) * (1.0 - (s / hl) * (s / hl))
			var w := float(f.wf) if tt >= 0.0 else float(f.wb)
			if absf(tt) >= w:
				return 0.0
			var taper := 1.0 if a < 0.35 else 0.5 + 0.5 * cos(PI * (a - 0.35) / 0.65)
			var hh := float(f.h) * (1.0 + 0.12 * sin(3.0 * s / hl + float(f.get("ph", 0.0))))
			return hh * taper * (0.5 + 0.5 * cos(PI * absf(tt) / w))
		LINE:
			var q := Vector2(x, z)
			var pts: PackedVector2Array = f.p2
			var acc: PackedFloat32Array = f.acc
			var best := INF
			var along := 0.0
			for i in pts.size() - 1:
				var ab := pts[i + 1] - pts[i]
				var l2 := ab.length_squared()
				var tt := 0.0 if l2 < 1e-6 else clampf((q - pts[i]).dot(ab) / l2, 0.0, 1.0)
				var d := q.distance_to(pts[i] + ab * tt)
				if d < best:
					best = d
					along = acc[i] + sqrt(l2) * tt
			var w := float(f.w)
			if best >= w:
				return 0.0
			var tap := float(f.get("taper", 8.0))
			var e := minf(along, float(f.len) - along)
			var end := 1.0 if e >= tap else 0.5 - 0.5 * cos(PI * maxf(e, 0.0) / tap)
			return float(f.a) * end * (0.5 + 0.5 * cos(PI * best / w))
	return 0.0


static func _build_index() -> void:
	for fi in feats.size():
		var b: Rect2 = feats[fi].box
		for x in range(floori(b.position.x / INDEX_M), floori(b.end.x / INDEX_M) + 1):
			for z in range(floori(b.position.y / INDEX_M), floori(b.end.y / INDEX_M) + 1):
				var k := Vector2i(x, z)
				if not _index.has(k):
					_index[k] = []
				_index[k].append(fi)


## Steepest gradient a feature adds (its own shape): MAX_GRADE is checked against this at placement.
static func max_gradient(f: Dictionary) -> float:
	match int(f.type):
		HOLLOW:
			# The irregular outline shrinks the radius to ~0.77 of rx / rz at worst.
			return absf(float(f.d)) * PI * 0.5 / (minf(float(f.rx), float(f.rz)) * 0.77)
		RIDGE:
			return float(f.h) * 1.12 * PI * 0.5 / minf(float(f.wf), float(f.wb))
		LINE:
			return absf(float(f.a)) * PI * 0.5 / float(f.w)
	return 0.0


# --- Builder -------------------------------------------------------------------------------------------------------------------

const CELL := 40.0
## Features keep this much clear ground between their boxes (m).
const GAP := 4.0

var demo: CoreDemo
var bstats := {}
var _veg: Image
var _info: Image
var _half := 10000.0
var _excl: Array = []  # [Vector2 centre, radius]
var _cover: Dictionary = {}  # 16 m hash -> [[Vector2, reach]]
var _boxes: Dictionary = {}  # 32 m hash -> [Rect2]
var _band := PackedByteArray()  # road shoulder vertices (bitmap over the vertex grid)
var _band_n := 0


func _init(p_demo: CoreDemo) -> void:
	demo = p_demo


func run(args: PackedStringArray) -> void:
	var disc := Vector3.INF
	for a in args:
		if a.begins_with("--area="):
			var v := a.trim_prefix("--area=").split(",")
			disc = Vector3(float(v[0]), float(v[1]), float(v[2]))
	await demo.get_tree().create_timer(2.0).timeout
	var world: String = demo.config.world_name
	if enabled(world):
		push_error("TerrainRelief: build with --no-terrain-relief (the current relief is applied and would be measured as ground)")
		print("RELIEF_LAYER {\"error\": \"run with --no-terrain-relief\"}")
		demo.get_tree().quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var src := "res://worlds/%s/source/" % world
	_veg = Image.load_from_file(ProjectSettings.globalize_path(src.path_join("vegetation.png")))
	_info = Image.load_from_file(ProjectSettings.globalize_path(src.path_join("info.png")))
	_half = demo.config.half_size()
	var area := Rect2(-_half + 60.0, -_half + 60.0, _half * 2.0 - 120.0, _half * 2.0 - 120.0)
	if disc.is_finite():
		area = Rect2(disc.x - disc.z, disc.y - disc.z, disc.z * 2.0, disc.z * 2.0)
	_exclusions(world)
	_load_band()
	var out: Array = []
	var out_path := path(world)
	if disc.is_finite() and FileAccess.file_exists(out_path):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(out_path))
		if j is Dictionary:
			for f: Dictionary in j.get("features", []):
				var c := _centre(f)
				if c.distance_to(Vector2(disc.x, disc.y)) > disc.z:
					out.append(f)
					_mark(_compile(f))
	# Ditches and banks first (they follow roads and field edges), then the scattered features in the gaps.
	for f: Dictionary in _ditches(area, disc):
		out.append(f)
	for cz in range(floori(area.position.y / CELL), floori(area.end.y / CELL) + 1):
		for cx in range(floori(area.position.x / CELL), floori(area.end.x / CELL) + 1):
			var c := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
			if disc.is_finite() and c.distance_to(Vector2(disc.x, disc.y)) > disc.z:
				continue
			for f: Dictionary in _cell(Vector2i(cx, cz)):
				out.append(f)
		if cz % 25 == 0:
			await demo.get_tree().process_frame
	out = _clear_objects(out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "world": world, "features": out}, "", false))
	file.close()
	bstats["features"] = out.size()
	bstats["ms"] = Time.get_ticks_msec() - t0
	print("RELIEF_LAYER ", JSON.stringify(bstats))
	demo.get_tree().quit()


## Last pass: no feature may change the ground under an object (its centre and four points at its reach): the features that
## would are dropped (a ditch run's box or a hollow's rim can reach where the placement checks did not look).
func _clear_objects(list: Array) -> Array:
	var comp: Array = list.map(func(f: Dictionary) -> Dictionary: return _compile(f))
	var grid := {}
	for i in comp.size():
		var b: Rect2 = comp[i].box
		for x in range(floori(b.position.x / INDEX_M), floori(b.end.x / INDEX_M) + 1):
			for z in range(floori(b.position.y / INDEX_M), floori(b.end.y / INDEX_M) + 1):
				var k := Vector2i(x, z)
				if not grid.has(k):
					grid[k] = []
				grid[k].append(i)
	var drop := {}
	for cell: Array in _cover.values():
		for e: Array in cell:
			var p: Vector2 = e[0]
			var r: float = e[1]
			var pts: Array[Vector2] = [p, p + Vector2(r, 0), p - Vector2(r, 0), p + Vector2(0, r), p - Vector2(0, r)]
			var cand := {}
			for q: Vector2 in pts:
				for fi: int in grid.get(Vector2i(floori(q.x / INDEX_M), floori(q.y / INDEX_M)), []):
					cand[fi] = true
			for fi: int in cand:
				if drop.has(fi):
					continue
				for q: Vector2 in pts:
					if absf(_eval(comp[fi], q.x, q.y)) > 0.02:
						drop[fi] = true
						break
	var out: Array = []
	for i in list.size():
		if not drop.has(i):
			out.append(list[i])
	bstats["dropped_for_objects"] = drop.size()
	return out


func _count(k: String) -> void:
	bstats[k] = int(bstats.get(k, 0)) + 1


static func _centre(f: Dictionary) -> Vector2:
	if int(f.type) == LINE:
		var raw: Array = f.pts
		return Vector2(raw[0], raw[1])
	return Vector2(float(f.x), float(f.z))


## Objectives (70 m), bases (reach + 50 m), settlements (their radius + 30 m), base sites (270 m); the cover layer's objects and
## the user's own added objects (their footprint + 3 m).
func _exclusions(world: String) -> void:
	var war := demo.sim.state.war
	for o: ObjectiveState in war.all_objectives():
		_excl.append([Vector2(o.position.x, o.position.z), 70.0])
	for b: Dictionary in demo.sim.state.construction.bases.values():
		_excl.append([Vector2(b.anchor.x, b.anchor.z), float(b.get("radius", 120.0)) + 50.0])
	var sites: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s/source/sites.json" % world))
	if sites is Dictionary:
		for s: Dictionary in sites.get("settlements", []):
			_excl.append([Vector2(s.pos[0], s.pos[2]), float(s.radius_m) + 30.0])
	for p: Vector3 in demo.config.base_sites:
		_excl.append([Vector2(p.x, p.z), 270.0])
	for file in [CoverLayer.path(world), SettlementLayer.overrides_path(world), "res://worlds/%s.overrides.json" % world]:
		if file == "" or not FileAccess.file_exists(file):
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not j is Dictionary:
			continue
		for rec: Dictionary in (j.get("records", {}) as Dictionary).values():
			if rec.get("kind", "") != "added" or not rec.has("transform"):
				continue
			var o: Array = rec.transform
			# Cover objects: their footprint; anything else (buildings, fences, garden trees): a generous 6 m.
			var foot: Vector2 = CoverLayer.FOOT.get(int(rec.get("mesh", -1)), Vector2(6.0, 6.0))
			var sc := Vector3(o[0], o[1], o[2]).length()
			var p := Vector2(o[9], o[11])
			var k := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
			if not _cover.has(k):
				_cover[k] = []
			_cover[k].append([p, maxf(foot.x, foot.y) * sc])


## The road shoulder band of RoadShoulders (the vertices it eased) as a bitmap: no feature may change them.
func _load_band() -> void:
	_band_n = roundi(_half * 2.0 / SP)
	_band.resize((_band_n * _band_n + 7) / 8)
	_band.fill(0)
	for p: Vector2 in RoadShoulders.kept_keys:
		var ix := roundi((p.x + _half) / SP)
		var iz := roundi((p.y + _half) / SP)
		if ix >= 0 and iz >= 0 and ix < _band_n and iz < _band_n:
			var bit := iz * _band_n + ix
			_band[bit >> 3] |= 1 << (bit & 7)
	bstats["band_vertices"] = RoadShoulders.kept_keys.size()


func _in_band(p: Vector2) -> bool:
	var ix := roundi((p.x + _half) / SP)
	var iz := roundi((p.y + _half) / SP)
	if ix < 0 or iz < 0 or ix >= _band_n or iz >= _band_n:
		return false
	var bit := iz * _band_n + ix
	return (_band[bit >> 3] >> (bit & 7)) & 1 == 1


func _map(img: Image, x: float, z: float) -> Color:
	var w := img.get_width()
	return img.get_pixel(clampi(int((x + _half) / (_half * 2.0) * w), 0, w - 1), clampi(int((z + _half) / (_half * 2.0) * w), 0, w - 1))


func _h(p: Vector2) -> float:
	return demo.sim.terrain.data.get_height(Vector3(p.x, 0.0, p.y))


## The scattered features of one 40 m cell, by the ground the cell lies on (deterministic: a hash of the cell).
func _cell(c: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = CoverLayer._hash(c, 5113)
	var p := Vector2((c.x + 0.15 + rng.randf() * 0.7) * CELL, (c.y + 0.15 + rng.randf() * 0.7) * CELL)
	var veg := _map(_veg, p.x, p.y)
	var info := _map(_info, p.x, p.y)
	var forest := veg.r
	var wet := veg.a
	var rocky := info.r
	var field := info.g
	if info.b > 0.2 or wet > 0.55:
		return []
	var out: Array = []
	if field > 0.45:
		# Ploughed fields stay level; their edges get an earth bank (where the field map drops off within 25 m).
		var lo := INF
		var dir := Vector2.ZERO
		for d: Vector2 in [Vector2(25, 0), Vector2(-25, 0), Vector2(0, 25), Vector2(0, -25)]:
			var f2 := _map(_info, p.x + d.x, p.y + d.y).g
			if f2 < lo:
				lo = f2
				dir = d
		if lo < 0.25 and rng.randf() < 0.22:
			var f := _bank(p + dir.normalized() * 9.0, dir.normalized(), rng)
			if _accept(f):
				out.append(f)
		return out
	var r := rng.randf()
	var kind := ""
	if rocky > 0.45:
		kind = "step" if r < 0.12 else ("hollow" if r < 0.17 else "")
	elif forest > 0.55:
		kind = "hollow" if r < 0.09 else ("fold" if r < 0.14 else ("uneven" if r < 0.18 else ""))
	elif forest > 0.2:
		kind = "hollow" if r < 0.09 else ("fold" if r < 0.17 else ("uneven" if r < 0.22 else ""))
	else:
		kind = "hollow" if r < 0.06 else ("fold" if r < 0.12 else ("uneven" if r < 0.15 else ""))
	match kind:
		"hollow":
			var f := _hollow(p, rng, rng.randf_range(0.65, 1.0) if forest > 0.2 else rng.randf_range(0.55, 0.9))
			if _accept(f):
				out.append(f)
		"fold":
			var f := _ridge(p, rng, rng.randf_range(1.1, 1.5), rng.randf_range(12.0, 22.0), false)
			if _accept(f):
				out.append(f)
		"step":
			var f := _ridge(p, rng, rng.randf_range(1.0, 1.4), rng.randf_range(8.0, 16.0), true)
			if _accept(f):
				out.append(f)
		"uneven":
			# Uneven ground: two to four low swells and hollows close together.
			for k in rng.randi_range(2, 4):
				var q := p + Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0))
				var f := _hollow(q, rng, rng.randf_range(0.28, 0.45) * (1.0 if rng.randf() < 0.5 else -1.0), 4.5, 7.5)
				f.erase("rim")
				if _accept(f):
					out.append(f)
					_count("uneven_part")
	return out


func _hollow(p: Vector2, rng: RandomNumberGenerator, depth: float, r0 := 4.5, r1 := 8.5) -> Dictionary:
	# Wide enough that the irregular outline keeps the slope under MAX_GRADE.
	var r_min := absf(depth) * PI * 0.5 / (0.77 * MAX_GRADE)
	var rx := maxf(rng.randf_range(r0, r1), r_min)
	var rz := maxf(rx * rng.randf_range(0.6, 0.95), r_min)
	return {"type": HOLLOW, "kind": "hollow" if depth > 0.0 else "swell", "x": snappedf(p.x, 0.01), "z": snappedf(p.y, 0.01),
		"rx": snappedf(rx, 0.01), "rz": snappedf(rz, 0.01), "yaw": snappedf(rng.randf() * TAU, 0.001),
		"d": snappedf(depth, 0.01), "rim": snappedf(rng.randf_range(0.0, 0.14), 0.01) if depth > 0.0 and rng.randf() < 0.5 else 0.0,
		"ph": snappedf(rng.randf() * TAU, 0.001), "lobes": rng.randi_range(2, 4)}


## A low earth fold (gentle both sides) or, on rocky ground, a step (steeper towards one side).
func _ridge(p: Vector2, rng: RandomNumberGenerator, h: float, hl: float, step: bool) -> Dictionary:
	var w_min := h * 1.12 * PI * 0.5 / MAX_GRADE
	var wf := maxf(w_min, rng.randf_range(8.0, 10.5))
	var wb := wf if not step else wf * rng.randf_range(1.6, 2.2)
	if not step:
		wb = maxf(w_min, wf * rng.randf_range(0.8, 1.3))
	return {"type": RIDGE, "kind": "step" if step else "fold", "x": snappedf(p.x, 0.01), "z": snappedf(p.y, 0.01),
		"yaw": snappedf(rng.randf() * TAU, 0.001), "hl": snappedf(hl, 0.01), "bend": snappedf(rng.randf_range(-0.25, 0.25) * hl, 0.01),
		"wf": snappedf(wf, 0.01), "wb": snappedf(wb, 0.01), "h": snappedf(h, 0.01), "ph": snappedf(rng.randf() * TAU, 0.001)}


## An earth bank along a field edge at p; `out` points out of the field (the bank runs across it).
func _bank(p: Vector2, out: Vector2, rng: RandomNumberGenerator) -> Dictionary:
	var along := Vector2(-out.y, out.x)
	var half := rng.randf_range(12.0, 24.0)
	var pts: Array = []
	for k in 5:
		var s := -half + half * 2.0 * k / 4.0
		var q := p + along * s + out * rng.randf_range(-1.2, 1.2)
		pts.append(snappedf(q.x, 0.01))
		pts.append(snappedf(q.y, 0.01))
	var a := rng.randf_range(0.55, 0.75)
	return {"type": LINE, "kind": "bank", "pts": pts, "w": snappedf(maxf(a * PI * 0.5 / MAX_GRADE, rng.randf_range(3.6, 4.4)), 0.01),
		"a": snappedf(a, 0.01), "taper": 7.0}


## Drainage ditches beside the world roads outside settlements (local roads, tracks, secondary and primary): runs of 40-140 m on
## either side with gaps, just beyond the road shoulder band, ending before junctions, bridges, culverts and other roads.
func _ditches(area: Rect2, disc: Vector3) -> Array:
	var out: Array = []
	var roads := demo.sim.state.roads
	for rd: RoadNetwork.Road in roads.world:
		if rd.points.size() < 2 or not rd.cls in [&"local", &"track", &"secondary", &"primary"]:
			continue
		for side: float in [-1.0, 1.0]:
			var rng := RandomNumberGenerator.new()
			rng.seed = CoverLayer._hash(Vector2i(rd.key, int(side)), 909)
			var run: Array = []  # [Vector2 point, offset]
			var want := rng.randf_range(40.0, 140.0)
			var gap := rng.randf_range(20.0, 160.0)
			var walked := 0.0
			var pts := rd.points
			var s_total := 0.0
			for i in pts.size() - 1:
				var a := Vector2(pts[i].x, pts[i].z)
				var b := Vector2(pts[i + 1].x, pts[i + 1].z)
				var seg := a.distance_to(b)
				if seg < 0.01:
					continue
				var d := (b - a) / seg
				var nrm := Vector2(-d.y, d.x) * side
				var s := fmod(4.0 - fmod(s_total, 4.0), 4.0)
				while s < seg:
					var c := a + d * s
					s += 4.0
					walked += 4.0
					if gap > 0.0:
						gap -= 4.0
						continue
					var station := _ditch_station(rd, i, c, nrm, area, disc)
					if station.is_empty() or (not run.is_empty() and absf(float(station.off) - float(run[run.size() - 1].off)) > 2.5):
						_close_run(run, out, rng)
						run = []
						gap = rng.randf_range(20.0, 160.0) if station.is_empty() else 0.0
						want = rng.randf_range(40.0, 140.0)
						if station.is_empty():
							continue
					run.append(station)
					if run.size() * 4.0 >= want:
						_close_run(run, out, rng)
						run = []
						gap = rng.randf_range(20.0, 160.0)
						want = rng.randf_range(40.0, 140.0)
				s_total += seg
			_close_run(run, out, rng)
	return out


## One 4 m station of a ditch beside road rd at centre-line point c, normal nrm (pointing to the side): {p, off} or {} where no
## ditch may lie. The ditch centre is half a ditch width beyond the outermost shoulder vertex.
func _ditch_station(rd: RoadNetwork.Road, seg: int, c: Vector2, nrm: Vector2, area: Rect2, disc: Vector3) -> Dictionary:
	if not area.has_point(c) or (disc.is_finite() and c.distance_to(Vector2(disc.x, disc.y)) > disc.z):
		return {}
	for br: Array in rd.bridges:
		if seg >= int(br[0]) - 6 and seg <= int(br[1]) + 6:
			return {}
	for cv in rd.culverts:
		if absi(int(cv) - seg) <= 2:
			return {}
	var roads := demo.sim.state.roads
	if roads.bridge_at(Vector3(c.x, 0, c.y), 50.0) != null:
		return {}
	var hw := rd.width * 0.5
	# The band edge: the first metre beyond which no shoulder vertex lies within the next 3 m.
	var off := hw + 1.0
	var last_band := off
	while off < hw + 18.0:
		if _in_band(c + nrm * off):
			last_band = off
		elif off - last_band >= 3.0:
			break
		off += 1.0
	if off >= hw + 18.0:
		return {}
	var w := 2.6
	var centre_off := last_band + w + 1.0
	var p := c + nrm * centre_off
	# Nothing else here: no other road within its own band, no exclusion, no water, ground nearly level across the ditch.
	var n := roads.nearest(Vector3(p.x, 0, p.y), 30.0, rd.key, 0.0)
	if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + 16.0:
		return {}
	for e: Array in _excl:
		if p.distance_to(e[0]) < float(e[1]):
			return {}
	if _near_cover(p, w + 2.0):
		return {}
	var h0 := _h(c + nrm * (last_band + 1.0))
	var h1 := _h(p)
	var h2 := _h(c + nrm * (centre_off + w))
	if is_nan(h0) or is_nan(h1) or is_nan(h2) or absf(h2 - h0) > (w * 2.0) * BASE_GRADE * 1.5:
		return {}
	var st := demo.sim.structures
	if st._wet(p.x, p.y, h1 - 0.7) or st._wet(p.x, p.y, h1 + 0.5):
		return {}
	var info := _map(_info, p.x, p.y)
	if info.b > 0.2:
		return {}
	return {"p": p, "off": centre_off}


func _close_run(run: Array, out: Array, rng: RandomNumberGenerator) -> void:
	if run.size() < 6:
		return
	var pts: Array = []
	for st: Dictionary in run:
		pts.append(snappedf((st.p as Vector2).x, 0.01))
		pts.append(snappedf((st.p as Vector2).y, 0.01))
	var depth := rng.randf_range(0.45, 0.65)
	var f := {"type": LINE, "kind": "ditch", "pts": pts, "w": 2.6, "a": snappedf(-depth, 0.01), "taper": 8.0}
	if max_gradient(f) > MAX_GRADE:
		f.w = snappedf(depth * PI * 0.5 / MAX_GRADE, 0.01)
	out.append(f)
	_mark(_compile(f))
	_count("ditch")
	bstats["ditch_m"] = int(bstats.get("ditch_m", 0)) + run.size() * 4


## True when the feature may be laid: inside no exclusion, clear of roads (and their band), bridges, water, cover objects and other
## features, on ground level enough that the feature keeps every gradient under MAX_GRADE + BASE_GRADE.
func _accept(f: Dictionary) -> bool:
	var cf := _compile(f)
	var box: Rect2 = cf.box
	var c := box.get_center()
	var reach := box.size.length() * 0.5
	if max_gradient(f) > MAX_GRADE + 0.01:
		_count("rejected_gradient")
		return false
	for e: Array in _excl:
		if c.distance_to(e[0]) < float(e[1]) + reach:
			_count("rejected_area")
			return false
	if _overlaps(cf):
		_count("rejected_gap")
		return false
	if _near_cover(c, reach + 3.0):
		_count("rejected_cover")
		return false
	var roads := demo.sim.state.roads
	var n := roads.nearest(Vector3(c.x, 0, c.y), reach + 30.0, 0, 0.0)
	if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + 18.0 + reach:
		_count("rejected_road")
		return false
	if roads.bridge_at(Vector3(c.x, 0, c.y), 80.0 + reach) != null:
		_count("rejected_bridge")
		return false
	# Ground: heights round the box and through it; level enough, dry, no structure footprint.
	var lo := INF
	var hi := -INF
	var st := demo.sim.structures
	for k in 13:
		var q := c if k == 12 else c + Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0)) * reach
		var h := _h(q)
		if is_nan(h):
			return false
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if _in_band(q):
			_count("rejected_road")
			return false
		if st._wet(q.x, q.y, h - 1.0):
			_count("rejected_water")
			return false
	for k in 8:
		var q := c + Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * (reach + 15.0)
		var hq := _h(q)
		if not is_nan(hq) and st._wet(q.x, q.y, hq - 0.5):
			_count("rejected_water")
			return false
	if hi - lo > reach * 2.0 * BASE_GRADE:
		_count("rejected_slope")
		return false
	if st.blocks_point(c, reach):
		_count("rejected_occupied")
		return false
	_mark(cf)
	_count("placed_" + String(f.kind))
	return true


func _near_cover(p: Vector2, r: float) -> bool:
	var k0 := Vector2i(floori((p.x - r - 8.0) / 16.0), floori((p.y - r - 8.0) / 16.0))
	var k1 := Vector2i(floori((p.x + r + 8.0) / 16.0), floori((p.y + r + 8.0) / 16.0))
	for kx in range(k0.x, k1.x + 1):
		for kz in range(k0.y, k1.y + 1):
			for e: Array in _cover.get(Vector2i(kx, kz), []):
				if (e[0] as Vector2).distance_to(p) < r + float(e[1]):
					return true
	return false


## The boxes a compiled feature occupies: its box, or for a line one per segment (a long diagonal ditch's box would cover a
## square of land beside the road).
static func _parts(cf: Dictionary) -> Array:
	if int(cf.type) != LINE:
		return [cf.box]
	var out: Array = []
	var pts: PackedVector2Array = cf.p2
	for i in pts.size() - 1:
		out.append(Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(float(cf.w)))
	return out


func _mark(cf: Dictionary) -> void:
	for box: Rect2 in _parts(cf):
		for x in range(floori(box.position.x / 32.0), floori(box.end.x / 32.0) + 1):
			for z in range(floori(box.position.y / 32.0), floori(box.end.y / 32.0) + 1):
				var k := Vector2i(x, z)
				if not _boxes.has(k):
					_boxes[k] = []
				_boxes[k].append(box)


func _overlaps(cf: Dictionary) -> bool:
	for part: Rect2 in _parts(cf):
		var box := part.grow(GAP)
		for x in range(floori(box.position.x / 32.0), floori(box.end.x / 32.0) + 1):
			for z in range(floori(box.position.y / 32.0), floori(box.end.y / 32.0) + 1):
				for b: Rect2 in _boxes.get(Vector2i(x, z), []):
					if b.intersects(box):
						return true
	return false
