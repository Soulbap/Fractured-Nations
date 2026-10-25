## Every buildable type and its numbers.
##
## Two sources, one list:
##   * the WORLD-BASE-01 field set, kept in code so its numbers live next to each other
##     (20 ft ISO shelters, HESCO MIL-series cells, 2.4 m chain-link, F-shape barriers;
##     meshes from tools/blender/structures/*.py -> assets/structures/*.glb), plus the
##     WORLD-PLAYTEST-01 roads and paved areas;
##   * WORLD-INTEGRATION-03: the ASSET-PRODUCTION-01 library as StructureDef resources
##     (assets/military/defs/*.tres for the buildings and modules, written by the asset
##     pipeline; assets/military/defs/props/*.tres for the curated props, written by
##     tools/asset_production/make_prop_defs.py). A new asset is a new .tres, no code.
## Asset categories ("Ammunition", "Fuel", ...) are folded into the six menu categories here:
## grouping is a gameplay decision, the asset data stays as authored.
class_name StructureCatalog
extends RefCounted

const CATEGORIES: Array[String] = ["Buildings", "Training", "Logistics", "Defences", "Infrastructure", "Roads"]
const ASSET_DIR := "res://assets/structures/"
const DEF_DIRS: Array[String] = ["res://assets/military/defs/", "res://assets/military/defs/props/"]
## Asset-side category -> menu category (anything not listed keeps its own name).
const MENU_CATEGORY := {
	"Ammunition": "Logistics", "Fuel": "Logistics", "Maintenance": "Logistics", "Containers": "Logistics",
	"Checkpoint": "Defences", "Fences": "Defences",
	"Communications": "Infrastructure", "Power": "Infrastructure", "Shelter": "Infrastructure", "Signs": "Infrastructure",
	"Vehicle training": "Training",
}

static var _defs: Array[StructureDef] = []
static var _by_id := {}
static var _meshes := {}


static func all() -> Array[StructureDef]:
	if _defs.is_empty():
		_build()
	return _defs


static func get_def(id: StringName) -> StructureDef:
	if _defs.is_empty():
		_build()
	return _by_id.get(id)


static func in_category(category: String) -> Array[StructureDef]:
	var out: Array[StructureDef] = []
	for d in all():
		if d.category == category:
			out.append(d)
	return out


## The type's mesh (first MeshInstance3D of the GLB, with import LODs), or a placeholder
## box standing on the origin when the asset is missing.
static func mesh_of(def: StructureDef) -> Mesh:
	if def.is_surface():
		return null
	if _meshes.has(def.id):
		return _meshes[def.id]
	var mesh: Mesh = null
	if def.mesh_path != "" and ResourceLoader.exists(def.mesh_path):
		var scene: PackedScene = load(def.mesh_path)
		var root := scene.instantiate()
		var mi := _first_mesh_instance(root)
		if mi:
			mesh = mi.mesh
			_tune_materials(mesh)
		root.free()
	if mesh == null:
		mesh = _placeholder(def)
	_meshes[def.id] = mesh
	return mesh


static func _first_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh_instance(c)
		if r:
			return r
	return null


## Wire mesh and chain-link are alpha blended, the camouflage net alpha tested; both sides.
## Vertex colours (baked ground dirt) always multiply the albedo.
static func _tune_materials(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m == null:
			continue
		# Ground dirt / contact darkening is baked into vertex colours (Blender ground_ao).
		if mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR:
			m.vertex_color_use_as_albedo = true
		var n := m.resource_name.to_lower()
		if n in ["shelterfabric", "kspanend", "geotextile"]:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED  # single-sheet surfaces seen from both sides
		if n in ["hescomesh", "chainlink"]:
			# Thin wires: alpha blending, so distant mips fade to a grey haze like real
			# mesh instead of vanishing (alpha scissor loses wires under 1 px).
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		elif n == "camonet":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.5
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE


static func _placeholder(def: StructureDef) -> Mesh:
	var box := BoxMesh.new()
	var s := def.size
	if def.linear:
		s.x = def.module_length
	box.size = s
	var st := SurfaceTool.new()
	st.create_from(box, 0)
	var arr := box.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += s.y * 0.5
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.color
	mat.roughness = 0.9
	mesh.surface_set_material(0, mat)
	return mesh


static func _surface_def(id: StringName, name: String, kind: StructureDef.Surface, width: float, tex: int, over: int,
		blend: float, grade: float, cost: float) -> StructureDef:
	var d := StructureDef.new()
	d.id = id
	d.display_name = name
	d.category = "Roads"
	d.surface = kind
	d.surface_width = width
	d.surface_texture = tex
	d.surface_overlay = over
	d.surface_blend = blend
	d.max_grade = grade
	d.travel_cost = cost
	d.max_cut = 3.0
	d.blocks_navigation = false
	d.size = Vector3(width, 0.1, width)
	return d


static func _add(d: StructureDef) -> void:
	d.display_name = sentence_case(d.display_name)
	if d.mesh_path == "":
		d.mesh_path = ASSET_DIR + String(d.id) + ".glb"
	_defs.append(d)
	_by_id[d.id] = d


## GAMEPLAY-05B: one style for every structure name the player reads (build menu, messages, panels): the first word
## capitalised, the rest lower case, acronyms and words with digits kept ("Guard Tower" -> "Guard tower", "HESCO barrier").
## StructureDef.display_name is the one name; FacilityDefs and the build menu read it.
static func sentence_case(n: String) -> String:
	var words := n.split(" ")
	for i in range(1, words.size()):
		var w := words[i]
		if w.length() > 1 and w == w.to_upper() or w.contains("(") or w.is_valid_int() or w.lstrip("0123456789") != w:
			continue
		words[i] = w.to_lower()
	return " ".join(words)


## WORLD-INTEGRATION-03: every StructureDef resource in DEF_DIRS, in file order. A resource
## whose id the code-built set already has is skipped (the code set wins), one without a
## menu category goes to "Buildings".
static func _load_resource_defs() -> void:
	for dir_path in DEF_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var names: Array[String] = []
		for f in dir.get_files():
			if f.ends_with(".tres") or f.ends_with(".tres.remap"):
				names.append(f.trim_suffix(".remap"))
		names.sort()
		for f in names:
			var d := load(dir_path + f) as StructureDef
			if d == null or d.id == &"" or _by_id.has(d.id):
				continue
			d.category = MENU_CATEGORY.get(d.category, d.category)
			if not CATEGORIES.has(d.category):
				d.category = "Buildings"
			# Props and road dressing are small: cells beyond 700 m do not draw them at all
			# (buildings and modules keep the 1600 m default, like the WORLD-BASE-01 set).
			if d.mesh_path.contains("/props/") or d.mesh_path.contains("/roads/"):
				d.visible_range = minf(d.visible_range, 700.0)
			_add(d)


static func _box(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> AABB:
	return AABB(Vector3(x0, y0, z0), Vector3(x1 - x0, y1 - y0, z1 - z0))


static func _build() -> void:
	var d: StructureDef

	# --- Buildings -------------------------------------------------------------------
	d = StructureDef.new()
	d.id = &"command_post"
	d.display_name = "Command post"
	d.description = "Expandable 20 ft ISO shelter (tactical operations cell) with a side extension, A/C units, steps and an antenna mast."
	d.size = Vector3(6.6, 3.1, 5.2)
	d.collision_boxes = [_box(-3.1, -0.4, -2.55, 3.1, 2.9, 1.95), _box(-0.9, -0.4, 1.95, 0.9, 0.6, 2.6)]
	d.max_slope_deg = 7.0
	d.max_ground_gap = 0.7
	d.color = Color(0.36, 0.38, 0.27)
	_add(d)

	d = StructureDef.new()
	d.id = &"barracks"
	d.display_name = "Barracks module"
	d.description = "Containerized housing unit (CHU): 20 ft accommodation container on blocks with door, windows, A/C and steps."
	d.size = Vector3(6.3, 2.9, 3.6)
	d.collision_boxes = [_box(-3.05, -0.4, -1.25, 3.05, 2.85, 1.25), _box(-0.6, -0.4, -1.95, 0.6, 0.45, -1.25)]
	d.max_slope_deg = 7.0
	d.max_ground_gap = 0.7
	d.color = Color(0.72, 0.66, 0.52)
	_add(d)

	d = StructureDef.new()
	d.id = &"supply_storage"
	d.display_name = "Supply storage"
	d.description = "K-span corrugated steel arch building for supplies, concrete footing, roll-up door."
	d.size = Vector3(10.0, 5.2, 14.0)
	d.max_slope_deg = 5.0
	d.max_ground_gap = 0.9
	d.color = Color(0.68, 0.64, 0.52)
	_add(d)

	d = StructureDef.new()
	d.id = &"vehicle_shelter"
	d.display_name = "Vehicle shelter"
	d.description = "Steel frame vehicle maintenance shelter with a fabric cover, open front for vehicles."
	d.size = Vector3(8.4, 5.6, 12.4)
	# Walls and roof only: soldiers and vehicles fit inside.
	d.collision_boxes = [_box(-4.2, -0.3, -6.2, -3.9, 3.4, 6.2), _box(3.9, -0.3, -6.2, 4.2, 3.4, 6.2),
		_box(-4.2, -0.3, 5.9, 4.2, 3.4, 6.2), _box(-4.2, 3.4, -6.2, 4.2, 5.6, 6.2)]
	d.max_slope_deg = 6.0
	d.max_ground_gap = 0.8
	d.color = Color(0.3, 0.33, 0.24)
	_add(d)

	d = StructureDef.new()
	d.id = &"guard_tower"
	d.display_name = "Guard tower"
	d.category = "Defences"
	d.description = "Timber guard tower: braced legs, sandbagged fighting position on a 4 m platform, corrugated roof and stairs."
	d.size = Vector3(3.8, 6.9, 3.8)
	# Legs, platform, parapet walls, roof and a stair ramp (walkable in first person).
	d.collision_boxes = [_box(-1.5, -0.3, -1.5, -1.3, 4.0, -1.3), _box(1.3, -0.3, -1.5, 1.5, 4.0, -1.3),
		_box(-1.5, -0.3, 1.3, -1.3, 4.0, 1.5), _box(1.3, -0.3, 1.3, 1.5, 4.0, 1.5),
		_box(-1.7, 3.85, -1.7, 1.7, 4.05, 1.7),
		_box(-1.7, 4.05, -1.7, 1.7, 5.15, -1.5), _box(-1.7, 4.05, -1.7, -1.5, 5.15, 1.7), _box(1.5, 4.05, -1.7, 1.7, 5.15, 1.7),
		_box(-1.7, 4.05, 1.5, 0.4, 5.15, 1.7),
		_box(-1.9, 6.4, -1.9, 1.9, 6.6, 1.9)]
	# Stairs at the back right, 42 degrees: walkable for the first-person controller.
	d.ramps = [_box(0.45, 0.0, 1.7, 1.45, 4.05, 6.1)]
	d.max_slope_deg = 12.0
	d.max_ground_gap = 0.8
	d.color = Color(0.55, 0.45, 0.32)
	_add(d)

	d = StructureDef.new()
	d.id = &"fence_gate"
	d.display_name = "Fence gate"
	d.category = "Defences"
	d.description = "Double swing gate, 4 m opening between 2.4 m galvanized posts. Snaps to fence ends; soldiers path through it."
	d.size = Vector3(4.3, 2.9, 0.6)
	d.collision_boxes = [_box(-2.2, -0.3, -0.1, -2.0, 2.6, 0.1), _box(2.0, -0.3, -0.1, 2.2, 2.6, 0.1)]
	d.snap_points = PackedVector3Array([Vector3(-2.1, 0, 0), Vector3(2.1, 0, 0)])
	d.connect_group = &"fence"
	d.blocks_navigation = false
	d.max_slope_deg = 10.0
	d.max_ground_gap = 0.5
	d.color = Color(0.6, 0.62, 0.6)
	_add(d)

	# --- Linear defences -------------------------------------------------------------
	d = StructureDef.new()
	d.id = &"hesco"
	d.display_name = "HESCO barrier"
	d.category = "Defences"
	d.description = "Sand-filled HESCO cell (MIL1-type, 1.06 m cell, 1.37 m high). Draw lines and perimeters; cells step with the terrain."
	d.linear = true
	d.module_length = 1.06
	d.size = Vector3(1.06, 1.37, 1.06)
	d.layout = StructureDef.Layout.CENTERED
	d.fit = StructureDef.Fit.STEP
	d.max_slope_deg = 22.0
	d.max_ground_gap = 0.55
	d.sink = 0.08
	d.connect_group = &"hesco"
	d.color = Color(0.7, 0.62, 0.45)
	_add(d)

	d = StructureDef.new()
	d.id = &"hesco_tall"
	d.display_name = "HESCO barrier (tall)"
	d.category = "Defences"
	d.description = "Large HESCO cell (MIL7-type, 2.13 m cell, 2.21 m high) for main perimeter walls."
	d.linear = true
	d.module_length = 2.13
	d.size = Vector3(2.13, 2.21, 2.13)
	d.layout = StructureDef.Layout.CENTERED
	d.fit = StructureDef.Fit.STEP
	d.max_slope_deg = 16.0
	d.max_ground_gap = 0.8
	d.sink = 0.1
	d.connect_group = &"hesco"
	d.color = Color(0.7, 0.62, 0.45)
	_add(d)

	d = StructureDef.new()
	d.id = &"fence"
	d.display_name = "Chain-link fence"
	d.category = "Defences"
	d.description = "2.4 m galvanized chain-link panel with Y-arm outriggers and barbed wire, 3 m post spacing. Follows the slope with vertical posts."
	d.linear = true
	d.module_length = 3.0
	d.size = Vector3(3.0, 2.95, 0.5)
	d.collision_boxes = [_box(-1.5, -0.3, -0.06, 1.5, 2.45, 0.06)]
	d.layout = StructureDef.Layout.SPAN
	d.fit = StructureDef.Fit.SHEAR
	d.max_slope_deg = 30.0
	d.max_ground_gap = 0.5
	d.sink = 0.03
	d.connect_group = &"fence"
	d.color = Color(0.62, 0.64, 0.62)
	_add(d)

	d = StructureDef.new()
	d.id = &"concrete_barrier"
	d.display_name = "Concrete barrier"
	d.category = "Defences"
	d.description = "F-shape concrete barrier, 3 m x 0.81 m, 0.61 m base, lifting slots. Pitches with the slope."
	d.linear = true
	d.module_length = 3.0
	d.size = Vector3(3.0, 0.81, 0.61)
	d.layout = StructureDef.Layout.SPAN
	d.fit = StructureDef.Fit.PITCH
	d.max_slope_deg = 14.0
	d.max_ground_gap = 0.25
	d.sink = 0.03
	d.connect_group = &"concrete"
	d.color = Color(0.66, 0.65, 0.62)
	_add(d)

	# --- Roads and paved areas (WORLD-PLAYTEST-01) ----------------------------------
	# Built into the terrain (graded, painted with the world's own road textures), part of
	# the road network the AI routes on. Widths fit one military truck / AFV (2.5-3.6 m)
	# per lane; grades are what a loaded truck manages on the surface.
	d = _surface_def(&"road_dirt", "Dirt track", StructureDef.Surface.ROAD, 4.0, WorldTerrainGenerator.TEX_DIRT,
		ReferenceWorldBuilder.TEX_GRAVEL, 0.25, 0.16, 0.6)
	d.description = "Bulldozed dirt track, 4 m. Quick to lay, up to 16 % grade. Draw a curve: click control points, Enter / right click finishes; drag a point to adjust it."
	_add(d)
	d = _surface_def(&"road_gravel", "Gravel road", StructureDef.Surface.ROAD, 5.5, ReferenceWorldBuilder.TEX_GRAVEL,
		WorldTerrainGenerator.TEX_DIRT, 0.3, 0.12, 0.5)
	d.description = "Compacted gravel road, 5.5 m (two trucks pass slowly), up to 12 % grade."
	_add(d)
	d = _surface_def(&"road_asphalt", "Asphalt road", StructureDef.Surface.ROAD, 7.0, ReferenceWorldBuilder.TEX_ASPHALT,
		ReferenceWorldBuilder.TEX_GRAVEL, 0.08, 0.09, 0.45)
	d.description = "Two-lane asphalt road, 7 m, up to 9 % grade."
	_add(d)
	d = _surface_def(&"area_gravel", "Gravel yard", StructureDef.Surface.AREA, 0.0, ReferenceWorldBuilder.TEX_GRAVEL,
		WorldTerrainGenerator.TEX_DIRT, 0.3, 0.06, 1.0)
	d.description = "Gravel hardstanding for vehicle yards and motor pools. Click the corners, Enter / right click closes the polygon. Graded to one plane (max 6 %)."
	_add(d)
	d = _surface_def(&"area_asphalt", "Asphalt yard", StructureDef.Surface.AREA, 0.0, ReferenceWorldBuilder.TEX_ASPHALT,
		ReferenceWorldBuilder.TEX_GRAVEL, 0.06, 0.05, 1.0)
	d.description = "Asphalt apron / parking area. Graded to one plane (max 5 %)."
	_add(d)

	# --- ASSET-PRODUCTION-01 library (WORLD-INTEGRATION-03) --------------------------
	_load_resource_defs()
