## GAMEPLAY-04 checks in the real game on ref_20km: Military Development (B), the New Game opening (A), the arsenal and the
## combat accuracy arena (C), squad equipment (D), opportunities (E) and the integrated first hour (G).
##
##   Godot.exe --path . --resolution 1600x900 --log-file g4.log res://scenes/game/world_ref_20km.tscn -- --scenario=new_game --gameplay04-test [--shots] --only b_lock,...
##
## Narrow checks: each one property, with state set directly instead of waiting through a whole process. Builds on the
## GAMEPLAY-01B test helpers. Prints "G4 <check> <json>", writes res://benchmarks/raw/gameplay04_test.json and (with
## --shots) docs/gameplay04/*.png.
class_name Gameplay04SelfTest
extends GameplaySelfTest

## Every check in run order. Checks that need another scenario are only run when named in --only.
const CHECKS: Array[String] = ["a_setup", "a_cache_safe", "a_ui", "a_phases", "a_persist", "a_skip", "a_road", "a_profile", "a_shoulders", "a_trees", "a_encounter", "b_lock", "b_start", "b_pause", "b_persist", "b_complete", "b_future", "b_ui", "b_ai", "b_dev_off", "c_arena", "c_gl", "c_recoilless", "c_carry", "c_fps", "c_persist", "c_ai_comp", "c_visual", "d_setup", "d_rearm", "d_field_equip", "d_deliver", "d_procure", "d_fallen", "d_persist", "d_ui", "e_offer", "e_complete", "e_recon", "e_persist", "e_ui", "g_defend_spike", "g_playthrough"]
const ONLY_NAMED: Array[String] = ["g_playthrough", "g_defend_spike", "c_arena", "b_dev_off", "a_encounter", "a_road", "a_profile", "a_trees"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/gameplay04"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	tree.create_timer(2700.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	for n in CHECKS:
		if only.has(n) or (only.is_empty() and not ONLY_NAMED.has(n)):
			_log(n, await call("_" + n))
	_finish()


func _dev() -> MilitaryDevelopment:
	return demo.sim.war.dev


func _stock_of(f: int) -> Dictionary:
	return demo.sim.logistics.bases.faction_stock(f)


## A finished command post of the player near his squad (the scenario-setup path), so the development rules have a base.
func _player_cp() -> StructureState:
	var pf := _war().player_faction
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and s.type_id == &"command_post" and not s.is_site():
			return s
	var sqs := _player_squads()
	var at: Vector3 = demo.sim.war.squad_center(sqs[0]) if not sqs.is_empty() else Vector3(-1350, 0, 6950)
	var p := _spot(&"command_post", at, [30.0, 50.0, 70.0, 90.0, 120.0, 150.0], 12)
	return _add_built(&"command_post", p, Vector3(0, 0, -1), pf) if p.is_finite() else null


## The barracks development running, with the player's command post in place (shared setup of the narrow checks).
func _running_project() -> Dictionary:
	var pf := _war().player_faction
	if _player_cp() == null:
		return {}
	_war().faction(pf).pool.add(&"supplies", 1000.0)
	if _dev().active_entry(pf, &"personnel_facilities").is_empty() and not _dev().is_done(pf, &"personnel_facilities"):
		_dev().start(pf, &"personnel_facilities")
	return _dev().active_entry(pf, &"personnel_facilities")



# --- 04A New Game opening ---------------------------------------------------------------------------------------------

func _objective(oname: String) -> ObjectiveState:
	for o: ObjectiveState in _war().all_objectives():
		if o.obj_name == oname:
			return o
	return null


func _squads_at(f: int, oid: int) -> Array:
	return demo.sim.war.squads_of(f).filter(func(sq: SquadState) -> bool: return sq.station_objective == oid)


## The opening as set up: the checkpoint (South, kept by the South AI), its section of four riflemen and position, the
## distance from the start, the phases copied into the war, nobody in contact at minute zero.
func _a_setup() -> Dictionary:
	var war := _war()
	var cp := _objective("Moen checkpoint")
	_expect(cp != null, "a_setup: no Moen checkpoint")
	if cp == null:
		return {}
	var guards := _squads_at(1, cp.id)
	var roles := []
	for sq: SquadState in guards:
		for uid in sq.members:
			roles.append(String(demo.sim.state.get_unit(uid).role))
	var start := demo.sim.war.squad_center(_player_squads()[0])
	var fp := 0
	for st: StructureState in demo.sim.state.construction.all():
		if st.faction == 1 and st.type_id in [&"fighting_position", &"checkpoint_station"] and WarSim._flat(st.position, cp.position) < 80.0:
			fp += 1
	var free: Array = demo.sim.war._free_squads(war.faction(1), demo.sim.war.profile(war.faction(1)))
	var seen := 0
	for sq: SquadState in _player_squads():
		for uid in sq.members:
			if demo.sim.state.get_unit(uid).target_id >= 0:
				seen += 1
	var out := {"owner": cp.owner, "hold": cp.hold, "guards": guards.size(), "roles": roles, "structures": fp,
		"start_to_checkpoint_m": roundi(WarSim._flat(start, cp.position)), "guard_free_for_ops": guards.any(func(sq: SquadState) -> bool: return free.has(sq.id)),
		"phases": (war.guide.get("intro", []) as Array).map(func(p: Dictionary) -> String: return p.id), "player_targets_at_start": seen}
	_expect(cp.owner == 1 and cp.hold == 1, "a_setup: checkpoint owner/hold %s" % str([cp.owner, cp.hold]))
	_expect(guards.size() == 1 and roles.size() == 3 and roles.all(func(r: String) -> bool: return r == "rifleman"), "a_setup: guards %s" % str(roles))
	_expect(fp == 1, "a_setup: checkpoint structures %d" % fp)
	_expect(out.start_to_checkpoint_m > 420 and out.start_to_checkpoint_m < 650, "a_setup: start %d m from the checkpoint" % out.start_to_checkpoint_m)
	_expect(not out.guard_free_for_ops, "a_setup: the South AI may send the checkpoint section away")
	_expect((out.phases as Array).size() >= 5 and demo.sim.war.intro.current().get("id", "") == "command", "a_setup: phases %s" % str(out.phases))
	_expect(seen == 0, "a_setup: the player soldiers see an enemy at minute zero")
	return out


## The checkpoint stands in front of the farm cache, not on it: in the first minute its fire team neither secures the
## cache (it is outside its radius) nor lets anyone else do it (within 80 m of it).
func _a_cache_safe() -> Dictionary:
	await _until(func() -> bool: return false, 60.0, 4.0)
	var c: Dictionary = {}
	for x: Dictionary in _war().caches:
		if x.name == "Moen farm cache":
			c = x
	var out := {"state": c.get("state", "?"), "faction": c.get("faction", -9), "taken_by": c.get("taken_by", -9), "progress": snappedf(float(c.get("progress", 0.0)), 0.01)}
	_expect(c.get("state", "") == "intact" and int(c.get("taken_by", -1)) == -1, "a_cache_safe: the cache went: %s" % str(out))
	return out


## The tracker at the start (briefing, the first phase) in the tactical view, its compact form in first person.
func _a_ui() -> Dictionary:
	if demo.game.mode != GameController.Mode.RTS:
		demo.game.enter_rts()
	var sq: SquadState = _player_squads()[0]
	demo.rts.select_squads([sq.id])
	await _frame(demo.sim.war.squad_center(sq) + Vector3(0, 0, 120), 260.0, 0.0)
	await _physics(20)
	var tr := demo.hud.tracker
	var out := {"visible": tr._panel.visible, "current": tr.current_id, "brief": tr._brief.visible, "rows": tr._list.get_child_count(), "foot": tr._foot.text}
	_expect(tr._panel.visible and tr.current_id == "command" and tr._brief.visible, "a_ui: tracker at the start %s" % str(out))
	_png("a_start_tracker")
	demo.game.possess(sq.leader_id)
	await _seconds(1.0)
	out["fps_visible"] = tr._panel.visible
	out["fps_rows"] = tr._list.get_child_count()
	out["fps_flag"] = _war().guide.get("fps", false)
	_expect(tr._panel.visible and _war().guide.get("fps", false), "a_ui: tracker / fps tip in first person %s" % str(out))
	_png("a_fps_tracker")
	demo.game.enter_rts()
	await _seconds(0.5)
	return out


## Each phase completes from its world condition (state set directly), in the order the player happens to do things; the
## introduction ends once every phase is done and says so once.
func _a_phases() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var it := demo.sim.war.intro
	var f := war.faction(pf)
	var out := {}
	var home := f.home
	# The command post first (out of order): its phase is ticked though an earlier one is still current.
	_player_cp()
	await _until(func() -> bool: return war.guide.intro_done.has("foothold"), 3.0, 1.0)
	out["out_of_order"] = war.guide.intro_done.duplicate()
	_expect(war.guide.intro_done.has("foothold") and it.current().get("id", "") == "command", "a_phases: out-of-order base %s" % str(out.out_of_order))
	f.home = home + Vector3(100, 0, 0)
	await _until(func() -> bool: return war.guide.intro_done.has("command"), 3.0, 1.0)
	f.home = home
	_expect(it.current().get("id", "") == "checkpoint", "a_phases: after moving the current phase is %s" % it.current().get("id", ""))
	for sq: SquadState in _squads_at(1, _objective("Moen checkpoint").id):
		for uid in sq.members.duplicate():
			demo.sim.combat.kill(demo.sim.state.get_unit(uid))
	await _until(func() -> bool: return war.guide.intro_done.has("checkpoint"), 3.0, 1.0)
	_expect(war.guide.intro_done.has("checkpoint"), "a_phases: checkpoint not cleared with its section dead")
	for c: Dictionary in war.caches:
		if c.name == "Moen farm cache":
			c.taken_by = pf
			c.state = "depleted"
	war.faction(pf).pool.add(&"supplies", 500.0)
	demo.sim.war.dev.start(pf, &"personnel_facilities")
	await _until(func() -> bool: return it.complete(), 3.0, 1.0)
	out["done"] = war.guide.intro_done.duplicate()
	out["complete"] = it.complete()
	var msgs := war.events.filter(func(e: Dictionary) -> bool: return e.kind == "objective_done").map(func(e: Dictionary) -> String: return e.text)
	out["messages"] = msgs
	_expect(it.complete() and msgs.size() == 6, "a_phases: introduction not complete or messages %s" % str(msgs))
	return out


## The introduction progress survives save / load.
func _a_persist() -> Dictionary:
	var war := _war()
	var before: Array = (war.guide.get("intro_done", []) as Array).duplicate()
	demo.construction.save()
	war.guide["intro_done"] = []
	var res := demo.construction.load_game()
	await _physics(5)
	var after: Array = _war().guide.get("intro_done", [])
	_expect(res.ok and after == before and not (_war().guide.get("intro", []) as Array).is_empty(), "a_persist: %s -> %s" % [str(before), str(after)])
	return {"before": before, "after": after}


## The x hides the guidance; the phases still count (the world does not depend on the guide).
func _a_skip() -> Dictionary:
	var war := _war()
	war.guide.erase("intro_complete_at")
	war.guide["off"] = true
	await _physics(10)
	var hidden := not demo.hud.tracker._panel.visible
	_expect(hidden, "a_skip: tracker still shown")
	war.guide.erase("off")
	return {"hidden": hidden}


## The first encounter as a player would start it: the squad ordered to ASSAULT the checkpoint from the start (RTS order,
## real combat, compressed time). It must be winnable without expert play. Records time to contact and the outcome.
## Run alone (--only a_encounter) on a fresh New Game.
func _a_encounter() -> Dictionary:
	var cp := _objective("Moen checkpoint")
	var sq: SquadState = _player_squads()[0]
	demo.rts.select_squads([sq.id])
	var res := demo.rts.order_tactic(SquadState.Tactic.ASSAULT, cp.position)
	_expect(res.get("ok", false), "a_encounter: assault refused: %s" % str(res))
	var t0 := demo.sim.state.time
	var shots0 := demo.sim.combat.shots_total
	var contact := -1.0
	var guards := _squads_at(1, cp.id)
	var shot_taken := false
	CoreDemo.apply_time_scale(4.0)
	var trace := []
	var next_trace := 0.0
	while demo.sim.state.time - t0 < 300.0 and _alive(guards) > 0 and _alive([sq]) > 0:
		await _physics(20)
		if demo.sim.state.time - t0 >= next_trace:
			next_trace += 20.0
			var g: SquadState = guards[0]
			trace.append([roundi(demo.sim.state.time - t0), roundi(WarSim._flat(demo.sim.war.squad_center(sq), cp.position)),
				SquadState.TACTIC_NAMES[sq.tactic], sq.tactic_phase, sq.tactic_why.left(60), SquadState.TACTIC_NAMES[g.tactic],
				roundi(WarSim._flat(demo.sim.war.squad_center(g), cp.position)), demo.sim.combat.shots_total - shots0, _why(sq), _why(g)])
		if contact < 0.0 and demo.sim.combat.shots_total > shots0:
			contact = demo.sim.state.time - t0
		if shots and not shot_taken and contact >= 0.0 and demo.sim.state.time - t0 - contact > 20.0:
			shot_taken = true
			CoreDemo.apply_time_scale(1.0)
			await _frame(cp.position + Vector3(0, 0, -90), 140.0, 0.0)
			_png("a_encounter_fight")
			CoreDemo.apply_time_scale(4.0)
	CoreDemo.apply_time_scale(1.0)
	var out := {"duration_s": roundi(demo.sim.state.time - t0), "first_shot_s": roundi(contact), "guards_left": _alive(guards),
		"player_left": _alive([sq]), "shots": demo.sim.combat.shots_total - shots0, "trace": trace}
	_expect(int(out.guards_left) == 0 and int(out.player_left) >= 5, "a_encounter: not won comfortably: %s" % str(out))
	return out


## What the soldiers of a squad are doing (ai_reason counts, visible targets) - diagnostics.
func _why(sq: SquadState) -> Dictionary:
	var out := {}
	for uid in sq.members:
		var u := demo.sim.state.get_unit(uid)
		if u and u.alive:
			var k := "%s%s" % [u.ai_reason, "+vis" if u.target_visible else ""]
			out[k] = int(out.get(k, 0)) + 1
	return out


## Crossing the road next to the start (seen getting stuck by the product owner): the squad is moved 150 m towards the
## checkpoint with a right-click order, near tier (bodies); per soldier the time to arrive and the stuck stages raised,
## and the road along the line (where it is crossed, its height over the terrain).
func _a_road() -> Dictionary:
	var cp := _objective("Moen checkpoint")
	var sq: SquadState = _player_squads()[0]
	var start := demo.sim.war.squad_center(sq)
	var dir := Vector3(cp.position.x - start.x, 0, cp.position.z - start.z).normalized()
	var line := []
	for i in 76:
		var p := start + dir * float(i) * 2.0
		if demo.sim.state.roads.on_road(p, 0.0):
			var g := demo.on_ground(p.x, p.z, 0.0)
			line.append([i * 2, snappedf(g.y, 0.01)])
	var dest := demo.on_ground(start.x + dir.x * 150.0, start.z + dir.z * 150.0, 0.0)
	demo.rts.select_squads([sq.id])
	await _frame(start + dir * 60.0, 70.0, 0.0)
	var n := demo.rts.order_move(dest)
	var t0 := demo.sim.state.time
	var arrived := {}
	var stuck := {}
	var body_log := {}
	while demo.sim.state.time - t0 < 90.0 and arrived.size() < sq.members.size():
		await _physics(5)
		for uid in sq.members:
			var u := demo.sim.state.get_unit(uid)
			var body := demo.sim.view_of(uid) as SoldierBody
			if body and body._stuck_stage > 0:
				stuck[uid] = maxi(int(stuck.get(uid, 0)), body._stuck_stage)
			if not arrived.has(uid) and WarSim._flat(u.position, dest) < 12.0:
				arrived[uid] = snappedf(demo.sim.state.time - t0, 0.1)
		if demo.sim.state.time - t0 > 25.0:
			for uid in sq.members:
				var b := demo.sim.view_of(uid) as SoldierBody
				if b and not arrived.has(uid) and (body_log.get(uid, []) as Array).size() < 4 and randi() % 6 == 0 and stuck.has(uid):
					if not body_log.has(uid):
						body_log[uid] = []
					body_log[uid].append([snappedf(b.global_position.x, 0.01), snappedf(b.global_position.y, 0.01), snappedf(b.global_position.z, 0.01), b.is_on_floor(), b.is_on_wall(),
						snappedf(b.velocity.length(), 0.01), snappedf(b.dbg_desired, 0.01), b._stuck_stage, snappedf(b._progress_t, 0.1),
						(func() -> Array:
							var c := b.get_last_slide_collision()
							return [] if c == null else [String((c.get_collider() as Node).name) if c.get_collider() is Node else "", c.get_normal().snappedf(0.01), c.get_position().snappedf(0.01)]).call(),
						b.get_floor_normal().snappedf(0.01), b.nav.get_next_path_position().snappedf(0.1), b.dbg_branch, b.nav.get_current_navigation_path().size(), b.nav.get_current_navigation_path_index(), b._unstick_left, b.unit.is_reacting(), b._applied_target.snappedf(0.1)])
		if shots and demo.sim.state.time - t0 > 12.0 and not results.has("_road_shot"):
			results["_road_shot"] = true
			_png("a_road_crossing")
	results.erase("_road_shot")
	var left := {}
	for uid in sq.members:
		if not arrived.has(uid):
			var u := demo.sim.state.get_unit(uid)
			left[uid] = [roundi(WarSim._flat(u.position, dest)), u.ai_reason, String(UnitState.Order.keys()[u.order]), _colliders_near(u.position + Vector3.UP * 0.9, 1.5),
				[snappedf(u.position.x, 0.1), snappedf(u.position.y, 0.01), snappedf(u.position.z, 0.1)], snappedf(demo.on_ground(u.position.x, u.position.z, 0.0).y, 0.01)]
	var out := {"ordered": n, "road_along_line_m": line, "arrived_s": arrived, "not_arrived": left, "stuck_stages": stuck, "ledge_hops": SoldierBody.ledge_hops, "body_log": body_log,
		"near_bodies": demo.sim.view_of(sq.leader_id) is SoldierBody}
	_expect(arrived.size() == sq.members.size(), "a_road: %d of %d soldiers crossed in 90 s: %s" % [arrived.size(), sq.members.size(), str(left)])
	return out


## Physics colliders within r of p (what a body stands against) - diagnostics.
func _colliders_near(p: Vector3, r: float) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, p)
	var out := []
	for h: Dictionary in demo.get_world_3d().direct_space_state.intersect_shape(q, 12):
		var c: Object = h.collider
		var n: Node = c as Node
		out.append("%s:%s" % [c.get_class(), n.name if n else ""] + ("/" + String(n.get_parent().name) if n and n.get_parent() else ""))
	return out


## Terrain profile north of the start (where soldiers stood against an edge): height every 0.5 m along three lines, the
## steepest steps, and what the physics ground reports there (a ray down) - diagnostics only.
func _a_profile() -> Dictionary:
	var out := {}
	var space := demo.get_world_3d().direct_space_state
	await _frame(Vector3(-1330, 190, 6905), 60.0, 0.0)
	await _seconds(2.0)
	for x: float in [-1340.0, -1333.0, -1327.0, -1322.0]:
		var steps := []
		var prev := NAN
		var prev_ray := NAN
		var z := 6870.0
		while z <= 6935.0:
			var h := demo.terrain.data.get_height(Vector3(x, 0, z))
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, h + 5.0, z), Vector3(x, h - 5.0, z))
			var hit := space.intersect_ray(q)
			var ray_y: float = hit.position.y if not hit.is_empty() else NAN
			if not is_nan(prev) and (absf(h - prev) > 0.15 or absf(ray_y - prev_ray) > 0.2):
				steps.append([z, snappedf(h - prev, 0.01), snappedf(ray_y - prev_ray, 0.01), snappedf(ray_y - h, 0.01), String(hit.collider.name) if not hit.is_empty() else ""])
			prev = h
			prev_ray = ray_y
			z += 0.5
		out[str(x)] = steps
	return out


## The eased road shoulders: vegetation of the loaded chunks stands on the ground there (offset 0 .. -0.2 m), and a look at
## the road beside the start.
func _a_shoulders() -> Dictionary:
	var veg := demo.vegetation
	var fpi := VegetationChunk.FLOATS_PER_INSTANCE
	var checked := 0
	var off_ground := 0
	var worst := 0.0
	for loc in veg.chunks:
		var ch: VegetationChunk = veg.chunks[loc]
		for cell in ch.cells:
			if not RoadShoulders.touched.has(cell):
				continue
			for mesh_id in ch.cells[cell]:
				var buf: PackedFloat32Array = ch.cells[cell][mesh_id]
				for i in buf.size() / fpi:
					var k := i * fpi
					var h: float = demo.terrain.data.get_height(Vector3(buf[k + 3], 0.0, buf[k + 11]))
					if is_nan(h):
						continue
					checked += 1
					var off := buf[k + 7] - h
					if off > 0.1 or off < -0.25:
						off_ground += 1
						worst = maxf(worst, absf(off))
	_expect(checked > 100 and off_ground == 0, "a_shoulders: %d of %d instances off the ground (worst %.2f m)" % [off_ground, checked, worst])
	var start := demo.sim.war.squad_center(_player_squads()[0])
	await _frame(start + Vector3(-15, 0, 35), 35.0, 2.4)
	await _seconds(1.5)
	_png("a_road_shoulder")
	return {"touched_cells": RoadShoulders.touched.size(), "instances_checked": checked, "off_ground": off_ground, "worst_m": snappedf(worst, 0.01)}


## Walking through woods near the start (the product owner saw soldiers walk into trunks and slide round them): the squad is
## moved 150 m through the densest trees within 400 m, near tier; per soldier the physics frames spent against a tree
## collider and the movement branch they were in, and the trees the navmesh bake knew about.
func _a_trees() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	var start := demo.sim.war.squad_center(sq)
	var veg := demo.vegetation
	var solid := []
	for d in veg.library.meshes:
		if d.collider.x >= 0.0 and d.collider.x < 1.0:
			solid.append(d.id)
	# The densest 150 m line within 1.5 km of the start (trees within 6 m of it).
	var best_dir := Vector3.ZERO
	var best_n := -1
	var best_from := start
	var count_line := func(from: Vector3, dir: Vector3) -> int:
		var n := 0
		for s2 in range(10, 160, 10):
			var p := from + dir * float(s2)
			for inst in veg.get_cell_instances(VegetationChunk.cell_of(p, veg.cell_size_m), solid):
				var o: Vector3 = (inst[1] as Transform3D).origin
				if Vector2(o.x - p.x, o.z - p.z).length() < 6.0:
					n += 1
		return n
	for gx in range(-6, 7):
		for gz in range(-6, 7):
			var from := start + Vector3(gx * 250.0, 0, gz * 250.0)
			if not demo.sim.war.routes.passable(from):
				continue
			for k in 8:
				var dir := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
				var n: int = count_line.call(from, dir)
				if n > best_n:
					best_n = n
					best_dir = dir
					best_from = from
	# Move the squad there (records first, then the camera so the bodies are made at the new place).
	await _frame(best_from + Vector3(0, 0, 900), 200.0, 0.0)
	await _seconds(2.0)
	var k2 := 0
	for uid in sq.members:
		var u := demo.sim.state.get_unit(uid)
		u.position = demo.on_ground(best_from.x + (k2 % 4) * 2.5 - best_dir.x * 5.0, best_from.z + (k2 / 4) * 2.5 - best_dir.z * 5.0, 0.0)
		u.order = UnitState.Order.NONE
		k2 += 1
	start = best_from
	var dest := demo.on_ground(start.x + best_dir.x * 150.0, start.z + best_dir.z * 150.0, 0.0)
	await _frame(start + best_dir * 60.0, 60.0, 0.0)
	await _seconds(6.0)
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(dest)
	var t0 := demo.sim.state.time
	var hits := {}
	var branches := {}
	var arrived := {}
	while demo.sim.state.time - t0 < 90.0 and arrived.size() < sq.members.size():
		await _physics(1)
		for uid in sq.members:
			var b := demo.sim.view_of(uid) as SoldierBody
			if b == null:
				continue
			if not arrived.has(uid) and WarSim._flat(b.global_position, dest) < 14.0:
				arrived[uid] = snappedf(demo.sim.state.time - t0, 0.1)
			for c in b.get_slide_collision_count():
				var col := b.get_slide_collision(c).get_collider() as Node
				if col and col.name == "InstanceColliders":
					hits[uid] = int(hits.get(uid, 0)) + 1
					branches[b.dbg_branch] = int(branches.get(b.dbg_branch, 0)) + 1
	var out := {"from": [roundi(best_from.x), roundi(best_from.z)], "dir_deg": roundi(rad_to_deg(atan2(best_dir.z, best_dir.x))), "trees_on_line": best_n, "arrived_s": arrived,
		"tree_contact_frames": hits, "contact_branches": branches, "nav_bake": demo.detail.last_bake.duplicate()}
	_png("a_trees")
	return out


func _alive(list: Array) -> int:
	var n := 0
	for g: SquadState in list:
		for uid in g.members:
			var u := demo.sim.state.get_unit(uid)
			if u and u.alive:
				n += 1
	return n

# --- 04B Military Development --------------------------------------------------------------------------------------

## Initial knowledge; a locked building is refused by construction and shown greyed with its reason; the AI is refused too.
func _b_lock() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var dev := _dev()
	var con := demo.construction
	_expect(dev.enabled(), "b_lock: Military Development is off (run with --scenario=new_game)")
	var done: Array = war.faction(pf).dev.get("done", [])
	_expect(done.has("field_command") and done.has("standard_infantry") and not done.has("personnel_facilities"), "b_lock: player knowledge %s" % str(done))
	_expect((war.faction(1).dev.get("done", []) as Array).has("personnel_facilities"), "b_lock: South does not know its barracks")
	var lock := dev.structure_lock(pf, &"barracks_block")
	_expect(lock.begins_with("Locked"), "b_lock: barracks not locked: %s" % lock)
	con.set_active(true)
	con.select_type(&"barracks_block")
	_expect(con.def == null or con.def.id != &"barracks_block", "b_lock: a locked barracks could be selected")
	await _physics(15)
	var card: FNBuildCard = con.panel._base_buttons.get(&"barracks_block")
	var card_state := [card.disabled, card.note_label.text] if card else []
	_expect(card != null and card.disabled and card.note_label.text.begins_with("Locked"), "b_lock: barracks card %s" % str(card_state))
	con.set_active(false)
	var ai := demo.sim.war.bases.request(war.faction(1), &"hq_building", demo.sim.logistics.bases.bases_of(1)[0].anchor, "test")
	_expect(not ai.ok and String(ai.reason).begins_with("Locked"), "b_lock: AI built a locked type: %s" % str(ai))
	return {"done": done, "lock": lock, "card": card_state, "ai": ai.reason}


## Refused without its facility and without money; paid exactly; one project at a time; cancel refunds exactly.
func _b_start() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var dev := _dev()
	var out := {}
	var no_cp := dev.can_start(pf, &"personnel_facilities")
	out["no_cp"] = no_cp.reason
	_expect(not no_cp.ok and "command post" in String(no_cp.reason).to_lower(), "b_start: started without a command post: %s" % str(no_cp))
	if _player_cp() == null:
		_expect(false, "b_start: no command post could be placed")
		return out
	var pool := war.faction(pf).pool
	var keep := pool.get_qty(&"supplies")
	pool.take(&"supplies", keep)
	var no_money := dev.can_start(pf, &"personnel_facilities")
	out["no_money"] = no_money.reason
	_expect(not no_money.ok and bool(no_money.get("cost", false)), "b_start: started without supplies: %s" % str(no_money))
	pool.add(&"supplies", keep + 1000.0)
	var before := float(_stock_of(pf).supplies)
	var r := dev.start(pf, &"personnel_facilities")
	_expect(r.ok, "b_start: refused: %s" % str(r))
	out["paid"] = snappedf(before - float(_stock_of(pf).supplies), 0.1)
	_expect(absf(out.paid - 300.0) < 0.5, "b_start: paid %s instead of 300" % out.paid)
	var second := dev.can_start(pf, &"reconnaissance")
	out["second"] = second.reason
	_expect(not second.ok and "already running" in String(second.reason), "b_start: a second project allowed: %s" % str(second))
	var b2 := float(_stock_of(pf).supplies)
	dev.cancel(pf, &"personnel_facilities")
	out["refund"] = snappedf(float(_stock_of(pf).supplies) - b2, 0.01)
	_expect(absf(out.refund - 300.0) < 0.01 and dev.active_of(pf).is_empty(), "b_start: cancel refunded %s" % out.refund)
	return out


## A disabled facility pauses a running project; repaired, it resumes (a few simulated seconds).
func _b_pause() -> Dictionary:
	var e := _running_project()
	if e.is_empty():
		_expect(false, "b_pause: no running project")
		return {}
	var cp := _player_cp()
	var hp := cp.max_hp()
	demo.sim.state.construction.damage(cp, hp * 0.8)
	await _until(func() -> bool: return false, 1.5, 1.0)
	var p0 := float(e.progress)
	await _until(func() -> bool: return false, 2.0, 1.0)
	var out := {"disabled": cp.is_disabled(), "progress": [snappedf(p0, 0.01), snappedf(float(e.progress), 0.01)], "why": e.get("why", "")}
	_expect(cp.is_disabled() and absf(float(e.progress) - p0) < 0.01 and "paused" in String(out.why), "b_pause: not paused: %s" % str(out))
	cp.hp = hp
	await _until(func() -> bool: return false, 2.5, 1.0)
	out["resumed"] = snappedf(float(e.progress), 0.01)
	_expect(float(e.progress) > p0 + 0.5, "b_pause: did not resume: %s" % str(out))
	return out


## A running project survives save / load with its progress.
func _b_persist() -> Dictionary:
	var pf := _war().player_faction
	var e := _running_project()
	if e.is_empty():
		_expect(false, "b_persist: no running project")
		return {}
	e["progress"] = 42.0
	demo.construction.save()
	e["progress"] = 5.0
	var res := demo.construction.load_game()
	await _physics(5)
	var after := float(_dev().active_entry(pf, &"personnel_facilities").get("progress", -1.0))
	_expect(res.ok and absf(after - 42.0) < 1.5, "b_persist: progress %s after load (%s)" % [after, str(res)])
	return {"loaded": res.ok, "progress": snappedf(after, 0.1)}


## A project that finishes unlocks its building; the knowledge stays when the facility is lost.
func _b_complete() -> Dictionary:
	var pf := _war().player_faction
	var dev := _dev()
	var e := _running_project()
	if e.is_empty():
		_expect(false, "b_complete: no running project")
		return {}
	e["progress"] = DevelopmentDef.by_id(&"personnel_facilities").time_s - 0.5
	await _until(func() -> bool: return dev.is_done(pf, &"personnel_facilities"), 3.0, 1.0)
	_expect(dev.is_done(pf, &"personnel_facilities") and dev.structure_lock(pf, &"barracks_block") == "", "b_complete: not completed / still locked")
	var con := demo.construction
	con.set_active(true)
	con.select_type(&"barracks_block")
	var chosen := con.def != null and con.def.id == &"barracks_block"
	con.set_active(false)
	_expect(chosen, "b_complete: barracks cannot be chosen after the development")
	var cp := _player_cp()
	demo.sim.state.construction.damage(cp, cp.max_hp() * 0.9)
	var kept := dev.is_done(pf, &"personnel_facilities") and dev.structure_lock(pf, &"barracks_block") == ""
	_expect(kept, "b_complete: knowledge lost with the facility")
	cp.hp = cp.max_hp()
	return {"done": dev.is_done(pf, &"personnel_facilities"), "selectable": chosen, "kept_without_cp": kept}


## A future capability cannot start; the reconnaissance effect is what its definition says.
func _b_future() -> Dictionary:
	var pf := _war().player_faction
	var dev := _dev()
	var fut := dev.can_start(pf, &"expanded_coordination")
	_expect(not fut.ok and dev.status(pf, &"expanded_coordination").state == "future", "b_future: a future capability could start: %s" % str(fut))
	var done: Array = _war().faction(pf).dev.done
	done.append("reconnaissance")
	var m := dev.effect(pf, "intel_delay_mult")
	done.erase("reconnaissance")
	_expect(absf(m - 0.4) < 0.01, "b_future: reconnaissance effect %s" % m)
	return {"future": fut.reason, "intel_mult": m}


## F2 opens and closes the screen (screenshot with --shots).
func _b_ui() -> Dictionary:
	if demo.game.mode != GameController.Mode.RTS:
		demo.game.enter_rts()
	_press(KEY_F2)
	await _physics(10)
	var panel := demo.hud.development
	var out := {"visible": panel.visible, "cards": panel._cards.size()}
	_expect(panel.visible and panel._cards.size() >= 12, "b_ui: the screen did not open with F2: %s" % str(out))
	if shots:
		panel.select(&"personnel_facilities")
		await _seconds(1.0)
		_png("b_development_screen")
	_press(KEY_F2)
	await _physics(5)
	out["closed"] = not panel.visible
	_expect(out.closed, "b_ui: F2 did not close the screen")
	return out


## AI policy: an AI faction with money starts a valid project of its preferred branch and pays for it.
func _b_ai() -> Dictionary:
	var dev := _dev()
	var war := _war()
	var out := {}
	for fid in [1, 2]:
		var f := war.faction(fid)
		var before := float(_stock_of(fid).supplies)
		dev._ai_policy(f)
		var act: Array = dev.active_of(fid)
		out[f.faction_name] = {"active": act.map(func(e: Dictionary) -> String: return e.id), "supplies_before": roundi(before),
			"paid": roundi(before - float(_stock_of(fid).supplies))}
		_expect(act.size() == 1, "b_ai: %s started no project with %d kg" % [f.faction_name, roundi(before)])
		if act.size() == 1:
			var d := DevelopmentDef.by_id(StringName(act[0].id))
			_expect(d != null and d.available and not d.initial and dev.status(fid, d.id).state == "active", "b_ai: %s started an invalid project %s" % [f.faction_name, act[0].id])
	return out


## Development Scenario: the system is off - nothing locked (run with --scenario=dev).
func _b_dev_off() -> Dictionary:
	var dev := _dev()
	_expect(not dev.enabled(), "b_dev_off: development is on in %s" % _war().scenario_id)
	var locks := {}
	for id in [&"barracks_block", &"hq_building", &"bunker_fighting", &"repair_bay"]:
		locks[id] = dev.structure_lock(0, id)
		_expect(locks[id] == "", "b_dev_off: %s locked" % id)
	_expect(dev.weapon_lock(0, &"dmr") == "" and dev.role_lock(0, &"marksman") == "", "b_dev_off: weapons locked")
	return {"enabled": dev.enabled(), "locks": locks}


# --- 04C combat accuracy arena -----------------------------------------------------------------------------------------

## The accuracy arena (GAMEPLAY-04C addendum): one AI shooter against one target on open, level ground of the real world,
## through the real CombatBrain / CombatSim (perception, reaction, aim error, weapon spread, LineOfFire, damage). The target
## holds fire and never dies (its health is topped up; hits are counted from WorldState.shot_fired) and makes no cover moves
## (held like a possessed soldier, so it still records suppression); squad tactics are off while it runs, so the numbers are
## marksmanship, not manoeuvre. Far tier (no bodies), seeds 1-3 (the
## world seed drives every aim error and spread). Run once with --legacy-aim for the GAMEPLAY-03 model.
## Cases: [name, weapon, distance, target moving, shooter moving, shooter suppression, proficiency, friend near the line].
const ARENA_CASES := [
	["rifle_50", &"rifle", 50.0, false, false, 0.0, 0.5, false],
	["rifle_100", &"rifle", 100.0, false, false, 0.0, 0.5, false],
	["rifle_200", &"rifle", 200.0, false, false, 0.0, 0.5, false],
	["rifle_300", &"rifle", 300.0, false, false, 0.0, 0.5, false],
	["rifle_100_moving_target", &"rifle", 100.0, true, false, 0.0, 0.5, false],
	["rifle_300_moving_target", &"rifle", 300.0, true, false, 0.0, 0.5, false],
	["rifle_100_moving_shooter", &"rifle", 100.0, false, true, 0.0, 0.5, false],
	["rifle_100_suppressed", &"rifle", 100.0, false, false, 0.7, 0.5, false],
	["rifle_100_recruit", &"rifle", 100.0, false, false, 0.0, 0.1, false],
	["rifle_100_veteran", &"rifle", 100.0, false, false, 0.0, 0.9, false],
	["rifle_300_recruit_moving_target", &"rifle", 300.0, true, false, 0.0, 0.1, false],
	["carbine_50", &"carbine", 50.0, false, false, 0.0, 0.5, false],
	["carbine_100_moving_shooter", &"carbine", 100.0, false, true, 0.0, 0.5, false],
	["carbine_300", &"carbine", 300.0, false, false, 0.0, 0.5, false],
	["dmr_100", &"dmr", 100.0, false, false, 0.0, 0.5, false],
	["dmr_300", &"dmr", 300.0, false, false, 0.0, 0.5, false],
	["dmr_500", &"dmr", 500.0, false, false, 0.0, 0.5, false],
	["lmg_100", &"lmg", 100.0, false, false, 0.0, 0.5, false],
	["lmg_300", &"lmg", 300.0, false, false, 0.0, 0.5, false],
	["lmg_100_moving_shooter", &"lmg", 100.0, false, true, 0.0, 0.5, false],
	["gpmg_300", &"gpmg", 300.0, false, false, 0.0, 0.5, false],
	["gpmg_100_moving_shooter", &"gpmg", 100.0, false, true, 0.0, 0.5, false],
	["rifle_100_friend_near_line", &"rifle", 100.0, false, false, 0.0, 0.5, true],
]
const ARENA_SEEDS := [1, 2, 3]
const ARENA_S := 12.0


func _c_arena() -> Dictionary:
	var sim := demo.sim
	var cs := CombatScenario.new(demo)
	cs.approach_m = 520.0
	var site := cs.find_site()
	_expect(not site.is_empty(), "c_arena: no open site")
	if site.is_empty():
		return {}
	var target_at: Vector3 = site.def
	var dir: Vector3 = site.dir
	var side: Vector3 = site.side
	# Far tier: the camera well away from the arena; then the vegetation of the line is warm for the LOS search below.
	await _frame(target_at + Vector3(0, 0, 3000), 300.0, 0.0)
	await _seconds(2.0)
	# A direction from the target with a clear line (eye to chest) at every distance the cases use.
	var clear_dir := Vector3.ZERO
	for k in 24:
		var dd := Vector3(cos(k * TAU / 24.0), 0, sin(k * TAU / 24.0))
		var ok := true
		for dist: float in [50.0, 100.0, 200.0, 300.0, 400.0, 500.0]:
			var from := demo.on_ground(target_at.x - dd.x * dist, target_at.z - dd.z * dist, 0.0) + Vector3.UP * CombatSim.EYE_HEIGHT
			await _warm_line(from, target_at)
			var r := sim.combat.line.trace(from, target_at + Vector3.UP * 1.2, -1, false)
			if r.blocker != "range":
				ok = false
				break
		if ok:
			clear_dir = dd
			break
	_expect(clear_dir != Vector3.ZERO, "c_arena: no direction with a clear 500 m line at the site")
	if clear_dir != Vector3.ZERO:
		dir = clear_dir
		side = Vector3(-dir.z, 0, dir.x)
	var tactics_were: bool = sim.brain.tactics_enabled
	var squads_were: bool = sim.tactics.enabled
	sim.tactics.enabled = false
	var seed_was: int = sim.state.world_seed
	var out := {"model": "legacy (GAMEPLAY-03)" if not sim.brain.aim_model else "GAMEPLAY-04C", "site": [roundi(target_at.x), roundi(target_at.z)], "cases": {}}
	var usec0: int = sim.brain.update_usec
	var frames0: int = sim.brain.frames
	var pick: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arena="):
			pick = a.trim_prefix("--arena=").split(",")
	for c: Array in ARENA_CASES:
		if sim.combat.weapon(c[1]) == null or (not pick.is_empty() and not pick.has(c[0])):
			continue
		var rows := []
		for s in ARENA_SEEDS:
			sim.state.world_seed = int(s)
			rows.append(await _arena_run(cs, c, target_at, dir, side))
		out.cases[c[0]] = _arena_sum(rows)
	sim.state.world_seed = seed_was
	sim.tactics.enabled = squads_were
	out["brain_usec_per_frame"] = snappedf(float(sim.brain.update_usec - usec0) / maxf(sim.brain.frames - frames0, 1), 0.1)
	cs.reset()
	return out


## One shooter against one target for ARENA_S simulated seconds.
func _arena_run(cs: CombatScenario, c: Array, target_at: Vector3, dir: Vector3, side: Vector3) -> Dictionary:
	var sim := demo.sim
	var d: float = c[2]
	var shooter_sq := cs.spawn(0, target_at - dir * d, dir, 1, "ARENA_S")
	var target_sq := cs.spawn(1, target_at, -dir, 1, "ARENA_T")
	var sh := sim.state.get_unit(shooter_sq.members[0])
	var tg := sim.state.get_unit(target_sq.members[0])
	var role_id: StringName = {&"rifle": &"rifleman", &"carbine": &"carbineer", &"dmr": &"marksman", &"lmg": &"machine_gunner", &"gpmg": &"heavy_gunner"}.get(c[1], &"rifleman")
	sh.role = &""
	sim.combat._equip_role(sh, role_id)
	sh.grenades = 0
	sh.sec_id = &""
	sh.proficiency = float(c[6])
	target_sq.roe = SquadState.Roe.HOLD_FIRE
	# Held like the possessed soldier: it records the suppression it takes but makes no cover moves of its own.
	tg.player_controlled = true
	tg.max_health = 100000.0
	tg.health = 100000.0
	var friend: UnitState = null
	if c[7]:
		var fsq := cs.spawn(0, target_at - dir * (d * 0.5) + side * 1.2, dir, 1, "ARENA_F")
		friend = sim.state.get_unit(fsq.members[0])
		fsq.roe = SquadState.Roe.HOLD_FIRE
		friend.player_controlled = true
		friend.max_health = 100000.0
		friend.health = 100000.0
	var rec := {"shots": 0, "hits": 0, "friend_hits": 0, "first_shot": -1.0, "first_hit": -1.0, "bursts": 0, "last_shot": -10.0, "blockers": {}}
	var t0 := sim.state.time
	var on_shot := func(shot: Dictionary) -> void:
		if int(shot.get("shooter", -1)) != sh.id:
			return
		var t := sim.state.time - t0
		rec.shots += 1
		if t - float(rec.last_shot) > 0.3:
			rec.bursts += 1
		rec.last_shot = t
		if float(rec.first_shot) < 0.0:
			rec.first_shot = t
		var bl := String(shot.get("blocker", ""))
		rec.blockers[bl] = int(rec.blockers.get(bl, 0)) + 1
		if int(shot.get("hit_unit", -1)) == tg.id:
			rec.hits += 1
			if float(rec.first_hit) < 0.0:
				rec.first_hit = t
		elif friend and int(shot.get("hit_unit", -1)) == friend.id:
			rec.friend_hits += 1
	sim.state.shot_fired.connect(on_shot)
	var holds0: int = sim.brain.friendly_holds
	var supp_max := 0.0
	var flip := 1.0
	var next_flip := 0.0
	CoreDemo.apply_time_scale(6.0)
	while sim.state.time - t0 < ARENA_S:
		await _physics(2)
		var now := sim.state.time
		tg.health = tg.max_health
		sh.mag = maxi(sh.mag, 1)
		sh.reserve = 500
		if c[5] > 0.0:
			sh.suppression = float(c[5])
			sh.suppression_t = now
		if friend:
			friend.health = friend.max_health
		supp_max = maxf(supp_max, tg.suppression_at(now))
		if now - t0 >= next_flip:
			next_flip += 6.0
			flip = -flip
			if c[3]:
				tg.order = UnitState.Order.MOVE
				tg.order_target = demo.on_ground(target_at.x + side.x * 15.0 * flip, target_at.z + side.z * 15.0 * flip, 0.0)
			if c[4]:
				sh.order = UnitState.Order.MOVE
				sh.order_target = demo.on_ground(sh.position.x + side.x * 15.0 * flip, sh.position.z + side.z * 15.0 * flip, 0.0)
	CoreDemo.apply_time_scale(1.0)
	sim.state.shot_fired.disconnect(on_shot)
	for u: UnitState in [sh, tg, friend]:
		if u:
			cs.unit_ids.erase(u.id)
			sim.state.remove_unit(u.id)
	await _physics(2)
	return {"shots": rec.shots, "hits": rec.hits, "friend_hits": rec.friend_hits, "first_shot": rec.first_shot, "first_hit": rec.first_hit,
		"bursts": rec.bursts, "supp": supp_max, "friendly_holds": sim.brain.friendly_holds - holds0, "blockers": rec.blockers}


func _arena_sum(rows: Array) -> Dictionary:
	var shots := 0
	var hits := 0
	var fh := 0
	var bursts := 0
	var holds := 0
	var fs := []
	var fhit := []
	var supp := 0.0
	var blockers := {}
	for r: Dictionary in rows:
		for b in r.blockers:
			blockers[b] = int(blockers.get(b, 0)) + int(r.blockers[b])
		shots += int(r.shots)
		hits += int(r.hits)
		fh += int(r.friend_hits)
		bursts += int(r.bursts)
		holds += int(r.friendly_holds)
		supp += float(r.supp)
		if float(r.first_shot) >= 0.0:
			fs.append(float(r.first_shot))
		if float(r.first_hit) >= 0.0:
			fhit.append(float(r.first_hit))
	var avg := func(a: Array) -> float:
		var t := 0.0
		for v in a:
			t += float(v)
		return snappedf(t / a.size(), 0.1) if not a.is_empty() else -1.0
	return {"shots": shots, "hits": hits, "hit_pct": snappedf(100.0 * hits / maxf(shots, 1), 0.1), "first_shot_s": avg.call(fs),
		"first_hit_s": avg.call(fhit), "no_hit_runs": rows.size() - fhit.size(), "burst_len": snappedf(float(shots) / maxf(bursts, 1), 0.1),
		"target_suppression": snappedf(supp / rows.size(), 0.01), "friend_hits": fh, "friendly_holds": holds, "blockers": blockers}


## The arena line (shared by the narrow weapon checks): open level ground of the real world with a clear line from 50 to
## 500 m, the camera far away (far tier). {cs, at, dir, side} or {} when no site.
func _arena_line(near := false) -> Dictionary:
	var sim := demo.sim
	var cs := CombatScenario.new(demo)
	cs.approach_m = 520.0
	var site := cs.find_site()
	if site.is_empty():
		return {}
	var at: Vector3 = site.def
	# Near: the camera over the site, so bodies, vegetation and lines are loaded as in play.
	await _frame(at + Vector3(0, 0, 3000) if not near else at, 300.0 if not near else 220.0, 0.0)
	await _seconds(2.0 if not near else 5.0)
	for k in 24:
		var dd := Vector3(cos(k * TAU / 24.0), 0, sin(k * TAU / 24.0))
		var ok := true
		for dist: float in [50.0, 150.0, 330.0, 500.0]:
			var from := demo.on_ground(at.x - dd.x * dist, at.z - dd.z * dist, 0.0) + Vector3.UP * CombatSim.EYE_HEIGHT
			await _warm_line(from, at)
			if sim.combat.line.trace(from, at + Vector3.UP * 1.2, -1, false).blocker != "range":
				ok = false
				break
		if ok:
			if near:
				await _frame(at - dd * 120.0, 260.0, 0.0)
				await _seconds(3.0)
			return {"cs": cs, "at": at, "dir": dd, "side": Vector3(-dd.z, 0, dd.x)}
	return {}


## Waits until CombatBrain has the vegetation of the cells along a line (it fills a cell per frame; far from the camera a
## fresh line is unknown for a while - a soldier cannot see along it and a line test would miss its trees).
func _warm_line(a: Vector3, b: Vector3) -> void:
	var n := 0
	while not demo.sim.brain._line_warm(a, b) and n < 400:
		await _physics(1)
		n += 1


## One soldier of faction f in a role at p facing `face` (a fresh squad of one).
func _soldier(cs: CombatScenario, f: int, p: Vector3, face: Vector3, role_id: StringName) -> UnitState:
	var sq := cs.spawn(f, p, face, 1)
	var u := demo.sim.state.get_unit(sq.members[0])
	# Exactly at p (a fresh squad lines its soldiers up beside the spawn point).
	u.position = demo.on_ground(p.x, p.z, 0.0)
	u.anchor_pos = u.position
	var body := demo.sim.view_of(u.id) as Node3D
	if body:
		body.global_position = u.position + Vector3.UP * 0.1
	u.role = &""
	demo.sim.combat._equip_role(u, role_id)
	return u


## The 40 mm grenade launcher: an AI grenadier fires at two enemies standing together 150 m away, the round comes down there
## (blast near them, suppression); with a friend beside the targets it holds.
func _c_gl() -> Dictionary:
	var sim := demo.sim
	var L := await _arena_line(true)
	_expect(not L.is_empty(), "c_gl: no arena line")
	if L.is_empty():
		return {}
	var cs: CombatScenario = L.cs
	sim.tactics.enabled = false
	var gren := _soldier(cs, 0, L.at - L.dir * 150.0, L.dir, &"grenadier_gl")
	gren.grenades = 0
	var t1 := _soldier(cs, 1, L.at, -L.dir, &"rifleman")
	var t2 := _soldier(cs, 1, L.at + L.side * 2.0, -L.dir, &"rifleman")
	for t in [t1, t2]:
		t.player_controlled = true
		t.max_health = 100000.0
		t.health = t.max_health
	var fired0 := sim.brain.gl_fired
	var bursts := []
	var on_burst := func(e: Dictionary) -> void:
		if int(e.get("src", -1)) == gren.id:
			bursts.append(roundi(WarSim._flat(e.at, L.at)))
	var conn := sim.state.has_signal("explosive_burst")
	if conn:
		sim.state.explosive_burst.connect(on_burst)
	var t0 := sim.state.time
	CoreDemo.apply_time_scale(4.0)
	var trace := []
	while sim.state.time - t0 < 20.0 and sim.brain.gl_fired - fired0 < 2:
		await _physics(4)
		if trace.size() < 8 and Engine.get_physics_frames() % 40 < 5:
			trace.append([snappedf(sim.state.time - t0, 0.1), gren.ai_reason, gren.target_id, gren.target_visible, gren.sec_ammo, snappedf(gren.sec_ready_at - sim.state.time, 0.1)])
		t1.health = t1.max_health
		t2.health = t2.max_health
		gren.reserve = 200
	await _until(func() -> bool: return false, 4.0, 4.0)
	CoreDemo.apply_time_scale(1.0)
	var fired := sim.brain.gl_fired - fired0
	var supp := maxf(t1.suppression_at(sim.state.time), t2.suppression_at(sim.state.time))
	var out := {"fired": fired, "rounds_left": gren.sec_ammo, "target_suppression": snappedf(supp, 0.01), "bursts_m_from_targets": bursts, "holds": sim.brain.gl_holds.duplicate(), "trace": trace}
	_expect(fired >= 1 and gren.sec_ammo < 6, "c_gl: the grenadier did not fire at two enemies at 150 m: %s" % str(out))
	# A friend beside the target: the launcher's own decision (called directly, everything else ready) holds the round.
	var friend := _soldier(cs, 0, t1.position + L.side * 6.0, L.dir, &"rifleman")
	friend.position = t1.position + L.side * 6.0
	await _physics(2)
	var now := sim.state.time
	gren.sec_ready_at = 0.0
	gren.moved_at = now - 10.0
	sim.brain._squad_gl_at.clear()
	sim.brain._rocket_check.erase(gren.id)
	var holds0 := int(sim.brain.gl_holds.get("friend near the impact", 0))
	var fired_near := sim.brain._grenade_launcher(gren, t1, sim.combat.weapon(&"gl40"), t1.position, false, sim.state.squad_of(gren.id), now)
	out["fired_with_friend_6m"] = fired_near
	out["friend_holds"] = int(sim.brain.gl_holds.get("friend near the impact", 0)) - holds0
	out["holds_after"] = sim.brain.gl_holds.duplicate()
	out["direct_call"] = {"d": snappedf(WarSim._flat(gren.position, t1.position), 0.1), "friend_m": snappedf(WarSim._flat(friend.position, t1.position), 0.1),
		"sec_ammo": gren.sec_ammo, "group": sim.brain._group_near(t1, 6.0)}
	_expect(not fired_near and out.friend_holds == 1, "c_gl: fired with a friend 6 m from the impact: %s" % str(out))
	if conn:
		sim.state.explosive_burst.disconnect(on_burst)
	sim.tactics.enabled = true
	cs.reset()
	return out


## The 84 mm recoilless rifle reaches an enemy position at 330 m (the light launcher holds there: range); one AT gunner and
## one grenadier side by side against a South fighting position with a soldier in it.
func _c_recoilless() -> Dictionary:
	var sim := demo.sim
	var L := await _arena_line(true)
	if L.is_empty():
		_expect(false, "c_recoilless: no arena line")
		return {}
	var cs: CombatScenario = L.cs
	sim.tactics.enabled = false
	var fp := _add_built(&"fighting_position", L.at, -L.dir, 1)
	_expect(fp != null, "c_recoilless: no fighting position could be placed")
	if fp == null:
		return {}
	var enemy := _soldier(cs, 1, fp.position + L.side * 3.5, -L.dir, &"rifleman")
	enemy.player_controlled = true
	enemy.max_health = 100000.0
	var at := _soldier(cs, 0, fp.position - L.dir * 330.0, L.dir, &"at_gunner")
	var gr := _soldier(cs, 0, fp.position - L.dir * 330.0 + L.side * 4.0, L.dir, &"grenadier")
	at.grenades = 0
	gr.grenades = 0
	var at0 := at.sec_ammo
	var gr0 := gr.sec_ammo
	var hp0 := fp.health_frac()
	CoreDemo.apply_time_scale(4.0)
	var t0 := sim.state.time
	var trace := []
	while sim.state.time - t0 < 25.0 and at.sec_ammo == at0:
		await _physics(4)
		if trace.size() < 8 and Engine.get_physics_frames() % 40 < 5:
			trace.append([snappedf(sim.state.time - t0, 0.1), at.ai_reason, at.target_id, at.target_visible, at.sec_ammo])
		enemy.health = enemy.max_health
		at.reserve = 200
		gr.reserve = 200
	await _until(func() -> bool: return false, 3.0, 4.0)
	CoreDemo.apply_time_scale(1.0)
	var out := {"at_rounds_used": at0 - at.sec_ammo, "light_rounds_used": gr0 - gr.sec_ammo, "position_health": [snappedf(hp0, 0.01), snappedf(fp.health_frac(), 0.01)],
		"holds": sim.brain.rocket_holds.duplicate(), "trace": trace}
	_expect(out.at_rounds_used >= 1 and fp.health_frac() < hp0, "c_recoilless: no 84 mm round on the position at 330 m: %s" % str(out))
	_expect(out.light_rounds_used == 0, "c_recoilless: the light launcher fired beyond its reach: %s" % str(out))
	sim.state.construction.remove(fp.id)
	sim.tactics.enabled = true
	cs.reset()
	return out


## The heavy machine gun slows its carrier, in the far tier as in the near one (the same factor): a heavy gunner and a
## rifleman walk 60 m side by side.
func _c_carry() -> Dictionary:
	var sim := demo.sim
	var L := await _arena_line()
	if L.is_empty():
		_expect(false, "c_carry: no arena line")
		return {}
	var cs: CombatScenario = L.cs
	var hg := _soldier(cs, 0, L.at - L.dir * 300.0, L.dir, &"heavy_gunner")
	var rf := _soldier(cs, 0, L.at - L.dir * 300.0 + L.side * 4.0, L.dir, &"rifleman")
	var times := {}
	for u: UnitState in [hg, rf]:
		u.order = UnitState.Order.MOVE
		u.order_target = demo.on_ground(u.position.x + L.dir.x * 60.0, u.position.z + L.dir.z * 60.0, 0.0)
	var t0 := sim.state.time
	CoreDemo.apply_time_scale(4.0)
	while sim.state.time - t0 < 40.0 and times.size() < 2:
		await _physics(2)
		for u: UnitState in [hg, rf]:
			if not times.has(u.role) and u.order != UnitState.Order.MOVE:
				times[u.role] = snappedf(sim.state.time - t0, 0.1)
	CoreDemo.apply_time_scale(1.0)
	var out := {"seconds": times, "factor": sim.carry_speed(hg)}
	_expect(times.size() == 2 and float(times.heavy_gunner) > float(times.rifleman) * 1.15, "c_carry: the heavy gunner is not slower: %s" % str(out))
	cs.reset()
	return out


## First person: the possessed marksman fires the weapon itself - its own spread, no AI aim error. Ten aimed shots at a man
## 50 m away all hit (DMR spread 0.02 deg = 2 cm at 50 m); the line is checked first (a precondition, not a result).
func _c_fps() -> Dictionary:
	var sim := demo.sim
	var L := await _arena_line(true)
	if L.is_empty():
		_expect(false, "c_fps: no arena line")
		return {}
	var cs: CombatScenario = L.cs
	var dm := _soldier(cs, 0, L.at - L.dir * 50.0, L.dir, &"marksman")
	var tg := _soldier(cs, 1, L.at, -L.dir, &"rifleman")
	tg.player_controlled = true
	tg.max_health = 100000.0
	await _physics(10)
	demo.game.possess(dm.id)
	await _seconds(0.5)
	var hits := 0
	var o0 := CombatSim.eye_of(dm)
	var pre := sim.combat.line.trace(o0, tg.position + Vector3.UP * 1.3, dm.id, false)
	_expect(pre.blocker == "range", "c_fps: precondition - no clear line to the target (%s at %.1f m)" % [pre.blocker, pre.distance])
	for i in 10:
		tg.health = tg.max_health
		var origin := CombatSim.eye_of(dm)
		var aim := tg.position + Vector3.UP * 1.3
		dm.next_shot_at = 0.0
		dm.last_shot_at = -100.0
		var r := sim.combat.request_fire(dm.id, origin, (aim - origin).normalized(), CombatSim.Source.PLAYER)
		if int(r.get("hit_unit", -1)) == tg.id:
			hits += 1
		elif i < 3:
			results["c_fps_miss_%d" % i] = [r.get("reason", ""), r.get("blocker", ""), snappedf(float(r.get("distance", 0.0)), 0.1), r.get("hit_unit", -1), tg.id]
		await _physics(2)
	demo.game.enter_rts()
	var out := {"hits_of_10": hits, "weapon": String(dm.weapon_id)}
	_expect(hits == 10, "c_fps: aimed player shots missed: %s" % str(out))
	cs.reset()
	return out


## Role, proficiency, the secondary weapon and its rounds survive save / load.
func _c_persist() -> Dictionary:
	var sim := demo.sim
	var u: UnitState = sim.state.get_unit(_player_squads()[0].members[1])
	u.role = &""
	sim.combat._equip_role(u, &"grenadier_gl")
	u.proficiency = 0.8
	u.sec_ammo = 4
	var before := [String(u.role), String(u.weapon_id), String(u.sec_id), u.sec_ammo, u.proficiency]
	demo.construction.save()
	u.proficiency = 0.1
	var res := demo.construction.load_game()
	await _physics(5)
	var v: UnitState = demo.sim.state.get_unit(u.id)
	var after := [String(v.role), String(v.weapon_id), String(v.sec_id), v.sec_ammo, v.proficiency]
	_expect(res.ok and str(before) == str(after), "c_persist: %s -> %s" % [str(before), str(after)])
	return {"before": before, "after": after}


## AI factions field the new weapons through the same rules: South without the developments arms a new squad as standard;
## with them (and its base's supply depot and ammunition magazine) as the scenario's support squad - heavy gunner, marksman,
## 40 mm grenadier - each wearing the faction's loadout for the role.
func _c_ai_comp() -> Dictionary:
	var sim := demo.sim
	var war := _war()
	var south := war.faction(1)
	var at: Vector3 = sim.logistics.bases.bases_of(1)[0].anchor
	var sq0 := sim.war.spawn_squad(south, demo.on_ground(at.x + 40.0, at.z + 40.0, 0.0), 8)
	var roles0 := []
	for id in sq0.members:
		roles0.append(String(sim.state.get_unit(id).role))
	_expect(not roles0.has("heavy_gunner") and roles0.has("machine_gunner"), "c_ai_comp: undeveloped South fielded new roles: %s" % str(roles0))
	var done: Array = south.dev.done
	for d in ["infantry_equipment", "marksman", "advanced_support"]:
		if not done.has(d):
			done.append(d)
	var sq1 := sim.war.spawn_squad(south, demo.on_ground(at.x + 60.0, at.z + 40.0, 0.0), 8)
	var roles1 := []
	var looks := []
	for id in sq1.members:
		var u := sim.state.get_unit(id)
		roles1.append(String(u.role))
		looks.append(u.loadout)
	var usable := {}
	for r in [&"heavy_gunner", &"marksman", &"grenadier_gl"]:
		usable[r] = sim.war.dev.role_usable(1, r)
	_expect(roles1.has("heavy_gunner") and roles1.has("marksman") and roles1.has("grenadier_gl"), "c_ai_comp: developed South did not field the support squad: %s (%s)" % [str(roles1), str(usable)])
	for lo in looks:
		_expect(InfantryLoadout.by_id(lo) != null, "c_ai_comp: missing loadout %s" % lo)
	for id in Array(sq0.members) + Array(sq1.members):
		sim.state.remove_unit(id)
	return {"undeveloped": roles0, "developed": roles1, "loadouts": looks, "usable": usable}


## The new weapons as they look: a NATO squad of every new role in the near tier (third person), first person with the DMR,
## the raised 40 mm launcher and the 84 mm recoilless rifle (screenshots with --shots; checks that the loadouts are worn).
func _c_visual() -> Dictionary:
	var sim := demo.sim
	var sq: SquadState = _player_squads()[0]
	var roles := [&"carbineer", &"marksman", &"heavy_gunner", &"grenadier_gl", &"at_gunner", &"rifleman", &"machine_gunner", &"grenadier"]
	for i in sq.members.size():
		var u := sim.state.get_unit(sq.members[i])
		u.role = &""
		sim.combat._equip_role(u, roles[i % roles.size()])
	var c := sim.war.squad_center(sq)
	if demo.game.mode != GameController.Mode.RTS:
		demo.game.enter_rts()
	await _frame(c, 14.0, 0.5)
	await _seconds(3.0)
	_png("c_third_person_roles_wide")
	await _frame(c, 7.0, 0.5)
	await _seconds(1.5)
	var worn := {}
	for id in sq.members:
		var u := sim.state.get_unit(id)
		var body := sim.view_of(id) as SoldierBody
		worn[String(u.role)] = [u.loadout, body != null and body.character != null and body.character.loadout != null and body.character.loadout.id == u.loadout,
			body.is_visible_in_tree() if body else false, body.character.get_child_count() if body and body.character else -1,
			snappedf(body.global_position.y - u.position.y, 0.01) if body else 0.0, String(UnitState.Order.keys()[u.order]), u.tactic, u.down_until > sim.state.time]
	_png("c_third_person_roles")
	var out := {"worn": worn}
	for e: Array in [[&"marksman", "c_fps_dmr", false], [&"grenadier_gl", "c_fps_gl40", true], [&"at_gunner", "c_fps_recoilless", true]]:
		var who := -1
		for id in sq.members:
			if sim.state.get_unit(id).role == e[0]:
				who = id
				break
		if who < 0:
			continue
		demo.game.possess(who)
		await _seconds(1.0)
		if e[2]:
			_press(KEY_X)
			await _seconds(1.2)
		_png(e[1])
		if e[2]:
			_press(KEY_X)
			await _seconds(0.5)
		demo.game.enter_rts()
		await _seconds(0.5)
	for r in worn:
		_expect(bool(worn[r][1]), "c_visual: %s does not wear %s" % [r, worn[r][0]])
	return out


# --- 04D squad equipment, REARM, discovery ---------------------------------------------------------------------------------

func _eqs() -> SquadEquipment:
	return demo.sim.war.equip


func _stash_named(n: String) -> Dictionary:
	for s: Dictionary in _war().stashes:
		if s.name == n:
			return s
	return {}


## Puts a squad's records at p (far tier: the camera is moved away first so no body holds them back).
func _move_squad(sq: SquadState, p: Vector3) -> void:
	await _frame(p + Vector3(0, 0, 2500), 300.0, 0.0)
	await _seconds(1.5)
	var k := 0
	for uid in sq.members:
		var u := demo.sim.state.get_unit(uid)
		u.position = demo.on_ground(p.x + (k % 4) * 2.0, p.z + (k / 4) * 2.0, 0.0)
		u.order = UnitState.Order.NONE
		u.anchor_pos = u.position
		k += 1
	sq.order = SquadState.Order.NONE
	await _physics(5)


## The finds are where the scenario put them and each faction knows its own weapon types (the player only the standard ones).
func _d_setup() -> Dictionary:
	var war := _war()
	var names := war.stashes.map(func(s: Dictionary) -> String: return "%s %s" % [s.name, str(s.items)])
	_expect(not _stash_named("Moen checkpoint stores").is_empty() and not _stash_named("Abandoned army depot").is_empty() and not _stash_named("Verket yard cache").is_empty(),
		"d_setup: stashes %s" % str(names))
	var pd: Array = war.faction(war.player_faction).discovered
	_expect(pd.has("rifle") and pd.has("lmg") and not pd.has("dmr") and not pd.has("carbine"), "d_setup: player discovered %s" % str(pd))
	_expect((war.faction(1).discovered as Array).has("dmr"), "d_setup: South does not know the DMR")
	var lock := demo.sim.war.dev.weapon_lock(war.player_faction, &"carbine")
	_expect(lock.begins_with("Not discovered"), "d_setup: carbine lock %s" % lock)
	return {"stashes": names, "player_discovered": pd, "carbine_lock": lock}


## REARM at the checkpoint stores: missing ammunition topped up from the stash, the unknown carbine into the cargo, the stash
## emptied of it; a new order cancels a REARM in progress.
func _d_rearm() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	var st := _stash_named("Moen checkpoint stores")
	# The checkpoint is cleared first (its stores lie among the South fire team): REARM waits while the squad is under fire.
	for g: SquadState in _squads_at(1, _objective("Moen checkpoint").id):
		for gid in g.members.duplicate():
			demo.sim.combat.kill(demo.sim.state.get_unit(gid))
	await _move_squad(sq, st.pos + Vector3(8, 0, 8))
	var u := demo.sim.state.get_unit(sq.members[0])
	u.reserve = 10
	var ammo0 := float(st.ammo)
	var r := _eqs().order_rearm([sq.id], st.pos)
	_expect(r.ok and sq.rearm_at.is_finite(), "d_rearm: order refused %s" % str(r))
	var trace := []
	for i in 6:
		await _until(func() -> bool: return false, 2.0, 2.0)
		trace.append([snappedf(sq.rearm_s, 0.1), roundi(WarSim._flat(demo.sim.war.squad_center(sq), sq.rearm_at)) if sq.rearm_at.is_finite() else -1,
			demo.sim.tactics.assessment(sq).get("under_fire", "?"), String(SquadState.Order.keys()[sq.order]), demo.sim.war.enabled])
		if not sq.rearm_at.is_finite():
			break
	results["d_rearm_trace"] = trace
	var out := {"order": r.text, "reserve": u.reserve, "cargo": sq.cargo.duplicate(), "stash_ammo": [roundi(ammo0), roundi(float(st.ammo))], "stash_items": st.items.duplicate()}
	_expect(not sq.rearm_at.is_finite(), "d_rearm: the search did not finish")
	_expect(u.reserve > 10 and int(sq.cargo.get("carbine", 0)) == 1 and not st.items.has("carbine") and float(st.ammo) < ammo0, "d_rearm: %s" % str(out))
	# Cancel: a move order ends a REARM.
	_eqs().order_rearm([sq.id], st.pos)
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(st.pos + Vector3(40, 0, 0))
	out["cancelled"] = not sq.rearm_at.is_finite()
	_expect(out.cancelled, "d_rearm: a move order did not cancel the REARM")
	return out


## In the field a soldier takes the found carbine from the cargo (half a load; his rifle goes into the cargo); a third
## machine gunner is refused (squad limit); the procured ones are refused away from a base.
func _d_field_equip() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	if not sq.cargo.has("carbine"):
		sq.cargo["carbine"] = 1
	var u: UnitState = null
	for uid in sq.members:
		var m := demo.sim.state.get_unit(uid)
		if m.role == &"rifleman":
			u = m
			break
	var r := _eqs().equip(sq, u, &"carbineer")
	var wd := demo.sim.combat.weapon(&"carbine")
	var out := {"result": r, "weapon": String(u.weapon_id), "reserve": u.reserve, "cargo": sq.cargo.duplicate(), "loadout": u.loadout}
	_expect(r.ok and u.weapon_id == &"carbine" and u.reserve == wd.reserve_start / 2 and int(sq.cargo.get("rifle", 0)) == 1 and not sq.cargo.has("carbine"), "d_field_equip: %s" % str(out))
	var gunners := 0
	for uid in sq.members:
		if demo.sim.state.get_unit(uid).role == &"machine_gunner":
			gunners += 1
	var r2 := {}
	for uid in sq.members:
		var m := demo.sim.state.get_unit(uid)
		if m.role == &"rifleman":
			r2 = _eqs().can_equip(sq, m, &"machine_gunner")
			break
	out["second_mg"] = r2.get("reason", "")
	var r3 := {}
	for uid in sq.members:
		var m := demo.sim.state.get_unit(uid)
		if m.role == &"rifleman":
			r3 = _eqs().can_equip(sq, m, &"grenadier_gl")
			break
	out["gl_in_field"] = r3.get("reason", "")
	_expect(not r3.get("ok", true) and "base" in String(r3.reason), "d_field_equip: a weapon not carried was issued in the field: %s" % str(r3))
	return out


## A squad with a found DMR enters its base (command post and supply depot): the DMR goes to the armoury and the type is
## registered; Marksman Specialization no longer lacks its discovery.
func _d_deliver() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var cp := _player_cp()
	var depot := _add_built(&"supply_depot", cp.position + Vector3(40, 0, 0), Vector3(0, 0, -1), pf)
	_expect(depot != null, "d_deliver: no depot could be placed")
	var sq: SquadState = _player_squads()[0]
	sq.cargo["dmr"] = 1
	await _move_squad(sq, cp.position + Vector3(15, 0, 15))
	await _until(func() -> bool: return sq.cargo.is_empty(), 5.0, 1.0)
	var f := war.faction(pf)
	var req := demo.sim.war.dev.requirements(pf, DevelopmentDef.by_id(&"marksman")).filter(func(r: Dictionary) -> bool: return r.kind == "discovery")
	var out := {"cargo": sq.cargo.duplicate(), "armory": f.armory.duplicate(), "discovered": f.discovered.duplicate(), "marksman_discovery": req}
	_expect(sq.cargo.is_empty() and int(f.armory.get("dmr", 0)) >= 1 and f.discovered.has("dmr") and not req.is_empty() and req[0].ok, "d_deliver: %s" % str(out))
	var msgs := war.events.filter(func(e: Dictionary) -> bool: return e.kind == "discovery").map(func(e: Dictionary) -> String: return e.text)
	out["messages"] = msgs
	_expect(not msgs.is_empty(), "d_deliver: no discovery message")
	return out


## At the base: the armoury's DMR is issued without any development (found equipment is usable), procuring a second one is
## locked until Marksman Specialization; a discovered carbine is procured for its price.
func _d_procure() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	var sq: SquadState = _player_squads()[0]
	f.armory["dmr"] = 1
	if not f.discovered.has("carbine"):
		f.discovered.append("carbine")
	f.pool.add(&"supplies", 500.0)
	f.pool.add(&"ammo", 100.0)
	var riflemen := []
	for uid in sq.members:
		var m := demo.sim.state.get_unit(uid)
		if m.role == &"rifleman":
			riflemen.append(m)
	var out := {}
	var a := _eqs().equip(sq, riflemen[0], &"marksman")
	out["from_armory"] = a
	_expect(a.ok and riflemen[0].weapon_id == &"dmr" and not f.armory.has("dmr") and int(f.armory.get("rifle", 0)) >= 1, "d_procure: armoury DMR not issued: %s" % str(a))
	var b := _eqs().can_equip(sq, riflemen[1], &"marksman")
	out["second_dmr"] = b.reason
	_expect(not b.ok and String(b.reason).contains("Locked"), "d_procure: a second DMR without development: %s" % str(b))
	var st0 := demo.sim.logistics.bases.faction_stock(pf)
	var c := _eqs().equip(sq, riflemen[1], &"carbineer")
	var st1 := demo.sim.logistics.bases.faction_stock(pf)
	out["procured_carbine"] = c
	out["paid"] = [snappedf(float(st0.supplies) - float(st1.supplies), 0.1), snappedf(float(st0.ammo) - float(st1.ammo), 0.1)]
	_expect(c.ok and absf(out.paid[0] - 40.0) < 0.5 and absf(out.paid[1] - 15.0) < 0.5, "d_procure: carbine procurement %s paid %s" % [str(c), str(out.paid)])
	return out


## A soldier who dies leaves his weapon where he fell (a stash of the fallen), merged with others nearby.
func _d_fallen() -> Dictionary:
	var war := _war()
	var n0 := war.stashes.size()
	var south := war.faction(1)
	var p := demo.on_ground(-1000.0, 6500.0, 0.0)
	var sq := demo.sim.war.spawn_squad(south, p, 2)
	var a := demo.sim.state.get_unit(sq.members[0])
	var b := demo.sim.state.get_unit(sq.members[1])
	demo.sim.combat.kill(a)
	demo.sim.combat.kill(b)
	await _physics(3)
	var fallen := war.stashes.filter(func(s: Dictionary) -> bool: return s.kind == "fallen" and WarSim._flat(s.pos, p) < 20.0)
	var out := {"new_stashes": war.stashes.size() - n0, "fallen": fallen.map(func(s: Dictionary) -> Dictionary: return {"items": s.items, "ammo": snappedf(float(s.ammo), 0.1)})}
	var n := 0
	for s2: Dictionary in fallen:
		for k in s2.items:
			n += int(s2.items[k])
	_expect(fallen.size() == 1 and n == 2 and float(fallen[0].ammo) > 0.0, "d_fallen: %s" % str(out))
	return out


## Saved and loaded: stashes, cargo, armoury and discoveries come back as saved - a REARM after the save does not survive the
## load (no duplication).
func _d_persist() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var sq: SquadState = _player_squads()[0]
	sq.cargo = {"gl40": 1}
	var depot := _stash_named("Abandoned army depot")
	var before := {"cargo": sq.cargo.duplicate(), "depot": depot.items.duplicate(), "armory": war.faction(pf).armory.duplicate(), "discovered": war.faction(pf).discovered.duplicate()}
	demo.construction.save()
	# After the save: take everything from the depot.
	_eqs().rearm(sq, depot.pos)
	var res := demo.construction.load_game()
	await _physics(5)
	var w2 := _war()
	var sq2 := demo.sim.state.get_squad(sq.id)
	var after := {"cargo": sq2.cargo.duplicate(), "depot": _stash_named("Abandoned army depot").items.duplicate(), "armory": w2.faction(pf).armory.duplicate(), "discovered": w2.faction(pf).discovered.duplicate()}
	_expect(res.ok and str(before) == str(after), "d_persist: %s -> %s" % [str(before), str(after)])
	return {"before": before, "after": after}


## The equipment screen from the command panel's EQUIP button (screenshot with --shots).
func _d_ui() -> Dictionary:
	var sq: SquadState = _player_squads()[0]
	if demo.game.mode != GameController.Mode.RTS:
		demo.game.enter_rts()
	demo.rts.select_squads([sq.id])
	await _frame(demo.sim.war.squad_center(sq), 60.0, 0.4)
	await _physics(10)
	demo.hud.tactical_panel._on_button(TacticalPanel.EQUIP)
	await _seconds(1.0)
	var ep := demo.hud.equipment
	var out := {"visible": ep.visible, "rows": ep.pickers.size()}
	_expect(ep.visible and ep.pickers.size() == sq.members.size(), "d_ui: equipment screen %s" % str(out))
	_png("d_equipment_screen")
	ep.visible = false
	return out


# --- 04E opportunities ------------------------------------------------------------------------------------------------

func _opps() -> Opportunities:
	return demo.sim.war.opps


## The introduction over: the world offers what is really there (a known cache, an enemy-held objective near), nothing is
## spawned for it, at most four at once.
func _end_intro() -> void:
	_war().guide["intro_complete_at"] = snappedf(demo.sim.state.time, 0.1)


func _e_offer() -> Dictionary:
	var soldiers0 := demo.sim.state.count_of(UnitState.Kind.SOLDIER)
	_expect(_opps().open().is_empty(), "e_offer: offers during the introduction")
	_end_intro()
	await _until(func() -> bool: return not _opps().open().is_empty(), 6.0, 2.0)
	var open := _opps().open()
	var kinds := open.map(func(o: Dictionary) -> String: return o.kind)
	var out := {"offers": open.map(func(o: Dictionary) -> String: return "%s: %s" % [o.kind, o.title]), "soldiers": [soldiers0, demo.sim.state.count_of(UnitState.Kind.SOLDIER)]}
	_expect(open.size() >= 2 and open.size() <= Opportunities.MAX_OPEN and kinds.has("supplies") and kinds.has("assault"), "e_offer: %s" % str(out))
	_expect(soldiers0 == demo.sim.state.count_of(UnitState.Kind.SOLDIER), "e_offer: soldiers appeared with the offers")
	_expect(not kinds.has("recon"), "e_offer: reconnaissance offered without the development")
	return out


## Achieved, accepted or not, they pay: the accepted assault when the objective is the player's, the ignored cache when it is
## secured.
func _e_complete() -> Dictionary:
	if _opps().open().is_empty():
		await _e_offer()
	var war := _war()
	var pf := war.player_faction
	var assault: Dictionary = {}
	var supplies: Dictionary = {}
	for o: Dictionary in _opps().open():
		if o.kind == "assault" and assault.is_empty():
			assault = o
		if o.kind == "supplies" and supplies.is_empty():
			supplies = o
	_opps().accept(int(assault.id))
	var st0 := demo.sim.logistics.bases.faction_stock(pf)
	war.objective(int(assault.ref)).owner = pf
	for c: Dictionary in war.caches:
		if int(c.id) == int(supplies.ref):
			c.state = "depleted"
			c.taken_by = pf
	await _until(func() -> bool: return assault.state == "done" and supplies.state == "done", 6.0, 2.0)
	var st1 := demo.sim.logistics.bases.faction_stock(pf)
	var out := {"assault": assault.state, "supplies_opp": supplies.state, "gain": [roundi(float(st1.supplies) - float(st0.supplies)), roundi(float(st1.ammo) - float(st0.ammo))]}
	_expect(assault.state == "done" and supplies.state == "done" and out.gain[0] >= 400 and out.gain[1] >= 100, "e_complete: %s" % str(out))
	return out


## Reconnaissance is offered only with its development, and done when a soldier has watched from within reach.
func _e_recon() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	_end_intro()
	(war.faction(pf).dev.done as Array).append("reconnaissance")
	for o: Dictionary in _opps().open():
		_opps().dismiss(int(o.id))
	await _until(func() -> bool: return _opps().open().any(func(o: Dictionary) -> bool: return o.kind == "recon"), 70.0, 8.0)
	var recon: Dictionary = {}
	for o: Dictionary in _opps().open():
		if o.kind == "recon":
			recon = o
	_expect(not recon.is_empty(), "e_recon: no reconnaissance offered: %s" % str(_opps().open().map(func(o: Dictionary) -> String: return o.title)))
	if recon.is_empty():
		return {}
	var u := demo.sim.state.get_unit(_player_squads()[0].members[0])
	u.position = demo.on_ground(recon.pos.x + 150.0, recon.pos.z + 150.0, 0.0)
	u.order = UnitState.Order.NONE
	await _until(func() -> bool: return recon.state == "done", 30.0, 2.0)
	_expect(recon.state == "done", "e_recon: not done after watching: %s" % str(recon))
	return {"recon": recon.title, "state": recon.state}


func _e_persist() -> Dictionary:
	_end_intro()
	await _until(func() -> bool: return not _opps().open().is_empty(), 6.0, 2.0)
	var before := str(_opps().open().map(func(o: Dictionary) -> String: return "%d %s %s" % [o.id, o.kind, o.state]))
	demo.construction.save()
	var res := demo.construction.load_game()
	await _physics(5)
	var after := str(_opps().open().map(func(o: Dictionary) -> String: return "%d %s %s" % [o.id, o.kind, o.state]))
	_expect(res.ok and before == after and before != "[]", "e_persist: %s -> %s" % [before, after])
	return {"before": before, "after": after}


## The tracker lists the offers with Accept; accepting one marks it (screenshot with --shots).
func _e_ui() -> Dictionary:
	_end_intro()
	await _until(func() -> bool: return not _opps().open().is_empty(), 6.0, 2.0)
	if demo.game.mode != GameController.Mode.RTS:
		demo.game.enter_rts()
	await _until(func() -> bool: return false, 26.0, 8.0)
	await _physics(10)
	var tr := demo.hud.tracker
	var out := {"title": tr._title.text, "rows": tr._list.get_child_count()}
	_expect(tr._panel.visible and tr._title.text == "Opportunities", "e_ui: tracker %s" % str(out))
	var first: Dictionary = _opps().offered()[0] if not _opps().offered().is_empty() else {}
	if not first.is_empty():
		_opps().accept(int(first.id))
		await _seconds(1.0)
		out["target"] = tr.target_label
		var texts := []
		for c in tr._list.get_children():
			texts.append([c.get_class(), c.is_queued_for_deletion(), (c as FNStatusIndicator).text_label.text if c is FNStatusIndicator else ((c.get_child(0) as FNStatusIndicator).text_label.text if c.get_child_count() > 0 and c.get_child(0) is FNStatusIndicator else "")])
		out["children"] = texts
		out["accepted"] = _opps().accepted().map(func(o: Dictionary) -> String: return o.title)
		_expect(tr.target.is_finite(), "e_ui: the accepted opportunity has no marker")
		await _frame(tr.target + Vector3(0, 0, -200), 400.0, 0.0)
		await _seconds(2.0)
	var geo := []
	for c in tr._list.get_children():
		geo.append([c.get_class(), c.visible, c.position.round(), c.size.round()])
	out["geo"] = geo
	out["all"] = _opps()._list().map(func(o: Dictionary) -> String: return "%d %s %s %s" % [o.id, o.kind, o.state, o.get("done_at", "")])
	out["panel"] = [tr._panel.position.round(), tr._panel.size.round(), tr._list.size.round(), tr._brief.visible, tr._foot.visible]
	_png("e_opportunities")
	return out


# --- 04G performance ---------------------------------------------------------------------------------------------------

## The GAMEPLAY-03 DEFEND planning spike: three South squads at one of its objectives, an enemy reported there, all told to
## DEFEND in the same tactics step. Measures the judged post plans of that step (count, cost) - the step a player feels.
func _g_defend_spike() -> Dictionary:
	var sim := demo.sim
	var war := _war()
	var bid: int = sim.logistics.bases.main_base(1)
	var obj: ObjectiveState = sim.war.base_objective(bid)
	if obj == null:
		for o: ObjectiveState in war.owned_by(1):
			if o.is_hq():
				obj = o
	_expect(obj != null, "g_defend_spike: no South base objective")
	if obj == null:
		return {}
	var anchor: Vector3 = sim.state.construction.bases[bid].anchor
	sim.war.intel.report_objective(1, 0, obj, 8)
	await _until(func() -> bool: return false, 8.0, 2.0)
	var sqs := []
	for k in 3:
		var sq := sim.war.spawn_squad(war.faction(1), demo.on_ground(anchor.x + (k - 1) * 30.0, anchor.z - 20.0, 0.0), 8)
		sqs.append(sq)
	await _physics(5)
	sim.tactics.plans_tick_max = 0
	sim.tactics.plan_tick_usec_max = 0
	sim.tactics.plan_usec_max = 0
	var step0 := sim.tactics.step_usec_max
	sim.tactics.step_usec_max = 0
	# The way it happens in play: three AI squads ordered to garrison the same base take up their posts in the same step.
	for sq: SquadState in sqs:
		sim.tactics.assign_garrison(sq, bid, SquadState.Owner.SQUAD)
	var deferred0 := sim.tactics.deferred
	await _until(func() -> bool: return sqs.all(func(s2: SquadState) -> bool: return s2.tactic == SquadState.Tactic.DEFEND), 20.0, 1.0)
	var out := {"defending": sqs.map(func(s2: SquadState) -> bool: return s2.tactic == SquadState.Tactic.DEFEND), "deferred": sim.tactics.deferred - deferred0,
		"plans_per_tick_max": sim.tactics.plans_tick_max, "plan_ms_max": snappedf(sim.tactics.plan_usec_max / 1000.0, 0.1),
		"plan_tick_ms_max": snappedf(sim.tactics.plan_tick_usec_max / 1000.0, 0.1), "step_ms_max": snappedf(sim.tactics.step_usec_max / 1000.0, 0.1)}
	_expect(out.defending.all(func(x: bool) -> bool: return x), "g_defend_spike: not every squad took up the defence: %s" % str(out))
	_expect(int(out.plans_per_tick_max) <= 1, "g_defend_spike: several defence plans in one step: %s" % str(out))
	sim.tactics.step_usec_max = maxi(step0, sim.tactics.step_usec_max)
	for sq: SquadState in sqs:
		for id in Array(sq.members):
			sim.state.remove_unit(id)
	return out


# --- 04G the first hour, from the start screen ---------------------------------------------------------------------------

var _marks := {}


func _mark(key: String) -> void:
	if not _marks.has(key):
		_marks[key] = snappedf(demo.sim.state.time, 1.0)


func _player_shots() -> int:
	return int(_marks.get("_shots", 0))


## The first hour as a player plays it, through the game's own controls (run with --menu-shot: New Game is pressed on the
## start screen). Twenty steps of the brief, each logged with its simulated time; the timeline marks feed the report.
func _g_playthrough() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var rts := demo.rts
	var con := demo.construction
	_steps.clear()
	var shot_counter := func(shot: Dictionary) -> void:
		var u := demo.sim.state.get_unit(int(shot.get("shooter", -1)))
		if u and u.faction == pf:
			_marks["_shots"] = int(_marks.get("_shots", 0)) + 1
			_mark("first_combat")
	demo.sim.state.shot_fired.connect(shot_counter)
	# 1-2. New Game; the situation.
	var sq: SquadState = _player_squads()[0]
	_step_log(1, "New Game started from the start screen", war.scenario_id == "new_game" and _player_squads().size() == 1, {"scenario": war.scenario_id})
	await _frame(demo.sim.war.squad_center(sq) + Vector3(0, 0, -60), 160.0, 0.0)
	await _seconds(2.0)
	_png("g01_start")
	_step_log(2, "situation shown: briefing and first objective", demo.hud.tracker._panel.visible and demo.hud.tracker.current_id == "command")
	# 3. Command the squad: select, move towards the checkpoint.
	rts.select_squads([sq.id])
	var cp_obj := _objective("Moen checkpoint")
	var mid := demo.sim.war.squad_center(sq).lerp(cp_obj.position, 0.35)
	rts.order_move(demo.on_ground(mid.x, mid.z, 0.0))
	_mark("first_action")
	await _until(func() -> bool: return war.guide.get("intro_done", []).has("command"), 60.0, 2.0)
	_step_log(3, "squad selected and moved (first objective done)", war.guide.intro_done.has("command"))
	# 4-5. First person and back.
	demo.game.possess(sq.leader_id)
	await _seconds(1.5)
	_png("g04_first_person")
	_step_log(4, "first person as the squad leader", demo.game.mode == GameController.Mode.FPS)
	demo.game.enter_rts()
	await _seconds(1.0)
	_step_log(5, "back to the tactical view", demo.game.mode == GameController.Mode.RTS)
	# 6. The map.
	demo.toggle_map()
	await _seconds(1.5)
	_png("g06_map")
	_step_log(6, "strategic map", demo.strategic_map.visible and war.guide.get("map", false))
	demo.toggle_map()
	await _seconds(0.5)
	# 7. The first encounter: the checkpoint, ordered as an assault from the tactical view.
	rts.select_squads([sq.id])
	rts.order_tactic(SquadState.Tactic.ASSAULT, cp_obj.position)
	var guards := _squads_at(1, cp_obj.id)
	var shot_taken := false
	var t_fight := demo.sim.state.time
	CoreDemo.apply_time_scale(4.0)
	while demo.sim.state.time - t_fight < 360.0 and _alive(guards) > 0 and _alive([sq]) > 0:
		await _physics(20)
		if not shot_taken and _marks.has("first_combat") and demo.sim.state.time - float(_marks.first_combat) > 15.0:
			shot_taken = true
			CoreDemo.apply_time_scale(1.0)
			await _frame(cp_obj.position + Vector3(0, 0, -110), 150.0, 0.0)
			await _seconds(1.0)
			_png("g07_first_encounter")
			CoreDemo.apply_time_scale(4.0)
	CoreDemo.apply_time_scale(1.0)
	_mark("checkpoint_cleared")
	_step_log(7, "first encounter: checkpoint cleared", _alive(guards) == 0, {"alive": _alive([sq]), "fight_s": roundi(demo.sim.state.time - t_fight)})
	# 8. Supplies: the cache behind the checkpoint, REARM at the checkpoint's stores.
	var cache := {}
	for c: Dictionary in war.caches:
		if c.name == "Moen farm cache":
			cache = c
	rts.select_squads([sq.id])
	rts.order_move(cache.pos)
	await _until(func() -> bool: return cache.state == "depleted", 240.0, 4.0)
	_mark("first_reward")
	var stores := _stash_named("Moen checkpoint stores")
	rts.select_squads([sq.id])
	rts.order_rearm_at(stores.pos)
	await _until(func() -> bool: return not sq.rearm_at.is_finite(), 120.0, 4.0)
	await _frame(cache.pos, 70.0, 0.4)
	await _seconds(1.0)
	_png("g08_supplies_rearm")
	_step_log(8, "supplies secured and rearmed at the checkpoint", int(cache.get("taken_by", -1)) == pf and sq.cargo.has("carbine"), {"cargo": sq.cargo.duplicate(), "stock": _stock()})
	# 9. A Command Post through the construction tool (placed near the farm), built by the squad.
	var spot := _cp_spot(demo.sim.war.squad_center(sq))
	await _frame(spot, 60.0)
	con.set_active(true)
	con.select_type(&"command_post")
	con.mouse_override = demo.rts_camera.camera.unproject_position(spot)
	await _seconds(1.0)
	con.primary_action()
	con.mouse_override = Vector2.INF
	con.set_active(false)
	var cp: StructureState = null
	for s: StructureState in demo.sim.state.construction.all():
		if s.faction == pf and s.type_id == &"command_post":
			cp = s
	if cp == null:
		_step_log(9, "command post placed", false, {"message": con.message})
		return _play_out(shot_counter)
	await _until(func() -> bool: return not cp.is_site(), 240.0, 4.0)
	_mark("first_construction")
	_step_log(9, "command post built: a base", not cp.is_site() and not demo.sim.logistics.bases.bases_of(pf).is_empty())
	# 10-11. Military Development: F2, Barracks & Personnel started and completed (a supply depot meanwhile).
	rts.select([])
	_press(KEY_F2)
	await _physics(10)
	var dp := demo.hud.development
	dp.select(&"personnel_facilities")
	await _seconds(1.0)
	_png("g10_development")
	dp._on_start()
	_mark("dev_started")
	_step_log(10, "Military Development opened, Barracks & Personnel started", dp.visible and not demo.sim.war.dev.active_entry(pf, &"personnel_facilities").is_empty())
	_press(KEY_F2)
	var depot := _place(&"supply_depot", _site_in_base(&"supply_depot", cp.position))
	await _until(func() -> bool: return demo.sim.war.dev.is_done(pf, &"personnel_facilities") and depot != null and not depot.is_site(), 400.0, 6.0)
	_mark("first_unlock")
	_step_log(11, "first development complete, supply depot built (11a)", demo.sim.war.dev.is_done(pf, &"personnel_facilities") and depot != null and not depot.is_site())
	# The carbine in the cargo is handed in at the base (the squad stands in it) and registered.
	await _until(func() -> bool: return war.faction(pf).discovered.has("carbine"), 60.0, 2.0)
	_mark("discovery")
	# The hint asks for it before the barracks: a guard tower and two fighting positions facing north (where South is).
	var forts := []
	for e: Array in [[&"guard_tower_steel", Vector3(0, 0, 45)], [&"fighting_position", Vector3(-25, 0, 50)], [&"fighting_position", Vector3(25, 0, 50)]]:
		var sp := _site_in_base(e[0], cp.position + e[1])
		if sp.is_finite():
			var st := _place(e[0], sp)
			if st:
				forts.append(st)
	await _until(func() -> bool: return forts.all(func(x: StructureState) -> bool: return not x.is_site()), 300.0, 6.0)
	_mark("fortified")
	_step_log(11, "base fortified (guard tower, fighting positions)", forts.size() >= 2 and forts.all(func(x: StructureState) -> bool: return not x.is_site()), {"forts": forts.size(), "stock": _stock()})
	# 12-13. Barracks (unlocked now), recruit.
	await _until(func() -> bool: return _stock().supplies >= 560.0, 600.0, 8.0)
	var barracks := _place(&"barracks_block", _site_in_base(&"barracks_block", cp.position))
	await _until(func() -> bool: return barracks != null and not barracks.is_site(), 600.0, 6.0)
	_step_log(12, "barracks built (unlocked by the development)", barracks != null and not barracks.is_site())
	await _until(func() -> bool: return _stock().supplies >= 330.0 and _stock().ammo >= 200.0, 900.0, 8.0)
	rts.select([])
	rts.selected_structure = barracks.id
	await _frame(barracks.position + Vector3(0, 0, 25), 55.0)
	await _seconds(1.0)
	var pressed := _press_panel_button("RECRUIT")
	var n0 := _player_squads().size()
	await _until(func() -> bool: return _player_squads().size() > n0, 120.0, 4.0)
	var recruit: SquadState = _player_squads().back()
	_step_log(13, "squad recruited at the barracks", pressed and _player_squads().size() > n0)
	# 14. The new weapon: a soldier of the recruit squad takes the registered carbine from the armoury (equipment screen).
	rts.select_squads([recruit.id])
	await _seconds(0.5)
	demo.hud.tactical_panel._on_button(TacticalPanel.EQUIP)
	await _seconds(1.0)
	# Re-equipping waits while the squad is under fire (it may be, at the base): give it the time a player would.
	await _until(func() -> bool: return int(demo.sim.tactics.assessment(recruit).get("under_fire", 0)) == 0, 180.0, 4.0)
	var who := -1
	for uid in recruit.members:
		if demo.sim.state.get_unit(uid).role == &"rifleman":
			who = uid
			break
	var eq: Dictionary = demo.hud.equipment.apply_choice(who, &"carbineer")
	await _seconds(1.0)
	_png("g14_equipment")
	demo.hud.equipment.visible = false
	_mark("first_new_weapon")
	_step_log(14, "registered carbine issued to a recruit (equipment screen)", eq.get("ok", false) and demo.sim.state.get_unit(who).weapon_id == &"carbine", {"result": eq})
	# The recruits garrison the base (O); the first squad is refilled at the barracks before it moves on.
	rts.select_squads([recruit.id])
	rts.order_garrison(barracks.base_id)
	var refill := demo.sim.logistics.bases.replenish(barracks.id, sq.id)
	await _until(func() -> bool: return sq.members.size() >= 8 or not refill.get("ok", false), 120.0, 4.0)
	_marks["refill"] = refill.get("reason", "ok")
	# 15. An opportunity: the introduction is over; take the Verket roadblock.
	await _until(func() -> bool: return demo.sim.war.intro.complete() and not demo.sim.war.opps.open().is_empty(), 60.0, 4.0)
	var opp := {}
	for o: Dictionary in demo.sim.war.opps.open():
		if String(o.title).contains("Verket roadblock"):
			opp = o
	if opp.is_empty() and not demo.sim.war.opps.open().is_empty():
		opp = demo.sim.war.opps.open()[0]
	if not opp.is_empty():
		demo.sim.war.opps.accept(int(opp.id))
	await _frame(demo.sim.war.squad_center(sq), 160.0)
	await _seconds(1.0)
	_png("g15_opportunity")
	_step_log(15, "opportunity accepted", not opp.is_empty() and opp.state == "accepted", {"opportunity": opp.get("title", "-"), "open": demo.sim.war.opps.open().map(func(o: Dictionary) -> String: return o.title)})
	# 16. Another encounter: both squads assault the roadblock.
	var rb := _objective("Verket roadblock")
	var rb_guards := _squads_at(1, rb.id)
	rts.select_squads([sq.id])
	rts.order_tactic(SquadState.Tactic.ASSAULT, rb.position)
	var t2 := demo.sim.state.time
	var shot2 := false
	CoreDemo.apply_time_scale(6.0)
	while demo.sim.state.time - t2 < 900.0 and _alive(rb_guards) > 0 and _alive([sq]) > 0:
		await _physics(20)
		if not shot2 and _alive(rb_guards) < 4:
			shot2 = true
			CoreDemo.apply_time_scale(1.0)
			await _frame(rb.position + Vector3(0, 0, 100), 150.0, 3.14)
			await _seconds(1.0)
			_png("g16_second_encounter")
			CoreDemo.apply_time_scale(6.0)
	CoreDemo.apply_time_scale(1.0)
	_step_log(16, "second encounter: Verket roadblock", _alive(rb_guards) == 0, {"alive": [_alive([sq]), _alive([recruit])], "fight_s": roundi(demo.sim.state.time - t2),
		"base_held": not demo.sim.logistics.bases.bases_of(pf).is_empty()})
	# 17-19. Save (F5), load (F9), the progression intact, orders still work.
	var snap := _progress_snapshot()
	_press(KEY_F5)
	await _seconds(1.5)
	_step_log(17, "game saved (F5)", FileAccess.file_exists(con.save_path))
	_press(KEY_F9)
	await _seconds(3.0)
	await _physics(10)
	var snap2 := _progress_snapshot()
	_step_log(18, "game loaded (F9)", str(snap) == str(snap2), {"before": snap, "after": snap2})
	var sq_l: SquadState = _player_squads()[0] if not _player_squads().is_empty() else null
	if sq_l == null:
		_step_log(19, "orders work after loading", false, {"why": "no squad left"})
		return _play_out(shot_counter)
	rts.select_squads([sq_l.id])
	var moved := rts.order_move(demo.on_ground(rb.position.x, rb.position.z + 60.0, 0.0))
	_step_log(19, "orders work after loading", moved > 0)
	# 20. The sandbox goes on: time, the war, opportunities.
	var t3 := demo.sim.state.time
	await _until(func() -> bool: return false, 120.0, 8.0)
	_step_log(20, "the sandbox continues after the introduction", demo.sim.state.time > t3 + 100.0 and demo.sim.war.enabled and not demo.sim.war.opps.open().is_empty(),
		{"open": demo.sim.war.opps.open().map(func(o: Dictionary) -> String: return o.title)})
	await _frame(demo.sim.war.squad_center(sq_l), 200.0)
	await _seconds(1.0)
	_png("g20_sandbox")
	return _play_out(shot_counter)


func _progress_snapshot() -> Dictionary:
	var war := _war()
	var pf := war.player_faction
	var f := war.faction(pf)
	# (Supplies are left out: income keeps arriving between the snapshot and the save.)
	return {"done": f.dev.get("done", []).duplicate(), "discovered": f.discovered.duplicate(), "armory": f.armory.duplicate(),
		"squads": _player_squads().size(), "bases": demo.sim.logistics.bases.bases_of(pf).size(), "intro": war.guide.get("intro_done", []).duplicate(),
		"opps": demo.sim.war.opps.open().size()}


func _play_out(counter: Callable) -> Dictionary:
	if demo.sim.state.shot_fired.is_connected(counter):
		demo.sim.state.shot_fired.disconnect(counter)
	var marks := _marks.duplicate()
	marks.erase("_shots")
	return {"steps": _steps, "timeline_s": marks, "player_shots": _player_shots(), "tactics": demo.sim.tactics.summary().judged_plans}


# --- Output ------------------------------------------------------------------------------------------------------

func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/gameplay04_test.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("G4 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	tree.quit()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("G4 %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("G4 FAILED CHECK: ", msg)
