extends SceneTree
## Downscales the ASSET-PRODUCTION-01 preview JPEGs in place (max width, JPEG quality) so
## the committed renders stay small.  Godot --headless --path . --script res://tools/asset_lab/shrink_previews.gd -- [max_width]

const DIRS := ["res://docs/asset01/blender", "res://docs/asset01/godot", "res://docs/asset01/characters", "res://docs/asset01/characters/hips"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var max_w := int(args[0]) if args.size() > 0 else 1600
	var n := 0
	for d in DIRS:
		var abs_dir := ProjectSettings.globalize_path(d)
		for f in DirAccess.get_files_at(abs_dir):
			if not f.ends_with(".jpg"):
				continue
			var p := abs_dir.path_join(f)
			var img := Image.load_from_file(p)
			if img == null:
				continue
			if img.get_width() > max_w:
				img.resize(max_w, int(img.get_height() * float(max_w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
			img.save_jpg(p, 0.78)
			n += 1
	print("SHRINK files=", n)
	quit()
