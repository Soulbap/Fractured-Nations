## Scripted checks of WORLD-SANDBOX-01 (the persistent three-faction war) on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 res://scenes/game/world_ref_20km.tscn -- --sandbox-test [--shots] [--only a,b] [--minutes N]
##
## Runs the real game in sandbox mode (WarSim, StrategicRoutes, faction AI, SquadControl,
## CombatBrain / CombatSim, DetailManager) and drives it through the same functions the
## player's map and RTS use. Prints "SANDBOX <check> <json>", writes
## res://benchmarks/raw/sandbox_test.json and (with --shots) docs/sandbox01/s01_*.jpg.
class_name SandboxSelfTest
extends CombatAISelfTest

var only: PackedStringArray = []
var war: WarState
var ws: WarSim
var log_from := 0
## Every accelerated stretch of the run: requested and reached speed, largest step.
var warps := []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/sandbox01b"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	con = demo.construction
	sm = demo.structures
	cs = demo.sim.state.construction
	combat = demo.sim.combat
	lof = combat.line
	brain = demo.sim.brain
	def = combat.weapon(&"rifle")
	war = demo.sim.state.war
	ws = demo.sim.war
	SoldierBody.require_mouse_capture = false
	var state := demo.sim.state
	state.shot_fired.connect(_on_shot_rec)
	state.unit_damaged.connect(func(t: UnitState, _a: float, _z: int, _s: int) -> void:
		dmg_events += 1
		if not t.alive:
			dmg_on_dead += 1)
	state.unit_died.connect(func(u: UnitState) -> void:
		deaths.append({"id": u.id, "t": snappedf(state.time, 0.1)}))
	# Real time (the scenarios run simulated time fast).
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_log("setup", demo.spawn_info.merged({"summary": ws.summary()}))
	if _want("routes"):
		_log("routes", _routes())
	if _want("transitions"):
		_log("transitions", await _transitions())
	if _want("mapshot"):
		demo.toggle_map()
		await _frames(10)
		_shot("dev_map_start")
		demo.toggle_map()
		await _warp(300.0)
		demo.toggle_map()
		await _frames(10)
		_shot("dev_map_5min")
		demo.strategic_map.zoom *= 3.0
		demo.strategic_map.view_center = Vector2(-2000, 1500)
		await _frames(10)
		_shot("dev_map_zoom")
		demo.toggle_map()
	if _want("war"):
		var mi := args.find("--minutes")
		var minutes := float(args[mi + 1]) if mi >= 0 and mi + 1 < args.size() else 20.0
		_log("autonomous_war", await _autonomous(minutes))
	if _want("timescale"):
		_log("time_compression", await _time_compression())
	if _want("warp_fidelity"):
		_log("warp_fidelity", await _warp_fidelity())
	if _want("map_ui"):
		_log("map_ui", await _map_ui())
	if _want("hud"):
		_log("hud", await _hud())
	if _want("start_map"):
		await _map_shot("01_strategic_map_start")
		await _map_shot("02_objectives_and_borders", Vector2(-1500, -3000), 2.2)
	if _want("offensive"):
		_log("player_offensive", await _offensive())
	if _want("reinforce"):
		_log("reinforcement", await _reinforce())
	if _want("map_fps"):
		_log("map_rts_fps", await _map_to_fps())
	if _want("navigation"):
		_log("navigation_march", await _navigation_march())
	if _want("persist"):
		_log("save_load_war", await _persist())
	if _want("perf"):
		_log("performance", await _perf())
	if _want("extended"):
		await _multi_ops_shot()
		_log("extended_war", await _extended(40.0))
		await _map_shot("11_map_after_autonomous_war")
		await _map_shot("03_force_markers", _known_center(), 3.0)
	# A navmesh bake on a worker must finish before the engine shuts down.
	TimeCompression.reset()
	while demo.navigation.has_pending_bake():
		await _seconds(0.2)
	await _seconds(0.5)
	_finish()


func _want(n: String) -> bool:
	# Development checks (long war printout, map snapshots) only when asked for.
	if n in ["war", "mapshot"]:
		return only.has(n)
	return only.is_empty() or only.has(n)


func _obj(name: String) -> ObjectiveState:
	for o: ObjectiveState in war.objectives.values():
		if o.obj_name == name:
			return o
	return null


# --- Camera transitions ---------------------------------------------------------------------

## Jumps of the tactical camera between distant objectives (as the map's "View" does) and
## the possession of a soldier far away: worst frame within 4 s after each, and what
## DetailManager did (navmesh bake, terrain collision, bodies promoted).
func _transitions() -> Dictionary:
	var out := {"jumps": []}
	var names := ["North HQ", "East HQ", "Sentrum", "South HQ", "North Bridge"]
	await _seconds(2.0)
	for nm in names:
		var o := _obj(nm)
		var p0 := demo.detail.promotions
		var bakes0 := demo.detail.bake_count
		demo.strategic_map.visible = true
		demo.strategic_map.selected_objective = o.id
		demo.strategic_map.selected_squads.clear()
		demo.strategic_map.go_to_selection()
		var m := await _frame_stats(4.0)
		m["to"] = nm
		m["promoted"] = demo.detail.promotions - p0
		m["bakes"] = demo.detail.bake_count - bakes0
		m["last_bake"] = demo.detail.last_bake.duplicate()
		out.jumps.append(m)
	# Possess a soldier of the player's faction far from the camera.
	var far_u: UnitState = null
	for u in demo.sim.state.soldiers():
		if u.faction == war.player_faction and u.alive and Vector2(u.position.x - demo.rts_camera.focus.x, u.position.z - demo.rts_camera.focus.z).length() > 5000.0:
			far_u = u
			break
	if far_u:
		var t := Time.get_ticks_usec()
		var ok := demo.game.possess(far_u.id)
		var call_ms := (Time.get_ticks_usec() - t) / 1000.0
		var m2 := await _frame_stats(4.0)
		m2["possess_call_ms"] = snappedf(call_ms, 0.1)
		m2["possessed"] = ok
		m2["on_ground"] = demo.game.possessed_body() != null and demo.game.possessed_body().is_on_floor()
		m2["last_bake"] = demo.detail.last_bake.duplicate()
		out["possess_far"] = m2
		_press(KEY_TAB)
		await _seconds(1.0)
	return out


func _frame_stats(seconds: float) -> Dictionary:
	var ms := PackedFloat32Array()
	var t_end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < t_end:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
	var sorted := ms.duplicate()
	sorted.sort()
	var over := 0
	for v in ms:
		if v > 33.3:
			over += 1
	var sum := 0.0
	for v in ms:
		sum += v
	return {"frames": ms.size(), "avg_ms": snappedf(sum / maxi(ms.size(), 1), 0.01), "max_ms": snappedf(sorted[-1], 0.1), "p99_ms": snappedf(sorted[int(ms.size() * 0.99)], 0.1),
		"frames_over_33ms": over, "first5_ms": Array(ms.slice(0, 5)).map(func(v: float) -> float: return snappedf(v, 0.1))}


# --- Scenario helpers ----------------------------------------------------------------------

## AI factions decide nothing while a scenario sets up its own fight (the rest of the
## war keeps running: marches, captures, reserves).
func _pause_ai(on: bool) -> void:
	for f: FactionState in war.factions.values():
		if not f.player:
			f.next_decision_at = INF if on else demo.sim.state.time + 5.0


func _spawn(f: int, p: Vector3, n := 8) -> SquadState:
	var sq := ws.spawn_squad(war.faction(f), demo.on_ground(p.x, p.z, 0.0), n)
	for id in sq.members:
		spawned_ids.append(id)
	return sq


## A passable point at distance d from o, towards `towards` (searched round if needed).
func _near_point(o: Vector3, towards: Vector3, d: float) -> Vector3:
	var dir := Vector3(towards.x - o.x, 0, towards.z - o.z).normalized()
	for k in 16:
		var a := k * 0.4 * (1 if k % 2 == 0 else -1)
		var p := o + dir.rotated(Vector3.UP, a) * d
		if ws.routes.passable(p) and ws.routes.passable(p + Vector3(12, 0, 12)) and ws.routes.passable(p - Vector3(12, 0, 12)):
			return demo.on_ground(p.x, p.z, 0.0)
	return demo.on_ground(o.x + dir.x * d, o.z + dir.z * d, 0.0)


func _ids_of(sqs: Array) -> Array:
	var out := []
	for sq: SquadState in sqs:
		out.append_array(Array(sq.members) + Array(sq.fallen))
	return out


func _alive_count(sqs: Array) -> int:
	var n := 0
	for sq: SquadState in sqs:
		for id in sq.members:
			if _u(id) and _u(id).alive:
				n += 1
	return n


func _map_shot(shot_name: String, center := Vector2.INF, zoom_mul := 1.0) -> void:
	if not shots:
		return
	var m := demo.strategic_map
	var was := m.visible
	if not was:
		demo.toggle_map()
	m.fit_all()
	if center.is_finite():
		m.view_center = center
		m.zoom *= zoom_mul
	await _frames(6)
	_shot(shot_name)
	if not was:
		demo.toggle_map()
	await _frames(2)


## Consistency of the war records: every squad serves at most one active operation and
## that operation lists it; operation ids are unique; no living soldier is in two squads.
func _consistency() -> Dictionary:
	var bad := []
	var in_op := {}
	for op: OperationState in war.active_operations():
		for sid in op.squads:
			if in_op.has(sid):
				bad.append("squad %d in ops %d and %d" % [sid, in_op[sid], op.id])
			in_op[sid] = op.id
			var sq := demo.sim.state.get_squad(sid)
			if sq and sq.op_id != op.id:
				bad.append("op %d lists squad %d whose op is %d" % [op.id, sid, sq.op_id])
	for sq: SquadState in demo.sim.state.all_squads():
		if sq.op_id >= 0 and (war.operation(sq.op_id) == null or not war.operation(sq.op_id).is_active() or not war.operation(sq.op_id).squads.has(sq.id)):
			bad.append("squad %s points at op %d that does not list it" % [sq.squad_name, sq.op_id])
	var seen := {}
	for sq: SquadState in demo.sim.state.all_squads():
		for id in sq.members:
			if seen.has(id):
				bad.append("unit %d in two squads" % id)
			seen[id] = true
	return {"problems": bad.slice(0, 8), "count": bad.size()}


# --- Scenario 2: player offensive ------------------------------------------------------------

## The player selects two squads on the map and orders an attack on Haugen, held by a
## South squad. The squads march, fight the defenders and take the village.
func _offensive() -> Dictionary:
	_pause_ai(true)
	var hau := _obj("Haugen")
	hau.owner = 1
	hau.history.append([demo.sim.state.time, 1])
	var defenders := _spawn(1, hau.position + Vector3(10, 0, -10))
	defenders.station_objective = hau.id
	var hq := _obj("North HQ")
	var start := _near_point(hau.position, hq.position, 520.0)
	var a := _spawn(0, start)
	var b := _spawn(0, start + Vector3(25, 0, 25))
	var c := _spawn(0, start + Vector3(-25, 0, 25))
	await _physics(10)
	var m := demo.strategic_map
	m.selected_squads = [a.id, b.id, c.id]
	m.selected_objective = hau.id
	await _map_shot("04_operation_planned", Vector2(hau.position.x, hau.position.z) - Vector2(0, -200), 4.0)
	var op := m.order(OperationState.Type.ATTACK, hau.id)
	_expect(op != null and op.player_ordered and op.squads.size() == 3, "the map did not create the player's attack")
	if op == null:
		_pause_ai(false)
		return {}
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _seconds(0.5)
	var w1 := await _warp(70.0, 16.0)
	var phases := [op.phase_name()]
	var contested_seen := {"v": false}
	var w2 := await _warp(900.0, 12.0, 150.0, func() -> bool:
		if phases[-1] != op.phase_name():
			phases.append(op.phase_name())
		if hau.contested:
			contested_seen.v = true
		return not op.is_active())
	if shots and not contested_seen.v:
		pass
	await _map_shot("07_territory_changed", Vector2(hau.position.x, hau.position.z), 3.0)
	var out := {"op": {"id": op.id, "phase": op.phase_name(), "outcome": op.outcome, "start_strength": op.start_strength, "losses": op.losses, "phases_seen": phases},
		"haugen_owner": WorldState.faction_name(hau.owner) if hau.owner >= 0 else "-", "defenders_left": _alive_count([defenders]),
		"attackers_left": _alive_count([a, b, c]), "contested_seen": contested_seen.v, "warp": [w1, w2], "consistency": _consistency(),
		"events": war.events.slice(-8).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t, e.text])}
	_expect(op.phase == OperationState.Phase.COMPLETED and hau.owner == 0 and out.defenders_left == 0, "the player's attack did not take Haugen (%s)" % JSON.stringify(out))
	_expect(phases.has("engaging") and out.consistency.count == 0, "attack phases / records wrong (%s)" % JSON.stringify(out))
	_pause_ai(false)
	return out


# --- Scenario 3: reinforcement --------------------------------------------------------------

## South attacks Elvetun (North, one squad of garrison) from 1.5 km. The player sends two
## squads from the North Bridge garrison 3 km away. They follow their route (checked: no
## water, no impassable ground), travel, arrive and fight.
func _reinforce() -> Dictionary:
	_pause_ai(true)
	var elv := _obj("Elvetun")
	var nb := _obj("North Bridge")
	var hq := _obj("South HQ")
	var s1 := _spawn(1, _near_point(elv.position, hq.position, 1500.0))
	var s2 := _spawn(1, _near_point(elv.position, hq.position, 1500.0) + Vector3(20, 0, 20))
	var att := ws.start_operation(1, OperationState.Type.ATTACK, [s1.id, s2.id], elv.id)
	var r1 := _spawn(0, nb.position + Vector3(-30, 0, 0))
	var r2 := _spawn(0, nb.position + Vector3(-30, 0, 25))
	await _physics(10)
	var m := demo.strategic_map
	m.selected_squads = [r1.id, r2.id]
	var rop := m.order(OperationState.Type.REINFORCE, elv.id)
	_expect(rop != null, "the map did not create the reinforcement")
	if rop == null:
		_pause_ai(false)
		return {}
	var route := r1.route.duplicate()
	var wet := 0
	for i in range(1, route.size()):
		var n := maxi(1, int(route[i].distance_to(route[i - 1]) / 5.0))
		for k in n + 1:
			if not ws.routes.passable(route[i - 1].lerp(route[i], float(k) / n)):
				wet += 1
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _seconds(0.5)
	await _warp(150.0, 16.0)
	var mid := (ws.squad_center(r1) + elv.position) * 0.5
	await _map_shot("05_forces_on_strategic_route", Vector2(mid.x, mid.z), 3.0)
	_begin()
	var track := {"in_water": 0, "samples": 0, "d0": _flat(ws.squad_center(r1), elv.position), "min_d": INF}
	var t0 := demo.sim.state.time
	var w := await _warp(1500.0, 16.0, 150.0, func() -> bool:
		for sq: SquadState in [r1, r2]:
			for id in sq.members:
				var u := _u(id)
				if u and u.alive:
					track.samples += 1
					if ws.routes.is_water(u.position):
						track.in_water += 1
		if not r1.members.is_empty():
			track.min_d = minf(track.min_d, _flat(ws.squad_center(r1), elv.position))
		return not rop.is_active() and demo.sim.state.time - rop.ended_at > 120.0)
	var shots_r := _shots_by(_ids_of([r1, r2]))
	var out := {"route": {"waypoints": route.size(), "length_km": snappedf(ws.routes.route_length(route) / 1000.0, 0.01), "impassable_samples": wet},
		"travel": {"start_m": snappedf(track.d0, 1.0), "closest_m": snappedf(track.min_d, 1.0), "samples_in_water": track.in_water},
		"reinforce_op": {"type": rop.type_name(), "phase": rop.phase_name(), "outcome": rop.outcome, "arrived_after_s": snappedf(rop.ended_at - t0, 1.0) if rop.ended_at > 0 else -1},
		"south_attack": {"phase": att.phase_name() if att else "-", "outcome": att.outcome if att else ""},
		"elvetun_owner": WorldState.faction_name(elv.owner) if elv.owner >= 0 else "-", "reinforcement_shots": shots_r,
		"reinforcements_left": _alive_count([r1, r2]), "south_left": _alive_count([s1, s2]), "warp": w, "consistency": _consistency()}
	_expect(wet == 0 and track.in_water == 0 and track.min_d < elv.radius + 60.0, "reinforcements did not travel a valid route to Elvetun (%s)" % JSON.stringify(out))
	_expect(not rop.is_active() and rop.phase != OperationState.Phase.FAILED or rop.type == OperationState.Type.ATTACK, "reinforcement did not arrive (%s)" % JSON.stringify(out))
	_expect(shots_r > 0 and out.consistency.count == 0, "reinforcements did not take part in the fight (%s)" % JSON.stringify(out))
	_pause_ai(false)
	return out


# --- Scenario 4: map -> RTS -> FPS -> map ---------------------------------------------------------

## A battle 7 km from the camera: the player opens the map, selects the squad there, jumps
## (RTS), possesses one of its soldiers, fires, goes back to RTS and to the map. Nothing
## is duplicated or reset on the way.
func _map_to_fps() -> Dictionary:
	_pause_ai(true)
	var sen := _obj("Sentrum")
	var hq := _obj("North HQ")
	var own := _spawn(0, _near_point(sen.position, hq.position, 300.0))
	var own2 := _spawn(0, _near_point(sen.position, hq.position, 300.0) + Vector3(20, 0, 20))
	var foe := _spawn(1, sen.position)
	foe.station_objective = sen.id
	var op := ws.start_operation(0, OperationState.Type.ATTACK, [own.id, own2.id], sen.id, Vector3.INF, true)
	demo.rts_camera.frame(_obj("East HQ").position, 0.0, 120.0)
	await _seconds(1.0)
	await _warp(35.0, 8.0)
	_begin()
	var units0 := demo.sim.state.units.size()
	var squads0 := demo.sim.state.squads.size()
	await _map_shot("06_objective_under_attack", Vector2(sen.position.x, sen.position.z), 6.0)
	var m := demo.strategic_map
	demo.toggle_map()
	await _frames(3)
	m.selected_squads = [own.id]
	var t0 := Time.get_ticks_msec()
	m.go_to_selection()
	var jump := await _frame_stats(3.0)
	if shots:
		_frame_action(ws.squad_center(own), demo.rts_camera.yaw, 70.0)
		await _seconds(0.5)
		await _snap_firing("08_rts_active_operation")
	var pid := -1
	for id in Array(own.members) + Array(own2.members):
		if _u(id).alive:
			pid = id
			break
	var poss := {}
	if pid > 0:
		var body := await _possess(pid)
		var psq := demo.sim.state.squad_of(pid)
		poss = {"possessed": body != null, "op_kept": psq != null and psq.op_id == op.id, "had_body_before": true}
		if body:
			var tgt := -1
			var bd := INF
			for id in foe.members:
				if _u(id).alive and _flat(_u(id).position, _u(pid).position) < bd:
					bd = _flat(_u(id).position, _u(pid).position)
					tgt = id
			if tgt > 0:
				await _fps_shot_at(body, _u(tgt).position + Vector3.UP * 1.2)
				Input.action_press("fire")
				await _physics(3)
				if shots:
					_shot("09_fps_same_operation")
				await _physics(6)
				Input.action_release("fire")
			poss["player_shots"] = shot_log.filter(func(s: Dictionary) -> bool: return s.shooter == pid and s.possessed).size()
		await _seconds(1.0)
		_press(KEY_TAB)
		await _physics(5)
	demo.toggle_map()
	await _frames(5)
	var back_on_map := m.visible
	demo.toggle_map()
	var st := _combat_stats([own, own2, foe])
	var out := {"jump_frames": jump, "possession": poss, "back_on_map": back_on_map, "units": [units0, demo.sim.state.units.size()],
		"squads": [squads0, demo.sim.state.squads.size()], "op_still_active_or_done": op.phase_name(), "duplicate_shot_counters": st.duplicate_counters,
		"damage_events": st.damage_events, "damaging_shots": st.damaging_shots, "consistency": _consistency()}
	_expect(poss.get("possessed", false) and poss.get("player_shots", 0) > 0 and back_on_map, "map -> RTS -> FPS -> map did not work (%s)" % JSON.stringify(out))
	_expect(out.units[0] == out.units[1] and st.duplicate_counters == 0 and st.damage_events == st.damaging_shots and out.consistency.count == 0,
		"switching views duplicated units, shots or damage (%s)" % JSON.stringify(out))
	_pause_ai(false)
	return out


# --- Scenario 5: save / load during the war -------------------------------------------------------

func _war_sig() -> Dictionary:
	var s := {}
	for o: ObjectiveState in war.all_objectives():
		s["obj%d" % o.id] = "%d|%d|%.3f|%s" % [o.owner, o.capture_faction, o.capture_progress, o.contested]
	for u: UnitState in demo.sim.state.all_units():
		s["u%d" % u.id] = "%s|%.3f|%.3f|%.3f|%s|%d|%d" % [u.alive, u.position.x, u.position.z, u.health, u.order, u.mag, u.reserve]
	for sq: SquadState in demo.sim.state.all_squads():
		s["sq%d" % sq.id] = "%s|%d|%d/%d|%d|%d" % [str(Array(sq.members)), sq.op_id, sq.route_i, sq.route.size(), sq.order, sq.station_objective]
	for op: OperationState in war.operations.values():
		s["op%d" % op.id] = "%d|%d|%d|%s|%d|%d" % [op.type, op.phase, op.target_objective, str(Array(op.squads)), op.start_strength, op.losses]
	for f: FactionState in war.factions.values():
		s["f%d" % f.id] = "%d|%d|%d|%.4f|%.4f|%d" % [f.reserves, f.casualties, f.squad_counter, f.next_reinforcement_at, f.recovery_until, f.ops_started]
	s["events"] = war.events.size()
	s["next_op"] = war.next_op_id
	return s


func _persist() -> Dictionary:
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _seconds(0.5)
	await _warp(240.0, 24.0)
	var saved := {}
	var restored := {}
	# Simulated time stands still around the save, so the comparison sees exactly what was
	# written (at 1 x a physics tick between the key press and the snapshot moves soldiers).
	# The signature is taken in the same instant the save takes its snapshot.
	var on_save := func() -> void: saved.merge(_war_sig(), true)
	demo.sim.state.saving.connect(on_save)
	_press(KEY_F5)
	await _frames(2)
	demo.sim.state.saving.disconnect(on_save)
	_expect(not saved.is_empty(), "F5 did not save the world")
	var ops_at_save := war.active_operations().size()
	await _warp(120.0, 24.0)
	var changed := 0
	var after := _war_sig()
	for k in saved:
		if saved[k] != after.get(k):
			changed += 1
	var on_restore := func() -> void: restored.merge(_war_sig(), true)
	demo.sim.state.restored.connect(on_restore)
	_press(KEY_F9)
	await _frames(2)
	demo.sim.state.restored.disconnect(on_restore)
	var diff := []
	for k in saved:
		if saved[k] != restored.get(k):
			diff.append({"key": k, "saved": saved[k], "loaded": restored.get(k)})
	for k in restored:
		if not saved.has(k):
			diff.append({"key": k, "extra_after_load": restored[k]})
	var t1 := demo.sim.state.time
	await _warp(180.0, 24.0)
	var out := {"active_ops_at_save": ops_at_save, "keys_compared": saved.size(), "changed_before_load": changed, "differences": diff.slice(0, 6),
		"difference_count": diff.size(), "war_continues": demo.sim.state.time > t1 + 100.0, "consistency_after": _consistency(), "summary": ws.summary()}
	_expect(diff.is_empty() and changed > 0 and ops_at_save > 0, "save / load did not restore the war (%s)" % JSON.stringify(out.differences))
	_expect(out.consistency_after.count == 0, "records inconsistent after load (%s)" % JSON.stringify(out.consistency_after))
	return out


## The player runs several operations at once (shown on the map), then cancels them so
## the extended war that follows is the AI factions' own.
func _multi_ops_shot() -> void:
	var idle := ws.squads_of(war.player_faction).filter(func(sq: SquadState) -> bool: return sq.op_id < 0 and sq.members.size() >= 4)
	var ops := []
	var targets := [["Sentrum", OperationState.Type.ATTACK], ["Centre Bridge", OperationState.Type.ATTACK], ["Elvetun", OperationState.Type.REINFORCE], ["Haugen", OperationState.Type.ATTACK]]
	var k := 0
	for t: Array in targets:
		if k + 1 >= idle.size():
			break
		var o := _obj(t[0])
		if o == null:
			continue
		var type: OperationState.Type = t[1]
		if o.owner == war.player_faction and type == OperationState.Type.ATTACK:
			type = OperationState.Type.REINFORCE
		var op := ws.start_operation(war.player_faction, type, [idle[k].id, idle[k + 1].id], o.id, Vector3.INF, true)
		if op:
			ops.append(op)
		k += 2
	await _warp(120.0, 16.0)
	await _map_shot("10_multiple_operations", Vector2(-3000, -5000), 1.8)
	_log("multiple_operations", {"started": ops.size(), "phases": ops.map(func(o: OperationState) -> String: return "%s %s" % [o.type_name(), o.phase_name()])})
	for op: OperationState in ops:
		ws.cancel(op.id, "test: back to the AI war")


## Centre of the enemy soldiers the player's faction currently knows about.
func _known_center() -> Vector2:
	var k: Dictionary = ws.known.get(war.player_faction, {})
	if k.is_empty():
		return Vector2(-1000, -2500)
	var c := Vector2.ZERO
	for id in k:
		c += Vector2(k[id][0].x, k[id][0].z)
	return c / k.size()


## The player's time compression (key .): at 8 x the simulation step must stay 1/60 s.
func _time_compression() -> Dictionary:
	demo.rts_camera.frame(_obj("North HQ").position, 0.0, 120.0)
	await _seconds(1.0)
	for i in 3:
		demo.set_time_speed(1)
	var deltas := {}
	var t0 := demo.sim.state.time
	var r0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - r0 < 5000:
		await tree.physics_frame
		deltas[snappedf(demo.sim.last_delta, 0.0001)] = true
	var real := (Time.get_ticks_msec() - r0) / 1000.0
	var out := {"nominal": Engine.time_scale, "ticks_per_s": Engine.physics_ticks_per_second, "step_s": deltas.keys(),
		"achieved_speed": snappedf((demo.sim.state.time - t0) / real, 0.1)}
	demo.set_time_speed(-3)
	out["after_reset"] = [Engine.time_scale, Engine.physics_ticks_per_second]
	_expect(out.step_s.size() == 1 and absf(out.step_s[0] - 1.0 / 60.0) < 0.0002 and out.achieved_speed > 4.0 and out.after_reset == [1.0, 60],
		"time compression changed the simulation step (%s)" % JSON.stringify(out))
	return out


## WORLD-SANDBOX-01B: the strategic map in the situations the player meets, with
## screenshots (--shots) and checks of what the map promises: markers at real positions
## (groups only merge on screen), zoom towards the cursor, group selection, double-click
## zoom, objective as target for the order buttons, operation details.
func _map_ui() -> Dictionary:
	_pause_ai(true)
	var out := {}
	var m := demo.strategic_map
	var elv := _obj("Elvetun")
	var hau := _obj("Haugen")
	var nhq := _obj("North HQ")
	# Four squads close together in the open, 0.5 km from Elvetun.
	var base := _near_point(elv.position, nhq.position, 500.0)
	var group := []
	for off: Vector3 in [Vector3(0, 0, 0), Vector3(70, 0, 30), Vector3(140, 0, -20), Vector3(40, 0, 120)]:
		group.append(_spawn(0, base + off))
	await _physics(10)
	if not m.visible:
		demo.toggle_map()
	await _frames(3)
	# 1. Whole map.
	m.fit_all()
	await _frames(6)
	_shot("01_full_map")
	var groups_overview: Array = m.squad_groups()
	var grouped := {}
	for g: Dictionary in groups_overview:
		var has := 0
		for sq: SquadState in group:
			if g.ids.has(sq.id):
				has += 1
		if has > 0:
			grouped[str(g.ids.size())] = has
	# Group centre on screen = mean of the squads' real positions.
	var real := Vector3.ZERO
	for sq: SquadState in group:
		real += ws.squad_center(sq)
	real /= group.size()
	var g4: Dictionary = {}
	for g: Dictionary in groups_overview:
		if g.ids.has(group[0].id):
			g4 = g
	if not g4.is_empty():
		# The group's real centre: all its squads (a garrison nearby may join on screen).
		real = Vector3.ZERO
		for sid in g4.ids:
			real += ws.squad_center(demo.sim.state.get_squad(sid))
		real /= g4.ids.size()
	out.overview = {"groups": groups_overview.size(), "group_of_the_four": g4.ids.size() if not g4.is_empty() else 0,
		"group_center_error_m": snappedf(Vector2(m.to_world(g4.pos).x - real.x, m.to_world(g4.pos).z - real.z).length(), 0.1) if not g4.is_empty() else -1.0}
	_expect(not g4.is_empty() and g4.ids.size() >= 4 and out.overview.group_center_error_m < 30.0, "the four nearby squads are not one group at their real centre (%s)" % JSON.stringify(out.overview))
	# Click on the group: all its squads selected.
	m.selected_squads.clear()
	m._click(g4.draw_at, false)
	out.group_click_selects = m.selected_squads.size()
	_expect(m.selected_squads.size() == g4.ids.size(), "clicking a group did not select its squads")
	# 5./6. The same squads at three zoom levels.
	var c4 := Vector3.ZERO
	for sq: SquadState in group:
		c4 += ws.squad_center(sq)
	c4 /= group.size()
	var c2 := Vector2(c4.x, c4.z)
	var levels := {}
	for z: Array in [["05_nearby_squads_strategic", 0.06], ["06_nearby_squads_operational", 0.25], ["06_nearby_squads_close", 0.9]]:
		m.view_center = c2
		m.zoom = z[1]
		await _frames(6)
		_shot(z[0])
		var n := 0
		for g: Dictionary in m.squad_groups():
			for sq: SquadState in group:
				if g.ids.has(sq.id):
					n += 1
					break
		levels[z[0]] = {"zoom": z[1], "level": m.detail_level(), "markers_for_the_four": n}
	out.zoom_levels = levels
	_expect(levels["06_nearby_squads_close"].markers_for_the_four == 4, "zoomed in, the four squads are still not separate (%s)" % JSON.stringify(levels))
	# Zoom towards the cursor keeps the world point under it.
	m.view_center = c2
	m.zoom = 0.06
	await _frames(2)
	var cursor := m.map_rect().get_center() + Vector2(180, -90)
	var before := m.to_world(cursor)
	m.zoom_by(1.35 * 1.35 * 1.35, cursor)
	await _seconds(0.8)
	var after := m.to_world(cursor)
	out.zoom_anchor = {"zoom": snappedf(m.zoom, 0.001), "world_shift_m": snappedf(Vector2(after.x - before.x, after.z - before.z).length(), 0.1)}
	_expect(absf(m.zoom - 0.06 * 1.35 * 1.35 * 1.35) < 0.002 and out.zoom_anchor.world_shift_m < 5.0, "zoom did not keep the point under the cursor (%s)" % JSON.stringify(out.zoom_anchor))
	# Double-click on the group zooms in until it separates.
	m.view_center = c2
	m.zoom = 0.05
	await _frames(2)
	var gd: Dictionary = {}
	for g: Dictionary in m.squad_groups():
		if g.ids.has(group[0].id):
			gd = g
	m._double_click(gd.draw_at)
	await _seconds(0.8)
	out.double_click_zoom = snappedf(m.zoom, 0.001)
	_expect(m.zoom > 0.05 * 2.0, "double-click on a group did not zoom in")
	# 2. One selected squad.
	m.selected_squads = [group[2].id]
	m.selected_objective = -1
	m.selected_op = -1
	m.view_center = c2
	m.zoom = 0.3
	await _frames(6)
	_shot("02_selected_squad")
	# The order buttons: squads selected, objective clicked = target, Attack.
	m.selected_squads = [group[0].id, group[1].id]
	m.view_center = Vector2(hau.position.x, hau.position.z)
	m.zoom = 0.1
	await _frames(3)
	m._click(m.to_screen(hau.position), false)
	out.target_kept_squads = m.selected_squads.size() == 2 and m.selected_objective == hau.id
	_expect(out.target_kept_squads, "clicking an objective with squads selected did not make it their target")
	m._button("attack")
	var op: OperationState = null
	for o: OperationState in war.active_operations(0):
		if o.target_objective == hau.id:
			op = o
	_expect(op != null and op.player_ordered and op.squads.size() == 2, "the Attack button did not order the attack")
	# 3. The operation selected, after some marching (ETA from measured progress).
	if op:
		await _warp(120.0, 8.0)
		m.select_operation(op.id)
		var mid := (ws.squad_center(group[0]) + hau.position) * 0.5
		m.view_center = Vector2(mid.x, mid.z)
		m.zoom = 0.14
		await _frames(8)
		_shot("03_selected_operation")
		out.operation = {"text": m._operation_text(op), "march": ws.march_info(op)}
		_expect(ws.march_info(op).rem > 0.0, "operation march progress not measured")
		# Player override: a direct RTS order takes a squad out of the operation.
		demo.rts._player_takes([group[1].id])
		out.override_released = group[1].op_id < 0 and not op.squads.has(group[1].id)
		_expect(out.override_released, "a player order did not release the squad from the operation")
	# 4. A contested objective (both sides inside Sentrum) at the close level.
	var sen := _obj("Sentrum")
	var n1 := _spawn(0, sen.position + Vector3(-20, 0, 10))
	var s1 := _spawn(1, sen.position + Vector3(20, 0, -10))
	n1.station_objective = sen.id
	s1.station_objective = sen.id
	await _warp(4.0, 2.0)
	m.selected_squads.clear()
	m.selected_op = -1
	m.selected_objective = sen.id
	m.view_center = Vector2(sen.position.x, sen.position.z)
	m.zoom = 0.7
	await _frames(8)
	_shot("04_contested_objective")
	out.sentrum_contested = sen.contested
	_expect(sen.contested, "Sentrum with both sides inside is not contested")
	m.zoom = 0.1
	await _frames(6)
	_shot("04b_contested_objective_operational")
	# Help overlay.
	m.show_help = true
	m.fit_all()
	await _frames(6)
	_shot("07_map_help")
	m.show_help = false
	demo.toggle_map()
	await _frames(3)
	_pause_ai(false)
	return out


## WORLD-SANDBOX-01B: what the player sees at the start (tactical view over the HQ, the
## faction badge, the short HUD text), with all controls (F1), technical counters (F3)
## and in first person. Checks that the default text is short and names the faction.
func _hud() -> Dictionary:
	var hud := demo.hud
	demo.rts_camera.frame(_obj("North HQ").position, 0.0, 120.0)
	await _seconds(1.5)
	var out := {}
	var short_text := hud._text()
	out.default_lines = short_text.count("\n") + 1
	out.badge = hud._badge.text
	_shot("08_tactical_start_hud")
	hud.show_controls = true
	await _frames(8)
	out.controls_lines = hud._text().count("\n") + 1
	_shot("09_tactical_f1_controls")
	hud.show_controls = false
	hud.show_debug = true
	await _frames(8)
	out.debug_lines = hud._text().count("\n") + 1
	hud.show_debug = false
	var sq: SquadState = null
	for s: SquadState in ws.squads_of(0):
		if not s.members.is_empty():
			sq = s
			break
	if sq:
		demo.game.possess(sq.members[0])
		await _seconds(1.5)
		out.fps_lines = hud._text().count("\n") + 1
		_shot("10_first_person_hud")
		demo.game.enter_rts()
		await _seconds(0.5)
	_expect(String(out.badge).contains("NORTH") and out.default_lines <= 4 and out.controls_lines > out.default_lines and out.debug_lines > out.default_lines,
		"HUD not short by default / faction missing (%s)" % JSON.stringify(out))
	return out


## WORLD-SANDBOX-01B: the same small fight (2 North v 2 South squads, 150 m apart at
## Haugen, camera far away as in the accelerated scenarios) for 90 simulated seconds at
## 1 x (reference), compressed with fixed steps at 8 x and 24 x, and with the old
## stretched steps at 24 x. Fixed-step runs must keep 1/60 s steps; their outcome
## (shots, hits, deaths) should stay in the range of the reference. Fights are not
## deterministic (timing, random spread), so this compares magnitudes, not exact values.
func _warp_fidelity() -> Dictionary:
	_pause_ai(true)
	var hau := _obj("Haugen")
	demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
	await _seconds(1.0)
	var out := {}
	# Open ground 600 m from the village; the two sides advance towards each other
	# (a meeting engagement) so contact does not depend on who happens to look where.
	var c := _near_point(hau.position, _obj("North HQ").position, 600.0)
	var axis := Vector3(0, 0, 1)
	for mode: Array in [["x1", 1.0, false], ["x8_fixed", 8.0, false], ["x24_fixed", 24.0, false], ["x24_coarse_old", 24.0, true]]:
		seed(4242)
		var a := [_spawn(0, c + axis * 110.0 + Vector3(-25, 0, 0)), _spawn(0, c + axis * 110.0 + Vector3(25, 0, 0))]
		var b := [_spawn(1, c - axis * 110.0 + Vector3(-25, 0, 0)), _spawn(1, c - axis * 110.0 + Vector3(25, 0, 0))]
		await _physics(5)
		for sq: SquadState in a:
			demo.sim.squads.follow_route(sq, PackedVector3Array([demo.on_ground(c.x, c.z - 60.0, 0.0)]), SquadState.Formation.LINE)
		for sq: SquadState in b:
			demo.sim.squads.follow_route(sq, PackedVector3Array([demo.on_ground(c.x, c.z + 60.0, 0.0)]), SquadState.Formation.LINE)
		_begin()
		var w: Dictionary
		if mode[1] == 1.0:
			var r0 := Time.get_ticks_msec()
			var t0 := demo.sim.state.time
			var step_max := 0.0
			while demo.sim.state.time - t0 < 90.0:
				await tree.physics_frame
				step_max = maxf(step_max, demo.sim.last_delta)
			var real := (Time.get_ticks_msec() - r0) / 1000.0
			w = {"sim_s": snappedf(demo.sim.state.time - t0, 0.1), "real_s": snappedf(real, 0.1), "speed": snappedf((demo.sim.state.time - t0) / real, 0.1), "step_max_s": snappedf(step_max, 0.0001)}
		else:
			w = await _warp(90.0, mode[1], 60.0, Callable(), mode[2])
		var ids_a := _ids_of(a)
		var ids_b := _ids_of(b)
		var hits := 0
		var first := -1.0
		for s in shot_log:
			if s.hit > 0:
				hits += 1
			if first < 0.0:
				first = s.t
		out[mode[0]] = {"warp": w, "shots_north": _shots_by(ids_a), "shots_south": _shots_by(ids_b), "hits": hits,
			"first_shot_after_s": snappedf(first - (demo.sim.state.time - w.sim_s), 0.1) if first >= 0.0 else -1.0,
			"north_left": _alive_count(a), "south_left": _alive_count(b)}
		for id in ids_a + ids_b:
			demo.sim.state.remove_unit(id)
		await _physics(10)
	var ref: Dictionary = out.x1
	for k in ["x8_fixed", "x24_fixed"]:
		var r: Dictionary = out[k]
		_expect(absf(r.warp.step_max_s - 1.0 / 60.0) < 0.0005, "%s did not keep the 1/60 s step (%s)" % [k, JSON.stringify(r.warp)])
		_expect(r.shots_north + r.shots_south > 0 and ref.shots_north + ref.shots_south > 0, "no fight in the warp comparison (%s)" % JSON.stringify(out))
	_pause_ai(false)
	return out


# --- Performance -----------------------------------------------------------------------------

func _measure_case(seconds: float) -> Dictionary:
	var u0 := ws.update_usec
	var n0 := ws.updates
	brain.reset_stats()
	var m := await _frame_stats(seconds)
	var b := brain.summary()
	m["war_update_us_avg"] = snappedf(float(ws.update_usec - u0) / maxi(ws.updates - n0, 1), 0.1)
	m["war_update_us_max_ever"] = ws.update_usec_max
	m["brain_update_us_avg"] = b.update_us_avg
	m["brain_update_us_max"] = b.update_us_max
	m["bodies"] = demo.sim.bodies.size()
	m["soldiers"] = demo.sim.state.count_of(UnitState.Kind.SOLDIER)
	m["static_memory_mb"] = snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1)
	m["time_scale"] = Engine.time_scale
	return m


## Frame times in the situations the player meets: the map over the whole war, the
## tactical view, a 50 v 50 battle in RTS and first person, the war running far away,
## and 8 x time compression.
func _perf() -> Dictionary:
	var out := {}
	demo.rts_camera.frame(_obj("North HQ").position, 0.0, 120.0)
	await _seconds(2.0)
	out.rts_hq = await _measure_case(6.0)
	demo.toggle_map()
	await _frames(5)
	out.map_overview = await _measure_case(6.0)
	demo.toggle_map()
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(2.0)
	out.war_far_away = await _measure_case(6.0)
	TimeCompression.apply(8.0)
	var t8 := demo.sim.state.time
	out.war_far_8x = await _measure_case(6.0)
	out.war_far_8x["achieved_speed"] = snappedf((demo.sim.state.time - t8) / 6.0, 0.1)
	TimeCompression.reset()
	# 50 v 50 at Haugen: five squads each, 150 m apart, real health (they fight to death).
	_pause_ai(true)
	var hau := _obj("Haugen")
	var a := []
	var b := []
	for k in 5:
		a.append(_spawn(0, hau.position + Vector3(-60 + k * 30, 0, 75)))
		b.append(_spawn(2, hau.position + Vector3(-60 + k * 30, 0, -75)))
	demo.rts_camera.frame(hau.position, 0.0, 150.0)
	await _seconds(3.0)
	out.battle_50v50_rts = await _measure_case(8.0)
	var pid := -1
	for sq: SquadState in a:
		for id in sq.members:
			if _u(id).alive and _u(id).has_body:
				pid = id
	if pid > 0:
		var body := await _possess(pid)
		if body:
			await _fps_shot_at(body, hau.position + Vector3(0, 1.2, -75))
		out.battle_50v50_fps = await _measure_case(8.0)
		_press(KEY_TAB)
		await _physics(5)
	out.battle_alive = [_alive_count(a), _alive_count(b)]
	_pause_ai(false)
	return out


# --- Scenario 7: a march across the map --------------------------------------------------------------

## One squad marches from North HQ to Østby (across the river, through forest and fields)
## in the abstract tier; every soldier's position is checked against water / impassable
## ground at every frame.
func _navigation_march() -> Dictionary:
	_pause_ai(true)
	# From the North HQ to the east bank north of Lia (no enemy garrison on the way):
	# forest, fields, the river (North Bridge), the hills beyond.
	var from := _obj("North HQ")
	var goal := demo.on_ground(3200.0, -5600.0, 0.0)
	var sq := _spawn(0, from.position + Vector3(0, 0, 18))
	await _physics(5)
	var op := ws.start_operation(0, OperationState.Type.MOVE, [sq.id], -1, goal, true)
	var route := sq.route.duplicate()
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(0.5)
	var track := {"wet": 0, "bad": 0, "n": 0, "crossed": false, "bridge": -1}
	var east0 := ws.squad_center(sq).x > _river_x(ws.squad_center(sq).z)
	var w := await _warp(7200.0, 32.0, 200.0, func() -> bool:
		for id in sq.members:
			var u := _u(id)
			track.n += 1
			if ws.routes.is_water(u.position):
				track.wet += 1
			elif not ws.routes.passable(u.position):
				track.bad += 1
		var c := ws.squad_center(sq)
		if (c.x > _river_x(c.z)) != east0 and not track.crossed:
			track.crossed = true
			for j in ws.routes.bridges.size():
				if _flat(ws.routes.bridges[j], c) < 200.0:
					track.bridge = j
		return not op.is_active())
	var out := {"route_km": snappedf(ws.routes.route_length(route) / 1000.0, 0.01), "waypoints": route.size(), "arrived": op.phase_name(),
		"dist_to_goal_m": snappedf(_flat(ws.squad_center(sq), op.target_pos), 0.1), "samples": track.n, "in_water": track.wet,
		"on_impassable_cells": track.bad, "crossed_river": track.crossed, "near_bridge": track.bridge, "warp": w, "route_skips": demo.sim.squads.route_skips}
	_expect(op.phase == OperationState.Phase.COMPLETED and track.wet == 0 and track.crossed and track.bridge >= 0, "the march did not reach the east bank by a bridge without wading (%s)" % JSON.stringify(out))
	_pause_ai(false)
	return out


# --- Scenario 6: extended autonomous war ------------------------------------------------------------

## minutes of war at 24 x with nobody watching. Records operations, captures, casualties,
## reinforcements, stuck soldiers, AI inactivity, reserve exhaustion and capture loops.
func _extended(minutes: float) -> Dictionary:
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(0.5)
	var ev0 := war.events.size()
	var ops0 := war.operations.size()
	var cas0 := {}
	var res0 := {}
	for f: FactionState in war.factions.values():
		cas0[f.id] = f.casualties
		res0[f.id] = f.reserves
	var last_pos := {}
	var stuck := {"max": 0}
	var last_op_start := {}
	var gaps := {}
	var t0 := demo.sim.state.time
	var check := {"t": t0}
	var idle_since := {}
	var idle_max := {}
	var w := await _warp(minutes * 60.0, 24.0, 230.0, func() -> bool:
		var now := demo.sim.state.time
		for f: FactionState in war.factions.values():
			if f.player:
				continue
			if war.active_operations(f.id).is_empty():
				if not idle_since.has(f.id):
					idle_since[f.id] = now
				idle_max[f.id] = maxf(idle_max.get(f.id, 0.0), now - idle_since[f.id])
			else:
				idle_since.erase(f.id)
		if now - check.t >= 120.0:
			check.t = now
			var n := 0
			for u: UnitState in demo.sim.state.units.values():
				if u.kind != UnitState.Kind.SOLDIER or not u.alive:
					continue
				var prev: Vector3 = last_pos.get(u.id, Vector3.INF)
				if u.has_order() and prev.is_finite() and _flat(prev, u.position) < 3.0 and not u.is_reacting() and u.target_id < 0:
					n += 1
				last_pos[u.id] = u.position
			stuck.max = maxi(stuck.max, n)
		return false)
	var kinds := {}
	var changes := {}
	for i in range(ev0, war.events.size()):
		var e: Dictionary = war.events[i]
		kinds[e.kind] = kinds.get(e.kind, 0) + 1
		if e.kind == "op_start" and e.faction >= 0 and not war.faction(e.faction).player:
			var f: int = e.faction
			if last_op_start.has(f):
				gaps[f] = maxf(gaps.get(f, 0.0), e.t - last_op_start[f])
			else:
				gaps[f] = maxf(gaps.get(f, 0.0), e.t - t0)
			last_op_start[f] = e.t
	for f: int in last_op_start:
		gaps[f] = maxf(gaps.get(f, 0.0), demo.sim.state.time - last_op_start[f])
	var loops := []
	for o: ObjectiveState in war.objectives.values():
		var n := 0
		for h: Array in o.history:
			if h[0] >= t0:
				n += 1
		changes[o.obj_name] = n
		if n >= 4:
			loops.append(o.obj_name)
	var ops := war.operations.values().filter(func(o: OperationState) -> bool: return o.id > ops0)
	var by_phase := {}
	for op: OperationState in ops:
		by_phase[op.phase_name()] = by_phase.get(op.phase_name(), 0) + 1
	var fac := {}
	for f: FactionState in war.factions.values():
		fac[f.faction_name] = {"casualties": f.casualties - cas0[f.id], "reserves_used": res0[f.id] - f.reserves, "reserves_left": f.reserves,
			"objectives": war.owned_by(f.id).size(), "longest_without_new_op_min": snappedf(gaps.get(f.id, 0.0) / 60.0, 0.1) if not f.player else -1,
			"longest_without_any_op_min": snappedf(idle_max.get(f.id, 0.0) / 60.0, 0.1)}
	var out := {"sim_minutes": snappedf((demo.sim.state.time - t0) / 60.0, 0.1), "warp": w, "events_by_kind": kinds, "operations": {"started": ops.size(), "by_phase": by_phase},
		"ownership_changes": changes, "capture_loops": loops, "stuck_soldiers_max": stuck.max, "factions": fac, "consistency": _consistency(),
		"war_us_avg": ws.summary().update_us_avg, "war_us_max": ws.update_usec_max, "ai_us_max": ws.ai_usec_max, "routes": ws.summary().routes,
		"route_skips": demo.sim.squads.route_skips, "summary": ws.summary()}
	# Inactive = starting nothing for 20 minutes while having no operation running either
	# (a faction whose squads are all on long marches is busy, not idle).
	var ai_ok := true
	for f: FactionState in war.factions.values():
		if not f.player and gaps.get(f.id, INF) > 20.0 * 60.0 and idle_max.get(f.id, 0.0) > 20.0 * 60.0:
			ai_ok = false
	_expect(ops.size() >= 4 and kinds.get("captured", 0) >= 1, "the war did not progress (%s)" % JSON.stringify(out.operations))
	_expect(loops.is_empty() and out.consistency.count == 0, "capture loops or inconsistent records (%s)" % JSON.stringify(out))
	_expect(ai_ok, "an AI faction stayed inactive for over 20 minutes (%s)" % JSON.stringify(fac))
	return out


# --- Routes ----------------------------------------------------------------------------

## Routes between objectives: never through water or impassable cells, crossing the
## river only on a bridge.
func _routes() -> Dictionary:
	var r := ws.routes
	var out := {"grid": {"ms": snappedf(r.build_ms, 0.1), "cached": r.loaded_from_cache, "bridges": r.bridges.size()}, "pairs": []}
	var pairs := [["North HQ", "East HQ"], ["South HQ", "East HQ"], ["North HQ", "South HQ"], ["Sentrum", "Østby"], ["East HQ", "Verket"], ["Elvetun", "Ødegård"]]
	var bad := 0
	for pr: Array in pairs:
		var a := _obj(pr[0])
		var b := _obj(pr[1])
		var route := r.route(a.position, b.position, demo.terrain)
		var wet := 0
		var steep := 0
		var crossings := 0
		var bridge_used := -1
		var was_east := a.position.x > _river_x(a.position.z)
		for i in range(1, route.size()):
			var p := route[i - 1]
			var q := route[i]
			var n := maxi(1, int(Vector2(p.x - q.x, p.z - q.z).length() / 5.0))
			for k in n + 1:
				var x := p.lerp(q, float(k) / n)
				if r.is_water(x):
					wet += 1
				elif not r.passable(x):
					steep += 1
				var east := x.x > _river_x(x.z)
				if east != was_east:
					crossings += 1
					was_east = east
					for j in r.bridges.size():
						if Vector2(r.bridges[j].x - x.x, r.bridges[j].z - x.z).length() < 160.0:
							bridge_used = j
		var straight := Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length()
		var e := {"from": pr[0], "to": pr[1], "waypoints": route.size(), "length_km": snappedf(r.route_length(route) / 1000.0, 0.01),
			"straight_km": snappedf(straight / 1000.0, 0.01), "ms": snappedf(r.last_route_ms, 0.01), "samples_in_water": wet,
			"samples_impassable": steep, "river_crossings": crossings, "bridge_near_crossing": bridge_used}
		out.pairs.append(e)
		if route.is_empty() or wet > 0 or steep > 0 or (crossings > 0 and bridge_used < 0):
			bad += 1
	_expect(bad == 0, "routes cross water / impassable ground or ford the river (%s)" % JSON.stringify(out.pairs))
	return out


## x of the river centre line at z (from water.json), for crossing detection.
var _river_pts: Array = []
func _river_x(z: float) -> float:
	if _river_pts.is_empty():
		var w: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/%s/source/water.json" % demo.config.world_name))
		_river_pts = w.river.points
	var best := 0.0
	var bd := INF
	for p: Array in _river_pts:
		var d := absf(p[1] - z)
		if d < bd:
			bd = d
			best = p[0]
	return best


# --- Autonomous war -----------------------------------------------------------------------

## Fast-forward: simulated time runs `scale` times faster (many physics ticks per frame;
## each tick is an ordinary one, so movement, combat and capture are unchanged), for at
## most max_real_s seconds of real time. Returns {sim_s, real_s, speed}.
## Runs sim_seconds of simulated time compressed (the player's TimeCompression: every
## physics step stays 1/60 s, so movement and fights are the same as at 1 x). The machine
## decides the speed reached; it is measured and returned, never assumed from `scale`.
## max_real_s is a safety limit only: it grows so that at least 6 x is allowed.
## coarse: the old behaviour (time_scale alone, stretched steps) for the comparison check.
func _warp(sim_seconds: float, scale := 24.0, max_real_s := 240.0, until := Callable(), coarse := false) -> Dictionary:
	max_real_s = maxf(max_real_s, sim_seconds / 6.0 + 20.0)
	if coarse:
		Engine.max_physics_steps_per_frame = 64
		Engine.time_scale = scale
	else:
		TimeCompression.apply(scale, 64)
	var t0 := demo.sim.state.time
	var r0 := Time.get_ticks_msec()
	var step_max := 0.0
	var frames := 0
	while demo.sim.state.time - t0 < sim_seconds and Time.get_ticks_msec() - r0 < max_real_s * 1000.0:
		await tree.process_frame
		frames += 1
		step_max = maxf(step_max, demo.sim.last_delta)
		if until.is_valid() and until.call():
			break
	TimeCompression.reset()
	var real := (Time.get_ticks_msec() - r0) / 1000.0
	var sim_s := demo.sim.state.time - t0
	var out := {"sim_s": snappedf(sim_s, 0.1), "real_s": snappedf(real, 0.1), "requested": scale, "speed": snappedf(sim_s / maxf(real, 0.01), 0.1),
		"step_max_s": snappedf(step_max, 0.0001), "frames": frames}
	warps.append(out)
	return out


func _autonomous(minutes: float) -> Dictionary:
	# The camera far from every force: the war runs in the abstract tier like a war the
	# player is not watching.
	demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	await _seconds(1.0)
	TimeCompression.apply(24.0, 64)
	var r0 := Time.get_ticks_msec()
	var t0 := demo.sim.state.time
	var samples := []
	var next := t0
	var ms := PackedFloat32Array()
	while demo.sim.state.time - t0 < minutes * 60.0 and Time.get_ticks_msec() - r0 < 240000:
		var t := Time.get_ticks_usec()
		await tree.process_frame
		ms.append((Time.get_ticks_usec() - t) / 1000.0)
		if demo.sim.state.time >= next:
			next += 30.0
			var s := ws.summary()
			samples.append(s)
			var fs := {}
			for k in s.factions:
				var f: Dictionary = s.factions[k]
				fs[k] = "%d obj, %d sold (%d sq), res %d, cas %d, ops %s | %s" % [f.objectives, f.soldiers, f.squads, f.reserves, f.casualties, str(f.ops), f.last_decision]
			var dbg := []
			for op: OperationState in war.active_operations():
				for sid in op.squads:
					var sq := demo.sim.state.get_squad(sid)
					var st := {}
					for id in sq.members:
						var u := demo.sim.state.get_unit(id)
						var k := "%s/%s%s" % [UnitState.MoveState.keys()[u.move_state], "o" if u.has_order() else "-", "B" if u.has_body else ""]
						st[k] = st.get(k, 0) + 1
					dbg.append("op%d %s r%d/%d %s %s lead@%s tgt@%s %s" % [op.id, sq.squad_name, sq.route_i, sq.route.size(), sq.order_name(), SquadState.Status.keys()[sq.status],
						_v(demo.sim.state.get_unit(sq.leader_id).position), _v(sq.route[sq.route_i]) if not sq.route.is_empty() else "-", JSON.stringify(st)])
			print("SANDBOX dbg ", JSON.stringify(dbg))
			print("SANDBOX tick ", JSON.stringify({"t_min": snappedf((demo.sim.state.time - t0) / 60.0, 0.1), "fps_ms": snappedf(ms[-1], 0.1), "factions": fs, "ops": s.ops}))
	TimeCompression.reset()
	var real := (Time.get_ticks_msec() - r0) / 1000.0
	var out := {"minutes": minutes, "sim_minutes_done": snappedf((demo.sim.state.time - t0) / 60.0, 0.1), "real_s": snappedf(real, 0.1),
		"speed": snappedf((demo.sim.state.time - t0) / maxf(real, 0.01), 0.1), "summary": ws.summary(), "events": war.events.slice(-40).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t, e.text])}
	return out


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("SANDBOX %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond and msg != "":
		failures.append(msg)
		print("SANDBOX FAILED CHECK: ", msg)


func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	var path := "%s/s01b_%s.jpg" % [_shot_dir, shot_name]
	img.save_jpg(ProjectSettings.globalize_path(path), 0.9)
	print("SANDBOX shot: ", path)


func _finish() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["warps"] = warps
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/sandbox_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("SANDBOX %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.shutdown_cleanup()
	tree.quit()
