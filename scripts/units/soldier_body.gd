## Physical soldier: the detailed-tier body of a UnitState.
##
## Reuses the WORLD-TECH-01 first-person controller unchanged: when possessed, the
## FPSController reads the keyboard and mouse; when nobody controls it, this script
## executes the unit's move order through a NavigationAgent3D (navmesh path + RVO
## avoidance against the other soldiers) and feeds the same CharacterBody3D. Either
## way the result is written back into the UnitState every physics tick, so the record
## in WorldState is always what the world shows. A possessed soldier suspends its order
## and resumes it when the player leaves; it never loses it.
class_name SoldierBody
extends FPSController

## Flat distance at which an order counts as reached.
@export var arrive_distance := 1.3
## COMBAT-02: a cover position must be reached more closely than an order slot.
@export var react_arrive_distance := 0.7
## Reached the end of the navigation path but still farther than this from the target:
## the target was not reachable (outside the navmesh), reported as BLOCKED.
@export var blocked_distance := 3.0
@export var turn_speed := 8.0
## Repath attempts before an order with no navigation path is reported as BLOCKED.
@export var max_empty_path_s := 4.0
## UNIT-01A stuck handling: a soldier that walks but gains less than stuck_progress_m in
## stuck_s first re-queries its path and ignores crowd avoidance for unstick_s (two
## agents can hold each other in a narrow gap); still stuck after another stuck_s, the
## order ends as BLOCKED instead of walking in place forever.
@export var stuck_s := 3.0
@export var stuck_progress_m := 0.8
@export var unstick_s := 1.5
## NAV-INF-01: distance walked after a stuck episode that counts as real progress. The unstick stage is a budget for one
## blockage, not for the whole march: a later, unrelated jam gets its own recovery instead of dropping the order.
@export var stuck_clear_m := 4.0
## NAV-INF-01: a ledge up to this high is stepped onto. The navmesh is baked from the terrain only, while roads are collision
## meshes 12-25 cm above it with a sharp edge: a capsule of radius 0.35 m cannot slide up such an edge (contact normal y 0.3-0.6),
## so every soldier whose path crossed a road verge stood still against it until the stuck logic gave up on the order.
@export var step_height := 0.35
## GAMEPLAY-04A: the highest edge a stuck soldier climbs over on its first unstick attempt (_hop_ledge). GAMEPLAY-05B: 1.2 m - the
## road mesh at the navinf_04 verge stands ~1 m above the slope below it (the collider is wider and ~0.2 m higher than the
## RoadNetwork line the shoulders ease to), one step too high for 0.95 m.
@export var ledge_hop_m := 1.2
## GAMEPLAY-04A: a soldier whose navmesh path ends under its feet walks straight at a goal farther than this (nearer, among
## the squad's formation slots, it waits for the path as before).
@export var straight_fallback_m := 15.0

var unit: UnitState
var sim: WorldSim
var selected := false:
	set(v):
		selected = v
		if is_node_ready():
			UnitVisuals.style_ring(ring, unit.faction if unit else 0, selected, true)

@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var visual: Node3D = $Visual
@onready var ring: MeshInstance3D = $Ring
## CHARACTER-01 infantry character (null when the placeholder model is used).
var character: InfantryCharacter

var _safe_velocity := Vector3.ZERO
var _applied_target := Vector3.INF
var _empty_path_s := 0.0
## Scripted tests run in a window that may not hold OS mouse capture; they clear this so
## the trigger works without it. Always true in play.
static var require_mouse_capture := true
## COMBAT-01a first-person weapon: the viewmodel exists while possessed.
var viewmodel: Viewmodel
## The trigger only works after it was released once with the mouse captured (the click
## that captures the mouse must not fire).
var _trigger_armed := false
var _fov_hip := 75.0
var _base_sens := 0.0025
var _progress_ref := Vector3.INF
var _progress_t := 0.0
var _stuck_stage := 0
## Which movement branch _ai_step took last (diagnostics).
var dbg_branch := ""
## Where the first stuck stage was raised: real progress from there (stuck_clear_m) renews the recovery budget.
var _stuck_at := Vector3.INF
var _unstick_left := 0.0
## Diagnostics (AI-WAR-LOGISTICS-01 movement parity): what the last AI step wanted.
## GAMEPLAY-01C: the body was standing in a fortification slot last tick.
var _in_fort := false
var dbg_desired := 0.0
var dbg_next_dist := -1.0
## BRIDGE-NAV-01: the path waypoint reached on the ground (_ground_waypoint), and which path it belongs to.
var _wp_idx := 0
var _wp_size := -1
var _wp_first := Vector3.INF


func _ready() -> void:
	ensure_combat_actions()
	_base_sens = mouse_sensitivity
	player_controlled = false
	super()
	nav.velocity_computed.connect(_on_velocity_computed)
	possession_changed.connect(_on_possession_changed)
	# QOL-01.1: avoidance may hand back up to the sprint (the desired speed is the pace; walk_speed capped sprints at 4.5).
	nav.max_speed = maxf(walk_speed, UnitState.PACE_SPEED[UnitState.Pace.SPRINT])
	# GAMEPLAY-04A: the body stands and walks on the same grades the routes send it over (WorldSim.INFANTRY_MAX_GRADE, slower uphill).
	floor_max_angle = atan(WorldSim.INFANTRY_MAX_GRADE) + deg_to_rad(2.0)


## Attaches this body to a unit record and registers it with the simulation.
func bind(p_unit: UnitState, p_sim: WorldSim) -> void:
	unit = p_unit
	sim = p_sim
	name = "Soldier_%d" % unit.id
	global_position = unit.position
	rotation.y = unit.yaw
	velocity = Vector3.ZERO
	_spawn = global_transform
	if InfantryCharacter.enabled():
		_use_infantry_character()
	else:
		UnitVisuals.apply_faction(visual, unit.faction)
	UnitVisuals.style_ring(ring, unit.faction, selected, true)
	sim.register_body(unit.id, self)
	_sync_state()


## Replaces the placeholder model with the modular infantry character for the unit's
## loadout. Built once per body; a re-promoted unit gets the same loadout (UnitState).
func _use_infantry_character() -> void:
	if unit.loadout == "":
		unit.loadout = InfantryLoadout.default_for(unit.id, unit.faction)
	var lo := InfantryLoadout.by_id(unit.loadout)
	if lo == null:
		UnitVisuals.apply_faction(visual, unit.faction)
		return
	if character and character.loadout == lo and character.faction == unit.faction:
		return
	for c in visual.get_children():
		visual.remove_child(c)
		c.queue_free()
	character = InfantryCharacter.new()
	character.name = "Infantry"
	character.body = self
	visual.add_child(character)
	character.setup(lo, unit.faction)
	if player_controlled:
		UnitVisuals.set_shadows_only(visual, true)


## GAMEPLAY-04D: the record's loadout changed (re-equipped at a base): the character is rebuilt for it.
func refresh_look() -> void:
	if unit and InfantryCharacter.enabled():
		_use_infantry_character()
	if viewmodel and player_controlled:
		_set_viewmodel(false)
		_set_viewmodel(true)


func _exit_tree() -> void:
	if sim and unit and sim.bodies.get(unit.id) == self:
		sim.unregister_body(unit.id)


func _process(_delta: float) -> void:
	# GAMEPLAY-03D: the launcher in the hands while the record says so (AI raising / just fired, or switched to in first person).
	if character and unit and sim and unit.sec_id != &"":
		var on := unit.launcher_in_hands(sim.state.time)
		var def := sim.combat.weapon(unit.sec_id)
		var scene := def.held_scene() if def else null
		# ASSET-INTEGRATION-01: also when another secondary weapon was issued while one is held
		if on != character.secondary_shown() or (on and scene != character.secondary_scene()):
			character.show_secondary(on, scene, def.held_piece if def else null)
	if ring.visible:
		UnitVisuals.scale_ring_for_camera(ring, selected, true)


func _physics_process(delta: float) -> void:
	if unit == null:
		return
	if player_controlled:
		# COMBAT-01: the record's posture limits the possessed body too (crouch walk, prone crawl, still while getting down).
		if unit:
			speed_scale = Posture.speed_mult(unit, sim.state.time) if sim else 1.0
			may_sprint = unit.posture == Posture.STAND and Posture.settled(unit, sim.state.time if sim else NAN)
		super(delta)
		_player_eye(delta)
		_recoil_recover(delta)
		# Let the avoidance simulation know where the player is heading.
		if nav.avoidance_enabled:
			nav.velocity = Vector3(velocity.x, 0.0, velocity.z)
		_player_weapon(delta)
	elif unit.fort_pos.is_finite():
		_hold_fort(delta)
	else:
		if _in_fort:
			# GAMEPLAY-01C: the record left its slot (WorldState.leave_fort put it on the exit point): the body follows.
			_in_fort = false
			teleport(unit.position, rotation.y)
			reset_order_tracking()
		_ai_step(delta)
	_sync_state()
	if character:
		# COMBAT-01: the character shows the record's posture (stand / crouch / prone and the change between them).
		# GAMEPLAY-01B: soldiers at work on a construction site kneel at it (the work pose).
		var now := sim.state.time
		character.set_posture(unit.posture_from, unit.posture, Posture.progress(unit, now))
		character.crouched = Posture.current(unit, now) == Posture.CROUCH or (not player_controlled and unit.work_until > now)
		character.ground_slope = _prone_slope() if unit.posture == Posture.PRONE or unit.posture_from == Posture.PRONE else Vector2.ZERO
		_character_layers()


## COMBAT-POLISH-01: the slope under the lying soldier (InfantryCharacter.slope_at); the character lays the prone body onto it.
func _prone_slope() -> Vector2:
	return InfantryCharacter.slope_at(sim.terrain.data, global_position, rotation.y) if sim and sim.terrain else Vector2.ZERO


## GAMEPLAY-01C: in a fortification slot the body stands exactly where the record says (on a tower platform too), without
## navigation or gravity, and turns to what its AI watches.
func _hold_fort(delta: float) -> void:
	_in_fort = true
	global_position = unit.fort_pos
	velocity = Vector3.ZERO
	_applied_target = Vector3.INF
	if not is_nan(unit.watch_yaw):
		rotation.y = lerp_angle(rotation.y, unit.watch_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	if nav.avoidance_enabled:
		nav.velocity = Vector3.ZERO


func _ai_step(delta: float) -> void:
	var desired := Vector3.ZERO
	# COMBAT-02: a tactical reaction (react_target) pauses the order: walk to the
	# reaction's goal, then wait there until the AI ends the reaction.
	var reacting := unit.is_reacting()
	var goal := unit.react_target if reacting else unit.order_target
	if reacting and unit.react_state != UnitState.ReactState.MOVING:
		_applied_target = Vector3.INF
		if not is_nan(unit.watch_yaw):
			rotation.y = lerp_angle(rotation.y, unit.watch_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	elif reacting or unit.order == UnitState.Order.MOVE:
		if _applied_target != goal:
			_applied_target = goal
			nav.target_position = goal
			if not reacting:
				unit.move_state = UnitState.MoveState.MOVING
			_empty_path_s = 0.0
			_reset_stuck()
		var flat := goal - global_position
		flat.y = 0.0
		var remaining := flat.length()
		# get_next_path_position() is what makes the agent (re)query its path.
		var next := nav.get_next_path_position()
		var path_len := nav.get_current_navigation_path().size()
		dbg_branch = "?"
		# WORLD-COVER-01: a walk to a post (a cover or firing position a tactic gave, UnitState.post_pos) ends as precisely as a
		# cover dash: a metre off is out of the cover's shadow.
		var to_post := unit.post_pos.is_finite() and Vector2(unit.post_pos.x - goal.x, unit.post_pos.z - goal.z).length() < 0.5
		if remaining <= (react_arrive_distance if reacting or to_post else arrive_distance):
			dbg_branch = "arrive"
			_finish(remaining, reacting)
		elif path_len == 0 and sim.detail and not sim.detail.nav_covers(goal):
			dbg_branch = "no_path_off_nav"
			desired = flat.normalized() * _ai_speed()
			_face(flat.normalized(), delta)
		elif path_len == 0:
			dbg_branch = "no_path"
			# No path yet (navigation map not synced, or target off the navmesh): retry.
			_empty_path_s += delta
			if _empty_path_s > max_empty_path_s:
				_finish(remaining, reacting, "no navmesh path to the target")
			elif Engine.get_physics_frames() % 10 == 0:
				nav.target_position = goal
		elif nav.is_navigation_finished():
			dbg_branch = "nav_finished"
			if remaining > blocked_distance and sim.detail and not sim.detail.nav_covers(goal):
				# The target lies beyond the navmesh area around the active camera: keep
				# heading for it. Leaving the camera's detail radius hands the unit to
				# the abstract tier, which finishes the walk (the order is never dropped).
				var far_dir := flat.normalized()
				desired = far_dir * _ai_speed()
				_face(far_dir, delta)
			else:
				_finish(remaining, reacting, "navmesh path ends short of the target")
		else:
			dbg_branch = "path"
			var wp := _ground_waypoint()
			var dir := (wp if wp.is_finite() else next) - global_position
			dir.y = 0.0
			dbg_next_dist = dir.length()
			# AI-WAR-LOGISTICS-01 (movement parity): the agent's next path point can lie under the soldier's feet
			# (its own start point, or a point straight above / below it). The old code then asked for no movement
			# at all, and as stuck detection ran only for a moving soldier, a whole squad could stand still on a
			# valid path for minutes while the abstract tier walked the same route in a fraction of the time.
			if dir.length_squared() <= 0.09:
				dir = _next_distinct_dir()
			if dir.length_squared() <= 1e-4 and remaining > straight_fallback_m:
				# GAMEPLAY-04A: the rest of the path lies straight above / below the soldier (the navmesh is baked from the
				# terrain with up to 1 m of height error and without the road surface, so beside a road bank its path can end
				# "here" one metre up). Standing still waiting for a better path held soldiers at road banks next to the New
				# Game start for the rest of the order: walk straight at the goal instead, as off the navmesh; the stuck
				# handling still watches the progress.
				dir = flat
			if dir.length_squared() > 1e-4:
				dir = dir.normalized()
				desired = dir * _ai_speed()
				_face(dir, delta)
			else:
				_empty_path_s += delta
				if _empty_path_s > 1.0:
					_empty_path_s = 0.0
					nav.target_position = goal
		# A soldier that wants to go and gains no ground is stuck, whatever the reason (an order or reaction that was
		# just finished above is over and has nothing to be stuck on).
		if (reacting and unit.react_state == UnitState.ReactState.MOVING) or (not reacting and unit.order == UnitState.Order.MOVE):
			_check_stuck(delta, remaining, reacting)
	else:
		_applied_target = Vector3.INF
		# COMBAT-01b: standing, the soldier turns to what its AI watches (its target).
		if not is_nan(unit.watch_yaw):
			rotation.y = lerp_angle(rotation.y, unit.watch_yaw, clampf(turn_speed * delta, 0.0, 1.0))
	dbg_desired = desired.length()
	if _unstick_left > 0.0:
		_unstick_left -= delta
		_apply_velocity(desired, delta)
		return
	if nav.avoidance_enabled:
		nav.velocity = desired
		_apply_velocity(_safe_velocity if desired != Vector3.ZERO else Vector3.ZERO, delta)
	else:
		_apply_velocity(desired, delta)


## BRIDGE-NAV-01: the waypoint to steer for. The agent counts a waypoint reached within path_desired_distance in 3D, but the
## navmesh's heights are off by up to ~1.5 m where a long polygon edge spans a hollow: a corner that high above the ground is
## never reached, and a soldier who walked on under it turned back to it, forth and back on the spot (Rv1 bridge approach).
## A waypoint is therefore reached on the ground too (flat distance), remembered until the agent moves on or the path changes.
## The last point is never skipped. INF without a path.
func _ground_waypoint() -> Vector3:
	var path := nav.get_current_navigation_path()
	if path.is_empty():
		return Vector3.INF
	var i0 := maxi(nav.get_current_navigation_path_index(), 0)
	if path.size() != _wp_size or path[0] != _wp_first or i0 > _wp_idx:
		_wp_size = path.size()
		_wp_first = path[0]
		_wp_idx = i0
	while _wp_idx < path.size() - 1:
		var d := path[_wp_idx] - global_position
		d.y = 0.0
		if d.length() > nav.path_desired_distance:
			break
		_wp_idx += 1
	return path[mini(_wp_idx, path.size() - 1)]


## The first point of the current navigation path, from the agent's own index on, that lies more than 0.6 m
## away on the ground (as a flat vector from the soldier); ZERO when there is none.
func _next_distinct_dir() -> Vector3:
	var path := nav.get_current_navigation_path()
	var i0 := maxi(nav.get_current_navigation_path_index(), 0)
	if path.size() == _wp_size and path.size() > 0 and path[0] == _wp_first:
		i0 = maxi(i0, _wp_idx)
	for k in range(i0, path.size()):
		var d := path[k] - global_position
		d.y = 0.0
		if d.length() > 0.6:
			return d
	return Vector3.ZERO


## The record's order was replaced from outside (load): apply it afresh.
func reset_order_tracking() -> void:
	_applied_target = Vector3.INF
	_safe_velocity = Vector3.ZERO
	_empty_path_s = 0.0
	_reset_stuck()


func _reset_stuck() -> void:
	_progress_ref = global_position
	_progress_t = 0.0
	_stuck_stage = 0
	_stuck_at = Vector3.INF
	_unstick_left = 0.0


func _check_stuck(delta: float, remaining: float, reacting := false) -> void:
	if not _progress_ref.is_finite() or global_position.distance_to(_progress_ref) > stuck_progress_m:
		_progress_ref = global_position
		_progress_t = 0.0
		if _stuck_stage > 0 and _stuck_at.is_finite() and global_position.distance_to(_stuck_at) >= stuck_clear_m:
			_stuck_stage = 0
			_stuck_at = Vector3.INF
		return
	_progress_t += delta
	if _progress_t < stuck_s:
		return
	_progress_t = 0.0
	if _stuck_stage == 0:
		_stuck_stage = 1
		_stuck_at = global_position
		nav.target_position = unit.react_target if reacting else unit.order_target
		_unstick_left = unstick_s
		_hopped = _hop_ledge(unit.react_target if reacting else unit.order_target)
	else:
		# GAMEPLAY-05B: where and against what a soldier gave up (tests read stuck_log; bounded).
		stuck_log.append({"id": unit.id, "pos": [snappedf(global_position.x, 0.1), snappedf(global_position.y, 0.1), snappedf(global_position.z, 0.1)],
			"goal_m": snappedf(remaining, 0.1), "floor_n": get_floor_normal().snapped(Vector3.ONE * 0.01) if is_on_floor() else null,
			"wall_n": get_wall_normal().snapped(Vector3.ONE * 0.01) if is_on_wall() else null, "hopped": _hopped, "reacting": reacting,
			"next_d": snappedf(_next_distinct_dir().length(), 0.1), "real_v": get_real_velocity().snapped(Vector3.ONE * 0.01),
			"safe_v": _safe_velocity.snapped(Vector3.ONE * 0.01), "floor_max_deg": snappedf(rad_to_deg(floor_max_angle), 0.1),
			"nav_fin": nav.is_navigation_finished()})
		if stuck_log.size() > 60:
			stuck_log.pop_front()
		_finish(remaining, reacting, "stuck: no progress after an unstick attempt")


func _finish(remaining: float, reacting: bool, why := "") -> void:
	if reacting:
		# The order is untouched; the AI decides what the arrival (or failure) means.
		unit.react_state = UnitState.ReactState.ARRIVED if remaining <= react_arrive_distance + 0.8 else UnitState.ReactState.FAILED
		_applied_target = Vector3.INF
		return
	_finish_order(remaining, why)


func _finish_order(remaining: float, why := "") -> void:
	unit.order = UnitState.Order.NONE
	unit.move_state = UnitState.MoveState.ARRIVED if remaining <= blocked_distance else UnitState.MoveState.BLOCKED
	unit.nav_reason = "" if unit.move_state == UnitState.MoveState.ARRIVED else "%s, %.1f m from the target" % [why if why != "" else "near path ended", remaining]
	unit.anchor_pos = global_position
	_applied_target = Vector3.INF
	sim.state.order_changed.emit(unit)


func _apply_velocity(v: Vector3, delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif v.length_squared() > 0.01:
		# GAMEPLAY-04A: uphill slower, the same rule as the abstract tier (WorldSim.slope_speed); the floor normal gives the grade
		# along the walking direction.
		var n := get_floor_normal()
		var flat_n := Vector2(n.x, n.z)
		if flat_n.length_squared() > 1e-6 and n.y > 0.01:
			var along := -Vector2(v.x, v.z).normalized().dot(flat_n) / n.y
			v *= WorldSim.slope_speed(along)
		v *= sim.carry_speed(unit) if sim and unit else 1.0
	velocity.x = v.x
	velocity.z = v.z
	if step_height > 0.0 and is_on_floor():
		_step_up(delta)
	move_and_slide()


## GAMEPLAY-04A: a soldier pressed against a low edge stops dead (its velocity after the collision is zero, so _step_up,
## which needs a moving body, never fires): seen at road verges next to the New Game start, where a soldier stood against
## the road's edge 0.1 m below its surface for the rest of the order. On the first stuck stage the body is lifted over the
## edge towards its goal when the space above and ahead is free (the same test _step_up makes); otherwise nothing changes.
func _hop_ledge(goal: Vector3) -> String:
	# GAMEPLAY-05B: towards where the path goes next (the goal itself can lie past a bend), and an edge is found by testing the
	# move, not by is_on_wall(): a soldier standing still against an edge often reports no wall contact (zero velocity, nothing to
	# slide along), so the hop never fired and the second stuck stage dropped the order (navinf_04, 3 of 6 stuck at one verge).
	var ahead := _next_distinct_dir()
	if ahead.length_squared() < 0.01:
		ahead = goal - global_position
		ahead.y = 0.0
	if ahead.length_squared() < 0.01:
		return "no direction"
	var motion := ahead.normalized() * 0.5
	# An edge is a contact steeper than the walkable limit (a plain slope ahead is ground, not an edge; the rule of _step_up).
	var hit := KinematicCollision3D.new()
	if not is_on_wall() and (not test_move(global_transform, motion * 0.6, hit) or hit.get_normal().y >= cos(floor_max_angle)):
		return "no edge ahead"
	# The lowest lift that clears it, up to ledge_hop_m (road embankments stand up to ~1 m above the slope beside them).
	for h: float in [step_height + 0.15, 0.7, 0.95, ledge_hop_m]:
		var lift := Vector3.UP * h
		if test_move(global_transform, lift) or test_move(global_transform.translated(lift), motion):
			continue
		global_position += lift + motion
		velocity.y = 0.0
		ledge_hops += 1
		return "hopped %.2f m" % h
	return "edge higher than %.2f m or no room" % ledge_hop_m


## Times a stuck soldier was lifted over a low edge (_hop_ledge), for tests.
static var ledge_hops := 0
## GAMEPLAY-05B: the last soldiers that gave up an order as stuck (where, normals, what the hop found), for tests.
static var stuck_log: Array = []
var _hopped := ""


## Walks up a ledge the capsule would otherwise stand against: when the next move hits a wall (not a floor) and the same move
## from step_height higher is free, the body is lifted over the ledge; gravity and the floor snap put it on top.
func _step_up(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < 0.25:
		return
	var motion := horizontal.normalized() * maxf(horizontal.length() * delta, 0.1)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit) or hit.get_normal().y >= cos(floor_max_angle):
		return
	var raised := global_transform.translated(Vector3.UP * step_height)
	if test_move(global_transform, Vector3.UP * step_height) or test_move(raised, motion):
		return
	global_position += Vector3.UP * step_height + motion
	velocity.y = 0.0
	apply_floor_snap()


## VISUAL-03: what the character's upper-body layers show, from the record the AI writes: the rifle raised at the target
## the soldier tracks (or shot at in the last seconds), the ready stance while it is alerted, a reload while one runs and a
## recoil per shot. Read-only: the record stays the authority.
var _seen_shots := -1


func _character_layers() -> void:
	if player_controlled or sim == null:
		character.aim_point = Vector3.INF
		character.alert = false
		character.reloading = false
		_seen_shots = unit.shot_counter
		return
	var now := sim.state.time
	character.reloading = unit.reload_until >= now
	var tracking := unit.target_id >= 0 and now - unit.target_seen_at < 6.0
	var shooting := now - unit.last_shot_at < 2.5
	if unit.target_last_pos.is_finite() and (tracking or shooting):
		# COMBAT-01: at the height of the target's posture (its head / torso), where it was last seen.
		var tgt := sim.state.get_unit(unit.target_id)
		var h := unit.target_aim_y
		if tgt:
			h = Posture.aim_point(tgt, unit.target_aim_y > 1.3, now).y - tgt.position.y
		character.aim_point = unit.target_last_pos + Vector3.UP * h
	else:
		character.aim_point = Vector3.INF
	character.alert = unit.ai_state != UnitState.AiState.IDLE or now < unit.watch_until or now < unit.under_fire_until
	# QOL-01: weapon readiness by the squad's behaviour - SAFE relaxed unless fighting or shot at, COMBAT / STEALTH always ready.
	var sq := sim.state.squad_of(unit.id)
	if sq:
		match sim.tactics.behaviour_now(sq):
			SquadBehaviour.SAFE:
				character.alert = unit.ai_state == UnitState.AiState.ENGAGING or now < unit.under_fire_until
			SquadBehaviour.COMBAT, SquadBehaviour.STEALTH:
				character.alert = true
	if unit.shot_counter != _seen_shots:
		if _seen_shots >= 0:
			character.fire()
		_seen_shots = unit.shot_counter


## VISUAL-03: an AI-driven body moves at its record's pace (WorldSim.move_speed), the same as the abstract tier; the
## possessed body keeps the FPS controller's walk / sprint.
func _ai_speed() -> float:
	return sim.move_speed(unit) if sim and unit else walk_speed


func _face(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _sync_state() -> void:
	unit.position = global_position
	unit.yaw = rotation.y
	unit.velocity = velocity
	unit.player_controlled = player_controlled


func _on_velocity_computed(safe: Vector3) -> void:
	_safe_velocity = safe


func _on_possession_changed(controlled: bool) -> void:
	# Re-apply the suspended order when control returns to the simulation.
	_applied_target = Vector3.INF
	_safe_velocity = Vector3.ZERO
	if is_node_ready():
		UnitVisuals.set_shadows_only(visual, controlled)
		ring.visible = not controlled
		_set_viewmodel(controlled)
	if unit:
		unit.player_controlled = controlled
		if controlled and unit.fort_pos.is_finite():
			# GAMEPLAY-01C: the player takes over where the soldier stands (in the slot); the slot is his to leave.
			unit.fort_pos = Vector3.INF
			unit.fort_exit = Vector3.INF
			unit.fort_slot = ""
			_in_fort = false


# --- First-person weapon (COMBAT-01a) ------------------------------------------------

## LMB fire (held = automatic when the rifle is in auto), R reload, V fire mode, RMB aim.
## The shot leaves from the eye along the view; CombatSim resolves it like any other.
## GAMEPLAY-02C: G throws a grenade at the point under the crosshair (at most 35 m), X raises / lowers the secondary
## weapon (the launcher: LMB fires it). The same CombatSim calls as the AI's.
func _player_weapon(delta: float) -> void:
	if unit == null or not unit.alive or sim == null:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or not require_mouse_capture
	var held := Input.is_action_pressed("fire")
	if not captured:
		_trigger_armed = false
	elif not held:
		_trigger_armed = true
	var aiming := captured and Input.is_action_pressed("aim")
	if viewmodel:
		viewmodel.aiming = aiming
		viewmodel.reloading = unit.is_reloading()
	# COMBAT-01: the weapon's sight decides the zoom (a marksman optic magnifies); the mouse slows with it.
	var wd := sim.combat.weapon(unit.sec_id if unit.sec_active else unit.weapon_id)
	var ads := wd.ads_fov if wd else 42.0
	camera.fov = lerpf(camera.fov, ads if aiming else _fov_hip, clampf(delta * 12.0, 0.0, 1.0))
	mouse_sensitivity = _base_sens * clampf(camera.fov / maxf(_fov_hip, 1.0), 0.25, 1.0)
	if not captured:
		return
	_player_posture()
	if Input.is_action_just_pressed("reload"):
		sim.combat.request_reload(unit.id)
	if Input.is_action_just_pressed("fire_mode"):
		sim.combat.set_fire_mode(unit.id, not unit.fire_auto)
	if Input.is_action_just_pressed("throw_grenade"):
		var view := -camera.global_basis.z
		var look := sim.combat.line.trace(camera.global_position, camera.global_position + view * 35.0, unit.id)
		sim.combat.throw_grenade(unit.id, look.point, CombatSim.Source.PLAYER)
	if Input.is_action_just_pressed("switch_weapon") and unit.sec_id != &"":
		unit.sec_active = not unit.sec_active
		_set_viewmodel(false)
		_set_viewmodel(true)
	if not _trigger_armed or not held:
		return
	if unit.sec_active:
		if Input.is_action_just_pressed("fire"):
			# GAMEPLAY-04C: a lobbed 40 mm round comes down where the crosshair points (the distance along the sight line).
			var sdef := sim.combat.weapon(unit.sec_id)
			var aim_dist := -1.0
			if sdef and sdef.role == &"gl":
				var look := sim.combat.line.trace(camera.global_position, camera.global_position - camera.global_basis.z * sdef.max_range, unit.id)
				aim_dist = look.distance
			var ms := sim.combat.muzzle_shot(unit.id, camera.global_position, -camera.global_basis.z, muzzle_position())
			var r := sim.combat.fire_secondary(unit.id, ms.origin, ms.dir, CombatSim.Source.PLAYER, aim_dist)
			if r.get("fired", false):
				_recoil()
		return
	if not unit.fire_auto and not Input.is_action_just_pressed("fire"):
		return
	# COMBAT-COVER-03: the round leaves the muzzle towards the point under the crosshair (CombatSim.muzzle_shot), not the camera.
	var wdef := sim.combat.weapon(unit.weapon_id)
	var ms := sim.combat.muzzle_shot(unit.id, camera.global_position, -camera.global_basis.z, muzzle_position(), wdef.max_range if wdef else 1200.0)
	var shot := sim.combat.request_fire(unit.id, ms.origin, ms.dir, CombatSim.Source.PLAYER)
	if shot.get("fired", false):
		_recoil()


## COMBAT-01 first-person recoil: the view kicks up (and drifts sideways with the weapon's bias plus a little seeded
## variation), then recovers recoil_recover of it over recoil_recover_s - a burst climbs predictably and a single aimed
## shot comes back close to where it was. Crouched, prone and aiming down the sight kick less. Only the camera's view moves
## (the player's own aim, as with any mouse movement); nothing is forced on the player by incoming fire.
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _recoil_def: WeaponDef


func _recoil() -> void:
	var def := sim.combat.weapon(unit.sec_id if unit.sec_active else unit.weapon_id)
	if def == null:
		return
	var k := Posture.steady(unit, sim.state.time) * (0.8 if Input.is_action_pressed("aim") else 1.0)
	if unit.posture == Posture.PRONE and sim.combat.settle_factor(unit, def) < 1.0:
		k *= 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([unit.id, unit.shot_counter, 31])
	var up := deg_to_rad(def.recoil_pitch_deg) * k * rng.randf_range(0.85, 1.1)
	var side := deg_to_rad(def.recoil_yaw_deg) * k * (def.recoil_yaw_bias + rng.randf_range(-1.0, 1.0))
	head.rotation.x = clampf(head.rotation.x + up, -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	rotate_y(-side)
	_recoil_pitch += up * def.recoil_recover
	_recoil_yaw += side * def.recoil_recover * 0.6
	_recoil_def = def
	if viewmodel:
		viewmodel.kick(def.viewmodel_kick * lerpf(1.0, k, 0.6))


## The recovering part of the kick, eased out each tick.
func _recoil_recover(delta: float) -> void:
	if _recoil_def == null or (absf(_recoil_pitch) < 1e-5 and absf(_recoil_yaw) < 1e-5):
		return
	var f := 1.0 - exp(-delta / maxf(_recoil_def.recoil_recover_s, 0.02))
	var dp := _recoil_pitch * f
	var dy := _recoil_yaw * f
	_recoil_pitch -= dp
	_recoil_yaw -= dy
	head.rotation.x = clampf(head.rotation.x - dp, -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	rotate_y(dy)


## COMBAT-01: the first-person eye follows the record's posture (Posture.eye_local), eased so a change reads as a movement.
func _player_eye(delta: float) -> void:
	if unit == null or sim == null:
		return
	var want := Posture.eye_local(unit, sim.state.time) + Vector3(0, 0.02, 0)
	var local := Vector3(want.x, want.y, -want.z)
	head.position = head.position.lerp(local, clampf(delta * 14.0, 0.0, 1.0))


## COMBAT-01: C crouch / stand, Z prone / crouch, sprint stands up. Prone needs room for the body (the AI's ground rule).
func _player_posture() -> void:
	var now := sim.state.time
	var cur := unit.posture
	if Input.is_action_just_pressed("crouch"):
		Posture.request(unit, Posture.STAND if cur == Posture.CROUCH else Posture.CROUCH, now)
	elif Input.is_action_just_pressed("prone"):
		if cur == Posture.PRONE:
			Posture.request(unit, Posture.CROUCH, now)
		elif sim.brain.prone_ground_ok(unit):
			Posture.request(unit, Posture.PRONE, now)
		else:
			posture_refused_at = now
	elif Input.is_action_pressed("sprint") and move_intent.length() > 0.1 and cur != Posture.STAND:
		Posture.request(unit, Posture.STAND, now)


## Last time a prone request was refused (no room / ground): the HUD says so briefly.
var posture_refused_at := -1.0e9


func _set_viewmodel(on: bool) -> void:
	if on and viewmodel == null and unit and unit.weapon_id != &"":
		viewmodel = Viewmodel.new()
		viewmodel.loadout = InfantryLoadout.by_id(unit.loadout if unit.loadout != "" else InfantryLoadout.default_for(unit.id, unit.faction))
		var sec := sim.combat.weapon(unit.sec_id) if unit.sec_active else null
		if sec and sec.held_scene():
			viewmodel.held_scene = sec.held_scene()
			viewmodel.held_piece = sec.held_piece
		viewmodel.faction = unit.faction
		camera.add_child(viewmodel)
		camera.near = 0.03
		_fov_hip = camera.fov
	elif not on and viewmodel:
		viewmodel.queue_free()
		viewmodel = null
		camera.fov = _fov_hip


## Where shots visibly leave this soldier: the first-person muzzle while possessed, else
## the muzzle of the carbine held by the character (the placeholder model's carbine
## when the character is disabled).
func muzzle_position() -> Vector3:
	if viewmodel and player_controlled:
		return viewmodel.muzzle.global_position
	var tip := character.muzzle() if character else null
	if tip:
		return tip.global_position
	return global_transform * Vector3(0.03, 1.22, -0.80)


static func ensure_combat_actions() -> void:
	var keys := {"reload": KEY_R, "fire_mode": KEY_V, "throw_grenade": KEY_G, "switch_weapon": KEY_X, "crouch": KEY_C, "prone": KEY_Z}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var mb := InputEventMouseButton.new()
			mb.button_index = buttons[action]
			InputMap.action_add_event(action, mb)
