## Supplies in motion (LOGISTICS-01), owned by WorldSim: depot inventories, vehicle jobs
## (load, unload, refuel, deliver between depots), resupplying soldiers, and the optional
## automation built on the same orders.
##
## One inventory model: depots (StructureState.inventory) and vehicles (VehicleState.cargo) are
## Inventory objects and `Inventory.transfer` is the only way supplies change hands (fuel into
## a tank and ammunition into a soldier's reserve take from an Inventory in one step as well).
## Nothing here moves a vehicle: a job asks VehicleSim to drive to the depot's dock, waits for
## the arrival and does its timed work there, in both camera tiers alike.
##
## A job lives in VehicleState.job: {kind, src, dst, item, qty, stage, until, repeat, cycles}.
class_name LogisticsSim
extends RefCounted

## Supplies handled per second at a dock and the fixed time of every handling (sim seconds).
const LOAD_RATE := 250.0
const WORK_BASE_S := 4.0
## A soldier takes ammunition from a depot within this distance, or from a truck within RESUPPLY_VEHICLE_M.
const RESUPPLY_DEPOT_M := 26.0
const RESUPPLY_VEHICLE_M := 14.0
const RESUPPLY_TICK_S := 0.5

var sim: WorldSim
var vsim: VehicleSim
## Bases, recruiting, vehicle acquisition and the optional automation.
var bases: BaseSim
var stats := {"jobs_started": 0, "jobs_done": 0, "jobs_failed": 0, "moved": {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}, "resupplied_soldiers": 0}
var _timer := 0.0
## structure id -> true when its dock slots are counted (cache cleared every tick of jobs).
var _slot_cache := {}


func _init(p_sim: WorldSim, p_vsim: VehicleSim) -> void:
	sim = p_sim
	vsim = p_vsim
	bases = BaseSim.new(self)


## Called by WorldSim once the construction state exists: starter stock and inventories for
## every store that is placed.
func bind() -> void:
	var cs := sim.state.construction
	cs.structure_added.connect(_on_structure_added)
	for s in cs.all():
		_on_structure_added(s)
	bases.bind()


func _on_structure_added(s: StructureState) -> void:
	if not FacilityDefs.is_store(s.type_id):
		return
	if s.inventory == null:
		s.inventory = FacilityDefs.make_inventory(s.type_id)
		var kind := FacilityDefs.kind_of(s.type_id)
		# The scenario's initial stockpile: the first supply depot of the player's faction.
		var war := sim.state.war
		var lg := sim.state.logistics
		# GAMEPLAY-01B: not in New Game (rule start_stock_gift): there the player's stock is what he carried and found.
		if kind == &"supply" and war.active and s.faction == war.player_faction and not lg.starter_given.get(s.faction, false) and war.rule("start_stock_gift", true):
			lg.starter_given[s.faction] = true
			for item in FacilityDefs.START_STOCK:
				s.inventory.add(item, FacilityDefs.START_STOCK[item])
			_event(s.faction, "%s: the first supply depot receives the starting stockpile" % FacilityDefs.display_name(s.type_id))


# --- Lookups ----------------------------------------------------------------------------------

func structure(id: int) -> StructureState:
	return sim.state.construction.get_structure(id)


## Inventory of a source id string ("s<id>" structure, "v<id>" vehicle cargo) or null.
func inventory_of(key: String) -> Inventory:
	if key.begins_with("s"):
		var s := structure(int(key.substr(1)))
		return s.inventory if s else null
	if key.begins_with("v"):
		var u := sim.state.get_unit(int(key.substr(1)))
		return u.veh.cargo if u and u.veh else null
	return null


func position_of(key: String) -> Vector3:
	if key.begins_with("s"):
		var s := structure(int(key.substr(1)))
		return s.position if s else Vector3.INF
	var u := sim.state.get_unit(int(key.substr(1)))
	return u.position if u else Vector3.INF


## Structures with an inventory (depots), optionally of one faction / kind, by id.
func stores(faction := -1, kind := &"") -> Array[StructureState]:
	var out: Array[StructureState] = []
	for s in sim.state.construction.all():
		if s.inventory == null:
			continue
		if faction >= 0 and s.faction != faction:
			continue
		if kind != &"" and FacilityDefs.kind_of(s.type_id) != kind:
			continue
		out.append(s)
	return out


func nearest_store(pos: Vector3, faction: int, item := &"", kind := &"") -> StructureState:
	var best: StructureState
	var best_d := INF
	for s in stores(faction, kind):
		if item != &"" and not s.inventory.accepts(item):
			continue
		var d := Vector2(s.position.x - pos.x, s.position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = s
	return best


func store_name(s: StructureState) -> String:
	return s.label if s.label != "" else "%s #%d" % [FacilityDefs.display_name(s.type_id), s.id]


## Where vehicles dock at a store; slots spread the vehicles queueing for the same store.
func dock_world(s: StructureState, vid: int) -> Vector3:
	var slot := 0
	var u := sim.state.get_unit(vid)
	if u and u.veh and not u.veh.job.is_empty():
		slot = int(u.veh.job.get("slot", 0))
	var p := FacilityDefs.dock_point(s, slot)
	p.y = vsim.ground_at(p)
	return p


## The lowest dock slot of a store that no other vehicle's job uses.
func _free_slot(s: StructureState, vid: int) -> int:
	var used := {}
	for id in vsim.ids:
		if id == vid:
			continue
		var o: UnitState = sim.state.units.get(id)
		if o and not o.veh.job.is_empty() and (int(o.veh.job.get("src", -1)) == s.id or int(o.veh.job.get("dst", -1)) == s.id):
			used[int(o.veh.job.get("slot", 0))] = true
	var k := 0
	while used.has(k):
		k += 1
	return k


## Where a vehicle goes when its job is done, out of the way of the next vehicle at the dock.
func parking_world(s: StructureState, slot: int) -> Vector3:
	var p := FacilityDefs.dock_point(s, slot)
	var b := Basis(Vector3.UP, s.yaw)
	# The first spot of the yard in front of the building that is clear of every structure (a vehicle's footprint) and of
	# vehicles: 16 m beyond the dock, else further out and to the sides (AI-WAR-LOGISTICS-01: the old fixed spot could lie
	# inside the next building, and a vehicle sent there could not even be ordered).
	for out_m: float in [16.0, 24.0, 32.0, 42.0]:
		for side: float in [0.0, 7.0, -7.0, 14.0, -14.0]:
			var q := p + b * Vector3(side, 0.0, -out_m)
			q.y = vsim.ground_at(q)
			if vsim.spot_valid(q) and (sim.structures == null or not sim.structures.blocks_point(Vector2(q.x, q.z), 3.6)):
				return q
	var fallback := p + b * Vector3(0, 0, -16.0)
	fallback.y = vsim.ground_at(fallback)
	return fallback


# --- Vehicle jobs -----------------------------------------------------------------------------

## Load `qty` of `item` from depot `src` into the vehicle, then drive to depot `dst` and unload
## (dst < 0: stay loaded). repeat: do it again and again (an automated supply route).
func order_delivery(vid: int, src: int, dst: int, item: StringName, qty: float, repeat := false, auto := false) -> Dictionary:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null or not u.alive:
		return {"ok": false, "reason": "No such vehicle"}
	var s := structure(src)
	if s == null or s.inventory == null:
		return {"ok": false, "reason": "The source is not a depot"}
	if dst >= 0:
		var d := structure(dst)
		if d == null or d.inventory == null:
			return {"ok": false, "reason": "The destination is not a depot"}
		if not d.inventory.accepts(item):
			return {"ok": false, "reason": "%s does not store %s" % [store_name(d), Inventory.NAMES[item]]}
	if s.inventory.get_qty(item) <= 0.0:
		return {"ok": false, "reason": "%s has no %s" % [store_name(s), Inventory.NAMES[item]]}
	if u.veh.cargo.room_for(item) <= 0.0:
		return {"ok": false, "reason": "Cargo full (%d/%d)" % [roundi(u.veh.cargo.total()), roundi(u.veh.cargo.capacity)]}
	return _start_job(u, {"kind": "delivery", "src": src, "dst": dst, "item": String(item), "qty": qty, "stage": "to_src", "until": 0.0, "repeat": repeat, "cycles": 0, "moved": 0.0}, auto)


func order_load(vid: int, src: int, item: StringName, qty: float) -> Dictionary:
	var r := order_delivery(vid, src, -1, item, qty)
	if r.ok:
		var u := sim.state.get_unit(vid)
		u.veh.job["kind"] = "load"
	return r


## Unload the vehicle's cargo (everything, or one item) at depot `dst`.
func order_unload(vid: int, dst: int, item := &"") -> Dictionary:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null or not u.alive:
		return {"ok": false, "reason": "No such vehicle"}
	var d := structure(dst)
	if d == null or d.inventory == null:
		return {"ok": false, "reason": "The destination is not a depot"}
	if u.veh.cargo.is_empty():
		return {"ok": false, "reason": "The vehicle carries nothing"}
	return _start_job(u, {"kind": "unload", "src": -1, "dst": dst, "item": String(item), "qty": 0.0, "stage": "to_dst", "until": 0.0, "repeat": false, "cycles": 0, "moved": 0.0})


func order_refuel(vid: int, depot: int, auto := false) -> Dictionary:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null or not u.alive:
		return {"ok": false, "reason": "No such vehicle"}
	var d := structure(depot)
	if d == null or d.inventory == null or not d.inventory.accepts(Inventory.FUEL):
		return {"ok": false, "reason": "That building has no fuel"}
	if d.inventory.get_qty(Inventory.FUEL) <= 0.0:
		return {"ok": false, "reason": "%s has no fuel" % store_name(d)}
	if u.veh.fuel >= u.veh.def().fuel_capacity - 0.5:
		return {"ok": false, "reason": "The tank is full"}
	return _start_job(u, {"kind": "refuel", "src": depot, "dst": -1, "item": "fuel", "qty": 0.0, "stage": "to_src", "until": 0.0, "repeat": false, "cycles": 0, "moved": 0.0}, auto)


## Repairs a damaged vehicle at a vehicle depot or repair bay (supplies from the base).
func order_repair(vid: int, depot: int) -> Dictionary:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null or not u.alive:
		return {"ok": false, "reason": "No such vehicle"}
	var d := structure(depot)
	if d == null or not [&"vehicle", &"repair"].has(FacilityDefs.kind_of(d.type_id)):
		return {"ok": false, "reason": "That building cannot repair vehicles"}
	if u.health >= u.max_health - 0.5:
		return {"ok": false, "reason": "The vehicle is undamaged"}
	return _start_job(u, {"kind": "repair", "src": depot, "dst": -1, "item": "", "qty": 0.0, "stage": "to_src", "until": 0.0, "repeat": false, "cycles": 0, "moved": 0.0})


func _start_job(u: UnitState, job: Dictionary, auto := false) -> Dictionary:
	var v := u.veh
	if not auto:
		bases.on_manual_order(u.id)
	if v.phase != VehicleState.Phase.NONE:
		return {"ok": false, "reason": "The vehicle is busy with its passengers"}
	var target := structure(int(job.src) if int(job.get("src", -1)) >= 0 else int(job.dst))
	job["slot"] = _free_slot(target, u.id) if target else 0
	job["retries"] = 0
	vsim.convoy.leave(u.id)
	v.job = job
	stats.jobs_started += 1
	var res := _drive_to_stage(u, v)
	if not res.ok:
		_fail(u, res.reason)
		return {"ok": false, "reason": res.reason}
	_event(u.faction, "%s: %s" % [u.unit_name, describe_job(u)])
	return {"ok": true, "reason": ""}


## Plans the drive that belongs to the job's current stage ("to_src" / "to_dst").
func _drive_to_stage(u: UnitState, v: VehicleState) -> Dictionary:
	var j := v.job
	var id: int = j.src if j.stage == "to_src" else j.dst
	var s := structure(id)
	if s == null:
		return {"ok": false, "reason": "The depot no longer exists"}
	var dock := dock_world(s, u.id)
	if Vector2(u.position.x - dock.x, u.position.z - dock.z).length() <= FacilityDefs.DOCK_REACH_M:
		u.order = UnitState.Order.NONE
		_begin_work(u, v)
		return {"ok": true, "reason": ""}
	return vsim.request_drive(u.id, dock, true)


func _begin_work(u: UnitState, v: VehicleState) -> void:
	var j := v.job
	var qty := _planned_qty(u, v)
	if j.kind == "repair":
		j["stage"] = "repairing"
	else:
		j["stage"] = "loading" if (j.stage == "to_src" and j.kind != "refuel") else ("unloading" if j.stage == "to_dst" else "refueling")
	j["until"] = sim.state.time + WORK_BASE_S + qty / LOAD_RATE
	j["began"] = sim.state.time


func _planned_qty(u: UnitState, v: VehicleState) -> float:
	var j := v.job
	var item := StringName(j.item)
	match j.kind:
		"repair":
			return (u.max_health - u.health) * 4.0
		"refuel":
			return v.def().fuel_capacity - v.fuel
		"unload":
			return v.cargo.get_qty(item) if item != &"" else v.cargo.total()
		_:
			if j.stage == "to_dst" or j.stage == "unloading":
				return v.cargo.get_qty(item)
			return minf(float(j.qty), v.cargo.room_for(item))


func cancel_job(vid: int, reason := "cancelled") -> void:
	var u := sim.state.get_unit(vid)
	if u == null or u.veh == null or u.veh.job.is_empty():
		return
	# Cargo stays aboard (nothing is destroyed or duplicated); the vehicle stops.
	_event(u.faction, "%s: %s %s" % [u.unit_name, describe_job(u), reason])
	u.veh.job = {}
	vsim.halt(vid)


func _fail(u: UnitState, reason: String) -> void:
	_event(u.faction, "%s: %s - %s" % [u.unit_name, describe_job(u), reason])
	u.veh.job = {}
	u.veh.reason = reason
	stats.jobs_failed += 1


func _done(u: UnitState, v: VehicleState, msg: String) -> void:
	_event(u.faction, "%s: %s" % [u.unit_name, msg])
	var j := v.job
	stats.jobs_done += 1
	if j.get("repeat", false) and j.kind == "delivery":
		j["cycles"] = int(j.cycles) + 1
		j["stage"] = "to_src"
		j["slot"] = _free_slot(structure(j.src), u.id) if structure(j.src) else 0
		var res := _drive_to_stage(u, v)
		if not res.ok:
			_fail(u, res.reason)
		return
	# Clear the dock for the next vehicle.
	var s := structure(int(j.get("src", -1)) if int(j.get("src", -1)) >= 0 and j.stage != "unloading" else int(j.get("dst", -1)))
	v.job = {}
	if s:
		var park := parking_world(s, int(j.get("slot", 0)))
		vsim.request_drive(u.id, park, true)


## One tick of a vehicle's job (called from VehicleSim while a job is set).
func update_vehicle(u: UnitState, v: VehicleState) -> void:
	var j := v.job
	if j.is_empty():
		return
	if not u.alive or v.status == VehicleState.Status.DISABLED:
		v.job = {}
		return
	var now := sim.state.time
	match j.stage:
		"to_src", "to_dst":
			if u.player_controlled:
				return
			if u.order == UnitState.Order.NONE and absf(v.speed) < 0.6:
				var s := structure(j.src if j.stage == "to_src" else j.dst)
				if s == null:
					_fail(u, "The depot no longer exists")
					return
				var dock := dock_world(s, u.id)
				if Vector2(u.position.x - dock.x, u.position.z - dock.z).length() <= FacilityDefs.DOCK_REACH_M:
					_begin_work(u, v)
				elif v.status == VehicleState.Status.BLOCKED or v.status == VehicleState.Status.NO_FUEL:
					_fail(u, "Cannot reach the depot" + (": " + v.reason if v.reason != "" else ""))
				else:
					# Stopped short of the dock (another vehicle is being served): wait a little, try again.
					var now2 := sim.state.time
					if float(j.get("retry_at", 0.0)) <= 0.0:
						j["retry_at"] = now2 + 5.0
					elif now2 >= float(j.retry_at):
						j["retry_at"] = 0.0
						j["retries"] = int(j.get("retries", 0)) + 1
						if int(j.retries) > 12:
							_fail(u, "The dock stayed occupied")
						else:
							var rs := vsim.request_drive(u.id, dock, true)
							if not rs.ok:
								_fail(u, "Cannot reach the depot: " + rs.reason)
		"loading", "unloading", "refueling", "repairing":
			if absf(v.speed) > 0.8:
				# Driven away by the player: the job ends, cargo stays aboard.
				cancel_job(u.id, "interrupted")
				return
			v.status = VehicleState.Status.WAITING
			v.reason = "%s %d %%" % [_stage_text(j), roundi(clampf((now - float(j.began)) / maxf(float(j.until) - float(j.began), 0.1), 0.0, 1.0) * 100.0)]
			if now >= float(j.until):
				v.reason = ""
				v.status = VehicleState.Status.PARKED
				_finish_work(u, v)


func _stage_text(j: Dictionary) -> String:
	var item: String = Inventory.NAMES.get(StringName(j.item), "cargo") if j.item != "" else "cargo"
	match j.stage:
		"loading":
			return "Loading %s" % item
		"unloading":
			return "Unloading %s" % item
		"repairing":
			return "Repairing"
	return "Refuelling"


func _finish_work(u: UnitState, v: VehicleState) -> void:
	var j := v.job
	var item := StringName(j.item)
	match j.stage:
		"repairing":
			var d := structure(j.src)
			if d == null:
				_fail(u, "The depot no longer exists")
				return
			var missing := u.max_health - u.health
			var stock: float = bases.base_stock(d.base_id).supplies
			var hp := minf(missing, stock / BaseSim.REPAIR_SUPPLIES_PER_HP)
			if hp <= 0.0:
				_fail(u, "No supplies at the base for repairs")
				return
			bases.pay(d.base_id, {&"supplies": hp * BaseSim.REPAIR_SUPPLIES_PER_HP}, d)
			u.health += hp
			_done(u, v, "repaired %d points at %s" % [roundi(hp), store_name(d)])
		"refueling":
			var d := structure(j.src)
			if d == null or d.inventory == null:
				_fail(u, "The depot no longer exists")
				return
			var want := v.def().fuel_capacity - v.fuel
			var q := d.inventory.take(Inventory.FUEL, want)
			v.fuel += q
			stats.moved.fuel += q
			_done(u, v, "refuelled %d l at %s" % [roundi(q), store_name(d)])
		"loading":
			var d := structure(j.src)
			if d == null or d.inventory == null:
				_fail(u, "The depot no longer exists")
				return
			var q := Inventory.transfer(d.inventory, v.cargo, item, float(j.qty))
			stats.moved[String(item)] += q
			j["moved"] = q
			if q <= 0.0:
				_fail(u, "Nothing loaded: %s" % ("cargo full" if v.cargo.room_for(item) <= 0.0 else "%s has no %s" % [store_name(d), Inventory.NAMES[item]]))
				return
			var short := ""
			if q < float(j.qty) - 0.5:
				short = " (only %d of %d available or fitting)" % [roundi(q), roundi(j.qty)]
			if j.kind == "load" or int(j.dst) < 0:
				_done(u, v, "loaded %d %s %s%s" % [roundi(q), Inventory.UNITS[item], Inventory.NAMES[item], short])
				return
			_event(u.faction, "%s: loaded %d %s %s%s, driving to %s" % [u.unit_name, roundi(q), Inventory.UNITS[item], Inventory.NAMES[item], short, store_name(structure(j.dst)) if structure(j.dst) else "?"])
			j["stage"] = "to_dst"
			var res := _drive_to_stage(u, v)
			if not res.ok:
				# The cargo stays aboard; the player is told why the delivery stopped.
				_fail(u, "Cannot deliver: " + res.reason)
		"unloading":
			var d := structure(j.dst)
			if d == null or d.inventory == null:
				_fail(u, "The depot no longer exists")
				return
			var moved := 0.0
			var left := 0.0
			var items: Array = [item] if item != &"" else Inventory.ITEMS
			for it: StringName in items:
				var q := Inventory.transfer(v.cargo, d.inventory, it, v.cargo.get_qty(it))
				moved += q
				stats.moved[String(it)] += q
				left += v.cargo.get_qty(it)
			j["moved"] = float(j.get("moved", 0.0)) + moved
			if left > 0.5:
				_fail(u, "Unloaded %d, %d left aboard: %s cannot take more" % [roundi(moved), roundi(left), store_name(d)])
				return
			_done(u, v, "unloaded %d at %s" % [roundi(moved), store_name(d)])


func describe_job(u: UnitState) -> String:
	var j := u.veh.job
	if j.is_empty():
		return ""
	var item: String = Inventory.NAMES.get(StringName(j.item), "cargo") if j.item != "" else "cargo"
	var src := structure(j.src) if int(j.get("src", -1)) >= 0 else null
	var dst := structure(j.dst) if int(j.get("dst", -1)) >= 0 else null
	match j.kind:
		"delivery":
			return "delivering %s%s %s to %s" % ["%d %s " % [roundi(j.qty), Inventory.UNITS[StringName(j.item)]], item, "from %s" % store_name(src) if src else "", store_name(dst) if dst else "?"]
		"load":
			return "loading %d %s %s from %s" % [roundi(j.qty), Inventory.UNITS[StringName(j.item)], item, store_name(src) if src else "?"]
		"unload":
			return "unloading at %s" % (store_name(dst) if dst else "?")
		"refuel":
			return "refuelling at %s" % (store_name(src) if src else "?")
		"repair":
			return "being repaired at %s" % (store_name(src) if src else "?")
	return ""


# --- Resupplying soldiers ---------------------------------------------------------------------

## The squads' soldiers walk to a supply source (a depot, magazine or a truck with ammunition
## aboard) and refill their spare rounds from it when they get there.
func order_resupply(squad_ids: Array, key: String) -> Dictionary:
	var inv := inventory_of(key)
	if inv == null:
		return {"ok": false, "reason": "That is not a supply source"}
	if inv.get_qty(Inventory.AMMO) <= 0.0:
		return {"ok": false, "reason": "No ammunition there"}
	var pos := position_of(key)
	var n := 0
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq == null:
			continue
		for id in sq.members:
			var u := sim.state.get_unit(id)
			if u and u.alive and u.vehicle_id < 0:
				u.resupply_src = key
				n += 1
		var near := Vector3(pos.x, pos.y, pos.z)
		if key.begins_with("s"):
			var s := structure(int(key.substr(1)))
			var dock := dock_world(s, -1) if s else pos
			near = dock + Vector3(0, 0, 0)
		sim.squads.order_move([sid], near)
	return {"ok": n > 0, "reason": "" if n > 0 else "Nobody to resupply", "soldiers": n}


## Spare rounds a soldier is missing, in rounds.
func rounds_needed(u: UnitState) -> int:
	var def := sim.combat.weapon(u.weapon_id)
	if def == null:
		return 0
	return maxi(def.reserve_start - u.reserve, 0)


func update(dt: float) -> void:
	bases.update(dt)
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = RESUPPLY_TICK_S
	for u: UnitState in sim.state.units.values():
		if u.resupply_src == "" or not u.alive:
			continue
		_resupply_step(u)


func _resupply_step(u: UnitState) -> void:
	var key := u.resupply_src
	var inv := inventory_of(key)
	if inv == null:
		u.resupply_src = ""
		return
	var pos := position_of(key)
	var reach := RESUPPLY_DEPOT_M if key.begins_with("s") else RESUPPLY_VEHICLE_M
	if Vector2(u.position.x - pos.x, u.position.z - pos.z).length() > reach:
		return
	var need := rounds_needed(u)
	if need > 0:
		var kg := inv.take(Inventory.AMMO, float(need) / Inventory.AMMO_ROUNDS_PER_KG)
		u.reserve += roundi(kg * Inventory.AMMO_ROUNDS_PER_KG)
		stats.moved.ammo += kg
		stats.resupplied_soldiers += 1
		if rounds_needed(u) > 0:
			_event(u.faction, "%s: the source ran out of ammunition" % u.unit_name)
	u.resupply_src = ""


func _event(faction: int, text: String) -> void:
	if sim.war:
		sim.war.log_event(faction, "logistics", text)
