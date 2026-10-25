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
## NAV-PERF-01B: the one route planning service (squad marches, local refinements, vehicle routes), stepped once per rendered frame.
var routing := RouteService.new()
var _routing_bound := false
var _routing_ticks := 0
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
##
## GAMEPLAY-04A: raised to tan(50 deg) with slower climbing (slope_speed) - road shoulders and cut banks of 40-45 degrees next to
## the New Game start held soldiers at the foot of the bank or routed them far round; a soldier climbs such a bank, slowly.
const INFANTRY_MAX_GRADE := 1.19
## GAMEPLAY-04A: walking speed uphill, as a share of the flat speed: full up to SLOPE_EASY_GRADE, falling linearly to
## SLOPE_MIN_FACTOR at INFANTRY_MAX_GRADE. Downhill and across the slope are not slowed. Both tiers use slope_speed.
const SLOPE_EASY_GRADE := 0.25
const SLOPE_MIN_FACTOR := 0.4
const INFANTRY_RETRY_BUDGET := 3
const INFANTRY_RETRY_RENEW_M := 10.0
const INFANTRY_FAIL_MEMORY_S := 20.0
var _local_routes := {}
## unit id -> RouteService job id of the walker's local refinement in progress (the token: a result for another job is dropped).
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
	state.roads.bridge_changed.connect(func(b: RoadNetwork.Bridge) -> void: routing.invalidate("bridge %s %s" % [b.id, b.state_name()]))
	state.roads.changed.connect(func(rect: Rect2) -> void: routing.invalidate("roads changed", rect.grow(60.0)))
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


## NAV-PERF-01B: route searches run here, within the service's budget per rendered frame. Under time compression a frame carries
## several simulation steps; the budget is per step, up to the compression factor (about the same simulated waiting time as at 1x;
## TimeCompression keeps the frame within its own budget by running fewer steps). Steps a slow frame had to catch up do not raise
## it: a hitch is not followed by a longer route slice.
func _process(_delta: float) -> void:
	if not _routing_bound and structures != null:
		_routing_bound = true
		structures.area_changed.connect(func(rect: Rect2) -> void: routing.invalidate("structures changed", rect.grow(10.0)))
		structures.terrain_edited.connect(func(rect: Rect2) -> void: routing.invalidate("terrain edited", rect.grow(10.0)))
	var ticks := Engine.get_physics_frames()
	var steps := clampi(ticks - _routing_ticks, 1, maxi(1, roundi(Engine.time_scale)))
	_routing_ticks = ticks
	routing.step(steps)


func _physics_process(delta: float) -> void:
	last_delta = delta
	state.time += delta
	var t0 := Time.get_ticks_usec()
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
	# NAV-PERF-01B: searches for the old state are dropped; squads and vehicles that were waiting for a route ask again.
	routing.cancel_all("save loaded")
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
	# GAMEPLAY-01C: a soldier in a fortification slot stands exactly there (a tower platform: above the terrain).
	if u.fort_pos.is_finite():
		u.position = u.fort_pos
		u.velocity = Vector3.ZERO
		if not is_nan(u.watch_yaw) and not u.player_controlled:
			u.yaw = lerp_angle(u.yaw, u.watch_yaw, clampf(8.0 * delta, 0.0, 1.0))
		return
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
	var dir := to / dist
	var climb := 1.0
	if terrain:
		var h0: float = terrain.data.get_height(u.position)
		var h1: float = terrain.data.get_height(u.position + dir)
		if not is_nan(h0) and not is_nan(h1):
			climb = slope_speed(h1 - h0)
	climb *= carry_speed(u)
	var v := move_speed(u)
	var step := minf(v * abstract_friction * climb * delta, dist)
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
	u.velocity = dir * v * abstract_friction * climb
	u.yaw = atan2(-dir.x, -dir.z)
	u.move_state = UnitState.MoveState.MOVING
	_settle_height(u)


## NAVIGATION N1-C1: a bridge changed state. Local refinements of abstract infantry were planned with the old deck rule: they are
## dropped (and the retry budgets renewed); every walker re-checks the deck at its next step, and squads re-plan their routes.
func _on_bridge_changed(_b: RoadNetwork.Bridge) -> void:
	_local_routes.clear()
	for id: int in _local_pending:
		routing.cancel_owner("unit:%d" % id, "bridge changed")
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
	if _local_pending.has(id):
		routing.cancel_owner("unit:%d" % id, "order changed")
		_local_pending.erase(id)
	_local_attempts.erase(id)
	_local_anchor.erase(id)


func invalidate_local_route(id: int) -> void:
	_clear_local_route(id)


## NAV-PERF-01B: the walker waits for its local refinement (SquadControl does not count that as a stall).
func local_route_pending(id: int) -> bool:
	return _local_pending.has(id)


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
	if structures == null:
		return
	_local_attempts[u.id] = attempts + 1
	u.nav_reason = "local route queued"
	var lj := LocalJob.new(self, u.id, goal, reacting)
	var prio: int = RouteService.Priority.COMBAT if reacting else squads.route_priority(state.squad_of(u.id))
	var job := routing.submit(&"infantry_local", "unit:%d" % u.id, prio, "", lj, _on_local_job, u.position, goal,
		LocalRoutePlanner.Search.area_for(u.position, goal, INFANTRY_LOCAL_CELL, 75.0, 0.55))
	_local_pending[u.id] = job.id
	if job.is_done():
		_on_local_job(job)


## NAV-PERF-01B: one abstract walker's local refinement as a RouteService job (it replaces the old one-search-per-physics-tick queue,
## whose single search took 100-450 ms inside one tick). Every step that walks a route or builds a grid stops at the frame's deadline
## and goes on in the next frame. What squad mates found meanwhile (their shared route, a search from the same spot that failed) is
## looked at when the job starts, not when it was queued: members that stand together still do not each repeat a search (NAV-INF-01).
## The order is the one the old queue used: shared route (walkable from here?), then the failure memory, then an own search, and
## after a failed search the shared route once more.
class LocalJob:
	var sim: WorldSim
	var id := 0
	var goal := Vector3.ZERO
	var reacting := false
	var fail_key := ""
	var search: LocalRoutePlanner.Search = null
	var result := {}
	var _phase := 0
	var _shared := PackedVector3Array()
	var _walk: LocalRoutePlanner.Walk = null

	func _init(p_sim: WorldSim, p_id: int, p_goal: Vector3, p_reacting: bool) -> void:
		sim = p_sim
		id = p_id
		goal = p_goal
		reacting = p_reacting

	func step(deadline_us: int) -> bool:
		while true:
			match _phase:
				0:
					var u: UnitState = sim._local_walker(self)
					if u == null:
						result = {"ok": false, "skip": true}
						return true
					_phase = 2
					if not reacting:
						_shared = sim._shared_candidate(u, goal)
						if not _shared.is_empty():
							_walk = sim._shared_walk(u, _shared)
							_phase = 1
				1, 4:
					if not _walk.step(deadline_us):
						return false
					var walkable := not _walk.bad.is_finite()
					_walk = null
					if walkable:
						result = {"ok": true, "shared": true, "pts": _shared, "searched": _phase == 4, "search": search.result if search else {}}
						return true
					sim._local_route_cache.erase(sim._squad_route_key(id))
					if _phase == 4:
						result = search.result
						return true
					_phase = 2
				2:
					var blocked: String = sim._local_fail_memory(self)
					if blocked != "":
						result = {"ok": false, "blocked": blocked}
						return true
					search = sim._local_search(self)
					_phase = 3
				3:
					if not search.step(deadline_us):
						return false
					result = search.result
					if result.ok or reacting:
						return true
					var u2: UnitState = sim.state.get_unit(id)
					_shared = sim._shared_candidate(u2, goal) if u2 else PackedVector3Array()
					if _shared.is_empty():
						return true
					_walk = sim._shared_walk(u2, _shared)
					_phase = 4
		return true

	func reset() -> void:
		search = null
		_walk = null
		_phase = 0
		result = {}

	func debug_state() -> Dictionary:
		return {"job_phase": _phase, "shared_points": _shared.size(), "search": search.debug_state() if search else {}}


## The walker of a local job, or null when its order changed (or it got a body, died, boarded) since the request.
func _local_walker(lj: LocalJob) -> UnitState:
	var u := state.get_unit(lj.id)
	if u == null or u.has_body or not u.alive or u.vehicle_id >= 0:
		return null
	if (lj.reacting and (not u.is_reacting() or _flat(u.react_target, lj.goal) > 0.5)) \
			or (not lj.reacting and (u.order != UnitState.Order.MOVE or _flat(u.order_target, lj.goal) > 0.5)):
		return null
	return u


## "" or the reason a squad mate's search from the same 50 m cell failed a moment ago (the walker does not repeat it).
func _local_fail_memory(lj: LocalJob) -> String:
	if lj.reacting or _squad_route_key(lj.id) == "":
		return ""
	var u := state.get_unit(lj.id)
	lj.fail_key = "%s@%d,%d" % [_squad_route_key(lj.id), floori(u.position.x / 50.0), floori(u.position.z / 50.0)]
	if state.time - float(_local_fail.get(lj.fail_key, -1.0e9)) < INFANTRY_FAIL_MEMORY_S:
		return "no local passage (a squad mate's search from here failed %.0f s ago)" % (state.time - float(_local_fail[lj.fail_key]))
	return ""


func _local_search(lj: LocalJob) -> LocalRoutePlanner.Search:
	var u := state.get_unit(lj.id)
	var ctx := _infantry_area(LocalRoutePlanner.Search.area_for(u.position, lj.goal, INFANTRY_LOCAL_CELL, 75.0, 0.55))
	return LocalRoutePlanner.Search.new(u.position, lj.goal, INFANTRY_LOCAL_CELL, INFANTRY_LOCAL_MAX_CELLS, INFANTRY_MAX_GRADE,
		func(x: float, z: float) -> float: return _infantry_height_in(x, z, ctx),
		func(x: float, z: float) -> bool: return _infantry_blocked_in(x, z, ctx), 75.0, 0.55, true, false,
		Callable(self, "_step_blocked"), 1.0)


func _on_local_job(job: RouteService.Job) -> void:
	var lj: LocalJob = job.runner
	var id := lj.id
	if int(_local_pending.get(id, -1)) != job.id:
		return  # replaced: a newer order or request owns the walker now
	_local_pending.erase(id)
	var u := state.get_unit(id)
	var result := job.result
	if u == null or bool(result.get("skip", false)):
		return
	var reacting := lj.reacting
	var goal := lj.goal
	if result.has("blocked"):
		_block_local_move(u, reacting, String(result.blocked))
		return
	var searched: Dictionary = result.get("search", {}) if bool(result.get("shared", false)) else result
	if not bool(result.get("shared", false)) or bool(result.get("searched", false)):
		local_nav_stats.searches += 1
		local_nav_stats.repairs += int(searched.get("repairs", 0))
		local_nav_stats.plan_ms_total += float(searched.get("ms", 0.0))
		local_nav_stats.plan_ms_max = maxf(float(local_nav_stats.plan_ms_max), float(searched.get("ms", 0.0)))
	if bool(result.get("shared", false)):
		_local_routes[id] = {"goal": goal, "reacting": false, "pts": result.pts, "i": 1, "cached": true, "cache_key": _squad_route_key(id)}
		local_nav_stats.cache_hits += 1
		local_nav_stats.recoveries += 1
		u.nav_reason = "shared squad local route active"
		return
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
		local_nav_stats.failures += 1
		if lj.fail_key != "":
			_local_fail[lj.fail_key] = state.time
		_block_local_move(u, reacting, String(result.reason))


## The squad's shared local route for this walker (the cached route with the walker's goal appended), not yet checked; empty: none.
func _shared_candidate(u: UnitState, goal: Vector3) -> PackedVector3Array:
	var cached: PackedVector3Array = _local_route_cache.get(_squad_route_key(u.id), PackedVector3Array())
	if cached.size() < 2:
		return PackedVector3Array()
	var adapted := cached.duplicate()
	adapted.append(goal)
	return adapted


## The walker's own test along a shared route from where it stands (resumable).
func _shared_walk(u: UnitState, adapted: PackedVector3Array) -> LocalRoutePlanner.Walk:
	var walk := PackedVector3Array([u.position])
	walk.append_array(adapted.slice(1))
	return LocalRoutePlanner.Walk.new(walk, Callable(self, "_step_blocked"), 1.0)


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


## NAV-PERF-01B: what a search area holds, measured once per search so the per-cell tests can skip what cannot be there: no blocking
## footprint in reach, no bridge deck, ground well above any water surface. The answers are those of _infantry_blocked /
## _infantry_height (the same tests, far fewer calls).
func _infantry_area(rect: Rect2) -> Dictionary:
	var r := rect.grow(INFANTRY_CLEARANCE_M + 2.0)
	return {"block": structures.blocks_in_rect(r), "deck": not state.roads.bridges_in(rect.grow(30.0)).is_empty(),
		"wet_top": structures.water_top_in_rect(r)}


func _infantry_height_in(x: float, z: float, ctx: Dictionary) -> float:
	if ctx.deck:
		return _infantry_height(x, z)
	return terrain.data.get_height(Vector3(x, 0.0, z)) if terrain else 0.0


func _infantry_blocked_in(x: float, z: float, ctx: Dictionary) -> bool:
	if ctx.block and structures.blocks_point(Vector2(x, z), INFANTRY_CLEARANCE_M):
		return true
	if ctx.deck:
		var p := Vector3(x, 0.0, z)
		if not is_nan(state.roads.deck_height(p)):
			return state.roads.blocking_bridge_at(p) != null
	var h := structures._height(x, z)
	if is_nan(h) or h >= float(ctx.wet_top) + 0.15:
		return false
	return structures._wet(x, z, h)


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
## VISUAL-03: the pace a soldier moves at right now, read from the state that already says how urgent its movement is
## (no separate locomotion decision): a cover reaction or fire taken -> run; the squad's assault, flank, bound or
## withdrawal -> run; other squad tactics (defend, reposition, regroup, suppress, build) -> jog; an operation past its
## approach (deploy, support, assault, secure, withdraw) -> run, its approach -> jog on the march and run over the last
## APPROACH_RUN_M, in transport -> jog; a squad garrisoning a
## base -> walk; otherwise the pace the order chose (SquadState.pace), else jog (ordinary RTS movement). Both tiers.
func pace_of(u: UnitState) -> int:
	if u.is_reacting() or state.time < u.under_fire_until:
		return UnitState.Pace.RUN
	var sq := state.squad_of(u.id)
	if sq == null:
		return UnitState.Pace.JOG
	match sq.tactic:
		SquadState.Tactic.ASSAULT, SquadState.Tactic.FLANK, SquadState.Tactic.BOUND, SquadState.Tactic.WITHDRAW:
			return UnitState.Pace.RUN
		SquadState.Tactic.DEFEND, SquadState.Tactic.REPOSITION, SquadState.Tactic.REGROUP, SquadState.Tactic.SUPPRESS, 				SquadState.Tactic.BUILD:
			return UnitState.Pace.JOG
	if sq.op_id >= 0 and state.war:
		var op: OperationState = state.war.operations.get(sq.op_id)
		if op and op.stage >= OperationState.Stage.DEPLOY and op.stage < OperationState.Stage.DONE:
			return UnitState.Pace.RUN
		# The approach: a jog on the march, a run over the last APPROACH_RUN_M before the target (within rifle range of
		# the defence; jogging that stretch left an assault exposed for a third longer than the CHARACTER-01 pace).
		if op and op.stage == OperationState.Stage.APPROACH and _flat(u.position, op.target_pos) < APPROACH_RUN_M:
			return UnitState.Pace.RUN
		if op:
			return UnitState.Pace.JOG
	if sq.pace >= 0:
		return sq.pace
	if sq.garrison_base >= 0:
		return UnitState.Pace.WALK
	return UnitState.Pace.JOG


const APPROACH_RUN_M := 500.0
## VISUAL-03: the paces are opt-in (--paces) until COMBAT-01 settles movement speeds and tactics: without the flag every
## soldier moves at `speed` (4.5 m/s) as before; the walk / brisk / jog / run clips are in the animation set either way.
static var PACES := "--paces" in OS.get_cmdline_user_args()


## VISUAL-03: ground speed of a soldier at its current pace (before grade and carried load); vehicles keep `speed`.
func move_speed(u: UnitState) -> float:
	if u.kind != UnitState.Kind.SOLDIER or not PACES:
		return u.speed
	return minf(UnitState.PACE_SPEED[pace_of(u)], u.speed)


## GAMEPLAY-04C: share of the walking speed a soldier keeps with what he carries (WeaponDef.move_speed_mult: the heavy machine
## gun and its belt). Both tiers.
func carry_speed(u: UnitState) -> float:
	var def := combat.weapon(u.weapon_id) if combat else null
	return def.move_speed_mult if def else 1.0


## GAMEPLAY-04A: share of the walking speed left on an uphill grade (rise per metre walked; negative = downhill).
static func slope_speed(grade: float) -> float:
	if grade <= SLOPE_EASY_GRADE:
		return 1.0
	var t := clampf((grade - SLOPE_EASY_GRADE) / (INFANTRY_MAX_GRADE - SLOPE_EASY_GRADE), 0.0, 1.0)
	return lerpf(1.0, SLOPE_MIN_FACTOR, t)


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
