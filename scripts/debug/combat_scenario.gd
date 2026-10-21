## A controlled infantry encounter inside the persistent sandbox world (AI-SQUAD-01).
##
## Not a separate battle map: it finds a real site on the 20 km terrain, spawns real squads
## (WarSim.spawn_squad - the same soldiers, weapons and ammunition as in play), may build a
## small defended position with the normal construction records (ConstructionState.add_line,
## the same path the player and the earlier tests use), and tears everything down again so
## the next run starts from the same state. The automated checks (AISquadSelfTest) and the
## visual demo (`--squad-demo`) both use it, so what the tests assert is what can be watched.
##
## Geometry of a site (all flat ground vectors, `dir` points from the attackers to the
## defenders, `side` is 90 degrees to the right of it):
##   att      attacker start (an approach `approach_m` short of the defence)
##   def      the defended position
##   left / right  two flank staging points (offset sideways, roughly level with the defence)
## The site is found by measuring the terrain (dry, moderate slope, open sight line between
## att and def, some natural cover, a way round on both sides) - deterministic for a given
## terrain, so every run uses the same ground.
class_name CombatScenario
extends RefCounted

var demo: CoreDemo
var seed_value := 4242
var approach_m := 170.0
var site := {}
## Units / structures created by the scenario (removed by reset()).
var unit_ids: Array[int] = []
var structure_ids: Array[int] = []
var _avoid: Array[Vector3] = []
var _stations := {}


func _init(p_demo: CoreDemo) -> void:
	demo = p_demo
	for u in demo.sim.state.soldiers():
		_avoid.append(u.position)
	for sq: SquadState in demo.sim.state.all_squads():
		_stations[sq.id] = sq.station_objective


# --- Site -------------------------------------------------------------------------------

## Searches rings around the objectives for a site. Result is cached in `site`
## ({} when none was found).
func find_site() -> Dictionary:
	if not site.is_empty():
		return site
	var war := demo.sim.state.war
	var centers: Array[Vector3] = []
	for o: ObjectiveState in war.objectives.values():
		centers.append(o.position)
	centers.append(Vector3.ZERO)
	var line := demo.sim.combat.line
	for center in centers:
		for r: float in [500.0, 900.0, 1400.0, 2000.0, 2800.0, 3600.0]:
			var n := clampi(int(r / 60.0), 8, 40)
			for k in n:
				var a := k * TAU / n + 0.37
				var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
				if absf(p.x) > 9000.0 or absf(p.z) > 9000.0 or not _far(p, 700.0):
					continue
				var s := _try_site(p, line)
				if not s.is_empty():
					site = s
					return site
	return {}


func _far(p: Vector3, r: float) -> bool:
	for q in _avoid:
		if Vector2(q.x - p.x, q.z - p.z).length() < r:
			return false
	return true


## p is the defended position. Tries 12 approach directions.
func _try_site(p: Vector3, line: LineOfFire) -> Dictionary:
	if not _dry(p, 90.0) or _slope(p, 10.0) > 9.0 or _slope(p, 30.0) > 9.0:
		return {}
	for j in 12:
		var dir := Vector3(cos(j * TAU / 12.0 + 0.2), 0.0, sin(j * TAU / 12.0 + 0.2))
		var side := Vector3(-dir.z, 0.0, dir.x)
		var att := demo.on_ground(p.x - dir.x * approach_m, p.z - dir.z * approach_m, 0.0)
		if not _dry(att, 40.0) or _slope(att, 10.0) > 10.0:
			continue
		# An open sight line between the two starts (a firefight, not a game of hide and seek).
		var vis := 0
		for off: float in [-10.0, 0.0, 10.0]:
			var e1 := demo.on_ground(att.x + side.x * off, att.z + side.z * off, 1.6)
			var e2 := demo.on_ground(p.x + side.x * off, p.z + side.z * off, 1.6)
			if line.sight(e1, e2).visible:
				vis += 1
		if vis < 3:
			continue
		var left := _flank_point(p, dir, -side)
		var right := _flank_point(p, dir, side)
		if not left.is_finite() or not right.is_finite():
			continue
		return {"def": p, "att": att, "dir": dir, "side": side, "left": left, "right": right, "dist": approach_m}
	return {}


## A staging point 85 m to the side of the defence and 60 m short of it, on dry, walkable
## ground (null/INF when the side is wet, a cliff, or off the route grid).
func _flank_point(p: Vector3, dir: Vector3, side: Vector3) -> Vector3:
	var q := demo.on_ground(p.x + side.x * 85.0 - dir.x * 60.0, p.z + side.z * 85.0 - dir.z * 60.0, 0.0)
	var routes := demo.sim.war.routes
	if not _dry(q, 20.0) or _slope(q, 8.0) > 12.0:
		return Vector3.INF
	if routes != null and routes.ready and not routes.passable(q):
		return Vector3.INF
	return q


# --- Spawning -----------------------------------------------------------------------------

func spawn(faction: int, at: Vector3, facing: Vector3, n := 8, tag := "") -> SquadState:
	var ws := demo.sim.war
	var sq := ws.spawn_squad(demo.sim.state.war.faction(faction), demo.on_ground(at.x, at.z, 0.0), n)
	if tag != "":
		sq.squad_name = tag
	var yaw := atan2(-facing.x, -facing.z)
	sq.order_yaw = yaw
	for id in sq.members:
		unit_ids.append(id)
		var u := demo.sim.state.get_unit(id)
		u.yaw = yaw
		u.anchor_pos = u.position
	return sq


## The defended position and its surroundings, built from the normal construction set: a short
## horseshoe of HESCO baskets with a sandbag fighting position on each wing, concrete barriers in
## front (AI-SQUAD-01 first set), and natural / improvised cover on the approach - a boulder group
## on one side, a log barricade on the other, an earth berm across the middle - so the ground
## offers a covered way round either flank and something to bound between in the centre.
func build_defence() -> void:
	if site.is_empty():
		return
	var cs := demo.sim.state.construction
	var d: Vector3 = site.def
	var dir: Vector3 = site.dir
	var side: Vector3 = site.side
	var pts := PackedVector3Array([
		demo.on_ground(d.x - dir.x * 4.0 - side.x * 13.0, d.z - dir.z * 4.0 - side.z * 13.0, 0.0),
		demo.on_ground(d.x + dir.x * 5.0 - side.x * 10.0, d.z + dir.z * 5.0 - side.z * 10.0, 0.0),
		demo.on_ground(d.x + dir.x * 7.0, d.z + dir.z * 7.0, 0.0),
		demo.on_ground(d.x + dir.x * 5.0 + side.x * 10.0, d.z + dir.z * 5.0 + side.z * 10.0, 0.0),
		demo.on_ground(d.x - dir.x * 4.0 + side.x * 13.0, d.z - dir.z * 4.0 + side.z * 13.0, 0.0)])
	_track(cs.add_line(&"hesco", pts))
	for off: float in [-22.0, 22.0]:
		var a := demo.on_ground(d.x + dir.x * 14.0 + side.x * off, d.z + dir.z * 14.0 + side.z * off, 0.0)
		var b := demo.on_ground(a.x + side.x * 5.0, a.z + side.z * 5.0, 0.0)
		_track(cs.add_line(&"concrete_barrier", PackedVector3Array([a, b])))
	# The wings: a sandbag fighting position each, looking at the attackers.
	var yaw_def := atan2(dir.x, dir.z)
	for off: float in [-19.0, 19.0]:
		var p := demo.on_ground(d.x + side.x * off + dir.x * 2.0, d.z + side.z * off + dir.z * 2.0, 0.0)
		_track(cs.add_building(&"sandbag_fighting_position", p, yaw_def, 1))
	# The approach (attackers come from -dir): cover for the bounding elements.
	var att: Vector3 = site.att
	var yaw_att := atan2(-dir.x, -dir.z)
	var q1 := att.lerp(d, 0.62) - side * 30.0
	_track(cs.add_building(&"boulder_cluster", demo.on_ground(q1.x, q1.z, 0.0), 0.6, 0))
	var q2 := att.lerp(d, 0.50) + side * 34.0
	_track(cs.add_building(&"log_barricade", demo.on_ground(q2.x, q2.z, 0.0), yaw_att + 0.25, 0))
	var q3 := att.lerp(d, 0.34)
	_track(cs.add_line(&"earth_berm", PackedVector3Array([demo.on_ground(q3.x - side.x * 4.0, q3.z - side.z * 4.0, 0.0), demo.on_ground(q3.x + side.x * 4.0, q3.z + side.z * 4.0, 0.0)])))
	var q4 := att.lerp(d, 0.78) + side * 14.0
	_track(cs.add_building(&"boulder_cluster", demo.on_ground(q4.x, q4.z, 0.0), 2.4, 0))


func _track(s: StructureState) -> void:
	if s:
		structure_ids.append(s.id)


## Back to the starting state: scenario units and structures gone, no contacts or
## operations, AI decisions paused, the war's garrisons as they were.
func reset() -> void:
	var state := demo.sim.state
	var cs := state.construction
	for id in unit_ids:
		state.remove_unit(id)
	unit_ids.clear()
	for id in structure_ids:
		cs.remove(id)
	structure_ids.clear()
	var war := state.war
	for op: OperationState in war.active_operations():
		demo.sim.war.cancel(op.id, "scenario reset")
	for sq: SquadState in state.all_squads():
		if _stations.has(sq.id):
			sq.station_objective = _stations[sq.id]
	war.contacts.clear()
	war.intel_pending.clear()
	demo.sim.war.intel.rebuild()
	demo.sim.war.threatened.clear()
	for f: FactionState in war.factions.values():
		f.decisions.clear()
		if not f.player:
			f.next_decision_at = INF
	state.world_seed = seed_value
	TimeCompression.reset()


# --- Terrain measurements -------------------------------------------------------------------

func _slope(p: Vector3, half: float) -> float:
	var gx := (demo.ground_height(p + Vector3(half, 0, 0)) - demo.ground_height(p - Vector3(half, 0, 0))) / (2.0 * half)
	var gz := (demo.ground_height(p + Vector3(0, 0, half)) - demo.ground_height(p - Vector3(0, 0, half))) / (2.0 * half)
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


func _dry(p: Vector3, half: float) -> bool:
	var sm := demo.structures
	for ix in range(-2, 3):
		for iz in range(-2, 3):
			var q := p + Vector3(ix * half / 2.0, 0, iz * half / 2.0)
			if sm._wet(q.x, q.z, demo.ground_height(q)):
				return false
	return true
