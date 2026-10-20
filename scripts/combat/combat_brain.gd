## Autonomous soldier combat (COMBAT-01b): perception, target choice and firing.
##
## Works on UnitState records only - never on bodies, proxies or the camera - so a
## soldier fights the same way in the detailed and the abstract tier and nothing changes
## when it is promoted, demoted, saved or loaded. Every shot goes through
## CombatSim.request_fire(..., Source.AI): the same weapon, ammunition, reload, spread,
## damage and line-of-fire resolution as the player's rifle. The brain only decides
## when and where to pull the trigger; it never moves a soldier (squad and unit orders
## stay in charge of movement) and never touches the possessed soldier.
##
## Per soldier the state is small (UnitState.ai_state and the target fields):
##   IDLE / OBSERVING -> ENGAGING (visible enemy) -> LOST_TARGET (hidden, remembered for
##   target_memory_s) -> OBSERVING (looks at the last known position) -> IDLE;
##   RELOADING while a magazine change runs; DEAD; PLAYER while possessed.
##
## Cost: perception runs perception_hz times per second per soldier, staggered over the
## physics frames (round robin), with at most los_budget sight checks per frame across
## all soldiers. Candidates come from a coarse grid of living soldiers, nearest first,
## inside the field of view or the close-awareness radius. Firing decisions run every
## frame but cost nothing until a shot is due.
class_name CombatBrain
extends RefCounted

# --- Perception ------------------------------------------------------------------------
var enabled := true
## Perception updates per soldier per second.
var perception_hz := 3.0
## Farthest distance at which an enemy can be noticed (m).
var sight_range := 400.0
## Total field of view (degrees) around the direction the soldier looks.
var fov_deg := 150.0
## Enemies closer than this are noticed in any direction (hearing, peripheral).
var awareness_m := 25.0
## Sight checks for new candidates per soldier per update (the current target is extra).
var max_candidates := 3
## Sight checks per physics frame for all soldiers together; the rest wait a frame.
var los_budget := 24
## A hidden target is remembered (last known position) this long, then dropped (s).
var target_memory_s := 6.0
## A visible target is only replaced by one closer than this fraction of its distance.
var switch_ratio := 0.6
## After a target is lost, the soldier keeps looking at its last position this long (s).
var watch_after_lost_s := 8.0
## Enemy shots heard within this distance make a soldier look towards the shooter (m).
var hearing_m := 150.0
## Squad mates within this distance are told where a newly seen enemy is (m).
var contact_share_m := 120.0

# --- Engagement ------------------------------------------------------------------------
## Targets farther than this are tracked but not fired at (m).
var engage_range := 350.0
## Time from acquiring a target to the first shot: base + per 100 m (s).
var reaction_s := 0.45
var reaction_per_100m_s := 0.15
## Aim error (degrees, one standard deviation) on top of the weapon's spread: base,
## growth with distance, and a penalty while the shooter walks.
var aim_error_base_deg := 0.25
var aim_error_per_100m_deg := 0.20
var aim_error_moving_deg := 1.2
## The aim follows a moving target with this delay (s): a walking target is trailed.
var track_lag_s := 0.2
## Extra clearance kept around friends in the line of fire (m), for the weapon spread.
var friendly_margin_m := 0.5
## A partly emptied magazine is refilled when no enemy is in sight below this fraction.
var tactical_reload_fraction := 0.5

# --- Measurements ---------------------------------------------------------------------
var sight_checks := 0
var sight_usec := 0
var perception_updates := 0
var update_usec := 0
var update_usec_max := 0
var frames := 0
var ai_shots := 0
var friendly_holds := 0
var acquisitions := 0
var target_switches := 0
var dropped_targets := 0
var last_frame_checks := 0
var last_frame_usec := 0
## Recent decisions for the debug overlay / log: {t, unit, text}. Short ring buffer.
var events: Array[Dictionary] = []
var log_events := false

var sim: WorldSim
var _queue: PackedInt32Array = PackedInt32Array()
var _qi := 0
var _accum := 0.0
var _grid := {}
var _grid_frame := -1
const GRID := 64.0
const MAX_EVENTS := 200


func _init(p_sim: WorldSim) -> void:
	sim = p_sim


## Hearing and being hit turn a soldier towards the source (no position knowledge).
func connect_signals() -> void:
	sim.state.shot_fired.connect(_on_shot)
	sim.state.unit_damaged.connect(_on_damaged)
	sim.state.unit_died.connect(_on_died)


func reset_stats() -> void:
	sight_checks = 0
	sight_usec = 0
	perception_updates = 0
	update_usec = 0
	update_usec_max = 0
	frames = 0
	ai_shots = 0
	friendly_holds = 0
	acquisitions = 0
	target_switches = 0
	dropped_targets = 0


func update(delta: float) -> void:
	if not enabled:
		return
	var t0 := Time.get_ticks_usec()
	var checks0 := sight_checks
	if _queue.size() != _living_count() or Engine.get_physics_frames() % 120 == 0:
		_rebuild_queue()
	# Perception: each soldier perception_hz times per second, spread over the frames.
	_accum = minf(_accum + delta * perception_hz * _queue.size(), float(_queue.size()))
	var budget := los_budget
	while _accum >= 1.0 and budget > 0 and not _queue.is_empty():
		_accum -= 1.0
		_qi = _qi % _queue.size()
		var u := sim.state.get_unit(_queue[_qi])
		_qi += 1
		if u:
			budget -= _perceive(u, budget)
	# Engagement: every frame, cheap until a shot is due.
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.SOLDIER:
			_engage(u)
	last_frame_checks = sight_checks - checks0
	last_frame_usec = Time.get_ticks_usec() - t0
	update_usec += last_frame_usec
	update_usec_max = maxi(update_usec_max, last_frame_usec)
	frames += 1


# --- Perception ------------------------------------------------------------------------

## One perception update of one soldier. Returns the sight checks it used.
func _perceive(u: UnitState, budget: int) -> int:
	if not u.alive:
		u.ai_state = UnitState.AiState.DEAD
		return 0
	if u.player_controlled:
		return 0
	perception_updates += 1
	var now := sim.state.time
	var eye := CombatSim.eye_of(u)
	var used := 0
	var cur := sim.state.get_unit(u.target_id)
	if cur and (not cur.alive or cur.faction == u.faction):
		_drop_target(u, "target down")
		cur = null
	var cur_visible := false
	var cur_dist := INF
	if cur:
		cur_dist = _flat(u.position, cur.position)
		if cur_dist <= sight_range:
			var s := _see(eye, cur, u.target_aim_y)
			used += s.checks
			cur_visible = s.visible
			if cur_visible:
				u.target_aim_y = s.aim_y
	# Look for a (closer) enemy: always when the target is hidden or missing, otherwise
	# only among enemies clearly closer than the current one.
	var best: UnitState = null
	var best_aim := 1.0
	var tried := 0
	for c: UnitState in _enemies_near(u, sight_range):
		if used >= budget or tried >= max_candidates:
			break
		if c == cur:
			continue
		var d := _flat(u.position, c.position)
		if cur_visible and d >= cur_dist * switch_ratio:
			break  # sorted by distance: nobody closer enough follows
		if d > awareness_m and not _in_fov(u, c.position):
			continue
		tried += 1
		var s := _see(eye, c, 1.55)
		used += s.checks
		if s.visible:
			best = c
			best_aim = s.aim_y
			break
	if best:
		_acquire(u, best, best_aim)
	elif cur and cur_visible:
		u.target_seen_at = now
		u.target_last_pos = cur.position
		u.target_visible = true
	elif cur:
		u.target_visible = false
		if now - u.target_seen_at > target_memory_s:
			_drop_target(u, "lost contact")
	else:
		u.target_visible = false
	return used


## Sight from an eye to a soldier: first the height that was visible last time, then
## the other one (head 1.55 m / torso 1.1 m). {visible, aim_y, checks, blocker}
func _see(eye: Vector3, t: UnitState, first_y: float) -> Dictionary:
	var ys: Array[float] = [1.55, 1.1]
	if first_y <= 1.3:
		ys = [1.1, 1.55]
	var checks := 0
	var blocker := ""
	for y in ys:
		var t0 := Time.get_ticks_usec()
		var r := sim.combat.line.sight(eye, t.position + Vector3.UP * y)
		sight_usec += Time.get_ticks_usec() - t0
		sight_checks += 1
		checks += 1
		if r.visible:
			# Seen at the head: the torso may still be visible (better target).
			if y > 1.3:
				var t1 := Time.get_ticks_usec()
				var r2 := sim.combat.line.sight(eye, t.position + Vector3.UP * 1.1)
				sight_usec += Time.get_ticks_usec() - t1
				sight_checks += 1
				checks += 1
				return {"visible": true, "aim_y": 1.1 if r2.visible else 1.55, "checks": checks, "blocker": ""}
			return {"visible": true, "aim_y": y, "checks": checks, "blocker": ""}
		blocker = r.blocker
		if r.blocker == "terrain" and y > 1.3:
			break  # the head is under the horizon: the torso is too
	return {"visible": false, "aim_y": first_y, "checks": checks, "blocker": blocker}


func _acquire(u: UnitState, t: UnitState, aim_y: float) -> void:
	var now := sim.state.time
	if t.id != u.target_id:
		if u.target_id > 0:
			target_switches += 1
		acquisitions += 1
		u.target_id = t.id
		var d := _flat(u.position, t.position)
		u.aim_ready_at = now + reaction_s + reaction_per_100m_s * d / 100.0
		u.burst_left = 0
		_event(u, "sees %s at %.0f m" % [t.unit_name, d])
		_share_contact(u, t)
	u.target_aim_y = aim_y
	u.target_seen_at = now
	u.target_last_pos = t.position
	u.target_visible = true


func _drop_target(u: UnitState, why: String) -> void:
	if u.target_id < 0:
		return
	dropped_targets += 1
	_event(u, "drops target (%s)" % why)
	if u.target_last_pos.is_finite():
		_watch(u, u.target_last_pos, watch_after_lost_s)
	u.target_id = -1
	u.target_visible = false
	u.burst_left = 0


## Squad mates nearby turn towards a contact one of them reported (they still need to
## see it themselves before they shoot).
func _share_contact(u: UnitState, t: UnitState) -> void:
	var sq := sim.state.squad_of(u.id)
	if sq == null:
		return
	for id in sq.members:
		var m := sim.state.get_unit(id)
		if m and m != u and m.target_id < 0 and not m.player_controlled and _flat(m.position, u.position) <= contact_share_m:
			_watch(m, t.position, 6.0)


func _watch(u: UnitState, at: Vector3, seconds: float) -> void:
	var d := Vector3(at.x - u.position.x, 0.0, at.z - u.position.z)
	if d.length() < 0.5:
		return
	u.watch_yaw = atan2(-d.x, -d.z)
	u.watch_until = sim.state.time + seconds


func _on_shot(shot: Dictionary) -> void:
	if not enabled:
		return
	var s := sim.state.get_unit(shot.shooter)
	if s == null:
		return
	var origin: Vector3 = shot.origin
	_ensure_grid()
	for u: UnitState in _near(origin, hearing_m):
		if u.faction != s.faction and u.target_id < 0 and not u.player_controlled and u.watch_until < sim.state.time:
			_watch(u, origin, 5.0)


## A soldier died: everyone tracking it lets go at once (not at their next update).
func _on_died(t: UnitState) -> void:
	for u: UnitState in sim.state.units.values():
		if u.target_id == t.id:
			_drop_target(u, "target down")


func _on_damaged(t: UnitState, _amount: float, _zone: int, source_id: int) -> void:
	var s := sim.state.get_unit(source_id)
	if not enabled or s == null or not t.alive or t.player_controlled:
		return
	if t.target_id < 0 or not t.target_visible:
		_watch(t, s.position, 5.0)


## Living enemy soldiers within r, nearest first (coarse grid, no global scan).
func _enemies_near(u: UnitState, r: float) -> Array:
	_ensure_grid()
	var out := []
	for c: UnitState in _near(u.position, r):
		if c.faction != u.faction:
			out.append(c)
	var p := u.position
	out.sort_custom(func(a: UnitState, b: UnitState) -> bool: return _flat(a.position, p) < _flat(b.position, p))
	return out


func _near(p: Vector3, r: float) -> Array:
	var out := []
	var c0 := Vector2i(floori((p.x - r) / GRID), floori((p.z - r) / GRID))
	var c1 := Vector2i(floori((p.x + r) / GRID), floori((p.z + r) / GRID))
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			for u: UnitState in _grid.get(Vector2i(x, z), []):
				if _flat(u.position, p) <= r:
					out.append(u)
	return out


func _ensure_grid() -> void:
	var f := Engine.get_physics_frames()
	if f == _grid_frame:
		return
	_grid_frame = f
	_grid.clear()
	for u: UnitState in sim.state.units.values():
		if u.alive and u.kind == UnitState.Kind.SOLDIER:
			var k := Vector2i(floori(u.position.x / GRID), floori(u.position.z / GRID))
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(u)


## Where the soldier is looking: at its target, else where it was told / heard to look,
## else straight ahead.
func look_yaw(u: UnitState) -> float:
	if u.target_id > 0 and u.target_last_pos.is_finite():
		var d := u.target_last_pos - u.position
		if Vector2(d.x, d.z).length() > 0.5:
			return atan2(-d.x, -d.z)
	if not is_nan(u.watch_yaw) and u.watch_until >= sim.state.time:
		return u.watch_yaw
	return u.yaw


func _in_fov(u: UnitState, p: Vector3) -> bool:
	var d := Vector3(p.x - u.position.x, 0.0, p.z - u.position.z)
	var yaw := atan2(-d.x, -d.z)
	return absf(angle_difference(look_yaw(u), yaw)) <= deg_to_rad(fov_deg * 0.5)


func _rebuild_queue() -> void:
	_queue.clear()
	for u: UnitState in sim.state.all_units():
		if u.alive and u.kind == UnitState.Kind.SOLDIER:
			_queue.append(u.id)
	_qi = _qi % maxi(_queue.size(), 1)


func _living_count() -> int:
	var n := 0
	for u: UnitState in sim.state.units.values():
		if u.alive and u.kind == UnitState.Kind.SOLDIER:
			n += 1
	return n


# --- Engagement ----------------------------------------------------------------------

func _engage(u: UnitState) -> void:
	if not u.alive:
		u.ai_state = UnitState.AiState.DEAD
		u.ai_reason = "dead"
		return
	if u.player_controlled:
		u.ai_state = UnitState.AiState.PLAYER
		u.ai_reason = "player in control"
		return
	var now := sim.state.time
	var def := sim.combat.weapon(u.weapon_id)
	var t := sim.state.get_unit(u.target_id)
	if t and not t.alive:
		_drop_target(u, "target down")
		t = null
	# Facing: towards the target (or its last position), else the watch direction.
	if t:
		_watch(u, t.position if u.target_visible else u.target_last_pos, 1.0)
	elif u.watch_until < now:
		u.watch_yaw = NAN
	if def == null:
		u.ai_state = UnitState.AiState.IDLE
		u.ai_reason = "unarmed"
		return
	if u.is_reloading():
		u.ai_state = UnitState.AiState.RELOADING
		u.ai_reason = "reloading"
		return
	if t == null:
		u.ai_state = UnitState.AiState.OBSERVING if u.watch_until >= now else UnitState.AiState.IDLE
		u.ai_reason = "no target"
		if u.mag < def.magazine_size * tactical_reload_fraction and u.reserve > 0:
			sim.combat.request_reload(u.id)
		return
	if not u.target_visible:
		u.ai_state = UnitState.AiState.LOST_TARGET
		u.ai_reason = "target hidden"
		return
	var sq := sim.state.squad_of(u.id)
	if sq and sq.roe == SquadState.Roe.HOLD_FIRE:
		u.ai_state = UnitState.AiState.OBSERVING
		u.ai_reason = "hold fire"
		u.burst_left = 0
		return
	u.ai_state = UnitState.AiState.ENGAGING
	var dist := _flat(u.position, t.position)
	if dist > engage_range:
		u.ai_reason = "out of range"
		return
	if now < u.aim_ready_at:
		u.ai_reason = "aiming"
		return
	if u.mag <= 0 and u.reserve <= 0:
		u.ai_reason = "no ammunition"
		return
	if now < u.next_shot_at:
		return
	if u.burst_left <= 0:
		if now < u.next_burst_at:
			u.ai_reason = "between bursts"
			return
		u.burst_left = _burst_size(u, dist)
	var origin := CombatSim.eye_of(u)
	var aim := t.position + Vector3.UP * u.target_aim_y - Vector3(t.velocity.x, 0.0, t.velocity.z) * track_lag_s
	var dir := _aim_error(u, (aim - origin).normalized(), dist)
	if _friendly_near_line(u, origin, aim):
		# The shot preview (same world data and hit shapes as the real shot, without the
		# weapon's spread) and a 0.5 m margin around friends for that spread.
		var p := sim.combat.preview_shot(u.id, origin, dir, u.shot_counter + 1, 0.0)
		var hit := sim.state.get_unit(p.get("hit_unit", -1))
		if (hit and hit.faction == u.faction) or _friend_on_ray(u, origin, dir, minf(dist, p.get("distance", dist))):
			friendly_holds += 1
			u.ai_reason = "friendly in line of fire"
			u.burst_left = 0
			u.next_burst_at = now + 0.4
			return
	var shot := sim.combat.request_fire(u.id, origin, dir, CombatSim.Source.AI)
	if shot.get("fired", false):
		ai_shots += 1
		u.ai_reason = ""
		u.burst_left -= 1
		if u.burst_left <= 0:
			u.next_burst_at = now + _burst_pause(u, dist)
	else:
		u.ai_reason = shot.get("reason", "")
		u.burst_left = 0


## Bursts: long at close range, short at medium range, single aimed shots far away.
func _burst_size(u: UnitState, dist: float) -> int:
	var r := _rand(u, 11)
	if dist < 40.0:
		return 4 + int(r * 3.0)
	if dist < 120.0:
		return 2 + int(r * 3.0)
	if dist < 250.0:
		return 1 + int(r * 2.0)
	return 1


func _burst_pause(u: UnitState, dist: float) -> float:
	return 0.25 + dist / 250.0 + _rand(u, 13) * 0.35


## The direction the soldier actually holds: the ideal one plus a seeded aim error that
## grows with distance and while walking (the weapon's spread is added by CombatSim).
func _aim_error(u: UnitState, dir: Vector3, dist: float) -> Vector3:
	var speed := Vector2(u.velocity.x, u.velocity.z).length()
	var sigma := aim_error_base_deg + aim_error_per_100m_deg * dist / 100.0 + aim_error_moving_deg * clampf(speed / 4.5, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.state.world_seed, u.id, u.shot_counter + 1, 977])
	var ex := deg_to_rad(rng.randfn(0.0, sigma))
	var ey := deg_to_rad(rng.randfn(0.0, sigma))
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		return dir
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir + side * tan(ex) + up * tan(ey)).normalized()


## Cheap pre-check before the shot preview: a living friend close to the line in front.
func _friendly_near_line(u: UnitState, origin: Vector3, aim: Vector3) -> bool:
	_ensure_grid()
	var a := Vector2(origin.x, origin.z)
	var b := Vector2(aim.x, aim.z)
	var mid := (origin + aim) * 0.5
	for f: UnitState in _near(mid, a.distance_to(b) * 0.5 + 2.0):
		if f == u or f.faction != u.faction:
			continue
		if LineOfFire._point_segment_dist2d(Vector2(f.position.x, f.position.z), a, b) < 1.5:
			return true
	return false


## A living friend whose body axis passes within friendly_margin_m of the ray before
## max_d (the spread can still carry a shot that the preview passed by a hair).
func _friend_on_ray(u: UnitState, origin: Vector3, dir: Vector3, max_d: float) -> bool:
	for f: UnitState in _near(origin + dir * max_d * 0.5, max_d * 0.5 + 2.0):
		if f == u or f.faction != u.faction:
			continue
		var a := f.position + Vector3.UP * 0.2
		var b := f.position + Vector3.UP * 1.7
		var pts := Geometry3D.get_closest_points_between_segments(origin, origin + dir * max_d, a, b)
		if pts[0].distance_to(pts[1]) < friendly_margin_m + LineOfFire.TORSO_R:
			return true
	return false


func _rand(u: UnitState, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.state.world_seed, u.id, u.shot_counter, salt])
	return rng.randf()


func _event(u: UnitState, text: String) -> void:
	var e := {"t": snappedf(sim.state.time, 0.01), "unit": u.unit_name, "text": text}
	events.append(e)
	if events.size() > MAX_EVENTS:
		events.pop_front()
	if log_events:
		print("BRAIN %.2f %s %s" % [e.t, u.unit_name, text])


## Summary for the HUD and tests.
func summary() -> Dictionary:
	var states := {}
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.SOLDIER:
			var k := u.ai_state_name()
			states[k] = states.get(k, 0) + 1
	return {"states": states, "sight_checks": sight_checks, "ai_shots": ai_shots, "acquisitions": acquisitions,
		"switches": target_switches, "dropped": dropped_targets, "friendly_holds": friendly_holds,
		"update_us_avg": snappedf(float(update_usec) / maxi(frames, 1), 0.1), "update_us_max": update_usec_max,
		"sight_us_avg": snappedf(float(sight_usec) / maxi(sight_checks, 1), 0.1),
		"sight_checks_per_frame": snappedf(float(sight_checks) / maxi(frames, 1), 0.01)}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
