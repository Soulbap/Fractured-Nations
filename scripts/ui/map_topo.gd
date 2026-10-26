## UI-UX-03: the tactical map's base layer - the persistent 3D world drawn as a military topographic sheet. Built once when the
## map first opens, from the same data the world is made of (nothing invented, nothing stored):
##   terrain   Terrain3D's height maps as they are in memory (settlements, road shoulders and relief applied), 256 px per 2 km
##             region, with vegetation.png / info.png (forest, wetness, fields, rock, built-up, water) - drawn by
##             shaders/ui/topo_map.gdshader on this node: hillshade, height tint, contours at a zoom-dependent interval, territory;
##   vectors   RoadNetwork (the one road network, world and built roads, bridges with their state), the rivers and lakes of
##             water.json and the settlement houses of the WorldOverrides layers - drawn by StrategicMap in world coordinates
##             (one transform per draw, no per-point work in GDScript), so lines stay sharp at every zoom.
## This node sits behind the map (show_behind_parent) and only draws the terrain quad; panning and zooming change two uniforms.
class_name MapTopo
extends Control

const REGION_PX := 256

var ready_ok := false
var half := 10000.0
var area := Rect2()
var _mat: ShaderMaterial
var _height: ImageTexture
var _height_range := Vector2(0, 1000)
## [PackedVector2Array points (x, z), class StringName, width m, Rect2 bounds, key]
var roads: Array = []
## [PackedVector2Array, width m] pieces of the rivers
var rivers: Array = []
var lakes: Array[PackedVector2Array] = []
## Settlement houses as quads (x, z).
var houses: Array[PackedVector2Array] = []
var _house_bounds: Array[Rect2] = []
var build_ms := 0.0

const ROAD_STYLE := {
	&"primary": [Color(0.24, 0.13, 0.08), Color(0.89, 0.45, 0.22), 3.6, 0.0],
	&"secondary": [Color(0.30, 0.22, 0.10), Color(0.96, 0.80, 0.33), 2.8, 0.0],
	&"local": [Color(0.35, 0.32, 0.28), Color(0.99, 0.98, 0.94), 2.2, 0.035],
	&"street": [Color(0.40, 0.37, 0.33), Color(0.99, 0.98, 0.94), 1.6, 0.12],
	&"track": [Color(0.0, 0.0, 0.0, 0.0), Color(0.45, 0.33, 0.20, 0.9), 1.1, 0.06],
}
const BUILT_ROAD := [Color(0.20, 0.17, 0.10), Color(0.93, 0.76, 0.40), 2.4, 0.03]
const RIVER_COL := Color(0.30, 0.50, 0.70)
const RIVER_FILL := Color(0.60, 0.765, 0.875)
const HOUSE_COL := Color(0.24, 0.21, 0.19, 0.92)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func build(demo: CoreDemo) -> void:
	var t0 := Time.get_ticks_usec()
	half = demo.config.half_size()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ui/topo_map.gdshader")
	material = _mat
	_build_height(demo.sim.terrain)
	var src := "res://worlds/%s/source/" % demo.config.world_name
	for pair: Array in [["veg_tex", "vegetation.png"], ["info_tex", "info.png"]]:
		var p := ProjectSettings.globalize_path(src + String(pair[1]))
		var img := Image.load_from_file(p) if FileAccess.file_exists(p) else null
		if img:
			img.generate_mipmaps()
			_mat.set_shader_parameter(pair[0], ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("world_size", half * 2.0)
	for i in 4:
		_mat.set_shader_parameter("fac%d" % i, WorldState.faction_color(i))
	_build_roads(demo.sim.state.roads)
	_build_water(src)
	_build_houses(demo)
	ready_ok = _height != null
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _build_height(terrain: Terrain3D) -> void:
	if terrain == null or terrain.data == null:
		return
	var region_m := float(terrain.region_size) * terrain.vertex_spacing
	var n := int(roundf(half * 2.0 / region_m)) * REGION_PX
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	var lo := INF
	var hi := -INF
	for loc: Vector2i in terrain.data.get_region_locations():
		var region: Terrain3DRegion = terrain.data.get_region(loc)
		if region == null:
			continue
		var hm: Image = region.get_height_map()
		if hm == null:
			continue
		var small := hm.duplicate() as Image
		if small.get_format() != Image.FORMAT_RF:
			small.convert(Image.FORMAT_RF)
		small.resize(REGION_PX, REGION_PX, Image.INTERPOLATE_BILINEAR)
		var at := Vector2i(roundi((loc.x * region_m + half) / region_m) * REGION_PX, roundi((loc.y * region_m + half) / region_m) * REGION_PX)
		if at.x < 0 or at.y < 0 or at.x >= n or at.y >= n:
			continue
		img.blit_rect(small, Rect2i(0, 0, REGION_PX, REGION_PX), at)
		# The range from a coarse sample (holes are NaN / 0 outside the data).
		for y in range(0, REGION_PX, 16):
			for x in range(0, REGION_PX, 16):
				var v := small.get_pixel(x, y).r
				if is_finite(v):
					lo = minf(lo, v)
					hi = maxf(hi, v)
	if not is_finite(lo):
		return
	_height_range = Vector2(lo, hi)
	_height = ImageTexture.create_from_image(img)
	_mat.set_shader_parameter("height_tex", _height)
	_mat.set_shader_parameter("height_range", _height_range)
	_mat.set_shader_parameter("height_texel", Vector2(1.0 / n, 1.0 / n))


func _build_roads(net: RoadNetwork) -> void:
	roads.clear()
	if net == null:
		return
	for r: RoadNetwork.Road in net.all_roads():
		var pts := PackedVector2Array()
		var last := Vector2.INF
		for p in r.points:
			var q := Vector2(p.x, p.z)
			if q.distance_to(last) >= 3.0:
				pts.append(q)
				last = q
		var e := Vector2(r.points[r.points.size() - 1].x, r.points[r.points.size() - 1].z) if r.points.size() > 0 else Vector2.INF
		if pts.size() > 0 and pts[pts.size() - 1] != e and e.is_finite():
			pts.append(e)
		if pts.size() >= 2:
			roads.append([pts, StringName("built") if r.built else r.cls, r.width, r.bounds, r.key])
	# Wider roads over narrower ones at junctions.
	var rank := {&"track": 0, &"street": 1, &"local": 2, &"built": 2, &"secondary": 3, &"primary": 4}
	roads.sort_custom(func(a: Array, b: Array) -> bool: return int(rank.get(a[1], 1)) < int(rank.get(b[1], 1)))


func _build_water(src: String) -> void:
	rivers.clear()
	lakes.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(src + "water.json"))
	if not data is Dictionary:
		return
	var rv: Dictionary = data.get("river", {})
	var pts: Array = rv.get("points", [])
	var widths: Array = rv.get("width", [])
	# Pieces of ~16 points with their mean width (draw_polyline has one width per call).
	var i := 0
	while i < pts.size() - 1:
		var piece := PackedVector2Array()
		var w := 0.0
		var j := i
		while j < mini(i + 17, pts.size()):
			piece.append(Vector2(float(pts[j][0]), float(pts[j][1])))
			w += float(widths[j]) if j < widths.size() else 20.0
			j += 1
		rivers.append([piece, w / piece.size()])
		i = j - 1
	for lk: Dictionary in data.get("lakes", []):
		var o := PackedVector2Array()
		for q: Array in lk.get("outline", []):
			o.append(Vector2(float(q[0]), float(q[1])))
		if o.size() >= 3:
			o.append(o[0])
			lakes.append(o)


func _build_houses(demo: CoreDemo) -> void:
	houses.clear()
	_house_bounds.clear()
	var vs := demo.vegetation
	if vs == null or vs.overrides == null or vs.library == null:
		return
	var recs: Dictionary = vs.overrides.records
	for id in recs:
		var r: Dictionary = recs[id]
		var mesh := int(r.get("mesh", -1))
		if r.get("removed", false) or not mesh in [16, 17, 18]:
			continue
		var def := vs.library.get_def(mesh)
		if def == null:
			continue
		var xf: Transform3D = vs.overrides._decode(r.transform)
		for bx: Array in def.boxes_of(xf):
			var c: Vector3 = bx[0]
			var yaw: float = bx[1]
			var ax := Vector2(cos(yaw), -sin(yaw)) * float(bx[2])
			var az := Vector2(sin(yaw), cos(yaw)) * float(bx[4])
			var cc := Vector2(c.x, c.z)
			var quad := PackedVector2Array([cc + ax + az, cc + ax - az, cc - ax - az, cc - ax + az])
			houses.append(quad)
			_house_bounds.append(Rect2(cc, Vector2.ZERO).grow(maxf(float(bx[2]), float(bx[4])) * 1.5))


## The territory as one channel per faction (see StrategicMap._update_territory).
func set_territory(tex: Texture2D) -> void:
	if _mat:
		_mat.set_shader_parameter("terr_tex", tex)


## Contour interval for a zoom (px per m): contours about every 8-25 px on moderate ground.
static func interval_for(zoom: float) -> float:
	if zoom < 0.05:
		return 50.0
	if zoom < 0.12:
		return 20.0
	if zoom < 0.4:
		return 10.0
	return 5.0


func set_view(p_area: Rect2, zoom: float, show_territory: bool, territory_alpha: float, show_relief: bool) -> void:
	area = p_area
	if _mat:
		_mat.set_shader_parameter("interval", interval_for(zoom))
		_mat.set_shader_parameter("territory", territory_alpha if show_territory else 0.0)
		_mat.set_shader_parameter("contours", 1.0 if show_relief else 0.0)
		_mat.set_shader_parameter("relief", 1.0 if show_relief else 0.35)
	queue_redraw()


func _draw() -> void:
	# (The dark surround is a separate ColorRect behind this node: everything drawn here goes through the topographic shader.)
	if ready_ok and _height:
		draw_texture_rect(_height, area, false)


# --- Vector layers (called from StrategicMap._draw with the world transform set) -----------------------------------------

## Rivers and lake shores.
func draw_water(ci: CanvasItem, zoom: float, view: Rect2) -> void:
	var px := 1.0 / zoom
	for lk in lakes:
		ci.draw_polyline(lk, RIVER_COL, 1.2 * px, true)
	for r: Array in rivers:
		var pts: PackedVector2Array = r[0]
		if not view.grow(200.0).has_point(pts[0]) and not view.grow(200.0).has_point(pts[pts.size() - 1]):
			continue
		var w := maxf(float(r[1]), 2.0 * px)
		ci.draw_polyline(pts, RIVER_COL, w + 1.6 * px, true)
		ci.draw_polyline(pts, RIVER_FILL, w, true)


## Roads by class (casing and fill, real width once it is wider than the symbol), bridges with their state, and houses when close.
func draw_roads(ci: CanvasItem, zoom: float, view: Rect2, net: RoadNetwork) -> void:
	var px := 1.0 / zoom
	for r: Array in roads:
		var st: Array = BUILT_ROAD if r[1] == &"built" else ROAD_STYLE.get(r[1], ROAD_STYLE[&"local"])
		if zoom < float(st[3]):
			continue
		if not (r[3] as Rect2).intersects(view):
			continue
		var pts: PackedVector2Array = r[0]
		var w := maxf(float(st[2]) * px * clampf(zoom / 0.08, 0.6, 1.0), float(r[2]))
		var casing: Color = st[0]
		if casing.a > 0.0:
			ci.draw_polyline(pts, casing, w + 1.5 * px, true)
		ci.draw_polyline(pts, st[1], w, true)
	if net == null or zoom < 0.05:
		return
	for b: RoadNetwork.Bridge in net.bridges:
		if not b.bounds.intersects(view):
			continue
		for s: Array in b.segs:
			var a: Vector2 = s[0]
			var e: Vector2 = s[1]
			var d := (e - a).normalized()
			var n := Vector2(-d.y, d.x) * (float(s[2]) + 1.5 * px)
			var col := Color(0.12, 0.10, 0.08) if b.is_open() else Color(0.75, 0.12, 0.10)
			ci.draw_line(a + n, e + n, col, 1.4 * px, true)
			ci.draw_line(a - n, e - n, col, 1.4 * px, true)
		if not b.is_open():
			var c := Vector2(b.center.x, b.center.z)
			var k := 6.0 * px
			ci.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), Color(0.75, 0.12, 0.10), 2.0 * px)
			ci.draw_line(c + Vector2(-k, k), c + Vector2(k, -k), Color(0.75, 0.12, 0.10), 2.0 * px)


func draw_houses(ci: CanvasItem, zoom: float, view: Rect2) -> void:
	if zoom < 0.12:
		return
	for i in houses.size():
		if _house_bounds[i].intersects(view):
			ci.draw_colored_polygon(houses[i], HOUSE_COL)
