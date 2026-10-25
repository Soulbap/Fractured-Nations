## VISUAL-02 candidate world: the reference world with a new vegetation cover, built next to it (never over it).
##
##   1. tools/terrain_ref/generate.py --layout tools/terrain_ref/layout_ref03_visual02.json --out worlds/ref_20km_visual02/source
##   2. Godot_console.exe --headless --path . --script res://tools/visual02/build_candidate.gd
##   3. Godot_console.exe --headless --path . --script res://tools/settlement_proto/build_overrides.gd -- --world=ref_20km_visual02
##
## Step 2 loads the reference Terrain3D regions (worlds/ref_20km/terrain: heights, holes and every later edit unchanged),
## replaces only their colour maps and the ground texture ids of their control maps with the candidate's
## (worlds/ref_20km_visual02/source/color.rgba8, control.r32), saves them to worlds/ref_20km_visual02/terrain, scatters the
## vegetation with the candidate maps into worlds/ref_20km_visual02/vegetation and writes the candidate world scene
## scenes/world/ref_20km_visual02.tscn (a copy of the reference scene pointing at the candidate folders) plus
## scenes/game/world_ref_20km_visual02.tscn (the game on it). Roads, settlements, bases, water and relief are the
## reference world's. Control map: a pixel takes the candidate value only where the reference region still holds the generated
## value (no later edit) and both its texture ids are ground cover (meadow, rock, field, forest floor, bog); road surfaces,
## verges, yards, river banks and lake beds (dirt, gravel, asphalt) keep the reference paint.
## --skip-vegetation: only the terrain (control / colour maps) and the scenes.
extends SceneTree

const REF := "res://worlds/ref_20km"
const CAND := "res://worlds/ref_20km_visual02"
const RES := 10240


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var cfg := (load(REF + "/world_config.tres") as ReferenceWorldConfig).duplicate() as ReferenceWorldConfig
	cfg.world_name = "ref_20km_visual02"
	cfg.source_directory = CAND + "/source"
	# Same order as tools/build_world.gd: in the tree first, then layout, assets and data (no collision, no rendering need).
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	get_root().add_child(terrain)
	terrain.collision_mode = Terrain3DCollision.DISABLED
	terrain.region_size = cfg.region_size as Terrain3D.RegionSize
	terrain.vertex_spacing = cfg.vertex_spacing
	terrain.assets = load(REF + "/terrain_assets.tres")
	terrain.data_directory = REF + "/terrain"
	for i in 5:
		await process_frame
	print("CAND loaded %d reference regions in %d ms" % [terrain.data.get_region_count(), Time.get_ticks_msec() - t0])

	var col := _image(CAND + "/source/color.rgba8", Image.FORMAT_RGBA8)
	var ctl_new := _image(CAND + "/source/control.r32", Image.FORMAT_RF)
	var ctl_ref := _image(REF + "/source/control.r32", Image.FORMAT_RF)
	if col == null or ctl_new == null or ctl_ref == null:
		quit(1)
		return
	var half := RES / 2
	var rs := cfg.region_size
	var kept := 0
	var taken := 0
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		var loc := region.location
		var ox := loc.x * rs + half
		var oy := loc.y * rs + half
		var rect := Rect2i(ox, oy, rs, rs)
		var cm := col.get_region(rect)
		cm.generate_mipmaps()
		region.set_color_map(cm)
		# Control: per pixel, the candidate value where the region still holds the generated value.
		var rc := region.get_control_map()
		var cref := ctl_ref.get_region(rect)
		var cnew := ctl_new.get_region(rect)
		var a := rc.get_data().to_float32_array()
		var b := cref.get_data().to_float32_array()
		var c := cnew.get_data().to_float32_array()
		var ai := a.to_byte_array().to_int32_array()
		var bi := b.to_byte_array().to_int32_array()
		var ci := c.to_byte_array().to_int32_array()
		for k in ai.size():
			if ai[k] != bi[k]:
				kept += 1
			elif ai[k] != ci[k] and _cover(ai[k]):
				ai[k] = ci[k]
				taken += 1
		region.set_control_map(Image.create_from_data(rs, rs, false, Image.FORMAT_RF, ai.to_byte_array()))
		region.set_modified(true)
	terrain.data.update_maps(Terrain3DRegion.TYPE_MAX, true, false)
	print("CAND control: %d pixels from the candidate, %d edited pixels kept" % [taken, kept])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAND + "/terrain"))
	terrain.data.save_directory(CAND + "/terrain")
	print("CAND saved terrain in %d ms" % (Time.get_ticks_msec() - t0))

	if "--skip-vegetation" in OS.get_cmdline_user_args():
		_write_scenes()
		quit(0)
		return
	var builder := ReferenceWorldBuilder.new()
	builder.name = "WorldBuilder"
	builder.config = cfg
	builder.terrain = terrain
	get_root().add_child(builder)
	builder.allow_replace_existing_vegetation = true
	builder.scatter_vegetation()
	print("CAND vegetation done in %d ms" % (Time.get_ticks_msec() - t0))
	_write_scenes()
	print("CAND done in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)


## Both texture ids of a control value are ground cover: meadow 0, rock 1, field 3, forest floor 4, bog 6.
func _cover(c: int) -> bool:
	var base := (c >> 27) & 0x1F
	var over := (c >> 22) & 0x1F
	return base in [0, 1, 3, 4, 6] and over in [0, 1, 3, 4, 6]


func _image(path: String, fmt: Image.Format) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("build_candidate: missing " + path)
		return null
	return Image.create_from_data(RES, RES, false, fmt, bytes)


## The candidate world scene is the reference scene with the terrain, vegetation and mask paths moved; the game scene is
## the reference game scene instancing it.
func _write_scenes() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/world/ref_20km.tscn")
	src = src.replace('data_directory = "res://worlds/ref_20km/terrain"', 'data_directory = "res://worlds/ref_20km_visual02/terrain"')
	src = src.replace('data_directory = "res://worlds/ref_20km/vegetation"', 'data_directory = "res://worlds/ref_20km_visual02/vegetation"')
	src = src.replace('path="res://worlds/ref_20km/vegetation/mask.res"', 'path="res://worlds/ref_20km_visual02/vegetation/mask.res"')
	src = _strip_uid(src)
	var f := FileAccess.open("res://scenes/world/ref_20km_visual02.tscn", FileAccess.WRITE)
	f.store_string(src)
	f.close()
	var game := FileAccess.get_file_as_string("res://scenes/game/world_ref_20km.tscn")
	game = game.replace('path="res://scenes/world/ref_20km.tscn"', 'path="res://scenes/world/ref_20km_visual02.tscn"')
	game = _strip_uid(game)
	f = FileAccess.open("res://scenes/game/world_ref_20km_visual02.tscn", FileAccess.WRITE)
	f.store_string(game)
	f.close()


## A copied scene must not claim the original's uid (Godot would resolve both to one file).
func _strip_uid(text: String) -> String:
	var i := text.find(" uid=\"uid://")
	if i >= 0 and i < text.find("\n"):
		var j := text.find("\"", i + 7)
		text = text.substr(0, i) + text.substr(j + 1)
	return text
