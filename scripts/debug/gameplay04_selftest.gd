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
const CHECKS: Array[String] = ["a_setup", "a_ui", "a_phases", "a_persist", "a_skip", "a_road", "a_profile", "a_shoulders", "a_trees", "a_encounter", "b_lock", "b_start", "b_pause", "b_persist", "b_complete", "b_future", "b_ui", "b_ai", "b_dev_off"]
const ONLY_NAMED: Array[String] = ["b_dev_off", "a_encounter", "a_road", "a_profile", "a_trees"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/gameplay04"
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	SoldierBody.require_mouse_capture = false
	tree.create_timer(900.0, true, false, true).timeout.connect(func() -> void:
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
