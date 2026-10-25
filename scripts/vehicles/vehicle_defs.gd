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
## ASSET-INTEGRATION-01: the VEHICLE-ASSETS-01 pack (assets/military/vehicles/<id>/<id>.glb + sidecar). Registered for the
## development armoury and the systems below; the New Game economy (BaseSim.VEHICLES) does not build them.
const LMV := &"iveco_lmv"
const PATRIA := &"patria_6x6"
const CV90 := &"cv9030n"
const SCANIA := &"scania_military"
const LEOPARD := &"leopard_2a8_nor"
const NH90 := &"nh90_tth"

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
	## Route planning: how many metres of road one metre of cross-country driving costs. Trucks prefer roads (3), an APC copes with
	## terrain far better (1.7), a tracked vehicle would use about 1.2: the planner takes the straight way across country whenever
	## that is cheaper for *this* vehicle, it is never road-only.
	var offroad_factor := 3.0
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
	## ASSET-INTEGRATION-01: the body GLB carries its own running gear and moving parts (wheel / road-wheel / turret / door
	## / rotor pivots, VEHICLE-ASSETS-01) - VehicleVisual poses them instead of instancing wheel_glb; wheel_glb is "".
	var articulated := false
	## Tracks instead of wheels: road wheels, sprockets, idlers and rollers spin, nothing steers (VehicleSim's steering is a
	## turning circle either way).
	var tracked := false
	## False: the vehicle has no movement model in VehicleSim (the NH90 - no flight model yet): it never drives.
	var drivable := true
	## Short role text for the development armoury and inspectors (what the type is for, what of it works).
	var role_note := ""


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
			d.offroad_factor = 1.7
			d.offroad_speed = 9.0
			d.max_grade = 0.55
			d.passengers = 8
			d.door_z = 4.7
			d.cargo_capacity = 800.0
		LMV:
			d.display_name = "Iveco LMV"
			d.short_name = "LMV"
			d.role_note = "light multirole vehicle, RWS, 4 seats"
			_pack(d, "iveco_lmv")
			d.width = 2.10
			d.length = 4.90
			d.circle_r = 1.15
			d.circle_z = [-1.35, 0.0, 1.35]
			d.collide_r = 0.95
			d.wheelbase = 3.20
			d.max_steer = 0.60
			d.steer_rate = 1.2
			d.max_speed = 30.0
			d.accel = 2.6
			d.brake = 6.0
			d.lat_accel = 3.2
			d.offroad_factor = 1.8
			d.offroad_speed = 11.0
			d.max_grade = 0.60
			d.wheel_radius = 0.52
			d.fuel_capacity = 180.0
			d.fuel_per_km = 0.6
			d.max_health = 500.0
			d.passengers = 4
			d.door_z = 3.1
			d.cargo_capacity = 300.0
		PATRIA:
			d.display_name = "Patria 6x6"
			d.short_name = "Patria"
			d.role_note = "wheeled APC, RWS, 10 troop seats"
			_pack(d, "patria_6x6")
			d.width = 2.84
			d.length = 7.50
			d.circle_r = 1.45
			d.circle_z = [-2.3, 0.0, 2.3]
			d.collide_r = 1.15
			d.wheelbase = 3.10
			d.steer_axles = {1: 1.0, 2: 0.5}
			d.max_steer = 0.50
			d.max_speed = 27.0
			d.accel = 1.9
			d.brake = 5.0
			d.lat_accel = 2.6
			d.offroad_factor = 1.7
			d.offroad_speed = 9.5
			d.max_grade = 0.55
			d.wheel_radius = 0.62
			d.fuel_capacity = 280.0
			d.fuel_per_km = 1.4
			d.max_health = 900.0
			d.passengers = 10
			d.door_z = 4.6
			d.cargo_capacity = 800.0
		CV90:
			d.display_name = "CV9030N"
			d.short_name = "CV90"
			d.role_note = "tracked IFV, 30 mm turret (visual), 8 troop seats"
			_pack(d, "cv9030n")
			d.tracked = true
			d.width = 3.24
			d.length = 6.55
			d.circle_r = 1.62
			d.circle_z = [-1.7, 0.0, 1.7]
			d.collide_r = 1.3
			d.wheelbase = 3.0
			d.steer_axles = {}
			d.max_steer = 0.62
			d.steer_rate = 1.1
			d.max_speed = 19.0
			d.max_reverse = 5.0
			d.accel = 1.6
			d.brake = 5.5
			d.lat_accel = 2.4
			d.offroad_factor = 1.2
			d.offroad_speed = 12.0
			d.max_grade = 0.60
			d.wheel_radius = 0.31
			d.fuel_capacity = 525.0
			d.fuel_per_km = 2.5
			d.max_health = 1400.0
			d.passengers = 8
			d.door_z = 4.25
			d.cargo_capacity = 400.0
		SCANIA:
			d.display_name = "Scania XT 6x6"
			d.short_name = "Scania"
			d.role_note = "cargo truck, troops on the bed"
			_pack(d, "scania_military")
			d.width = 2.55
			d.length = 8.90
			d.circle_r = 1.35
			d.circle_z = [-3.0, -1.0, 1.0, 3.0]
			d.collide_r = 1.05
			d.wheelbase = 4.50
			d.max_steer = 0.55
			d.max_speed = 25.0
			d.wheel_radius = 0.60
			d.fuel_capacity = 400.0
			d.fuel_per_km = 1.2
			d.max_health = 400.0
			d.passengers = 12
			d.door_z = 5.4
			d.cargo_capacity = 10000.0
		LEOPARD:
			d.display_name = "Leopard 2A8 NOR"
			d.short_name = "Leopard"
			d.role_note = "main battle tank, 120 mm turret (visual), crew only"
			_pack(d, "leopard_2a8_nor")
			d.tracked = true
			d.width = 3.80
			d.length = 8.05
			d.circle_r = 1.9
			d.circle_z = [-2.1, 0.0, 2.1]
			d.collide_r = 1.55
			d.wheelbase = 3.4
			d.steer_axles = {}
			d.max_steer = 0.60
			d.steer_rate = 0.9
			d.max_speed = 18.5
			d.max_reverse = 8.0
			d.accel = 1.3
			d.brake = 5.0
			d.lat_accel = 2.2
			d.offroad_factor = 1.2
			d.offroad_speed = 11.0
			d.max_grade = 0.60
			d.wheel_radius = 0.35
			d.fuel_capacity = 1160.0
			d.fuel_per_km = 4.0
			d.max_health = 2500.0
			d.passengers = 0
			d.door_z = 4.0
			d.cargo_capacity = 0.0
		NH90:
			d.display_name = "NH90 TTH"
			d.short_name = "NH90"
			d.role_note = "transport helicopter - landed only (no flight model), 10 troop seats"
			_pack(d, "nh90_tth")
			d.drivable = false
			d.width = 3.6
			d.length = 16.1
			d.circle_r = 1.8
			d.circle_z = [-6.0, -3.0, 0.0, 3.0, 6.0]
			d.collide_r = 1.6
			d.max_speed = 0.0
			d.max_reverse = 0.0
			d.offroad_speed = 0.0
			d.fuel_capacity = 2000.0
			d.max_health = 600.0
			d.passengers = 10
			d.door_z = 3.4
			d.cargo_capacity = 2000.0
		_:
			d.id = TRUCK
			d.display_name = "Cargo truck 6x6"
			d.short_name = "Truck"
			d.body_glb = GLB_DIR + "truck_6x6.glb"
			d.wheel_glb = GLB_DIR + "wheel_truck.glb"
	_cache[id] = d
	return d


## ASSET-INTEGRATION-01: a VEHICLE-ASSETS-01 type: its GLB in its own folder, articulated, LOD ranges from the sidecar.
static func _pack(d: Def, folder: String) -> void:
	d.body_glb = GLB_DIR + "%s/%s.glb" % [folder, folder]
	d.wheel_glb = ""
	d.articulated = true


## The LOGISTICS-01 types every system and the New Game economy use.
static func all_ids() -> Array[StringName]:
	return [TRUCK, APC]


## ASSET-INTEGRATION-01: the VEHICLE-ASSETS-01 types (development armoury; not built by the economy).
static func pack_ids() -> Array[StringName]:
	return [LMV, PATRIA, CV90, SCANIA, LEOPARD, NH90]
