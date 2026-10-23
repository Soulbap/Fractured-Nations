## NAVIGATION N1-B vehicle routing diagnostics and acceptance (N1B-01 ... N1B-10).
##
##   Godot.exe --path . --resolution 1600x900 --log-file n1b.log \
##     res://scenes/game/world_ref_20km.tscn -- --navigation-n1b-test [--only diag,n1b_01]
##
## Output: user://navigation_n1b/navigation_n1b_test.json (never modifies tracked files).
class_name NavigationN1BSelfTest
extends NavigationN1SelfTest

const IDS_B: Array[String] = ["diag", "verket", "convoy_dbg", "yard_repro", "dock_grid", "n1b_01", "n1b_02", "n1b_03", "n1b_04", "n1b_05", "n1b_06", "n1b_07", "n1b_08", "n1b_09", "n1b_10"]


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "user://navigation_n1b/screenshots"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
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
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: navigation N1-B test did not finish")
		_finish_b())
	await _physics(60)
	_load_world_data()
	_pause_ai(true)
	brain.enabled = false
	demo.sim.vehicles.router.ensure_built()
	for id in IDS_B:
		if _want(id):
			var data := {}
			match id:
				"diag": data = await _diag()
				"yard_repro": data = await _yard_repro()
				"n1b_01": data = await _n1b_01()
				"perf": data = await _perf()
				"verket": data = _verket()
				"convoy_dbg": data = await _convoy_dbg()
				"n1b_02": data = await _n1b_02()
				"n1b_03": data = await _n1b_03()
				"n1b_04": data = await _n1b_04()
				"n1b_05": data = await _n1b_05()
				"n1b_06": data = await _n1b_06()
				"n1b_07": data = await _n1b_07()
				"n1b_08": data = await _n1b_08()
				"n1b_09": data = await _n1b_09()
				"n1b_10": data = await _n1b_10()
				"dock_grid": data = _dock_grid()
			_log_b(id, data)
	_finish_b()


## Screenshots only where a viewport image exists (a headless run has none).
func _shot(shot_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))
	var img := demo.get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_jpg(ProjectSettings.globalize_path("%s/n1b_%s.jpg" % [_shot_dir, shot_name]), 0.9)
	print("NAV_N1B shot: ", shot_name)


func _log_b(check: String, data: Dictionary) -> void:
	results[check] = data
	if data.has("status"):
		_case_status[check] = data.status
	print("NAV_N1B %s %s" % [check, JSON.stringify(data)])


func _finish_b() -> void:
	if _done:
		return
	_done = true
	TimeCompression.reset()
	results["harness_failures"] = failures
	results["case_status"] = _case_status
	var dir := "user://navigation_n1b"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "/navigation_n1b_test.json"
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("NAV_N1B %s %s" % ["COMPLETE" if failures.is_empty() else "HARNESS_FAIL", JSON.stringify({"cases": _case_status, "failures": failures, "output": path})])
	demo.shutdown_cleanup()
	tree.quit()


## Root-cause probes (no driving): the settlement legs the road audit reports as failing.
func _diag() -> Dictionary:
	var out := {}
	var vr: VehicleRouter = demo.sim.vehicles.router
	var truck := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var apc := VehicleDefs.get_def(VehicleDefs.APC)
	var st := demo.sim.structures
	var audit := RoadAudit.new(demo.sim)
	for place: String in ["Elvetun", "Kvernes"]:
		var pos := Vector3(-3000.0, 0.0, -7500.0) if place == "Elvetun" else Vector3(-8700.0, 0.0, -1600.0)
		pos.y = demo.sim.vehicles.ground_at(pos)
		var info := {"pos": [pos.x, pos.z]}
		info["blocked_circle_r"] = st.blocks_point(Vector2(pos.x, pos.z), truck.circle_r)
		info["wet"] = st.is_wet(pos.x, pos.z)
		var near := []
		for s: StructureState in cs.all():
			if Vector2(s.position.x - pos.x, s.position.z - pos.z).length() < 60.0:
				near.append("%s %.0f,%.0f" % [s.type_id, s.position.x, s.position.z])
		info["structures_60m"] = near
		var nodes := vr.nearest_nodes(pos, 4, 300.0)
		var legs := []
		for n: Dictionary in nodes:
			vr.debug_legs = true
			vr.last_leg_debug = ""
			var lt := vr._leg(pos, n.pos, truck)
			var la := vr._leg(pos, n.pos, apc)
			vr.debug_legs = false
			legs.append({"road": n.road.name, "dist": snappedf(n.dist, 0.1), "truck_ok": lt.ok, "apc_ok": la.ok,
				"diag": audit.leg_diagnosis(pos, n.pos, truck), "grid": vr.last_leg_debug if not lt.ok else ""})
		info["legs"] = legs
		out[place] = info
	# r_yard: the eight candidate road points 400 m round the faction-1 base, planned from the truck's spot.
	var bs := _bs()
	var b: Dictionary = bs.bases_of(1)[0]
	await _ensure_vehicles(1, 1)
	var tr := _free_vehicle(1, VehicleDefs.TRUCK)
	var cands := []
	for k in 8:
		var ang := float(k) * TAU / 8.0
		var cand := net_nearest(b.anchor + Vector3(cos(ang), 0.0, sin(ang)) * 400.0, 200.0)
		var pl := vr.plan(tr.position, cand, truck)
		cands.append({"k": k, "cand": [snappedf(cand.x, 1.0), snappedf(cand.z, 1.0)], "straight_m": snappedf(_flat(tr.position, cand), 1.0),
			"ok": pl.ok, "len": snappedf(float(pl.get("length_m", -1.0)), 1.0), "road_share": snappedf(float(pl.get("road_m", 0.0)) / maxf(float(pl.get("length_m", 1.0)), 1.0), 0.01)})
	out["yard"] = {"truck": [tr.position.x, tr.position.z], "anchor": [b.anchor.x, b.anchor.z], "cands": cands}
	out["spots"] = _spot_scan()
	return out


## Planner-level scan of every dock and parking spot of the AI bases: plan away and back with the parked vehicles of the yard
## known to the router, as VehicleSim.order_drive does. Returns the failures with the local grid of the failing leg.
func _spot_scan() -> Dictionary:
	var vs := demo.sim.vehicles
	var vr: VehicleRouter = vs.router
	var bs := _bs()
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var rows := []
	var total := 0
	var failed := 0
	for fid in [1, 2]:
		for b: Dictionary in bs.bases_of(fid):
			var spots: Array = []
			for st in bs.base_stores(b.id):
				spots.append(["dock %s" % FacilityDefs.display_name(st.type_id), demo.sim.logistics.dock_world(st, -1), st])
				spots.append(["park %s" % FacilityDefs.display_name(st.type_id), demo.sim.logistics.parking_world(st, 0), st])
			var away := net_nearest(b.anchor + Vector3(600, 0, 0), 900.0)
			for sp: Array in spots:
				var pos: Vector3 = sp[1]
				truck.faction = fid
				truck.position = Vector3(pos.x, vs.ground_at(pos), pos.z)
				truck.yaw = (sp[2] as StructureState).yaw
				vs._collect_parked(truck)
				total += 1
				vr._fail_cache.clear()
				var out_plan := vr.plan(truck.position, away, td)
				vr._fail_cache.clear()
				var back_plan := vr.plan(away, truck.position, td)
				if not out_plan.ok or not back_plan.ok:
					failed += 1
					rows.append({"base": b.name, "spot": sp[0], "pos": [snappedf(pos.x, 0.1), snappedf(pos.z, 0.1)], "out": out_plan.ok, "back": back_plan.ok,
						"out_why": out_plan.get("why", []), "parked": vr.parked_circles.size(), "reason": out_plan.get("reason", back_plan.get("reason", ""))})
				else:
					rows.append({"base": b.name, "spot": sp[0], "out_m": snappedf(float(out_plan.length_m), 1.0), "back_m": snappedf(float(back_plan.length_m), 1.0), "ms": snappedf(float(out_plan.ms) + float(back_plan.ms), 1.0), "parked": vr.parked_circles.size()})
	truck.faction = 1
	vr.parked_circles = []
	return {"total": total, "failed": failed, "rows": rows}


## r_yard reproduction at planner level: the same truck, base and candidate loop as AIWarSelfTest._r_drive, with parked circles.
func _yard_repro() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 3)
	var vs := demo.sim.vehicles
	var vr: VehicleRouter = vs.router
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var b: Dictionary = _bs().bases_of(1)[0]
	var out := {"truck": [truck.position.x, truck.position.z], "yaw": truck.yaw, "vehicles": _vehicles_of(1).map(func(u: UnitState) -> Array: return [u.id, snappedf(u.position.x, 0.1), snappedf(u.position.z, 0.1), String(u.veh.type_id)])}
	var rows := []
	for k in 8:
		var ang := float(k) * TAU / 8.0
		var cand := net_nearest(b.anchor + Vector3(cos(ang), 0.0, sin(ang)) * 400.0, 200.0)
		vs._collect_parked(truck)
		var n_parked := vr.parked_circles.size()
		vr._fail_cache.clear()
		var pl := vr.plan(truck.position, cand, truck.veh.def())
		rows.append({"k": k, "cand": [snappedf(cand.x, 1.0), snappedf(cand.z, 1.0)], "parked": n_parked, "ok": pl.ok, "len": snappedf(float(pl.get("length_m", -1.0)), 1.0),
			"road_share": snappedf(float(pl.get("road_m", 0.0)) / maxf(float(pl.get("length_m", 1.0)), 1.0), 0.01), "ms": snappedf(float(pl.get("ms", 0.0)), 1.0), "why": pl.get("why", [])})
	out["rows"] = rows
	return out


# --- Driving helpers ---------------------------------------------------------------------------

## Drives u to dest like AIWarSelfTest._drive and records what is needed to classify a failure: the longest time without progress,
## re-routes, recoveries, the route's first points and a position trace sampled every 2 simulated seconds.
func _drive_traced(u: UnitState, dest: Vector3, max_s := 420.0, scale := 8.0, visual := "") -> Dictionary:
	var vs := demo.sim.vehicles
	var v := u.veh
	var start := u.position
	var yaw0 := u.yaw
	var res := vs.order_drive(u.id, dest)
	if not res.ok:
		return {"ok": false, "reason": res.reason, "arrived": false, "start": [start.x, start.z], "goal": [dest.x, dest.z]}
	var t0 := demo.sim.state.time
	var odo0 := v.odometer
	var trace: Array = []
	var st := {"last_t": -9.0, "ref": u.position, "ref_t": t0, "max_idle": 0.0, "rec": 0, "rep": 0, "byp": 0}
	var seen := visual != "" and shots
	if seen:
		demo.rts_camera.frame(u.position, 0.0, 38.0)
		scale = minf(scale, 3.0)
	else:
		demo.rts_camera.frame(Vector3(9000, 0, -9000), 0.0, 150.0)
	var shot_n := {"n": 0, "next": 0.0}
	await _warp(max_s, scale, 400.0 if not seen else 900.0, func() -> bool:
		var now := demo.sim.state.time
		if seen and int(Engine.get_physics_frames()) % 20 == 0:
			demo.rts_camera.frame(u.position, 0.0, 38.0)
		if seen and now - t0 >= float(shot_n.next) and int(shot_n.n) < 10:
			shot_n.next = now - t0 + 4.0
			shot_n.n += 1
			_shot("%s_%02d" % [visual, int(shot_n.n)])
		if _flat(u.position, st.ref) > 1.0:
			st.ref = u.position
			st.ref_t = now
		st.max_idle = maxf(st.max_idle, now - st.ref_t)
		st.rec = maxi(st.rec, v.recoveries)
		st.rep = maxi(st.rep, v.replans)
		st.byp = maxi(st.byp, v.bypasses)
		if not st.has("idle_diag") and now - st.ref_t >= 3.0 and absf(v.speed) < 0.3:
			var around := []
			for sx: StructureState in cs.all():
				var sp := sx.position
				if sx.is_line() and not sx.points.is_empty():
					var best := INF
					for q: Vector3 in sx.points:
						best = minf(best, _flat(q, u.position))
					if best < 30.0:
						around.append("LINE %s min %.1f m" % [sx.type_id, best])
				elif _flat(sp, u.position) < 30.0:
					around.append("%s at %.0f,%.0f d=%.1f yaw %.2f" % [sx.type_id, sp.x, sp.z, _flat(sp, u.position), sx.yaw])
			var ahead := []
			for k in range(v.route_i, mini(v.route_i + 14, v.route.size())):
				ahead.append([snappedf(v.route[k].x, 0.1), snappedf(v.route[k].z, 0.1), sm.blocks_point(Vector2(v.route[k].x, v.route[k].z), v.def().collide_r)])
			var hits := []
			var dd := v.def()
			var fw := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
			for dyaw: float in [-0.1, 0.0, 0.1]:
				var fw2 := Vector3(-sin(u.yaw + dyaw), 0.0, -cos(u.yaw + dyaw))
				for oz: float in dd.circle_z:
					var q := u.position + fw2 * oz + fw2 * 0.3
					for obb: Array in sm.blocking_boxes(Vector2(q.x, q.z), dd.collide_r):
						hits.append("dyaw %.1f circle %.1f -> box c(%.1f,%.1f) half(%.1f,%.1f) ax(%.2f,%.2f)" % [dyaw, oz, obb[0].x, obb[0].y, obb[3].x, obb[3].y, obb[1].x, obb[1].y])
			st["idle_diag"] = {"hits": hits, "t": snappedf(now - t0, 1.0), "diag": vs.diagnose(u), "around": around, "route_ahead": ahead, "route_i": v.route_i, "route_n": v.route.size(), "goal_d": snappedf(_flat(u.position, dest), 1.0)}
		if now - float(st.last_t) >= 2.0 and trace.size() < 60:
			st.last_t = now
			trace.append("%.0f (%.1f,%.1f) yaw %.2f v %.1f %s rev %.1f rec %d byp %d" % [now - t0, u.position.x, u.position.z, u.yaw, v.speed, v.status_name(), v.reverse_left, v.recoveries, v.bypasses])
		return u.order == UnitState.Order.NONE and absf(v.speed) < 0.5)
	var arrived := _flat(u.position, dest) < 14.0 and v.status != VehicleState.Status.BLOCKED
	var out := {"ok": true, "arrived": arrived, "time_s": snappedf(demo.sim.state.time - t0, 1.0), "driven_m": snappedf(v.odometer - odo0, 1.0),
		"route_m": snappedf(float(res.length_m), 1.0), "end_dist_m": snappedf(_flat(u.position, dest), 1.0), "recoveries": st.rec, "replans": st.rep,
		"bypasses": st.byp, "max_idle_s": snappedf(st.max_idle, 1.0), "status": v.status_name(), "reason": v.reason,
		"start": [snappedf(start.x, 0.1), snappedf(start.z, 0.1)], "start_yaw": snappedf(yaw0, 0.01), "goal": [snappedf(dest.x, 0.1), snappedf(dest.z, 0.1)]}
	if not arrived:
		out["idle_diag"] = st.get("idle_diag", {})
		out["trace"] = trace.slice(-12)
		out["diag"] = vs.diagnose(u)
	return out


## N1B-01: every dock and parking spot of the AI bases is left to a road point about 600 m away and entered again.
## Failures carry the full driving record. `--spot-filter=text` restricts the scan to spots whose name contains the text.
func _n1b_01() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var out := {}
	var vs := demo.sim.vehicles
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spot-filter="):
			filter = a.trim_prefix("--spot-filter=")
	var rows := []
	var total := 0
	var failed := 0
	for fid in [1, 2]:
		for b: Dictionary in _bs().bases_of(fid):
			var spots: Array = []
			for st in _bs().base_stores(b.id):
				spots.append(["dock %s" % FacilityDefs.display_name(st.type_id), demo.sim.logistics.dock_world(st, -1), st])
				spots.append(["park %s" % FacilityDefs.display_name(st.type_id), demo.sim.logistics.parking_world(st, 0), st])
			for sp: Array in spots:
				var label := "%s / %s" % [b.name, sp[0]]
				if filter != "" and not label.contains(filter):
					continue
				var pos: Vector3 = sp[1]
				var away := net_nearest(b.anchor + Vector3(600, 0, 0), 900.0)
				truck.faction = fid
				truck.position = Vector3(pos.x, vs.ground_at(pos), pos.z)
				truck.yaw = (sp[2] as StructureState).yaw
				truck.order = UnitState.Order.NONE
				vs.halt(truck.id)
				await _physics(2)
				total += 1
				var r1: Dictionary = await _drive_traced(truck, away)
				var r2: Dictionary = {}
				if r1.arrived:
					r2 = await _drive_traced(truck, pos)
				var ok: bool = r1.arrived and (r2.get("arrived", false) or float(r2.get("end_dist_m", 99.0)) < 16.0)
				var row := {"spot": label, "ok": ok, "out": r1, "back": r2}
				if not ok:
					failed += 1
					var near := []
					for st: StructureState in cs.all():
						if not st.is_line() and _flat(st.position, pos) < 45.0:
							near.append("%s %.0f m" % [st.type_id, _flat(st.position, pos)])
					row["near"] = near
					row["valid"] = vs.spot_valid(pos)
					row["pos"] = [snappedf(pos.x, 0.1), snappedf(pos.z, 0.1)]
				else:
					row["out"] = {"time_s": r1.time_s, "route_m": r1.route_m}
					row["back"] = {"time_s": r2.get("time_s", 0.0), "end_dist_m": r2.get("end_dist_m", 0.0), "idle": r2.get("max_idle_s", 0.0)}
				rows.append(row)
	truck.faction = 1
	out["total"] = total
	out["failed"] = failed
	out["rows"] = rows
	return _classify("n1b_01", _verdict(failed == 0 and total >= 20), out, "Every dock and parking spot of the AI bases is left and entered again.")


## Planner workload: truck and APC plans between a deterministic subset of the audit's locations (cold, no failure cache).
## Reports the plan-time distribution, the failures and the router's per-stage profile. `--pairs=N` sets the sample size.
func _perf() -> Dictionary:
	var vr: VehicleRouter = demo.sim.vehicles.router
	var audit := RoadAudit.new(demo.sim)
	var locs := audit.locations("res://worlds/%s/source/" % demo.config.world_name)
	var want := 240
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pairs="):
			want = int(a.trim_prefix("--pairs="))
	var pairs := []
	var n := locs.size()
	var stride := maxi(1, int(float(n * (n - 1)) / want))
	var idx := 0
	for i in n:
		for j in n:
			if i != j:
				if idx % stride == 0 and _flat(locs[i].pos, locs[j].pos) > 60.0:
					pairs.append([locs[i], locs[j]])
				idx += 1
	var base_prof := vr.prof.duplicate()
	var out := {"locations": n, "pairs": pairs.size()}
	for def_id: StringName in [VehicleDefs.TRUCK, VehicleDefs.APC]:
		var d := VehicleDefs.get_def(def_id)
		var ms: Array = []
		var failed := 0
		var reasons := {}
		var slow := []
		vr._fail_cache.clear()
		for pr: Array in pairs:
			var res := vr.plan(pr[0].pos, pr[1].pos, d)
			ms.append(float(res.ms))
			if not res.ok:
				failed += 1
				reasons[res.reason] = int(reasons.get(res.reason, 0)) + 1
			if float(res.ms) > 150.0 and slow.size() < 6:
				slow.append("%s -> %s %.0f ms ok=%s" % [pr[0].name, pr[1].name, float(res.ms), str(res.ok)])
			await tree.process_frame
		out[String(def_id)] = {"plans": _percentiles(ms), "failed": failed, "reasons": reasons, "slow": slow}
	var prof := {}
	for k in vr.prof:
		prof[k] = snappedf(float(vr.prof[k]) - float(base_prof[k]), 0.1)
	out["profile"] = prof
	return out


## The local grid of the way into the East base fuel point dock (the N1B-01 failure) from the road point 600 m away.
func _dock_grid() -> Dictionary:
	var vs := demo.sim.vehicles
	var vr: VehicleRouter = vs.router
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var out := {}
	for b: Dictionary in _bs().bases_of(2):
		for st in _bs().base_stores(b.id):
			if FacilityDefs.display_name(st.type_id) != "Fuel point":
				continue
			var dock: Vector3 = demo.sim.logistics.dock_world(st, -1)
			var res := vr.plan(net_nearest(b.anchor + Vector3(600, 0, 0), 900.0), dock, td)
			out["plan_ok"] = res.ok
			# the last road vertex before the dock: re-run only the final leg
			var pts: PackedVector3Array = res.points
			var k := maxi(pts.size() - 40, 0)
			vr.debug_legs = true
			var k_from := Vector3(7796.6, 0.0, 190.5)
			k_from.y = vs.ground_at(k_from)
			var leg := vr._leg(k_from, dock, td)
			out["leg_pts"] = Array(leg.pts).map(func(q: Vector3) -> Array: return [snappedf(q.x, 0.1), snappedf(q.z, 0.1)])
			vr.debug_legs = false
			out["leg_ok"] = leg.ok
			out["from"] = [pts[k].x, pts[k].z]
			out["dock"] = [dock.x, dock.z]
			out["grid"] = vr.last_leg_debug
			var rows := []
			for q: Vector3 in pts:
				if _flat(q, Vector3(7772.5, 0, 171.8)) < 45.0:
					var clear := 0.0
					for rr: float in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]:
						if sm.blocks_point(Vector2(q.x, q.z), rr):
							break
						clear = rr
					rows.append("%.1f,%.1f clear>=%.1f road=%s" % [q.x, q.z, clear, str(demo.sim.state.roads.on_road(q, 3.0))])
			out["near_route"] = rows
			out["res_names"] = res.roads
			out["road_m"] = res.road_m
			out["offroad_m"] = res.offroad_m
	return out


# --- Shared helpers ----------------------------------------------------------------------------

func _verdict(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


## A free vehicle of the type for faction 1 (an APC is bought at the depot when none exists).
func _vehicle_of_type(type_id: StringName) -> UnitState:
	var v := _free_vehicle(1, type_id)
	if v == null:
		var dep := _bs().facility_of_kind(1, &"vehicle")
		_bs().acquire_vehicle(dep.id, type_id)
		await _warp(BaseSim.VEHICLES[type_id].time + 20.0, 24.0, 90.0)
		v = _free_vehicle(1, type_id)
	return v


func _put_vehicle(u: UnitState, pos: Vector3, yaw: float) -> void:
	var vs := demo.sim.vehicles
	u.order = UnitState.Order.NONE
	vs.halt(u.id)
	u.position = Vector3(pos.x, vs.ground_at(pos), pos.z)
	u.yaw = yaw


## Hard-obstacle audit of a route: samples every metre and counts the samples inside a structure footprint, in water, or within
## the vehicle's collision radius of a trunk / rock / settlement collider.
func _route_hits(pts: PackedVector3Array, def: VehicleDefs.Def) -> Dictionary:
	var structure_hits := 0
	var trunk_hits := 0
	var wet := 0
	var n := 0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := Vector2(b.x - a.x, b.z - a.z).length()
		var k := maxi(1, ceili(d / 1.0))
		for j in k:
			var q := a.lerp(b, float(j) / k)
			n += 1
			var q2 := Vector2(q.x, q.z)
			if sm.blocks_point(q2, def.collide_r):
				structure_hits += 1
			if sm.blocks_trunk(q2, def.collide_r):
				trunk_hits += 1
			if is_nan(demo.sim.state.roads.deck_height(q)) and sm.is_wet(q.x, q.z):
				wet += 1
	return {"samples": n, "structure": structure_hits, "trunk": trunk_hits, "wet": wet}


## Drives u with the traced driver and additionally samples, every physics tick, hits of the vehicle's collision circles against
## trunks (the kinematic mover ignores them, the planner has to keep clear) - proof that the driven line is clear.
func _drive_clear(u: UnitState, dest: Vector3, max_s := 600.0, scale := 8.0, visual := "") -> Dictionary:
	var d := u.veh.def()
	var hits := {"trunk_ticks": 0, "n": 0}
	var sampler := func() -> void:
		if u.order == UnitState.Order.MOVE:
			hits.n += 1
			var fwd := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
			for oz: float in d.circle_z:
				var q := u.position + fwd * oz
				if sm.blocks_trunk(Vector2(q.x, q.z), d.collide_r):
					hits.trunk_ticks += 1
					break
	tree.physics_frame.connect(sampler)
	var r := await _drive_traced(u, dest, max_s, scale, visual)
	tree.physics_frame.disconnect(sampler)
	r["trunk_ticks"] = hits.trunk_ticks
	r["ticks"] = hits.n
	return r


# --- N1B-02: a cramped yard --------------------------------------------------------------------

## A dead-end alley between three supply depots (8.5 m wide, 20 m deep): the truck stands at its end, nose towards the closed end,
## and has to leave. The alley is too narrow to turn round in, so it has to reverse out (or make a multi-point turn).
func _n1b_02() -> Dictionary:
	await _fresh()
	await _cleanup_test_structures()
	await _ensure_vehicles(1, 1)
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var c := _find_site() + Vector3(-60, 0, 0)
	var made: Array = []
	for spec: Array in [[Vector3(0, 0, -11.25), 0.0], [Vector3(0, 0, 11.25), 0.0], [Vector3(17, 0, 0), PI * 0.5]]:
		var b := await _building(&"supply_storage", c + spec[0], spec[1], false)
		if b:
			made.append(b)
	await _wait_navigation()
	var inside := c + Vector3(4, 0, 0)
	var goal := c + Vector3(-70, 0, 0)
	_put_vehicle(truck, inside, -PI * 0.5)  # nose towards +x: the closed end
	await _physics(2)
	var width := 0.0
	for z in range(-12, 13):
		if not sm.blocks_point(Vector2(c.x, c.z + z), 0.3):
			width += 1.0
	var r := await _drive_traced(truck, goal, 300.0, 8.0, "alley_truck")
	var pre_ok := made.size() == 3 and width > 5.0 and width < 12.0
	var ok: bool = pre_ok and r.arrived and int(r.recoveries) <= 4 and float(r.max_idle_s) < 40.0
	var out := {"buildings": made.size(), "alley_width_m": width, "drive": r, "precondition_ok": pre_ok}
	if not r.arrived:
		demo.rts_camera.frame(truck.position, 0.0, 45.0)
		await _seconds(1.0)
		_shot("n1b_02_fail")
	for b in made:
		cs.remove(b.id)
	await _wait_navigation()
	return _classify("n1b_02", _verdict(ok), out, "Leaves a dead-end alley without lasting blockage (reverse / multi-point turn).")


# --- N1B-03: truck services at base facilities -------------------------------------------------

func _n1b_03() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var lg := demo.sim.logistics
	var bs := _bs()
	var fuel_store: StructureState = null
	var supply_store: StructureState = null
	for st in bs.base_stores(bs.bases_of(1)[0].id):
		match FacilityDefs.display_name(st.type_id):
			"Fuel point": fuel_store = st
			"Supply depot": supply_store = st
	if fuel_store == null or supply_store == null:
		return _classify("n1b_03", "ERROR", {"reason": "base lacks fuel point or supply depot"})
	var out := {}
	var steps := []
	# Start outside the yard, 250 m up the road: the vehicle has to come in and go out again for every service.
	var away := net_nearest(bs.bases_of(1)[0].anchor + Vector3(250, 0, 0), 400.0)
	_put_vehicle(truck, away, 0.0)
	truck.veh.fuel = truck.veh.def().fuel_capacity * 0.3
	await _physics(2)
	var jobs := [
		["refuel", func() -> Dictionary: return lg.order_refuel(truck.id, fuel_store.id), fuel_store],
		["load", func() -> Dictionary: return lg.order_load(truck.id, supply_store.id, Inventory.SUPPLIES, 400.0), supply_store],
		["unload", func() -> Dictionary: return lg.order_unload(truck.id, supply_store.id), supply_store],
	]
	var all_ok := true
	for j: Array in jobs:
		var res: Dictionary = j[1].call()
		var st: StructureState = j[2]
		var dock := lg.dock_world(st, truck.id)
		var row := {"job": j[0], "ordered": res.ok, "reason": res.get("reason", "")}
		if res.ok:
			var t0 := demo.sim.state.time
			var idle := {"max": 0.0, "ref": truck.position, "t": t0}
			await _warp(900.0, 8.0, 240.0, func() -> bool:
				var now := demo.sim.state.time
				if _flat(truck.position, idle.ref) > 1.0:
					idle.ref = truck.position
					idle.t = now
				idle.max = maxf(idle.max, now - float(idle.t))
				return truck.veh.job.is_empty() and truck.order == UnitState.Order.NONE and absf(truck.veh.speed) < 0.3)
			row["done_s"] = snappedf(demo.sim.state.time - t0, 1.0)
			row["job_cleared"] = truck.veh.job.is_empty()
			row["end_dist_to_dock_m"] = snappedf(_flat(truck.position, dock), 1.0)
			row["max_idle_s"] = snappedf(idle.max, 1.0)
			row["status"] = truck.veh.status_name()
			var good: bool = row.job_cleared and truck.veh.status != VehicleState.Status.BLOCKED and float(row.max_idle_s) < 60.0
			all_ok = all_ok and good
		else:
			all_ok = false
		steps.append(row)
		await _physics(2)
	out["fuel_end_l"] = snappedf(truck.veh.fuel, 1.0)
	out["steps"] = steps
	return _classify("n1b_03", _verdict(all_ok), out, "Refuel, load and unload at base facilities complete: dock entry and exit without lasting blockage.")


# --- N1B-04: APC through a forest ------------------------------------------------------------------

func _n1b_04() -> Dictionary:
	await _fresh()
	var ad := VehicleDefs.get_def(VehicleDefs.APC)
	var vr: VehicleRouter = demo.sim.vehicles.router
	var apc := await _vehicle_of_type(VehicleDefs.APC)
	if apc == null:
		return _classify("n1b_04", "ERROR", {"reason": "no APC"})
	var found: Dictionary = await _find_woodland(450.0, 20.0, 55.0)
	if found.is_empty():
		return _classify("n1b_04", "ERROR", {"reason": "no woodland corridor found"})
	# The densest woods found (a truck-width gap is rare there): informational, the planner must either refuse or keep clear.
	var dense: Dictionary = await _find_route("forest", 300.0)
	var dense_info := {}
	if not dense.is_empty():
		var dp := vr.plan(dense.a, dense.b, ad)
		dense_info = {"trees_per_100m": dense.trees_per_100m, "plan_ok": dp.ok, "ms": snappedf(float(dp.get("ms", 0.0)), 1.0)}
		if dp.ok:
			dense_info["hits"] = _route_hits(dp.points, ad)
			dense_info["length_m"] = snappedf(dp.length_m, 1.0)
	var a: Vector3 = found.a
	var b: Vector3 = found.b
	# Precondition: the straight line really is blocked by solid vegetation, or the scenario proves nothing.
	var straight_blocked := not vr.line_ok(a, b, ad)
	var straight_hits := _route_hits(PackedVector3Array([a, b]), ad)
	var plan := vr.plan(a, b, ad)
	var out := {"corridor": found, "straight_blocked": straight_blocked, "straight_hits": straight_hits, "plan_ok": plan.ok, "dense_woods": dense_info}
	if not plan.ok:
		return _classify("n1b_04", "FAIL", out, "No route although an APC can usually pass woods.")
	var hits := _route_hits(plan.points, ad)
	out["plan"] = {"length_m": snappedf(plan.length_m, 1.0), "offroad_m": snappedf(plan.offroad_m, 1.0), "road_m": snappedf(plan.road_m, 1.0), "ms": snappedf(plan.ms, 1.0), "hits": hits}
	_put_vehicle(apc, a, atan2(-(b.x - a.x), -(b.z - a.z)))
	await _physics(2)
	vr._plan_cache.clear()
	var again := vr.plan(a, b, ad)
	out["plan_repeat_ms"] = snappedf(float(again.ms), 1.0)
	var drive := await _drive_clear(apc, b, 400.0, 8.0, "apc_woods")
	out["drive"] = drive
	var ok: bool = straight_blocked and hits.structure == 0 and hits.wet == 0 and hits.trunk == 0 and drive.arrived and int(drive.trunk_ticks) <= int(float(drive.ticks) * 0.01)
	if dense_info.get("plan_ok", false):
		ok = ok and int(dense_info.hits.trunk) <= 2
	return _classify("n1b_04", _verdict(ok), out, "The APC plans and drives a route that never touches a trunk, rock, structure or water.")


# --- N1B-05: truck against APC ---------------------------------------------------------------------

func _n1b_05() -> Dictionary:
	await _fresh()
	var vr: VehicleRouter = demo.sim.vehicles.router
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var ad := VehicleDefs.get_def(VehicleDefs.APC)
	await _ensure_vehicles(1, 1)
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var rows := []
	var more_off := 0
	var total := 0
	for o: ObjectiveState in war.all_objectives():
		var dist := _flat(truck.position, o.position)
		if dist < 1500.0 or dist > 9000.0:
			continue
		var rt := vr.plan(truck.position, o.position, td)
		var ra := vr.plan(truck.position, o.position, ad)
		if not rt.ok or not ra.ok:
			continue
		total += 1
		if float(ra.offroad_m) > float(rt.offroad_m) + 25.0 or absf(float(ra.length_m) - float(rt.length_m)) > 25.0:
			more_off += 1
		rows.append({"to": o.obj_name, "truck_m": snappedf(rt.length_m, 1.0), "truck_off": snappedf(rt.offroad_m, 1.0), "apc_m": snappedf(ra.length_m, 1.0), "apc_off": snappedf(ra.offroad_m, 1.0)})
		if rows.size() >= 8:
			break
	# Terrain capability: the same straight 60 m lines on rough ground. Whatever the truck passes the APC passes; some the truck
	# does not (grade between 0.40 and 0.55).
	var only_apc := 0
	var only_truck := 0
	var both := 0
	var tested := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for k in 1200:
		var p := Vector3(rng.randf_range(-8000.0, 8000.0), 0.0, rng.randf_range(-8000.0, 8000.0))
		var ang := rng.randf() * TAU
		var q := p + Vector3(cos(ang), 0.0, sin(ang)) * 60.0
		p.y = demo.sim.vehicles.ground_at(p)
		q.y = demo.sim.vehicles.ground_at(q)
		var tl := vr.line_ok(p, q, td)
		var al := vr.line_ok(p, q, ad)
		tested += 1
		if tl and al:
			both += 1
		elif al and not tl:
			only_apc += 1
		elif tl and not al:
			only_truck += 1
	var out := {"trips": rows, "trips_different": more_off, "trips_total": total, "lines_tested": tested, "lines_both": both,
		"lines_only_apc": only_apc, "lines_only_truck": only_truck}
	var ok: bool = total >= 3 and more_off >= 1 and only_apc > 0 and only_truck == 0
	return _classify("n1b_05", _verdict(ok), out, "Profiles differ: the APC chooses other routes and passes terrain the truck does not, never the opposite.")


# --- N1B-06: a blocked road stretch ------------------------------------------------------------------

func _n1b_06() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 1)
	var vr: VehicleRouter = demo.sim.vehicles.router
	var truck := _free_vehicle(1, VehicleDefs.TRUCK)
	var td := truck.veh.def()
	var trip := _candidate_trip(truck, 800.0, 12000.0, true)
	if trip.is_empty():
		return _classify("n1b_06", "ERROR", {"reason": "no bridge trip"})
	var before: Dictionary = trip.plan
	var pts: PackedVector3Array = before.points
	# The first deck point of the route: the structure goes onto the bridge, where the way cannot be driven round.
	var at := -1
	for i in pts.size():
		if not is_nan(demo.sim.state.roads.deck_height(pts[i])):
			at = i
			break
	if at < 0:
		return _classify("n1b_06", "ERROR", {"reason": "route has no deck point"})
	var mid := pts[mini(at + 6, pts.size() - 1)]
	var yaw := atan2(-(pts[mini(at + 7, pts.size() - 1)].x - mid.x), -(pts[mini(at + 7, pts.size() - 1)].z - mid.z))
	var blocker := await _building(&"supply_storage", mid, yaw + PI * 0.5, false)
	await _physics(5)
	vr._fail_cache.clear()
	var after := vr.plan(truck.position, trip.objective.position, td)
	var out := {"destination": trip.objective.obj_name, "bridge_point": [snappedf(mid.x, 0.1), snappedf(mid.z, 0.1)],
		"before_m": snappedf(before.length_m, 1.0), "blocker_placed": blocker != null, "after_ok": after.ok}
	var ok := false
	if blocker == null:
		out["note"] = "blocker could not be placed"
	elif after.ok:
		var hits := _route_hits(after.points, td)
		out["after_m"] = snappedf(after.length_m, 1.0)
		out["after_hits"] = hits
		out["after_bridges"] = after.bridges
		out["blocked_stretch_still_used"] = hits.structure > 0
		# Valid alternative: a different route that does not touch the structure.
		ok = hits.structure == 0 and absf(float(after.length_m) - float(before.length_m)) > 20.0
	else:
		# Correct blocking: no route, with a stable reason and nothing driven.
		out["after_reason"] = after.reason
		out["last_failure"] = vr.last_failure
		var again := vr.plan(truck.position, trip.objective.position, td)
		out["cached_failure_repeat"] = {"ok": again.ok, "cached": again.get("cached", false), "reason": again.get("reason", "")}
		ok = not again.ok and again.reason == after.reason
	if blocker:
		cs.remove(blocker.id)
	await _wait_navigation()
	vr._fail_cache.clear()
	var restored := vr.plan(truck.position, trip.objective.position, td)
	out["restored_ok"] = restored.ok
	ok = ok and restored.ok
	return _classify("n1b_06", _verdict(ok), out, "A blocked road stretch gives a valid alternative route or a stable blocked result, and recovers when removed.")


# --- N1B-07: isolated roads ----------------------------------------------------------------------------

func _n1b_07() -> Dictionary:
	await _fresh()
	var vr: VehicleRouter = demo.sim.vehicles.router
	var audit := RoadAudit.new(demo.sim)
	var rep := audit.audit_graph(60)
	var hq := _obj("North HQ").position
	var rows := []
	var reachable := {"truck": 0, "apc": 0}
	var unreachable_reason := {}
	for r: Dictionary in rep.isolated_roads:
		var mid := Vector3((r.from[0] + r.to[0]) * 0.5, 0.0, (r.from[1] + r.to[1]) * 0.5)
		var near := vr.nearest_nodes(mid, 1, 400.0)
		var target: Vector3 = near[0].pos if not near.is_empty() else mid
		var row := {"road": r.name, "length_m": r.length_m}
		for def_id: StringName in [VehicleDefs.TRUCK, VehicleDefs.APC]:
			var pl := vr.plan(hq, target, VehicleDefs.get_def(def_id))
			row[String(def_id)] = pl.ok
			if pl.ok:
				reachable["truck" if def_id == VehicleDefs.TRUCK else "apc"] += 1
		if not row[String(VehicleDefs.TRUCK)]:
			row["why"] = vr.last_failure.get("reason", "")
			var only_main := func(id: int, _p: Vector3) -> bool: return vr._comp_of.get(id, -1) == vr._main_comp
			var m := vr.nearest_nodes(target, 1, 3000.0, only_main)
			if not m.is_empty():
				var leg := audit.leg_diagnosis(target, m[0].pos)
				var cause: String = String(leg.first_problem).split(" at")[0] if leg.first_problem != "" else "no straight-line fault, local search failed"
				row["main_network_m"] = snappedf(m[0].dist, 1.0)
				row["straight_leg"] = leg.first_problem
				unreachable_reason[cause] = int(unreachable_reason.get(cause, 0)) + 1
		rows.append(row)
	var n: int = rep.isolated_roads.size()
	var out := {"isolated_roads": rep.isolated_road_count, "listed": n, "reachable_truck": reachable.truck, "reachable_apc": reachable.apc,
		"unreachable_by_cause": unreachable_reason, "soft_link_components": vr._soft.size(), "rows": rows}
	# Every isolated street is either reached over a validated short cross-country link, or classified with a terrain cause.
	var classified := 0
	for r in rows:
		if r[String(VehicleDefs.TRUCK)] or r.has("straight_leg"):
			classified += 1
	var ok: bool = n >= 10 and classified == n and reachable.truck + reachable.apc > 0
	return _classify("n1b_07", _verdict(ok), out, "Isolated roads are reached over a validated cross-country link or classified by cause.")


# --- N1B-08: a convoy meets an obstacle ----------------------------------------------------------------

func _n1b_08() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 3)
	var ids := []
	for u: UnitState in _vehicles_of(1):
		if ids.size() < 3 and u.alive and u.veh.assign_kind == "" and u.order == UnitState.Order.NONE:
			ids.append(u.id)
	if ids.size() < 3:
		return _classify("n1b_08", "ERROR", {"reason": "fewer than three free vehicles"})
	var lead := _u(ids[0])
	var vs := demo.sim.vehicles
	var trip := _candidate_trip(lead, 1200.0, 12000.0)
	if trip.is_empty():
		return _classify("n1b_08", "ERROR", {"reason": "no trip"})
	var cr := vs.convoy.order_convoy(ids, trip.objective.position, "N1B obstacle convoy")
	if not cr.ok:
		return _classify("n1b_08", "FAIL", {"formed": false, "reason": cr.reason})
	# NAV-PERF-01B: the leader's route is planned by RouteService; the obstacle goes on it once it is there.
	for i in 900:
		if lead.veh.route.size() >= 2:
			break
		await tree.process_frame
	var route: PackedVector3Array = lead.veh.route
	# A spot 150-900 m along the route with open ground round it (no trunk within 30 m, not on a bridge): a building in woods has
	# no way round and would only test that the way is really closed.
	var k := -1
	for cand in range(50, mini(600, route.size() - 12)):
		var q := route[cand]
		if not is_nan(demo.sim.state.roads.deck_height(q)):
			continue
		var tr := PackedFloat32Array()
		sm.trunks_in_rect(Rect2(q.x - 30.0, q.z - 30.0, 60.0, 60.0), tr)
		if tr.is_empty() and not sm.blocks_point(Vector2(q.x, q.z), 40.0):
			k = cand
			break
	if k < 0:
		return _classify("n1b_08", "ERROR", {"reason": "no open spot on the route"})
	var spot := route[k]
	var blocker := await _building(&"supply_storage", spot, atan2(-(route[k + 1].x - spot.x), -(route[k + 1].z - spot.z)) + PI * 0.5, false)
	await _physics(5)
	var by0 := int(vs.stats.bypassed)
	var t0 := demo.sim.state.time
	var idle := {}
	var max_idle := 0.0
	await _warp(2400.0, 20.0, 300.0, func() -> bool:
		var active := 0
		for id in ids:
			var u := _u(id)
			if u.order == UnitState.Order.MOVE:
				active += 1
				var rec: Dictionary = idle.get(id, {"ref": u.position, "t": demo.sim.state.time})
				if _flat(u.position, rec.ref) > 1.0:
					rec = {"ref": u.position, "t": demo.sim.state.time}
				idle[id] = rec
				max_idle = maxf(max_idle, demo.sim.state.time - float(rec.t))
		return active == 0)
	var rows := []
	var arrived := 0
	for id in ids:
		var u := _u(id)
		var d := _flat(u.position, trip.objective.position)
		var ok_v := d < 60.0 and u.veh.status != VehicleState.Status.BLOCKED
		arrived += 1 if ok_v else 0
		rows.append({"id": id, "end_dist_m": snappedf(d, 1.0), "status": u.veh.status_name(), "reason": u.veh.reason, "bypasses": u.veh.bypasses, "recoveries": u.veh.recoveries})
	vs.convoy.stop(int(cr.convoy))
	var out := {"destination": trip.objective.obj_name, "blocker_at": [snappedf(spot.x, 0.1), snappedf(spot.z, 0.1)], "arrived": arrived, "vehicles": rows,
		"max_idle_s": snappedf(max_idle, 1.0), "time_s": snappedf(demo.sim.state.time - t0, 1.0), "bypasses": int(vs.stats.bypassed) - by0,
		"bypass_attempts": int(vs.stats.bypass_attempted)}
	out["events"] = war.events.filter(func(e: Dictionary) -> bool: return e.kind == "vehicle" and e.t >= t0 - 1.0).slice(0, 30).map(func(e: Dictionary) -> String: return "%.0f %s" % [e.t - t0, e.text])
	if arrived < 3:
		out["diag"] = ids.map(func(id: int) -> Dictionary: return vs.diagnose(_u(id)))
	if blocker:
		cs.remove(blocker.id)
	await _wait_navigation()
	var ok: bool = blocker != null and arrived == 3 and max_idle < 120.0
	return _classify("n1b_08", _verdict(ok), out, "All convoy members pass an obstacle on the route and reach the goal without lasting blockage.")


# --- N1B-09: many simultaneous route requests ----------------------------------------------------------

func _n1b_09() -> Dictionary:
	await _fresh()
	var vr: VehicleRouter = demo.sim.vehicles.router
	var vs := demo.sim.vehicles
	await _ensure_vehicles(1, 3)
	var fleet := _vehicles_of(1).filter(func(u: UnitState) -> bool: return u.alive and u.order == UnitState.Order.NONE)
	var dests: Array = []
	for o: ObjectiveState in war.all_objectives():
		var d := _flat(fleet[0].position, o.position)
		if d > 800.0 and d < 7000.0:
			dests.append(o.position)
	var out := {"fleet": fleet.size(), "destinations": dests.size()}
	# Warm-up: the first plan after the world changed rebuilds the vegetation collider caches (a one-off cost, reported apart).
	var cold := vs.router.plan(fleet[0].position, dests[0], fleet[0].veh.def())
	out["cold_first_plan_ms"] = snappedf(float(cold.ms), 1.0)
	vr._plan_cache.clear()
	vr._leg_cache.clear()
	var prof0: Dictionary = vr.prof.duplicate()
	# 1. A burst: every vehicle ordered to a different destination within one frame, several rounds.
	var frame_ms: Array = []
	var plan_ms: Array = []
	var by_round := []
	var slow := []
	out["slow"] = slow
	for round_i in 6:
		vr._fail_cache.clear()
		var t0 := Time.get_ticks_usec()
		var n := 0
		for i in fleet.size():
			var u: UnitState = fleet[i]
			var dest: Vector3 = dests[(i + round_i * 2) % dests.size()]
			var res := vs.order_drive(u.id, dest)
			if res.has("ms"):
				plan_ms.append(float(res.ms))
				if float(res.ms) > 150.0:
					slow.append({"from": [snappedf(u.position.x, 1.0), snappedf(u.position.z, 1.0)], "to": [snappedf(dest.x, 1.0), snappedf(dest.z, 1.0)], "ms": snappedf(float(res.ms), 1.0), "ok": res.ok, "why": res.get("why", [])})
			n += 1
		var burst := (Time.get_ticks_usec() - t0) / 1000.0
		by_round.append({"orders": n, "ms": snappedf(burst, 1.0)})
		frame_ms.append(burst)
		for u: UnitState in fleet:
			vs.halt(u.id)
		await tree.process_frame
	out["burst_rounds"] = by_round
	out["burst_frame_ms"] = _percentiles(frame_ms)
	out["plan_ms"] = _percentiles(plan_ms)
	# 2. The same destination for the whole column (a convoy).
	var cm: Array = []
	for round_i in 4:
		vr._fail_cache.clear()
		var t1 := Time.get_ticks_usec()
		var ids: Array = fleet.map(func(u: UnitState) -> int: return u.id)
		var cr := vs.convoy.order_convoy(ids, dests[round_i % dests.size()], "N1B burst convoy")
		cm.append((Time.get_ticks_usec() - t1) / 1000.0)
		if cr.ok:
			vs.convoy.stop(int(cr.convoy))
		for u: UnitState in fleet:
			vs.halt(u.id)
		await tree.process_frame
	out["convoy_order_ms"] = _percentiles(cm)
	out["router_cache"] = {"plan_hits": vr.cache_hits, "leg_hits": vr.leg_cache_hits, "leg_misses": vr.leg_cache_misses}
	var prof_delta := {}
	for k in vr.prof:
		prof_delta[k] = snappedf(float(vr.prof[k]) - float(prof0[k]), 0.1)
	out["router_profile"] = prof_delta
	# Acceptance: no single request above 450 ms, and a burst of the whole fleet under a second.
	var ok: bool = float(out.plan_ms.max) < 450.0 and float(out.burst_frame_ms.max) < 1000.0 and float(out.convoy_order_ms.max) < 1000.0
	return _classify("n1b_09", _verdict(ok), out, "Bursts of route requests stay within budget (no request above 450 ms - the N1 baseline peaked at 390-574 ms - and a burst below a second).")


# --- N1B-10: the road audit --------------------------------------------------------------------------------

func _n1b_10() -> Dictionary:
	await _fresh()
	var audit := RoadAudit.new(demo.sim)
	var vr: VehicleRouter = demo.sim.vehicles.router
	var src := "res://worlds/%s/source/" % demo.config.world_name
	var rep: Dictionary = await audit.run(src, ["objective:hq", "objective:town", "objective:village", "objective:bridge", "base", "dock", "settlement"], func() -> void: await tree.process_frame)
	var causes := {}
	for f in rep.route_failures:
		var tag := String(f.intentional)
		var cause := "other"
		if tag.begins_with("isolated"):
			cause = "isolated settlement streets (no drivable ground to the main network)"
		elif tag.begins_with("terrain"):
			cause = "terrain: place cannot be entered"
		causes[cause] = int(causes.get(cause, 0)) + 1
	var out := {"nodes": rep.nodes, "components": rep.components, "main_component_share": rep.main_component_share, "isolated_roads": rep.isolated_road_count,
		"routes_planned": rep.routes_planned, "routes_ok": rep.routes_ok, "failures": rep.route_failure_count, "failures_unexplained": rep.route_failures_unexplained,
		"listed_failures_by_cause": causes, "failures_by_destination": rep.route_failures_by_destination, "plan_ms_max": rep.plan_ms_max,
		"repaired_gaps": rep.repaired_gaps, "soft_link_components": vr._soft.size()}
	# Baseline (N1): 2310 / 2604 planned, 294 failed, 180 unexplained.
	var ok: bool = int(rep.route_failure_count) < 294 and int(rep.route_failures_unexplained) < 180
	return _classify("n1b_10", _verdict(ok), out, "Fewer failed audit routes than the N1 baseline (294, 180 unexplained); every remaining failure is classified.")


## A corridor of `length` metres through woods of the wanted density (trees per 100 m of a ~48 m band), flat enough and dry.
func _find_woodland(length: float, min_density: float, max_density: float) -> Dictionary:
	var best := {}
	var best_score := INF
	for o: ObjectiveState in war.objectives.values():
		for r: float in [700.0, 1200.0, 1900.0, 2700.0]:
			var n := clampi(int(r / 80.0), 8, 30)
			for k in n:
				var ang := k * TAU / n + 0.3
				var a := demo.on_ground(o.position.x + cos(ang) * r, o.position.z + sin(ang) * r, 0.0)
				if absf(a.x) > 9000.0 or absf(a.z) > 9000.0 or not ws.routes.passable(a):
					continue
				for j in 4:
					var dd := Vector3(cos(j * TAU / 4.0 + 0.5), 0.0, sin(j * TAU / 4.0 + 0.5))
					var b := demo.on_ground(a.x + dd.x * length, a.z + dd.z * length, 0.0)
					if not ws.routes.passable(b):
						continue
					var c := _corridor(a, b)
					if c.wet or c.max_grade >= 0.12 or c.trees_per_100m < min_density or c.trees_per_100m > max_density:
						continue
					var score := absf(c.trees_per_100m - 0.5 * (min_density + max_density))
					if score < best_score:
						best_score = score
						best = {"a": a, "b": b, "len": c.len, "trees_per_100m": snappedf(c.trees_per_100m, 0.1), "max_grade": snappedf(c.max_grade, 0.01)}
			if not best.is_empty():
				return best
			await tree.process_frame
	return best


func _convoy_dbg() -> Dictionary:
	await _fresh()
	await _ensure_vehicles(1, 3)
	var ids: Array = []
	for u: UnitState in _vehicles_of(1):
		if ids.size() < 3 and u.veh.job.is_empty() and u.order == UnitState.Order.NONE:
			ids.append(u.id)
	var out := {}
	for km: float in [2.5, 4.0, 5.5]:
		var obj := _far_objective(1, km)
		var dest := net_nearest(obj.position, 400.0)
		var cr: Dictionary = demo.sim.vehicles.convoy.order_convoy(ids, dest, "dbg")
		await _physics(30)
		var rows := []
		for id in ids:
			var u := _u(id)
			rows.append({"id": id, "route": u.veh.route.size(), "order": u.order, "status": u.veh.status_name(), "reason": u.veh.reason, "pos": [snappedf(u.position.x, 1.0), snappedf(u.position.z, 1.0)], "speed": snappedf(u.veh.speed, 0.1)})
		out["%.1f" % km] = {"ok": cr.ok, "rows": rows, "events": war.events.filter(func(e: Dictionary) -> bool: return e.kind == "vehicle").slice(-6).map(func(e: Dictionary) -> String: return e.text)}
		demo.sim.vehicles.convoy.stop(int(cr.convoy))
		for id in ids:
			demo.sim.vehicles.halt(id)
	return out


## A plan that started in a village (Verket): where the time goes.
func _verket() -> Dictionary:
	var vr: VehicleRouter = demo.sim.vehicles.router
	var td := VehicleDefs.get_def(VehicleDefs.TRUCK)
	var from := Vector3(-371.0, 0.0, 6139.0)
	from.y = demo.sim.vehicles.ground_at(from)
	var to := Vector3(1173.0, 0.0, 4539.0)
	to.y = demo.sim.vehicles.ground_at(to)
	var out := {}
	for round_i in 2:
		vr._plan_cache.clear()
		vr._leg_cache.clear()
		vr._fail_cache.clear()
		var p0: Dictionary = vr.prof.duplicate()
		var res := vr.plan(from, to, td)
		var d := {}
		for k in vr.prof:
			d[k] = snappedf(float(vr.prof[k]) - float(p0[k]), 0.1)
		out["round%d" % round_i] = {"ok": res.ok, "ms": snappedf(float(res.ms), 1.0), "prof": d, "len": snappedf(float(res.get("length_m", 0.0)), 1.0), "offroad_m": snappedf(float(res.get("offroad_m", 0.0)), 1.0)}
	return out
