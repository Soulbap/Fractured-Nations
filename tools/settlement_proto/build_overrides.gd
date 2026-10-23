## WORLD-SETTLEMENT-02: writes the settlement layer's world-overrides file
## (res://worlds/settlements/ref_20km.overrides.json) from res://worlds/settlements/ref_20km.json.
##
## The file is a *layer*: WorldOverrides loads it under the user's own overrides (ref_20km.overrides.json,
## never read or copied here), so manual edits stay the user's and win on the same id. Records:
##   - the old settlement buildings and mailboxes (mesh 16, 17, 18, 20) round every settlement: removed,
##   - the old settlements' garden trees (scattered trees in the round disc, not forest ground): about four in
##     five removed, except near the new buildings,
##   - trees, bushes and rocks under the new buildings and on the new roads: removed,
##   - the new buildings (kind "added", with their colour).
## The vegetation chunks are only read. Run:
##   Godot --headless --path . --script res://tools/settlement_proto/build_overrides.gd
extends SceneTree

const WORLD := "res://worlds/ref_20km"
const VEG_DIR := WORLD + "/vegetation/"
const LAYER := "res://worlds/settlements/ref_20km"
const OLD_BUILDINGS := [16, 17, 18, 20]
const RADIUS := {16: 9.0, 17: 13.0, 18: 4.5}
const CELL := 32.0

var _control_file: FileAccess
## Spatial hashes (32 m) of the new buildings and road segments.
var _bld_grid := {}
var _seg_grid := {}


func _init() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYER + ".json"))
	var records := {}
	var sites: Array = d.sites
	var blds: Array = d.buildings
	for b: Dictionary in blds:
		_hash(_bld_grid, Rect2(b.x, b.z, 0, 0).grow(RADIUS[int(b.mesh)] + 30.0), b)
	for r: Dictionary in d.roads:
		var hw := (float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)) * 0.5
		var pts: Array = r.points
		for i in pts.size() - 1:
			var a := Vector2(pts[i][0], pts[i][2])
			var b2 := Vector2(pts[i + 1][0], pts[i + 1][2])
			_hash(_seg_grid, Rect2(a, Vector2.ZERO).expand(b2).grow(hw + 2.0), [a, b2, hw])
	var chunks := {}
	for b: Dictionary in blds:
		chunks[Vector2i(floori(b.x / 1024.0), floori(b.z / 1024.0))] = true
	for key: Vector2i in _seg_grid:
		chunks[Vector2i(floori(key.x * CELL / 1024.0), floori(key.y * CELL / 1024.0))] = true
	for s: Dictionary in sites:
		var c := Vector2(s.center[0], s.center[1])
		var r := maxf(float(s.radius_m) * 1.25, float(s.radius_m) + 30.0)
		for cx in range(floori((c.x - r) / 1024.0), floori((c.x + r) / 1024.0) + 1):
			for cz in range(floori((c.y - r) / 1024.0), floori((c.y + r) / 1024.0) + 1):
				chunks[Vector2i(cx, cz)] = true
	var removed := {"old": 0, "garden": 0, "veg": 0}
	for loc: Vector2i in chunks:
		var file := VEG_DIR + VegetationChunk.file_name(loc)
		if not FileAccess.file_exists(file):
			continue
		var ch := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE) as VegetationChunk
		var digest := FileAccess.get_sha256(file)
		for cell: Vector2i in ch.cells:
			var by_mesh: Dictionary = ch.cells[cell]
			for mesh_id: int in by_mesh:
				var buf: PackedFloat32Array = by_mesh[mesh_id]
				for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
					var xf := VegetationChunk.instance_transform(buf, i)
					var p := Vector2(xf.origin.x, xf.origin.z)
					var kind := ""
					var site := _site_at(sites, p)
					if OLD_BUILDINGS.has(mesh_id):
						if site >= 0:
							kind = "old"
					elif mesh_id <= 15 and _blocked(p):
						kind = "veg"
					elif mesh_id <= 8 and site >= 0 and _garden_tree(p, i):
						kind = "garden"
					if kind.is_empty():
						continue
					removed[kind] += 1
					records["g:%d:%d:%d:%d" % [cell.x, cell.y, mesh_id, i]] = {"kind": "generated",
						"cell": [cell.x, cell.y], "mesh": mesh_id, "index": i, "chunk_hash": digest,
						"transform": _encode(xf), "removed": true}
	for i in blds.size():
		var b: Dictionary = blds[i]
		var xf := Transform3D(Basis(Vector3.UP, float(b.yaw)), Vector3(b.x, b.y, b.z))
		records["a:ws02_%04d" % i] = {"kind": "added", "mesh": int(b.mesh), "transform": _encode(xf), "color": b.color, "removed": false}
	var out := LAYER + ".overrides.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "records": records}, " "))
	f.close()
	print("build_overrides: %d chunks; removed %d old buildings/mailboxes, %d garden trees, %d trees/rocks on new sites; added %d buildings -> %s"
		% [chunks.size(), removed.old, removed.garden, removed.veg, blds.size(), out])
	quit()


func _hash(grid: Dictionary, r: Rect2, item: Variant) -> void:
	for x in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
		for z in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
			var k := Vector2i(x, z)
			if not grid.has(k):
				grid[k] = []
			grid[k].append(item)


func _site_at(sites: Array, p: Vector2) -> int:
	for i in sites.size():
		var s: Dictionary = sites[i]
		if p.distance_to(Vector2(s.center[0], s.center[1])) < maxf(float(s.radius_m) * 1.25, float(s.radius_m) + 30.0):
			return i
	return -1


## Under a new building (its radius + 3 m) or on a new road (half width + 1.5 m).
func _blocked(p: Vector2) -> bool:
	var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for b: Dictionary in _bld_grid.get(k, []):
		if p.distance_to(Vector2(b.x, b.z)) < float(RADIUS[int(b.mesh)]) + 3.0:
			return true
	for s: Array in _seg_grid.get(k, []):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, s[0], s[1])) < float(s[2]) + 1.5:
			return true
	return false


## Scattered trees of the old disc: keep about one in five and those near the new buildings; forest ground
## keeps its trees.
func _garden_tree(p: Vector2, i: int) -> bool:
	if _base_texture(p) == 4:
		return false
	for b: Dictionary in _bld_grid.get(Vector2i(floori(p.x / CELL), floori(p.y / CELL)), []):
		if p.distance_to(Vector2(b.x, b.z)) < 30.0:
			return false
	return (i * 2654435761) % 5 != 0


## Base texture of the canonical control map (source/control.r32, 10240 x 10240 uint32).
func _base_texture(p: Vector2) -> int:
	if _control_file == null:
		_control_file = FileAccess.open(WORLD + "/source/control.r32", FileAccess.READ)
	var xi := roundi((p.x + 10000.0) / 1.953125)
	var zi := roundi((p.y + 10000.0) / 1.953125)
	_control_file.seek((zi * 10240 + xi) * 4)
	return _control_file.get_32() >> 27 & 0x1F


## Same layout as WorldOverrides._encode.
static func _encode(xf: Transform3D) -> Array:
	return [xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z]
