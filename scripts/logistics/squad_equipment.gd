## GAMEPLAY-04D squad equipment: what a faction's soldiers carry, find and are issued, owned by WarSim (`WarSim.equip`).
##
## One small inventory model, three places a weapon can be:
##   * on a soldier (UnitState weapon / secondary: the record, as before);
##   * in a squad's cargo (SquadState.cargo: spare weapons it picked up, at most cargo_cap);
##   * in the world (WarState.stashes: placed finds, the equipment of caches, what fallen soldiers left), or in the faction's
##     armoury (FactionState.armory: handed in at a base).
## Nothing is created or lost on the way: a weapon moves between these places, is bought (procured) at a base, or is lost
## with a soldier who dies with no one to pick it up.
##
## REARM (order_rearm): the squad walks there with an ordinary move, searches for rearm_s while nobody shoots at it, then takes
## the ammunition its soldiers lack (from the stashes in reach, at its own base from the stores) and spare weapons into its
## cargo - types the faction has not registered first. Nobody swaps weapons by himself: specialists keep their roles.
## Delivery: a squad with cargo inside its own base with an operational supply depot hands it to the armoury; a weapon type the
## faction did not know is registered (FactionState.discovered): it can then be developed / procured (MilitaryDevelopment).
## Equipping (equip): a soldier changes role with the weapons from the squad's cargo (anywhere out of contact), the armoury or
## procurement (at a base); his old weapons go back to the armoury at a base, else into the cargo, else onto the ground.
class_name SquadEquipment
extends RefCounted

## Metres from the REARM point within which stashes are searched and the squad counts as arrived.
const SEARCH_R := 30.0
const REARM_S := 6.0
## Fallen soldiers' equipment within this distance is one stash; at most FALLEN_MAX of them (the oldest go).
const MERGE_R := 15.0
const FALLEN_MAX := 150
## Grenades are restocked at this weight each (kg of the ammunition stock).
const GRENADE_KG := 0.5
## Specialists a squad may have at most (the rest of a squad stays riflemen): role id -> count.
const MAX_PER_SQUAD := {&"machine_gunner": 2, &"heavy_gunner": 1, &"marksman": 2, &"grenadier": 2, &"grenadier_gl": 2, &"at_gunner": 2}

var ws: WarSim
var _t := 0.0
var stats := {"rearms": 0, "delivered": 0, "registered": 0, "equipped": 0, "procured": 0, "fallen_stashes": 0}


func _init(p_ws: WarSim) -> void:
	ws = p_ws


func _war() -> WarState:
	return ws.war


# --- Stashes ---------------------------------------------------------------------------------------------------------

## A stash in the world (scenario finds, caches with equipment). Returns it.
func add_stash(stash_name: String, kind: String, pos: Vector3, items: Dictionary, ammo_kg: float) -> Dictionary:
	var s := {"id": _war().next_stash_id, "name": stash_name, "kind": kind, "pos": pos, "items": items.duplicate(), "ammo": ammo_kg,
		"t": snappedf(ws.sim.state.time, 0.1)}
	_war().next_stash_id += 1
	_war().stashes.append(s)
	return s


func stashes_near(p: Vector3, r: float) -> Array:
	return _war().stashes.filter(func(s: Dictionary) -> bool: return WarSim._flat(s.pos, p) <= r and not _empty(s))


static func _empty(s: Dictionary) -> bool:
	if float(s.get("ammo", 0.0)) > 0.5:
		return false
	for k in s.items:
		if int(s.items[k]) > 0:
			return false
	return true


## A soldier died: his weapons stay where he fell (merged with a stash of the fallen within MERGE_R), with half the
## ammunition he carried.
func on_death(u: UnitState) -> void:
	if u.kind != UnitState.Kind.SOLDIER or not _war().active:
		return
	var items := {}
	var ammo := 0.0
	var def := ws.sim.combat.weapon(u.weapon_id)
	if def:
		items[String(u.weapon_id)] = 1
		ammo += def.procure_ammo * 0.5 * float(u.mag + u.reserve) / maxf(def.magazine_size + def.reserve_start, 1)
	var sdef := ws.sim.combat.weapon(u.sec_id) if u.sec_id != &"" else null
	if sdef and u.sec_ammo > 0:
		items[String(u.sec_id)] = 1
	ammo += u.grenades * GRENADE_KG * 0.5
	if items.is_empty() and ammo < 0.5:
		return
	for s: Dictionary in _war().stashes:
		if s.kind == "fallen" and WarSim._flat(s.pos, u.position) <= MERGE_R:
			for k in items:
				s.items[k] = int(s.items.get(k, 0)) + int(items[k])
			s.ammo = float(s.ammo) + ammo
			return
	add_stash("Fallen soldiers' equipment", "fallen", u.position, items, ammo)
	stats.fallen_stashes += 1
	var fallen := _war().stashes.filter(func(s: Dictionary) -> bool: return s.kind == "fallen")
	if fallen.size() > FALLEN_MAX:
		_war().stashes.erase(fallen[0])


# --- REARM -----------------------------------------------------------------------------------------------------------

## Stashes a faction's squads came within SandboxSetup.CACHE_SPOT_M of become known to it (shown on its map and screen).
func _spot_stashes() -> void:
	var centres := []
	for sq: SquadState in ws.sim.state.all_squads():
		if not sq.members.is_empty():
			centres.append([sq.faction, ws.squad_center(sq)])
	for s: Dictionary in _war().stashes:
		if not s.has("known"):
			s["known"] = []
		for c: Array in centres:
			if not (s.known as Array).has(c[0]) and WarSim._flat(c[1], s.pos) <= SandboxSetup.CACHE_SPOT_M:
				(s.known as Array).append(c[0])
				if s.kind != "fallen":
					ws.log_event(c[0], "cache", "Equipment spotted: %s" % s.name, s.pos)


## Stashes faction f knows of that still hold something.
func known_stashes(f: int) -> Array:
	return _war().stashes.filter(func(s: Dictionary) -> bool: return (s.get("known", []) as Array).has(f) and not _empty(s))


## Spare weapons a squad can carry (one per two soldiers, at least two).
static func cargo_cap(sq: SquadState) -> int:
	return maxi(2, ceili(sq.members.size() / 2.0))


static func cargo_count(sq: SquadState) -> int:
	var n := 0
	for k in sq.cargo:
		n += int(sq.cargo[k])
	return n


## The squads search at `at` (INF: where they stand): far ones walk there first (an ordinary move). {ok, text}.
func order_rearm(squad_ids: Array, at := Vector3.INF) -> Dictionary:
	var names: Array[String] = []
	for sid in squad_ids:
		var sq := ws.sim.state.get_squad(sid)
		if sq == null or sq.members.is_empty():
			continue
		var c := ws.squad_center(sq)
		var p := at if at.is_finite() else c
		if WarSim._flat(c, p) > SEARCH_R * 0.8:
			ws.sim.squads.order_move([sq.id], p)
		sq.rearm_at = p
		sq.rearm_s = 0.0
		names.append(sq.squad_name)
	if names.is_empty():
		return {"ok": false, "text": "Rearm: select a squad first"}
	var what := describe_sources(at if at.is_finite() else ws.squad_center(ws.sim.state.get_squad(squad_ids[0])), ws.sim.state.get_squad(squad_ids[0]).faction)
	return {"ok": true, "text": "%s: rearming %s" % [", ".join(names), what]}


## What a REARM at p would search, in words ("at the Moen checkpoint stash", "from the base stores", "here - nothing found").
func describe_sources(p: Vector3, f: int) -> String:
	var near := stashes_near(p, SEARCH_R)
	if not near.is_empty():
		return "at " + ", ".join(near.map(func(s: Dictionary) -> String: return String(s.name)))
	if _store_base(p, f) >= 0:
		return "from the base stores"
	return "here (no equipment known within %d m)" % roundi(SEARCH_R)


## The faction's base at p with an operational supply store (supply depot or storage), or -1.
func _store_base(p: Vector3, f: int) -> int:
	var bs := ws.sim.logistics.bases
	var bid := bs.base_area_at(p, f)
	if bid < 0:
		return -1
	for s in bs.facilities_of(bid):
		if FacilityDefs.kind_of(s.type_id) == &"supply" and s.is_operational():
			return bid
	return -1


func update(dt: float) -> void:
	_t += dt
	if _t < 1.0:
		return
	var step := _t
	_t = 0.0
	_spot_stashes()
	for sq: SquadState in ws.sim.state.all_squads():
		if sq.members.is_empty():
			continue
		if sq.rearm_at.is_finite():
			_rearm_step(sq, step)
		if not sq.cargo.is_empty():
			var bid := _store_base(ws.squad_center(sq), sq.faction)
			if bid >= 0:
				deliver(sq, bid)


func _rearm_step(sq: SquadState, dt: float) -> void:
	var c := ws.squad_center(sq)
	if WarSim._flat(c, sq.rearm_at) > SEARCH_R:
		# Still on the way; a squad that stopped short (its move ended, blocked) searches where it stands.
		if sq.order == SquadState.Order.NONE or (sq.order == SquadState.Order.MOVE and not ws.sim.squads.marching(sq) and _arrived(sq)):
			sq.rearm_at = c
		return
	var a := ws.sim.tactics.assessment(sq)
	if int(a.get("under_fire", 0)) > 0:
		sq.rearm_s = 0.0
		return
	sq.rearm_s += dt
	if sq.rearm_s < REARM_S:
		return
	var res := rearm(sq, sq.rearm_at)
	sq.rearm_at = Vector3.INF
	sq.rearm_s = 0.0
	ws.log_event(sq.faction, "rearm", res.text, c)


func _arrived(sq: SquadState) -> bool:
	for uid in sq.members:
		var u := ws.sim.state.get_unit(uid)
		if u and u.order == UnitState.Order.MOVE:
			return false
	return true


## The search itself (also called directly by tests): ammunition first, then spare weapons. {ok, text, ammo_kg, taken}.
func rearm(sq: SquadState, at: Vector3) -> Dictionary:
	var f := sq.faction
	var sources := stashes_near(at, SEARCH_R)
	var base := _store_base(at, f)
	var bs := ws.sim.logistics.bases
	var used := 0.0
	# 1. Ammunition the soldiers lack: their weapons, secondary rounds, grenades.
	for uid in sq.members:
		var u := ws.sim.state.get_unit(uid)
		if u == null or not u.alive:
			continue
		var def := ws.sim.combat.weapon(u.weapon_id)
		if def:
			var full := def.magazine_size + def.reserve_start
			var missing := full - (u.mag + u.reserve)
			if missing > 0:
				var need := def.procure_ammo * float(missing) / maxf(full, 1)
				var got := _take_ammo(sources, base, f, need)
				var rounds := int(floor(float(missing) * (got / maxf(need, 0.001))))
				u.reserve += rounds
				used += got
		var role := InfantryRole.by_id(u.role)
		if role:
			var sdef := ws.sim.combat.weapon(u.sec_id) if u.sec_id != &"" else null
			if sdef and u.sec_ammo < role.secondary_rounds and sdef.id == role.secondary_id:
				var miss_s := role.secondary_rounds - u.sec_ammo
				var need_s := sdef.procure_ammo * float(miss_s) / maxf(role.secondary_rounds, 1)
				var got_s := _take_ammo(sources, base, f, need_s)
				u.sec_ammo += int(floor(float(miss_s) * (got_s / maxf(need_s, 0.001))))
				used += got_s
			if u.grenades < role.grenades:
				var got_g := _take_ammo(sources, base, f, (role.grenades - u.grenades) * GRENADE_KG)
				u.grenades += int(floor(got_g / GRENADE_KG))
				used += got_g
	# 2. Spare weapons into the cargo: types the faction has not registered first, then the dearest.
	var taken := {}
	var fs := _war().faction(f)
	var pile := []
	for s: Dictionary in sources:
		for k in s.items:
			for i in int(s.items[k]):
				pile.append([s, String(k)])
	pile.sort_custom(func(x: Array, y: Array) -> bool:
		var nx := fs != null and not fs.discovered.has(x[1])
		var ny := fs != null and not fs.discovered.has(y[1])
		if nx != ny:
			return nx
		return _price(x[1]) > _price(y[1]))
	for e: Array in pile:
		if cargo_count(sq) >= cargo_cap(sq):
			break
		var s: Dictionary = e[0]
		s.items[e[1]] = int(s.items[e[1]]) - 1
		if int(s.items[e[1]]) <= 0:
			s.items.erase(e[1])
		sq.cargo[e[1]] = int(sq.cargo.get(e[1], 0)) + 1
		taken[e[1]] = int(taken.get(e[1], 0)) + 1
	for s: Dictionary in sources:
		if _empty(s) and s.kind == "fallen":
			_war().stashes.erase(s)
	stats.rearms += 1
	if f == _war().player_faction:
		_war().guide["rearmed"] = true  # the introduction's REARM tip
	var parts: Array[String] = []
	if used > 0.05:
		parts.append("ammunition topped up (%d kg)" % roundi(used))
	for k in taken:
		var wd := ws.sim.combat.weapon(StringName(k))
		var new := fs != null and not fs.discovered.has(k)
		parts.append("%d x %s%s" % [taken[k], wd.display_name if wd else k, " (unknown type: deliver it to a base)" if new else ""])
	if parts.is_empty():
		parts.append("nothing usable found")
	return {"ok": true, "text": "%s rearmed: %s" % [sq.squad_name, ", ".join(parts)], "ammo_kg": used, "taken": taken}


func _price(weapon_id: String) -> float:
	var wd := ws.sim.combat.weapon(StringName(weapon_id))
	return wd.procure_cost if wd else 0.0


## Takes up to `need` kg of ammunition: from the stashes, then (at its own base) from the faction's stores. Returns the kg.
func _take_ammo(sources: Array, base: int, f: int, need: float) -> float:
	var got := 0.0
	for s: Dictionary in sources:
		if got >= need - 0.001:
			break
		var q := minf(float(s.ammo), need - got)
		s.ammo = float(s.ammo) - q
		got += q
	if got < need - 0.001 and base >= 0:
		var bs := ws.sim.logistics.bases
		var want := minf(need - got, float(bs.faction_stock(f).ammo))
		if want > 0.01 and not bs.faction_pay(f, {&"ammo": want}, base).is_empty():
			got += want
	return got


# --- Delivery and discovery ------------------------------------------------------------------------------------------

## A squad at its base hands in its cargo: the weapons go to the armoury; an unknown type is registered.
func deliver(sq: SquadState, _base_id: int) -> Dictionary:
	var fs := _war().faction(sq.faction)
	if fs == null or sq.cargo.is_empty():
		return {}
	var new: Array[String] = []
	var n := 0
	for k in sq.cargo:
		fs.armory[k] = int(fs.armory.get(k, 0)) + int(sq.cargo[k])
		n += int(sq.cargo[k])
		if not fs.discovered.has(k):
			fs.discovered.append(k)
			new.append(k)
	sq.cargo.clear()
	stats.delivered += n
	ws.log_event(sq.faction, "deliver", "%s handed in %d weapon%s to the armoury" % [sq.squad_name, n, "" if n == 1 else "s"], ws.squad_center(sq))
	for k in new:
		stats.registered += 1
		var wd := ws.sim.combat.weapon(StringName(k))
		var opens := ""
		for d in DevelopmentDef.all():
			if d.requires_discovery.has(StringName(k)):
				opens = " - %s can now be developed" % d.display_name
		if opens == "" and wd and ws.dev.weapon_lock(sq.faction, StringName(k)) == "":
			opens = " - it can now be procured"
		ws.log_event(sq.faction, "discovery", "Discovery registered: %s%s" % [wd.display_name if wd else k, opens], ws.squad_center(sq))
	return {"delivered": n, "new": new}


# --- Equipping -------------------------------------------------------------------------------------------------------

## Whether the squad stands at one of its bases with an operational supply store (armoury and procurement are there).
func at_base(sq: SquadState) -> int:
	return _store_base(ws.squad_center(sq), sq.faction)


## How a soldier could take a role: {ok, reason, sources: {weapon id: "carried" / "cargo" / "armory" / "procure"}, cost {}}.
func can_equip(sq: SquadState, u: UnitState, role_id: StringName) -> Dictionary:
	var role := InfantryRole.by_id(role_id)
	if role == null:
		return {"ok": false, "reason": "unknown role"}
	if u.role == role_id:
		return {"ok": false, "reason": "current role", "current": true}
	if not u.alive:
		return {"ok": false, "reason": "dead"}
	if int(ws.sim.tactics.assessment(sq).get("under_fire", 0)) > 0:
		return {"ok": false, "reason": "the squad is under fire"}
	if u.vehicle_id >= 0:
		return {"ok": false, "reason": "aboard a vehicle"}
	var cap := int(MAX_PER_SQUAD.get(role_id, 99))
	var have := 0
	for uid in sq.members:
		var m := ws.sim.state.get_unit(uid)
		if m and m.alive and m.role == role_id:
			have += 1
	if have >= cap:
		return {"ok": false, "reason": "a squad has at most %d %s" % [cap, role.display_name.to_lower()]}
	var base := at_base(sq)
	var fs := _war().faction(sq.faction)
	var sources := {}
	var cost := {&"supplies": 0.0, &"ammo": 0.0}
	var cargo_left := sq.cargo.duplicate()
	for wid: StringName in [role.weapon_id, role.secondary_id]:
		if wid == &"":
			continue
		var wd := ws.sim.combat.weapon(wid)
		if wd == null:
			return {"ok": false, "reason": "unknown weapon %s" % wid}
		if (wid == u.weapon_id) or (wid == u.sec_id and u.sec_ammo > 0):
			sources[wid] = "carried"
			continue
		if int(cargo_left.get(String(wid), 0)) > 0:
			cargo_left[String(wid)] = int(cargo_left[String(wid)]) - 1
			sources[wid] = "cargo"
			continue
		if base < 0:
			return {"ok": false, "reason": "%s: none in the squad's cargo - issue it at one of your bases with a Supply Depot" % wd.display_name}
		if fs and int(fs.armory.get(String(wid), 0)) > 0:
			sources[wid] = "armory"
			cost[&"ammo"] += wd.procure_ammo
			continue
		var lock := ws.dev.weapon_lock(sq.faction, wid)
		if lock != "":
			return {"ok": false, "reason": "%s: %s" % [wd.display_name, lock]}
		if wd.procure_facility != &"" and not ws.dev.has_facility(sq.faction, wd.procure_facility):
			return {"ok": false, "reason": "%s: needs an operational %s" % [wd.display_name, MilitaryDevelopment.facility_name(wd.procure_facility)]}
		sources[wid] = "procure"
		cost[&"supplies"] += wd.procure_cost
		cost[&"ammo"] += wd.procure_ammo
	var bs := ws.sim.logistics.bases
	if (cost[&"supplies"] > 0.0 or cost[&"ammo"] > 0.0) and not bs.faction_can_pay(sq.faction, cost):
		var st := bs.faction_stock(sq.faction)
		return {"ok": false, "reason": "needs %d kg supplies and %d kg ammunition (you have %d / %d)" % [roundi(cost[&"supplies"]), roundi(cost[&"ammo"]), roundi(st.supplies), roundi(st.ammo)],
			"sources": sources, "cost": cost}
	return {"ok": true, "reason": "", "sources": sources, "cost": cost, "base": base}


## Re-equips a soldier in a role (see can_equip): pays, moves the weapons, refreshes his look. {ok, reason, text}.
func equip(sq: SquadState, u: UnitState, role_id: StringName) -> Dictionary:
	var c := can_equip(sq, u, role_id)
	if not c.ok:
		return c
	var bs := ws.sim.logistics.bases
	var fs := _war().faction(sq.faction)
	var cost: Dictionary = c.cost
	if cost[&"supplies"] > 0.0 or cost[&"ammo"] > 0.0:
		if bs.faction_pay(sq.faction, {&"supplies": cost[&"supplies"], &"ammo": cost[&"ammo"]}, int(c.get("base", -1))).is_empty():
			return {"ok": false, "reason": "payment failed"}
	var base := int(c.get("base", -1))
	var old_w := u.weapon_id
	var old_s := u.sec_id if u.sec_ammo > 0 else &""
	var role := InfantryRole.by_id(role_id)
	# The new weapons leave their sources.
	var field_load := false
	for wid in c.sources:
		match String(c.sources[wid]):
			"cargo":
				sq.cargo[String(wid)] = int(sq.cargo[String(wid)]) - 1
				if int(sq.cargo[String(wid)]) <= 0:
					sq.cargo.erase(String(wid))
				field_load = true
			"armory":
				fs.armory[String(wid)] = int(fs.armory[String(wid)]) - 1
				if int(fs.armory[String(wid)]) <= 0:
					fs.armory.erase(String(wid))
			"procure":
				stats.procured += 1
	# The old ones go to the armoury at a base, else the cargo, else the ground.
	for wid: StringName in [old_w, old_s]:
		if wid == &"" or wid == role.weapon_id or wid == role.secondary_id:
			continue
		if base >= 0 and fs:
			fs.armory[String(wid)] = int(fs.armory.get(String(wid), 0)) + 1
		elif cargo_count(sq) < cargo_cap(sq):
			sq.cargo[String(wid)] = int(sq.cargo.get(String(wid), 0)) + 1
		else:
			add_stash("Left equipment", "fallen", u.position, {String(wid): 1}, 0.0)
	var keep_reserve := u.reserve if old_w == role.weapon_id else -1
	u.role = &""
	ws.sim.combat._equip_role(u, role_id)
	if keep_reserve >= 0:
		u.reserve = keep_reserve
	elif field_load:
		# A found weapon comes with the rounds found with it: half a load.
		var wd := ws.sim.combat.weapon(u.weapon_id)
		if wd:
			u.reserve = wd.reserve_start / 2
	stats.equipped += 1
	var text := "%s is now %s" % [u.unit_name, role.display_name.to_lower()]
	ws.log_event(sq.faction, "equip", text, u.position)
	return {"ok": true, "reason": "", "text": text}


## The roles a soldier could take and how (the equipment screen's rows): [{role, name, state, reason, cost}] where state is
## "current", "ready" (cargo / armoury / carried), "procure" (bought at the base), "locked" or "unavailable".
func options(sq: SquadState, u: UnitState) -> Array:
	var out := []
	var dir := DirAccess.open(InfantryRole.DIR)
	var ids: Array[StringName] = []
	if dir:
		for fname in dir.get_files():
			fname = fname.trim_suffix(".remap")
			if fname.ends_with(".tres"):
				ids.append(StringName(fname.get_basename()))
	ids.sort()
	for rid in ids:
		var role := InfantryRole.by_id(rid)
		if role == null:
			continue
		var c := can_equip(sq, u, rid)
		var state := "current" if c.get("current", false) else ("unavailable" if not c.ok else "ready")
		if c.ok and (c.sources as Dictionary).values().has("procure"):
			state = "procure"
		if not c.ok and String(c.reason).contains("Locked") or String(c.get("reason", "")).contains("Not discovered"):
			state = "locked"
		out.append({"role": rid, "name": role.display_name, "short": role.short, "state": state, "reason": String(c.get("reason", "")),
			"cost": c.get("cost", {}), "sources": c.get("sources", {})})
	return out
