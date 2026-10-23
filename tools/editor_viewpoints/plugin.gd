## Editor-only viewpoints for large world scenes (EDITOR-WORLD-01, phase 1).
##
## Adds a "Viewpoints" menu to the 3D editor toolbar. It finds the Terrain3D node of the
## edited scene and, when the scene has a ReferenceWorldBuilder, the world's sites.json,
## and moves only the *editor* camera to a chosen place at a fixed height over the
## terrain. It writes nothing: no scene change, no node, no resource, no world data.
@tool
class_name WorldViewpointsPlugin
extends EditorPlugin

const OVERVIEW_ALT_M := 9000.0
const TOWN_ALT_M := 140.0
const SITE_ALT_M := 90.0
const FAR_M := 30000.0

var _menu: MenuButton
## Menu item id -> viewpoint dictionary (see viewpoints()).
var _points := {}


func _enter_tree() -> void:
	# The editor's 3D viewports take their far plane from this preference when they are
	# created (default 4 km, which hides most of a 20 km world). Only ever raised; takes
	# effect the next time the editor starts. Per open viewport: View > Settings > Z-Far.
	var es := EditorInterface.get_editor_settings()
	if float(es.get_setting("editors/3d/default_z_far")) < FAR_M:
		es.set_setting("editors/3d/default_z_far", FAR_M)
	_menu = MenuButton.new()
	_menu.text = "Viewpoints"
	_menu.tooltip_text = "Move the editor camera over the world (editor camera only)"
	_menu.switch_on_hover = false
	var popup := _menu.get_popup()
	popup.about_to_popup.connect(_fill_menu)
	popup.id_pressed.connect(_go)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)


func _exit_tree() -> void:
	if _menu:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _menu)
		_menu.queue_free()
		_menu = null


func _fill_menu() -> void:
	var popup := _menu.get_popup()
	popup.clear()
	_points.clear()
	if _terrain() == null:
		popup.add_item("(open a scene with Terrain3D)", 0)
		popup.set_item_disabled(0, true)
		return
	var id := 0
	var section := ""
	for p in viewpoints():
		if p["section"] != section:
			section = p["section"]
			if not section.is_empty():
				popup.add_separator(section)
		popup.add_item(p["name"], id)
		_points[id] = p
		id += 1


func _go(id: int) -> void:
	if _points.has(id):
		move_camera(_points[id])


## Viewpoint list for the edited scene: {name, section, xz, alt, dist, pitch}. The overview
## is always there; towns and plateaus come from the world's sites.json when the scene
## has a ReferenceWorldBuilder.
static func viewpoints() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var terrain := _terrain()
	if terrain == null:
		return out
	out.append({"name": "Overview", "section": "", "xz": Vector2.ZERO, "alt": OVERVIEW_ALT_M,
			"dist": _world_extent() * 0.35, "pitch": 62.0})
	var sites := _load_sites()
	for s in sites.get("settlements", []):
		out.append({"name": "%s (%s)" % [s["name"], s["kind"]], "section": "Towns and villages",
				"xz": Vector2(s["pos"][0], s["pos"][2]), "alt": TOWN_ALT_M,
				"dist": maxf(float(s["radius_m"]) * 1.2, 220.0), "pitch": 22.0})
	for p in sites.get("plateaus", []):
		var r: float = maxf(float(p["radii_m"][0]), float(p["radii_m"][1]))
		out.append({"name": str(p["name"]), "section": "Plateaus / base sites",
				"xz": Vector2(p["pos"][0], p["pos"][2]), "alt": SITE_ALT_M + r * 0.25,
				"dist": r * 1.1, "pitch": 28.0})
	return out


## Moves the editor camera to the viewpoint with this name (first match, case-insensitive
## substring). Returns false if nothing matched.
static func goto_named(point_name: String) -> bool:
	for p in viewpoints():
		if (p["name"] as String).to_lower().contains(point_name.to_lower()):
			return move_camera(p)
	return false


## Looks at the terrain surface under `xz` from the south-east; the camera height is read
## from Terrain3D, never below the surface.
static func move_camera(p: Dictionary) -> bool:
	var terrain := _terrain()
	if terrain == null or terrain.data == null:
		return false
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam == null:
		return false
	var xz: Vector2 = p["xz"]
	var h: float = terrain.data.get_height(Vector3(xz.x, 0.0, xz.y))
	if is_nan(h):
		h = 0.0
	var target := Vector3(xz.x, h, xz.y)
	var dist: float = p["dist"]
	var alt: float = p["alt"]
	# The editor owns the camera's far plane and resets it every frame, so never go beyond
	# it: a point farther away than `far` is simply not drawn (grey viewport).
	var reach := sqrt(dist * dist + alt * alt)
	var limit := cam.far * 0.85
	if reach > limit:
		dist *= limit / reach
		alt *= limit / reach
	var pos := target + Vector3(dist * 0.5, 0.0, dist * 0.87)
	pos.y = h + alt
	var th: float = terrain.data.get_height(pos)
	if not is_nan(th):
		pos.y = maxf(pos.y, th + 30.0)
	cam.global_transform = Transform3D(Basis(), pos).looking_at(target, Vector3.UP)
	return true


static func _terrain() -> Terrain3D:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var found := root.find_children("*", "Terrain3D", true, false)
	return found[0] as Terrain3D if not found.is_empty() else null


static func _builder_config() -> Variant:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	for n in root.find_children("*", "ReferenceWorldBuilder", true, false):
		return n.get("config")
	return null


static func _world_extent() -> float:
	var cfg: Variant = _builder_config()
	return float(cfg.half_size()) if cfg != null and cfg.has_method("half_size") else 10000.0


static func _load_sites() -> Dictionary:
	var cfg: Variant = _builder_config()
	if not cfg is ReferenceWorldConfig:
		return {}
	var txt := FileAccess.get_file_as_string((cfg as ReferenceWorldConfig).source_directory.path_join("sites.json"))
	var parsed: Variant = JSON.parse_string(txt) if not txt.is_empty() else null
	return parsed if parsed is Dictionary else {}
