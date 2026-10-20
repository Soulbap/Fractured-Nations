## Physical vehicle: the near-camera presentation of a UnitState of kind VEHICLE.
##
## LOGISTICS-01: the body does not drive. VehicleSim moves the record every tick (the same
## code for a vehicle in front of the camera and one 10 km away); this node follows the
## record with a kinematic collider (soldiers path around it, shots hit it), draws the hull
## with wheels that spin and steer and a body that rides the ground, and reports what its
## physics world sees ahead (trees, soldiers) back to the record for the driving code.
## Promotion and demotion therefore change a node, never a journey.
class_name VehicleBody
extends AnimatableBody3D

## Footprint (width, length) in metres used to carve the navigation mesh around parked
## vehicles; the same for every vehicle, which lets DetailManager carve vehicles that
## currently have no body.
const FOOTPRINT := Vector2(3.3, 8.7)
const PROBE_TICKS := 3

var unit: UnitState
var sim: WorldSim
var visual: VehicleVisual
var selected := false:
	set(v):
		selected = v
		if is_node_ready() and unit:
			UnitVisuals.style_ring(ring, unit.faction, selected)

@onready var ring: MeshInstance3D = $Ring

var _probe_tick := 0


func bind(p_unit: UnitState, p_sim: WorldSim) -> void:
	unit = p_unit
	sim = p_sim
	name = "Vehicle_%d" % unit.id
	global_transform = Transform3D(Basis(Vector3.UP, unit.yaw), unit.position)
	visual = VehicleVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(unit.veh.type_id, unit.faction)
	for sh in visual.collision_shapes:
		add_child(sh)
	var def := unit.veh.def()
	var torus := (ring.mesh as TorusMesh).duplicate() as TorusMesh
	torus.inner_radius = def.length * 0.5 + 0.4
	torus.outer_radius = torus.inner_radius + 0.3
	ring.mesh = torus
	UnitVisuals.style_ring(ring, unit.faction, selected)
	sim.register_body(unit.id, self)
	visual.pose(unit, 1.0, ground_height)


func _exit_tree() -> void:
	if sim and unit and sim.bodies.get(unit.id) == self:
		sim.unregister_body(unit.id)


func _process(delta: float) -> void:
	if unit == null:
		return
	UnitVisuals.scale_ring_for_camera(ring, selected)
	visual.pose(unit, delta, ground_height)


func _physics_process(_delta: float) -> void:
	if unit == null:
		return
	global_transform = Transform3D(Basis(Vector3.UP, unit.yaw), unit.position)
	_probe_tick += 1
	if _probe_tick % PROBE_TICKS == 0:
		_probe()


func ground_height(p: Vector3) -> float:
	return sim.vehicles.ground_at(p)


## Obstacle awareness of the detailed tier: rays at bumper height along the planned route (or
## along the heading while the player drives) report the free distance to the nearest tree,
## rock or soldier. Terrain, structures (the simulation knows their footprints) and other
## vehicles (also known) are not reported here.
func _probe() -> void:
	var v := unit.veh
	var space := get_world_3d().direct_space_state
	var def := v.def()
	var look := clampf(absf(v.speed) * 1.6 + 8.0, 10.0, 34.0)
	var best := INF
	var half := def.width * 0.5 - 0.1
	var from := unit.position + Vector3.UP * 1.1
	var fwd := Vector3(-sin(unit.yaw), 0.0, -cos(unit.yaw))
	var legs: Array = []
	if unit.player_controlled or v.route.size() < 2 or unit.order != UnitState.Order.MOVE or v.speed < -0.1:
		var dir := fwd if v.speed >= -0.1 else -fwd
		legs.append([from + dir * (def.length * 0.5), dir * look, 0.0])
	else:
		# Along the route: chain of ~6 m legs from the point just ahead of the front bumper.
		var n := v.route.size()
		var s0: float = v.route_s[mini(v.route_i, n - 1)] if v.route_s.size() == n else 0.0
		var prev := unit.position + fwd * (def.length * 0.5)
		prev.y = from.y
		var k := v.route_i
		var acc := 0.0
		while k < n - 1 and acc < look:
			k += 1
			var p := v.route[k]
			if v.route_s.size() == n and v.route_s[k] - s0 < def.length * 0.5:
				continue
			var q := Vector3(p.x, from.y + (p.y - unit.position.y), p.z)
			var seg := q - prev
			if seg.length() > 4.0:
				legs.append([prev, seg, acc])
				acc += seg.length()
				prev = q
			if legs.size() >= 5:
				break
	for leg: Array in legs:
		var origin: Vector3 = leg[0]
		var dirv: Vector3 = leg[1]
		var dn := Vector3(dirv.x, 0.0, dirv.z).normalized()
		var side := Vector3(dn.z, 0.0, -dn.x)
		for off in [-half, 0.0, half]:
			var o: Vector3 = origin + side * off
			var q := PhysicsRayQueryParameters3D.create(o, o + dirv)
			q.collide_with_areas = false
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var col: Object = hit.collider
			var blocking := false
			if col is SoldierBody:
				blocking = true
			elif col is Node and (col as Node).name == &"InstanceColliders":
				blocking = true
			if blocking:
				best = minf(best, float(leg[2]) + (hit.position - o).length())
	v.probe_ahead = best


## Obstacle description for AreaNavigation.
func nav_obstacle() -> Dictionary:
	return {"position": global_position, "yaw": rotation.y, "size": FOOTPRINT}
