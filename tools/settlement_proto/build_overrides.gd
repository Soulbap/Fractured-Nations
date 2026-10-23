## WORLD-SETTLEMENT-01: writes res://worlds/settlement_proto/<name>.overrides.json from <name>.json.
##
## Starts from the canonical overrides file (res://worlds/ref_20km.overrides.json, if present) so the
## prototype shows the same world plus the settlement change, then
##   - removes the old settlement buildings and mailboxes (mesh 16, 17, 18, 20) inside clear_radius_m,
##   - removes trees, bushes and rocks under the new buildings and on the new roads,
##   - adds the new buildings (kind "added", with their colour).
## The vegetation chunks are only read. Run:
##   Godot --headless --path . --script res://tools/settlement_proto/build_overrides.gd -- haugen
extends SceneTree

const WORLD := "res://worlds/ref_20km"
const VEG_DIR := WORLD + "/vegetation/"
const OLD_BUILDINGS := [16, 17, 18, 20]
const RADIUS := {16: 9.0, 17: 13.0, 18: 4.5}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var proto_name: String = args[0] if args.size() > 0 else "haugen"
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SettlementProto.DIR + proto_name + ".json"))
	var records := {}
	var base_path := WORLD + ".overrides.json"
	if FileAccess.file_exists(base_path):
		records = JSON.parse_string(FileAccess.get_file_as_string(base_path)).records
	var n_base := records.size()
	var center := Vector2(d.center[0], d.center[1])
	var clear_r: float = d.clear_radius_m
	var blds: Array = d.buildings
	var roads: Array = []
	for r: Dictionary in d.roads:
		var pts := PackedVector2Array()
		for p: Array in r.points:
			pts.append(Vector2(p[0], p[2]))
		roads.append([pts, (float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)) * 0.5])
	var area := Rect2(center - Vector2(clear_r, clear_r), Vector2(clear_r, clear_r) * 2.0)
	for r in roads:
		for p: Vector2 in r[0]:
			area = area.expand(p)
	area = area.grow(40.0)
	var removed := {"old": 0, "veg": 0}
	for cx in range(floori(area.position.x / 1024.0), floori(area.end.x / 1024.0) + 1):
		for cz in range(floori(area.position.y / 1024.0), floori(area.end.y / 1024.0) + 1):
			var loc := Vector2i(cx, cz)
			var file := VEG_DIR + VegetationChunk.file_name(loc)
			var ch := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE) as VegetationChunk
			if ch == null:
				push_error("missing chunk " + file)
				continue
			var digest := FileAccess.get_sha256(file)
			for cell: Vector2i in ch.cells:
				var by_mesh: Dictionary = ch.cells[cell]
				for mesh_id: int in by_mesh:
					var buf: PackedFloat32Array = by_mesh[mesh_id]
					for i in buf.size() / VegetationChunk.FLOATS_PER_INSTANCE:
						var xf := VegetationChunk.instance_transform(buf, i)
						var p := Vector2(xf.origin.x, xf.origin.z)
						if not area.has_point(p):
							continue
						var kind := ""
						if OLD_BUILDINGS.has(mesh_id):
							if p.distance_to(center) < clear_r:
								kind = "old"
						elif mesh_id <= 15 and _blocked(p, blds, roads):
							kind = "veg"
						elif mesh_id <= 8 and p.distance_to(center) < clear_r and _garden_tree(p, i, blds):
							kind = "veg"
						if kind.is_empty():
							continue
						removed[kind] += 1
						records["g:%d:%d:%d:%d" % [cell.x, cell.y, mesh_id, i]] = {"kind": "generated",
							"cell": [cell.x, cell.y], "mesh": mesh_id, "index": i, "chunk_hash": digest,
							"transform": _encode(xf), "removed": true}
	for i in blds.size():
		var b: Dictionary = blds[i]
		var xf := Transform3D(Basis(Vector3.UP, float(b.yaw)), Vector3(b.x, b.y, b.z))
		records["a:ws01_%s_%03d" % [proto_name, i]] = {"kind": "added", "mesh": int(b.mesh),
			"transform": _encode(xf), "color": b.color, "removed": false}
	var out := SettlementProto.DIR + proto_name + ".overrides.json"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "records": records}, "  "))
	f.close()
	print("build_overrides: %d canonical records, removed %d old buildings/mailboxes and %d trees/rocks, added %d buildings -> %s"
		% [n_base, removed.old, removed.veg, blds.size(), out])
	quit()


## The old settlement disc was planted with scattered garden trees (a round wood pasture in the open
## fields): keep about one in five, plus those near the new buildings; forest ground keeps its trees.
func _garden_tree(p: Vector2, i: int, blds: Array) -> bool:
	if _base_texture(p) == 4:
		return false
	for b: Dictionary in blds:
		if p.distance_to(Vector2(b.x, b.z)) < 30.0:
			return false
	return (i * 2654435761) % 5 != 0


var _control_file: FileAccess


## Base texture of the canonical control map (source/control.r32, 10240 x 10240 uint32).
func _base_texture(p: Vector2) -> int:
	if _control_file == null:
		_control_file = FileAccess.open(WORLD + "/source/control.r32", FileAccess.READ)
	var sp := 1.953125
	var xi := roundi((p.x + 10000.0) / sp)
	var zi := roundi((p.y + 10000.0) / sp)
	_control_file.seek((zi * 10240 + xi) * 4)
	return _control_file.get_32() >> 27 & 0x1F


## Under a new building (its radius + 3 m) or on a new road (half width + 1.5 m).
static func _blocked(p: Vector2, blds: Array, roads: Array) -> bool:
	for b: Dictionary in blds:
		if p.distance_to(Vector2(b.x, b.z)) < float(RADIUS[int(b.mesh)]) + 3.0:
			return true
	for r in roads:
		var pts: PackedVector2Array = r[0]
		for i in pts.size() - 1:
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])) < float(r[1]) + 1.5:
				return true
	return false


## Same layout as WorldOverrides._encode.
static func _encode(xf: Transform3D) -> Array:
	return [xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z, xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z]
