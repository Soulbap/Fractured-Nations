## Scripted checks of COMBAT-01b (AI perception and autonomous engagement) on the
## reference world.
##
##   Godot.exe --path . --resolution 1600x900 --log-file ai.log res://scenes/game/world_ref_20km.tscn -- --combat-ai-test [--shots]
##
## Every scenario spawns fresh squads (WorldState.add_unit / add_squad, rifles from
## CombatSim.equip_all) far from the default soldiers, lets the real game run them -
## DetailManager bodies, SquadControl orders, CombatBrain, CombatSim - and removes them
## again. Squads are 8 soldiers unless noted. Where a scenario must keep a fight going
## for a measurement window, the soldiers' health is raised (stated in the log); weapon,
## ammunition and accuracy are never changed. Prints "AI <check> <json>", writes
## res://benchmarks/raw/combat_ai_test.json and (with --shots) docs/combat01b/c01b_*.jpg.
class_name CombatAISelfTest
extends CombatSelfTest

var brain: CombatBrain
## Every shot of the current scenario: {shooter, counter, faction, hit, damage, killed,
## blocker, zone, end, origin, t, speed, possessed}.
var shot_log: Array[Dictionary] = []
var dmg_events := 0
var dmg_on_dead := 0
var reloads := 0
var dead_shots := 0
var ammo_violations := []
var stale_targets := 0
## Units spawned by the test (removed after each scenario).
var spawned_ids: Array[int] = []
var default_soldiers: Array[Vector3] = []
var _last_shot_frame := -1


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat01b"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	brain = demo.sim.brain
	brain.enabled = true
	SoldierBody.require_mouse_capture = false
	def = combat.weapon(&"rifle")
	tree.create_timer(1700.0).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish in 1700 s")
		_finish())
	var state := demo.sim.state
	state.shot_fired.connect(_on_shot_rec)
	state.unit_damaged.connect(func(t: UnitState, _a: float, _z: int, _s: int) -> void:
		dmg_events += 1
		if not t.alive:
			dmg_on_dead += 1)
	state.reload_started.connect(func(u: UnitState) -> void:
		if spawned_ids.has(u.id):
			reloads += 1)
	state.unit_died.connect(func(u: UnitState) -> void:
		deaths.append({"id": u.id, "name": u.unit_name, "killer": u.killer_id, "t": snappedf(state.time, 0.01)}))
	await _physics(60)
	_load_world_data()
	for u in state.soldiers():
		default_soldiers.append(u.position)
	_press(KEY_TAB)
	await _physics(3)
	# The UNIT-01A / COMBAT-01a meadow (about 6 km from site A) when it is clear of the
	# default soldiers, else the nearest other one that is.
	area = _find_spot("meadow", demo.sites[0].position)
	if not area.is_finite() or not _far_from_soldiers(area, 1000.0):
		area = _find_far("meadow", demo.sites[0].position, 1000.0)
	_expect(area.is_finite(), "no open meadow far from the default soldiers")
	if not area.is_finite():
		_finish()
		return
	demo.rts_camera.frame(area, 0.0, 90.0)
	await _seconds(3.0)
	_log("startup", {"area": _describe(area), "brain": {"perception_hz": brain.perception_hz, "sight_range": brain.sight_range,
		"fov_deg": brain.fov_deg, "awareness_m": brain.awareness_m, "los_budget": brain.los_budget, "target_memory_s": brain.target_memory_s,
		"engage_range": brain.engage_range, "aim_error_deg": [brain.aim_error_base_deg, brain.aim_error_per_100m_deg, brain.aim_error_moving_deg],
		"foliage": [lof.foliage_m, lof.foliage_skip_m, lof.foliage_block]}, "default_soldiers": default_soldiers.size()})

	_log("open_firefight", await _open_fight())
	_log("symmetry", await _symmetry())
	_log("target_stability", await _stability())
	_log("reload_and_ammo", await _ammo_ai())
	_log("hold_fire", await _hold_fire())
	_log("terrain", await _terrain())
	_log("structures", await _structures())
	_log("forest", await _forest())
	_log("friendly_in_line", await _friendly_line())
	_log("orders_and_possession", await _orders_possession())
	_log("save_load", await _save_load_ai())
	_log("tiers", await _tiers())
	_log("performance", await _perf_ai())
	_finish()


# --- Bookkeeping ------------------------------------------------------------------------

func _on_shot_rec(shot: Dictionary) -> void:
	var u := _u(shot.shooter)
	if u == null:
		return
	if not u.alive:
		dead_shots += 1
	_last_shot_frame = Engine.get_process_frames()
	if not spawned_ids.has(u.id):
		return
	var tgt := _u(u.target_id)
	shot_log.append({"target_d": _flat(u.position, tgt.position) if tgt else -1.0, "dist": shot.distance,
		"shooter": u.id, "counter": shot.counter, "faction": u.faction, "hit": shot.hit_unit, "damage": shot.damage,
		"killed": shot.killed, "blocker": shot.blocker, "zone": shot.zone, "end": shot.end, "origin": shot.origin,
		"t": demo.sim.state.time, "speed": Vector2(u.velocity.x, u.velocity.z).length(), "possessed": u.player_controlled,
		"has_body": u.has_body})


func _begin() -> void:
	shot_log.clear()
	dmg_events = 0
	reloads = 0
	brain.reset_stats()


## Per frame invariants while a scenario runs: ammunition limits, and no living soldier
## still holding a dead target after its update.
func _invariants() -> void:
	for id in spawned_ids:
		var u := _u(id)
		if u == null:
			continue
		if u.mag < 0 or u.mag > def.magazine_size or u.reserve < 0:
			ammo_violations.append({"unit": u.unit_name, "mag": u.mag, "reserve": u.reserve})
		var t := _u(u.target_id)
		if u.alive and t and not t.alive:
			stale_targets += 1


func _run_for(seconds: float, until := Callable()) -> float:
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < seconds:
		await tree.physics_frame
		_invariants()
		if until.is_valid() and until.call():
			break
	return demo.sim.state.time - t0


func _squad(sq_name: String, faction: int, n: int, center: Vector3, yaw: float, rows := 1, spacing := 3.0) -> SquadState:
	var state := demo.sim.state
	var ids := []
	var right := SquadControl._right(yaw)
	var back := -SquadControl._forward(yaw)
	var per_row := ceili(float(n) / rows)
	for i in n:
		var col := i % per_row
		var row := i / per_row
		var p := center + right * ((col - (per_row - 1) * 0.5) * spacing) + back * (row * spacing)
		var u := state.add_unit(UnitState.Kind.SOLDIER, faction, demo.on_ground(p.x, p.z, 0.3), yaw, "%s-%d" % [sq_name, i + 1])
		ids.append(u.id)
		spawned_ids.append(u.id)
	var sq := state.add_squad(sq_name, faction, ids)
	combat.equip_all(&"rifle")
	demo.detail.create_missing_proxies()
	return sq


func _clear() -> void:
	for id in spawned_ids.duplicate():
		demo.sim.state.remove_unit(id)
	spawned_ids.clear()
	await _physics(5)


func _sq(sq_name: String) -> SquadState:
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.squad_name == sq_name:
			return sq
	return null


func _ids(sq: SquadState) -> Array:
	return Array(sq.members) + Array(sq.fallen) if sq else []


func _tough(sq: SquadState, hp: float) -> void:
	for id in sq.members:
		_u(id).max_health = hp
		_u(id).health = hp


func _alive(sq: SquadState) -> int:
	return sq.members.size() if sq and demo.sim.state.get_squad(sq.id) == sq else 0


func _shots_of(faction: int, since := -1.0) -> int:
	var n := 0
	for s in shot_log:
		if s.faction == faction and s.t >= since:
			n += 1
	return n


func _shots_by(ids: Array, since := -1.0) -> int:
	var n := 0
	for s in shot_log:
		if ids.has(s.shooter) and s.t >= since:
			n += 1
	return n


func _seeing(ids: Array) -> int:
	var n := 0
	for id in ids:
		var u := _u(id)
		if u and u.alive and u.target_id > 0 and u.target_visible:
			n += 1
	return n


## Tactical camera on p with the action in the upper half of the screen (the HUD text
## covers the lower part).
func _frame_action(p: Vector3, yaw: float, zoom: float) -> void:
	demo.rts_camera.frame(p - SquadControl._forward(yaw) * zoom * 0.25, yaw, zoom)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


## Screenshot right after a shot left a rifle (tracers visible), within max_s.
func _snap_firing(shot_name: String, max_s := 3.0) -> void:
	if not shots:
		return
	var t0 := Time.get_ticks_msec()
	var f0 := _last_shot_frame
	while Time.get_ticks_msec() - t0 < max_s * 1000.0 and _last_shot_frame == f0:
		await tree.process_frame
	await tree.process_frame
	_shot(shot_name)


func _find_far(kind: String, center: Vector3, min_r: float) -> Vector3:
	for r: float in [0.0, 300.0, 600.0, 900.0, 1300.0, 1800.0, 2400.0, 3000.0, 3800.0, 4500.0, 5200.0, 6000.0, 7000.0]:
		var n := 1 if r == 0.0 else clampi(int(r / 40.0), 12, 160)
		for k in n:
			var a := k * TAU / n
			var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			if absf(p.x) > 9300.0 or absf(p.z) > 9300.0 or not _far_from_soldiers(p, min_r):
				continue
			if _matches(kind, p):
				return p
	return Vector3.INF


func _far_from_soldiers(p: Vector3, r: float) -> bool:
	for q in default_soldiers:
		if Vector2(q.x - p.x, q.z - p.z).length() < r:
			return false
	return true


## Shots, hits, deaths, consistency of one scenario (shared by several checks).
func _combat_stats(sides: Array) -> Dictionary:
	var hits := 0
	var damaging := 0
	var blockers := {}
	var counters := {}
	var dup := 0
	var gaps := 0
	var rate_violations := 0
	var last_t := {}
	for s in shot_log:
		if s.hit > 0:
			hits += 1
		if s.damage > 0.0:
			damaging += 1
		blockers[s.blocker] = blockers.get(s.blocker, 0) + 1
		var prev: int = counters.get(s.shooter, -1)
		if prev >= 0 and s.counter <= prev:
			dup += 1
		elif prev >= 0 and s.counter != prev + 1:
			gaps += 1
		counters[s.shooter] = s.counter
		if last_t.has(s.shooter) and s.t - last_t[s.shooter] < def.fire_interval() - 0.0005:
			rate_violations += 1
		last_t[s.shooter] = s.t
	var per_side := []
	for sq: SquadState in sides:
		var ids := _ids(sq)
		var side_hits := 0
		var short := 0
		var long := 0
		var ground := 0.0
		for id in ids:
			ground += _u(id).position.y if _u(id) else 0.0
		for sh in shot_log:
			if not ids.has(sh.shooter):
				continue
			if sh.hit > 0:
				side_hits += 1
			elif sh.target_d > 0.0 and sh.dist < sh.target_d - 1.0:
				short += 1
			elif sh.target_d > 0.0:
				long += 1
		per_side.append({"squad": sq.squad_name if sq else "?", "shots": _shots_by(ids), "hits": side_hits, "misses_short": short, "misses_long": long,
			"alive": sq.members.size() if sq else 0, "fallen": sq.fallen.size() if sq else 0, "mean_ground_y": snappedf(ground / maxi(ids.size(), 1), 0.01)})
	return {"sides": per_side, "shots": shot_log.size(), "hits": hits, "hit_ratio": snappedf(float(hits) / maxi(shot_log.size(), 1), 0.001),
		"damage_events": dmg_events, "damaging_shots": damaging, "blockers": blockers, "duplicate_counters": dup, "counter_gaps": gaps,
		"rate_violations": rate_violations, "reloads": reloads, "brain": brain.summary()}


# --- 1. open terrain firefight ------------------------------------------------------------

func _open_fight() -> Dictionary:
	_begin()
	var c := area
	demo.rts_camera.frame(c, 0.0, 110.0)
	await _seconds(1.5)
	_begin()
	var n := _squad("North-1", 0, 8, c + Vector3(0, 0, 60), 0.0)
	var s := _squad("South-1", 1, 8, c + Vector3(0, 0, -60), PI)
	var t0 := demo.sim.state.time
	var first := {"north_sees": -1.0, "south_sees": -1.0, "north_fires": -1.0, "south_fires": -1.0}
	var snapped := false
	var dead_frames := 0
	var bodies := 0
	while demo.sim.state.time - t0 < 90.0:
		await tree.physics_frame
		_invariants()
		var now := demo.sim.state.time - t0
		if first.north_sees < 0.0 and _seeing(_ids(n)) > 0:
			first.north_sees = now
		if first.south_sees < 0.0 and _seeing(_ids(s)) > 0:
			first.south_sees = now
		if first.north_fires < 0.0 and _shots_by(_ids(n)) > 0:
			first.north_fires = now
		if first.south_fires < 0.0 and _shots_by(_ids(s)) > 0:
			first.south_fires = now
		bodies = maxi(bodies, demo.sim.bodies.size())
		if not snapped and first.south_fires > 0.0 and now > first.south_fires + 2.0 and shots:
			snapped = true
			_frame_action(c, PI * 0.5, 90.0)
			await _snap_firing("open_exchange_fire")
			demo.hud.combat_debug = true
			_frame_action(c, PI * 0.5, 110.0)
			await _snap_firing("open_debug_overlay")
			demo.hud.combat_debug = false
		if n.members.is_empty() or s.members.is_empty():
			dead_frames += 1
			if dead_frames > 30:
				break
	var out := _combat_stats([n, s])
	out["first_seconds"] = first
	out["duration_s"] = snappedf(demo.sim.state.time - t0, 0.1)
	out["max_bodies"] = bodies
	out["shots_by_dead"] = dead_shots
	out["damage_on_dead"] = dmg_on_dead
	out["stale_dead_targets"] = stale_targets
	out["ammo_violations"] = ammo_violations.slice(0, 5)
	var unique := {}
	for d in deaths:
		unique[d.id] = unique.get(d.id, 0) + 1
	var twice := unique.values().filter(func(k: int) -> bool: return k > 1).size()
	out["deaths_reported_twice"] = twice
	var members_dead := 0
	for sq: SquadState in [n, s]:
		for id in sq.members:
			if not _u(id).alive:
				members_dead += 1
	out["dead_still_in_squads"] = members_dead
	_expect(first.north_sees >= 0.0 and first.south_sees >= 0.0 and first.north_sees < 5.0 and first.south_sees < 5.0,
		"open terrain: squads did not detect each other within 5 s (%s)" % JSON.stringify(first))
	_expect(first.north_fires >= 0.0 and first.south_fires >= 0.0, "open terrain: a squad never fired (%s)" % JSON.stringify(first))
	_expect(out.hits > 0 and out.hit_ratio < 0.95 and (n.fallen.size() + s.fallen.size()) > 0, "open terrain: no hits / casualties, or perfect accuracy (%s)" % JSON.stringify(out))
	_expect(out.damage_events == out.damaging_shots and dmg_on_dead == 0 and dead_shots == 0 and twice == 0 and members_dead == 0,
		"death / damage bookkeeping inconsistent (%s)" % JSON.stringify(out))
	_expect(out.duplicate_counters == 0 and out.counter_gaps == 0 and out.rate_violations == 0 and ammo_violations.is_empty(),
		"open terrain: duplicate shots, rate or ammunition violations (%s)" % JSON.stringify(out))
	_expect(stale_targets == 0, "living soldiers kept dead targets (%d frames)" % stale_targets)
	await _clear()
	return out


## One fight decides little (the first casualties snowball). Four short 8 v 8 fights with
## other spread seeds, the factions swapping sides each time: a systematic bias would
## make one faction or one side win every time.
func _symmetry() -> Dictionary:
	var rounds := []
	var seed0 := demo.sim.state.world_seed
	for k in 4:
		_begin()
		demo.sim.state.world_seed = 100 + k
		var swap := k % 2 == 1
		var a := _squad("SymA%d" % k, 1 if swap else 0, 8, area + Vector3(0, 0, 60), 0.0)
		var b := _squad("SymB%d" % k, 0 if swap else 1, 8, area + Vector3(0, 0, -60), PI)
		await _run_for(40.0, func() -> bool: return a.members.is_empty() or b.members.is_empty())
		var hits := {0: 0, 1: 0}
		var shots_f := {0: 0, 1: 0}
		for sh in shot_log:
			shots_f[sh.faction] += 1
			if sh.hit > 0:
				hits[sh.faction] += 1
		var alive := {a.faction: a.members.size(), b.faction: b.members.size()}
		rounds.append({"seed": 100 + k, "north_side_faction": a.faction, "alive_f0": alive[0], "alive_f1": alive[1],
			"winner_faction": 0 if alive[0] > alive[1] else (1 if alive[1] > alive[0] else -1), "winner_side": "z+" if a.members.size() > b.members.size() else ("z-" if b.members.size() > a.members.size() else "-"),
			"hits_f0": hits[0], "hits_f1": hits[1], "shots_f0": shots_f[0], "shots_f1": shots_f[1]})
		await _clear()
	demo.sim.state.world_seed = seed0
	var by_faction := rounds.map(func(r: Dictionary) -> int: return r.winner_faction)
	var by_side := rounds.map(func(r: Dictionary) -> String: return r.winner_side)
	var out := {"rounds": rounds, "winners_by_faction": by_faction, "winners_by_side": by_side}
	_expect(rounds.all(func(r: Dictionary) -> bool: return r.hits_f0 > 0 and r.hits_f1 > 0), "a faction never hit in a symmetric fight (%s)" % JSON.stringify(rounds))
	return out


# --- 4. target stability and memory --------------------------------------------------------

func _stability() -> Dictionary:
	_begin()
	var c := area
	var w := _squad("Watch", 0, 1, c + Vector3(0, 0, 50), 0.0)
	var e := _squad("Pair", 1, 2, c + Vector3(0, 0, -50), PI, 1, 10.0)
	demo.sim.squads.set_roe([w.id, e.id], SquadState.Roe.HOLD_FIRE)
	demo.rts_camera.frame(c, 0.0, 100.0)
	await _seconds(1.0)
	var wid: int = w.members[0]
	var seen := []
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 15.0:
		await tree.physics_frame
		var tid := _u(wid).target_id
		if seen.is_empty() or seen[-1] != tid:
			seen.append(tid)
	var two_equal := {"targets_over_15s": seen, "switches": brain.target_switches, "acquisitions": brain.acquisitions}
	# A much closer enemy appears: switching to it is right.
	var near := _squad("Close", 1, 1, c + Vector3(6, 0, 25), PI)
	demo.sim.squads.set_roe([near.id], SquadState.Roe.HOLD_FIRE)
	await _run_for(3.0)
	var switched_to_close := _u(wid).target_id == near.members[0]
	# Every enemy disappears (800 m away): the target is remembered, then dropped; the
	# soldier looks at the last position and does not walk after it.
	var pos0 := _u(wid).position
	for sq: SquadState in [e, near]:
		for id in sq.members:
			_put(id, demo.on_ground(c.x + 800.0, c.z + 800.0 + id, 0.3), 0.0)
	var lost_at := demo.sim.state.time
	var states := []
	var dropped_after := -1.0
	while demo.sim.state.time - lost_at < 12.0:
		await tree.physics_frame
		var u := _u(wid)
		var st := u.ai_state_name()
		if states.is_empty() or states[-1] != st:
			states.append(st)
		if dropped_after < 0.0 and u.target_id < 0:
			dropped_after = demo.sim.state.time - lost_at
	var out := {"two_equal_targets": two_equal, "closer_enemy_switch": switched_to_close, "after_contact_lost": {"states": states,
		"dropped_after_s": snappedf(dropped_after, 0.01), "memory_s": brain.target_memory_s, "moved_m": snappedf(_flat(pos0, _u(wid).position), 0.01),
		"has_order": _u(wid).has_order()}}
	# One target for the whole window (it may already have been taken during the setup second).
	_expect(seen.filter(func(t: int) -> bool: return t > 0).size() == 1 and seen[-1] > 0 and two_equal.switches == 0,
		"the soldier switched between equally valid targets (%s)" % JSON.stringify(two_equal))
	_expect(switched_to_close, "the soldier did not take the much closer enemy")
	_expect(states.has("lost target") and dropped_after > brain.target_memory_s - 0.5 and dropped_after < brain.target_memory_s + 1.0
		and _flat(pos0, _u(wid).position) < 0.5 and not _u(wid).has_order(), "target memory / no pursuit failed (%s)" % JSON.stringify(out.after_contact_lost))
	await _clear()
	return out


# --- 7. reload and ammunition limits ----------------------------------------------------

func _ammo_ai() -> Dictionary:
	_begin()
	var c := area
	var sh := _squad("Rifle", 0, 1, c + Vector3(0, 0, 40), 0.0)
	var tg := _squad("Dummy", 1, 1, c + Vector3(0, 0, -40), PI)
	demo.sim.squads.set_roe([tg.id], SquadState.Roe.HOLD_FIRE)
	_tough(tg, 100000.0)
	var id: int = sh.members[0]
	var u := _u(id)
	u.mag = 3
	u.reserve = 32
	demo.rts_camera.frame(c, 0.0, 90.0)
	var seen_reloading := false
	var shots_while_reloading := 0
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 30.0:
		var n0 := shot_log.size()
		var was_reloading := u.is_reloading()
		await tree.physics_frame
		_invariants()
		if u.ai_state == UnitState.AiState.RELOADING:
			seen_reloading = true
		if was_reloading and u.is_reloading() and shot_log.size() > n0:
			shots_while_reloading += 1
		if u.mag == 0 and u.reserve == 0 and not u.is_reloading() and demo.sim.state.time - t0 > 3.0:
			await _run_for(2.0)
			break
	var fired := _shots_by([id])
	var out := {"start": {"mag": 3, "reserve": 32}, "shots": fired, "reloads": reloads, "seen_reloading_state": seen_reloading,
		"shots_during_reload": shots_while_reloading, "end": {"mag": u.mag, "reserve": u.reserve, "reason": u.ai_reason}, "stats": _combat_stats([sh, tg])}
	_expect(fired == 35 and reloads == 2 and seen_reloading and shots_while_reloading == 0 and u.mag == 0 and u.reserve == 0 and u.ai_reason == "no ammunition"
		and out.stats.rate_violations == 0, "AI reload / ammunition limits wrong (%s)" % JSON.stringify(out))
	await _clear()
	return out


# --- 5. / 6. hold fire and weapons free ----------------------------------------------------

func _hold_fire() -> Dictionary:
	_begin()
	var c := area
	var n := _squad("North-H", 0, 8, c + Vector3(0, 0, 60), 0.0)
	var s := _squad("South-H", 1, 8, c + Vector3(0, 0, -60), PI)
	demo.sim.squads.set_roe([n.id, s.id], SquadState.Roe.HOLD_FIRE)
	_tough(n, 1000.0)
	_tough(s, 1000.0)
	demo.rts_camera.frame(c, 0.0, 120.0)
	await _seconds(0.5)
	_begin()
	await _run_for(8.0)
	var held := {"north_seeing": _seeing(_ids(n)), "south_seeing": _seeing(_ids(s)), "shots": shot_log.size()}
	# Weapons free for North through the tactical view: Ctrl+click a North soldier, Y.
	var cam := demo.rts_camera.camera
	var nu := _u(n.members[3])
	demo.rts_camera.frame(nu.position, 0.0, 45.0)
	await _frames(3)
	_click_mod(MOUSE_BUTTON_LEFT, cam.unproject_position(nu.position + Vector3.UP), true, false)
	await _frames(3)
	if shots:
		_frame_action(c, PI * 0.5, 110.0)
		await _seconds(0.6)
		_shot("rts_hold_fire_selected")
	_press(KEY_Y)
	await _frames(2)
	var roe_after_y := n.roe
	var t_free := demo.sim.state.time
	await _run_for(5.0, func() -> bool: return _shots_by(_ids(n), t_free) > 0)
	var first_shot_s := demo.sim.state.time - t_free
	await _run_for(2.0)
	if shots:
		_frame_action(c, PI * 0.5, 110.0)
		await _snap_firing("rts_squad_combat_status")
	var free := {"north_shots": _shots_by(_ids(n), t_free), "south_shots": _shots_by(_ids(s)), "first_shot_after_s": snappedf(first_shot_s, 0.01),
		"roe_after_key": n.roe_name(), "panel_row": demo.hud.squad_panel.row_text(n)}
	# Y again: hold fire; at most the shot in flight this tick.
	_press(KEY_Y)
	await _frames(2)
	var t_hold := demo.sim.state.time
	await _run_for(4.0)
	var again := {"roe": n.roe_name(), "north_shots_after": _shots_by(_ids(n), t_hold + 0.05)}
	var out := {"hold_fire_8s": held, "weapons_free": free, "hold_again": again}
	_expect(held.north_seeing > 0 and held.south_seeing > 0 and held.shots == 0, "Hold Fire: no detection or shots were fired (%s)" % JSON.stringify(held))
	_expect(roe_after_y == SquadState.Roe.WEAPONS_FREE and free.north_shots > 0 and free.south_shots == 0, "Weapons Free did not restore engagement (%s)" % JSON.stringify(free))
	_expect(n.roe == SquadState.Roe.HOLD_FIRE and again.north_shots_after == 0, "Hold Fire did not stop the squad (%s)" % JSON.stringify(again))
	demo.rts.select([])
	await _clear()
	return out


# --- 2. terrain ---------------------------------------------------------------------------

## Two spots p (North) and q (South) 150-240 m apart, with a ridge between them, open
## ground, and a point r on q's side of the ridge from which q's squad sees p.
func _find_ridge(center: Vector3) -> Dictionary:
	for r: float in [0.0, 400.0, 800.0, 1200.0, 1700.0, 2300.0, 3000.0]:
		var n := 1 if r == 0.0 else 16
		for k in n:
			var a := k * TAU / n + 0.3
			var p := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			if absf(p.x) > 9200.0 or absf(p.z) > 9200.0 or not _far_from_soldiers(p, 900.0):
				continue
			if _solids(p, 25.0).trees > 0 or not _dry(p, 20.0) or _slope_at(p, 12.0) > 8.0:
				continue
			for j in 16:
				var dir := Vector3(cos(j * TAU / 16.0), 0, sin(j * TAU / 16.0))
				var side := Vector3(-dir.z, 0, dir.x)
				for dist: float in [150.0, 190.0, 230.0]:
					var q := demo.on_ground(p.x + dir.x * dist, p.z + dir.z * dist, 0.0)
					if _solids(q, 25.0).trees > 0 or not _dry(q, 20.0) or _slope_at(q, 12.0) > 8.0:
						continue
					var hidden := true
					for off: float in [-10.0, 0.0, 10.0]:
						for off2: float in [-10.0, 0.0, 10.0]:
							var e1 := demo.on_ground(p.x + side.x * off, p.z + side.z * off, 1.6)
							var e2 := demo.on_ground(q.x + side.x * off2, q.z + side.z * off2, 1.6)
							if lof.sight(e1, e2).blocker != "terrain":
								hidden = false
					if not hidden:
						continue
					for step: float in [30.0, 45.0, 60.0, 75.0, 90.0]:
						var rr := demo.on_ground(q.x - dir.x * step, q.z - dir.z * step, 0.0)
						if absf(rr.y - q.y) / step > 0.35 or _solids(rr, 20.0).trees > 0:
							continue
						var vis := 0
						for off: float in [-6.0, 0.0, 6.0]:
							var e2 := demo.on_ground(rr.x + side.x * off, rr.z + side.z * off, 1.55)
							if lof.sight(p + Vector3.UP * 1.6, e2).visible:
								vis += 1
						if vis == 3:
							return {"p": p, "q": q, "r": rr, "dir": dir, "dist": dist, "step": step}
	return {}


func _terrain() -> Dictionary:
	_begin()
	var g := _find_ridge(area)
	_expect(not g.is_empty(), "no ridge between two open spots found")
	if g.is_empty():
		return {"found": false}
	var p: Vector3 = g.p
	var q: Vector3 = g.q
	var n := _squad("North-R", 0, 8, p, _yaw_to(p, q))
	var s := _squad("South-R", 1, 8, q, _yaw_to(q, p))
	_tough(n, 400.0)
	_tough(s, 400.0)
	demo.rts_camera.frame(p.lerp(q, 0.5), 0.0, 140.0)
	await _seconds(1.5)
	_begin()
	var seen_hidden := 0
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 10.0:
		await tree.physics_frame
		seen_hidden = maxi(seen_hidden, _seeing(_ids(n)) + _seeing(_ids(s)))
	var hidden := {"seconds": 10.0, "max_seeing": seen_hidden, "shots": shot_log.size(), "sight_checks": brain.sight_checks}
	# South walks over the ridge (squad Move): contact once it is in view.
	demo.sim.squads.order_move([s.id], g.r)
	var t1 := demo.sim.state.time
	await _run_for(30.0, func() -> bool: return _seeing(_ids(n)) > 0 and _shots_of(0, t1) > 0)
	var contact_s := demo.sim.state.time - t1
	await _run_for(4.0)
	var over := {"contact_after_s": snappedf(contact_s, 0.1), "north_seeing": _seeing(_ids(n)), "north_shots": _shots_by(_ids(n), t1),
		"south_shots": _shots_by(_ids(s), t1), "south_status": SquadState.Status.keys()[s.status], "blockers": _combat_stats([n, s]).blockers}
	var out := {"geometry": {"p": _v(p), "q": _v(q), "r": _v(g.r), "distance_m": g.dist, "walk_m": g.step}, "behind_ridge": hidden, "over_ridge": over}
	_expect(seen_hidden == 0 and hidden.shots == 0, "soldiers saw or shot through the ridge (%s)" % JSON.stringify(hidden))
	_expect(over.north_seeing > 0 and over.north_shots > 0, "no contact after crossing the ridge (%s)" % JSON.stringify(over))
	await _clear()
	return out


# --- 2./4. constructed defences ------------------------------------------------------------

func _structures() -> Dictionary:
	_begin()
	var c := area
	var out := {}
	# a) Tall HESCO (2.2 m) across the whole front between two squads 80 m apart.
	var wall := cs.add_line(&"hesco_tall", PackedVector3Array([demo.on_ground(c.x - 25.0, c.z, 0.0), demo.on_ground(c.x + 25.0, c.z, 0.0)]))
	var n := _squad("North-W", 0, 8, c + Vector3(0, 0, 40), 0.0)
	var s := _squad("South-W", 1, 8, c + Vector3(0, 0, -40), PI)
	demo.rts_camera.frame(c, 0.0, 100.0)
	await _seconds(1.5)
	_begin()
	var seeing := 0
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 10.0:
		await tree.physics_frame
		seeing = maxi(seeing, _seeing(_ids(n)) + _seeing(_ids(s)))
	out.tall_wall = {"max_seeing": seeing, "shots": shot_log.size(), "line_n0_s0": lof.sight(CombatSim.eye_of(_u(n.members[0])), _u(s.members[0]).position + Vector3.UP * 1.55).blocker}
	if shots:
		demo.hud.combat_debug = true
		_frame_action(c, PI * 0.5, 90.0)
		await _seconds(0.8)
		_shot("blocked_line_of_sight_wall")
		demo.hud.combat_debug = false
	_expect(seeing == 0 and out.tall_wall.shots == 0, "soldiers saw or shot through a tall HESCO wall (%s)" % JSON.stringify(out.tall_wall))
	await _clear()
	cs.remove(wall.id)
	# b) North behind standard HESCO (1.37 m), 3 m in front of them; South in the open 70 m
	# away. Heads show over the wall: South aims at them; nothing hits below the wall top.
	var low := cs.add_line(&"hesco", PackedVector3Array([demo.on_ground(c.x - 20.0, c.z + 32.0, 0.0), demo.on_ground(c.x + 20.0, c.z + 32.0, 0.0)]))
	n = _squad("North-C", 0, 8, c + Vector3(0, 0, 35), 0.0)
	s = _squad("South-C", 1, 8, c + Vector3(0, 0, -35), PI)
	_tough(n, 300.0)
	_tough(s, 300.0)
	await _seconds(1.0)
	_begin()
	var aims := []
	await _run_for(5.0)
	for id in s.members:
		if _u(id).target_id > 0:
			aims.append(_u(id).target_aim_y)
	await _run_for(15.0)
	var low_hits := 0
	var through := []
	var heights := []
	var south_blocked := 0
	var south_shots := 0
	for sh in shot_log:
		if sh.faction != 1:
			continue
		south_shots += 1
		if sh.blocker == "structure":
			south_blocked += 1
		if sh.hit > 0 and _u(sh.hit) and _u(sh.hit).faction == 0:
			low_hits += 1
			heights.append(snappedf((sh.end as Vector3).y - _u(sh.hit).position.y, 0.01))
			# The hit's own segment, tested against the wall's collision boxes again.
			var o: Vector3 = sh.origin
			var e: Vector3 = sh.end
			if lof._structures_hit(o, e, o.distance_to(e)).d < o.distance_to(e) - 0.01:
				through.append({"height": heights[-1]})
	heights.sort()
	out.low_wall = {"south_shots": south_shots, "south_blocked_by_wall": south_blocked, "south_hits_on_north": low_hits,
		"hits_crossing_the_wall": through, "hit_heights_above_target_feet": heights, "south_aim_heights_at_5s": aims, "north_shots": _shots_of(0)}
	_expect(south_shots > 0 and south_blocked > 0 and through.is_empty() and aims.all(func(y: float) -> bool: return y > 1.3),
		"standard HESCO: shots passed through the wall, aim not at the exposed head, or no engagement (%s)" % JSON.stringify(out.low_wall))
	await _clear()
	cs.remove(low.id)
	await _seconds(0.5)
	return out


# --- 3. forest ----------------------------------------------------------------------------

## A forest edge: `deep` 35 m inside dense forest, `edge` 3 m inside its border, `open`
## 90 m out in the open, all on one line.
func _find_forest_edge(center: Vector3) -> Dictionary:
	for r: float in [0.0, 400.0, 800.0, 1200.0, 1700.0, 2300.0, 3000.0, 3800.0]:
		var n := 1 if r == 0.0 else clampi(int(r / 60.0), 12, 64)
		for k in n:
			var a := k * TAU / n
			var f := demo.on_ground(center.x + cos(a) * r, center.z + sin(a) * r, 0.0)
			if absf(f.x) > 9200.0 or absf(f.z) > 9200.0 or not _far_from_soldiers(f, 900.0):
				continue
			if _solids(f, 15.0).trees < 6:
				continue
			for j in 16:
				var dir := Vector3(cos(j * TAU / 16.0), 0, sin(j * TAU / 16.0))
				var open_run := 0
				var edge_k := -1.0
				for step in range(5, 160, 5):
					var p := f + dir * step
					if _solids(p, 8.0).trees == 0:
						open_run += 1
						if open_run == 1:
							edge_k = step
						if open_run >= 6:
							break
					else:
						open_run = 0
				if open_run < 6:
					continue
				var e := demo.on_ground(f.x + dir.x * (edge_k - 6.0), f.z + dir.z * (edge_k - 6.0), 0.0)
				var o := demo.on_ground(e.x + dir.x * 90.0, e.z + dir.z * 90.0, 0.0)
				var d := demo.on_ground(e.x - dir.x * 35.0, e.z - dir.z * 35.0, 0.0)
				if _solids(o, 25.0).trees > 0 or _solids(e + dir * 45.0, 15.0).trees > 0 or not _dry(o, 20.0) or not _dry(d, 15.0):
					continue
				if _solids(d, 12.0).trees < 5 or _slope_at(o, 12.0) > 8.0 or _slope_at(d, 10.0) > 10.0 or absf(o.y - e.y) > 12.0:
					continue
				return {"edge": e, "open": o, "deep": d, "dir": dir}
	return {}


## Fraction of North-South pairs with a clear sight line, and what blocks the others.
func _pair_sight(a: SquadState, b: SquadState) -> Dictionary:
	var clear := 0
	var total := 0
	var why := {}
	for i in a.members:
		for j in b.members:
			var r := lof.sight(CombatSim.eye_of(_u(i)), _u(j).position + Vector3.UP * 1.55)
			total += 1
			if r.visible:
				clear += 1
			else:
				why[r.blocker] = why.get(r.blocker, 0) + 1
	return {"pairs": total, "clear": clear, "blocked_by": why}


func _forest() -> Dictionary:
	_begin()
	var g := _find_forest_edge(area)
	_expect(not g.is_empty(), "no forest edge found")
	if g.is_empty():
		return {"found": false}
	var dir: Vector3 = g.dir
	var n := _squad("North-F", 0, 8, g.open, _yaw_to(g.open, g.edge))
	var s := _squad("South-F", 1, 8, g.deep, _yaw_to(g.deep, g.open), 2, 3.0)
	demo.sim.squads.set_roe([n.id, s.id], SquadState.Roe.HOLD_FIRE)
	_tough(n, 400.0)
	_tough(s, 400.0)
	demo.rts_camera.frame(g.edge, 0.0, 130.0)
	await _seconds(1.5)
	_begin()
	var seen_deep := 0
	var t0 := demo.sim.state.time
	while demo.sim.state.time - t0 < 8.0:
		await tree.physics_frame
		seen_deep = maxi(seen_deep, _seeing(_ids(n)))
	var deep := {"trees_within_12m": _solids(g.deep, 12.0).trees, "north_max_seeing": seen_deep, "sight": _pair_sight(n, s)}
	# South moves up to the forest edge (3 m inside the border).
	demo.sim.squads.order_move([s.id], g.edge)
	var t1 := demo.sim.state.time
	await _run_for(30.0, func() -> bool: return s.status == SquadState.Status.DONE and demo.sim.state.time - t1 > 3.0)
	await _run_for(3.0)
	var edge := {"trees_within_12m": _solids(g.edge, 12.0).trees, "north_seeing": _seeing(_ids(n)), "sight": _pair_sight(n, s), "south_status": SquadState.Status.keys()[s.status]}
	# Weapons free: the firefight at the edge.
	demo.sim.squads.set_roe([n.id, s.id], SquadState.Roe.WEAPONS_FREE)
	var t2 := demo.sim.state.time
	await _run_for(4.0)
	if shots:
		var look := _yaw_to(g.open, g.edge)
		_frame_action(g.edge + dir * 70.0, look, 110.0)
		await _snap_firing("forest_edge_firefight")
		demo.hud.combat_debug = true
		_frame_action(g.edge + dir * 70.0, look, 125.0)
		await _seconds(0.3)
		_shot("forest_edge_debug")
		demo.hud.combat_debug = false
	await _run_for(10.0)
	var fight := _combat_stats([n, s])
	fight["shots_since_free"] = _shots_of(0, t2) + _shots_of(1, t2)
	var out := {"geometry": {"edge": _v(g.edge), "open": _v(g.open), "deep": _v(g.deep)}, "south_deep_in_forest": deep, "south_at_edge": edge, "fight": fight}
	var deep_frac := float(deep.sight.clear) / maxi(deep.sight.pairs, 1)
	var edge_frac := float(edge.sight.clear) / maxi(edge.sight.pairs, 1)
	out["clear_fraction"] = {"deep": snappedf(deep_frac, 0.01), "edge": snappedf(edge_frac, 0.01)}
	_expect(deep_frac < edge_frac and edge.north_seeing > 0 and (deep.sight.blocked_by.get("foliage", 0) + deep.sight.blocked_by.get("tree", 0)) > 0,
		"forest did not affect perception as expected (%s)" % JSON.stringify(out))
	_expect(fight.shots_since_free > 0, "no firefight at the forest edge (%s)" % JSON.stringify(fight))
	await _clear()
	return out


# --- 8. friendly soldier in the line of fire ---------------------------------------------

func _friendly_line() -> Dictionary:
	_begin()
	var c := area
	var sh := _squad("Gunner", 0, 1, c + Vector3(0, 0, 30), 0.0)
	var fr := _squad("Screen", 0, 1, c + Vector3(0, 0, 15), 0.0)
	var en := _squad("Target", 1, 1, c + Vector3(0, 0, -25), PI)
	demo.sim.squads.set_roe([fr.id, en.id], SquadState.Roe.HOLD_FIRE)
	_tough(en, 100000.0)
	demo.rts_camera.frame(c, 0.0, 70.0)
	await _seconds(1.0)
	_begin()
	var gid: int = sh.members[0]
	var fid: int = fr.members[0]
	var hp0 := _u(fid).health
	await _run_for(6.0)
	var blocked := {"gunner_shots": _shots_by([gid]), "friend_damage": hp0 - _u(fid).health, "friendly_holds": brain.friendly_holds,
		"gunner_seeing": _seeing([gid]), "reason": _u(gid).ai_reason}
	# The friend steps 4 m aside.
	_put(fid, demo.on_ground(c.x + 4.0, c.z + 15.0, 0.3), 0.0)
	var t1 := demo.sim.state.time
	await _run_for(4.0)
	var clear := {"gunner_shots": _shots_by([gid], t1), "friend_damage": hp0 - _u(fid).health}
	var out := {"friend_in_line": blocked, "friend_aside": clear}
	_expect(blocked.friend_damage == 0.0 and blocked.friendly_holds > 0 and blocked.gunner_seeing == 1, "AI fired through a friendly soldier (%s)" % JSON.stringify(blocked))
	_expect(clear.gunner_shots > 0 and clear.friend_damage == 0.0, "AI did not fire once the line was clear (%s)" % JSON.stringify(clear))
	await _clear()
	return out


# --- 9. / 10. / 12. squad orders, possession and FPS / RTS during combat --------------------

func _orders_possession() -> Dictionary:
	_begin()
	var c := area
	var n := _squad("North-M", 0, 8, c + Vector3(-40, 0, 65), 0.0)
	var f := _squad("North-F2", 0, 4, c + Vector3(-40, 0, 80), 0.0)
	var s := _squad("South-M", 1, 8, c + Vector3(0, 0, -65), PI)
	for sq: SquadState in [n, f, s]:
		_tough(sq, 600.0)
	demo.sim.squads.order_hold([s.id])
	demo.sim.squads.order_follow([f.id], n.leader_id)
	demo.rts_camera.frame(c, 0.0, 140.0)
	await _seconds(1.5)
	_begin()
	var s_pos := {}
	for id in s.members:
		s_pos[id] = _u(id).position
	# Move across the front while the fight runs.
	var dest := demo.on_ground(c.x + 40.0, c.z + 65.0, 0.0)
	demo.sim.squads.order_move([n.id], dest)
	var t0 := demo.sim.state.time
	var s_orders := 0
	await _run_for(45.0, func() -> bool:
		for id in s.members:
			if _u(id).has_order():
				s_orders += 1
		return n.status == SquadState.Status.DONE and demo.sim.state.time - t0 > 3.0)
	var move_s := demo.sim.state.time - t0
	var moving_shots := 0
	for sh in shot_log:
		if _ids(n).has(sh.shooter) and sh.speed > 0.5:
			moving_shots += 1
	var drift := 0.0
	for id in s.members:
		drift = maxf(drift, _flat(s_pos[id], _u(id).position))
	var leader := _u(n.leader_id)
	var follow_dist := 0.0
	for id in f.members:
		follow_dist = maxf(follow_dist, _flat(_u(id).position, leader.position))
	var movement := {"move_s": snappedf(move_s, 0.1), "status": SquadState.Status.keys()[n.status], "dist_to_destination_m": snappedf(_flat(_centroid(n), dest), 0.1),
		"north_shots": _shots_by(_ids(n)), "shots_while_moving": moving_shots, "holding_south_max_drift_m": snappedf(drift, 0.01),
		"holding_south_order_frames": s_orders, "south_shots": _shots_by(_ids(s)), "follower_order": f.order_name(),
		"follower_max_dist_to_leader_m": snappedf(follow_dist, 0.1), "follower_shots": _shots_by(_ids(f))}
	_expect(n.status == SquadState.Status.DONE and moving_shots > 0 and drift < 1.0 and s_orders == 0 and movement.south_shots > 0,
		"squad orders during combat failed (%s)" % JSON.stringify(movement))
	_expect(f.order == SquadState.Order.FOLLOW and follow_dist < 30.0, "Follow broke during combat (%s)" % JSON.stringify(movement))
	# Possession during the engagement.
	var engaged := {}
	for sq: SquadState in [n, s]:
		for id in sq.members:
			if _u(id).target_id > 0:
				engaged[id] = _u(id).target_id
	# The North soldier nearest to the enemy (nobody of his own in front of him).
	var pid: int = n.members[1]
	var sc := _centroid(s)
	for id in n.members:
		if id != n.leader_id and _flat(_u(id).position, sc) < _flat(_u(pid).position, sc):
			pid = id
	var orders_before := {}
	for id in n.members:
		orders_before[id] = [_u(id).order, _u(id).order_target]
	var sq_order := [n.order, n.order_target]
	var body := await _possess(pid)
	var kept := 0
	var changed := []
	for id in engaged:
		if id == pid or not _u(id).alive or not _u(engaged[id]).alive:
			continue
		if _u(id).target_id == engaged[id]:
			kept += 1
		else:
			changed.append(id)
	var tp := demo.sim.state.time
	await _run_for(4.0)
	var p_auto := 0
	for sh in shot_log:
		if sh.shooter == pid and sh.t >= tp and not sh.possessed:
			p_auto += 1
	var poss := {"possessed": demo.game.possessed_id == pid and body != null, "ai_state": _u(pid).ai_state_name(),
		"ai_shots_of_possessed": p_auto, "squad_mates_shots": _shots_by(_ids(n).filter(func(i: int) -> bool: return i != pid), tp),
		"engagements_kept_on_possess": kept, "engagements_changed": changed.size(), "squad_order_unchanged": [n.order, n.order_target] == sq_order}
	var others_ok := true
	for id in n.members:
		if id != pid and _u(id).alive and [_u(id).order, _u(id).order_target] != orders_before[id]:
			others_ok = false
	poss["other_members_orders_unchanged"] = others_ok
	# The player fires a few rounds at the nearest enemy through the real input.
	if body:
		# The nearest enemy with no friend in the way (the player has friendly fire too).
		var tgt := -1
		var best := INF
		var eye := body.camera.global_position
		for id in s.members:
			var aim_at := _u(id).position + Vector3.UP * 1.2
			var d := _flat(_u(id).position, _u(pid).position)
			if d < best and not brain._friend_on_ray(_u(pid), eye, (aim_at - eye).normalized(), eye.distance_to(aim_at)):
				best = d
				tgt = id
		if tgt > 0:
			await _fps_shot_at(body, _u(tgt).position + Vector3.UP * 1.2)
			var before := shot_log.size()
			Input.action_press("fire")
			await _physics(3)
			if shots:
				_shot("fps_possession_during_engagement")
			await _physics(3)
			Input.action_release("fire")
			await _physics(4)
			var player_shots := 0
			for i in range(before, shot_log.size()):
				if shot_log[i].shooter == pid and shot_log[i].possessed:
					player_shots += 1
			poss["player_shots"] = player_shots
	# Back to the tactical view: the soldier's AI takes over again; the rest unchanged.
	var engaged2 := {}
	for id in spawned_ids:
		if _u(id) and _u(id).alive and _u(id).target_id > 0 and id != pid:
			engaged2[id] = _u(id).target_id
	_press(KEY_TAB)
	await _physics(2)
	var kept2 := 0
	for id in engaged2:
		if _u(engaged2[id]).alive and _u(id).target_id == engaged2[id]:
			kept2 += 1
		elif not _u(engaged2[id]).alive:
			kept2 += 1
	await _run_for(2.0)
	poss["after_tab"] = {"mode_rts": demo.game.mode == GameController.Mode.RTS, "ai_state": _u(pid).ai_state_name(),
		"engagements_kept": kept2, "engaged_before": engaged2.size()}
	if shots:
		demo.rts.select_squads([n.id])
		_frame_action(_centroid(n).lerp(_centroid(s), 0.3), _yaw_to(_centroid(n), _centroid(s)), 150.0)
		await _seconds(0.4)
		await _snap_firing("rts_selection_combat_status")
		demo.rts.select([])
	var out := {"movement": movement, "possession": poss}
	_expect(poss.possessed and poss.ai_state == "player" and p_auto == 0 and poss.squad_mates_shots > 0 and others_ok and poss.squad_order_unchanged,
		"possession stopped the squad or the AI fired for the player (%s)" % JSON.stringify(poss))
	_expect(changed.is_empty() and kept2 == engaged2.size() and poss.after_tab.ai_state != "player" and poss.get("player_shots", 0) > 0,
		"FPS / RTS switching changed engagements (%s)" % JSON.stringify(poss))
	await _clear()
	return out


# --- 13. save / load ---------------------------------------------------------------------

func _ai_sig(u: UnitState) -> String:
	return "%d|%s|%d|%.3f|%s|%.3f|%.3f|%d|%.3f|%s|%d|%d|%.3f" % [u.ai_state, u.alive, u.target_id, u.target_seen_at, u.target_visible,
		u.target_aim_y, u.aim_ready_at, u.burst_left, u.next_burst_at, str(snappedf(u.watch_yaw, 0.001)), u.mag, u.reserve, u.reload_until]


func _save_load_ai() -> Dictionary:
	_begin()
	var c := area
	var n := _squad("North-S", 0, 8, c + Vector3(0, 0, 60), 0.0)
	var s := _squad("South-S", 1, 8, c + Vector3(0, 0, -60), PI)
	_tough(n, 800.0)
	_tough(s, 800.0)
	demo.rts_camera.frame(c, 0.0, 120.0)
	await _run_for(6.0)
	demo.sim.squads.set_roe([s.id], SquadState.Roe.HOLD_FIRE)
	var saved := {}
	var restored := {}
	var grab := func(into: Dictionary) -> void:
		for id in spawned_ids:
			var u := _u(id)
			if u:
				into[id] = _ai_sig(u)
		into["roe"] = [_sq("North-S").roe if _sq("North-S") else -1, _sq("South-S").roe if _sq("South-S") else -1]
	# F5 is handled in the input step before the physics step: grab right after it.
	_press(KEY_F5)
	await _frames(1)
	await tree.process_frame
	grab.call(saved)
	var engaged_saved := 0
	for id in spawned_ids:
		if _u(id) and _u(id).target_id > 0:
			engaged_saved += 1
	await _run_for(3.0)
	var on_restore := func() -> void: grab.call(restored)
	demo.sim.state.restored.connect(on_restore)
	_press(KEY_F9)
	await _frames(2)
	demo.sim.state.restored.disconnect(on_restore)
	var diff := []
	for k in saved:
		if saved[k] != restored.get(k):
			diff.append({"key": k, "saved": saved[k], "loaded": restored.get(k)})
	var t1 := demo.sim.state.time
	await _run_for(4.0)
	var out := {"units": saved.size() - 1, "engaged_when_saved": engaged_saved, "differences": diff.slice(0, 6), "roe_saved": saved.roe,
		"north_shots_after_load": _shots_by(_ids(_sq("North-S")), t1), "south_shots_after_load": _shots_by(_ids(_sq("South-S")), t1)}
	_expect(diff.is_empty() and engaged_saved > 0 and out.north_shots_after_load > 0 and out.south_shots_after_load == 0,
		"save / load did not restore the engagement state (%s)" % JSON.stringify(out))
	await _clear()
	return out


# --- 14. promotion / demotion mid-fight ------------------------------------------------------

func _tiers() -> Dictionary:
	_begin()
	var c := area
	var n := _squad("North-T", 0, 8, c + Vector3(0, 0, 50), 0.0)
	var s := _squad("South-T", 1, 8, c + Vector3(0, 0, -50), PI)
	_tough(n, 2000.0)
	_tough(s, 2000.0)
	demo.rts_camera.frame(c, 0.0, 110.0)
	await _seconds(1.0)
	_begin()
	var hp0 := {}
	for id in spawned_ids:
		hp0[id] = _u(id).health
	var p0 := demo.detail.promotions
	var d0 := demo.detail.demotions
	var phases := []
	for k in 4:
		var far := k % 2 == 0
		demo.rts_camera.frame(demo.sites[2].position if far else c, 0.0, 110.0)
		var n0 := shot_log.size()
		await _run_for(4.0)
		var bodies := 0
		for id in spawned_ids:
			if _u(id).has_body:
				bodies += 1
		phases.append({"camera": "12 km away" if far else "at the fight", "test_bodies": bodies, "shots": shot_log.size() - n0})
	var st := _combat_stats([n, s])
	var hp_mismatch := 0
	var dmg_by := {}
	for sh in shot_log:
		if sh.hit > 0:
			dmg_by[sh.hit] = dmg_by.get(sh.hit, 0.0) + sh.damage
	for id in spawned_ids:
		if absf((hp0[id] - _u(id).health) - dmg_by.get(id, 0.0)) > 0.01:
			hp_mismatch += 1
	var out := {"phases": phases, "promotions": demo.detail.promotions - p0, "demotions": demo.detail.demotions - d0, "stats": st, "health_vs_shot_damage_mismatch": hp_mismatch}
	_expect(st.duplicate_counters == 0 and st.counter_gaps == 0 and hp_mismatch == 0 and st.damage_events == st.damaging_shots,
		"tier changes duplicated shots or damage (%s)" % JSON.stringify(out))
	_expect(phases[0].test_bodies == 0 and phases[0].shots > 0 and phases[1].test_bodies > 0 and phases[1].shots > 0,
		"AI did not fight in both tiers (%s)" % JSON.stringify(phases))
	await _clear()
	demo.rts_camera.frame(c, 0.0, 90.0)
	await _seconds(2.0)
	return out


# --- 9. / 15. performance ------------------------------------------------------------------

func _measure_fight(seconds: float) -> Dictionary:
	brain.reset_stats()
	combat.shots_total = 0
	combat.shot_usec_total = 0
	combat.shot_usec_max = 0
	var ms := PackedFloat32Array()
	var t_end := Time.get_ticks_msec() + seconds * 1000.0
	var bodies := 0
	while Time.get_ticks_msec() < t_end:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
		bodies = maxi(bodies, demo.sim.bodies.size())
	var frames := ms.size()
	var sorted := ms.duplicate()
	sorted.sort()
	var sum := 0.0
	var spikes := 0
	for v in ms:
		sum += v
		if v > 33.3:
			spikes += 1
	var b := brain.summary()
	return {"frames": frames, "frame_ms_avg": snappedf(sum / frames, 0.01), "frame_ms_p99": snappedf(sorted[int(frames * 0.99)], 0.01),
		"frame_ms_max": snappedf(sorted[frames - 1], 0.01), "frames_over_33ms": spikes, "bodies": bodies,
		"brain_update_us_avg": b.update_us_avg, "brain_update_us_max": b.update_us_max, "sight_checks": b.sight_checks,
		"sight_checks_per_frame": b.sight_checks_per_frame, "sight_us_avg": b.sight_us_avg, "shots": combat.shots_total,
		"shot_resolve_us_avg": snappedf(float(combat.shot_usec_total) / maxi(combat.shots_total, 1), 0.1), "shot_resolve_us_max": combat.shot_usec_max,
		"states": b.states}


func _perf_case(label: String, center: Vector3, per_side: int, axis: Vector3, half: float, fps: bool) -> Dictionary:
	var yaw_n := _yaw_to(center + axis * half, center)
	var squads := []
	for k in per_side / 8:
		var off := Vector3(-axis.z, 0, axis.x) * (k * 30.0 - (per_side / 8 - 1) * 15.0)
		squads.append(_squad("N%d" % k, 0, 8, center + axis * half + off, yaw_n))
		squads.append(_squad("S%d" % k, 1, 8, center - axis * half + off, yaw_n + PI))
	for sq: SquadState in squads:
		_tough(sq, 100000.0)
	demo.rts_camera.frame(center, 0.0, 130.0)
	await _seconds(2.0)
	if fps:
		var pid: int = squads[0].members[3]
		var body := await _possess(pid)
		if body:
			await _fps_shot_at(body, center - axis * half + Vector3.UP * 1.2)
	await _seconds(1.0)
	var m := await _measure_fight(8.0)
	m["case"] = label
	m["soldiers"] = per_side * 2
	await _leave()
	await _clear()
	return m


func _perf_ai() -> Dictionary:
	var out := {}
	demo.rts_camera.frame(area, 0.0, 130.0)
	await _seconds(2.0)
	out.baseline_rts_no_test_squads = await _measure_fight(6.0)
	out.open_8v8_rts = await _perf_case("8v8 open RTS", area, 8, Vector3(0, 0, 1), 60.0, false)
	out.open_8v8_fps = await _perf_case("8v8 open FPS", area, 8, Vector3(0, 0, 1), 60.0, true)
	out.open_16v16_rts = await _perf_case("16v16 open RTS", area, 16, Vector3(0, 0, 1), 60.0, false)
	out.open_16v16_fps = await _perf_case("16v16 open FPS", area, 16, Vector3(0, 0, 1), 60.0, true)
	var g := _find_forest_edge(area)
	if not g.is_empty():
		out.forest_16v16_rts = await _perf_case("16v16 forest RTS", g.deep, 16, g.dir, 45.0, false)
		out.forest_16v16_fps = await _perf_case("16v16 forest FPS", g.deep, 16, g.dir, 45.0, true)
	var base: Dictionary = out.baseline_rts_no_test_squads
	var big: Dictionary = out.open_16v16_rts
	out["16v16_vs_baseline"] = {"avg_ms_added": snappedf(big.frame_ms_avg - base.frame_ms_avg, 0.01), "p99_ms_added": snappedf(big.frame_ms_p99 - base.frame_ms_p99, 0.01)}
	_expect(big.brain_update_us_avg < 1500.0 and big.frame_ms_avg - base.frame_ms_avg < 4.0 and big.frame_ms_p99 - base.frame_ms_p99 < 8.0 and big.shots > 0,
		"16 vs 16 degrades the frame time significantly (%s)" % JSON.stringify(out["16v16_vs_baseline"]))
	return out


# --- Output ---------------------------------------------------------------------------

func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/c01b_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("AI shot: ", path)


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("AI %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("AI FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	Input.action_release("fire")
	results["deaths"] = deaths.size()
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/combat_ai_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("AI %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()
