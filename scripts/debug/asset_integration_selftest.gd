## ASSET-INTEGRATION-01 checks in the real game on ref_20km (Development Scenario): the 16 WEAPON-ASSETS-01 weapons and
## the 6 VEHICLE-ASSETS-01 vehicles through the systems that use them. Short and deterministic, no stochastic battles.
##
##   Godot.exe --path . --fullscreen --log-file ai1.log res://scenes/game/world_ref_20km.tscn -- --asset-integration-test [--shots] [--only r_registry,...] [--shot-dir=res://docs/asset_integration01]
##
## r_registry  every weapon: WeaponDef, development role, a loadout per faction family, its piece (scene, muzzle, hold);
##             every vehicle: definition, GLB, sidecar parts; and the New Game guards - no new type in BaseSim's vehicle
##             table or VehicleDefs.all_ids, no development role in the equipment screen's role list, no armoury rule in
##             the New Game scenario, no new weapon in any development project.
## w_weapons   one soldier, each weapon in turn given through the armoury (CombatSim.give_role) and raised at a point:
##             record fields, the piece in the hands, the magazine on ATT_Magazine, and the grip measured on the posed
##             skeleton - firing wrist and support wrist in weapon space against the shared rifle's hold, the aiming eye
##             against the rifle's eye point (cm). Third-person close-ups.
## f_fps       first person with representative weapons (rifle, pistol, DMR, MG, sniper, launchers): hip and ADS
##             screenshots, the sight line on the camera axis (measured), a shot, a reload (mid-reload screenshot), the
##             launchers switched to with X and fired.
## p_posture   crouch and prone holding an MG, a pistol and a launcher: grip errors per posture, screenshots.
## v_switch    FPS -> RTS -> FPS keeps the weapon (record and first-person piece).
## v_vehicles  the six vehicles parked in a row next to a soldier (scale), their bodies, parts by kind, seats, collision,
##             orientation markers; then every moving part driven (doors, turret, gun, RWS, rotors): moved from rest.
## v_drive     LMV, Scania, CV90 and Leopard driven 50 m by VehicleSim (displacement, wheels / road wheels turned); the
##             NH90 refuses to drive (no movement model).
## v_transport a squad of four boards the Patria (doors open while it boards), is carried aboard, gets out again.
## s_persist   a soldier's development role, weapon, look and secondary, and every vehicle type through the save
##             serialiser (UnitState.to_dict / from_dict through var_to_str, as WorldState saves).
## Prints "AI1 <check> <json>", writes res://benchmarks/raw/asset_integration_test.json.
class_name AssetIntegrationSelfTest
extends Visual03SelfTest

const CHECKS_AI: Array[String] = ["r_registry", "w_weapons", "f_fps", "p_posture", "v_switch", "v_vehicles", "v_drive",
	"v_transport", "s_persist"]
const FPS_SET: Array[StringName] = [&"hk416", &"glock_17", &"svd", &"fn_mag", &"axmc", &"ak74m", &"pkp_pecheneg", &"fn_minimi",
	&"carl_gustaf_m4", &"rpg7", &"m72_law"]
const LAUNCHERS: Array[StringName] = [&"carl_gustaf_m4", &"m72_law", &"rpg7", &"rpg26"]

var _arm: DevArmoury
var _base := {}


func run(args: PackedStringArray) -> void:
	shots = "--shots" in args
	_shot_dir = "res://docs/asset_integration01"
	for a in args:
		if a.begins_with("--shot-dir="):
			_shot_dir = a.trim_prefix("--shot-dir=")
	var oi := args.find("--only")
	only = args[oi + 1].split(",") if oi >= 0 and oi + 1 < args.size() else PackedStringArray(CHECKS_AI)
	SoldierBody.require_mouse_capture = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	tree.create_timer(1200.0, true, false, true).timeout.connect(func() -> void:
		failures.append("watchdog: test did not finish")
		_finish())
	await _physics(30)
	_arm = demo.armoury
	_expect(_arm != null, "the Development Scenario has no armoury (rule dev_armoury)")
	if _arm == null:
		_arm = DevArmoury.new()
		_arm.demo = demo
		demo.hud.add_child(_arm)
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
	demo.rts.select_squads([])
	UnitVisuals.markers_visible = false
	for n in CHECKS_AI:
		if only.has(n):
			demo.rts_camera.frame(_site.def, 0.6, 40.0)
			await _seconds(2.0)
			_log(n, await call("_" + n))
			if demo.game.mode != GameController.Mode.RTS:
				demo.game.enter_rts()
			_tcam.current = true
			_cs.reset()
			await _physics(10)
	_finish()


func _log(check: String, data: Dictionary) -> void:
	results[check] = data
	print("AI1 %s %s" % [check, JSON.stringify(data)])


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		print("AI1 FAILED CHECK: ", msg)


func _finish() -> void:
	if _done:
		return
	_done = true
	results["failures"] = failures
	results["pass"] = failures.is_empty()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/asset_integration_test.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	print("AI1 %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(failures)])
	demo.get_tree().quit(0 if failures.is_empty() else 1)


# --- helpers ------------------------------------------------------------------------------------------------------------

func _right(f: Vector3) -> Vector3:
	return Vector3(-f.z, 0.0, f.x)


## Raises the soldier's weapon at a point 60 m ahead (the AI's aim layer, no brain needed).
func _raise(u: UnitState, dir: Vector3) -> void:
	u.target_id = 99999
	u.target_last_pos = u.position + dir * 60.0 + Vector3.UP * 0.3
	u.target_seen_at = demo.sim.state.time + 600.0
	u.last_shot_at = demo.sim.state.time


## The posed grip of a soldier's character: the firing and support wrists in the held weapon's space, and the weapon's
## aiming eye in the character's space (m).
func _grip_of(u: UnitState) -> Dictionary:
	var ch := _char(u)
	if ch == null or ch.skeleton == null:
		return {}
	var root: Node3D = ch._held_secondary if ch.secondary_shown() else ch._weapon_root_node()
	var piece: InfantryEquipment = null
	if ch.secondary_shown():
		var sd := demo.sim.combat.weapon(u.sec_id)
		piece = sd.held_piece if sd else null
	else:
		piece = ch.loadout.item_in_slot("weapon")
	if root == null or piece == null:
		return {}
	var w := root.global_transform
	var inv := w.affine_inverse()
	# the posed (modified) skeleton is what bone attachments follow; get_bone_global_pose would give the clip's pose
	var rh := _bone_probe(ch, "RightHand").global_position
	var lh := _bone_probe(ch, "LeftHand").global_position
	var head := _bone_probe(ch, "Head").global_transform
	var marker := root.find_child("GRIP_Support", true, false) as Node3D
	var support := piece.support_grip if piece.support_grip != Vector3.ZERO else (InfantryCharacter._local_in(root, marker) if marker else InfantryGripIK.STD_SUPPORT)
	var g: InfantryGripIK = ch._grip
	var eye := head * g.eye_local if g and g.eye_local.is_finite() else head.origin
	var look := (head.basis * g.head_fwd_local).normalized() if g else Vector3.FORWARD
	var bore := (w.basis * Vector3.FORWARD).normalized()
	return {"r_wrist": inv * rh, "l_from_support": inv * lh - support, "eye_off_cm": snappedf(eye.distance_to(w * piece.aim_eye) * 100.0, 0.1),
		"look_bore_deg": snappedf(rad_to_deg(look.angle_to(bore)), 0.1),
		"grip": "aim_w=%.2f shift=%s" % [g.aim_w, g.last_shift.snapped(Vector3.ONE * 0.001)] if g else "none"}


## Puts the bone probes on the soldier's current character (they follow the posed skeleton from the next frame on).
func _probes(u: UnitState) -> void:
	var ch := _char(u)
	if ch and ch.skeleton:
		for b in ["RightHand", "LeftHand", "Head"]:
			_bone_probe(ch, b)


func _bone_probe(ch: InfantryCharacter, bone: String) -> Node3D:
	var n := ch.skeleton.get_node_or_null("Probe_" + bone) as Node3D
	if n == null:
		var ba := BoneAttachment3D.new()
		ba.name = "Probe_" + bone
		ba.bone_name = bone
		ch.skeleton.add_child(ba)
		n = ba
	return n


func _err_cm(a: Vector3, b: Vector3) -> float:
	return snappedf(a.distance_to(b) * 100.0, 0.1)


func _new_soldier(at: Vector3, dir: Vector3, tag: String) -> UnitState:
	var pf := demo.sim.state.war.player_faction if demo.sim.state.war else 0
	var sq := _cs.spawn(pf, at, dir, 1, tag)
	var u := demo.sim.state.get_unit(sq.members[0])
	u.position = demo.on_ground(at.x, at.z, 0.0)
	u.anchor_pos = u.position
	var b := _body(u)
	if b:
		b.global_position = u.position + Vector3.UP * 0.1
	return u


# --- r_registry --------------------------------------------------------------------------------------------------------

func _r_registry() -> Dictionary:
	var out := {"weapons": {}, "vehicles": {}}
	for wid in DevArmoury.WEAPONS:
		var def := demo.sim.combat.weapon(wid)
		var role := InfantryRole.by_id(StringName("dev_" + String(wid)))
		var row := {"def": def != null, "role": role != null}
		_expect(def != null, "%s: no WeaponDef" % wid)
		_expect(role != null, "%s: no development role" % wid)
		if def == null or role == null:
			out.weapons[String(wid)] = row
			continue
		var launcher := LAUNCHERS.has(wid)
		row["primary"] = String(role.weapon_id)
		row["secondary"] = String(role.secondary_id)
		var piece: InfantryEquipment = def.held_piece if launcher else null
		for fam in ["NATO", "RU", "CN"]:
			var lo := InfantryLoadout.by_id("%s_%s" % [fam, role.loadout_suffix])
			_expect(lo != null, "%s: no %s loadout" % [wid, fam])
			if lo and not launcher:
				piece = lo.item_in_slot("weapon")
		_expect(piece != null and piece.scene != null, "%s: no weapon piece" % wid)
		if piece and piece.scene:
			var inst: Node3D = piece.scene.instantiate()
			row["muzzle"] = inst.find_child("ATT_Muzzle", true, false) != null
			row["mag"] = inst.find_children("*_Mag_LOD0", "MeshInstance3D", true, false).size() > 0
			row["aim_eye"] = str(piece.aim_eye)
			_expect(row.muzzle, "%s: no ATT_Muzzle" % wid)
			inst.free()
		if launcher:
			_expect(def.held_piece != null and def.role == &"launcher", "%s: launcher without its held piece" % wid)
		out.weapons[String(wid)] = row
	for tid in VehicleDefs.pack_ids():
		var d := VehicleDefs.get_def(tid)
		var ok := d.id == tid and d.articulated and ResourceLoader.exists(d.body_glb) and FileAccess.file_exists(d.body_glb.get_basename() + ".json")
		_expect(ok, "%s: definition / GLB / sidecar missing" % tid)
		out.vehicles[String(tid)] = {"glb": d.body_glb, "passengers": d.passengers, "tracked": d.tracked, "drivable": d.drivable}
	# New Game guards
	var guards := {}
	guards["all_ids"] = str(VehicleDefs.all_ids())
	_expect(VehicleDefs.all_ids() == [VehicleDefs.TRUCK, VehicleDefs.APC], "VehicleDefs.all_ids changed")
	var econ: Array = BaseSim.VEHICLES.keys()
	guards["economy_vehicles"] = str(econ)
	for tid in VehicleDefs.pack_ids():
		_expect(not econ.has(tid), "%s is in the economy's vehicle table" % tid)
	var dir := DirAccess.open(InfantryRole.DIR)
	var listed := Array(dir.get_files()) if dir else []
	guards["dev_roles_listed"] = listed.filter(func(f: String) -> bool: return f.begins_with("dev_")).size()
	_expect(int(guards.dev_roles_listed) == 0, "development roles are in the equipment screen's role folder")
	var ng := ScenarioDef.load_id("new_game")
	guards["new_game_armoury"] = ng != null and ng.rules.has("dev_armoury")
	_expect(not bool(guards.new_game_armoury), "the New Game scenario has the armoury rule")
	var in_dev := []
	for dd: DevelopmentDef in DevelopmentDef.all():
		for wid in DevArmoury.WEAPONS:
			if dd.weapons.has(wid):
				in_dev.append(String(wid))
	guards["weapons_in_development"] = in_dev
	_expect(in_dev.is_empty(), "named weapons in development projects: %s" % [in_dev])
	out["guards"] = guards
	return out


# --- w_weapons ---------------------------------------------------------------------------------------------------------

func _w_weapons() -> Dictionary:
	demo.sim.brain.enabled = false
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var u := _new_soldier(c, dir, "AI1W")
	await _physics(20)
	_raise(u, dir)
	_probes(u)
	await _seconds(1.5)
	# the shared rifle's hold (the faction rifleman, no grip modifier): the reference
	_base = _grip_of(u)
	var out := {"base": {"r_wrist": str(_base.get("r_wrist", Vector3.ZERO)), "eye_off_cm": _base.get("eye_off_cm", -1.0),
		"look_bore_deg": _base.get("look_bore_deg", -1.0)}}
	_expect(float(_base.get("eye_off_cm", 99.0)) < 2.0, "shared rifle: eye %.1f cm off its sight line" % float(_base.get("eye_off_cm", 99.0)))
	var view_yaw := atan2((_right(dir) * 0.75 + dir * 0.66).x, (_right(dir) * 0.75 + dir * 0.66).z)
	for wid in DevArmoury.WEAPONS:
		var txt := _arm.give(wid, u)
		var launcher := LAUNCHERS.has(wid)
		if launcher:
			u.sec_shown_until = demo.sim.state.time + 60.0
		await _physics(4)
		_raise(u, dir)
		_probes(u)
		await _seconds(1.4)
		var ch := _char(u)
		var row := {"armoury": txt, "weapon_id": String(u.weapon_id), "loadout": u.loadout, "sec": String(u.sec_id), "mag": u.mag}
		var g := _grip_of(u)
		_expect(not g.is_empty(), "%s: nothing in the hands" % wid)
		if not g.is_empty() and not _base.is_empty():
			row["r_wrist_err_cm"] = _err_cm(g.r_wrist, _base.r_wrist)
			row["support_err_cm"] = _err_cm(g.l_from_support, _base.l_from_support)
			row["eye_off_cm"] = g.eye_off_cm
			row["look_bore_deg"] = g.look_bore_deg
			row["grip"] = g.grip
			_expect(row.r_wrist_err_cm < 3.0, "%s: firing hand %.1f cm off the grip" % [wid, row.r_wrist_err_cm])
			_expect(row.support_err_cm < 6.0, "%s: support hand %.1f cm off its grip" % [wid, row.support_err_cm])
			_expect(float(row.eye_off_cm) < 2.0, "%s: eye %.1f cm off the sight line" % [wid, row.eye_off_cm])
			_expect(float(row.look_bore_deg) < 3.0, "%s: head looks %.1f deg off the bore" % [wid, row.look_bore_deg])
		if ch and not launcher:
			var mag_meshes := ch.attachments.has("ATT_Magazine") and (ch.attachments.ATT_Magazine as Node3D).find_children("*_Mag_LOD0", "MeshInstance3D", true, false).size() > 0
			row["mag_on_bone"] = mag_meshes
		if launcher:
			row["held"] = ch.secondary_shown() if ch else false
			_expect(bool(row.held), "%s: launcher not in the hands" % wid)
		else:
			_expect(u.weapon_id == wid, "%s: record weapon is %s" % [wid, u.weapon_id])
		_cam(u.position + Vector3.UP * 1.35, 2.3, view_yaw, 6.0)
		await _physics(3)
		_png("w_%s" % wid)
		_cam(u.position + Vector3.UP * 1.5, 1.6, atan2(_right(dir).x, _right(dir).z), 2.0)
		await _physics(3)
		_png("w_%s_side" % wid)
		u.sec_shown_until = -1.0
		out[String(wid)] = row
	return out


# --- f_fps -------------------------------------------------------------------------------------------------------------

func _f_fps() -> Dictionary:
	var sim := demo.sim
	sim.brain.enabled = false
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var u := _new_soldier(c, dir, "AI1F")
	await _physics(20)
	var out := {}
	var ok: bool = demo.game.possess(u.id)
	_expect(ok, "f_fps: could not possess")
	if not ok:
		return out
	await _seconds(1.0)
	var b := _body(u)
	b.rotation.y = atan2(-dir.x, -dir.z)
	b.head.rotation.x = deg_to_rad(-1.0)
	for wid in FPS_SET:
		var launcher := LAUNCHERS.has(wid)
		_arm.give(wid, u)
		await _seconds(0.6)
		if launcher:
			Input.action_press("switch_weapon")
			await _physics(2)
			Input.action_release("switch_weapon")
			await _seconds(0.8)
		var vm := b.viewmodel
		var row := {}
		_expect(vm != null and vm.arms != null, "%s: no first-person arms" % wid)
		if vm == null or vm.arms == null:
			out[String(wid)] = row
			continue
		b.head.rotation.x = deg_to_rad(-1.0)
		await _seconds(0.5)
		_png("f_%s_hip" % wid)
		Input.action_press("aim")
		await _seconds(0.9)
		# the weapon's own sight line on the camera axis: its sight point in camera space is (0, 0, -eye relief)
		var cam := b.camera
		var sp: Vector3 = cam.global_transform.affine_inverse() * (vm._weapon_root.global_transform * Vector3(vm._eye.x, vm._eye.y, 0.0))
		row["sight_in_camera"] = str(sp.snapped(Vector3.ONE * 0.001))
		row["sight_off_axis_mm"] = snappedf(Vector2(sp.x, sp.y).length() * 1000.0, 0.1)
		row["ads_fov"] = snappedf(cam.fov, 0.1)
		_expect(float(row.sight_off_axis_mm) < 6.0, "%s: sight line %.1f mm off the camera axis" % [wid, row.sight_off_axis_mm])
		_png("f_%s_ads" % wid)
		# one shot
		var mag0 := u.mag
		var sec0 := u.sec_ammo
		var launched0 := sim.combat.launched
		Input.action_press("fire")
		await _physics(2)
		Input.action_release("fire")
		await _physics(2)
		_png("f_%s_shot" % wid)
		Input.action_release("aim")
		if launcher:
			row["launched"] = sim.combat.launched - launched0
			row["sec_ammo"] = [sec0, u.sec_ammo]
			_expect(sim.combat.launched > launched0, "%s: the launcher did not fire" % wid)
			Input.action_press("switch_weapon")
			await _physics(2)
			Input.action_release("switch_weapon")
		else:
			row["mag"] = [mag0, u.mag]
			_expect(u.mag < mag0, "%s: no round fired" % wid)
			await _seconds(0.4)
			Input.action_press("reload")
			await _physics(2)
			Input.action_release("reload")
			row["reloading"] = u.is_reloading()
			_expect(u.is_reloading(), "%s: no reload" % wid)
			await _seconds(minf(sim.combat.weapon(wid).reload_time * 0.45, 1.2))
			_png("f_%s_reload" % wid)
			await _seconds(sim.combat.weapon(wid).reload_time)
			row["after_reload"] = u.mag
		await _seconds(0.4)
		out[String(wid)] = row
	return out


# --- p_posture ---------------------------------------------------------------------------------------------------------

func _p_posture() -> Dictionary:
	demo.sim.brain.enabled = false
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var u := _new_soldier(c, dir, "AI1P")
	await _physics(20)
	_raise(u, dir)
	_probes(u)
	await _seconds(1.5)
	if _base.is_empty():
		_base = _grip_of(u)
	var out := {}
	var view_yaw := atan2((_right(dir) * 0.8 + dir * 0.6).x, (_right(dir) * 0.8 + dir * 0.6).z)
	for wid: StringName in [&"fn_mag", &"glock_17", &"rpg7"]:
		_arm.give(wid, u)
		var row := {}
		for p: int in [Posture.CROUCH, Posture.PRONE, Posture.STAND]:
			if wid == &"rpg7":
				u.sec_shown_until = demo.sim.state.time + 60.0
			Posture.request(u, p, demo.sim.state.time)
			await _seconds(2.6)
			_raise(u, dir)
			_probes(u)
			await _seconds(1.0)
			var g := _grip_of(u)
			var name: String = ["stand", "crouch", "prone"][p]
			if not g.is_empty() and not _base.is_empty():
				row[name] = {"posture": u.posture, "eye_off_cm": g.eye_off_cm, "support_err_cm": _err_cm(g.l_from_support, _base.l_from_support),
					"r_wrist_err_cm": _err_cm(g.r_wrist, _base.r_wrist)}
			if p != Posture.STAND:
				_cam(u.position + Vector3.UP * (0.4 if p == Posture.PRONE else 0.9), 2.4, view_yaw, 10.0 if p == Posture.PRONE else 6.0)
				await _physics(3)
				_png("p_%s_%s" % [wid, name])
		u.sec_shown_until = -1.0
		out[String(wid)] = row
	return out


# --- v_switch ----------------------------------------------------------------------------------------------------------

func _v_switch() -> Dictionary:
	demo.sim.brain.enabled = false
	var u := _new_soldier(_site.def, _site.dir, "AI1S")
	await _physics(20)
	_arm.give(&"hk417", u)
	await _physics(5)
	var out := {}
	_expect(demo.game.possess(u.id), "v_switch: could not possess")
	await _seconds(0.8)
	var b := _body(u)
	out["fps_piece"] = String(b.viewmodel._weapon_root.name) if b and b.viewmodel and b.viewmodel._weapon_root else ""
	demo.game.enter_rts()
	await _seconds(0.8)
	out["rts_weapon"] = String(u.weapon_id)
	out["rts_char_piece"] = String(_char(u)._weapon_root_node().name) if _char(u) and _char(u)._weapon_root_node() else ""
	_expect(demo.game.possess(u.id), "v_switch: could not possess again")
	await _seconds(0.8)
	b = _body(u)
	out["fps_piece_again"] = String(b.viewmodel._weapon_root.name) if b and b.viewmodel and b.viewmodel._weapon_root else ""
	_expect(u.weapon_id == &"hk417", "v_switch: weapon lost (%s)" % u.weapon_id)
	_expect(String(out.fps_piece_again).contains("hk417") and String(out.rts_char_piece).contains("hk417"), "v_switch: wrong piece shown %s" % [out])
	demo.game.enter_rts()
	return out


# --- v_vehicles --------------------------------------------------------------------------------------------------------

func _v_vehicles() -> Dictionary:
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var right := _right(dir)
	var yaw := atan2(-right.x, -right.z)
	var ids := {}
	var x := -22.0
	for tid in VehicleDefs.pack_ids():
		var d := VehicleDefs.get_def(tid)
		x += d.length * 0.5 + (2.0 if tid != VehicleDefs.NH90 else 1.0)
		var p := c + right * x + dir * (12.0 if tid != VehicleDefs.NH90 else 18.0)
		var u := _arm.spawn_unit(tid, p, yaw)
		_cs.unit_ids.append(u.id)
		ids[tid] = u.id
		x += d.length * 0.5
	var soldier := _new_soldier(c + right * -24.0 + dir * 8.0, -dir, "AI1V")
	await _seconds(2.5)
	var out := {}
	for tid: StringName in ids:
		var u := demo.sim.state.get_unit(ids[tid])
		var b := demo.sim.body_of(u.id) as VehicleBody
		var row := {"body": b != null}
		_expect(b != null, "%s: no body near the camera" % tid)
		if b == null:
			out[String(tid)] = row
			continue
		var vv := b.visual
		var kinds := {}
		for e: Dictionary in vv.parts:
			kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
		row["parts"] = kinds
		row["seats"] = vv.seats.size()
		row["collision_shapes"] = vv.collision_shapes.size()
		row["lod_meshes"] = vv.lod_count
		_expect(vv.collision_shapes.size() >= 3, "%s: %d collision shapes" % [tid, vv.collision_shapes.size()])
		_expect(vv.seats.size() >= 2, "%s: seats not exposed" % tid)
		var need := {VehicleDefs.LMV: ["wheel", "rws", "door"], VehicleDefs.PATRIA: ["wheel", "rws", "door"],
			VehicleDefs.CV90: ["track", "turret", "gun", "rws", "door"], VehicleDefs.SCANIA: ["wheel", "door", "steering"],
			VehicleDefs.LEOPARD: ["track", "turret", "gun", "rws", "door"], VehicleDefs.NH90: ["rotor", "tail_rotor", "slide", "door"]}
		for k: String in need[tid]:
			_expect(kinds.has(k), "%s: no %s part" % [tid, k])
		# orientation: the front markers ahead (-Z), the back ones behind
		var fwd := {VehicleDefs.LEOPARD: "WEAPON_MUZZLE", VehicleDefs.NH90: "SEAT_PILOT", VehicleDefs.LMV: "WHEEL_1L",
			VehicleDefs.PATRIA: "WHEEL_1L", VehicleDefs.SCANIA: "SEAT_DRIVER", VehicleDefs.CV90: "SEAT_DRIVER"}
		if vv.markers.has(fwd[tid]):
			row["front_marker_z"] = snappedf((vv.markers[fwd[tid]] as Vector3).z, 0.01)
			_expect(float(row.front_marker_z) < 0.0, "%s: front marker behind the centre" % tid)
		out[String(tid)] = row
	_cam(c + right * 2.0 + dir * 12.0 + Vector3.UP * 1.5, 34.0, atan2(-dir.x, -dir.z) + 0.35, 14.0)
	await _physics(4)
	_png("v_lineup")
	_cam(soldier.position + right * 3.0 + Vector3.UP * 1.5, 12.0, atan2(-dir.x, -dir.z) + 0.6, 8.0)
	await _physics(4)
	_png("v_scale_lmv")
	# every moving part driven
	for tid: StringName in ids:
		var b := demo.sim.body_of(ids[tid]) as VehicleBody
		if b:
			b.visual.doors_open = 1.0
			b.visual.turret_yaw = 0.7
			b.visual.gun_pitch = 0.15
			b.visual.rws_yaw = -1.0
			b.visual.rws_pitch = 0.3
			b.visual.rotor_rate = 18.0
	await _seconds(2.2)
	for tid: StringName in ids:
		var b := demo.sim.body_of(ids[tid]) as VehicleBody
		if b == null:
			continue
		var moved := {}
		for e: Dictionary in b.visual.parts:
			if e.kind in ["wheel", "track", "steering"]:
				continue
			var n: Node3D = e.node
			var d := (n.transform.basis.get_rotation_quaternion().angle_to((e.rest as Transform3D).basis.get_rotation_quaternion())) \
				+ n.transform.origin.distance_to((e.rest as Transform3D).origin)
			moved[e.kind] = bool(moved.get(e.kind, true)) and d > 0.05
		out[String(tid)]["articulated"] = moved
		for k: String in moved:
			_expect(moved[k], "%s: %s did not move" % [tid, k])
	for tid: StringName in [VehicleDefs.CV90, VehicleDefs.LEOPARD, VehicleDefs.NH90, VehicleDefs.LMV, VehicleDefs.PATRIA, VehicleDefs.SCANIA]:
		var u := demo.sim.state.get_unit(ids[tid])
		var d := VehicleDefs.get_def(tid)
		_cam(u.position + Vector3.UP * 1.8, maxf(d.length * 1.15, 9.0), atan2(-dir.x, -dir.z) + 0.9, 16.0)
		await _physics(4)
		_png("v_parts_%s" % tid)
	return out


# --- v_drive -----------------------------------------------------------------------------------------------------------

func _v_drive() -> Dictionary:
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var right := _right(dir)
	var out := {}
	var ids := {}
	var lane := -15.0
	for tid: StringName in [VehicleDefs.LMV, VehicleDefs.SCANIA, VehicleDefs.CV90, VehicleDefs.LEOPARD, VehicleDefs.NH90]:
		var u := _arm.spawn_unit(tid, c + right * lane - dir * 10.0, atan2(-dir.x, -dir.z))
		_cs.unit_ids.append(u.id)
		ids[tid] = u.id
		lane += 8.0
	await _seconds(2.0)
	var rest := {}
	for tid: StringName in ids:
		var b := demo.sim.body_of(ids[tid]) as VehicleBody
		var wheel: Array = b.visual.parts.filter(func(e: Dictionary) -> bool: return e.kind in ["wheel", "track"]) if b else []
		rest[tid] = (wheel[0].node as Node3D).transform.basis if not wheel.is_empty() else Basis()
		var u := demo.sim.state.get_unit(ids[tid])
		var res: Dictionary = demo.sim.vehicles.order_drive(u.id, u.position + dir * 50.0)
		out[String(tid)] = {"order": bool(res.ok), "reason": String(res.get("reason", "")), "from": u.position}
	_expect(not bool(out[String(VehicleDefs.NH90)].order), "the NH90 accepted a drive order")
	var cv := demo.sim.state.get_unit(ids[VehicleDefs.CV90])
	var t_end := Time.get_ticks_msec() + 22000
	var shot := false
	while Time.get_ticks_msec() < t_end:
		await _physics(10)
		_cam(cv.position + Vector3.UP * 1.5, 14.0, atan2(right.x, right.z) + 0.5, 10.0)
		if not shot and cv.veh.speed > 3.0:
			await _physics(2)
			_png("v_drive_cv90")
			shot = true
	for tid: StringName in ids:
		var u := demo.sim.state.get_unit(ids[tid])
		var moved := Vector2(u.position.x - out[String(tid)].from.x, u.position.z - out[String(tid)].from.z).length()
		var b := demo.sim.body_of(u.id) as VehicleBody
		var wheel: Array = b.visual.parts.filter(func(e: Dictionary) -> bool: return e.kind in ["wheel", "track"]) if b else []
		var turned := not wheel.is_empty() and not (wheel[0].node as Node3D).transform.basis.is_equal_approx(rest[tid])
		out[String(tid)]["moved_m"] = snappedf(moved, 0.1)
		out[String(tid)]["wheels_turned"] = turned
		out[String(tid)]["status"] = VehicleState.STATUS_NAMES[u.veh.status]
		out[String(tid)].erase("from")
		if tid == VehicleDefs.NH90:
			_expect(moved < 0.5, "the NH90 moved %.1f m" % moved)
		else:
			_expect(moved > 20.0, "%s moved only %.1f m" % [tid, moved])
			_expect(turned, "%s: wheels / road wheels did not turn" % tid)
	return out


# --- v_transport -------------------------------------------------------------------------------------------------------

func _v_transport() -> Dictionary:
	demo.sim.brain.enabled = false
	var c: Vector3 = _site.def
	var dir: Vector3 = _site.dir
	var pf := demo.sim.state.war.player_faction if demo.sim.state.war else 0
	var out := {}
	for tid: StringName in [VehicleDefs.PATRIA, VehicleDefs.NH90]:
		var v := _arm.spawn_unit(tid, c + dir * 14.0, atan2(-dir.x, -dir.z))
		_cs.unit_ids.append(v.id)
		var sq := _cs.spawn(pf, c - dir * 4.0, dir, 4, "AI1T")
		await _seconds(1.5)
		var res: Dictionary = demo.sim.vehicles.transport.order_transport(v.id, sq.id)
		var row := {"order": bool(res.ok), "reason": String(res.get("reason", ""))}
		_expect(bool(res.ok), "%s: transport order refused: %s" % [tid, res.get("reason", "")])
		var b := demo.sim.body_of(v.id) as VehicleBody
		var doors_max := 0.0
		var rotor := 0.0
		var shot := false
		var t_end := Time.get_ticks_msec() + 30000
		while Time.get_ticks_msec() < t_end and v.veh.occupants.size() < sq.members.size():
			await _physics(6)
			if b:
				doors_max = maxf(doors_max, b.visual.doors_amount())
				rotor = maxf(rotor, b.visual._rotor_speed)
				if not shot and b.visual.doors_amount() > 0.9:
					_cam(v.position + Vector3.UP * 1.6, 13.0, atan2(dir.x, dir.z) + 0.5, 12.0)
					await _physics(3)
					_png("v_board_%s" % tid)
					shot = true
		row["aboard"] = v.veh.occupants.size()
		row["doors_max"] = snappedf(doors_max, 0.01)
		_expect(v.veh.occupants.size() == sq.members.size(), "%s: %d of %d aboard" % [tid, v.veh.occupants.size(), sq.members.size()])
		_expect(doors_max > 0.5, "%s: the doors never opened while boarding" % tid)
		if tid == VehicleDefs.NH90:
			row["rotor_idle"] = snappedf(rotor, 0.1)
		demo.sim.vehicles.transport.unload(v.id)
		t_end = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < t_end and not v.veh.occupants.is_empty():
			await _physics(6)
		row["after_unload"] = v.veh.occupants.size()
		_expect(v.veh.occupants.is_empty(), "%s: soldiers still aboard after unloading" % tid)
		for id in sq.members:
			_cs.unit_ids.append(id)
		out[String(tid)] = row
		_cs.reset()
		await _physics(10)
	return out


# --- s_persist ---------------------------------------------------------------------------------------------------------

func _s_persist() -> Dictionary:
	var u := _new_soldier(_site.def, _site.dir, "AI1P")
	await _physics(10)
	_arm.give(&"rpg7", u)
	# the save's own text form (WorldState.save_to: var_to_str)
	var d: Dictionary = str_to_var(var_to_str(u.to_dict()))
	var back := UnitState.from_dict(d)
	var out := {"role": String(back.role), "weapon": String(back.weapon_id), "loadout": back.loadout, "sec": String(back.sec_id),
		"sec_ammo": back.sec_ammo}
	_expect(back.role == u.role and back.weapon_id == u.weapon_id and back.loadout == u.loadout and back.sec_id == u.sec_id,
		"s_persist: soldier changed through the serialiser %s" % [out])
	_expect(InfantryRole.by_id(back.role) != null, "s_persist: the saved role does not load")
	var types := []
	for tid in VehicleDefs.pack_ids():
		var v := demo.sim.state.add_vehicle(tid, 0, _site.def + Vector3(0, 0, 300), 0.0)
		_cs.unit_ids.append(v.id)
		var vb := UnitState.from_dict(str_to_var(var_to_str(v.to_dict())))
		types.append(String(vb.veh.type_id) if vb.veh else "")
		_expect(vb.veh != null and vb.veh.type_id == tid and vb.veh.def().id == tid, "s_persist: %s lost its type" % tid)
	out["vehicles"] = types
	return out
