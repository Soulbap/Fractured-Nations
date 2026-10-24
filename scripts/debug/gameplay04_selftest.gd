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
const CHECKS: Array[String] = ["b_lock", "b_start", "b_pause", "b_persist", "b_complete", "b_future", "b_ui", "b_ai", "b_dev_off"]
const ONLY_NAMED: Array[String] = ["b_dev_off"]


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
