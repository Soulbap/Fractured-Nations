## Static description of the drivable vehicle types (LOGISTICS-01): dimensions and handling
## numbers the simulation reads, plus the asset paths the visuals build from. Read only;
## the instance state lives in UnitState.veh (VehicleState).
##
## Dimensions come from the asset sidecars (assets/military/vehicles/*.json); handling is
## deliberately heavy and deliberate (military trucks, not arcade cars).
class_name VehicleDefs
extends RefCounted

const TRUCK := &"truck_6x6"
const APC := &"apc_8x8"

const GLB_DIR := "res://assets/military/vehicles/"
## LOD switch distances (m), the same for both vehicles and their wheels (asset sidecars).
const LOD_RANGES: Array[Vector2] = [Vector2(0.0, 40.0), Vector2(40.0, 160.0), Vector2(160.0, 1500.0)]


class Def:
	var id: StringName
	var display_name := ""
	var short_name := ""
	## Body glb and the wheel glb instanced at every WHEEL_* marker.
	var body_glb := ""
	var wheel_glb := ""
	## Overall footprint (width, length) in metres and the circles used for collision tests:
	## offsets along the vehicle's long axis (+ = front) and their radius.
	var width := 3.3
	var length := 8.7
	var circle_r := 1.6
	var circle_z: Array[float] = [-2.9, 0.0, 2.9]
	## Radius of the same circles while driving: a little tighter than the planning radius, so
	## a route that was planned clear never stops a vehicle at a corner it was allowed to cut.
	var collide_r := 1.2
	## Distance between the steered front axle(s) and the driven rear axle(s) (m).
	var wheelbase := 4.4
	## Axles (1-based, front first) that steer, with the share of the steering angle.
	var steer_axles := {1: 1.0}
	var max_steer := 0.55
	## Steering wheel speed (rad/s).
	var steer_rate := 0.9
	## m/s
	var max_speed := 25.0
	var max_reverse := 5.0
	var accel := 1.6
	var brake := 4.5
	## Planned cornering and comfortable braking (route speed profile).
	var lat_accel := 2.2
	var plan_decel := 2.0
	## Cross-country ceiling (m/s) and the steepest ground the vehicle drives (rise / run).
	var offroad_speed := 7.0
	var max_grade := 0.40
	var wheel_radius := 0.625
	var fuel_capacity := 200.0
	## Litres per kilometre (configurable game rate, not an engine model).
	var fuel_per_km := 1.2
	var max_health := 400.0
	## Infantry the vehicle carries, and the supply capacity (kg) of its cargo.
	var passengers := 12
	## Distance behind the vehicle's centre where infantry board and disembark (rear door / ramp).
	var door_z := 5.2
	var cargo_capacity := 10000.0
	## Road class -> speed ceiling (m/s) when the route runs on it.
	var class_speed := {&"primary": 22.0, &"secondary": 18.0, &"local": 14.0, &"street": 12.0, &"track": 8.0}


static var _cache := {}


static func get_def(id: StringName) -> Def:
	if _cache.has(id):
		return _cache[id]
	var d := Def.new()
	d.id = id
	match id:
		APC:
			d.display_name = "Wheeled APC 8x8"
			d.short_name = "APC"
			d.body_glb = GLB_DIR + "apc_8x8.glb"
			d.wheel_glb = GLB_DIR + "wheel_apc.glb"
			d.width = 3.3
			d.length = 8.0
			d.circle_r = 1.6
			d.circle_z = [-2.4, 0.0, 2.4]
			d.wheelbase = 3.65
			d.steer_axles = {1: 1.0, 2: 0.55}
			d.max_steer = 0.50
			d.max_speed = 25.0
			d.accel = 1.9
			d.brake = 5.0
			d.lat_accel = 2.6
			d.wheel_radius = 0.60
			d.fuel_capacity = 280.0
			d.fuel_per_km = 1.6
			d.max_health = 900.0
			d.passengers = 8
			d.door_z = 4.7
			d.cargo_capacity = 800.0
		_:
			d.id = TRUCK
			d.display_name = "Cargo truck 6x6"
			d.short_name = "Truck"
			d.body_glb = GLB_DIR + "truck_6x6.glb"
			d.wheel_glb = GLB_DIR + "wheel_truck.glb"
	_cache[id] = d
	return d


static func all_ids() -> Array[StringName]:
	return [TRUCK, APC]
