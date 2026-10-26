## Player settings (GAMEPLAY-02 controls): what the Settings screen changes, kept in user://settings.cfg and applied at start.
## Only the interface scale so far: the root window's content scale factor on top of the 1152 x 648 logical canvas (stretch
## mode canvas_items), so every menu, HUD panel, tooltip and overlay grows together and lays itself out on the smaller
## logical canvas - no font is enlarged one by one. Scripted test runs keep 100 % (their screenshots stay comparable).
class_name UISettings
extends RefCounted

const PATH := "user://settings.cfg"
const SCALE_MIN := 0.75
const SCALE_MAX := 1.75
const SCALE_STEP := 0.05
const SCALE_DEFAULT := 1.25

static var ui_scale := SCALE_DEFAULT
static var _loaded := false


static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		ui_scale = clampf(float(cfg.get_value("interface", "scale", SCALE_DEFAULT)), SCALE_MIN, SCALE_MAX)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keeps any other section
	cfg.set_value("interface", "scale", ui_scale)
	cfg.save(PATH)


## Reads the file (once) and applies the scale to the window; tests run at 100 %.
static func apply_at_start(tree: SceneTree) -> void:
	if not _loaded:
		load_settings()
	if CoreDemo.automated_run():
		tree.root.content_scale_factor = 1.0
		return
	tree.root.content_scale_factor = ui_scale


static func set_ui_scale(tree: SceneTree, k: float, save := true) -> void:
	ui_scale = clampf(snappedf(k, SCALE_STEP), SCALE_MIN, SCALE_MAX)
	tree.root.content_scale_factor = ui_scale
	if save:
		save_settings()
