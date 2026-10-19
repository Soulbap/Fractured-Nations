## The construction set of WORLD-BASE-01: every buildable type and its numbers.
##
## Dimensions follow the real-world references listed in docs/WORLD-BASE-01_REPORT.md
## (20 ft ISO shelters, HESCO MIL-series cells, 2.4 m chain-link, F-shape concrete
## barriers). Meshes come from tools/blender/structures/*.py -> assets/structures/*.glb.
## Kept in code so the numbers live next to each other; a .tres per type would work the
## same way (StructureDef is a Resource).
class_name StructureCatalog
extends RefCounted

const CATEGORIES: Array[String] = ["Buildings", "Defences"]
const ASSET_DIR := "res://assets/structures/"

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


## Wire mesh, chain-link and netting surfaces are alpha-tested textures; glTF imports may
## arrive as alpha blend, which sorts badly on long fence lines. Force scissor + both sides.
static func _tune_materials(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		if m == null:
			continue
		var n := m.resource_name.to_lower()
		if n.contains("mesh") or n.contains("chainlink") or n.contains("net") or n.contains("wire"):
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


static func _add(d: StructureDef) -> void:
	if d.mesh_path == "":
		d.mesh_path = ASSET_DIR + String(d.id) + ".glb"
	_defs.append(d)
	_by_id[d.id] = d


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
