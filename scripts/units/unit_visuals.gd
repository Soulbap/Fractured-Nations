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
static func set_shadows_only(root: Node, enabled: bool) -> void:
	for mi in mesh_instances(root):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func make_ring_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


static func style_ring(ring: MeshInstance3D, faction: int, selected: bool) -> void:
	var mat := ring.material_override as StandardMaterial3D
	if mat == null:
		mat = make_ring_material()
		ring.material_override = mat
	var c := WorldState.faction_color(faction)
	mat.albedo_color = c.lightened(0.45) if selected else Color(c, 0.55)
	ring.scale = Vector3.ONE * (1.2 if selected else 0.85)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Grows the ring with the distance to the active camera (constant on-screen size
## beyond 40 m) so factions and selection stay readable from the tactical view.
static func scale_ring_for_camera(ring: MeshInstance3D, selected: bool) -> void:
	var cam := ring.get_viewport().get_camera_3d() if ring.is_inside_tree() else null
	if cam == null:
		return
	var d := cam.global_position.distance_to(ring.global_position)
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
