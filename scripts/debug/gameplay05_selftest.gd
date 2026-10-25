## GAMEPLAY-05 quality review checks in the real game on ref_20km: diagnostics of a saved game, the fixes of the review and the
## visual tour used for the before / after screenshots.
##
##   Godot.exe --path . --fullscreen --log-file g5.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --gameplay05-test [--shots] --only <checks> [--shot-dir=res://docs/gameplay05] [--shot-tag=after]
##
## p_state (with --continue: the save of the last playthrough) prints the player's squads, blocked soldiers and the objectives.
## Prints "G5 <check> <json>", writes res://benchmarks/raw/gameplay05_test.json and (with --shots) PNGs into the shot folder.
class_name Gameplay05SelfTest
extends Gameplay04SelfTest

const CHECKS5: Array[String] = ["p_state", "p_watch", "u_markers", "u_capture_name", "u_post_block", "u_strength", "v_tour", "q_perf", "u_bodies"]
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
	while Time.get_ticks_msec() < t_end:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
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
		"static_mb": roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)}


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


static func _xz2(p: Vector3) -> Array:
	return [roundi(p.x), roundi(p.z)] if p.is_finite() else []
