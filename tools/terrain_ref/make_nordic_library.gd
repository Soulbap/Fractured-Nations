## Writes assets/environment/nordic_library.tres, the VegetationLibrary of the reference
## world: Nordic trees, understorey, deadwood, rocks and settlement props from the Blender
## environment pipeline (assets/environment/scenes/<name>.tscn). Where an asset scene does
## not exist yet the WORLD-TECH placeholder is used, so the world builds at every stage.
##
##   Godot_console.exe --headless --path . --script res://tools/terrain_ref/make_nordic_library.gd
extends SceneTree

const OUT := "res://assets/environment/nordic_library.tres"
const SCENES := "res://assets/environment/scenes/"
const PH := "res://assets/vegetation/"

## id, name, scene, placeholder, near_range, max_range, fade, shadows, collider (type, radius, height)
const DEFS := [
	[1, "Pine A", "pine_a", "conifer", 90.0, 1000.0, 80.0, true, Vector3(0, 0.28, 8)],
	[2, "Pine B", "pine_b", "conifer", 90.0, 1000.0, 80.0, true, Vector3(0, 0.32, 9)],
	[3, "Spruce A", "spruce_a", "conifer", 85.0, 950.0, 80.0, true, Vector3(0, 0.3, 8)],
	[4, "Spruce B", "spruce_b", "conifer", 70.0, 650.0, 60.0, true, Vector3(0, 0.2, 5)],
	[5, "Birch A", "birch_a", "broadleaf", 110.0, 900.0, 80.0, true, Vector3(0, 0.18, 7)],
	[6, "Birch B", "birch_b", "broadleaf", 100.0, 850.0, 80.0, true, Vector3(0, 0.15, 6)],
	[7, "Juniper", "juniper", "bush", 60.0, 260.0, 40.0, false, Vector3(-1, 0, 0)],
	[8, "Shrub", "shrub", "bush", 60.0, 300.0, 40.0, false, Vector3(-1, 0, 0)],
	[9, "Boulder A", "boulder_a", "rocka", 140.0, 650.0, 60.0, true, Vector3(1, 1.1, 0)],
	[10, "Boulder B", "boulder_b", "rockb", 140.0, 650.0, 60.0, true, Vector3(1, 1.0, 0)],
	[11, "Stones", "rocks_small", "rockc", 45.0, 180.0, 30.0, false, Vector3(-1, 0, 0)],
	[12, "Outcrop", "outcrop", "rocka", 200.0, 1000.0, 90.0, true, Vector3(1, 2.4, 0)],
	[13, "Fallen log", "log", "rockc", 60.0, 220.0, 40.0, true, Vector3(-1, 0, 0)],
	[14, "Stump", "stump", "rockc", 40.0, 160.0, 30.0, false, Vector3(-1, 0, 0)],
	[15, "Fern", "fern", "bush", 30.0, 110.0, 25.0, false, Vector3(-1, 0, 0)],
	[16, "House", "house", "", 250.0, 1800.0, 100.0, true, Vector3(1, 4.0, 0)],
	[17, "Barn", "barn", "", 250.0, 1800.0, 100.0, true, Vector3(1, 5.0, 0)],
	[18, "Shed", "shed", "", 120.0, 900.0, 60.0, true, Vector3(1, 1.8, 0)],
	[19, "Fence", "fence", "", 40.0, 220.0, 30.0, false, Vector3(-1, 0, 0)],
	[20, "Mailbox", "mailbox", "", 30.0, 120.0, 20.0, false, Vector3(-1, 0, 0)],
	[21, "Road post", "road_post", "", 40.0, 200.0, 30.0, false, Vector3(-1, 0, 0)],
]


func _init() -> void:
	var lib := VegetationLibrary.new()
	var report := []
	for d in DEFS:
		var path: String = SCENES + d[2] + ".tscn"
		var used := path
		if not ResourceLoader.exists(path):
			if d[3] == "":
				continue
			used = PH + d[3] + ".tscn"
		var def := VegetationMeshDef.new()
		def.id = d[0]
		def.name = d[1]
		def.scene = load(used)
		def.near_range = d[4]
		def.max_range = d[5]
		def.fade_m = d[6]
		def.cast_shadows = d[7]
		def.collider = d[8]
		lib.meshes.append(def)
		report.append("%d %s -> %s" % [d[0], d[1], used.get_file()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(lib, OUT)
	print("LIBRARY ", OUT, " err=", err)
	for r in report:
		print("  ", r)
	quit()
