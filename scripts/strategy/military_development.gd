## GAMEPLAY-04B Military Development: what a faction knows how to build, procure and do, and the projects that extend it.
## Owned by WarSim (`WarSim.dev`); the definitions are DevelopmentDef resources, the state is FactionState.dev (saved):
##   {"done": [development ids], "active": [{"id", "progress" (s), "paid" (faction_pay record), "started", "why"}]}.
##
## One rule set for every faction (player and AI) and every caller - construction (ConstructionController, AiBases),
## equipment (SquadEquipment), squad compositions (CombatSim.apply_composition) and opportunities ask structure_lock /
## weapon_lock / role_lock here and nowhere else. Switched on by the scenario rule "development" (New Game); without it
## everything is unlocked and nothing below changes the game (Development Scenario, old saves).
##
## Separate concepts: knowledge (done, permanent: a lost facility never makes the faction forget), the facility a project
## needs while it runs (requires_facility: the project pauses without it) and what an unlocked item still needs to be used
## (a building is paid and built; a weapon is procured at a base with WeaponDef.procure_facility). A project is paid when
## it starts through BaseSim.faction_pay and refunded in full when cancelled.
class_name MilitaryDevelopment
extends RefCounted

const TICK_S := 1.0
## AI policy: an AI faction considers a new project this often, keeps this much supply beyond its price, and spends at
## most this share of its supplies on one.
const AI_THINK_S := 20.0
const AI_RESERVE := 1500.0
const AI_SHARE := 0.35

var ws: WarSim
var _t := 0.0
var _ai_t := 0.0
## kind ("structure" / "weapon" / "role") -> id -> DevelopmentDef that unlocks it.
var _unlocked_by := {}
var stats := {"started": 0, "completed": 0, "cancelled": 0, "ai_started": 0}


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	for d in DevelopmentDef.all():
		for s in d.structures:
			_index("structure", s, d)
		for w in d.weapons:
			_index("weapon", w, d)
		for r in d.roles:
			_index("role", r, d)


func _index(kind: String, id: StringName, d: DevelopmentDef) -> void:
	if not _unlocked_by.has(kind):
		_unlocked_by[kind] = {}
	_unlocked_by[kind][id] = d


func enabled() -> bool:
	return ws.war != null and ws.war.active and bool(ws.war.rule("development", false))


## The development that unlocks an item (kind "structure" / "weapon" / "role"), or null when nothing gates it.
func unlocked_by(kind: String, id: StringName) -> DevelopmentDef:
	return _unlocked_by.get(kind, {}).get(id)


# --- Faction state ---------------------------------------------------------------------------------------------------

func _state(f_id: int) -> Dictionary:
	var f := ws.war.faction(f_id)
	if f == null:
		return {"done": [], "active": []}
	if not f.dev.has("done"):
		f.dev["done"] = []
	if not f.dev.has("active"):
		f.dev["active"] = []
	return f.dev


## The starting knowledge of a faction: every initial development and the scenario's extra ones (an AI faction that starts
## with a barracks knows how to build one - a scenario setup rule).
func init_faction(f: FactionState, extra: Array = []) -> void:
	var st := _state(f.id)
	for d in DevelopmentDef.all():
		if d.initial and not (st.done as Array).has(String(d.id)):
			(st.done as Array).append(String(d.id))
	for x in extra:
		if DevelopmentDef.by_id(StringName(x)) and not (st.done as Array).has(String(x)):
			(st.done as Array).append(String(x))


func is_done(f_id: int, dev_id: StringName) -> bool:
	if not enabled():
		return true
	return (_state(f_id).done as Array).has(String(dev_id))


func active_of(f_id: int) -> Array:
	return _state(f_id).active


func active_entry(f_id: int, dev_id: StringName) -> Dictionary:
	for e: Dictionary in active_of(f_id):
		if String(e.id) == String(dev_id):
			return e
	return {}


## Projects a faction can run at once (1 + effects "dev_slots").
func slots(f_id: int) -> int:
	return 1 + int(effect(f_id, "dev_slots", 0.0))


## The combined effect of a faction's completed developments: *_mult keys multiply (default 1), others add.
func effect(f_id: int, key: String, fallback := 0.0) -> float:
	if not enabled():
		return 1.0 if key.ends_with("_mult") else fallback
	var mult := key.ends_with("_mult")
	var v := 1.0 if mult else fallback
	for id in _state(f_id).done:
		var d := DevelopmentDef.by_id(StringName(id))
		if d and d.effects.has(key):
			v = v * float(d.effects[key]) if mult else v + float(d.effects[key])
	return v


# --- Requirements ----------------------------------------------------------------------------------------------------

## An operational facility of this kind at one of the faction's bases (finished and not disabled).
func has_facility(f_id: int, kind: StringName) -> bool:
	if kind == &"":
		return true
	var bs := ws.sim.logistics.bases
	for b: Dictionary in bs.bases_of(f_id):
		for s in bs.facilities_of(b.id):
			if FacilityDefs.kind_of(s.type_id) == kind and s.is_operational():
				return true
	return false


const FACILITY_NAMES := {&"hq": "Command Post", &"supply": "Supply Depot", &"barracks": "Barracks", &"ammo": "Ammunition Magazine",
	&"repair": "Workshop (repair bay)", &"vehicle": "Vehicle Depot", &"fuel": "Fuel point"}


static func facility_name(kind: StringName) -> String:
	return FACILITY_NAMES.get(kind, String(kind))


## How far the faction is on an operational milestone.
func milestone_value(f_id: int, kind: StringName) -> int:
	var f := ws.war.faction(f_id)
	if f == null:
		return 0
	match kind:
		&"objectives":
			return ws.war.owned_by(f_id).size()
		&"captured":
			return f.objectives_captured
		&"kills":
			return f.kills
		&"caches":
			var n := 0
			for c: Dictionary in ws.war.caches:
				if int(c.get("taken_by", -1)) == f_id:
					n += 1
			return n
	return 0


static func milestone_text(kind: StringName, n: int) -> String:
	match kind:
		&"objectives":
			return "hold %d objective%s" % [n, "" if n == 1 else "s"]
		&"captured":
			return "capture %d objective%s" % [n, "" if n == 1 else "s"]
		&"kills":
			return "%d enemy soldiers killed" % n
		&"caches":
			return "secure %d supply cache%s" % [n, "" if n == 1 else "s"]
	return String(kind)


## Every requirement of a development and whether it is met: [{text, ok}] (prerequisites, milestone, facility, cost).
func requirements(f_id: int, d: DevelopmentDef) -> Array:
	var out := []
	for r in d.requires:
		var rd := DevelopmentDef.by_id(r)
		out.append({"text": rd.display_name if rd else String(r), "ok": is_done(f_id, r), "kind": "development"})
	if d.milestone != &"":
		var have := milestone_value(f_id, d.milestone)
		var t := milestone_text(d.milestone, d.milestone_count)
		out.append({"text": "%s (%d/%d)" % [t.left(1).to_upper() + t.substr(1), mini(have, d.milestone_count), d.milestone_count],
			"ok": have >= d.milestone_count, "kind": "milestone"})
	if d.requires_facility != &"":
		out.append({"text": "Operational %s" % facility_name(d.requires_facility), "ok": has_facility(f_id, d.requires_facility), "kind": "facility"})
	return out


## State of a development for a faction: {state: "done" / "active" / "available" / "locked" / "future", reason, progress 0..1}.
func status(f_id: int, dev_id: StringName) -> Dictionary:
	var d := DevelopmentDef.by_id(dev_id)
	if d == null:
		return {"state": "locked", "reason": "unknown development", "progress": 0.0}
	if is_done(f_id, dev_id):
		return {"state": "done", "reason": "", "progress": 1.0}
	var e := active_entry(f_id, dev_id)
	if not e.is_empty():
		return {"state": "active", "reason": String(e.get("why", "")), "progress": clampf(float(e.progress) / maxf(d.time_s, 1.0), 0.0, 1.0)}
	if not d.available:
		return {"state": "future", "reason": "not available in this version", "progress": 0.0}
	var c := can_start(f_id, dev_id)
	return {"state": "available" if c.ok else "locked", "reason": c.reason, "progress": 0.0, "blocked_by_cost": c.get("cost", false)}


## {ok, reason, cost (true when only the price is missing)}.
func can_start(f_id: int, dev_id: StringName) -> Dictionary:
	var d := DevelopmentDef.by_id(dev_id)
	if not enabled():
		return {"ok": false, "reason": "Military Development is not used in this scenario"}
	if d == null:
		return {"ok": false, "reason": "unknown development"}
	if is_done(f_id, dev_id):
		return {"ok": false, "reason": "already developed"}
	if not active_entry(f_id, dev_id).is_empty():
		return {"ok": false, "reason": "in development"}
	if not d.available:
		return {"ok": false, "reason": "a future capability: not available in this version"}
	for r in requirements(f_id, d):
		if not r.ok:
			match r.kind:
				"development":
					return {"ok": false, "reason": "needs %s first" % r.text}
				"milestone":
					return {"ok": false, "reason": "needs: %s" % r.text.to_lower()}
				_:
					return {"ok": false, "reason": "needs an %s" % r.text.to_lower()}
	if active_of(f_id).size() >= slots(f_id):
		return {"ok": false, "reason": "a project is already running (%d at a time)" % slots(f_id)}
	var bs := ws.sim.logistics.bases
	if not d.cost.is_empty() and not bs.faction_can_pay(f_id, _cost(d)):
		var st := bs.faction_stock(f_id)
		return {"ok": false, "cost": true, "reason": "needs %s (you have %d kg supplies, %d kg ammunition)" % [bs.cost_text(_cost(d)), roundi(st.supplies), roundi(st.ammo)]}
	return {"ok": true, "reason": ""}


static func _cost(d: DevelopmentDef) -> Dictionary:
	var c := {}
	for k in d.cost:
		c[StringName(k)] = float(d.cost[k])
	return c


# --- Actions ---------------------------------------------------------------------------------------------------------

## Starts a project: pays its price through the faction's economy and adds it to the active list. {ok, reason}.
func start(f_id: int, dev_id: StringName) -> Dictionary:
	var c := can_start(f_id, dev_id)
	if not c.ok:
		return c
	var d := DevelopmentDef.by_id(dev_id)
	var paid := {}
	if not d.cost.is_empty():
		paid = ws.sim.logistics.bases.faction_pay(f_id, _cost(d))
		if paid.is_empty():
			return {"ok": false, "reason": "payment failed"}
	(_state(f_id).active as Array).append({"id": String(dev_id), "progress": 0.0, "paid": paid, "started": snappedf(ws.sim.state.time, 0.1), "why": ""})
	stats.started += 1
	ws.log_event(f_id, "dev_start", "Development started: %s (%s)" % [d.display_name, _time_text(d.time_s)])
	return {"ok": true, "reason": ""}


## Cancels a running project; its price comes back where it was paid from.
func cancel(f_id: int, dev_id: StringName) -> bool:
	var st := _state(f_id)
	for i in (st.active as Array).size():
		var e: Dictionary = st.active[i]
		if String(e.id) == String(dev_id):
			if not (e.get("paid", {}) as Dictionary).is_empty():
				ws.sim.logistics.bases.faction_refund(f_id, e.paid)
			(st.active as Array).remove_at(i)
			stats.cancelled += 1
			var d := DevelopmentDef.by_id(dev_id)
			ws.log_event(f_id, "dev_cancel", "Development cancelled: %s (refunded)" % (d.display_name if d else String(dev_id)))
			return true
	return false


static func _time_text(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


func update(dt: float) -> void:
	if not enabled():
		return
	_t += dt
	if _t < TICK_S:
		return
	var step := _t
	_t = 0.0
	for f: FactionState in ws.war.factions.values():
		var st := _state(f.id)
		var finished := []
		for e: Dictionary in st.active:
			var d := DevelopmentDef.by_id(StringName(e.id))
			if d == null:
				finished.append(e)  # a definition that no longer exists: refunded below
				continue
			if d.requires_facility != &"" and not has_facility(f.id, d.requires_facility):
				e["why"] = "paused: no operational %s" % facility_name(d.requires_facility)
				continue
			e["why"] = ""
			e["progress"] = float(e.progress) + step
			if float(e.progress) >= d.time_s:
				finished.append(e)
		for e: Dictionary in finished:
			(st.active as Array).erase(e)
			var d := DevelopmentDef.by_id(StringName(e.id))
			if d == null:
				if not (e.get("paid", {}) as Dictionary).is_empty():
					ws.sim.logistics.bases.faction_refund(f.id, e.paid)
				ws.log_event(f.id, "dev_cancel", "Development %s no longer exists: refunded" % e.id)
				continue
			(st.done as Array).append(String(d.id))
			stats.completed += 1
			ws.log_event(f.id, "dev_done", "Development complete: %s - %s" % [d.display_name, unlock_text(d)])
	_ai_t += step
	if _ai_t >= AI_THINK_S:
		_ai_t = 0.0
		for f: FactionState in ws.war.factions.values():
			if not f.player:
				_ai_policy(f)


## What a development makes possible, in a few words ("Barracks, Barracks module").
func unlock_text(d: DevelopmentDef) -> String:
	var parts: Array[String] = []
	for s in d.structures:
		var sd := StructureCatalog.get_def(s)
		parts.append(FacilityDefs.display_name(s) if FacilityDefs.has(s) else (sd.display_name if sd else String(s)))
	for w in d.weapons:
		var wd := ws.sim.combat.weapon(w)
		parts.append(wd.display_name if wd else String(w))
	if parts.is_empty() and d.effects.has("intel_delay_mult"):
		parts.append("faster reports")
	if d.effects.has("dev_slots"):
		parts.append("two projects at once")
	return ", ".join(parts) if not parts.is_empty() else d.summary


## AI factions: a simple resource-aware policy under the player's rules - when a slot is free, the cheapest startable project
## of the profile's preferred branch (infantry first for an aggressive profile, base first otherwise) that leaves AI_RESERVE
## supplies and costs at most AI_SHARE of them.
func _ai_policy(f: FactionState) -> void:
	if active_of(f.id).size() >= slots(f.id) or ws.sim.logistics.bases.bases_of(f.id).is_empty():
		return
	var supplies := float(ws.sim.logistics.bases.faction_stock(f.id).supplies)
	var order: Array = [&"infantry", &"base", &"operations"] if String(f.profile_id) == "aggressive" else [&"base", &"infantry", &"operations"]
	var best: DevelopmentDef = null
	var best_sc := INF
	for d in DevelopmentDef.all():
		if not can_start(f.id, d.id).ok:
			continue
		var price := float(d.cost.get("supplies", 0.0))
		if supplies - price < AI_RESERVE or price > supplies * AI_SHARE:
			continue
		var sc := order.find(d.branch) * 1000.0 + price
		if sc < best_sc:
			best_sc = sc
			best = d
	if best and start(f.id, best.id).ok:
		stats.ai_started += 1


# --- Locks: one answer for every caller ---------------------------------------------------------------------------------

## "" when the faction may build this structure type, else why not ("needs Barracks & Personnel").
func structure_lock(f_id: int, type_id: StringName) -> String:
	if not enabled():
		return ""
	var d := unlocked_by("structure", type_id)
	if d == null or is_done(f_id, d.id):
		return ""
	return "Locked: develop %s" % d.display_name


## "" when the faction knows this weapon, else why not.
func weapon_lock(f_id: int, weapon_id: StringName) -> String:
	if not enabled():
		return ""
	var d := unlocked_by("weapon", weapon_id)
	if d == null or is_done(f_id, d.id):
		return ""
	return "Locked: develop %s" % d.display_name


## "" when the faction may equip soldiers in this role (its development done), else why not.
func role_lock(f_id: int, role_id: StringName) -> String:
	if not enabled():
		return ""
	var d := unlocked_by("role", role_id)
	if d == null or is_done(f_id, d.id):
		return ""
	return "Locked: develop %s" % d.display_name


func summary() -> Dictionary:
	var per := {}
	for f: FactionState in ws.war.factions.values():
		per[f.faction_name] = {"done": _state(f.id).done.duplicate(), "active": (_state(f.id).active as Array).map(func(e: Dictionary) -> String: return "%s %.0f s" % [e.id, float(e.progress)])}
	return {"enabled": enabled(), "stats": stats.duplicate(), "factions": per}
