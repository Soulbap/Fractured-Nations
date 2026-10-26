## WORLD-COVER-01.1 checks in the real game on ref_20km with the terrain microrelief (worlds/relief/ref_20km.relief.json), the
## natural cover layer and the fitted cover colliders:
##
##   Godot.exe --path . --fullscreen --log-file wc11.log res://scenes/game/world_ref_20km.tscn -- --scenario=dev --world-cover11-test [--shots] [--only ...]
##   before numbers: the same with --no-terrain-relief (terrain), --no-end-cover (end-of-move cover), --single-box-colliders (colliders)
##
## r_survey     each relief kind near the test area: eye-height and RTS shots; the chain at its deepest / highest point - terrain data,
##              terrain collision (a ray), navmesh, the relief's own delta - and the vegetation on it (no plant floating or buried)
## k_colliders  rock groups, root plates, logs, walls: shots across each object just under the old single box's top (stopped by
##              nothing visible where the object is lower), and a prone soldier beside a root plate's lying trunk
## b_hollow     a soldier in the three deepest hollows near the test area standing / crouched / prone, shot at from eight directions
##              40 m off (level) and from a rise: hits on his real hit volumes (LineOfFire with units)
## c_ridge      the same on the back of three folds, from across the fold, plus: can he fire over it (his eye to the shooter), is
##              the muzzle clear
## v_same       a squad defends at a fold against an enemy across it; one soldier the AI put in cover is shown from the RTS camera,
##              possessed (same place, same posture), checked in first person standing / crouched / prone (protected, can fire,
##              muzzle clear, on the ground, not inside a solid) with a shot of each, and shown again from the RTS camera; then the
##              same at a natural cover object
## d_combat_move a COMBAT squad moves to a place 110 m from a reported enemy: where its soldiers end (protected against the threat
##              in the posture they hold), how far from the ordered point, how long
## e_stealth_move the same in STEALTH: exposure to the threat at the end, protection, path length
## f_road       infantry crosses a road with ditches under fire (WorldCoverSelfTest c_road); APC and truck cross-country plans across it
## g_two_threats a squad defends at a fold against two enemy teams from two directions
## a_open       8 v 8 on open ground with microrelief, 45 s: exposure (posture-aware), relief used, stuck, shots
## q_perf       frame times at the relief (RTS / eye height), relief apply time, post search and tactics step cost
## Prints "WC11 <check> <json>", writes res://benchmarks/raw/world_cover11_test.json.
class_name WorldCover11SelfTest
extends WorldCoverSelfTest

const CHECKSWC11: Array[String] = ["r_global", "r_survey", "k_colliders", "b_hollow", "c_ridge", "v_same", "d_combat_move", "e_stealth_move",
	"f_road", "g_two_threats", "a_open", "q_perf"]
var _feats: Array = []


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/world_cover01_1"
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKSWC11)
	SoldierBody.require_mouse_capture = false
	tree.create_timer(2400.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(CoverLayer.path(demo.config.world_name)))
	_layer = j.records if j is Dictionary and CoverLayer.enabled() else {}
	_feats = TerrainRelief.read_features(demo.config.world_name)
	results["relief"] = TerrainRelief.stats
	results["relief_on"] = TerrainRelief.enabled(demo.config.world_name)
	results["natural_cover"] = CoverLayer.enabled()
	results["end_cover"] = demo.sim.tactics.settle_enabled
	results["single_box_colliders"] = not VegetationMeshDef.use_parts
	_cs = CombatScenario.new(demo)
	_site = _cs.find_site()
	_tcam = Camera3D.new()
	_tcam.fov = 50.0
	_tcam.far = 4000.0
	demo.add_child(_tcam)
	if demo.hud:
		demo.hud.visible = false
	_quiet_area(_site.def, 2500.0)
	for n in CHECKSWC11:
		if only.has(n):
			_log(n, await call("_" + n))
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("WC11 %s %s" % [check, JSON.stringify(data)])


func _finish() -> void:
	if _done:
		return
	_done = true
	CoreDemo.apply_time_scale(1.0)
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/world_cover11_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("WC11 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- Relief helpers -----------------------------------------------------------------------------------------------------------

## Relief features of `kind` near p, nearest first: [{f (compiled), c (Vector3 on the ground), d}] - from the file, so a run with
## --no-terrain-relief tests the same places on the old ground.
func _relief(kind: String, near: Vector3, limit := 4, min_size := 0.0) -> Array:
	var out: Array = []
	for f: Dictionary in _feats:
		if String(f.kind) != kind:
			continue
		if min_size > 0.0 and absf(float(f.get("d", f.get("h", f.get("a", 0.0))))) < min_size:
			continue
		var c := _extreme(f)
		out.append({"f": f, "c": c, "d": Vector2(c.x - near.x, c.z - near.z).length()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return out.slice(0, limit)


## The feature's deepest (hollow, ditch) or highest (fold, step, bank, swell) point, on the terrain.
func _extreme(f: Dictionary) -> Vector3:
	var p := Vector2.ZERO
	match int(f.type):
		TerrainRelief.HOLLOW:
			p = Vector2(float(f.x), float(f.z))
		TerrainRelief.RIDGE:
			p = Vector2(float(f.x), float(f.z)) + Vector2(-float(f.sn), float(f.cs)) * float(f.get("bend", 0.0))
		TerrainRelief.LINE:
			var pts: PackedVector2Array = f.p2
			p = pts[pts.size() / 2]
	return demo.on_ground(p.x, p.y, 0.0)


## A fold's crest point (middle) and the unit vector across it (its front side).
func _crest(f: Dictionary) -> Array:
	var across := Vector3(-float(f.sn), 0.0, float(f.cs))
	return [_extreme(f), across]


## Plants of the generated vegetation within r of p that stand off the ground: {n, floating (> 0.08 m above), buried (> 0.5 m below)}.
func _plants_off_ground(p: Vector3, r: float) -> Dictionary:
	var out := {"n": 0, "floating": 0, "buried": 0}
	var veg := demo.vegetation
	var fpi := VegetationChunk.FLOATS_PER_INSTANCE
	for loc in veg.chunks:
		var ch: VegetationChunk = veg.chunks[loc]
		for cell in ch.cells:
			if Vector2((cell.x + 0.5) * 128.0 - p.x, (cell.y + 0.5) * 128.0 - p.z).length() > r + 100.0:
				continue
			var by_mesh: Dictionary = ch.cells[cell]
			for mesh_id in by_mesh:
				var buf: PackedFloat32Array = by_mesh[mesh_id]
				for i in buf.size() / fpi:
					var k := i * fpi
					if Vector2(buf[k + 3] - p.x, buf[k + 11] - p.z).length() > r:
						continue
					var h: float = demo.sim.terrain.data.get_height(Vector3(buf[k + 3], 0.0, buf[k + 11]))
					out.n += 1
					if buf[k + 7] - h > 0.08:
						out.floating += 1
					elif buf[k + 7] - h < -0.5:
						out.buried += 1
	return out


## The terrain collision's height at p (a ray down; NAN without a collider there).
func _collision_y(p: Vector3, exclude: Array[RID] = []) -> float:
	var space := demo.get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p - Vector3.UP * 30.0)
	q.collision_mask = 1
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else NAN


## One soldier at p (faction 0, tough), facing `facing`, in posture `post` (settled at once).
func _target(p: Vector3, facing: Vector3, post: int) -> UnitState:
	var sq := _cs.spawn(0, p, facing, 1, "T")
	var u := demo.sim.state.get_unit(sq.members[0])
	u.position = demo.on_ground(p.x, p.z, 0.0)
	u.max_health = 9999.0
	u.health = 9999.0
	_set_posture(u, post)
	demo.sim.squads.order_hold([sq.id])
	return u


func _set_posture(u: UnitState, post: int) -> void:
	u.posture = post
	u.posture_from = post
	u.posture_at = demo.sim.state.time - 10.0
	u.posture_hold_until = demo.sim.state.time + 600.0


## Of shots from `from` (eye) at u's torso and head: how many reach him (LineOfFire with units, his posture's hit volumes).
func _hits(from: Vector3, u: UnitState) -> int:
	var line := demo.sim.combat.line
	var n := 0
	for pt: Vector3 in [u.position + Posture.AIM_TORSO[u.posture], u.position + Posture.AIM_HEAD[u.posture]]:
		var tr := line.trace(from, from + (pt - from).normalized() * (from.distance_to(pt) + 1.5), -1, true)
		if int(tr.hit_unit) == u.id:
			n += 1
	return n


## Can a soldier at u fire at `at` (a point on an enemy): his eye line reaches 1 m short of it, and the first 1.5 m from the eye
## (the muzzle) are clear.
func _can_fire(u: UnitState, at: Vector3) -> Dictionary:
	var line := demo.sim.combat.line
	var eye := Posture.eye(u)
	var tr := line.trace(eye, eye + (at - eye).normalized() * (eye.distance_to(at) - 1.0), u.id, false)
	return {"can_fire": tr.blocker == "range", "muzzle_clear": tr.blocker == "range" or float(tr.distance) > 1.5, "blocker": tr.blocker,
		"blocked_at_m": snappedf(float(tr.distance), 0.1) if tr.blocker != "range" else -1.0}


## Shots at a soldier at p in each posture from eight directions (40 m, eye 1.5 m above the shooter's ground) and from a rise
## (the same, the eye 5 m up): {stand, crouch, prone} each {hit_level, hit_high, of}; the brain's verdict on the spot.
func _posture_table(p: Vector3, dirs: Array) -> Dictionary:
	var out := {}
	for pp: Array in [["stand", Posture.STAND], ["crouch", Posture.CROUCH], ["prone", Posture.PRONE]]:
		var row := {"hit_level": 0, "hit_high": 0, "of": 0}
		for d: Vector3 in dirs:
			var u := _target(p, d, int(pp[1]))
			await _physics(2)
			var g := demo.on_ground(p.x + d.x * 40.0, p.z + d.z * 40.0, 0.0)
			row.hit_level += _hits(g + Vector3.UP * 1.5, u)
			row.hit_high += _hits(g + Vector3.UP * 5.0, u)
			row.of += 2
			demo.sim.state.remove_unit(u.id)
		out[pp[0]] = row
	return out


# --- Checks -------------------------------------------------------------------------------------------------------------------

func _r_survey() -> Dictionary:
	var out := {}
	var map := demo.get_viewport().get_world_3d().navigation_map
	var counts := {}
	for f: Dictionary in _feats:
		counts[f.kind] = int(counts.get(f.kind, 0)) + 1
	out["features"] = counts
	for kind: String in ["hollow", "swell", "fold", "step", "ditch", "bank"]:
		var list := _relief(kind, _site.def, 6)
		out[kind] = {"n_near": list.size()}
		if list.is_empty():
			continue
		var best: Dictionary = list[0]
		var best_n := 1 << 30
		for e: Dictionary in list:
			var n := _trunks_near(e.c, 10.0)
			if n < best_n:
				best_n = n
				best = e
		var c: Vector3 = best.c
		demo.rts_camera.camera.make_current()
		_tcam.current = false
		demo.rts_camera.frame(c, 0.6, 30.0)
		await _seconds(5.0)
		var row: Dictionary = out[kind]
		row["at"] = _v(c)
		row["relief_m"] = snappedf(TerrainRelief.delta_at(c.x, c.z), 0.01)
		var cy := _collision_y(c)
		row["collision_minus_data_m"] = snappedf(cy - c.y, 0.01) if not is_nan(cy) else "no collider"
		var np := NavigationServer3D.map_get_closest_point(map, c)
		row["navmesh_off_m"] = snappedf(np.distance_to(c), 0.01)
		row["plants"] = _plants_off_ground(c, 14.0)
		_expect(not is_nan(cy) and absf(cy - c.y) < 0.2, "r_survey: %s collision does not match the terrain data %s" % [kind, str(row)])
		_expect(int(row.plants.floating) == 0, "r_survey: %s plants floating %s" % [kind, str(row.plants)])
		_png("relief_%s_rts" % kind)
		var yaw := _open_side(c, 0.4)
		_cam(c + Vector3.UP * 0.5, 16.0, yaw, 7.0)
		await _seconds(1.5)
		_png("relief_%s_side" % kind)
	return out


## The whole relief file against what it must leave alone: the ground under every cover-layer object and every added object of
## the settlement / user overrides layers unchanged; no feature's deepest / highest point near a road (ditches: beside their own
## road only) or a bridge; the apply cost and the vegetation moved.
func _r_global() -> Dictionary:
	var out := {"features": _feats.size(), "apply": TerrainRelief.stats}
	var kinds := {}
	for f: Dictionary in _feats:
		kinds[f.kind] = int(kinds.get(f.kind, 0)) + 1
	out["kinds"] = kinds
	var moved := 0
	var checked := 0
	var worst := 0.0
	var files := [CoverLayer.path(demo.config.world_name), SettlementLayer.overrides_path(demo.config.world_name), "res://worlds/%s.overrides.json" % demo.config.world_name]
	for file: String in files:
		if file == "" or not FileAccess.file_exists(file):
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not j is Dictionary:
			continue
		for rec: Dictionary in (j.get("records", {}) as Dictionary).values():
			if rec.get("kind", "") != "added" or not rec.has("transform"):
				continue
			var t: Array = rec.transform
			var dv := absf(TerrainRelief.delta_at(float(t[9]), float(t[11])))
			checked += 1
			worst = maxf(worst, dv)
			if dv > 0.03:
				moved += 1
	out["objects_checked"] = checked
	out["objects_on_changed_ground"] = moved
	out["worst_change_under_object_m"] = snappedf(worst, 0.01)
	var roads := demo.sim.state.roads
	var near_road := 0
	var near_bridge := 0
	for f: Dictionary in _feats:
		var c := _extreme(f)
		if roads.bridge_at(c, 40.0) != null:
			near_bridge += 1
		if int(f.type) != TerrainRelief.LINE or String(f.kind) != "ditch":
			var n := roads.nearest(c, 30.0, 0, 0.0)
			if not n.is_empty() and float(n.dist) < (n.road as RoadNetwork.Road).width * 0.5 + 12.0:
				near_road += 1
	out["features_near_road"] = near_road
	out["features_near_bridge"] = near_bridge
	_expect(moved == 0, "r_global: %d objects stand on ground the relief changed (worst %.2f m)" % [moved, worst])
	_expect(near_road == 0 and near_bridge == 0, "r_global: features near roads %d / bridges %d" % [near_road, near_bridge])
	return out


func _k_colliders() -> Dictionary:
	var out := {}
	var line := demo.sim.combat.line
	var lib := demo.vegetation.library
	for name: String in ["rockgroup", "rootplate", "log", "wall", "ridge"]:
		var id: int = CoverLayer.IDS[name]
		var def: VegetationMeshDef = lib.get_def(id)
		var objs := _objects(id, _site.def, 6)
		var row := {"objects": objs.size(), "phantom_shots": 0, "shots": 0, "trunk_prone_protected": 0, "trunk_probes": 0}
		for o: Dictionary in objs:
			var p: Vector3 = o.pos
			demo.rts_camera.frame(p, 0.6, 40.0)
			await _seconds(0.6)
			var s := float(o.scale)
			var yaw := float(o.yaw)
			var axis := Vector3(cos(yaw), 0, -sin(yaw))
			var across := Vector3(sin(yaw), 0, cos(yaw))
			# Across the object at five stations along it, just under the single box's top: stopped only where the object is that tall.
			for k in 5:
				var c := p + axis * def.box.x * s * (-0.8 + 0.4 * k)
				var y := p.y + def.box.y * s - 0.08
				var a := Vector3(c.x, y, c.z) - across * 12.0
				var b := Vector3(c.x, y, c.z) + across * 12.0
				var tr := line.trace(a, b, -1, false)
				row.shots += 1
				if tr.blocker == "tree":
					row.phantom_shots += 1
			if name == "rootplate":
				# A prone soldier beside the lying trunk (2.5 m from the plate along it), shot at from across the trunk.
				for side: float in [-1.0, 1.0]:
					var spot := p + axis * 3.5 * s + across * side * (0.5 * s + 1.0)
					var u := _target(spot, -across * side, Posture.PRONE)
					await _physics(2)
					var g := demo.on_ground(spot.x + across.x * side * 30.0, spot.z + across.z * side * 30.0, 0.0)
					row.trunk_probes += 1
					if _hits(g + Vector3.UP * 1.5, u) == 0:
						row.trunk_prone_protected += 1
					demo.sim.state.remove_unit(u.id)
		out[name] = row
	return out


func _b_hollow() -> Dictionary:
	var out := {"spots": []}
	var dirs: Array = []
	for k in 8:
		dirs.append(Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)))
	var list := _relief("hollow", _site.def, 3, 0.55)
	_expect(not list.is_empty(), "b_hollow: no hollow of 0.55 m near the test area")
	for e: Dictionary in list:
		var p: Vector3 = e.c
		demo.rts_camera.frame(p, 0.6, 40.0)
		await _seconds(1.0)
		var t := await _posture_table(p, dirs)
		var ev: Dictionary = demo.sim.brain._evaluate_spot(null, p, p + dirs[0] * 60.0)
		out.spots.append({"at": _v(p), "depth": float(e.f.d), "relief_m": snappedf(TerrainRelief.delta_at(p.x, p.z), 0.01), "table": t,
			"brain": {"protected": ev.protected, "low": ev.get("low", false), "can_fire": ev.can_fire}})
	if shots and not list.is_empty():
		var p: Vector3 = list[0].c
		var u := _target(p, Vector3.FORWARD, Posture.PRONE)
		await _seconds(1.5)
		_cam(p + Vector3.UP * 0.3, 9.0, 0.6, 9.0)
		await _seconds(1.0)
		_png("hollow_prone_side")
		demo.sim.state.remove_unit(u.id)
	return out


func _c_ridge() -> Dictionary:
	var out := {"spots": []}
	var list := _relief("fold", _site.def, 3, 0.8)
	_expect(not list.is_empty(), "c_ridge: no fold of 0.8 m near the test area")
	for e: Dictionary in list:
		var f: Dictionary = e.f
		var cr := _crest(f)
		var crest: Vector3 = cr[0]
		var across: Vector3 = cr[1]
		var w := float(f.wb)
		demo.rts_camera.frame(crest, 0.6, 40.0)
		await _seconds(1.0)
		for frac: float in [0.55, 0.75]:
			var p := demo.on_ground(crest.x - across.x * w * frac, crest.z - across.z * w * frac, 0.0)
			var dirs: Array = []
			for a: float in [0.0, 0.5, -0.5]:
				dirs.append(across.rotated(Vector3.UP, a))
			var t := await _posture_table(p, dirs)
			# Firing over it at a shooter 60 m across the fold, in each posture.
			var enemy := demo.on_ground(crest.x + across.x * 60.0, crest.z + across.z * 60.0, 0.0) + Vector3.UP * 1.1
			var fire := {}
			for pp: Array in [["stand", Posture.STAND], ["crouch", Posture.CROUCH], ["prone", Posture.PRONE]]:
				var u := _target(p, across, int(pp[1]))
				await _physics(2)
				fire[pp[0]] = _can_fire(u, enemy)
				demo.sim.state.remove_unit(u.id)
			var ev: Dictionary = demo.sim.brain._evaluate_spot(null, p, enemy)
			out.spots.append({"at": _v(p), "height": float(f.h), "behind_crest_m": snappedf(w * frac, 0.1), "table": t, "fire": fire,
				"brain": {"protected": ev.protected, "low": ev.get("low", false), "can_fire": ev.can_fire}})
	return out


## The mandatory same-soldier check: the AI puts a squad into cover at a fold (or a cover object); one soldier in cover is shown
## from the RTS camera, possessed without changing the world state and checked in first person.
func _v_same() -> Dictionary:
	var out := {}
	# A fold on open ground (no trunks to hide behind instead): the soldier picked must be shielded by the terrain itself.
	var routes: StrategicRoutes = demo.sim.war.routes
	var folds := _relief("fold", _site.def, 12, 1.0).filter(func(e: Dictionary) -> bool: return routes.cover_at(e.c) <= 0.3 and _trunks_near(e.c, 15.0) <= 2)
	_expect(not folds.is_empty(), "v_same: no fold on open ground near the test area")
	if not folds.is_empty():
		var f: Dictionary = folds[0].f
		var cr := _crest(f)
		out["relief"] = await _same_soldier(cr[0] - (cr[1] as Vector3) * float(f.wb) * 0.6, cr[1], "relief", func(u: UnitState, threat: Vector3) -> bool:
			return String(demo.sim.brain._evaluate_spot(u, u.position, threat).get("blocker", "")) == "terrain")
	# A boulder on open ground: the first of three where the defence puts a soldier behind it.
	var objs := _objects(CoverLayer.IDS.boulder, _site.def, 12).filter(func(o: Dictionary) -> bool: return routes.cover_at(o.pos) <= 0.3).slice(0, 3)
	for o: Dictionary in objs:
		var p: Vector3 = o.pos
		var d := Vector3(1, 0, 0.2).normalized()
		var row := await _same_soldier(p - d * 5.0, d, "object", func(u: UnitState, _threat: Vector3) -> bool: return _cover_dist(u.position) < 3.5, false)
		if row.has("fps"):
			out["object"] = row
			break
		out["object_tries"] = int(out.get("object_tries", 0)) + 1
	_expect(out.has("object"), "v_same: no defence put a soldier behind any of %d boulders on open ground" % objs.size())
	return out


func _near_feature(p: Vector3, r: float) -> bool:
	for f: Dictionary in _feats:
		if (f.box as Rect2).grow(r).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _same_soldier(at: Vector3, across: Vector3, tag: String, at_cover: Callable, required := true) -> Dictionary:
	var row := {}
	# The enemy where it sees a man standing at the place (so the cover, not a hill beyond, decides what it sees of him).
	var line := demo.sim.combat.line
	var ground := demo.on_ground(at.x, at.z, 0.0)
	var ep := at + across * 90.0
	var found := false
	for d: float in [70.0, 90.0, 110.0, 130.0, 55.0]:
		for a: float in [0.0, 0.3, -0.3, 0.6, -0.6]:
			var q := demo.on_ground(at.x + across.rotated(Vector3.UP, a).x * d, at.z + across.rotated(Vector3.UP, a).z * d, 0.0)
			if line.sight(q + Vector3.UP * 1.6, ground + Vector3.UP * 1.6).visible:
				ep = q
				found = true
				break
		if found:
			break
	row["enemy_sees_standing_man"] = found
	var sq := _cs.spawn(0, at - across * 25.0, across, 4, "VS")
	var en := _cs.spawn(1, ep, (at - ep).normalized(), 2, "VE")
	_tough([sq])
	for id in en.members:
		demo.sim.state.get_unit(id).max_health = 9999.0
		demo.sim.state.get_unit(id).health = 9999.0
	var enemy_u := demo.sim.state.get_unit(en.members[0])
	demo.rts.select_squads([sq.id])
	demo.rts.order_tactic(SquadState.Tactic.DEFEND, at)
	await _until(func() -> bool: return false, 30.0, 2.0)
	var threat: Vector3 = enemy_u.position
	var pick: UnitState = null
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u and at_cover.call(u, threat) and demo.sim.brain._evaluate_spot(u, u.position, threat).protected:
			pick = u
			break
	row["defend"] = {"tactic": sq.tactic_name(), "why": sq.tactic_why}
	_expect(pick != null or not required, "v_same %s: no soldier of the defence in cover at the %s" % [tag, tag])
	if pick == null:
		await _clear_squads([sq, en])
		return row
	# Hold the scene still: the enemy holds fire, everyone holds where they are.
	en.roe = SquadState.Roe.HOLD_FIRE
	var p0 := pick.position
	var post0 := pick.posture
	row["soldier"] = pick.unit_name
	row["at"] = _v(p0)
	row["posture"] = Posture.NAMES[post0]
	var tdir := Vector3(threat.x - p0.x, 0, threat.z - p0.z).normalized()
	demo.rts.select_squads([sq.id])
	demo.rts_camera.camera.make_current()
	_tcam.current = false
	demo.rts_camera.frame(p0, atan2(-tdir.x, -tdir.z), 14.0)
	await _seconds(2.0)
	_png("same_%s_rts_before" % tag)
	var ok := demo.game.possess(pick.id)
	row["possessed"] = ok
	_expect(ok, "v_same %s: could not possess %s" % [tag, pick.unit_name])
	if not ok:
		await _clear_squads([sq, en])
		return row
	await _seconds(1.5)
	var body := demo.sim.body_of(pick.id) as SoldierBody
	row["moved_on_possess_m"] = snappedf(_flat3(pick.position, p0), 0.01)
	row["posture_kept"] = pick.posture == post0
	_expect(_flat3(pick.position, p0) < 0.5, "v_same %s: possession moved the soldier %.2f m" % [tag, _flat3(pick.position, p0)])
	# Look at the threat (the body's own yaw / pitch), then each posture.
	var checks := {}
	for pp: Array in [["stand", Posture.STAND], ["crouch", Posture.CROUCH], ["prone", Posture.PRONE]]:
		_set_posture(pick, int(pp[1]))
		_aim_body(body, enemy_u.position + Vector3.UP * 1.0)
		await _seconds(1.2)
		var g := _collision_y(pick.position, [body.get_rid()] as Array[RID])
		var eye_e := enemy_u.position + Vector3.UP * 1.5
		var hits := _hits(eye_e, pick)
		var cam := body.camera.global_position
		var shot := demo.sim.combat.preview_shot(pick.id, cam, (enemy_u.position + Vector3.UP * 1.0 - cam).normalized(), 9999, 0.0)
		var row2 := {"hits_from_threat": hits, "of": 2, "shot_blocker": shot.get("blocker", "?"), "shot_hit_enemy": int(shot.get("hit_unit", -1)) == enemy_u.id,
			"shot_blocked_at_m": snappedf(float(shot.get("distance", -1.0)), 0.1),
			"muzzle_clear": shot.get("blocker", "") in ["range", "unit"] or float(shot.get("distance", 0.0)) > 1.5,
			"feet_minus_ground_m": snappedf(body.global_position.y - g, 0.02) if not is_nan(g) else "no collider",
			"inside_solid": demo.sim.structures.blocks_trunk(Vector2(pick.position.x, pick.position.z), 0.2),
			"camera_minus_posture_eye_m": snappedf(cam.y - Posture.eye(pick).y, 0.02)}
		checks[pp[0]] = row2
		_expect(not bool(row2.inside_solid), "v_same %s: %s stands inside a solid" % [tag, pick.unit_name])
		_expect(is_nan(g) or absf(body.global_position.y - g) < 0.35, "v_same %s %s: body off the ground %s" % [tag, pp[0], str(row2)])
		_png("same_%s_fps_%s" % [tag, pp[0]])
	row["fps"] = checks
	_set_posture(pick, post0)
	demo.game.enter_rts()
	await _seconds(1.0)
	demo.rts.select_squads([sq.id])
	demo.rts_camera.camera.make_current()
	demo.rts_camera.frame(pick.position, atan2(-tdir.x, -tdir.z), 14.0)
	await _seconds(1.5)
	_png("same_%s_rts_after" % tag)
	row["moved_total_m"] = snappedf(_flat3(pick.position, p0), 0.01)
	await _clear_squads([sq, en])
	return row


func _flat3(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Turns a possessed body's view to `at` (its look yaw / pitch, as the mouse would).
func _aim_body(body: SoldierBody, at: Vector3) -> void:
	var cam := body.camera.global_position
	var d := at - cam
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	body.rotation.y = yaw
	body.head.rotation.x = clampf(pitch, -deg_to_rad(body.max_pitch_deg), deg_to_rad(body.max_pitch_deg))


## Protection at the end of a move, by the posture the soldier holds: a "low" spot counts only for a prone soldier.
func _held_protected(u: UnitState, threat: Vector3) -> bool:
	var ev: Dictionary = demo.sim.brain._evaluate_spot(u, u.position, threat)
	return bool(ev.protected) and (not bool(ev.get("low", false)) or u.posture == Posture.PRONE)


## An open place (forest cover of the route grid below 0.25) with relief features within 25 m, nearest the site.
func _relief_place() -> Vector3:
	var routes: StrategicRoutes = demo.sim.war.routes
	var best := Vector3.INF
	var best_d := INF
	for f: Dictionary in _feats:
		if not String(f.kind) in ["fold", "hollow", "swell"]:
			continue
		var c := _extreme(f)
		var n := 0
		for g: Dictionary in _feats:
			if (g.box as Rect2).grow(25.0).has_point(Vector2(c.x, c.z)):
				n += 1
		var d := Vector2(c.x - _site.def.x, c.z - _site.def.z).length() - n * 60.0
		if routes.cover_at(c) <= 0.25 and d < best_d:
			best_d = d
			best = c
	return best


func _move_to_threat(beh: int, tag: String) -> Dictionary:
	var c := _relief_place()
	if not c.is_finite():
		failures.append("%s: no open place with relief" % tag)
		return {}
	# The enemy is reported 230 m from the goal: beyond QOL-01's contact range (a reported contact nearer than 220 m interrupts a
	# COMBAT move), inside the end-of-move cover range (350 m COMBAT, 450 m STEALTH).
	var enemy := _cs.spawn(1, c + Vector3(0, 0, -230), Vector3.BACK, 4, tag + "E")
	var sq := _cs.spawn(0, c + Vector3(-70, 0, 30), Vector3.RIGHT, 6, tag + "S")
	sq.behaviour = beh
	_tough([sq])
	demo.sim.war.intel.report_seen(demo.sim.state.get_unit(sq.members[0]), demo.sim.state.get_unit(enemy.members[0]), 4)
	await _until(func() -> bool: return demo.sim.tactics.threat_pos(sq).is_finite(), 10.0, 1.0)
	var threat := demo.sim.tactics.threat_pos(sq)
	# The enemy is only reported (removed): the squad acts on what it believes, nobody shoots.
	for id in enemy.members:
		demo.sim.state.remove_unit(id)
	var start := demo.sim.squads._centroid(sq)
	var path := 0.0
	var last := start
	demo.rts.select_squads([sq.id])
	demo.rts.order_move(c)
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(2.0)
	while demo.sim.state.time - t0 < 120.0:
		await _physics(15)
		var cc := demo.sim.squads._centroid(sq)
		path += _flat3(cc, last)
		last = cc
		if demo.sim.state.time - t0 > 8.0 and sq.status != SquadState.Status.MOVING and not demo.sim.squads.marching(sq) \
				and not demo.sim.squads.route_waiting(sq) and (not demo.sim.tactics.settle_enabled or String(demo.sim.tactics._meta(sq, "settled_key", "")) != ""):
			# Done: arrived, and (when it settles) at its final positions too.
			break
	CoreDemo.apply_time_scale(1.0)
	await _seconds(4.0)
	var prot := 0
	var far := 0.0
	var exp_sum := 0.0
	var postures := {}
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if _held_protected(u, threat):
			prot += 1
		far = maxf(far, _flat3(u.position, c))
		exp_sum += demo.sim.tactics.pos.exposure(u.position, threat)
		postures[Posture.NAMES[u.posture]] = int(postures.get(Posture.NAMES[u.posture], 0)) + 1
	var settled: Dictionary = demo.sim.tactics._meta(sq, "settled", {})
	var out := {"at": _v(c), "time_s": snappedf(demo.sim.state.time - t0, 0.1), "protected_at_end": prot, "of": sq.members.size(),
		"exposure_avg": snappedf(exp_sum / maxi(sq.members.size(), 1), 0.01), "farthest_from_goal_m": snappedf(far, 0.1),
		"path_m": snappedf(path, 1.0), "straight_m": snappedf(_flat3(start, c), 1.0), "postures": postures, "settled": settled,
		"state": demo.sim.squads.describe_order(sq).text}
	demo.rts_camera.camera.make_current()
	_tcam.current = false
	var td := (threat - c).normalized()
	demo.rts_camera.frame(c, atan2(-td.x, -td.z), 30.0)
	await _seconds(2.0)
	_png("%s_end_rts" % tag)
	_expect(far < 40.0, "%s: soldiers ended %.0f m from the ordered point" % [tag, far])
	_expect(demo.sim.squads.describe_order(sq).state in ["arrived", "holding"], "%s: order not completed (%s)" % [tag, out.state])
	await _clear_squads([sq])
	return out


func _d_combat_move() -> Dictionary:
	return await _move_to_threat(SquadBehaviour.COMBAT, "combat_move")


func _e_stealth_move() -> Dictionary:
	return await _move_to_threat(SquadBehaviour.STEALTH, "stealth_move")


func _f_road() -> Dictionary:
	var out := {}
	var ditches := _relief("ditch", _site.def, 1)
	out["ditch_near"] = _v(ditches[0].c) if not ditches.is_empty() else []
	out["infantry"] = await _c_road()
	# Vehicles: cross-country plans across the road at the nearest ditch, both ways, for an APC and a truck.
	var veh := {}
	if not ditches.is_empty():
		var c: Vector3 = ditches[0].c
		var n := demo.sim.state.roads.nearest(c, 60.0, 0, 0.0)
		var rp: Vector3 = n.pos if not n.is_empty() else c
		var across := Vector3(c.x - rp.x, 0, c.z - rp.z).normalized()
		var along := Vector3(-across.z, 0, across.x)
		for vid: StringName in [&"apc", &"truck"]:
			var def := VehicleDefs.get_def(vid)
			var r := {"ok": 0, "of": 0, "max_grade": 0.0}
			for k in [-1, 0, 1]:
				for sgn: float in [1.0, -1.0]:
					var a := demo.on_ground(rp.x + across.x * 45.0 * sgn + along.x * k * 25.0, rp.z + across.z * 45.0 * sgn + along.z * k * 25.0, 0.0)
					var b := demo.on_ground(rp.x - across.x * 45.0 * sgn + along.x * k * 25.0, rp.z - across.z * 45.0 * sgn + along.z * k * 25.0, 0.0)
					var res := demo.sim.vehicles.router.plan(a, b, def)
					r.of += 1
					if res.ok:
						r.ok += 1
						var pts: PackedVector3Array = res.points
						for i in range(1, pts.size()):
							var dd := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
							var steps := maxi(1, int(dd / 2.0))
							for s in steps:
								var q0 := pts[i - 1].lerp(pts[i], float(s) / steps)
								var q1 := pts[i - 1].lerp(pts[i], float(s + 1) / steps)
								var h0: float = demo.sim.terrain.data.get_height(q0)
								var h1: float = demo.sim.terrain.data.get_height(q1)
								r.max_grade = maxf(float(r.max_grade), absf(h1 - h0) / maxf(dd / steps, 0.1))
			r.max_grade = snappedf(float(r.max_grade), 0.01)
			veh[String(vid)] = r
			_expect(int(r.ok) == int(r.of), "f_road: %s could not cross the road with ditches %s" % [vid, str(r)])
	out["vehicles"] = veh
	return out


func _g_two_threats() -> Dictionary:
	var folds := _relief("fold", _site.def, 1, 0.8)
	if folds.is_empty():
		return {"skipped": "no fold"}
	var cr := _crest(folds[0].f)
	var across: Vector3 = cr[1]
	var c: Vector3 = cr[0] - across * float(folds[0].f.wb) * 0.4
	var sq := _cs.spawn(0, c - across * 10.0, across, 8, "GTS")
	var side := Vector3(-across.z, 0, across.x)
	var e1 := _cs.spawn(1, c + across * 120.0, -across, 3, "GT1")
	var e2 := _cs.spawn(1, c + side * 120.0, -side, 3, "GT2")
	if e2.members.is_empty():
		e2 = _cs.spawn(1, c - side * 120.0, side, 3, "GT2")
	if e1.members.is_empty() or e2.members.is_empty() or sq.members.is_empty():
		failures.append("g_two_threats: a squad could not be placed")
		await _clear_squads([sq, e1, e2])
		return {}
	_tough([sq])
	for e: SquadState in [e1, e2]:
		for id in e.members:
			demo.sim.state.get_unit(id).max_health = 9999.0
			demo.sim.state.get_unit(id).health = 9999.0
	var t1: Vector3 = demo.sim.state.get_unit(e1.members[0]).position
	var t2: Vector3 = demo.sim.state.get_unit(e2.members[0]).position
	demo.rts.select_squads([sq.id])
	demo.rts.order_tactic(SquadState.Tactic.DEFEND, c)
	await _until(func() -> bool: return false, 40.0, 2.0)
	var vs1 := 0
	var vs2 := 0
	var either := 0
	for id in sq.members:
		var u := demo.sim.state.get_unit(id)
		if u == null:
			continue
		var p1 := _held_protected(u, t1)
		var p2 := _held_protected(u, t2)
		vs1 += int(p1)
		vs2 += int(p2)
		either += int(p1 or p2)
	var out := {"at": _v(c), "protected_vs_across": vs1, "protected_vs_side": vs2, "protected_from_one": either, "of": sq.members.size(),
		"tactic": sq.tactic_name(), "why": sq.tactic_why}
	demo.rts_camera.camera.make_current()
	_tcam.current = false
	demo.rts_camera.frame(c, atan2(-across.x, -across.z), 35.0)
	await _seconds(2.0)
	_png("two_threats_fold")
	await _clear_squads([sq, e1, e2])
	return out


func _a_open() -> Dictionary:
	var m := await _fight(_relief_place(), "open_relief")
	_expect(not m.is_empty() and int(m.get("shots", 0)) > 20, "a_open: no fight happened %s" % str(m))
	return m


## Posture-aware exposure (a low spot protects only a prone soldier) and soldiers on the microrelief, for WorldCoverSelfTest._fight.
func _watch(squads: Array, seconds: float) -> Dictionary:
	var m := {"samples": 0, "threatened": 0, "protected": 0, "on_relief": 0, "at_cover_object": 0, "blocked": 0, "in_cover_state": 0, "prone": 0}
	var t0 := demo.sim.state.time
	CoreDemo.apply_time_scale(2.0)
	while demo.sim.state.time - t0 < seconds:
		await _physics(15)
		for sq: SquadState in squads:
			for id in sq.members:
				var u := demo.sim.state.get_unit(id)
				if u == null or not u.alive:
					continue
				m.samples += 1
				var threat := u.target_last_pos if u.target_last_pos.is_finite() and demo.sim.state.time - u.target_seen_at < 6.0 else u.threat_pos
				if threat.is_finite():
					m.threatened += 1
					if _held_protected(u, threat):
						m.protected += 1
				if _near_feature(u.position, 0.0):
					m.on_relief += 1
				if u.cover_pos.is_finite() and _cover_dist(u.cover_pos) < 3.5:
					m.at_cover_object += 1
				if u.move_state == UnitState.MoveState.BLOCKED:
					m.blocked += 1
				if u.tactic == UnitState.Tactic.IN_COVER:
					m.in_cover_state += 1
				if u.posture == Posture.PRONE:
					m.prone += 1
	CoreDemo.apply_time_scale(1.0)
	m["protected_share"] = snappedf(float(m.protected) / maxi(int(m.threatened), 1), 0.01)
	m["on_relief_share"] = snappedf(float(m.on_relief) / maxi(int(m.samples), 1), 0.01)
	return m


func _q_perf() -> Dictionary:
	var out := {}
	var c := _relief_place()
	if not c.is_finite():
		c = _site.def
	for v: Array in [["rts", 70.0], ["ground", 0.0]]:
		if float(v[1]) > 0.0:
			_tcam.current = false
			demo.rts_camera.camera.make_current()
			demo.rts_camera.frame(c, 0.6, float(v[1]))
		else:
			_cam(c + Vector3.UP * 1.6, 4.0, 0.7, 2.0)
		await _seconds(4.0)
		var frames: Array = []
		var t := Time.get_ticks_usec()
		var end := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < end:
			await tree.process_frame
			var n := Time.get_ticks_usec()
			frames.append((n - t) / 1000.0)
			t = n
		frames.sort()
		out[v[0]] = {"median_ms": snappedf(frames[frames.size() / 2], 0.1), "p95_ms": snappedf(frames[int(frames.size() * 0.95)], 0.1), "max_ms": snappedf(frames[-1], 0.1)}
	out["relief_apply"] = TerrainRelief.stats
	out["route_grid"] = demo.spawn_info.get("route_grid", {})
	# The cover search with the relief candidates: a post search at the relief place (cost of SquadPositions.find_posts).
	var pos := demo.sim.tactics.pos
	var t1 := Time.get_ticks_usec()
	for k in 5:
		pos.find_posts(8, c, 18.0, c + Vector3(0, 0, -110), {"mode": "fire"})
	out["find_posts_usec_avg"] = (Time.get_ticks_usec() - t1) / 5
	return out
