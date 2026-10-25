## COMBAT-01 checks in the real game on ref_20km: short, targeted, one seed each (no stochastic series).
##
##   Godot.exe --path . --fullscreen --log-file c1.log res://scenes/game/world_ref_20km.tscn -- --combat01-test [--shots] [--only v_detect,...] [--shot-dir=res://docs/combat01]
##
## v_detect   the VISUAL-03 report's 120 m encounter (two fire teams of four on the open test site): every sight line of every
##            pair before the AI runs (blocker, foliage layers, field of view, vegetation data ready), then the first 12 s of
##            perception per soldier (state, target, reason) - explains a "they never saw each other" result instead of
##            guessing at it.
## p_posture  one soldier through stand -> crouch -> prone -> stand (the record's posture, the character's clips, close
##            shots from the side and the front quarter), the hit volumes per posture (rays at standing head / chest
##            height and at the prone head), the eye, a move order from prone (gets up first), save / load mid-prone, and
##            first-person possession (camera height, the player's prone).
## g_grass    grass concealment: one observer 100 m from one target in the densest grass near the site, the target
##            standing, crouched, prone, prone and firing, and standing on bare ground: time to notice each (the target
##            holds fire and its posture; one deterministic run each).
## a_accuracy the AI's aim model measured directly (no world, no stochastic battle): 600 deterministic shots per case of the
##            real CombatBrain aim error and CombatSim spread at a soldier's real hit volumes, per weapon, distance,
##            shooter posture / skill and target posture; first aimed shot and settled. --aim=g05b for the old profile.
## f_gunplay  first person: the possessed soldier fires rifle, marksman rifle and machine gun (recoil kick and recovery,
##            sight zoom), an enemy team 70 m away fires at him (cracks / whizzes heard where rounds pass, impacts around
##            him, his view never moved by it), hits make AI soldiers flinch; then the same fight from the tactical camera
##            at 350 m and 700 m (muzzle flickers, tracers). Screenshots of each.
## Prints "C1 <check> <json>", writes res://benchmarks/raw/combat01_test.json.
class_name Combat01SelfTest
extends Visual03SelfTest

const CHECKS1: Array[String] = ["v_detect", "p_posture", "g_grass", "a_accuracy", "f_gunplay"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/combat01"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKS1)
	SoldierBody.require_mouse_capture = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	tree.create_timer(1500.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_expect(not _site.is_empty(), "no open test site")
	if _site.is_empty():
		_finish()
		return
	_tcam = Camera3D.new()
	_tcam.fov = 50.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	if demo.hud:
		demo.hud.visible = false
		demo.hud.process_mode = Node.PROCESS_MODE_DISABLED
	demo.rts.select_squads([])
	for n in CHECKS1:
		if only.has(n):
			demo.rts_camera.frame(_site.def, 0.6, 40.0)
			await _seconds(3.0)
			_log(n, await call("_" + n))
			_cs.reset()
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("C1 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/combat01_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("C1 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


## Moves the test camera and waits until it has been drawn from there.
func _view(target: Vector3, dist: float, yaw: float, pitch := 10.0) -> void:
	_cam(target, dist, yaw, pitch)
	for i in 3:
		await tree.process_frame


func _keep_alive(squads: Array) -> void:
	var fn := func(_s: Variant = null) -> void:
		for sq: SquadState in squads:
			for id in sq.members:
				var uu := demo.sim.state.get_unit(id)
				if uu:
					uu.max_health = 100000.0
					uu.health = uu.max_health
	fn.call()
	demo.sim.state.shot_fired.connect(fn)


## One sight line in detail: the LineOfFire answer and what stands in it.
func _pair(a: UnitState, b: UnitState) -> Dictionary:
	var brain := demo.sim.brain
	var line := demo.sim.combat.line
	var eye := CombatSim.eye_of(a)
	var out := {"a": a.unit_name, "b": b.unit_name, "d": snappedf(CombatBrain._flat(a.position, b.position), 0.1)}
	var bearing := atan2(-(b.position.x - a.position.x), -(b.position.z - a.position.z))
	out["fov_off_deg"] = snappedf(rad_to_deg(absf(wrapf(brain.look_yaw(a) - bearing, -PI, PI))), 0.1)
	out["warm"] = brain._line_warm(eye, b.position)
	for y: float in [1.55, 1.1]:
		var s := line.sight(eye, b.position + Vector3.UP * y)
		out["y%.2f" % y] = {"visible": s.visible, "blocker": s.blocker, "at": snappedf(float(s.distance), 0.1), "foliage": s.foliage}
	# The lowest clearance of the line over the terrain (a rise between the two).
	var lo := INF
	var to := b.position + Vector3.UP * 1.55
	for k in range(1, 40):
		var p := eye.lerp(to, k / 40.0)
		var h: float = demo.sim.terrain.data.get_height(p)
		if not is_nan(h):
			lo = minf(lo, p.y - h)
	out["min_clear_m"] = snappedf(lo, 0.01)
	return out


## The VISUAL-03 placement (the site, +-60 m along its axis) and then the nearest placement with clear sight lines (the same
## ground turned / shifted): the first explains the old result, the second shows detection where nothing is in the way.
func _v_detect() -> Dictionary:
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var out := {"visual03": await _detect_at(c, dir, "v_detect_visual03")}
	_cs.reset()
	await _physics(10)
	var line := demo.sim.combat.line
	var best := {}
	for k in 24:
		var ang := k * TAU / 24.0
		var d2 := dir.rotated(Vector3.UP, ang)
		for shift: float in [0.0, 40.0, -40.0, 80.0]:
			var m := c + Vector3(-d2.z, 0, d2.x) * shift
			var pa := demo.on_ground(m.x - d2.x * 60.0, m.z - d2.z * 60.0, 1.6)
			var pb := demo.on_ground(m.x + d2.x * 60.0, m.z + d2.z * 60.0, 1.55)
			if line.trace(pa, pb, -1, false).blocker == "range":
				best = {"c": m, "dir": d2}
				break
		if not best.is_empty():
			break
	_expect(not best.is_empty(), "v_detect: no clear 120 m line near the site")
	if not best.is_empty():
		out["clear"] = await _detect_at(best.c, best.dir, "v_detect_clear")
		_expect(not (out.clear.first_target_s as Dictionary).is_empty(), "v_detect: clear 120 m lines but nobody acquired a target")
	return out


func _detect_at(c: Vector3, dir: Vector3, shot: String) -> Dictionary:
	demo.sim.brain.enabled = false
	var a := _cs.spawn(0, c - dir * 60.0, dir, 4, "C1A")
	var b := _cs.spawn(1, c + dir * 60.0, -dir, 4, "C1B")
	_keep_alive([a, b])
	await _physics(20)
	var units: Array = []
	for sq: SquadState in [a, b]:
		for id in sq.members:
			units.append(demo.sim.state.get_unit(id))
	var pairs := []
	for ua: UnitState in units:
		for ub: UnitState in units:
			if ua.faction == 0 and ub.faction == 1:
				pairs.append(_pair(ua, ub))
				pairs.append(_pair(ub, ua))
	var visible := pairs.filter(func(p: Dictionary) -> bool: return p["y1.55"].visible or p["y1.10"].visible).size()
	var blockers := {}
	for p: Dictionary in pairs:
		var k: String = p["y1.55"].blocker if p["y1.55"].blocker != "" else "clear"
		blockers[k] = int(blockers.get(k, 0)) + 1
	await _cam(c + Vector3.UP, 45.0, atan2(dir.x, dir.z) + PI * 0.5, 14.0)
	_png(shot)
	# The AI on: who acquires whom, when, and the reasons of those who do not.
	demo.sim.brain.enabled = true
	var t0 := demo.sim.state.time
	var first := {}
	var timeline := []
	while demo.sim.state.time - t0 < 12.0:
		await _physics(15)
		var row := {"t": snappedf(demo.sim.state.time - t0, 0.1)}
		for u: UnitState in units:
			if u.target_id > 0 and not first.has(u.unit_name):
				first[u.unit_name] = snappedf(demo.sim.state.time - t0, 0.01)
			row[u.unit_name] = "%s t%d %s" % [u.ai_state_name(), u.target_id, u.ai_reason]
		timeline.append(row)
	var clears := pairs.map(func(p: Dictionary) -> float: return float(p.min_clear_m))
	var out := {"site": [snappedf(c.x, 1), snappedf(c.z, 1)], "pairs_visible": "%d / %d" % [visible, pairs.size()], "blockers": blockers,
		"min_clear_m": [snappedf(clears.min(), 0.01), snappedf(clears.max(), 0.01)], "pair0": pairs[0],
		"first_target_s": first, "timeline": timeline.slice(0, 4), "warm_waits": demo.sim.brain.warm_waits}
	_expect(visible == 0 or not first.is_empty(), "v_detect: %d sight lines clear, nobody acquired a target in 12 s" % visible)
	return out


func _p_posture() -> Dictionary:
	demo.sim.brain.enabled = false
	UnitVisuals.markers_visible = false
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var pf := demo.sim.state.war.player_faction if demo.sim.state.war else 0
	var sq := _cs.spawn(pf, c, dir, 1, "C1P")
	var u := demo.sim.state.get_unit(sq.members[0])
	u.position = demo.on_ground(c.x, c.z, 0.0)
	var b := _body(u)
	if b:
		b.teleport(u.position, u.yaw)
	await _physics(30)
	var out := {"steps": []}
	var side := atan2(dir.x, dir.z) + PI * 0.5
	for step: Array in [["stand", Posture.STAND], ["crouch", Posture.CROUCH], ["prone", Posture.PRONE], ["up", Posture.STAND]]:
		var now := demo.sim.state.time
		Posture.request(u, step[1], now)
		var mid := {}
		# halfway through the change (the clip seeked to the record's progress)
		var dur: float = Posture.TRANSITION_S[u.posture_from][u.posture]
		if dur > 0.5:
			await _seconds(dur * 0.5)
			mid = {"k": snappedf(Posture.progress(u), 0.01), "anim": _char(u).anim_state() if _char(u) else {}}
			await _view(u.position + Vector3.UP * 0.6, 4.0, side, 8.0)
			_png("p_%s_mid" % step[0])
		await _seconds(maxf(dur, 0.4) + 0.4)
		var e := Posture.eye(u)
		var row := {"step": step[0], "posture": u.posture, "settled": Posture.settled(u), "eye_y": snappedf(e.y - u.position.y, 0.01),
			"top": Posture.top(u), "mid": mid, "anim": _char(u).anim_state() if _char(u) else {}}
		# Hit volumes: from 40 m in front, level rays at standing head height, standing chest, crouched head, prone head.
		var hits := {}
		var fwd := Vector3(-sin(u.yaw), 0, -cos(u.yaw))
		for h: Array in [["head_1.62", 1.62], ["chest_1.2", 1.2], ["crouch_head_1.12", 1.12], ["prone_head", Posture.HEAD[Posture.PRONE].y]]:
			var target := Posture.to_world(u, Vector3(0, h[1], 0.65 if h[0] == "prone_head" else 0.0))
			var from := target + fwd * 40.0
			var r := demo.sim.combat.line.trace(from, target - fwd * 5.0, -1, true)
			hits[h[0]] = "%s%s" % [r.blocker, ("/" + ("head" if r.zone == LineOfFire.Zone.HEAD else "body")) if r.hit_unit == u.id else ""]
		row["hits"] = hits
		out.steps.append(row)
		await _view(u.position + Vector3.UP * 0.6, 3.6, side, 8.0)
		_png("p_%s_side" % step[0])
		await _view(u.position + Vector3.UP * 0.6, 3.2, atan2(dir.x, dir.z) + PI * 0.15, 14.0)
		_png("p_%s_front" % step[0])
		# the same without the grass (the rifle, its optic and the hands)
		var grass := demo.world.get_node_or_null("Grass") as Node3D if demo.world else null
		if grass:
			grass.visible = false
			await _view(u.position + Vector3.UP * 0.5, 2.6, side + 0.5, 12.0)
			_png("p_%s_nograss" % step[0])
			grass.visible = true
	var st: Array = out.steps
	_expect(st[1].hits["head_1.62"] == "terrain" or st[1].hits["head_1.62"] == "range", "crouched soldier hit at standing head height: %s" % st[1].hits["head_1.62"])
	_expect(String(st[2].hits["chest_1.2"]).find("/") < 0, "prone soldier hit at standing chest height: %s" % st[2].hits["chest_1.2"])
	_expect(String(st[2].hits["prone_head"]).find("/head") >= 0, "prone head not hit: %s" % st[2].hits["prone_head"])
	_expect(String(st[0].hits["head_1.62"]).find("/head") >= 0, "standing head not hit: %s" % st[0].hits["head_1.62"])
	# Prone, then a move order 30 m on: the soldier gets up before it walks.
	Posture.request(u, Posture.PRONE, demo.sim.state.time)
	await _seconds(1.6)
	var p0 := u.position
	demo.sim.state.issue_move(u.id, demo.on_ground(p0.x + dir.x * 30.0, p0.z + dir.z * 30.0, 0.0))
	await _seconds(0.5)
	var moved_early := CombatBrain._flat(u.position, p0)
	await _seconds(2.5)
	out["move_from_prone"] = {"posture": u.posture, "moved_while_getting_up_m": snappedf(moved_early, 0.01), "moved_after_3s_m": snappedf(CombatBrain._flat(u.position, p0), 0.1)}
	_expect(moved_early < 0.3 and u.posture == Posture.STAND and CombatBrain._flat(u.position, p0) > 3.0, "move from prone: %s" % JSON.stringify(out.move_from_prone))
	demo.sim.state.halt(u.id)
	await _seconds(0.5)
	# Save / load mid-prone.
	Posture.request(u, Posture.PRONE, demo.sim.state.time)
	await _seconds(1.5)
	var snap := demo.sim.state.snapshot()
	Posture.set_now(u, Posture.STAND)
	demo.sim.state.apply_snapshot(snap)
	await _physics(5)
	var u2 := demo.sim.state.get_unit(u.id)
	out["load"] = {"posture": u2.posture, "settled": Posture.settled(u2)}
	_expect(u2.posture == Posture.PRONE and Posture.settled(u2), "posture lost on load: %s" % JSON.stringify(out.load))
	# First person: possess the prone soldier, camera at the prone eye; crouch with the player's own key path.
	var ok: bool = demo.game.possess(u2.id)
	await _seconds(0.8)
	var pb := _body(u2)
	out["fps"] = {"possessed": ok, "camera_y": snappedf(pb.camera.global_position.y - u2.position.y, 0.01) if pb else -1.0,
		"head_local": str(pb.head.position) if pb else "", "pc": pb.player_controlled if pb else false, "posture": u2.posture,
		"cam_current": pb.camera.current if pb else false}
	if ok and pb:
		await _seconds(0.3)
		_png("p_fps_prone")
		Posture.request(u2, Posture.CROUCH, demo.sim.state.time)
		await _seconds(1.4)
		out.fps["crouch_camera_y"] = snappedf(pb.camera.global_position.y - u2.position.y, 0.01)
		_png("p_fps_crouch")
		demo.game.enter_rts()
		await _seconds(0.5)
		out.fps["after_rts_posture"] = u2.posture
	_expect(ok and float(out.fps.camera_y) < 0.6, "first-person camera not at the prone eye: %s" % JSON.stringify(out.fps))
	demo.sim.brain.enabled = true
	return out


## The grassiest spot near p (Concealment, the same data the grass is drawn from) and the barest one.
func _grass_spots(p: Vector3) -> Array:
	var cc := demo.sim.brain.concealment
	var best := [p, -1.0]
	var bare := [p, 9.0]
	for r: float in [0.0, 20.0, 40.0, 60.0, 90.0]:
		for k in 16:
			var q := demo.on_ground(p.x + cos(k * TAU / 16.0) * r, p.z + sin(k * TAU / 16.0) * r, 0.0)
			var g := cc.grass_height(q)
			if g > float(best[1]):
				best = [q, g]
			if g < float(bare[1]):
				bare = [q, g]
	return [best, bare]


func _g_grass() -> Dictionary:
	var spots := _grass_spots(_site.def)
	var out := {"grass_spot_h": snappedf(float(spots[0][1]), 0.01), "bare_spot_h": snappedf(float(spots[1][1]), 0.01), "cases": {}}
	for case: Array in [["stand", Posture.STAND, false, 0], ["crouch", Posture.CROUCH, false, 0], ["prone", Posture.PRONE, false, 0],
			["prone_firing", Posture.PRONE, true, 0], ["stand_bare", Posture.STAND, false, 1], ["prone_bare", Posture.PRONE, false, 1]]:
		var tp: Vector3 = spots[case[3]][0]
		# the observer 100 m away along a clear line
		var obs := Vector3.INF
		for k in 24:
			var d2 := Vector3(cos(k * TAU / 24.0), 0, sin(k * TAU / 24.0))
			var o := demo.on_ground(tp.x + d2.x * 100.0, tp.z + d2.z * 100.0, 0.0)
			if demo.sim.combat.line.trace(o + Vector3.UP * 1.6, tp + Vector3.UP * Posture.AIM_HEAD[case[1]].y, -1, false).blocker == "range":
				obs = o
				break
		if not obs.is_finite():
			out.cases[case[0]] = "no clear line"
			continue
		demo.sim.brain.enabled = false
		var sa := _cs.spawn(0, obs, (tp - obs).normalized(), 1, "C1O")
		var sb := _cs.spawn(1, tp, (obs - tp).normalized(), 1, "C1T")
		_keep_alive([sa, sb])
		sb.roe = SquadState.Roe.HOLD_FIRE
		var a := demo.sim.state.get_unit(sa.members[0])
		var t := demo.sim.state.get_unit(sb.members[0])
		Posture.set_now(t, case[1])
		t.posture_hold_until = INF
		await _physics(20)
		var t0 := demo.sim.state.time
		# the observer looks that way (as if told): the measure is the grass, not where its attention sweeps
		demo.sim.brain._watch(a, t.position, 30.0)
		demo.sim.brain.enabled = true
		var delay := demo.sim.brain.acquire_delay(a, t, t0)
		var found := -1.0
		while demo.sim.state.time - t0 < 15.0:
			if case[2]:
				t.last_shot_at = demo.sim.state.time
			demo.sim.brain._watch(a, t.position, 30.0)
			await _physics(5)
			if a.target_id == t.id:
				found = demo.sim.state.time - t0
				break
		out.cases[case[0]] = {"grass_h": snappedf(demo.sim.brain.concealment.grass_height(t.position), 0.01), "delay_model_s": snappedf(delay, 0.01),
			"noticed_after_s": snappedf(found, 0.01), "d": snappedf(CombatBrain._flat(a.position, t.position), 0.1)}
		if case[0] == "prone":
			await _view(t.position + Vector3.UP * 0.4, 18.0, atan2(a.position.x - t.position.x, a.position.z - t.position.z), 6.0)
			_png("g_prone_in_grass_18m")
		_cs.reset()
		await _physics(10)
	var cs: Dictionary = out.cases
	if cs.get("stand") is Dictionary and cs.get("prone") is Dictionary:
		_expect(float(cs.stand.noticed_after_s) >= 0.0 and float(cs.stand.noticed_after_s) < 2.0, "standing in grass not noticed quickly: %s" % JSON.stringify(cs.stand))
		_expect(float(cs.prone.noticed_after_s) < 0.0 or float(cs.prone.noticed_after_s) > float(cs.stand.noticed_after_s) + 0.8, "prone in grass not concealed: %s" % JSON.stringify(cs.prone))
		_expect(float(cs.prone.noticed_after_s) > 0.0, "prone in grass never noticed at 100 m in 15 s: %s" % JSON.stringify(cs.prone))
	if cs.get("prone_firing") is Dictionary:
		_expect(float(cs.prone_firing.noticed_after_s) >= 0.0 and float(cs.prone_firing.noticed_after_s) < 1.5, "firing from the grass not noticed: %s" % JSON.stringify(cs.prone_firing))
	return out


## Hit rate of n shots: shooter (weapon, proficiency, posture, settled or a fresh aim) at a target (posture) d m away.
func _hit_rate(wid: StringName, d: float, prof: float, sp: int, tp: int, settled: bool, n := 600) -> float:
	var sim := demo.sim
	var def := sim.combat.weapon(wid)
	var now := sim.state.time
	var sh := UnitState.new()
	sh.id = 990001
	sh.weapon_id = wid
	sh.proficiency = prof
	sh.position = Vector3(0, 0, 0)
	Posture.set_now(sh, sp)
	sh.moved_at = now - 30.0
	# a first shot leaves when the reaction time is over (CombatBrain.aim_ready_at)
	sh.aim_since = now - (30.0 if settled else sim.brain.reaction_s + sim.brain.reaction_per_100m_s * d / 100.0)
	sh.last_shot_at = now - 30.0
	var tg := UnitState.new()
	tg.id = 990002
	tg.position = Vector3(0, 0, -d)
	tg.yaw = PI  # facing the shooter
	Posture.set_now(tg, tp)
	var hits := 0
	for i in n:
		sh.shot_counter = i * 7
		var origin := Posture.eye(sh, now)
		var aim := Posture.aim_point(tg, false, now)
		var dir := sim.brain._aim_error(sh, (aim - origin).normalized(), d)
		var spread := sim.combat.current_spread(sh, def)
		dir = CombatSim.spread_direction(dir, spread, 12345, sh.id, sh.shot_counter + 1)
		if Posture.hit(origin, origin + dir * (d + 5.0), tg, now).zone != LineOfFire.Zone.NONE:
			hits += 1
	return float(hits) / n


func _a_accuracy() -> Dictionary:
	var out := {"profile": demo.sim.brain.aim_profile, "cases": {}}
	var rows := [["rifle trained standing", &"rifle", 0.5, Posture.STAND], ["rifle trained prone", &"rifle", 0.5, Posture.PRONE],
		["rifle veteran crouched", &"rifle", 0.9, Posture.CROUCH], ["carbine trained standing", &"carbine", 0.5, Posture.STAND],
		["dmr trained prone", &"dmr", 0.5, Posture.PRONE], ["dmr trained standing", &"dmr", 0.5, Posture.STAND],
		["lmg trained prone", &"lmg", 0.5, Posture.PRONE], ["lmg trained standing", &"lmg", 0.5, Posture.STAND]]
	for r: Array in rows:
		var row := {}
		for d: float in [50.0, 100.0, 200.0, 300.0, 500.0]:
			row["%dm" % int(d)] = "%d%% / %d%%" % [roundi(_hit_rate(r[1], d, r[2], r[3], Posture.STAND, false) * 100.0), roundi(_hit_rate(r[1], d, r[2], r[3], Posture.STAND, true) * 100.0)]
		out.cases[r[0]] = row
	out["rifle trained standing vs prone target (settled)"] = {"100m": roundi(_hit_rate(&"rifle", 100.0, 0.5, Posture.STAND, Posture.PRONE, true) * 100.0),
		"200m": roundi(_hit_rate(&"rifle", 200.0, 0.5, Posture.STAND, Posture.PRONE, true) * 100.0)}
	out["note"] = "first aimed shot % / settled %, standing target unless noted"
	return out


func _f_gunplay() -> Dictionary:
	var sim := demo.sim
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var pf := sim.state.war.player_faction if sim.state.war else 0
	var ef := 1 if pf != 1 else 2
	sim.brain.enabled = false
	UnitVisuals.markers_visible = false
	var mine := _cs.spawn(pf, c, dir, 1, "C1F")
	var foe := _cs.spawn(ef, c + dir * 70.0, -dir, 3, "C1E")
	_keep_alive([mine, foe])
	var u := sim.state.get_unit(mine.members[0])
	await _physics(30)
	var out := {}
	var ok: bool = demo.game.possess(u.id)
	_expect(ok, "f_gunplay: could not possess")
	if not ok:
		return out
	await _seconds(1.0)
	var b := _body(u)
	b.rotation.y = atan2(-dir.x, -dir.z)
	b.head.rotation.x = deg_to_rad(-1.0)
	await _seconds(0.6)
	_png("f_hip")
	if b.viewmodel and b.viewmodel.arms:
		var vm := b.viewmodel
		var wr := vm._weapon_root.global_transform
		out["muzzle_in_weapon"] = str((wr.affine_inverse() * vm.muzzle.global_position).snapped(Vector3.ONE * 0.001))
		out["muzzle_node"] = str(vm.muzzle.get_path())
		out["mounts"] = str(vm.arms.mounts.keys())
	Input.action_press("aim")
	await _seconds(0.8)
	_png("f_ads_rifle")
	Input.action_release("aim")
	await _seconds(0.6)
	var fx := demo.combat_fx
	var weapons := {}
	for w: StringName in [&"rifle", &"dmr", &"lmg"]:
		var def := sim.combat.weapon(w)
		u.weapon_id = w
		u.mag = def.magazine_size
		u.reserve = def.reserve_start
		u.fire_auto = def.default_mode == WeaponDef.FireMode.AUTO
		u.reload_until = -1.0
		await _physics(10)
		var p0 := b.head.rotation.x
		# one shot: the kick, and how much is left 0.5 s later
		Input.action_press("fire")
		await _physics(2)
		Input.action_release("fire")
		var kick := rad_to_deg(b.head.rotation.x - p0)
		await _seconds(0.5)
		var left := rad_to_deg(b.head.rotation.x - p0)
		var row := {"kick_deg": snappedf(kick, 0.01), "after_0.5s_deg": snappedf(left, 0.01)}
		if u.fire_auto:
			var p1 := b.head.rotation.x
			Input.action_press("fire")
			await _seconds(0.6)
			Input.action_release("fire")
			row["burst_0.6s_climb_deg"] = snappedf(rad_to_deg(b.head.rotation.x - p1), 0.01)
			await _seconds(0.6)
			row["burst_after_0.6s_deg"] = snappedf(rad_to_deg(b.head.rotation.x - p1), 0.01)
		Input.action_press("aim")
		await _seconds(0.6)
		row["ads_fov"] = snappedf(b.camera.fov, 0.1)
		if w == &"dmr":
			_png("f_ads_dmr")
		Input.action_release("aim")
		await _seconds(0.4)
		weapons[String(w)] = row
		b.head.rotation.x = deg_to_rad(-1.0)
	out["player"] = weapons
	# Muzzle flash of the player's own shot.
	u.weapon_id = &"rifle"
	u.mag = 30
	Input.action_press("fire")
	await _physics(1)
	await tree.process_frame
	_png("f_own_flash")
	Input.action_release("fire")
	# The enemy team fires at the player (their brains on, ours stays player controlled); the player watches them.
	await _seconds(1.0)  # the own shot's recoil has recovered
	var cracks0: int = fx.cracks
	var flinch0: int = fx.flinches
	var view0 := b.head.rotation.x
	sim.brain.enabled = true
	await _seconds(6.0)
	_png("f_incoming")
	out["incoming"] = {"cracks": fx.cracks - cracks0, "view_moved_deg": snappedf(rad_to_deg(b.head.rotation.x - view0), 0.001)}
	_expect(fx.cracks - cracks0 > 0, "f_gunplay: no crack heard from 6 s of incoming fire")
	_expect(absf(b.head.rotation.x - view0) < 0.0001, "f_gunplay: incoming fire moved the player's view")
	# The player shoots back: flinches on the enemy.
	b.head.look_at(sim.state.get_unit(foe.members[0]).position + Vector3.UP * 1.2)
	b.head.rotation.y = 0.0
	var t0 := sim.state.get_unit(foe.members[0])
	b.rotation.y = atan2(-(t0.position.x - u.position.x), -(t0.position.z - u.position.z))
	var e := Posture.aim_point(t0, false) - b.camera.global_position
	b.head.rotation.x = atan2(e.y, Vector2(e.x, e.z).length())
	u.mag = 30
	Input.action_press("fire")
	await _seconds(1.0)
	Input.action_release("fire")
	out["flinches"] = fx.flinches - flinch0
	# The fight from the tactical camera.
	demo.game.enter_rts()
	await _seconds(0.5)
	for dist: float in [350.0, 700.0]:
		var ff: int = fx.far_flashes
		var ai0: int = sim.brain.ai_shots
		var mid := c + dir * 35.0
		await _view(mid + Vector3.UP * 2.0, dist, atan2(dir.x, dir.z) + PI * 0.5, 6.0)
		await _seconds(2.0)
		_png("f_fight_%dm" % int(dist))
		var states := []
		for id in foe.members + mine.members:
			var q := sim.state.get_unit(id)
			states.append("%s t%d %s %s" % [q.ai_state_name(), q.target_id, q.ai_reason, Posture.NAMES[q.posture]])
		out["view_%dm" % int(dist)] = {"far_flashes": fx.far_flashes - ff, "ai_shots": sim.brain.ai_shots - ai0, "states": states}
	sim.brain.enabled = false
	return out
