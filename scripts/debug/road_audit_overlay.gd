class_name RoadAuditOverlay
extends Node3D
## Debug overlay for the road audit (AI-WAR-LOGISTICS-01), toggled with F8 or started with `--road-overlay`.
## Roads of the main network are drawn dim green, every other component orange (an intentional isolation blue); a gap the
## router repaired is a cyan beam, a near miss between two networks that were not joined a red beam with the closing
## line, a place a vehicle cannot enter or reach from the main network a magenta beam. The same data as `--road-audit`,
## computed from the router's own graph, so edited or new roads show up the next time the overlay is rebuilt (F8 twice).

const BEAM_M := 60.0

var sim: WorldSim
var summary: Array[String] = []
var _mesh := ImmediateMesh.new()


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
	name = "RoadAuditOverlay"
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 10
	mi.material_override = m
	add_child(mi)


## Recomputes the audit and redraws.
func rebuild() -> void:
	var audit := RoadAudit.new(sim)
	var comps := audit.components()
	var comp_of := RoadAudit.component_of_roads(comps)
	var rep := audit.audit_graph(200)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for rd: RoadNetwork.Road in audit.net.all_roads():
		var comp: int = comp_of.get(rd.key, -1)
		var col := Color(0.25, 0.85, 0.3, 0.45)
		if comp != 0:
			col = Color(1.0, 0.55, 0.1, 0.95) if audit.intentional.get(rd.name, "") == "" else Color(0.3, 0.5, 1.0, 0.95)
		for i in range(1, rd.points.size()):
			_line(rd.points[i - 1] + Vector3.UP * 1.2, rd.points[i] + Vector3.UP * 1.2, col)
	for g: Dictionary in audit.router.repaired_gaps:
		_beam(g.at, Color(0.2, 0.9, 1.0), 30.0)
	var near_n := 0
	for nm: Dictionary in rep.get("near_misses", []):
		_beam(Vector3(nm.at[0], 0.0, nm.at[1]), Color(1.0, 0.15, 0.15), BEAM_M)
		near_n += 1
	var def := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var node_comp := audit.node_components()
	var bad: Array[String] = []
	for l: Dictionary in audit.locations():
		var pr := audit.probe_location(l, node_comp, def)
		if not pr.get("enter_ok", false) or int(pr.get("component", -1)) != 0 or float(pr.get("main_network_m", 0.0)) > 1500.0:
			_beam(l.pos, Color(1.0, 0.1, 1.0), BEAM_M * 1.4)
			bad.append("%s (%s): %s" % [l.name, l.kind, pr.get("enter", "") if not pr.get("enter_ok", false) else "not on the main road network"])
	_mesh.surface_end()
	summary = ["%d roads, %d nodes, %d components; %d gaps repaired; %d near misses; %d places not reachable" % [rep.roads, rep.nodes, rep.components, rep.repaired_gaps, near_n, bad.size()]]
	summary.append_array(bad)
	for line in summary:
		print("ROAD-OVERLAY ", line)


func _line(a: Vector3, b: Vector3, col: Color) -> void:
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(col)
	_mesh.surface_add_vertex(b)


func _beam(p: Vector3, col: Color, h: float) -> void:
	var g := Vector3(p.x, sim.vehicles.ground_at(p), p.z)
	_line(g, g + Vector3.UP * h, col)
	_line(g + Vector3(-4, 1, 0), g + Vector3(4, 1, 0), col)
	_line(g + Vector3(0, 1, -4), g + Vector3(0, 1, 4), col)
