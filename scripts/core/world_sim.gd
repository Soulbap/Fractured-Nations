## Advances the WorldState in time and connects it to physical bodies.
##
## Two tiers share one record per unit:
##   - detailed: a body (SoldierBody / VehicleBody) is registered for the unit; Godot
##     physics and navigation move it and the body writes position, heading, velocity and
##     move state back into the UnitState every physics tick;
##   - abstract: no body; the unit's order is executed here as straight-line travel at
##     its speed with the height read from the terrain. This is the tier distant units
##     will use later; today it exists so that the state provably does not depend on
##     scene nodes (the self-test exercises it).
## Possession is not a tier change: a possessed soldier keeps its body and its record.
## WORLD-CORE-02: DetailManager decides per unit which tier applies (distance to the
## active camera) and swaps bodies for lightweight proxies; this class only keeps the
## registries and runs the abstract step for every unit without a body.
class_name WorldSim
extends Node

## Emitted when a body or proxy starts representing a unit (selection state, HUD).
signal view_added(id: int, view: Node3D)

@export var terrain: Terrain3D
## Distance at which an abstract unit counts as arrived.
@export var abstract_arrive_m := 1.0
## AI-WAR-LOGISTICS-01 (near/far parity): bodies lose a few percent of their walking speed to turning, crowd avoidance
## and navmesh detours that the straight-line abstract step does not have. Measured on the same routes (open ground,
## dense woods, slopes, a three-squad column march) the bodies take 4-8 % longer; the abstract step takes that
## friction into account so the same march takes about the same time in both tiers. Not a terrain effect: the terrain
## itself affects both tiers through the same route and the same ground (no tier is faster over woods or slopes).
@export var abstract_friction := 0.93

var state := WorldState.new()
## UNIT-01A: turns squad orders (state.squads) into per-unit move orders.
var squads := SquadControl.new(self)
## AI-SQUAD-01: fire teams and squad tactics (defend, suppress, assault, flank, bound, withdraw).
var tactics := SquadTactics.new(self)
## LOGISTICS-01: driving of every vehicle record (both tiers), routes and the player's wheel.
var vehicles := VehicleSim.new(self)
## LOGISTICS-01: depots, vehicle jobs, resupply, automation.
var logistics := LogisticsSim.new(self, vehicles)
## COMBAT-01a: firing, reloading, damage and death (the one combat authority).
var combat := CombatSim.new(self)
## COMBAT-01b: soldiers' own perception, target choice and firing (through `combat`).
var brain := CombatBrain.new(self)
## WORLD-SANDBOX-01: the strategic simulation (capture, operations, faction AI, reserves,
## intelligence); idle unless the world has an active war (state.war.active).
var war := WarSim.new(self)
## Parent of bodies and proxies (corpse markers are created here).
var units_root: Node3D
## id -> Node3D body (detailed tier)
var bodies := {}
## id -> UnitProxy (abstract tier visual; a unit has a body or a proxy, never both)
var proxies := {}
## Set in the large world: tells bodies whether a point is covered by the navmesh.
var detail: DetailManager
## Set when construction exists: abstract units do not pass through structures.
var structures: StructureManager
## NAVIGATION N1-A: short obstacle refinements for abstract infantry. Routes are
## transient; the authoritative order target remains on UnitState and a route is
## recomputed after load or a tier transition if it is still needed.
const INFANTRY_LOCAL_CELL := 5.0
const INFANTRY_LOCAL_MAX_CELLS := 60000
const INFANTRY_LOCAL_MAX_M := 500.0
const INFANTRY_CLEARANCE_M := 0.5
## NAV-INF-01: the steepest ground infantry is sent over, in both tiers: tan(38 deg). The near tier's navmesh (AreaNavigation) takes
## its slope limit from this value. Before, the navmesh and the abstract tier allowed 45 degrees while a SoldierBody (capsule, no
## foothold) stood still on 40+ degree faces, so near soldiers were routed up banks they could not climb.
const INFANTRY_MAX_GRADE := 0.78
const INFANTRY_RETRY_BUDGET := 3
const INFANTRY_RETRY_RENEW_M := 10.0
const INFANTRY_FAIL_MEMORY_S := 20.0
var _local_routes := {}
var _local_pending := {}
var _local_attempts := {}
## NAV-INF-01: where the current run of attempts began. The retry budget is for one blockage: a walker that has covered
## INFANTRY_RETRY_RENEW_M since then has made progress, and its next obstacle starts a new run.
var _local_anchor := {}
var _local_route_cache := {}
## NAV-INF-01: plans that found no passage, by squad route and 50 m start cell -> time. Members of a squad that stand together do
## not each repeat a search that cannot succeed (a full-grid failure is the most expensive search there is).
var _local_fail := {}
var local_nav_stats := {"searches": 0, "successes": 0, "failures": 0, "cache_hits": 0,
	"recoveries": 0, "plan_ms_total": 0.0, "plan_ms_max": 0.0, "repairs": 0}
## NAV-INF-01: the last local-move blocks (time, unit, place, reason); the answer to "why did it stop" when no one was watching.
var local_block_log: Array[Dictionary] = []
## Length of the last simulation step (s).
var last_delta := 0.0
## Accumulated cost of the simulation parts (microseconds) and ticks counted.
var tick_usec := {"abstract": 0, "squads": 0, "tactics": 0, "war": 0, "brain": 0, "combat": 0, "vehicles": 0, "ticks": 0}


func register_body(id: int, body: Node3D) -> void:
	_clear_local_route(id)
	bodies[id] = body
	var u := state.get_unit(id)
	if u:
		u.has_body = true
	view_added.emit(id, body)


func register_proxy(id: int, proxy: Node3D) -> void:
	proxies[id] = proxy
	view_added.emit(id, proxy)


func unregister_proxy(id: int) -> void:
	proxies.erase(id)


func unregister_body(id: int) -> void:
	bodies.erase(id)
	var u := state.get_unit(id)
	if u:
		u.has_body = false


## A soldier boarded a vehicle: its body and proxy go (the record stays, DetailManager gives
## it neither while it is aboard).
func hide_view(id: int) -> void:
	var b: Node3D = bodies.get(id)
	if b:
		unregister_body(id)
		b.get_parent().remove_child(b)
		b.queue_free()
	var p: Node3D = proxies.get(id)
	if p:
		unregister_proxy(id)
		p.get_parent().remove_child(p)
		p.queue_free()


func body_of(id: int) -> Node3D:
	return bodies.get(id)


## The node currently showing a unit: its body in the detailed tier, else its proxy.
func view_of(id: int) -> Node3D:
	return bodies.get(id) if bodies.has(id) else proxies.get(id)


func _ready() -> void:
	logistics.bind()
	state.restored.connect(_on_restored)
	state.unit_removed.connect(_on_unit_removed)
	state.unit_died.connect(_on_unit_died)
	state.order_changed.connect(_on_order_changed)
	state.roads.bridge_changed.connect(_on_bridge_changed)
	brain.connect_signals()
	tactics.connect_signals()
	# COMBAT-02: shots find nearby soldiers through the brain's grid.
	combat.line.unit_index = brain


## A soldier died: its body (if any) goes, a corpse marker (UnitProxy) stays in the world.
func _on_unit_died(u: UnitState) -> void:
	var b: Node3D = bodies.get(u.id)
	var parent: Node = units_root
	if b:
		parent = b.get_parent()
		unregister_body(u.id)
		b.get_parent().remove_child(b)
		b.queue_free()
	var old: Node3D = proxies.get(u.id)
	if old:
		unregister_proxy(u.id)
		old.queue_free()
	if parent:
		var corpse := UnitProxy.new()
		parent.add_child(corpse)
		corpse.bind(u, self)


## A record went away (load without that unit): its body or proxy goes too.
func _on_unit_removed(id: int) -> void:
	_clear_local_route(id)
	for reg: Dictionary in [bodies, proxies]:
		var n: Node3D = reg.get(id)
		if n:
			reg.erase(id)
			n.queue_free()


func _physics_process(delta: float) -> void:
	last_delta = delta
	state.time += delta
	var t0 := Time.get_ticks_usec()
	# One bounded search per physics tick prevents a squad reaching a wall from causing
	# eight A* spikes in the same frame. Waiting members keep their order and position.
	_process_local_plan_budget()
	for u in state.units.values():
		if not u.has_body and u.alive and u.kind == UnitState.Kind.SOLDIER and u.vehicle_id < 0:
			_abstract_step(u, delta)
	var t1 := Time.get_ticks_usec()
	squads.update(delta)
	var t1t := Time.get_ticks_usec()
	tactics.update(delta)
	var t2 := Time.get_ticks_usec()
	vehicles.update(delta)
	logistics.update(delta)
	var t2v := Time.get_ticks_usec()
	war.update(delta)
	var t3 := Time.get_ticks_usec()
	brain.update(delta)
	var t4 := Time.get_ticks_usec()
	combat.update(delta)
	var t5 := Time.get_ticks_usec()
	# WORLD-PLAYTEST-01: where a simulation tick goes (time compression measurements).
	tick_usec.abstract += t1 - t0
	tick_usec.squads += t1t - t1
	tick_usec.tactics += t2 - t1t
	tick_usec.vehicles += t2v - t2
	tick_usec.war += t3 - t2v
	tick_usec.brain += t4 - t3
	tick_usec.combat += t5 - t4
	tick_usec.ticks += 1


## A save was loaded into the existing records: bodies would write their old position
## back on the next tick, so they jump to the loaded one first.
func _on_restored() -> void:
	_local_routes.clear()
	_local_pending.clear()
	_local_attempts.clear()
	_local_anchor.clear()
	_local_route_cache.clear()
	_local_fail.clear()
	# LOGISTICS-01: soldiers aboard a vehicle show nothing; the others show something again.
	for u: UnitState in state.units.values():
		if u.vehicle_id >= 0:
			hide_view(u.id)
	if detail:
		detail.create_missing_proxies()
	for id in bodies:
		var b: Node3D = bodies[id]
		var u := state.get_unit(id)
		if u == null:
			continue
		if b is SoldierBody:
			(b as SoldierBody).teleport(u.position, u.yaw)
			(b as SoldierBody).reset_order_tracking()
		else:
			b.global_position = u.position
			b.rotation.y = u.yaw


func _abstract_step(u: UnitState, delta: float) -> void:
	# COMBAT-02: a tactical reaction pauses the order (see SoldierBody._ai_step).
	var reacting := u.is_reacting()
	if (reacting and u.react_state != UnitState.ReactState.MOVING) or (not reacting and u.order != UnitState.Order.MOVE):
		u.velocity = Vector3.ZERO
		# COMBAT-01b: a standing soldier turns to what it watches (its target).
		if not is_nan(u.watch_yaw) and not u.player_controlled:
			u.yaw = lerp_angle(u.yaw, u.watch_yaw, clampf(8.0 * delta, 0.0, 1.0))
		return
	var goal := u.react_target if reacting else u.order_target
	var move_goal := _local_waypoint(u, goal, reacting)
	var to := move_goal - u.position
	to.y = 0.0
	var dist := to.length()
	if dist <= 1.0 and move_goal != goal:
		_advance_local_route(u.id)
		return
	if dist <= (0.5 if reacting else abstract_arrive_m) and move_goal == goal:
		u.position.x = goal.x
		u.position.z = goal.z
		_settle_height(u)
		u.velocity = Vector3.ZERO
		if reacting:
			u.react_state = UnitState.ReactState.ARRIVED
		else:
			u.order = UnitState.Order.NONE
			u.move_state = UnitState.MoveState.ARRIVED
			u.nav_reason = ""
			u.anchor_pos = u.position
		_clear_local_route(u.id)
		return
	var step := minf(u.speed * abstract_friction * delta, dist)
	var dir := to / dist
	if structures and _step_blocked(u.position, dir, step):
		var invalid: Dictionary = _local_routes.get(u.id, {})
		if bool(invalid.get("cached", false)):
			_local_route_cache.erase(String(invalid.get("cache_key", "")))
		_local_routes.erase(u.id)
		_request_local_route(u, goal, reacting)
		u.velocity = Vector3.ZERO
		if not reacting:
			u.move_state = UnitState.MoveState.MOVING
		return
	u.position += dir * step
	u.velocity = dir * u.speed * abstract_friction
	u.yaw = atan2(-dir.x, -dir.z)
	u.move_state = UnitState.MoveState.MOVING
	_settle_height(u)


## NAVIGATION N1-C1: a bridge changed state. Local refinements of abstract infantry were planned with the old deck rule: they are
## dropped (and the retry budgets renewed); every walker re-checks the deck at its next step, and squads re-plan their routes.
func _on_bridge_changed(_b: RoadNetwork.Bridge) -> void:
	_local_routes.clear()
	_local_pending.clear()
	_local_attempts.clear()
	_local_anchor.clear()
	_local_route_cache.clear()
	_local_fail.clear()


func _on_order_changed(u: UnitState) -> void:
	_clear_local_route(u.id)
	if u.order == UnitState.Order.MOVE:
		u.nav_reason = ""


func _clear_local_route(id: int) -> void:
	_local_routes.erase(id)
	_local_pending.erase(id)
	_local_attempts.erase(id)
	_local_anchor.erase(id)


func invalidate_local_route(id: int) -> void:
	_clear_local_route(id)


func _local_waypoint(u: UnitState, goal: Vector3, reacting: bool) -> Vector3:
	var route: Dictionary = _local_routes.get(u.id, {})
	if route.is_empty() or bool(route.get("reacting", false)) != reacting \
			or _flat(route.get("goal", Vector3.INF), goal) > 0.5:
		if not route.is_empty():
			_local_routes.erase(u.id)
		return goal
	var pts: PackedVector3Array = route.pts
	var i: int = route.i
	while i < pts.size() - 1 and _flat(u.position, pts[i]) <= 1.0:
		i += 1
	route.i = i
	_local_routes[u.id] = route
	return pts[i] if i < pts.size() else goal


func _advance_local_route(id: int) -> void:
	var route: Dictionary = _local_routes.get(id, {})
	if route.is_empty():
		return
	route.i = int(route.i) + 1
	if int(route.i) >= (route.pts as PackedVector3Array).size():
		_local_routes.erase(id)
	else:
		_local_routes[id] = route


func _request_local_route(u: UnitState, goal: Vector3, reacting: bool) -> void:
	if _local_pending.has(u.id):
		return
	var attempts: int = _local_attempts.get(u.id, 0)
	var anchor: Vector3 = _local_anchor.get(u.id, Vector3.INF)
	if attempts > 0 and anchor.is_finite() and _flat(u.position, anchor) >= INFANTRY_RETRY_RENEW_M:
		attempts = 0
	if attempts == 0:
		_local_anchor[u.id] = u.position
	if attempts >= INFANTRY_RETRY_BUDGET:
		_block_local_move(u, reacting, "no progress: %d local routes in a row failed within %.0f m (ground or an obstacle the plan does not know)" % [attempts, INFANTRY_RETRY_RENEW_M])
		return
	if _flat(u.position, goal) > INFANTRY_LOCAL_MAX_M:
		_block_local_move(u, reacting, "local obstacle beyond refinement range")
		return
	_local_pending[u.id] = {"goal": goal, "reacting": reacting}
	_local_attempts[u.id] = attempts + 1
	u.nav_reason = "local route queued"


func _process_local_plan_budget() -> void:
	if _local_pending.is_empty() or structures == null:
		return
	var id: int = _local_pending.keys()[0]
	var req: Dictionary = _local_pending[id]
	_local_pending.erase(id)
	var u := state.get_unit(id)
	if u == null or u.has_body or not u.alive or u.vehicle_id >= 0:
		return
	var reacting: bool = req.reacting
	var goal: Vector3 = req.goal
	if (reacting and (not u.is_reacting() or _flat(u.react_target, goal) > 0.5)) \
			or (not reacting and (u.order != UnitState.Order.MOVE or _flat(u.order_target, goal) > 0.5)):
		return
	if not reacting:
		var adapted := _shared_route(u, goal)
		if not adapted.is_empty():
			_local_routes[id] = {"goal": goal, "reacting": false, "pts": adapted, "i": 1,
				"cached": true, "cache_key": _squad_route_key(id)}
			local_nav_stats.cache_hits += 1
			local_nav_stats.recoveries += 1
			u.nav_reason = "shared squad local route active"
			return
	var fail_key := ""
	if not reacting and _squad_route_key(id) != "":
		fail_key = "%s@%d,%d" % [_squad_route_key(id), floori(u.position.x / 50.0), floori(u.position.z / 50.0)]
		if state.time - float(_local_fail.get(fail_key, -1.0e9)) < INFANTRY_FAIL_MEMORY_S:
			_block_local_move(u, reacting, "no local passage (a squad mate's search from here failed %.0f s ago)" % (state.time - float(_local_fail[fail_key])))
			return
	var result := LocalRoutePlanner.plan(u.position, goal, INFANTRY_LOCAL_CELL,
		INFANTRY_LOCAL_MAX_CELLS, INFANTRY_MAX_GRADE,
		func(x: float, z: float) -> float: return _infantry_height(x, z),
		func(x: float, z: float) -> bool: return _infantry_blocked(x, z), 75.0, 0.55, true, false,
		Callable(self, "_step_blocked"), 1.0)
	local_nav_stats.searches += 1
	local_nav_stats.repairs += int(result.get("repairs", 0))
	local_nav_stats.plan_ms_total += float(result.ms)
	local_nav_stats.plan_ms_max = maxf(float(local_nav_stats.plan_ms_max), float(result.ms))
	if result.ok:
		local_nav_stats.successes += 1
		local_nav_stats.recoveries += 1
		_local_routes[id] = {"goal": goal, "reacting": reacting, "pts": result.pts, "i": 1,
			"cached": false}
		if not reacting:
			var cache_key := _squad_route_key(id)
			if cache_key != "":
				_local_route_cache[cache_key] = result.pts
		u.nav_reason = "local route active"
	else:
		var adapted := PackedVector3Array() if reacting else _shared_route(u, goal)
		if not adapted.is_empty():
			_local_routes[id] = {"goal": goal, "reacting": false, "pts": adapted, "i": 1,
				"cached": true, "cache_key": _squad_route_key(id)}
			local_nav_stats.cache_hits += 1
			local_nav_stats.recoveries += 1
			u.nav_reason = "shared squad local route active"
		else:
			local_nav_stats.failures += 1
			if fail_key != "":
				_local_fail[fail_key] = state.time
			_block_local_move(u, reacting, String(result.reason))


## The squad's shared local route, adapted to this walker, or empty. NAV-INF-01: the route was planned from another member's
## position; it is only used when this walker can walk it from where it stands (the same test the plan was verified with),
## otherwise it is dropped from the cache and the walker plans its own.
func _shared_route(u: UnitState, goal: Vector3) -> PackedVector3Array:
	var key := _squad_route_key(u.id)
	var cached: PackedVector3Array = _local_route_cache.get(key, PackedVector3Array())
	if cached.size() < 2:
		return PackedVector3Array()
	var adapted := cached.duplicate()
	adapted.append(goal)
	var walk := PackedVector3Array([u.position])
	walk.append_array(adapted.slice(1))
	if LocalRoutePlanner.first_unwalkable(walk, Callable(self, "_step_blocked"), 1.0).is_finite():
		_local_route_cache.erase(key)
		return PackedVector3Array()
	return adapted


func _squad_route_key(unit_id: int) -> String:
	var sq := state.squad_of(unit_id)
	if sq == null or not sq.order_target.is_finite():
		return ""
	return "%d:%d:%d" % [sq.id, roundi(sq.order_target.x / 5.0), roundi(sq.order_target.z / 5.0)]


func _block_local_move(u: UnitState, reacting: bool, reason: String) -> void:
	local_block_log.append({"t": snappedf(state.time, 0.1), "id": u.id, "pos": [u.position.x, u.position.y, u.position.z],
		"goal": [u.order_target.x, u.order_target.y, u.order_target.z], "reacting": reacting, "reason": reason,
		"attempts": _local_attempts.get(u.id, 0)})
	if local_block_log.size() > 40:
		local_block_log.pop_front()
	u.velocity = Vector3.ZERO
	u.nav_reason = "blocked: " + reason
	if reacting:
		u.react_state = UnitState.ReactState.FAILED
	else:
		u.order = UnitState.Order.NONE
		u.move_state = UnitState.MoveState.BLOCKED
		u.anchor_pos = u.position
		state.order_changed.emit(u)


func _infantry_height(x: float, z: float) -> float:
	var p := Vector3(x, 0.0, z)
	var h := terrain.data.get_height(p) if terrain else 0.0
	var deck := state.roads.deck_height(p)
	if not is_nan(deck):
		return deck if is_nan(h) else maxf(h, deck)
	return h


## from_bridge: the closed bridge the walker already stands on (it finishes its crossing; nothing new enters a closed deck).
func _infantry_blocked(x: float, z: float, from_bridge: RoadNetwork.Bridge = null) -> bool:
	var p := Vector3(x, 0.0, z)
	# A bridge deck makes water passable, not structures placed on the deck.
	if structures.blocks_point(Vector2(x, z), INFANTRY_CLEARANCE_M):
		return true
	if not is_nan(state.roads.deck_height(p)):
		# NAVIGATION N1-C1: the deck of a closed or disabled bridge is not passable to anyone who is not already on it.
		var closed := state.roads.blocking_bridge_at(p)
		return closed != null and closed != from_bridge
	return structures.is_wet(x, z)


func _step_blocked(pos: Vector3, dir: Vector3, step: float) -> bool:
	if not _step_blocked_at(pos, dir, step, false):
		return false
	# NAV-INF-01: Terrain3D's height query has bands about 1 cm wide beside some heightmap vertices where it returns a value
	# 1-1.5 m off (the neighbouring points are fine). A walker that stands in one is "blocked in every direction" for good. A
	# refusal is therefore confirmed with the median of three nearby samples before it counts; real banks refuse both ways.
	return _step_blocked_at(pos, dir, step, true)


func _step_blocked_at(pos: Vector3, dir: Vector3, step: float, robust: bool) -> bool:
	var p := Vector2(pos.x, pos.z)
	var d := Vector2(dir.x, dir.z)
	var near := maxf(step * 2.0, 0.3)
	var look := maxf(step, 1.0)
	var h0 := _infantry_height_robust(pos.x, pos.z) if robust else _infantry_height(pos.x, pos.z)
	var on_bridge := state.roads.blocking_bridge_at(pos)
	for distance: float in [near, look]:
		var q: Vector2 = p + d * distance
		if _infantry_blocked(q.x, q.y, on_bridge):
			return true
		var h1 := _infantry_height_robust(q.x, q.y) if robust else _infantry_height(q.x, q.y)
		# N1-C1: the step from the bank onto a deck (or off it) is a kerb of 0.2-0.3 m, not a slope: steps between ground and a
		# deck skip the grade test (the deck itself is flat). With it the lip counted as a 100 % grade and nobody got onto a bridge.
		var kerb := not is_nan(state.roads.deck_height(Vector3(q.x, 0.0, q.y))) or not is_nan(state.roads.deck_height(pos))
		if is_nan(h0) or is_nan(h1) or (not kerb and absf(h1 - h0) / maxf(distance, 0.01) > INFANTRY_MAX_GRADE):
			return true
	return false


func _infantry_height_robust(x: float, z: float) -> float:
	var a := _infantry_height(x, z)
	var b := _infantry_height(x + 0.03, z)
	var c := _infantry_height(x, z + 0.03)
	if is_nan(a) or is_nan(b) or is_nan(c):
		return NAN
	return maxf(minf(a, b), minf(maxf(a, b), c))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Height of an abstract unit: the terrain, or the bridge deck it stands on; a unit beside
## a bridge above the river (a formation's outer file) moves onto the deck.
func _settle_height(u: UnitState) -> void:
	if terrain:
		var h: float = terrain.data.get_height(u.position)
		# WORLD-PLAYTEST-01: on a bridge the unit walks on the deck, not in the river below.
		var deck := state.roads.deck_height(u.position)
		if not is_nan(deck):
			h = deck if is_nan(h) else maxf(h, deck)
		elif structures and not is_nan(h) and structures.water_height(u.position.x, u.position.z) > h + 0.2:
			# Beside a bridge over the river (a formation's outer file): onto the deck.
			var on := state.roads.onto_deck(u.position)
			if on.is_finite():
				u.position.x = on.x
				u.position.z = on.z
				h = on.y
		if not is_nan(h):
			u.position.y = h


## Counts for the HUD and tests: how many units have a body, how many are moving.
func stats() -> Dictionary:
	var moving := 0
	var with_body := 0
	for u in state.units.values():
		if u.move_state == UnitState.MoveState.MOVING:
			moving += 1
		if u.has_body:
			with_body += 1
	return {"units": state.units.size(), "bodies": bodies.size(), "with_body": with_body, "moving": moving, "time": state.time}
