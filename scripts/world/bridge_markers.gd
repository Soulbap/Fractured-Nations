## NAVIGATION N1-C1: a plain debug indicator for bridges that are not open (no bridge asset is changed).
##
## Two red barrier bars across the deck, one at each end, and a label over the middle ("<name>: closed"), drawn only while the
## bridge is closed or disabled. Nothing here collides or decides anything: the state lives in RoadNetwork.Bridge, navigation
## reads it there, and this node only shows it, so the picture can never disagree with what the planners do. A deck that is
## disabled stays standing and visible; the markers are all that change.
class_name BridgeMarkers
extends Node3D

const BAR_H := 1.1
const BAR_THICK := 0.5
## Barrier colours by state (CLOSED: amber-red, DISABLED: dark red).
const COLORS := {RoadNetwork.BridgeState.CLOSED: Color(1.0, 0.25, 0.1), RoadNetwork.BridgeState.DISABLED: Color(0.55, 0.0, 0.0)}

var net: RoadNetwork
## bridge id -> Node3D holding that bridge's markers
var _nodes := {}
var _mat_cache := {}


func bind(p_net: RoadNetwork) -> void:
	net = p_net
	if not net.bridge_changed.is_connected(_on_changed):
		net.bridge_changed.connect(_on_changed)
	for b: RoadNetwork.Bridge in net.blocked_bridges():
		_on_changed(b)


## The ids of the bridges that currently show markers (tests).
func shown() -> Array:
	return _nodes.keys()


func _on_changed(b: RoadNetwork.Bridge) -> void:
	var old: Node3D = _nodes.get(b.id)
	if old:
		old.queue_free()
		_nodes.erase(b.id)
	if b.is_open() or net == null:
		return
	var road: RoadNetwork.Road = net.world[-b.road_key - 1]
	var root := Node3D.new()
	root.name = "Closed_%s" % b.id
	add_child(root)
	_nodes[b.id] = root
	var mat := _material(b.state)
	for end in [b.first, b.last]:
		var p: Vector3 = road.points[end]
		var q: Vector3 = road.points[end + 1] if end == b.first else road.points[end - 1]
		var along := Vector3(q.x - p.x, 0.0, q.z - p.z).normalized()
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(b.width + 1.0, BAR_H, BAR_THICK)
		bar.mesh = mesh
		bar.material_override = mat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bar)
		bar.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP), Vector3(p.x, p.y + 0.2 + BAR_H * 0.5, p.z))
	var label := Label3D.new()
	label.text = "%s: %s" % [b.name, b.state_name()]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 28
	label.outline_size = 8
	label.modulate = COLORS.get(b.state, Color.RED)
	root.add_child(label)
	label.global_position = Vector3(b.center.x, b.center.y + 5.0, b.center.z)


func _material(state: int) -> StandardMaterial3D:
	if _mat_cache.has(state):
		return _mat_cache[state]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLORS.get(state, Color.RED)
	_mat_cache[state] = m
	return m
