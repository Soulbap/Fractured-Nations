## The economy of the AI factions (AI-WAR-LOGISTICS-01), owned by WarSim.
##
## Nothing here makes supplies, soldiers or vehicles out of nothing:
##   * the faction's stores are the Inventory objects of its bases (BaseSim.base_stock); a recruit, a vehicle or
##     a repair is paid from them through BaseSim.recruit / acquire_vehicle / pay, exactly as the player pays;
##   * the only sources are the explicit ones: the starting stockpile of the first supply depot
##     (FacilityDefs.START_STOCK x FactionProfile.start_stock_mult, placed by AiBases) and the income below,
##     which is delivered into a store of the faction's main base with Inventory.add and written to
##     FactionState.ledger (so it is visible in the inspector and can be audited);
##   * personnel is `FactionState.reserves`, finite, with the same explicit inflow (ledger.manpower).
## Income is a rate per owned objective value (FactionProfile.income_*): a faction that loses ground earns less,
## a faction without a base (or with full depots) earns nothing. Spending is a compact utility choice every
## ECON_S seconds: recruit, buy a truck / an APC, refuel, repair; every candidate is kept with its utility,
## what was chosen and why not the others (FactionState.econ_actions), the "reasons for logistical decisions".
class_name WarEconomy
extends RefCounted

const INCOME_S := 10.0
const ECON_S := 15.0

var ws: WarSim
var sim: WorldSim
var bases: BaseSim
var usec := 0
var usec_max := 0
var ticks := 0
var stats := {"income_ticks": 0, "recruits": 0, "trucks": 0, "apcs": 0, "refuels": 0, "repairs": 0, "refused": 0}
var _t_income := 0.0
var _mp_acc := {}
## objective id -> time before which no new building is ordered there (after a failed search / a field-defence order).
var _build_cool := {}


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	sim = p_ws.sim


func _bases() -> BaseSim:
	return sim.logistics.bases


func update(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_t_income += dt
	if _t_income >= INCOME_S:
		var minutes := _t_income / 60.0
		_t_income = 0.0
		for f: FactionState in ws.war.factions.values():
			if not f.player:
				income(f, minutes)
	var now := sim.state.time
	for f: FactionState in ws.war.factions.values():
		if not f.player and now >= f.econ_next_at:
			f.econ_next_at = now + ECON_S
			decide(f)
	var d := Time.get_ticks_usec() - t0
	usec += d
	usec_max = maxi(usec_max, d)
	ticks += 1


# --- Income: the explicit source ------------------------------------------------------------------------------------

## What owned ground is worth per minute: the sum of the owned objectives' values.
func owned_value(f: FactionState) -> int:
	var v := 0
	for o: ObjectiveState in ws.war.owned_by(f.id):
		v += o.value
	return v


## One income tick: supplies, ammunition and fuel into the faction's main base, personnel into the reserves. A
## store that is full takes less (the rest is not produced). Returns {item: quantity delivered}.
func income(f: FactionState, minutes: float) -> Dictionary:
	var p := ws.profile(f)
	var v := float(owned_value(f))
	var out := {}
	var bl := _bases().bases_of(f.id)
	if v > 0.0 and not bl.is_empty():
		var rate := {&"supplies": p.income_supplies, &"ammo": p.income_ammo, &"fuel": p.income_fuel}
		for item: StringName in rate:
			var qty: float = rate[item] * v * minutes
			var got := _deposit(f, bl, item, qty)
			if got > 0.0:
				out[String(item)] = got
				f.ledger["in"][String(item)] = float(f.ledger["in"][String(item)]) + got
	if v > 0.0:
		_mp_acc[f.id] = float(_mp_acc.get(f.id, 0.0)) + p.income_manpower * v * minutes
		var whole := int(_mp_acc[f.id])
		if whole > 0:
			_mp_acc[f.id] -= whole
			f.reserves += whole
			f.ledger["manpower"] = int(f.ledger["manpower"]) + whole
			out["manpower"] = whole
	stats.income_ticks += 1
	return out


## Into the supply stores of the main base first (HQ base), then any other base of the faction.
func _deposit(f: FactionState, bl: Array, item: StringName, qty: float) -> float:
	var order := bl.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (_bases().base_kind(a.id) == "Main base") and not (_bases().base_kind(b.id) == "Main base"))
	var left := qty
	for b: Dictionary in order:
		var stores := _bases().base_stores(b.id)
		stores.sort_custom(func(x: StructureState, y: StructureState) -> bool:
			return _store_rank(x, item) < _store_rank(y, item))
		for s in stores:
			if left <= 0.001:
				break
			left -= s.inventory.add(item, left)
		if left <= 0.001:
			break
	return qty - left


static func _store_rank(s: StructureState, item: StringName) -> int:
	var k := FacilityDefs.kind_of(s.type_id)
	if item == &"ammo":
		return 0 if k == &"ammo" else (1 if k == &"supply" else 2)
	if item == &"fuel":
		return 0 if k == &"fuel" else (1 if k == &"supply" else 2)
	return 0 if k == &"supply" else (1 if k == &"storage" else 2)


# --- Decisions -----------------------------------------------------------------------------------------------------

## The faction's own stock (all bases), vehicles by type and the squads / soldiers it has.
func situation(f: FactionState) -> Dictionary:
	var stock := {"ammo": 0.0, "fuel": 0.0, "supplies": 0.0}
	var bl := _bases().bases_of(f.id)
	for b: Dictionary in bl:
		var st := _bases().base_stock(b.id)
		for k in stock:
			stock[k] += st[k]
	var trucks := 0
	var apcs := 0
	var idle_trucks := 0
	for id in sim.vehicles.ids:
		var u: UnitState = sim.state.units.get(id)
		if u == null or u.faction != f.id or not u.alive:
			continue
		if u.veh.type_id == VehicleDefs.APC:
			apcs += 1
		else:
			trucks += 1
			if u.veh.assign_kind == "" and not u.player_controlled:
				idle_trucks += 1
	var squads := ws.squads_of(f.id)
	var soldiers := 0
	for sq: SquadState in squads:
		soldiers += sq.members.size()
	return {"bases": bl.size(), "stock": stock, "trucks": trucks, "apcs": apcs, "idle_trucks": idle_trucks, "squads": squads.size(), "soldiers": soldiers}


## The shortages in words (inspector): below the faction's floors for ammunition and fuel, no personnel, no transport.
func shortages(f: FactionState) -> Array[String]:
	var p := ws.profile(f)
	var s := situation(f)
	var out: Array[String] = []
	if s.bases == 0:
		out.append("no base")
		return out
	if s.stock.ammo < p.keep_ammo_kg:
		out.append("ammunition %d kg (floor %d)" % [roundi(s.stock.ammo), roundi(p.keep_ammo_kg)])
	if s.stock.fuel < p.keep_fuel_l:
		out.append("fuel %d l (floor %d)" % [roundi(s.stock.fuel), roundi(p.keep_fuel_l)])
	if s.stock.supplies < BaseSim.RECRUIT_COST[&"supplies"]:
		out.append("supplies %d kg (a squad needs %d)" % [roundi(s.stock.supplies), roundi(BaseSim.RECRUIT_COST[&"supplies"])])
	if f.reserves < BaseSim.SQUAD_SIZE:
		out.append("personnel %d (a squad needs %d)" % [f.reserves, BaseSim.SQUAD_SIZE])
	if s.trucks + s.apcs == 0:
		out.append("no transport vehicle")
	return out


## One economic decision of an AI faction: candidates with a utility each, the best ones carried out while the
## stock lasts (at most two per decision, the base's queues are the real limit).
func decide(f: FactionState) -> void:
	var p := ws.profile(f)
	var s := situation(f)
	var actions: Array = []
	var notes: Array[String] = []
	if s.bases == 0:
		f.econ_note = "no base: nothing can be recruited, bought or repaired"
		f.econ_actions = []
		return
	var shortage := shortages(f)
	# Recruit: replace losses and keep the squads at their number; ammunition floor matters less than bodies.
	if s.squads < p.max_squads_econ:
		var gap := 1.0 - float(s.squads) / float(maxi(p.max_squads_econ, 1))
		actions.append({"kind": "recruit", "utility": 1.0 + 3.0 * gap + (1.5 if s.squads < 4 else 0.0), "note": "%d of %d squads, %d soldiers, %d personnel in reserve" % [s.squads, p.max_squads_econ, s.soldiers, f.reserves]})
	if s.trucks < p.want_trucks:
		actions.append({"kind": "truck", "utility": 2.6 if s.trucks == 0 else 1.2, "note": "%d of %d trucks" % [s.trucks, p.want_trucks]})
	if s.apcs < p.want_apcs and s.trucks >= 1:
		actions.append({"kind": "apc", "utility": 1.0, "note": "%d of %d APCs" % [s.apcs, p.want_apcs]})
	_collect_builds(f, p, s, actions)
	for id in sim.vehicles.ids:
		var u: UnitState = sim.state.units.get(id)
		if u == null or u.faction != f.id or not u.alive or u.player_controlled or u.veh.assign_kind != "" or not u.veh.job.is_empty():
			continue
		if u.order != UnitState.Order.NONE or u.veh.phase != VehicleState.Phase.NONE or u.veh.convoy_id >= 0:
			continue
		if u.veh.fuel < u.veh.def().fuel_capacity * 0.4:
			actions.append({"kind": "refuel", "vehicle": id, "utility": 2.2, "note": "%s has %d of %d l" % [u.unit_name, roundi(u.veh.fuel), roundi(u.veh.def().fuel_capacity)]})
		elif u.health < u.max_health * 0.6:
			actions.append({"kind": "repair", "vehicle": id, "utility": 1.6, "note": "%s at %d%%" % [u.unit_name, roundi(u.health / u.max_health * 100.0)]})
	actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.utility > b.utility)
	var done := 0
	for a: Dictionary in actions:
		if done >= 2:
			a["status"] = "not now (two actions per decision)"
			continue
		var res := _execute(f, p, s, a)
		a["status"] = "chosen" if res.ok else "refused: " + res.reason
		if res.ok:
			done += 1
			notes.append(a.kind)
		else:
			stats.refused += 1
	f.econ_actions = actions.map(func(a: Dictionary) -> Dictionary:
		return {"kind": a.kind, "utility": snappedf(a.utility, 0.01), "status": a.status, "note": a.get("note", "")}).slice(0, 8)
	var short_txt := ", ".join(shortage) if not shortage.is_empty() else "no shortage"
	f.econ_note = "%s | %s" % [", ".join(notes) if not notes.is_empty() else "no purchase", short_txt]


## Limited base development (AiBases.request, paid from the main base): a forward supply store at the held objective
## nearest the enemy when it is far from every base, a second barracks when the first one is the bottleneck, and
## sandbag positions at a threatened, garrisoned objective. Never two orders for the same place (pending orders count).
func _collect_builds(f: FactionState, p: FactionProfile, s: Dictionary, actions: Array) -> void:
	var bs := _bases()
	var main_bid := bs.main_base(f.id)
	if main_bid < 0 or sim.structures == null:
		return
	var supplies: float = s.stock.supplies
	var now := sim.state.time
	# 1. Forward depot.
	if supplies >= AiBases.BUILD_COST[&"supply_storage"] + 900.0 and ws.bases.pending_of(f.id, &"supply_storage").is_empty():
		var best: ObjectiveState = null
		var best_front := INF
		for o: ObjectiveState in ws.war.owned_by(f.id):
			if o.is_hq() or ws.threatened.get(o.id, false) or float(_build_cool.get(o.id, 0.0)) > now:
				continue
			var far := true
			for b: Dictionary in bs.bases_of(f.id):
				if WarSim._flat(b.anchor, o.position) < 2200.0:
					far = false
			if not far or not ws.bases.pending_of(f.id, &"", o.position, 500.0).is_empty():
				continue
			var front := INF
			for t: ObjectiveState in ws.war.all_objectives():
				if t.owner != f.id:
					front = minf(front, WarSim._flat(o.position, t.position))
			if front < best_front:
				best_front = front
				best = o
		if best != null:
			actions.append({"kind": "build_forward", "utility": 1.1 + 0.25 * best.value, "objective": best.id, "note": "%s is %d m from the nearest base and %d m from the enemy" % [best.obj_name, 2200, roundi(best_front)]})
	# 2. Second barracks.
	var barracks := 0
	for st in bs.facilities_of(main_bid):
		if FacilityDefs.kind_of(st.type_id) == &"barracks":
			barracks += 1
	if barracks < 2 and supplies >= AiBases.BUILD_COST[&"barracks_block"] + 2500.0 and s.squads >= 5 and ws.bases.pending_of(f.id, &"barracks_block").is_empty():
		actions.append({"kind": "build_barracks", "utility": 0.8, "note": "one barracks, %d squads, %d kg of supplies" % [s.squads, roundi(supplies)]})
	# 3. Field defences at a threatened garrisoned objective.
	if supplies >= AiBases.BUILD_COST[&"sandbag_fighting_position"] + 1500.0:
		for o: ObjectiveState in ws.war.owned_by(f.id):
			if not ws.threatened.get(o.id, false) or ws._garrison_count(f.id, o.id) < 1 or float(_build_cool.get(o.id, 0.0)) > now:
				continue
			if ws.bases.pending_of(f.id, &"sandbag_fighting_position", o.position, o.radius).size() + _built_near(f.id, &"sandbag_fighting_position", o.position, o.radius) >= 3:
				continue
			actions.append({"kind": "build_defence", "utility": 0.9 + 0.2 * o.value, "objective": o.id, "note": "%s is threatened and has a garrison" % o.obj_name})
			break


func _built_near(faction: int, type_id: StringName, p: Vector3, r: float) -> int:
	var n := 0
	for st: StructureState in sim.state.construction.all():
		if st.type_id == type_id and st.faction == faction and Vector2(st.position.x - p.x, st.position.z - p.z).length() <= r:
			n += 1
	return n


func _execute(f: FactionState, p: FactionProfile, s: Dictionary, a: Dictionary) -> Dictionary:
	var bs := _bases()
	match a.kind:
		"build_forward":
			var o := ws.war.objective(a.objective)
			var res := ws.bases.request(f, &"supply_storage", o.position, "forward supply store at %s" % o.obj_name, true)
			if res.ok:
				stats["builds"] = int(stats.get("builds", 0)) + 1
			else:
				_build_cool[o.id] = sim.state.time + 300.0
			return res
		"build_barracks":
			var b: Dictionary = bs.bases_of(f.id)[0]
			var mb := bs.main_base(f.id)
			var anchor: Vector3 = sim.state.construction.bases[mb].anchor if mb >= 0 else b.anchor
			var res := ws.bases.request(f, &"barracks_block", anchor, "second barracks at the main base")
			if res.ok:
				stats["builds"] = int(stats.get("builds", 0)) + 1
			return res
		"build_defence":
			var o := ws.war.objective(a.objective)
			_build_cool[o.id] = sim.state.time + 45.0
			# Between the objective's centre and the believed threat, at the edge of the garrison's ring.
			var at := o.position
			var best := 0.0
			for c: ContactState in ws.intel.contacts_near(f.id, o.position, o.radius + 500.0):
				if c.conf * float(maxi(c.strength, 1)) > best:
					best = c.conf * float(maxi(c.strength, 1))
					var dir := Vector3(c.pos.x - o.position.x, 0.0, c.pos.z - o.position.z).normalized()
					at = o.position + dir * o.radius * 0.5
			var res := ws.bases.request(f, &"sandbag_fighting_position", at, "field defences at %s" % o.obj_name)
			if res.ok:
				stats["builds"] = int(stats.get("builds", 0)) + 1
			return res
		"recruit":
			# A barracks with room in its queue, at the base with the most supplies.
			var best: StructureState = null
			var best_sup := -1.0
			for b: Dictionary in bs.bases_of(f.id):
				var sup: float = bs.base_stock(b.id).supplies
				for st in bs.facilities_of(b.id):
					if FacilityDefs.kind_of(st.type_id) == &"barracks" and st.facility.get("queue", []).size() < BaseSim.RECRUIT_QUEUE_MAX and sup > best_sup:
						best = st
						best_sup = sup
			if best == null:
				return {"ok": false, "reason": "no barracks with room in its queue"}
			# Ammunition floor: only below half the target force may recruiting dig into it.
			var stock: Dictionary = s.stock
			if stock.ammo - BaseSim.RECRUIT_COST[&"ammo"] < p.keep_ammo_kg * 0.5 and s.squads >= 4:
				return {"ok": false, "reason": "ammunition would fall below the floor (%d kg)" % roundi(p.keep_ammo_kg * 0.5)}
			var r := bs.recruit(best.id)
			if r.ok:
				stats.recruits += 1
			return r
		"truck", "apc":
			var type_id := VehicleDefs.TRUCK if a.kind == "truck" else VehicleDefs.APC
			var stock: Dictionary = s.stock
			var cost: Dictionary = BaseSim.VEHICLES[type_id].cost
			if stock.fuel - cost[&"fuel"] < p.keep_fuel_l * 0.4 and s.trucks >= 1:
				return {"ok": false, "reason": "fuel would fall below the floor"}
			var res := {"ok": false, "reason": "no vehicle depot"}
			for b: Dictionary in bs.bases_of(f.id):
				for st in bs.facilities_of(b.id):
					if FacilityDefs.kind_of(st.type_id) == &"vehicle":
						res = bs.acquire_vehicle(st.id, type_id)
						if res.ok:
							stats["trucks" if a.kind == "truck" else "apcs"] += 1
							return res
			return res
		"refuel":
			var u := sim.state.get_unit(a.vehicle)
			var depot := sim.logistics.nearest_store(u.position, f.id, Inventory.FUEL)
			if depot == null:
				return {"ok": false, "reason": "no fuel store"}
			var res := sim.logistics.order_refuel(u.id, depot.id, true)
			if res.ok:
				stats.refuels += 1
			return res
		"repair":
			var u := sim.state.get_unit(a.vehicle)
			var best: StructureState = null
			var best_d := INF
			for b: Dictionary in bs.bases_of(f.id):
				for st in bs.facilities_of(b.id):
					if [&"vehicle", &"repair"].has(FacilityDefs.kind_of(st.type_id)):
						var d := Vector2(st.position.x - u.position.x, st.position.z - u.position.z).length()
						if d < best_d:
							best_d = d
							best = st
			if best == null:
				return {"ok": false, "reason": "no repair facility"}
			var res := sim.logistics.order_repair(u.id, best.id)
			if res.ok:
				stats.repairs += 1
			return res
	return {"ok": false, "reason": "unknown"}


## For the inspector: the faction's economy in lines (real records: stocks, ledger, the last decision).
func explain(f: FactionState) -> Array[String]:
	var out: Array[String] = []
	var s := situation(f)
	var p := ws.profile(f)
	out.append("Economy: %d bases | ammunition %d kg, fuel %d l, supplies %d kg | personnel %d | %d trucks (%d free), %d APCs | %d squads, %d soldiers" % [
		s.bases, roundi(s.stock.ammo), roundi(s.stock.fuel), roundi(s.stock.supplies), f.reserves, s.trucks, s.idle_trucks, s.apcs, s.squads, s.soldiers])
	out.append("  income per minute from %d owned value: supplies %d, ammunition %d, fuel %d, personnel %.1f" % [owned_value(f), roundi(p.income_supplies * owned_value(f)), roundi(p.income_ammo * owned_value(f)),
		roundi(p.income_fuel * owned_value(f)), p.income_manpower * owned_value(f)])
	var li: Dictionary = f.ledger["in"]
	out.append("  ledger: received %d supplies, %d ammunition, %d fuel, %d personnel; recruited %d squads; bought %d vehicles" % [roundi(li.supplies), roundi(li.ammo), roundi(li.fuel), int(f.ledger.manpower), int(f.ledger.squads_recruited), int(f.ledger.vehicles_bought)])
	var lw: Dictionary = f.ledger["lost_with_bases"]
	if float(lw.ammo) + float(lw.fuel) + float(lw.supplies) > 0.5:
		out.append("  lost with captured bases: %d supplies, %d ammunition, %d fuel" % [roundi(lw.supplies), roundi(lw.ammo), roundi(lw.fuel)])
	for b: Dictionary in _bases().bases_of(f.id):
		var q := []
		for st in _bases().facilities_of(b.id):
			for e: Dictionary in st.facility.get("queue", []):
				q.append("%s (%d s)" % [e.get("what", "queued"), maxi(0, roundi(float(e.done) - sim.state.time))])
		out.append("  %s" % _bases().describe(b.id) + ("; queue: " + ", ".join(q) if not q.is_empty() else ""))
	if f.econ_note != "":
		out.append("  decision: " + f.econ_note)
	for a: Dictionary in f.econ_actions:
		out.append("    %s: utility %.2f - %s%s" % [a.kind, a.utility, a.status, (" (" + a.note + ")") if a.note != "" else ""])
	return out


func summary() -> Dictionary:
	return {"stats": stats.duplicate(), "us_avg": snappedf(float(usec) / maxi(ticks, 1), 0.1), "us_max": usec_max}
