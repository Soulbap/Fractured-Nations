## GAMEPLAY-02 checks: infantry combat, support weapons and tactical AI in the real game on ref_20km.
##
##   Godot.exe --path . --resolution 1600x900 --log-file c2.log res://scenes/game/world_ref_20km.tscn -- --combat02-test [--shots] [--only a_haugen,...] [--seeds=1,2,3]
##
## 02B weapon roles (b_*): squad composition and replacements, machine-gun suppression against a rifle, braced / moving
## handling, the MG emplacement's gunner slot, first person with the LMG, save / load and near / far of the equipment.
## 02A assault scenarios (a_*): an ATTACK operation of North squads against South defenders, run once per world seed (the
## seed drives every aim error, spread and scatter), each recorded by a CombatDiag (positions, roles, stages, suppression,
## shots, hits, casualties, movement, cover, blocked moves). Each scenario states what it expects over all seeds.
## Prints "C2 <check> <json>", writes res://benchmarks/raw/combat02_test.json.
class_name Combat02SelfTest
extends AIStratSelfTest

var seeds: Array = [1, 2, 3]


func run(args: PackedStringArray) -> void:
	out_file = "combat02_test.json"
	prefix = "C2"
	diag_on = true
	for a in args:
		if a.begins_with("--seeds="):
			seeds = Array(a.trim_prefix("--seeds=").split(",")).map(func(x: String) -> int: return int(x))
	await _strat_setup(args, "res://docs/gameplay02")
	_log("setup", {"soldiers": default_soldiers.size(), "seeds": seeds})
	for key: String in ["a_haugen", "a_cover", "a_two", "a_three", "a_limited", "a_unfavourable", "a_fortified"]:
		if _want(key):
			_log(key, await _assault_series(key))
	for key: String in ["b_compose", "b_suppress", "b_handling", "b_emplacement", "b_fps", "b_persist", "b_nearfar"]:
		if _want(key):
			_log(key, await call("_" + key))
	await _end_strat()


# --- 02A: assault scenarios ---------------------------------------------------------------------------------------------

## Scenario table: objective, attacking squads, defending squads, start distance, approach ("hq": from North HQ, "wooded" /
## "open": the direction with the most / fewest trees on the last 300 m), attackers' rounds (0 = the weapon's full load),
## whether the defenders hold an outpost, and what the series must show.
const SCEN := {
	"a_haugen": {"obj": "Haugen", "att": 3, "def": 1, "dist": 520.0, "from": "hq", "want": "win"},
	"a_cover": {"obj": "Haugen", "att": 3, "def": 1, "dist": 480.0, "from": "wooded", "want": "win"},
	"a_two": {"obj": "Haugen", "att": 2, "def": 1, "dist": 450.0, "from": "hq", "want": "win_or_clean_withdraw"},
	"a_three": {"obj": "Elvetun", "att": 3, "def": 1, "dist": 500.0, "from": "open", "want": "win"},
	"a_limited": {"obj": "Haugen", "att": 3, "def": 1, "dist": 520.0, "from": "hq", "ammo": 60, "want": "win_or_clean_withdraw"},
	"a_unfavourable": {"obj": "Haugen", "att": 2, "def": 2, "dist": 480.0, "from": "hq", "want": "clean_withdraw_or_win"},
	"a_fortified": {"obj": "Haugen", "att": 3, "def": 1, "dist": 500.0, "from": "hq", "fort": true, "want": "win_or_clean_withdraw"},
}


func _assault_series(key: String) -> Dictionary:
	var sc: Dictionary = SCEN[key]
	var seed0 := demo.sim.state.world_seed
	var runs: Array = []
	for s: int in seeds:
		demo.sim.state.world_seed = s
		var setup := await _assault_scene(sc)
		if setup.is_empty():
			_expect(false, "%s: scene could not be set up (seed %d)" % [key, s])
			continue
		var r := await _run_attack(setup, 900.0, 12.0)
		r.erase("op_obj")
		var one := {"seed": s, "owner": r.get("owner", -1), "outcome": r.get("op", {}).get("outcome", ""), "attackers_left": r.get("attackers_left", 0),
			"attackers": int(sc.att) * 8, "defenders_left": r.get("defenders_left", 0), "defenders": int(sc.def) * 8, "max_stall_s": r.get("max_assault_stall_s", 0.0),
			"stages": r.get("stages", []), "withdraw_why": r.get("withdraw_why", ""), "sim_s": r.get("warp", {}).get("sim_s", 0.0), "speed": r.get("warp", {}).get("speed", 0.0),
			"approach": setup.get("approach", {}), "diag": r.get("diag", {})}
		one["won"] = int(one.owner) == 0
		runs.append(one)
		print("C2 run %s seed %d: won=%s left %d/%d, defenders %d/%d, stall %.0f, %s" % [key, s, one.won, one.attackers_left, one.attackers, one.defenders_left,
			one.defenders, one.max_stall_s, one.withdraw_why])
		if setup.has("fort_ids"):
			_remove_structures(setup.fort_ids)
	demo.sim.state.world_seed = seed0
	return _judge(key, sc, runs)


## What a series must show. "win": most runs take the objective, none stalls, losses below 60 %. A "clean withdrawal" is a
## withdrawal decided by the operation with at least 40 % of the attackers left (not wiped out, not stuck in the open).
func _judge(key: String, sc: Dictionary, runs: Array) -> Dictionary:
	var wins := 0
	var clean := 0
	var losses := 0.0
	var stall := 0.0
	for r: Dictionary in runs:
		var left_f := float(r.attackers_left) / float(r.attackers)
		losses += 1.0 - left_f
		stall = maxf(stall, float(r.max_stall_s))
		if r.won:
			wins += 1
		elif r.stages.has("withdraw") and left_f >= 0.4:
			clean += 1
	var n := maxi(runs.size(), 1)
	var out := {"wins": wins, "clean_withdrawals": clean, "runs": runs.size(), "avg_losses": snappedf(losses / n, 0.01), "max_stall_s": stall,
		"per_seed": runs.map(func(r: Dictionary) -> String: return "seed %d %s %d/%d left, def %d/%d, stall %.0f" % [r.seed, "WON" if r.won else ("withdrew" if r.stages.has("withdraw") else "-"),
			r.attackers_left, r.attackers, r.defenders_left, r.defenders, r.max_stall_s]), "detail": runs}
	match String(sc.want):
		"win":
			_expect(wins * 3 >= n * 2, "%s: objective taken in %d of %d runs" % [key, wins, n])
			_expect(losses / n <= 0.6, "%s: average losses %.0f %%" % [key, losses / n * 100.0])
		"win_or_clean_withdraw", "clean_withdraw_or_win":
			_expect(wins + clean == n, "%s: %d of %d runs neither took the objective nor withdrew cleanly" % [key, n - wins - clean, n])
	_expect(stall <= 120.0, "%s: an assault made no progress for %.0f s" % [key, stall])
	return out


## Sets up one scenario: the objective held by South (an outpost of fortifications for "fort"), North squads `dist` short of it.
func _assault_scene(sc: Dictionary) -> Dictionary:
	await _fresh()
	_pause_ai(true)
	# 02A measures the coordination with the rifle squads it was diagnosed with; the 02B weapons are measured separately.
	war.rules["squad_composition"] = String(sc.get("comp", "riflemen"))
	var obj := _obj(String(sc.obj))
	obj.owner = 1
	obj.capture_faction = -1
	obj.capture_progress = 0.0
	obj.contested = false
	obj.history.append([demo.sim.state.time, 1])
	var dir := _approach_dir(obj.position, float(sc.dist), String(sc.from))
	var out := {"approach": {"from": sc.from, "trees": _trees_along(obj.position, dir, 300.0)}}
	var target := obj
	var defs: Array = []
	if sc.get("fort", false):
		var f := _fort_outpost(obj.position + dir * 40.0, dir)
		if f.is_empty():
			return {}
		target = f.objective
		defs.append(f.squad)
		out["fort_ids"] = f.ids
		out["approach"]["forts"] = f.ids.size()
		await _warp(40.0, 8.0, 30.0)  # the garrison takes its slots
		out["approach"]["in_slots"] = _fort_count(f.squad)
	for i in int(sc.def) - defs.size():
		var d := _spawn(1, obj.position + Vector3(10 + i * 18, 0, -10 + i * 9))
		d.station_objective = obj.id
		defs.append(d)
	var start := _passable_near(obj.position + dir * float(sc.dist))
	var atk: Array = []
	for i in int(sc.att):
		var a := _spawn(0, start + Vector3(((i % 3) - 1) * 25.0, 0, (i / 3) * 25.0 + 25.0 * (1 if i > 0 else 0)))
		if int(sc.get("ammo", 0)) > 0:
			for id in a.members:
				var u := _u(id)
				u.mag = mini(u.mag, int(sc.ammo))
				u.reserve = maxi(int(sc.ammo) - u.mag, 0)
		atk.append(a)
	await _physics(10)
	out.merge({"obj": target, "atk": atk, "def": defs})
	return out


## Unit direction from the objective towards the attackers' start.
func _approach_dir(o: Vector3, dist: float, mode: String) -> Vector3:
	var hq := _obj("North HQ").position
	var to_hq := Vector3(hq.x - o.x, 0, hq.z - o.z).normalized()
	if mode == "hq":
		return to_hq
	var best := to_hq
	var best_v := -INF
	for k in 16:
		var d := to_hq.rotated(Vector3.UP, k * TAU / 16.0)
		var p := o + d * dist
		if not ws.routes.passable(p) or absf(k * TAU / 16.0 - PI) < PI / 4.0:  # not from behind the defenders' own lines
			continue
		var trees := _trees_along(o, d, 300.0)
		var v := float(trees) if mode == "wooded" else -float(trees)
		if v > best_v:
			best_v = v
			best = d
	return best


## Trunks within 20 m of the line from 60 m to `len` m out of o along d.
func _trees_along(o: Vector3, d: Vector3, length: float) -> int:
	var n := 0
	var buf := PackedFloat32Array()
	var x := 60.0
	while x < length:
		var c := o + d * x
		buf.clear()
		demo.structures.trunks_in_rect(Rect2(c.x - 20.0, c.z - 20.0, 40.0, 40.0), buf)
		n += buf.size() / 3
		x += 40.0
	return n


func _passable_near(p: Vector3) -> Vector3:
	return demo.on_ground(p.x, p.z, 0.0) if ws.routes.passable(p) else demo.sim.tactics.pos.nearest_valid(p, 80.0)


## A South outpost at `at` facing `out` (command post, two fighting positions, a steel guard tower) with a garrison of 8.
func _fort_outpost(at: Vector3, out: Vector3) -> Dictionary:
	var cp := CoreSelfTest.add_built(demo, &"command_post", at, out, 1)
	if cp == null:
		return {}
	var ids: Array = [cp.id]
	for e: Array in [[&"fighting_position", out, 26.0], [&"guard_tower_steel", out.rotated(Vector3.UP, 0.6), 22.0], [&"fighting_position", out.rotated(Vector3.UP, -0.7), 24.0]]:
		var st := CoreSelfTest.add_built(demo, e[0], cp.position + (e[1] as Vector3) * float(e[2]), e[1], 1)
		if st:
			ids.append(st.id)
	ws.sync_bases()
	var sq := _spawn(1, demo.sim.tactics.pos.nearest_valid(cp.position - out * 15.0, 20.0), 8)
	demo.sim.tactics.assign_garrison(sq, cp.base_id, SquadState.Owner.SQUAD)
	return {"objective": ws.base_objective(cp.base_id), "squad": sq, "ids": ids}


func _fort_count(sq: SquadState) -> int:
	var n := 0
	for id in sq.members:
		if _u(id) and _u(id).fort_slot != "":
			n += 1
	return n


func _remove_structures(ids: Array) -> void:
	for id in ids:
		if demo.sim.state.construction.structures.has(id):
			demo.sim.state.construction.remove(id)
	ws.sync_bases()


# --- 02B: weapon roles and the machine gun ------------------------------------------------------------------------------

## A screenshot (1920 x 1080 with --fullscreen) into docs/gameplay02.
func _png(shot_name: String) -> void:
	if not shots:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var path := "%s/%s.png" % [_shot_dir, shot_name]
	demo.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("C2 shot: ", path)


func _roles_of(sq: SquadState) -> Array:
	return Array(sq.members).map(func(id: int) -> String: return String(_u(id).role))


func _start_near(d: float) -> Vector3:
	return _near_point(_obj("North HQ").position, _obj("Haugen").position, d)


## A fresh squad gets the standard composition (machine gunner second, grenadier sixth, the rest riflemen) with the
## faction's machine-gunner look; a squad that lost its gunner gets the next recruit as one; the "riflemen" table arms
## everybody with rifles (the composition is the scenario's choice, data only).
func _b_compose() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var sq := _spawn(0, _start_near(300.0))
	var out := {"roles": _roles_of(sq)}
	var mg := _u(sq.members[1])
	out["mg"] = {"weapon": mg.weapon_id, "mag": mg.mag, "reserve": mg.reserve, "loadout": mg.loadout, "auto": mg.fire_auto}
	_expect(out.roles[1] == "machine_gunner" and out.roles[5] == "grenadier" and out.roles.count("rifleman") == 6, "b_compose: wrong roles %s" % str(out.roles))
	_expect(mg.weapon_id == &"lmg" and mg.mag == 100 and mg.reserve == 300 and mg.loadout == "NATO_mg", "b_compose: machine gunner not equipped %s" % str(out.mg))
	_expect(_u(sq.members[0]).weapon_id == &"rifle" and _u(sq.members[0]).loadout == "NATO_rifleman", "b_compose: rifleman not equipped")
	# The machine gunner falls; a replacement joins and takes the gun, the veterans keep their weapons.
	demo.sim.combat.kill(mg, -1)
	await _physics(3)
	var before := Array(sq.members).map(func(id: int) -> StringName: return _u(id).weapon_id)
	var ids := ws.spawn_recruits(war.faction(0), demo.sim.squads._centroid(sq), 1, sq.squad_name)
	for id in ids:
		spawned_ids.append(id)
	demo.sim.state.add_to_squad(sq.id, ids)
	demo.sim.combat.apply_composition(sq, ids)
	var rec := _u(ids[0])
	out["replacement"] = {"role": rec.role, "weapon": rec.weapon_id, "loadout": rec.loadout}
	_expect(rec.role == &"machine_gunner" and rec.weapon_id == &"lmg", "b_compose: the replacement did not take the machine gun %s" % str(out.replacement))
	var same := true
	for i in before.size():
		same = same and _u(sq.members[i]).weapon_id == before[i]
	_expect(same, "b_compose: a veteran was re-armed")
	# South and East wear their own machine-gunner loadouts.
	var s2 := _spawn(1, _start_near(360.0))
	var s3 := _spawn(2, _start_near(420.0))
	out["looks"] = [_u(s2.members[1]).loadout, _u(s3.members[1]).loadout]
	_expect(out.looks == ["RU_mg", "CN_mg"], "b_compose: faction machine-gunner loadouts %s" % str(out.looks))
	war.rules["squad_composition"] = "riflemen"
	var r := _spawn(0, _start_near(480.0))
	out["riflemen_table"] = Array(r.members).map(func(id: int) -> String: return String(_u(id).weapon_id))
	_expect(not out.riflemen_table.has("lmg"), "b_compose: the riflemen table still gave a machine gun")
	war.rules.erase("squad_composition")
	return out


## One soldier (rifleman, then machine gunner) fires at four soldiers 150 m away for 30 simulated seconds; the targets do
## not fire back and cannot die. Suppression is the time integral of the targets' mean suppression; the damage per hit
## must be the same (a 5.56 round is a 5.56 round: suppression is not bought with damage).
func _b_suppress() -> Dictionary:
	var out := {}
	for role: StringName in [&"rifleman", &"machine_gunner"]:
		await _fresh()
		war.rules["squad_composition"] = "riflemen"
		var at := _start_near(250.0)
		var dir := _obj("Haugen").position - at
		dir.y = 0.0
		dir = dir.normalized()
		var shooter := _spawn(0, at, 1)
		var u := _u(shooter.members[0])
		demo.sim.combat._equip_role(u, role)
		var tgt := _spawn(1, demo.sim.tactics.pos.nearest_valid(at + dir * 150.0, 20.0), 4)
		tgt.roe = SquadState.Roe.HOLD_FIRE
		_tough(tgt, 100000.0)
		await _physics(10)
		var st := {"shots": 0, "hits": 0, "dmg": 0.0, "supp_s": 0.0, "next": demo.sim.state.time, "ammo0": u.mag + u.reserve}
		var on_shot := func(shot: Dictionary) -> void:
			if int(shot.shooter) == u.id:
				st.shots += 1
				if int(shot.get("hit_unit", -1)) > 0:
					st.hits += 1
					st.dmg += float(shot.damage)
		demo.sim.state.shot_fired.connect(on_shot)
		demo.rts_camera.frame(at + dir * 75.0, 0.0, 140.0)
		var t0 := demo.sim.state.time
		await _warp(30.0, 4.0, 60.0, func() -> bool:
			var now := demo.sim.state.time
			if now >= st.next:
				st.next = now + 0.5
				var sum := 0.0
				for id in tgt.members:
					sum += _u(id).suppression_at(now)
				st.supp_s += sum / maxf(tgt.members.size(), 1) * 0.5
			return false)
		demo.sim.state.shot_fired.disconnect(on_shot)
		if shots and role == &"machine_gunner":
			demo.rts_camera.frame(u.position + dir * 20.0, 0.0, 45.0)
			await _seconds(0.6)
			_png("b_mg_firing_rts")
		out[String(role)] = {"shots": st.shots, "hits": st.hits, "dmg_per_hit": snappedf(st.dmg / maxf(st.hits, 1), 0.1), "supp_integral": snappedf(st.supp_s, 0.01),
			"ammo_used": st.ammo0 - (u.mag + u.reserve), "sim_s": snappedf(demo.sim.state.time - t0, 0.1)}
	var r: Dictionary = out.rifleman
	var m: Dictionary = out.machine_gunner
	_expect(int(r.shots) > 5 and int(m.shots) > 5, "b_suppress: too few shots %s" % str(out))
	_expect(float(m.supp_integral) >= 2.0 * float(r.supp_integral), "b_suppress: the MG does not suppress clearly more than a rifle (%s vs %s)" % [m.supp_integral, r.supp_integral])
	_expect(int(m.ammo_used) > int(r.ammo_used), "b_suppress: the MG did not fire more")
	if int(r.hits) > 0 and int(m.hits) > 0:
		_expect(absf(float(m.dmg_per_hit) - float(r.dmg_per_hit)) <= 12.0, "b_suppress: damage per hit differs (%s vs %s)" % [m.dmg_per_hit, r.dmg_per_hit])
	war.rules.erase("squad_composition")
	return out


## The LMG: braced (still for settle_s) it shoots tighter than a standing rifle; on the move much wider; a long reload.
func _b_handling() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var sq := _spawn(0, _start_near(300.0))
	var mg := _u(sq.members[1])
	var rf := _u(sq.members[0])
	var cs := demo.sim.combat
	var lmg := cs.weapon(&"lmg")
	var rifle := cs.weapon(&"rifle")
	var now := demo.sim.state.time
	mg.velocity = Vector3.ZERO
	mg.moved_at = now - 5.0
	mg.bloom = 0.0
	var braced := cs.current_spread(mg, lmg)
	mg.moved_at = now - 0.3
	var unsettled := cs.current_spread(mg, lmg)
	mg.velocity = Vector3(3.5, 0, 0)
	mg.moved_at = now
	var moving := cs.current_spread(mg, lmg)
	rf.velocity = Vector3(3.5, 0, 0)
	rf.bloom = 0.0
	var rifle_moving := cs.current_spread(rf, rifle)
	mg.velocity = Vector3.ZERO
	rf.velocity = Vector3.ZERO
	var out := {"lmg_braced": snappedf(braced, 0.001), "lmg_unsettled": snappedf(unsettled, 0.001), "lmg_moving": snappedf(moving, 0.001),
		"rifle_moving": snappedf(rifle_moving, 0.001), "rifle_still": snappedf(rifle.spread_base_deg, 0.001), "lmg_reload_s": lmg.reload_time, "rifle_reload_s": rifle.reload_time}
	_expect(braced < unsettled and braced < rifle.spread_base_deg, "b_handling: a braced LMG is not tighter %s" % str(out))
	_expect(moving > rifle_moving * 2.0, "b_handling: the LMG on the move is not clearly worse than a rifle %s" % str(out))
	mg.mag = 0
	cs.request_reload(mg.id)
	out["reload_until"] = snappedf(mg.reload_until - demo.sim.state.time, 0.1)
	_expect(absf(float(out.reload_until) - lmg.reload_time) < 0.1, "b_handling: the LMG reload does not take its time")
	war.rules.erase("squad_composition")
	return out


## A South garrison (standard squad) in a base with an MG emplacement: the machine gunner takes the gunner slot.
func _b_emplacement() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var hau := _obj("Haugen").position
	var dir := _obj("North HQ").position - hau
	dir.y = 0.0
	dir = dir.normalized()
	var at := demo.sim.tactics.pos.nearest_valid(hau + dir * 60.0, 30.0)
	var cp := CoreSelfTest.add_built(demo, &"command_post", at, dir, 1)
	var em: StructureState = CoreSelfTest.add_built(demo, &"mg_emplacement", cp.position + dir * 24.0, dir, 1) if cp else null
	var out := {"built": cp != null and em != null}
	_expect(cp != null and em != null, "b_emplacement: the base could not be built")
	if em == null:
		return out
	ws.sync_bases()
	var sq := _spawn(1, demo.sim.tactics.pos.nearest_valid(cp.position - dir * 15.0, 20.0), 8)
	demo.sim.tactics.assign_garrison(sq, cp.base_id, SquadState.Owner.SQUAD)
	var gunner := _u(sq.members[1])
	await _warp(60.0, 6.0, 40.0, func() -> bool: return gunner.fort_slot != "")
	var slot := demo.sim.tactics.pos.slot_by_key(gunner.fort_slot, 1)
	out["gunner"] = {"weapon": gunner.weapon_id, "slot": gunner.fort_slot, "role": slot.get("role", ""), "structure": slot.get("structure", -1)}
	_expect(gunner.fort_slot != "" and String(slot.get("role", "")) == "mg" and int(slot.get("structure", -1)) == em.id, "b_emplacement: the machine gunner is not on the MG slot %s" % str(out.gunner))
	if shots:
		demo.rts_camera.frame(em.position, 0.6, 38.0)
		await _seconds(1.5)
		_png("b_mg_emplacement_manned")
	_remove_structures([cp.id, em.id])
	war.rules.erase("squad_composition")
	return out


## First person with the machine gun: the viewmodel is the LMG (with the faction optic), a held trigger fires a stream from
## the 100-round box, the reload takes its time. The same CombatSim rules as the AI's.
func _b_fps() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var at := _start_near(300.0)
	var sq := _spawn(0, at)
	var mg := _u(sq.members[1])
	demo.rts_camera.frame(at, 0.0, 60.0)
	await _seconds(1.5)
	var body := await _possess(mg.id)
	await _seconds(1.0)
	var out := {"possessed": body != null and demo.game.mode == GameController.Mode.FPS}
	_expect(out.possessed, "b_fps: could not take over the machine gunner")
	if body == null:
		return out
	var items: Array = []
	if body.viewmodel and body.viewmodel.loadout:
		for it in body.viewmodel.loadout.items:
			if it.slot.begins_with("weapon"):
				items.append(it.id)
	out["viewmodel"] = items
	_expect(items.has("lmg") and not items.has("nato_rifle"), "b_fps: the first-person weapon is not the LMG %s" % str(items))
	await _fps_shot_at(body, body.camera.global_position + (-body.global_basis.z) * 80.0 + Vector3.DOWN * 1.0)
	var mag0 := mg.mag
	Input.action_press("fire")
	await _physics(60)
	if shots:
		_png("b_fps_lmg")
	Input.action_release("fire")
	await _physics(4)
	out["burst"] = mag0 - mg.mag
	_expect(int(out.burst) >= 8, "b_fps: holding the trigger did not fire a stream (%d rounds)" % out.burst)
	mg.mag = 0
	_press(KEY_R)
	await _physics(3)
	out["reload_s"] = snappedf(mg.reload_until - demo.sim.state.time, 0.1)
	_expect(mg.is_reloading() and float(out.reload_s) > 5.5, "b_fps: the LMG reload is not the LMG's (%s s)" % out.reload_s)
	await _leave()
	war.rules.erase("squad_composition")
	return out


## Role, weapon, rounds and look of every soldier survive a save to the test save folder and a load.
func _b_persist() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var sq := _spawn(0, _start_near(300.0))
	var mg := _u(sq.members[1])
	mg.mag = 37
	mg.reserve = 211
	var before := _equip_sig(sq)
	var path := demo.save_dir() + "/combat02_persist.sav"
	var err := demo.sim.state.save_file(path)
	mg.mag = 100
	mg.role = &"rifleman"
	mg.weapon_id = &"rifle"
	mg.loadout = "NATO_rifleman"
	demo.sim.state.load_file(path)
	await _physics(3)
	var after := _equip_sig(sq)
	var out := {"path": path, "saved": err == OK, "before": before, "after": after}
	_expect(err == OK and path.contains("test_saves"), "b_persist: the save did not go to the test save folder (%s)" % path)
	_expect(before == after, "b_persist: equipment differs after loading")
	war.rules.erase("squad_composition")
	return out


func _equip_sig(sq: SquadState) -> Array:
	var out := []
	for id in sq.members:
		var u := _u(id)
		out.append("%s/%s/%d/%d/%s" % [u.role, u.weapon_id, u.mag, u.reserve, u.loadout])
	return out


## The camera comes near (a body with the machine-gunner character and the LMG in its hands), goes far (no body) and back:
## the record and the look are the same every time.
func _b_nearfar() -> Dictionary:
	await _fresh()
	war.rules["squad_composition"] = "standard"
	var at := _start_near(300.0)
	var sq := _spawn(0, at)
	var mg := _u(sq.members[1])
	var out := {}
	var s0 := _equip_sig(sq)
	for k in 2:
		demo.rts_camera.frame(at, 0.0, 40.0)
		await _seconds(3.0)
		var body: SoldierBody = demo.sim.bodies.get(mg.id)
		var look := ""
		if body and body.character and body.character.loadout:
			look = body.character.loadout.id
		out["near%d" % k] = {"body": mg.has_body, "character": look}
		_expect(mg.has_body and look == "NATO_mg", "b_nearfar: near, the machine gunner has no body with the LMG %s" % str(out["near%d" % k]))
		if shots and k == 0:
			demo.rts_camera.frame(mg.position, 0.4, 7.0)
			await _seconds(1.2)
			_png("b_mg_gunner_near")
		demo.rts_camera.frame(Vector3(9000, 0, 9000), 0.0, 150.0)
		await _seconds(3.0)
		out["far%d" % k] = {"body": mg.has_body}
		_expect(not mg.has_body, "b_nearfar: far away the machine gunner still has a body")
	out["record_same"] = _equip_sig(sq) == s0
	_expect(out.record_same, "b_nearfar: the record changed between near and far")
	war.rules.erase("squad_composition")
	return out
