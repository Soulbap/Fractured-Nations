## Faction colouring and selection feedback shared by soldier and vehicle bodies.
##
## Works on placeholder primitives and on imported glTF meshes alike: a surface whose
## material (or node) name contains "uniform", "hull" or "body" takes the faction's
## uniform colour, one containing "patch" or "faction" takes the bright faction colour.
## Everything else keeps the material it was authored with.
class_name UnitVisuals
extends RefCounted

## Uniform colours per faction: North olive green, South desert khaki, East grey-blue.
const UNIFORM_COLORS: Array[Color] = [Color(0.30, 0.36, 0.24), Color(0.60, 0.52, 0.36), Color(0.36, 0.40, 0.46)]


static func uniform_color(faction: int) -> Color:
	return UNIFORM_COLORS[faction] if faction >= 0 and faction < UNIFORM_COLORS.size() else Color.GRAY


static func apply_faction(root: Node, faction: int) -> void:
	var uniform := uniform_color(faction)
	var patch := WorldState.faction_color(faction)
	for mi in mesh_instances(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var node_name := String(mi.name).to_lower()
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			var mat_name := (mat.resource_name if mat else "").to_lower()
			var role := ""
			if "patch" in mat_name or "faction" in mat_name or "patch" in node_name:
				role = "patch"
			elif "uniform" in mat_name or "hull" in mat_name or "body" in node_name or "uniform" in node_name:
				role = "uniform"
			if role == "":
				continue
			var m := StandardMaterial3D.new()
			m.albedo_color = patch if role == "patch" else uniform
			m.roughness = 0.6 if role == "patch" else 0.92
			m.resource_name = mat_name
			mi.set_surface_override_material(s, m)


## While a body is possessed its mesh must not sit in front of the first-person camera;
## keeping the shadow preserves the soldier's presence on the ground.
## GAMEPLAY-02 (controls): render layer of the possessed soldier's upper body; the sun's shadow_caster_mask leaves it out
## (no_body_shadow_on). Lying where the first-person arms and weapon are, its shadow speckled them (shadow acne).
const FP_NO_SHADOW_LAYER := 1 << 19
const LOWER_BODY := ["trouser", "boot", "pant", "leg", "shoe"]


static func set_shadows_only(root: Node, enabled: bool) -> void:
	for mi in mesh_instances(root):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# first person: only the legs keep their shadow on the ground
		if enabled and not _lower_body(mi):
			mi.layers = FP_NO_SHADOW_LAYER
		elif not enabled and mi.layers == FP_NO_SHADOW_LAYER:
			mi.layers = 1


static func _lower_body(mi: MeshInstance3D) -> bool:
	var n := String(mi.name).to_lower()
	for k: String in LOWER_BODY:
		if n.contains(k):
			return true
	return false


## The directional lights under `root` cast no shadow from FP_NO_SHADOW_LAYER.
static func no_body_shadow_on(root: Node) -> void:
	for l in root.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_caster_mask &= ~FP_NO_SHADOW_LAYER


static func make_ring_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## UI-01C: unit markers are a tactical-view aid; the HUD switches them off in first person and while
## driving (GameHUD sets this every frame).
static var markers_visible := true
static var _dot: CylinderMesh


## soldier (UI-01C): a soldier's marker is a small flat dot, not a ring - many rings around a squad
## overlapped into a blur; the squad itself is marked by the HUD (brackets and its tag). Vehicles keep
## their footprint ring.
static func style_ring(ring: MeshInstance3D, faction: int, selected: bool, soldier := false) -> void:
	var mat := ring.material_override as StandardMaterial3D
	if mat == null:
		mat = make_ring_material()
		ring.material_override = mat
	var c := WorldState.faction_color(faction)
	if soldier:
		ring.mesh = _dot_mesh()
		mat.albedo_color = Color(c.lightened(0.6), 0.95) if selected else Color(c.lightened(0.1), 0.5)
		# UI-01C.1: drawn over foliage, so a squad in a forest still shows where its soldiers are.
		mat.no_depth_test = true
		mat.render_priority = 5
		ring.scale = Vector3(0.34 if selected else 0.24, 1.0, 0.34 if selected else 0.24)
	else:
		mat.albedo_color = c.lightened(0.45) if selected else Color(c, 0.55)
		ring.scale = Vector3.ONE * (1.2 if selected else 0.85)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _dot_mesh() -> CylinderMesh:
	if _dot == null:
		_dot = CylinderMesh.new()
		_dot.top_radius = 1.0
		_dot.bottom_radius = 1.0
		_dot.height = 0.03
		_dot.radial_segments = 20
		_dot.rings = 1
	return _dot


## Grows the marker with the distance to the active camera (constant on-screen size beyond 40 m) so
## factions and selection stay readable from the tactical view; a soldier's dot stops growing sooner
## (7x) so a squad's dots stay apart. Hidden while markers_visible is off.
static func scale_ring_for_camera(ring: MeshInstance3D, selected: bool, soldier := false) -> void:
	ring.transparency = 0.0 if markers_visible else 1.0
	var cam := ring.get_viewport().get_camera_3d() if ring.is_inside_tree() else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(ring.global_position)
	if soldier:
		var r := (0.34 if selected else 0.24) * clampf(d / 40.0, 1.0, 7.0)
		ring.scale = Vector3(r, 1.0, r)
	else:
		ring.scale = Vector3.ONE * ((1.2 if selected else 0.85) * clampf(d / 40.0, 1.0, 12.0))


static func mesh_instances(root: Node) -> Array:
	var out := []
	_collect(root, out)
	return out


static func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
