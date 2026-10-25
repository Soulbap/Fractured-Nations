## GAMEPLAY-05 quality review checks in the real game on ref_20km: diagnostics of a saved game, the fixes of the review and the
## visual tour used for the before / after screenshots.
##
##   Godot.exe --path . --fullscreen --log-file g5.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --gameplay05-test [--shots] --only <checks> [--shot-dir=res://docs/gameplay05] [--shot-tag=after]
##
## p_state (with --continue: the save of the last playthrough) prints the player's squads, blocked soldiers and the objectives.
## Prints "G5 <check> <json>", writes res://benchmarks/raw/gameplay05_test.json and (with --shots) PNGs into the shot folder.
class_name Gameplay05SelfTest
extends Gameplay04SelfTest

const CHECKS5: Array[String] = ["p_state", "p_watch", "u_markers", "u_capture_name", "u_post_block", "u_strength", "v_tour", "q_perf", "u_bodies", "b_build_resume", "n_edge", "u_capture", "u_orders", "n_roads", "p_veg"]
## Suffix of the tour's screenshots (before / after a visual change).
var shot_tag := ""
## p_watch: time compression (--watch-speed=8).
var watch_speed := 4.0


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/gameplay05"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
		elif a.begins_with("--watch-speed="):
			watch_speed = float(a.trim_prefix("--watch-speed="))
		elif a.begins_with("--shot-tag="):
			shot_tag = a.trim_prefix("--shot-tag=")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	tree.create_timer(1200.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	for n in CHECKS5:
		if only.has(n):
			_log(n, await call("_" + n))
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("G5 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/gameplay05_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("G5 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- Diagnostics -------------------------------------------------------------------------------------------------------

## The player's squads (members, fallen, strength as the UI shows it, status, blocked soldiers with their posts and why) and
## the objectives within 2.5 km of them.
func _p_state() -> Dictionary:
	var out := {"t": snappedf(demo.sim.state.time, 0.1), "squads": [], "objectives": [], "opps": demo.sim.war.opps.open().map(func(o: Dictionary) -> String: return o.title)}
	var centres := []
	for sq: SquadState in _player_squads():
		var c := demo.sim.war.squad_center(sq)
		centres.append(c)
		var bl := []
		for uid in sq.members:
			var u := demo.sim.state.get_unit(uid)
			if u.move_state == UnitState.MoveState.BLOCKED or sq.blocked.has(uid):
				bl.append({"id": uid, "pos": _xz2(u.position), "target": _xz2(u.order_target), "post": _xz2(u.post_pos) if u.post_pos.is_finite() else [],
					"slot": u.fort_slot, "in_slot": u.fort_pos.is_finite(), "nav": u.nav_reason, "order": u.order, "move": u.move_state})
		var sn := SquadPanel.strength(sq)
		out.squads.append({"name": sq.squad_name, "members": sq.members.size(), "fallen": sq.fallen.size(), "ui": "%d/%d" % [sn.x, sn.y],
			"status": sq.status, "order": sq.order, "tactic": sq.tactic_name(), "garrison": sq.garrison_base, "blocked": bl, "row": demo.hud.squad_panel.row_text(sq)})
	for o: ObjectiveState in _war().all_objectives():
		for c: Vector3 in centres:
			if WarSim._flat(c, o.position) < 2500.0:
				out.objectives.append({"name": o.obj_name, "owner": o.owner, "capture": o.capture_faction, "progress": snappedf(o.capture_progress, 0.01),
					"contested": o.contested, "presence": o.presence})
				break
	return out


## Runs the loaded game on for 240 simulated seconds and records every soldier of the player that reports BLOCKED (first time,
## where, what for), then the state at the end.
func _p_watch() -> Dictionary:
	var seen := {}
	# The camera with the first squad (as in the playthrough): a garrison far from it walks in the far tier.
	await _frame(demo.sim.war.squad_center(_player_squads()[0]), 160.0)
	await _physics(30)
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(watch_speed)
	while demo.sim.state.time - t0 < 240.0:
		await _physics(10)
		for sq: SquadState in _player_squads():
			for uid in sq.members:
				var u := demo.sim.state.get_unit(uid)
				if u.move_state == UnitState.MoveState.BLOCKED and not seen.has(uid):
					seen[uid] = {"t": snappedf(demo.sim.state.time - t0, 0.1), "squad": sq.squad_name, "tactic": sq.tactic_name(), "pos": _xz2(u.position),
						"target": _xz2(u.order_target), "post": _xz2(u.post_pos), "slot": u.fort_slot, "nav": u.nav_reason,
						"near": demo.sim.tier_of(u) if demo.sim.has_method("tier_of") else -1, "react": u.react_state}
	CoreDemo.apply_time_scale(1.0)
	var out := _p_state()
	out["blocked_seen"] = seen
	return out


# --- Fixes ---------------------------------------------------------------------------------------------------------------

## A defending soldier whose post cannot be reached (inside a command post's footprint): he is sent again a bounded number of
## times, then holds where he got to; the squad does not stay BLOCKED. Fails if the post was reachable (nothing was tested).
func _u_post_block() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	var cp := _player_cp()
	var c := demo.sim.war.squad_center(sq)
	demo.sim.tactics.order_tactic([sq.id], SquadState.Tactic.DEFEND, c)
	await _until(func() -> bool: return sq.tactic_phase != 0, 30.0, 4.0)
	var u: UnitState = null
	for uid in sq.members:
		if uid != sq.leader_id:
			u = demo.sim.state.get_unit(uid)
			break
	var given0 := demo.sim.tactics.posts_given_up
	demo.sim.state.issue_move(u.id, cp.position, false)
	u.post_pos = cp.position
	u.fort_slot = ""
	var was_blocked := false
	var partial_s := 0.0
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(4.0)
	while demo.sim.state.time - t0 < 90.0:
		var t := demo.sim.state.time
		await _physics(10)
		was_blocked = was_blocked or u.move_state == UnitState.MoveState.BLOCKED
		if not u.post_pos.is_finite() and not _marks.has("post_lost"):
			_marks["post_lost"] = {"t": snappedf(demo.sim.state.time - t0, 0.1), "move": u.move_state, "order": u.order, "tactic": sq.tactic_name(), "phase": sq.tactic_phase,
				"detached": sq.is_detached(u.id), "why": sq.tactic_why}
		if sq.status == SquadState.Status.PARTIAL:
			partial_s += demo.sim.state.time - t
		if was_blocked and demo.sim.tactics.posts_given_up > given0 and u.move_state != UnitState.MoveState.BLOCKED:
			break
	CoreDemo.apply_time_scale(1.0)
	await _physics(30)
	var out := {"was_blocked": was_blocked, "given_up": demo.sim.tactics.posts_given_up - given0, "partial_s": snappedf(partial_s, 0.1),
		"status": sq.status, "row": demo.hud.squad_panel.row_text(sq), "post_m": snappedf(WarSim._flat(u.post_pos, u.position), 0.1),
		"t_s": snappedf(demo.sim.state.time - t0, 0.1), "nav": u.nav_reason, "post_lost": _marks.get("post_lost", {})}
	_expect(was_blocked, "u_post_block: the post inside the command post was reached - nothing tested: %s" % str(out))
	_expect(out.given_up >= 1 and sq.status != SquadState.Status.PARTIAL and u.move_state != UnitState.MoveState.BLOCKED and out.post_m < 1.0,
		"u_post_block: the soldier did not settle short of the post: %s" % str(out))
	return out


## "a/b" strength: the dead leave the members, so a squad of 8 that lost 3 reads 5/8 (UI-01C read 2/5); a replenished squad reads
## full strength.
func _u_strength() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	var n0 := sq.members.size()
	var killed := []
	for uid in sq.members.duplicate().slice(1, 4):
		demo.sim.combat.apply_damage(uid, 1000.0, LineOfFire.Zone.BODY, -1)
		killed.append(uid)
	await _physics(10)
	var sn := SquadPanel.strength(sq)
	var out := {"members0": n0, "members": sq.members.size(), "fallen": sq.fallen.size(), "strength": [sn.x, sn.y], "row": demo.hud.squad_panel.row_text(sq)}
	_expect(sn == Vector2i(n0 - 3, n0), "u_strength: %s" % str(out))
	return out


## Equipment markers: six fallen stashes 4-20 m apart (as after a fight) and a find with an unregistered type read as two markers with a summary,
## not seven overlapping labels; the records are untouched.
func _u_markers() -> Dictionary:
	var pf := _war().player_faction
	var sq: SquadState = _player_squads()[0]
	var c := demo.sim.war.squad_center(sq) + Vector3(40, 0, -30)
	var eq := demo.sim.war.equip
	var n0 := _war().stashes.size()
	for i in 6:
		var s := eq.add_stash("Fallen soldiers' equipment", "fallen", demo.on_ground(c.x + i * 4.0, c.z + (i % 3) * 3.5, 0.0), {"rifle": 1 + i % 2}, 4.0 + i)
		s["known"] = [pf]
	var find := eq.add_stash("Verket yard cache", "cache", demo.on_ground(c.x + 120.0, c.z, 0.0), {"dmr": 1}, 20.0)
	find["known"] = [pf]
	await _frame(c + Vector3(60, 0, 0), 120.0, 0.0)
	await _seconds(0.5)
	var groups: Array = demo.hud.economy.stash_groups(demo.get_viewport().get_camera_3d(), pf)
	var titles := groups.map(func(g: Dictionary) -> String: return g.title)
	var fresh := groups.filter(func(g: Dictionary) -> bool: return not (g.new_types as Array).is_empty())
	_png("u_markers" + ("_" + shot_tag if shot_tag != "" else ""))
	demo.toggle_map()
	demo.strategic_map.zoom = 0.6
	demo.strategic_map.focus_on(c)
	await _seconds(1.0)
	_png("u_markers_map" + ("_" + shot_tag if shot_tag != "" else ""))
	demo.toggle_map()
	var out := {"groups": groups.size(), "titles": titles, "new": fresh.map(func(g: Dictionary) -> Array: return g.new_types), "stashes": _war().stashes.size() - n0}
	_expect(groups.size() == 2 and out.stashes == 7, "u_markers: %s" % str(out))
	_expect(titles.any(func(t: String) -> bool: return t.begins_with("FALLEN EQUIPMENT ×6")), "u_markers: no summary of the fallen: %s" % str(out))
	_expect(fresh.size() == 1, "u_markers: the unregistered DMR is not flagged: %s" % str(out))
	return out


## A captured base with a generated name takes the new owner's name; the events name both.
func _u_capture_name() -> Dictionary:
	var pf := _war().player_faction
	var bs := demo.sim.logistics.bases
	var sq: SquadState = _player_squads()[0]
	var at := _spot(&"command_post", demo.sim.war.squad_center(sq) + Vector3(0, 0, 300), [0.0, 30.0, 60.0, 90.0], 12)
	var st := _add_built(&"command_post", at, Vector3(0, 0, 1), 1)
	var b: Dictionary = demo.sim.state.construction.bases.get(st.base_id, {})
	var before := String(b.get("name", ""))
	var res := bs.capture_base(st.base_id, pf)
	var after := String(b.get("name", ""))
	var out := {"before": before, "after": after, "ok": res.get("ok", false)}
	_expect(before.begins_with("South base") and after.begins_with("North base") and res.get("ok", false), "u_capture_name: %s" % str(out))
	return out


# --- Visual tour -----------------------------------------------------------------------------------------------------------

## Fixed views of the New Game start (landscape low and far, overhead village, a small base, the squad close up, first person)
## for before / after screenshots under the same conditions: same place, camera, time of day; the frame rate of each view is
## measured over 2 s without vsync. Names end in the --shot-tag.
func _v_tour() -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var pf := _war().player_faction
	var sq: SquadState = _player_squads()[0]
	var start := demo.sim.war.squad_center(sq)
	var cpo := _objective("Moen checkpoint")
	# A small base 60 m east of the start, built at once (the same structures in every run).
	var base := start + Vector3(70, 0, 10)
	var placed := []
	for e: Array in [[&"command_post", Vector3(0, 0, 0)], [&"supply_depot", Vector3(-22, 0, 10)], [&"guard_tower", Vector3(18, 0, -18)],
			[&"sandbag_fighting_position", Vector3(10, 0, -26)], [&"fighting_position", Vector3(-14, 0, -24)], [&"mg_emplacement", Vector3(26, 0, 4)]]:
		var p := _spot(e[0], base + (e[1] as Vector3), [0.0, 6.0, 12.0], 8)
		if p.is_finite():
			var st := _add_built(e[0], p, Vector3(0, 0, -1), pf)
			if st:
				placed.append(String(e[0]))
	demo.sim.brain.enabled = false
	var views := [
		["v_land_low", start + Vector3(0, 0, -30), 0.0, 60.0, 9.0],
		["v_land_far", start + Vector3(0, 0, -150), 0.0, 200.0, 14.0],
		["v_overhead", cpo.position if cpo else start, 0.0, 160.0, -1.0],
		["v_base", base, 0.6, 55.0, 30.0],
		["v_squad", start, 2.4, 12.0, 14.0],
	]
	var fps := {}
	var tag := ("_" + shot_tag) if shot_tag != "" else ""
	for v: Array in views:
		var rig := demo.rts_camera
		await _frame(v[1], v[3], v[2])
		if float(v[4]) > 0.0:
			rig.pitch_offset = deg_to_rad(float(v[4])) - rig._base_pitch()
			rig._update_transform()
		await _seconds(2.5)
		fps[v[0]] = await _measure_fps()
		_png(String(v[0]) + tag)
		rig.pitch_offset = 0.0
	demo.game.possess(sq.leader_id)
	await _seconds(2.5)
	fps["v_fps"] = await _measure_fps()
	_png("v_fps" + tag)
	demo.game.enter_rts()
	# The interface: the build menu over the base, the strategic map.
	await _frame(base, 70.0, 0.6)
	_press(KEY_B)
	await _seconds(1.0)
	_png("v_build" + tag)
	_press(KEY_ESCAPE)
	await _seconds(0.5)
	demo.toggle_map()
	await _seconds(1.5)
	_png("v_map" + tag)
	demo.toggle_map()
	demo.sim.brain.enabled = true
	return {"fps": fps, "structures": placed, "look": WorldLook.active}


## Performance of a realistic workload: the opening assault on the Moen checkpoint at normal speed, watched from the tactical
## camera over the fight, then the same 30 s from first person. Frame times (avg, p95, p99, max: the spikes), WorldSim cost per
## tick and system, CombatBrain, render counters and memory. vsync off.
func _q_perf() -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var sq: SquadState = _player_squads()[0]
	var cpo := _objective("Moen checkpoint")
	demo.rts.select_squads([sq.id])
	demo.rts.order_tactic(SquadState.Tactic.ASSAULT, cpo.position)
	# March in at 4x until the first shot, then measure at 1x.
	var shot := {"n": 0}
	var counter := func(_s: Dictionary) -> void: shot.n += 1
	demo.sim.state.shot_fired.connect(counter)
	CoreDemo.apply_time_scale(4.0)
	var t0 := demo.sim.state.time
	while shot.n == 0 and demo.sim.state.time - t0 < 200.0:
		await _physics(10)
	CoreDemo.apply_time_scale(1.0)
	var out := {"first_shot_s": snappedf(demo.sim.state.time - t0, 0.1)}
	await _frame(demo.sim.war.squad_center(sq).lerp(cpo.position, 0.5), 90.0, 0.0)
	out["rts_fight"] = await _sample_frames(40.0)
	demo.game.possess(sq.leader_id)
	out["fps_fight"] = await _sample_frames(30.0)
	demo.game.enter_rts()
	out["shots"] = shot.n
	demo.sim.state.shot_fired.disconnect(counter)
	out["units"] = demo.sim.state.units.size()
	out["stashes"] = _war().stashes.size()
	return out


## Frame times over `seconds` real seconds plus the simulation's cost in that window.
func _sample_frames(seconds: float) -> Dictionary:
	var times := PackedFloat32Array()
	var tk0 := demo.sim.tick_usec.duplicate()
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	var probe := _spike_probe()
	var spikes := []
	while Time.get_ticks_msec() < t_end:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		times.append(ms)
		last = now
		# GAMEPLAY-05B: what happened in a frame over 33 ms (deltas of the counters since the previous frame).
		var p2 := _spike_probe()
		if ms > 33.3 and spikes.size() < 40:
			var e := {"ms": snappedf(ms, 0.1)}
			for k in p2:
				if p2[k] is float or p2[k] is int:
					var dv: float = float(p2[k]) - float(probe.get(k, 0))
					if absf(dv) > 0.0001:
						e[k] = snappedf(dv, 0.01)
			e["process_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01)
			e["physics_ms"] = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)
			e["veg_worst_ms"] = p2.veg_worst_ms
			e["route_ms"] = p2.route_ms
			spikes.append(e)
		probe = p2
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	var over := 0
	for x in sorted:
		sum += x
		if x > 33.3:
			over += 1
	var tk1 := demo.sim.tick_usec
	var ticks := maxi(int(tk1.ticks) - int(tk0.ticks), 1)
	var per := {}
	for k in ["abstract", "squads", "tactics", "war", "brain", "combat", "vehicles"]:
		per[k] = snappedf(float(int(tk1[k]) - int(tk0[k])) / ticks, 0.1)
	return {"frames": n, "ms_avg": snappedf(sum / maxi(n, 1), 0.01), "ms_p95": snappedf(sorted[int(n * 0.95)], 0.01), "ms_p99": snappedf(sorted[int(n * 0.99)], 0.01),
		"ms_max": snappedf(sorted[n - 1], 0.01), "frames_over_33ms": over, "sim_us_per_tick": per,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "vram_mb": roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"static_mb": roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), "spikes": spikes}


## Counters read every frame by the spike recorder: WorldSim cost per system (us, cumulative) and ticks, navmesh bakes,
## vegetation chunks and the worst chunk activation this frame, merged character LODs built, route planning this frame,
## render pipeline compilations (shaders), nodes, bodies.
func _spike_probe() -> Dictionary:
	var t: Dictionary = demo.sim.tick_usec
	var veg = demo.vegetation
	var worst := 0.0
	if veg and "_worst_drain_ms" in veg:
		worst = float(veg._worst_drain_ms)
		veg._worst_drain_ms = 0.0
	return {"ticks": int(t.ticks), "us_abstract": int(t.abstract), "us_squads": int(t.squads), "us_tactics": int(t.tactics), "us_war": int(t.war),
		"us_brain": int(t.brain), "us_combat": int(t.combat), "us_vehicles": int(t.vehicles), "navmesh_bakes": demo.detail.bake_count if demo.detail else 0,
		"veg_chunks": veg.chunks.size() if veg else 0, "veg_worst_ms": snappedf(worst, 0.01), "lod_merges": InfantryLodMerge._cache.size(),
		"route_ms": snappedf(demo.sim.routing.last_frame_ms, 0.01), "bodies": demo.sim.bodies.size(),
		"pipe_surface": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)), "pipe_mesh": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)),
		"pipe_draw": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)), "pipe_spec": int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}


## Frames per second over two real seconds.
func _measure_fps() -> float:
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await tree.create_timer(2.0, true, false, true).timeout
	return snappedf((Engine.get_frames_drawn() - f0) * 1000.0 / maxf(Time.get_ticks_msec() - t0, 1.0), 0.1)


## Diagnostic: the squad seen from 12 m (as v_squad): for every soldier its role, weapon, body or proxy, and what of it is
## visible (mesh instances, their visible flags, LOD ranges, the body's position against the record).
func _u_bodies() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	var start := demo.sim.war.squad_center(sq)
	await _frame(start, 12.0, 2.4)
	demo.rts_camera.pitch_offset = deg_to_rad(14.0) - demo.rts_camera._base_pitch()
	demo.rts_camera._update_transform()
	await _seconds(3.0)
	var cam := demo.get_viewport().get_camera_3d()
	var out := []
	for uid in sq.members:
		var u := demo.sim.state.get_unit(uid)
		var e := {"id": uid, "role": String(u.role), "weapon": String(u.weapon_id), "sec": String(u.sec_id), "cam_m": snappedf(cam.global_position.distance_to(u.position), 0.1)}
		var b: Node3D = demo.sim.bodies.get(uid)
		var px: Node3D = demo.sim.proxies.get(uid)
		e["body"] = b != null
		e["proxy"] = px != null
		var node: Node3D = b if b else px
		if node:
			e["visible"] = node.is_visible_in_tree()
			e["pos_err"] = snappedf(node.global_position.distance_to(u.position), 0.01)
			var meshes := []
			for m in node.find_children("*", "GeometryInstance3D", true, false):
				var gi := m as GeometryInstance3D
				var mi := gi as MeshInstance3D
				meshes.append({"n": String(gi.name), "vis": gi.is_visible_in_tree(), "mesh": mi != null and mi.mesh != null,
					"lod": [gi.visibility_range_begin, gi.visibility_range_end], "tr": gi.transparency, "aabb": snappedf(gi.get_aabb().size.length(), 0.01)})
			e["meshes"] = meshes
		out.append(e)
	return {"soldiers": out}


# --- GAMEPLAY-05B ---------------------------------------------------------------------------------------------------------

## B6: a squad building a site takes up a defence on its own (as on contact) which ends in a regroup; the tactics leave it on a
## HOLD / REGROUP it was never given. It must go back to the site by itself and finish it. Fails if the squad never built
## (precondition) or did not end on the tactics' hold / regroup (nothing tested).
func _b_build_resume() -> Dictionary:
	var pf := _war().player_faction
	var sq: SquadState = _player_squads()[0]
	_war().faction(pf).pool.add(&"supplies", 3000.0)
	var cp := _player_cp()
	var site := _place(&"fighting_position", _site_in_base(&"fighting_position", cp.position))
	_expect(site != null, "b_build_resume: no site placed")
	if site == null:
		return {}
	await _until(func() -> bool: return sq.tactic == SquadState.Tactic.BUILD and site.work_progress() > 0.02, 120.0, 4.0)
	var built0 := sq.tactic == SquadState.Tactic.BUILD
	var p0 := site.work_progress()
	var order_building := sq.order
	demo.sim.tactics.start(sq, SquadState.Tactic.DEFEND, SquadState.Owner.SQUAD, demo.sim.war.squad_center(sq), -1, "test: contact")
	var prev_order := sq.prev_order
	await _until(func() -> bool: return false, 15.0, 4.0)
	demo.sim.tactics._finish(sq, "test: calm", SquadState.Tactic.REGROUP)
	await _until(func() -> bool: return sq.tactic == SquadState.Tactic.NONE, 60.0, 4.0)
	var order_after := sq.order
	var t0 := demo.sim.state.time
	await _until(func() -> bool: return not site.is_site() or (sq.tactic == SquadState.Tactic.BUILD and site.work_progress() > p0 + 0.05), 180.0, 4.0)
	var out := {"built_first": built0, "p0": snappedf(p0, 0.01), "order_after_regroup": order_after, "resumed_s": roundi(demo.sim.state.time - t0),
		"p1": snappedf(site.work_progress(), 0.01), "finished": not site.is_site(), "tactic": sq.tactic_name(), "why": sq.tactic_why,
		"order_building": order_building, "prev_order": prev_order, "tactic_hold": demo.sim.tactics._meta(sq, "tactic_hold", null),
		"eligible": demo.sim.tactics.build_eligible(sq), "status": sq.status, "site_why": String(site.work_record().get("why", "")),
		"no_build_until": demo.sim.tactics._meta(sq, "no_build_until", 0.0), "now": roundi(demo.sim.state.time)}
	_expect(built0, "b_build_resume: the squad never started building (precondition): %s" % str(out))
	_expect(order_after == SquadState.Order.HOLD or order_after == SquadState.Order.REGROUP, "b_build_resume: the squad did not end on the tactics' hold / regroup (nothing tested): %s" % str(out))
	_expect(out.finished or float(out.p1) > p0 + 0.05, "b_build_resume: the squad did not go back to the site: %s" % str(out))
	return out


## navinf_04 diagnosis: physics heights across the road edge where near-tier soldiers stall (-142, -1312), against the terrain
## height (the navmesh's ground): where the road collider stands above the terrain and how high its edge is.
func _n_edge() -> Dictionary:
	var c := Vector3(-142.0, 0.0, -1312.0)
	await _frame(c, 40.0, 0.0)
	await _seconds(3.0)
	var nrm := Vector3(0.89, 0.0, -0.46).normalized()
	var space := demo.get_viewport().get_world_3d().direct_space_state
	var rows := []
	for i in range(-12, 13):
		var p := c + nrm * (i * 0.5)
		var th: float = demo.terrain.data.get_height(p)
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, th + 20.0, p.z), Vector3(p.x, th - 5.0, p.z))
		var hit := space.intersect_ray(q)
		var hy: float = hit.position.y if not hit.is_empty() else NAN
		var who: String = String(hit.collider.name) if not hit.is_empty() else "-"
		rows.append([i * 0.5, snappedf(th, 0.01), snappedf(hy, 0.01), snappedf(hy - th, 0.01), who])
	return {"along_normal": rows}


## Capture feedback: the squad is put into a neutral objective (Verket); the squad status, the world overlay (shot) and the map tag
## (shot) say CAPTURING with the progress and what keeps it going; the squad is moved out: CAPTURE PAUSED and one message.
func _u_capture() -> Dictionary:
	var pf := _war().player_faction
	var sq: SquadState = _player_squads()[0]
	var o := _objective("Verket")
	_expect(o != null and o.owner < 0, "u_capture: no neutral Verket (precondition)")
	if o == null:
		return {}
	var tag := ("_" + shot_tag) if shot_tag != "" else ""
	var put := func(at: Vector3) -> void:
		var i := 0
		for uid in sq.members:
			var u := demo.sim.state.get_unit(uid)
			demo.sim.state.halt(uid)
			u.position = demo.on_ground(at.x + (i % 4) * 3.0, at.z + (i / 4) * 3.0, 0.0)
			var b: Node3D = demo.sim.bodies.get(uid)
			if b:
				b.global_position = u.position + Vector3.UP * 0.3  # a near body writes its own position into the record
			i += 1
		# The squad's own order there too (else its formation slots pull the soldiers back).
		demo.sim.squads.order_move([sq.id], demo.on_ground(at.x + 4.5, at.z + 1.5, 0.0))
	put.call(o.position + Vector3(-10, 0, 10))
	await _frame(o.position, 140.0, 0.0)
	await _until(func() -> bool: return o.capture_progress > 0.15, 120.0, 4.0)
	await _seconds(1.0)
	var st1 := SquadPanel.squad_status(demo.sim, sq)
	# The capture word itself (combat - ENGAGED / UNDER FIRE - rightly wins in the shown status; Verket is in sight of a South post).
	var cap1 := SquadPanel.capture_status(demo.sim, sq)
	var cs1 := demo.sim.war.capture_state(o, pf)
	demo.rts.select_squads([sq.id])
	_png("u_capture_rts" + tag)
	demo.toggle_map()
	demo.strategic_map.zoom = 0.35
	demo.strategic_map.focus_on(o.position)
	await _seconds(1.0)
	_png("u_capture_map" + tag)
	demo.toggle_map()
	var n_ev := _war().events.size()
	put.call(o.position + Vector3(o.radius + 150.0, 0, 0))
	await _until(func() -> bool: return demo.sim.war.capture_state(o, pf).state == "paused", 30.0, 2.0)
	await _seconds(1.0)
	var cs2 := demo.sim.war.capture_state(o, pf)
	var msgs := []
	for i in range(n_ev, _war().events.size()):
		if String(_war().events[i].kind) == "capture":
			msgs.append(String(_war().events[i].text))
	await _frame(o.position, 140.0, 0.0)
	await _seconds(1.0)
	_png("u_capture_paused" + tag)
	var out := {"presence": o.presence, "squad_to_obj_m": roundi(WarSim._flat(demo.sim.war.squad_center(sq), o.position)), "war": demo.sim.war.enabled,
		"owner": o.owner, "capture_faction": o.capture_faction, "contested": o.contested, "shown_status": st1.text, "capture_status": cap1.get("text", ""), "state1": cs1.state, "progress1": snappedf(float(cs1.progress), 0.01), "radius": roundi(o.radius),
		"state2": cs2.state, "messages": msgs}
	_expect(String(cap1.get("text", "")).begins_with("CAPTURING") and cs1.state == "capturing", "u_capture: no CAPTURING status: %s" % str(out))
	_expect(cs2.state == "paused" and msgs.size() == 1 and String(msgs[0]).contains("%d m" % roundi(o.radius)), "u_capture: no single pause message with the radius: %s" % str(out))
	return out


## Command usability: an armed ASSAULT and an armed REARM show the line, distance and what the click will do (shots); the mouse on
## the ASSAULT button shows its tooltip (shot). The tooltips say what the order does (text checked).
func _u_orders() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	var c := demo.sim.war.squad_center(sq)
	await _frame(c + Vector3(0, 0, -40), 90.0, 0.0)
	demo.rts.select_squads([sq.id])
	await _seconds(0.5)
	var vs := demo.get_viewport().get_visible_rect().size
	var tag := ("_" + shot_tag) if shot_tag != "" else ""
	demo.rts.arm_tactic(SquadState.Tactic.ASSAULT)
	Input.warp_mouse(Vector2(vs.x * 0.55, vs.y * 0.3))
	await _seconds(0.6)
	_png("u_orders_assault" + tag)
	demo.rts.armed_tactic = -1
	demo.rts.arm_tactic(RTSController.REARM)
	Input.warp_mouse(Vector2(vs.x * 0.4, vs.y * 0.35))
	await _seconds(0.6)
	_png("u_orders_rearm" + tag)
	demo.rts.armed_tactic = -1
	var b: Control = demo.hud.tactical_panel._buttons[SquadState.Tactic.ASSAULT]
	Input.warp_mouse(b.get_global_rect().get_center() * demo.get_viewport().get_final_transform().get_scale())
	await _seconds(1.6)
	_png("u_orders_tooltip" + tag)
	var tips := {}
	for e: Array in TacticalPanel.ENTRIES:
		tips[String(e[3])] = String(e[5])
	_expect(String(tips.get("Assault", "")).contains("fire and movement") and String(tips.get("Rearm", "")).contains("ammunition"), "u_orders: tooltips: %s" % str(tips))
	return {"tooltips": tips.size(), "assault": tips.get("Assault", "")}


## Road mesh against RoadNetwork across many roads near the camera: for road segments within 600 m of a few spots, physics rays
## across the road find where the road collider ends and how high it is, compared with the RoadNetwork width and surface height
## that RoadShoulders eases the terrain to; and how far the terrain just outside the mesh lies below the mesh edge (the lip).
func _n_roads() -> Dictionary:
	var spots: Array = [Vector3(-142, 0, -1312), demo.sim.war.squad_center(_player_squads()[0]), Vector3(-1300, 0, 5600), Vector3(800, 0, 2200)]
	var rows := []
	var space := demo.get_viewport().get_world_3d().direct_space_state
	for sp: Vector3 in spots:
		await _frame(sp, 60.0, 0.0)
		await _seconds(3.0)
		for r: RoadNetwork.Road in demo.sim.state.roads.world:
			for i in range(0, r.points.size() - 1, 3):
				var a := r.points[i]
				var b := r.points[i + 1]
				var m := a.lerp(b, 0.5)
				if WarSim._flat(m, sp) > 120.0:
					continue
				var t := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
				var nrm := Vector3(-t.z, 0, t.x)
				var hw := r.width * 0.5
				for side: float in [-1.0, 1.0]:
					var edge := -1.0
					var edge_y := NAN
					for k in range(0, 41):
						var off := k * 0.1
						var p := m + nrm * side * (hw - 1.0 + off)
						var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, m.y + 15.0, p.z), Vector3(p.x, m.y - 15.0, p.z))
						var hit := space.intersect_ray(q)
						if hit.is_empty() or not String(hit.collider.name).contains("road"):
							break
						edge = off - 1.0
						edge_y = hit.position.y
					if edge < -0.9:
						continue
					var out := m + nrm * side * (hw + edge + 0.25)
					var th: float = demo.terrain.data.get_height(out)
					var road_y := m.y
					rows.append({"over_w": snappedf(edge, 0.05), "edge_dy": snappedf(edge_y - road_y, 0.01), "lip": snappedf(edge_y - th, 0.01),
						"w": r.width, "cls": String(r.cls)})
	var n := rows.size()
	var lips := rows.map(func(x: Dictionary) -> float: return float(x.lip))
	lips.sort()
	var ow := rows.map(func(x: Dictionary) -> float: return float(x.over_w))
	ow.sort()
	var dy := rows.map(func(x: Dictionary) -> float: return float(x.edge_dy))
	dy.sort()
	var over_35 := lips.filter(func(x: float) -> bool: return x > 0.35).size()
	var over_100 := lips.filter(func(x: float) -> bool: return x > 1.0).size()
	return {"samples": n, "over_w_median": ow[n / 2] if n > 0 else null, "over_w_p90": ow[int(n * 0.9)] if n > 0 else null,
		"edge_dy_median": dy[n / 2] if n > 0 else null, "lip_median": lips[n / 2] if n > 0 else null, "lip_p90": lips[int(n * 0.9)] if n > 0 else null,
		"lip_max": lips[n - 1] if n > 0 else null, "lips_over_step_0_35": over_35, "lips_over_1m": over_100, "rows": rows.slice(0, 60)}


# --- PERFORMANCE-01 ---------------------------------------------------------------------------------------------------------

## Vegetation streaming frame times under controlled events (1920x1080, vsync off): a still camera (baseline), chunks unloaded
## on purpose while the camera stands still, 60 cells freed in one frame, camera jumps between two areas 3 km apart, and a
## camera driving along a road at 25 m/s. Per phase: frame-time statistics; for every frame over 33 ms, what the streamer did in it
## (counter deltas). --veg-phases=baseline,unload,free,jump,drive picks phases.
func _p_veg() -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var veg = demo.vegetation
	demo.sim.brain.enabled = false
	var phases: PackedStringArray = ["baseline", "unload", "free", "jump", "drive", "pan", "flick", "views"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--veg-phases="):
			phases = a.trim_prefix("--veg-phases=").split(",")
	var start := demo.sim.war.squad_center(_player_squads()[0])
	await _frame(start, 80.0, 0.0)
	await _until(func() -> bool: return veg.is_settled(), 30.0, 1.0)
	await _seconds(2.0)
	var out := {}
	if phases.has("baseline"):
		out["baseline"] = await _veg_frames(240, Callable())
	if phases.has("unload"):
		var rows := []
		var locs: Array = veg.chunks.keys()
		for i in mini(4, locs.size()):
			var loc: Vector2i = locs[i]
			var act0: int = veg.active.size()
			var t0 := Time.get_ticks_usec()
			veg.unload_chunk(loc)
			var call_us := Time.get_ticks_usec() - t0
			var fr := await _veg_frames(60, Callable())
			rows.append({"chunk": [loc.x, loc.y], "call_us": call_us, "cells_freed": act0 - int(veg.active.size()), "frames": fr})
			veg.refresh()
			await _until(func() -> bool: return veg.is_settled(), 30.0, 1.0)
			await _seconds(1.0)
		out["unload"] = rows
	if phases.has("free"):
		var keys: Array = veg.active.keys()
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.x + a.y > b.x + b.y)
		var t0 := Time.get_ticks_usec()
		for k in keys.slice(0, 60):
			veg._deactivate(k)
		var call_us := Time.get_ticks_usec() - t0
		out["free"] = {"cells": mini(60, keys.size()), "call_us": call_us, "frames": await _veg_frames(60, Callable())}
		veg.refresh()
		await _until(func() -> bool: return veg.is_settled(), 30.0, 1.0)
	if phases.has("jump"):
		var far := start + Vector3(3000.0, 0, 0)
		var jumps := []
		for i in 6:
			var to := far if i % 2 == 0 else start
			jumps.append(await _veg_frames(240, func(_k: int) -> void: if _k == 0: demo.rts_camera.frame(to, 0.0, 80.0)))
		out["jump"] = _veg_merge(jumps)
	if phases.has("drive"):
		await _frame(start, 60.0, 0.0)
		await _until(func() -> bool: return veg.is_settled(), 30.0, 1.0)
		var t_start := Time.get_ticks_msec()
		out["drive"] = await _veg_frames(1200, func(_k: int) -> void:
			var dist := 25.0 * (Time.get_ticks_msec() - t_start) / 1000.0
			demo.rts_camera.frame(start + Vector3(dist * 0.8, 0, -dist * 0.6), 0.0, 60.0))
	if phases.has("pan"):
		# Fast RTS panning (Shift at a high zoom): 300 m/s for 10 s, out and back.
		await _frame(start, 150.0, 0.0)
		await _until(func() -> bool: return veg.is_settled(), 30.0, 1.0)
		var t_pan := Time.get_ticks_msec()
		out["pan"] = await _veg_frames(1200, func(_k: int) -> void:
			var t := (Time.get_ticks_msec() - t_pan) / 1000.0
			var dist := 300.0 * (t if t < 5.0 else 10.0 - t)
			demo.rts_camera.frame(start + Vector3(dist, 0, dist * 0.3), 0.0, 150.0))
	if phases.has("flick"):
		# Out 600 m and straight back before the leaving cells are freed: they must be shown again (reused), and the vegetation
		# must end exactly as it was.
		await _frame(start, 80.0, 0.0)
		await _until(func() -> bool: return veg.is_settled() and int(veg.get_stats().release_queued) == 0, 30.0, 1.0)
		var before_keys: Array = veg.active.keys()
		before_keys.sort()
		var r0 := int(veg.counters.get("cells_reused", 0))
		var fr := await _veg_frames(240, func(_k: int) -> void:
			if _k == 0:
				demo.rts_camera.frame(start + Vector3(600.0, 0, 0), 0.0, 80.0)
			elif _k == 6:
				demo.rts_camera.frame(start, 0.0, 80.0))
		await _until(func() -> bool: return veg.is_settled() and int(veg.get_stats().release_queued) == 0, 30.0, 1.0)
		var after_keys: Array = veg.active.keys()
		after_keys.sort()
		var hidden := 0
		for k in after_keys:
			if not (veg.active[k] as Node3D).visible:
				hidden += 1
		fr["reused"] = int(veg.counters.get("cells_reused", 0)) - r0
		fr["same_cells"] = before_keys == after_keys
		fr["hidden_active"] = hidden
		out["flick"] = fr
	if phases.has("views"):
		# First person, the map, back to the tactical view: no hitch, the same vegetation afterwards.
		await _frame(start, 80.0, 0.0)
		await _until(func() -> bool: return veg.is_settled(), 30.0, 1.0)
		var k0: Array = veg.active.keys()
		k0.sort()
		var sq: SquadState = _player_squads()[0]
		var fr2 := await _veg_frames(600, func(_k: int) -> void:
			if _k == 0:
				demo.game.possess(sq.leader_id)
			elif _k == 200:
				demo.toggle_map()
			elif _k == 350:
				demo.toggle_map()
			elif _k == 400:
				demo.game.enter_rts()
				demo.rts_camera.frame(start, 0.0, 80.0))
		await _until(func() -> bool: return veg.is_settled() and int(veg.get_stats().release_queued) == 0, 30.0, 1.0)
		var k1: Array = veg.active.keys()
		k1.sort()
		fr2["same_cells"] = k0 == k1
		out["views"] = fr2
	out["streamer_end"] = veg.get_stats()
	out["counters"] = veg.counters.duplicate()
	out["static_mb"] = roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	out["vram_mb"] = roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	demo.sim.brain.enabled = true
	return out


## n frames: statistics, and the streamer's counter deltas in every frame over 33 ms. per_frame(k) runs before frame k.
func _veg_frames(n: int, per_frame: Callable) -> Dictionary:
	var veg = demo.vegetation
	var times := PackedFloat32Array()
	var spikes := []
	var c0: Dictionary = veg.counters.duplicate()
	var last := Time.get_ticks_usec()
	var prev: Dictionary = veg.counters.duplicate()
	var qmax := 0
	var rmax := 0
	var bake0: int = demo.detail.bake_count if demo.detail else 0
	for k in n:
		if per_frame.is_valid():
			per_frame.call(k)
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		times.append(ms)
		var cur: Dictionary = veg.counters
		qmax = maxi(qmax, maxi(veg._queue.size() - veg._queue_pos, 0))
		rmax = maxi(rmax, maxi(veg._release.size() - veg._release_pos, 0) if "_release" in veg else 0)
		if ms > 33.3 and spikes.size() < 30:
			var e := {"ms": snappedf(ms, 0.1), "process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1),
				"physics_ms": snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1),
				"navmesh_bakes": (demo.detail.bake_count - bake0) if demo.detail else 0}
			for key in cur:
				var dv := int(cur[key]) - int(prev[key])
				if dv != 0:
					e[key] = dv
			spikes.append(e)
		prev = cur.duplicate()
		bake0 = demo.detail.bake_count if demo.detail else 0
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0.0
	var o16 := 0
	var o33 := 0
	for x in sorted:
		sum += x
		o16 += 1 if x > 16.7 else 0
		o33 += 1 if x > 33.3 else 0
	var d := {}
	for key in veg.counters:
		d[key] = int(veg.counters[key]) - int(c0[key])
	return {"frames": n, "ms_avg": snappedf(sum / n, 0.01), "ms_p95": snappedf(sorted[int(n * 0.95)], 0.01), "ms_p99": snappedf(sorted[int(n * 0.99)], 0.01),
		"ms_max": snappedf(sorted[n - 1], 0.01), "over_16_7": o16, "over_33": o33, "queue_max": qmax, "release_queue_max": rmax, "counters": d, "spikes": spikes}


func _veg_merge(rows: Array) -> Dictionary:
	var out := {"runs": rows.size(), "ms_avg": 0.0, "ms_p95": 0.0, "ms_p99": 0.0, "ms_max": 0.0, "over_16_7": 0, "over_33": 0, "queue_max": 0, "counters": {}, "spikes": []}
	for r: Dictionary in rows:
		out.ms_avg += float(r.ms_avg) / rows.size()
		out.ms_p95 = maxf(out.ms_p95, r.ms_p95)
		out.ms_p99 = maxf(out.ms_p99, r.ms_p99)
		out.ms_max = maxf(out.ms_max, r.ms_max)
		out.over_16_7 += int(r.over_16_7)
		out.over_33 += int(r.over_33)
		out.queue_max = maxi(out.queue_max, int(r.queue_max))
		for k in r.counters:
			out.counters[k] = int(out.counters.get(k, 0)) + int(r.counters[k])
		(out.spikes as Array).append_array(r.spikes)
	out.ms_avg = snappedf(out.ms_avg, 0.01)
	return out


static func _xz2(p: Vector3) -> Array:
	return [roundi(p.x), roundi(p.z)] if p.is_finite() else []
