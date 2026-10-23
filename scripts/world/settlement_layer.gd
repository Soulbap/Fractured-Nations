## WORLD-SETTLEMENT-02: the settlement layer of a generated world (ref_20km).
##
## The world generator gave every settlement a circle: a street grid or two straight streets graded into the
## terrain, a round mown-grass patch with a pale tint and random buildings. The layer replaces that with
## the settlements of tools/settlement_proto/design_settlements.py (Haugen: design_haugen.py), without
## touching the world's own files. Data in res://worlds/settlements/:
##   <world>.json               removed streets (by name), new local roads (roads.json form), buildings;
##   <world>.overrides.json     world-overrides layer (old buildings/garden trees removed, new buildings), loaded
##                              by WorldOverrides under the user's own overrides file;
##   <world>_paint.bin.gz       ground paint (control bits 14..31 + colour per terrain vertex);
##   <world>_height.bin.gz      the old streets' cut/fill corridors smoothed back into the terrain.
## Roads go into the one RoadNetwork (load_world); paint and heights are written into Terrain3DData in memory
## at game start (never saved). On by default when the files exist; `--no-settlements` shows the old world.
class_name SettlementLayer
extends RefCounted

const DIR := "res://worlds/settlements/"
## Terrain vertex grid of the paint/height files (ref_20km: 10240 vertices, 1.953125 m, origin -10000).
const GRID_N := 10240
const GRID_SP := 1.953125
const GRID_HALF := 10000.0

static var _cache := {}


static func enabled(world: String) -> bool:
	return not world.is_empty() and FileAccess.file_exists(DIR + world + ".json") and not "--no-settlements" in OS.get_cmdline_user_args()


static func data(world: String) -> Dictionary:
	if not enabled(world):
		return {}
	if not _cache.has(world):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + world + ".json"))
		_cache[world] = d if d is Dictionary else {}
	return _cache[world]


static func overrides_path(world: String) -> String:
	return DIR + world + ".overrides.json" if enabled(world) else ""


## Files the derived navigation data depends on (StrategicRoutes cache fingerprint).
static func files(world: String) -> PackedStringArray:
	if not enabled(world):
		return PackedStringArray()
	return PackedStringArray([DIR + world + ".json", DIR + world + "_height.bin.gz"])


## roads.json data with the layer applied. Removed roads keep their slot (empty points) so the indices, road
## keys and bridge ids of all other roads stay the same.
static func patch_roads(roads: Dictionary, world: String) -> Dictionary:
	var d := data(world)
	if d.is_empty():
		return roads
	var removed := {}
	for n: String in d.get("remove_roads", []):
		removed[n] = true
	for r: Dictionary in roads.roads:
		if removed.has(r.name):
			r.points = []
			r.bridges = []
	for r: Dictionary in d.get("roads", []):
		roads.roads.append(r)
	print("SettlementLayer: %d world streets removed, %d local roads added" % [removed.size(), d.get("roads", []).size()])
	return roads


## Writes the layer's heights and ground paint into the terrain (memory only) and keeps particle grass off
## the new roads. Call once, before collision, navigation grids and vehicles read the terrain.
static func apply_terrain(terrain: Terrain3D, world: String) -> void:
	var d := data(world)
	if d.is_empty() or terrain == null or terrain.data == null:
		return
	var t0 := Time.get_ticks_msec()
	var regions := {}
	var hv := _read(DIR + world + "_height.bin.gz")
	var nh := hv.size() / 8
	for k in nh:
		var key := hv.decode_u32(k * 8)
		var pos := Vector3((key % GRID_N) * GRID_SP - GRID_HALF, 0.0, (key / GRID_N) * GRID_SP - GRID_HALF)
		terrain.data.set_height(pos, hv.decode_float(k * 8 + 4))
		regions[terrain.data.get_region_location(pos)] = true
	var pv := _read(DIR + world + "_paint.bin.gz")
	var np := pv.size() / 12
	for k in np:
		var key := pv.decode_u32(k * 12)
		var pos := Vector3((key % GRID_N) * GRID_SP - GRID_HALF, 0.0, (key / GRID_N) * GRID_SP - GRID_HALF)
		var ctl := pv.decode_u32(k * 12 + 4)
		var cur: int = terrain.data.get_control(pos)
		terrain.data.set_control(pos, (cur & 0x3FFF) | ctl)
		var c := pv.decode_u32(k * 12 + 8)
		terrain.data.set_color(pos, Color8(c & 0xFF, c >> 8 & 0xFF, c >> 16 & 0xFF, c >> 24 & 0xFF))
		regions[terrain.data.get_region_location(pos)] = true
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, false, false)
	for loc in regions:
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region:
			region.set_edited(false)
	# Particle grass back on the old streets, off the new roads (the grass layer's exclusion mask, in memory).
	var grass := terrain.get_parent().get_node_or_null("Grass") as GrassLayer
	if grass and grass.mask and grass.mask.image:
		var img := grass.mask.image
		var t := grass.mask.texel_m
		var world_roads: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s/source/roads.json" % world))
		var removed: Array = d.get("remove_roads", [])
		var kept: Array = []
		if world_roads is Dictionary:
			for r: Dictionary in world_roads.roads:
				if not removed.has(r.name):
					kept.append(r)
					continue
				var hw0 := (float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)) * 0.5 + 4.0
				for p: Array in r.points:
					var c := (Vector2(p[0], p[2]) - grass.mask.origin) / t
					for px in range(floori(c.x - hw0 / t), ceili(c.x + hw0 / t) + 1):
						for pz in range(floori(c.y - hw0 / t), ceili(c.y + hw0 / t) + 1):
							if px >= 0 and pz >= 0 and px < img.get_width() and pz < img.get_height():
								img.set_pixel(px, pz, Color.BLACK)
		for r: Dictionary in kept + d.roads:
			var hw := (float(r.lane_m) * float(r.lanes) + 2.0 * float(r.shoulder_m)) * 0.5
			var pts: Array = r.points
			for i in pts.size() - 1:
				var a := Vector2(pts[i][0], pts[i][2])
				if not regions.has(terrain.data.get_region_location(Vector3(a.x, 0, a.y))):
					continue
				VegetationMask._paint(img, grass.mask, a, Vector2(pts[i + 1][0], pts[i + 1][2]), hw + 1.0, 3.0)
		grass.apply_mask()
	print("SettlementLayer: %d heights, %d paint vertices applied in %d ms" % [nh, np, Time.get_ticks_msec() - t0])


static func _read(path: String) -> PackedByteArray:
	var raw := FileAccess.get_file_as_bytes(path)
	return raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP) if not raw.is_empty() else raw
