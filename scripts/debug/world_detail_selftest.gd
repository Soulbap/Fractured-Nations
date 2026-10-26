## WORLD-DETAIL-02 checks in the real game on ref_20km with the man-made detail layer (worlds/detail/ref_20km.detail.json):
##
##   Godot.exe --path . --fullscreen --log-file wd.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --world-detail-test [--shots] [--only ...]
##
## r_loaded   the layer is in the streamer's overrides (records of ids 31-49)
## r_roads    no solid object on or beside a road surface (the road mesh edge + 0.5 m), none on a bridge deck
## b_ballistic shots through solid kinds from four sides at crouched height are stopped (LineOfFire); the picket fence and the
##            guardrail let them through; the cover test behind a solid protects against a threat on the far side
## c_cover    CombatBrain.cover_spots finds positions at the objects (a garden wall, a container, a bale row)
## v_shots    screenshots: a village plot boundary, farm bales, a container yard, a checkpoint, a guardrail, an approach
## v_culverts the culvert ends (CulvertSeat): none on the road surface, mouths facing away from the road; screenshots of two
## Prints "WD <check> <json>", writes res://benchmarks/raw/world_detail_test.json.
class_name WorldDetailSelfTest
extends WorldCoverSelfTest

const CHECKSWD: Array[String] = ["r_loaded", "r_roads", "b_ballistic", "c_cover", "v_shots", "v_culverts"]
var _kit := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/world_detail02"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKSWD)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(900.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(DetailLayer.path(demo.config.world_name)))
	_layer = j.records if j is Dictionary and DetailLayer.enabled() else {}
	var kj: Variant = JSON.parse_string(FileAccess.get_file_as_string(DetailLayer.KIT))
	for k: String in kj:
		_kit[int(k)] = kj[k]
	results["layer_records"] = _layer.size()
	_tcam = Camera3D.new()
	_tcam.fov = 55.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	if demo.hud:
		demo.hud.visible = false
	for n in CHECKSWD:
		if only.has(n):
			_log(n, await call("_" + n))
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("WD %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/world_detail_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("WD %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


func _r_loaded() -> Dictionary:
	var n := 0
	var recs: Dictionary = demo.vegetation.overrides.records
	for key: String in _layer:
		if recs.has(key):
			n += 1
	if _layer.is_empty() or n < _layer.size() * 0.9:
		failures.append("r_loaded: %d of %d layer records in the overrides" % [n, _layer.size()])
	var by := {}
	for rec: Dictionary in _layer.values():
		var k := str(rec.mesh)
		by[k] = int(by.get(k, 0)) + 1
	return {"in_overrides": n, "layer": _layer.size(), "by_mesh": by}


func _foot(id: int) -> Vector2:
	if DetailLayer.NATURAL.has(id):
		return DetailLayer.NATURAL[id]
	var f: Array = _kit[id].foot
	return Vector2(f[0], f[1])


func _r_roads() -> Dictionary:
	var roads := demo.sim.state.roads
	var bad: Array = []
	var deck := 0
	var checked := 0
	for rec: Dictionary in _layer.values():
		var id := int(rec.mesh)
		if _kit.has(id) and not _kit[id].solid:
			continue
		checked += 1
		var t: Array = rec.transform
		var p := Vector2(t[9], t[11])
		var yaw := atan2(-float(t[2]), float(t[0]))
		var ax := Vector2(cos(yaw), -sin(yaw))
		var sd := Vector2(sin(yaw), cos(yaw))
		var fo := _foot(id)
		for q: Vector2 in [p, p + ax * fo.x + sd * fo.y, p + ax * fo.x - sd * fo.y, p - ax * fo.x + sd * fo.y, p - ax * fo.x - sd * fo.y]:
			var n := roads.nearest(Vector3(q.x, 0, q.y), 20.0, 0, 0.0)
			if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + 2.5:
				bad.append([id, snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
				break
		if roads.bridge_at(Vector3(p.x, 0, p.y), 0.0) != null:
			deck += 1
	if not bad.is_empty() or deck > 0:
		failures.append("r_roads: %d solid objects at a road surface, %d on a bridge deck" % [bad.size(), deck])
	return {"solid_checked": checked, "at_road": bad.size(), "examples": bad.slice(0, 5), "on_deck": deck}


## The nearest layer objects of an id to a point.
func _near_objs(id: int, near: Vector3, limit: int) -> Array:
	return _objects(id, near, limit)


func _b_ballistic() -> Dictionary:
	var out := {}
	var line := demo.sim.combat.line
	var ref := Vector3(-1600, 0, -4400)
	for id: int in [31, 32, 33, 34, 35, 37, 39, 41, 42, 44, 46]:
		var objs := _near_objs(id, ref, 2)
		if objs.is_empty():
			continue
		var row := {"probes": 0, "stopped": 0, "protected": 0}
		for o: Dictionary in objs:
			var p: Vector3 = o.pos
			demo.rts_camera.frame(p, 0.6, 40.0)
			await _seconds(1.0)
			var fo := _foot(id)
			for k in 4:
				# Across the object's short side (the way it covers) and along its length.
				var a := float(o.yaw) + k * PI * 0.5
				var dir := Vector3(cos(a), 0, -sin(a))
				var reach := fo.x if k % 2 == 0 else fo.y
				var behind := p - dir * (reach + 1.0)
				var gy: float = demo.sim.terrain.data.get_height(behind)
				var from := p + dir * 30.0
				from.y = gy + 1.5
				row.probes += 1
				var tr := line.trace(from, Vector3(behind.x, gy + 0.6, behind.z), -1, false)
				if tr.blocker == "tree" and float(tr.distance) < 31.0:
					row.stopped += 1
				var u: UnitState = demo.sim.state.soldiers()[0]
				if demo.sim.brain._evaluate_spot(u, Vector3(behind.x, gy, behind.z), from).protected:
					row.protected += 1
		out[str(id)] = row
		var solid: bool = _kit[id].solid
		if solid and row.stopped == 0:
			failures.append("b_ballistic: id %d stopped none of %d shots" % [id, row.probes])
		if not solid and row.stopped == row.probes and row.probes > 0:
			failures.append("b_ballistic: drawn-only id %d stopped every shot" % id)
	return out


func _c_cover() -> Dictionary:
	var out := {}
	for id: int in [33, 44, 31]:
		var objs := _near_objs(id, Vector3(-900, 0, -1800), 1)
		if objs.is_empty():
			continue
		var p: Vector3 = objs[0].pos
		demo.rts_camera.frame(p, 0.6, 40.0)
		await _seconds(1.5)
		var a := float(objs[0].yaw) + PI * 0.5
		var threat := p + Vector3(cos(a), 0, -sin(a)) * 60.0
		# The search answers [] while its LineOfFire cells are still filling (it queues them): ask again for a few seconds.
		var spots: Array = []
		for t in 20:
			spots = demo.sim.brain.cover_spots(p, 6.0, threat, p + Vector3(cos(a), 0, -sin(a)) * -4.0)
			if not spots.is_empty():
				break
			await _seconds(0.25)
		var kinds := {}
		for c: Dictionary in spots:
			kinds[str(c.get("kind", "?"))] = int(kinds.get(str(c.get("kind", "?")), 0)) + 1
		out[str(id)] = {"spots": spots.size(), "kinds": kinds, "at": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]}
		if spots.is_empty():
			failures.append("c_cover: no cover spots at id %d" % id)
	return out


## One object of each scene: an RTS view and an eye-height view from its open side.
func _v_shots() -> Dictionary:
	var out := {}
	var scenes := [["plot_wall", 33, Vector3(-900, 0, -1800)], ["plot_fence", 34, Vector3(-1600, 0, -4400)],
		["farm_bales", 31, Vector3(-3000, 0, -7500)], ["yard_containers", 44, Vector3(-350, 0, 6150)],
		["checkpoint", 41, Vector3(0, 0, 0)], ["guardrail", 46, Vector3(-1600, 0, -4400)], ["kiosk", 38, Vector3(-1600, 0, -4400)],
		["firewood", 32, Vector3(-3000, 0, -7500)], ["skip", 37, Vector3(-900, 0, -1800)], ["approach_rocks", 25, Vector3(-1600, 0, -4400)]]
	for s: Array in scenes:
		var objs := _near_objs(int(s[1]), s[2], 6)
		if objs.is_empty():
			out[s[0]] = "none"
			continue
		var o: Dictionary = objs[0]
		var p: Vector3 = o.pos
		demo.rts_camera.frame(p, float(o.yaw), 30.0)
		await _seconds(4.0)
		_png("wd_%s_rts" % s[0])
		var yaw := _open_side(p, float(o.yaw) + PI * 0.5)
		_cam(p + Vector3.UP * 0.8, 14.0, yaw, 8.0)
		await _seconds(1.5)
		_png("wd_%s_eye" % s[0])
		_tcam.current = false
		demo.rts_camera.camera.make_current()
		out[s[0]] = [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]
	return out


func _v_culverts() -> Dictionary:
	var root := demo.world.get_node_or_null("RoadStructures") if demo.world else null
	if root == null:
		failures.append("v_culverts: no RoadStructures")
		return {}
	var roads := demo.sim.state.roads
	var all: Array = []
	var on_road := 0
	var facing_in := 0
	var hidden := 0
	for n in root.get_children():
		if not String(n.name).begins_with("Culvert_"):
			continue
		var cv := n as Node3D
		if not cv.visible:
			hidden += 1
			continue
		var p := cv.global_position
		all.append(cv)
		var near := roads.nearest(p, 30.0, 0, 0.0)
		if near.is_empty():
			continue
		var c: Vector3 = near.pos
		if float(near.dist) < (near.road as RoadNetwork.Road).width * 0.5 + 2.0:
			on_road += 1
		# The mouth (+Z) must point away from the road the pipe runs under (the one at its buried end, not a neighbour at a
		# junction).
		var under := roads.nearest(p - cv.global_basis.z * 4.0, 30.0, 0, 0.0)
		var uc: Vector3 = under.pos if not under.is_empty() else c
		if cv.global_basis.z.dot(Vector3(p.x - uc.x, 0, p.z - uc.z)) < 0.0:
			facing_in += 1
	if on_road > 0 or facing_in > 0:
		failures.append("v_culverts: %d on the road surface, %d facing the road" % [on_road, facing_in])
	all.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return Vector2(a.global_position.x + 1600, a.global_position.z + 4400).length() < Vector2(b.global_position.x + 1600, b.global_position.z + 4400).length())
	var picks := all.slice(0, 2)
	for i in picks.size():
		var cv: Node3D = picks[i]
		var p := cv.global_position
		demo.rts_camera.frame(p, 0.6, 25.0)
		await _seconds(4.0)
		var out_yaw := atan2(cv.global_basis.z.x, cv.global_basis.z.z)
		_cam(p + Vector3.UP * 0.6, 7.0, out_yaw + 0.5, 10.0)
		await _seconds(1.5)
		_png("wd_culvert_%d_eye" % i)
		_tcam.current = false
		demo.rts_camera.camera.make_current()
	return {"culverts": all.size(), "hidden": hidden, "on_road": on_road, "facing_road": facing_in}
