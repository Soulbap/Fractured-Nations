## Supplies for the AI factions' operations and garrisons (AI-WAR-LOGISTICS-01), owned by WarSim.
##
## Everything moves through the systems that already exist: ammunition leaves a depot with
## LogisticsSim.order_load (Inventory.transfer into a truck's cargo), the truck drives with VehicleSim.order_drive, soldiers
## take their rounds from the truck or a depot with LogisticsSim.order_resupply (the one place ammunition becomes
## soldier rounds), the truck's leftovers go back with order_unload. No supply counter exists outside those inventories.
##
## Sinks and losses (the only places supplies leave the books): rounds a soldier takes (kg -> `UnitState.reserve`, shot
## away in combat), fuel burnt by vehicles, recruit / vehicle / building costs paid by BaseSim.pay (they become soldiers,
## vehicles and structures), and the cargo of a destroyed truck, which stays in the wreck's VehicleState.cargo.
##
## Three jobs:
##  * readiness before an offensive (assess_attack): full / delay for resupply / reduced / cancel, with the numbers;
##  * recovery of squads (update_recovery): a squad low on ammunition or men goes to a friendly depot, takes real stock
##    (and receives replacement soldiers from a barracks via BaseSim), then returns to where it was needed;
##  * supply missions (update_missions): a truck brings ammunition to squads that are too far from a depot, to a point
##    behind them, never into the fire.
class_name WarLogistics
extends RefCounted

## Squads walk to a depot when it is this close (m); beyond it a truck brings the ammunition.
const WALK_M := 1800.0
## A truck mission carries at most this much ammunition (kg), at least MIN_LOAD_KG is worth a trip.
const LOAD_KG := 600.0
const MIN_LOAD_KG := 120.0
const SERVE_TIMEOUT_S := 150.0
const LOAD_TIMEOUT_S := 120.0
const DRIVE_TIMEOUT_S := 900.0
## The delivery point is pulled back from the squads at least this far from believed enemies (m).
const SAFE_M := 220.0
const CHECK_S := 6.0
const MAX_MISSIONS_PER_FACTION := 2

var ws: WarSim
var sim: WorldSim
var lsim: LogisticsSim
var stats := {"assessed": 0, "go": 0, "delay": 0, "reduced": 0, "cancel": 0, "recoveries": 0, "recovered": 0, "missions": 0, "delivered": 0, "failed": 0, "kg_delivered": 0.0, "kg_returned": 0.0}
var usec := 0
var usec_max := 0
var updates := 0
var _t := 0.0
## objective id -> how many times an attack on it was delayed for resupply (runtime).
var _delays := {}
## forward store id -> time before which no restock is tried again (after a failed attempt).
var _restock_cool := {}
## demand group key (operation / garrison) -> time before which no supply mission is requested for it again.
var _demand_cool := {}


func _init(p_ws: WarSim) -> void:
	ws = p_ws
	sim = p_ws.sim
	lsim = sim.logistics


# --- Readiness ------------------------------------------------------------------------------------------------------------

## The ammunition state of a squad: share of a full load (rifle magazine + spare rounds) and the spare rounds missing.
func squad_ammo(sq: SquadState) -> Dictionary:
	var a := sim.tactics.assessment(sq)
	if a.is_empty():
		a = sim.tactics._assess_squad(sq)
	var missing := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and u.alive:
			missing += lsim.rounds_needed(u)
	return {"frac": float(a.get("ammo", 1.0)), "missing_rounds": missing, "kg": float(missing) / Inventory.AMMO_ROUNDS_PER_KG}


## The nearest friendly store with ammunition in it ({store, kg}), or {} when none has any.
func ammo_source(f: int, pos: Vector3, min_kg := 1.0) -> Dictionary:
	var best: StructureState = null
	var best_d := INF
	for s in lsim.stores(f):
		if not s.inventory.accepts(Inventory.AMMO) or s.inventory.get_qty(Inventory.AMMO) < min_kg:
			continue
		var d := WarSim._flat(s.position, pos)
		if d < best_d:
			best_d = d
			best = s
	return {} if best == null else {"store": best, "kg": best.inventory.get_qty(Inventory.AMMO), "d": best_d}


## Decides whether the faction launches an offensive with `squad_ids` now. Returns {verdict, why, squads (the ones
## that go), resupply (the ones sent to a depot), notes}. The verdict is "go", "delay" (the squads are sent to resupply
## and the attack is decided again at the next decision), "reduced" (goes with the fit squads) or "cancel".
func assess_attack(f: FactionState, squad_ids: Array, obj: ObjectiveState) -> Dictionary:
	stats.assessed += 1
	var p := ws.profile(f)
	var notes: Array[String] = []
	var fit: Array = []
	var low: Array = []
	var need_kg := 0.0
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq == null:
			continue
		var am := squad_ammo(sq)
		if am.frac < p.resupply_below:
			low.append(sid)
			need_kg += am.kg
		else:
			fit.append(sid)
	var out := {"verdict": "go", "why": "", "squads": squad_ids.duplicate(), "resupply": [], "notes": notes, "need_kg": snappedf(need_kg, 0.1)}
	if low.is_empty():
		notes.append("ammunition fine in all %d squads" % squad_ids.size())
		out.why = "fully supplied"
		stats.go += 1
		return out
	var center := ws._centroid_of(low)
	var src := ammo_source(f.id, center, 1.0)
	var have_kg: float = src.kg if not src.is_empty() else 0.0
	var near_ok := not src.is_empty() and float(src.d) <= WALK_M * 2.0
	var delays: int = _delays.get(obj.id, 0)
	if near_ok and have_kg >= need_kg * 0.8 and delays < 4:
		_delays[obj.id] = delays + 1
		for sid in low:
			send_to_depot(sim.state.get_squad(sid), "attack on %s: ammunition below %d%%" % [obj.obj_name, roundi(p.resupply_below * 100.0)])
		out.verdict = "delay"
		out.resupply = low
		out.squads = fit
		out.why = "%d squad(s) low on ammunition (%.0f kg missing): resupplying at %s (%.0f kg there), attack decided again at the next decision" % [low.size(), need_kg, lsim.store_name(src.store), have_kg]
		stats.delay += 1
		return out
	_delays.erase(obj.id)
	var fit_soldiers := 0
	for sid in fit:
		fit_soldiers += ws.strength(sim.state.get_squad(sid))
	var want := p.min_attack_soldiers
	if not fit.is_empty() and fit_soldiers >= want:
		out.verdict = "reduced"
		out.squads = fit
		out.why = "%d squad(s) stay behind: %.0f kg of ammunition missing, %s" % [low.size(), need_kg, "the depot has %.0f kg" % have_kg if not src.is_empty() else "no depot has any"]
		for sid in low:
			send_to_depot(sim.state.get_squad(sid), "left out of the attack on %s" % obj.obj_name)
		stats.reduced += 1
		return out
	out.verdict = "cancel"
	out.squads = []
	out.why = "only %d fit soldiers (%d needed): %.0f kg of ammunition missing and %s" % [fit_soldiers, want, need_kg, "the depot has %.0f kg" % have_kg if not src.is_empty() else "no depot has any"]
	stats.cancel += 1
	return out


## Numbers the strategic scorer reads for an attack on `o` from the faction's front: how long the march takes (on
## foot / by vehicle if seats are free), and the ammunition the force would need against what the depots hold.
func attack_inputs(f: FactionState, o: ObjectiveState, from: Vector3, soldiers: int) -> Dictionary:
	var d := WarSim._flat(from, o.position)
	var p := ws.profile(f)
	var foot_min := d * 1.25 / 1.6 / 60.0
	var seats := free_seats(f.id)
	var mech := d >= p.mech_min_m and seats >= minf(float(soldiers), 8.0)
	var mech_min := d * DETOUR_SCORE / 6.0 / 60.0 + 3.0
	var need_kg := float(soldiers) * 100.0 / Inventory.AMMO_ROUNDS_PER_KG
	var have_kg := 0.0
	for s in lsim.stores(f.id):
		have_kg += s.inventory.get_qty(Inventory.AMMO)
	return {"travel_min": mech_min if mech else foot_min, "mech": mech, "seats": seats, "need_kg": need_kg, "have_kg": have_kg, "foot_min": foot_min}


const DETOUR_SCORE := 1.3


## The faction has a base (otherwise the old free-reserve layout applies and logistics inputs are ignored).
func has_bases(f: int) -> bool:
	return not lsim.bases.bases_of(f).is_empty()


## Free seats of the faction's unassigned transport vehicles.
func free_seats(faction: int) -> int:
	var n := 0
	for id in sim.vehicles.ids:
		var u: UnitState = sim.state.units.get(id)
		if u and u.faction == faction and u.alive and not u.player_controlled and u.veh.assign_kind == "" and u.veh.job.is_empty() \
				and u.veh.status != VehicleState.Status.DISABLED and u.veh.status != VehicleState.Status.NO_FUEL and u.veh.status != VehicleState.Status.BLOCKED:
			n += u.veh.def().passengers
	return n


# --- Recovery ---------------------------------------------------------------------------------------------------------------

## Sends a squad to the nearest friendly depot with ammunition (its soldiers refill their spare rounds there from the
## real stock, LogisticsSim.order_resupply) and notes where it goes back to. Returns {ok, reason}.
func send_to_depot(sq: SquadState, why: String) -> Dictionary:
	if sq == null or sq.members.is_empty():
		return {"ok": false, "reason": "no squad"}
	if sq.tactic_owner == SquadState.Owner.PLAYER or (sq.op_id >= 0 and ws.war.operation(sq.op_id) and ws.war.operation(sq.op_id).player_ordered):
		return {"ok": false, "reason": "the player commands the squad"}
	var center := ws.squad_center(sq)
	var src := ammo_source(sq.faction, center, 1.0)
	if src.is_empty():
		sq.recover_why = "no depot has ammunition"
		return {"ok": false, "reason": "no friendly depot has ammunition"}
	var s: StructureState = src.store
	var res := lsim.order_resupply([sq.id], "s%d" % s.id)
	if not res.ok:
		sq.recover_why = res.reason
		return res
	if sq.recover_site < 0:
		sq.home_pos = _home_of(sq, center)
	sq.recover_site = s.id
	sq.recover_why = why
	stats.recoveries += 1
	ws.log_event(sq.faction, "recovery", "%s goes to %s for ammunition (%s)" % [sq.squad_name, lsim.store_name(s), why], s.position)
	return {"ok": true, "reason": ""}


func _home_of(sq: SquadState, center: Vector3) -> Vector3:
	var o := ws.war.objective(sq.station_objective)
	if o:
		return o.position
	return center


## A squad being resupplied: finished when its soldiers have taken what the store had; then it goes back.
func _recovery_step(sq: SquadState) -> void:
	var s := lsim.structure(sq.recover_site)
	if s == null or s.faction != sq.faction or s.inventory == null:
		sq.recover_site = -1
		sq.recover_why = "the depot is gone or lost"
		return
	var pending := 0
	for id in sq.members:
		var u := sim.state.get_unit(id)
		if u and u.alive and u.resupply_src != "":
			pending += 1
	if pending > 0:
		# Soldiers that cannot reach the depot (blocked) give up with the squad's own stall handling; a stalled
		# squad is sent again once in a while.
		if sq.order == SquadState.Order.NONE or (sq.status == SquadState.Status.DONE and WarSim._flat(ws.squad_center(sq), s.position) > LogisticsSim.RESUPPLY_DEPOT_M * 3.0):
			lsim.order_resupply([sq.id], "s%d" % sq.recover_site)
		return
	var am := squad_ammo(sq)
	sq.recover_site = -1
	stats.recovered += 1
	if am.frac < 0.7:
		sq.recover_why = "depot ran short: %d%% ammunition" % roundi(am.frac * 100.0)
		sq.recover_until = sim.state.time + 60.0
	else:
		sq.recover_why = ""
	if sq.op_id < 0 and sq.home_pos.is_finite() and WarSim._flat(ws.squad_center(sq), sq.home_pos) > 80.0 and sq.tactic_owner != SquadState.Owner.PLAYER:
		sim.squads.order_move([sq.id], sq.home_pos)
	sq.home_pos = Vector3.INF
	ws.log_event(sq.faction, "recovery", "%s is resupplied (%d%% ammunition)" % [sq.squad_name, roundi(am.frac * 100.0)], ws.squad_center(sq))


## Squads of AI factions that serve nothing, are short of ammunition and have a depot with stock within walking range
## go there. Squads of operations are not pulled out (the operation decides: assess_attack before it, withdrawal in it).
func update_recovery(f: FactionState) -> void:
	var p := ws.profile(f)
	for sq: SquadState in ws.squads_of(f.id):
		if sq.recover_site >= 0:
			_recovery_step(sq)
			continue
		if sq.op_id >= 0 or sq.members.is_empty() or sq.tactic != SquadState.Tactic.NONE or sq.recover_until > sim.state.time:
			continue
		if sq.tactic_owner == SquadState.Owner.PLAYER or sq.order == SquadState.Order.MOVE and not sq.route.is_empty():
			continue
		if _under_fire(sq):
			continue
		var am := squad_ammo(sq)
		if am.frac >= p.resupply_below * 0.8:
			continue
		var src := ammo_source(f.id, ws.squad_center(sq), 20.0)
		if src.is_empty():
			sq.recover_until = sim.state.time + 45.0
			sq.recover_why = "no depot has ammunition"
			continue
		if float(src.d) <= WALK_M:
			send_to_depot(sq, "ammunition %d%%" % roundi(am.frac * 100.0))
		# else: a truck mission serves it (update_missions)


func _under_fire(sq: SquadState) -> bool:
	var a := sim.tactics.assessment(sq)
	return not a.is_empty() and (int(a.get("under_fire", 0)) > 0 or int(a.get("seen_n", 0)) > 0)


# --- Supply missions ---------------------------------------------------------------------------------------------------------------

func mission(id: int) -> Dictionary:
	for m: Dictionary in ws.war.missions:
		if int(m.id) == id:
			return m
	return {}


func active_missions(faction := -1) -> Array:
	return ws.war.missions.filter(func(m: Dictionary) -> bool: return (faction < 0 or int(m.faction) == faction) and m.state != "done" and m.state != "failed")


## Asks for a truck to bring ammunition to `squad_ids` at `at`. Returns {ok, reason, mission}.
func request_supply(f: FactionState, squad_ids: Array, at: Vector3, why: String, op_id := -1) -> Dictionary:
	if active_missions(f.id).size() >= MAX_MISSIONS_PER_FACTION:
		return {"ok": false, "reason": "%d missions are running" % MAX_MISSIONS_PER_FACTION}
	for m: Dictionary in active_missions(f.id):
		for sid in squad_ids:
			if m.squads.has(sid):
				return {"ok": false, "reason": "a mission already serves %s" % sim.state.get_squad(sid).squad_name}
	var need := 0.0
	for sid in squad_ids:
		var sq := sim.state.get_squad(sid)
		if sq:
			need += squad_ammo(sq).kg
	if need < MIN_LOAD_KG * 0.5:
		return {"ok": false, "reason": "the squads need only %.0f kg" % need}
	var src := ammo_source(f.id, at, MIN_LOAD_KG)
	if src.is_empty():
		return {"ok": false, "reason": "no depot holds %d kg of ammunition" % roundi(MIN_LOAD_KG)}
	var truck := _free_truck(f.id, src.store.position)
	if truck == null:
		return {"ok": false, "reason": "no free truck with fuel"}
	var point := _safe_point(f, at, src.store.position)
	if not point.is_finite():
		return {"ok": false, "reason": "no safe delivery point on a road within 260 m of the squads, or enemies are believed within %d m of it" % roundi(SAFE_M)}
	# The truck must be able to drive there: one route plan before anything is loaded.
	var chk := sim.vehicles.router.plan(lsim.dock_world(src.store, truck.id), point, truck.veh.def())
	if not chk.ok:
		return {"ok": false, "reason": "no truck route from %s to the delivery point: %s" % [lsim.store_name(src.store), chk.reason]}
	var qty := minf(minf(need * 1.15, LOAD_KG), float(src.kg))
	var m := {"id": ws.war.next_mission_id, "faction": f.id, "kind": "ammo", "squads": squad_ids.duplicate(), "dest": point, "src": src.store.id, "truck": truck.id,
		"qty": qty, "state": "loading", "since": sim.state.time, "state_since": sim.state.time, "why": why, "fail": "", "loaded": 0.0, "op": op_id, "delivered": 0.0, "returned": 0.0}
	ws.war.next_mission_id += 1
	var res := lsim.order_load(truck.id, src.store.id, Inventory.AMMO, qty)
	if not res.ok:
		return {"ok": false, "reason": "the truck cannot load: %s" % res.reason}
	truck.veh.assign_kind = "supply"
	truck.veh.assign_id = int(m.id)
	ws.war.missions.append(m)
	stats.missions += 1
	ws.log_event(f.id, "supply", "Supply mission #%d: %s takes %d kg of ammunition from %s to (%.0f, %.0f) - %s" % [m.id, truck.unit_name, roundi(qty), lsim.store_name(src.store), point.x, point.z, why], point)
	return {"ok": true, "reason": "", "mission": m}


func _free_truck(faction: int, near: Vector3) -> UnitState:
	var best: UnitState = null
	var best_d := INF
	for id in sim.vehicles.ids:
		var u: UnitState = sim.state.units.get(id)
		if u == null or u.faction != faction or not u.alive or u.player_controlled:
			continue
		var v := u.veh
		if v.assign_kind != "" or not v.job.is_empty() or v.convoy_id >= 0 or v.phase != VehicleState.Phase.NONE or u.order != UnitState.Order.NONE:
			continue
		if v.status == VehicleState.Status.DISABLED or v.status == VehicleState.Status.NO_FUEL or v.status == VehicleState.Status.BLOCKED:
			continue
		if v.fuel < v.def().fuel_capacity * 0.25 or v.cargo.free_space() < MIN_LOAD_KG:
			continue
		var d := WarSim._flat(u.position, near)
		if d < best_d:
			best_d = d
			best = u
	return best


## A point behind the squads (towards the depot) where no enemy is believed within SAFE_M; INF when none.
func _safe_point(f: FactionState, at: Vector3, from: Vector3) -> Vector3:
	var dir := Vector3(from.x - at.x, 0.0, from.z - at.z)
	var len := dir.length()
	dir = dir / maxf(len, 0.001)
	# The truck drives on roads (its cross-country planner knows no trees): the point is the road point nearest to the
	# candidate behind the squads (within 220 m of it), the squads walk to the truck from there.
	for back: float in [0.0, 90.0, 180.0, 300.0, 450.0]:
		if back > len * 0.8 and back > 0.0:
			break
		var p := ws._ground(at + dir * back)
		var rd := sim.state.roads.nearest(p, 220.0, 0, 0.0)
		if rd.is_empty():
			continue
		var q := ws._ground(rd.pos)
		if WarSim._flat(q, at) > 260.0:
			continue
		if ws.threat_near(f.id, q, SAFE_M) <= 0 and ws.routes.passable(q):
			return q
	return Vector3.INF


func update() -> void:
	var t0 := Time.get_ticks_usec()
	updates += 1
	ws.mech.update_returns()
	_t += 1.0
	_update_missions()
	if _t >= CHECK_S:
		_t = 0.0
		for f: FactionState in ws.war.factions.values():
			if f.player:
				continue
			update_recovery(f)
			_demand(f)
			_restock(f)
	var d := Time.get_ticks_usec() - t0
	usec += d
	usec_max = maxi(usec_max, d)


## Squads that need ammunition and are too far from a depot to walk: one truck mission per group (an operation's
## squads, a garrison), served from a point behind them.
func _demand(f: FactionState) -> void:
	var p := ws.profile(f)
	if active_missions(f.id).size() >= MAX_MISSIONS_PER_FACTION:
		return
	var groups := {}
	for sq: SquadState in ws.squads_of(f.id):
		if sq.recover_site >= 0 or sq.members.is_empty() or sq.tactic_owner == SquadState.Owner.PLAYER:
			continue
		var op := ws.war.operation(sq.op_id)
		# A squad of an operation is served only once the operation is deployed and the squad itself has no tactic
		# running (a squad that is suppressing, assaulting or withdrawing is never pulled to a truck).
		if op and (op.player_ordered or int(op.stage) < int(OperationState.Stage.DEPLOY) or op.stage == OperationState.Stage.WITHDRAW or sq.tactic != SquadState.Tactic.NONE):
			continue
		if _under_fire(sq):
			continue
		var am := squad_ammo(sq)
		if am.frac >= p.resupply_below * 0.8:
			continue
		var key := "op%d" % sq.op_id if sq.op_id >= 0 else "st%d" % sq.station_objective
		if sq.op_id < 0 and sq.station_objective < 0:
			continue
		var src := ammo_source(f.id, ws.squad_center(sq), MIN_LOAD_KG)
		if not src.is_empty() and float(src.d) <= WALK_M and sq.op_id < 0:
			continue  # walks to the depot (update_recovery)
		if not groups.has(key):
			groups[key] = []
		groups[key].append(sq.id)
	for key: String in groups:
		var ids: Array = groups[key]
		var at := ws._centroid_of(ids)
		var op_id := int(key.substr(2)) if key.begins_with("op") else -1
		if float(_demand_cool.get(key, 0.0)) > sim.state.time:
			continue
		var res := request_supply(f, ids, at, "squads below %d%% ammunition (%s)" % [roundi(p.resupply_below * 100.0 * 0.8), key], op_id)
		if res.ok:
			return
		_demand_cool[key] = sim.state.time + 240.0  # not asked again every few seconds
		var op := ws.war.operation(op_id)
		if op:
			op.supply_why = "resupply not possible: " + res.reason
		elif not ids.is_empty():
			var sq0 := sim.state.get_squad(ids[0])
			if sq0:
				sq0.recover_why = "resupply not possible: " + res.reason


## Forward stores (a base other than the main base) that are low on ammunition get a truck delivery from the main
## base: LogisticsSim.order_delivery depot -> depot (load, drive, unload; Inventory.transfer both ways).
func _restock(f: FactionState) -> void:
	if active_missions(f.id).size() >= MAX_MISSIONS_PER_FACTION:
		return
	var main := lsim.bases.main_base(f.id)
	if main < 0:
		return
	for b: Dictionary in lsim.bases.bases_of(f.id):
		if b.id == main:
			continue
		for s in lsim.bases.base_stores(b.id):
			if not s.inventory.accepts(Inventory.AMMO) or s.inventory.get_qty(Inventory.AMMO) >= 400.0 or s.inventory.free_space() < 500.0:
				continue
			var busy := false
			for m: Dictionary in active_missions(f.id):
				if int(m.get("dst", -1)) == s.id:
					busy = true
			if busy or float(_restock_cool.get(s.id, 0.0)) > sim.state.time:
				continue
			var src := ammo_source(f.id, s.position, 900.0)
			if src.is_empty() or int(src.store.base_id) != main:
				continue
			var truck := _free_truck(f.id, src.store.position)
			if truck == null:
				return
			var qty := minf(1200.0, float(src.kg) - 300.0)
			if qty < MIN_LOAD_KG:
				continue
			var res := lsim.order_delivery(truck.id, src.store.id, s.id, Inventory.AMMO, qty, false, true)
			if not res.ok:
				_restock_cool[s.id] = sim.state.time + 600.0  # the store cannot be reached by truck: not tried every few seconds
				continue
			truck.veh.assign_kind = "supply"
			truck.veh.assign_id = ws.war.next_mission_id
			var m := {"id": ws.war.next_mission_id, "faction": f.id, "kind": "restock", "squads": [], "dest": s.position, "src": src.store.id, "dst": s.id, "truck": truck.id,
				"qty": qty, "state": "running", "since": sim.state.time, "state_since": sim.state.time, "why": "forward store %s below 400 kg of ammunition" % lsim.store_name(s),
				"fail": "", "loaded": 0.0, "op": -1, "delivered": 0.0, "returned": 0.0, "before": s.inventory.get_qty(Inventory.AMMO)}
			ws.war.next_mission_id += 1
			ws.war.missions.append(m)
			stats.missions += 1
			ws.log_event(f.id, "supply", "Supply mission #%d: %s takes %d kg of ammunition from %s to %s" % [m.id, truck.unit_name, roundi(qty), lsim.store_name(src.store), lsim.store_name(s)], s.position)
			return


func _update_missions() -> void:
	var now := sim.state.time
	for m: Dictionary in ws.war.missions.duplicate():
		if m.state == "done" or m.state == "failed":
			if now - float(m.state_since) > 600.0:
				ws.war.missions.erase(m)
			continue
		var u := sim.state.get_unit(int(m.truck))
		if u == null or u.veh == null or not u.alive or u.veh.status == VehicleState.Status.DISABLED:
			_fail(m, "the truck was destroyed" + (": its cargo stays in the wreck" if u else ""), null)
			continue
		if u.player_controlled or u.veh.assign_kind != "supply" or u.veh.assign_id != int(m.id):
			_fail(m, "the truck was taken over", null)
			continue
		var src := lsim.structure(int(m.src))
		if src == null or src.faction != int(m.faction):
			if m.state == "loading" and m.kind != "restock":
				# The depot it loads from changed hands: the loading stops (cargo already aboard stays the truck's).
				lsim.cancel_job(u.id, "the depot was lost")
				_fail(m, "the source depot was lost to the enemy", u)
				continue
			if m.state in ["driving", "serving"]:
				m["src_lost"] = true  # it will return to another depot of the faction (or keep the cargo aboard)
		if m.kind == "restock":
			if u.veh.job.is_empty():
				var dst := lsim.structure(int(m.dst))
				m["delivered"] = (dst.inventory.get_qty(Inventory.AMMO) - float(m.before)) if dst and dst.inventory else 0.0
				if float(m.delivered) > 0.5:
					stats.delivered += 1
					stats.kg_delivered += float(m.delivered)
					_finish(m, u, "done", "")
				else:
					stats.failed += 1
					_finish(m, u, "failed", "nothing was delivered (%s)" % (u.veh.reason if u.veh.reason != "" else "the job ended"))
			elif now - float(m.state_since) > DRIVE_TIMEOUT_S + LOAD_TIMEOUT_S:
				lsim.cancel_job(u.id, "supply mission timed out")
				stats.failed += 1
				_finish(m, u, "failed", "timed out")
			continue
		match m.state:
			"loading":
				if u.veh.job.is_empty():
					var loaded := u.veh.cargo.get_qty(Inventory.AMMO)
					if loaded < MIN_LOAD_KG * 0.5:
						_fail(m, "nothing was loaded (%.0f kg)" % loaded, u)
						continue
					m["loaded"] = loaded
					var res := ws.sim.vehicles.order_drive(u.id, m.dest)
					# order_drive (not from transport) clears nothing of ours: the assignment stays.
					if not res.ok:
						_fail(m, "the truck cannot drive to the squads: %s" % res.reason, u)
						continue
					u.veh.assign_kind = "supply"
					u.veh.assign_id = int(m.id)
					_state(m, "driving")
				elif now - float(m.state_since) > LOAD_TIMEOUT_S:
					_fail(m, "loading took too long", u)
			"driving":
				if u.order == UnitState.Order.NONE and absf(u.veh.speed) < 0.6:
					if WarSim._flat(u.position, m.dest) <= 60.0:
						_serve(m, u)
					else:
						_fail(m, "the truck stopped %d m short (%s)" % [roundi(WarSim._flat(u.position, m.dest)), u.veh.reason if u.veh.reason != "" else u.veh.status_name()], u)
				elif now - float(m.state_since) > DRIVE_TIMEOUT_S:
					_fail(m, "the drive took more than %d s" % int(DRIVE_TIMEOUT_S), u)
				elif _threatened(m):
					# Enemies are now believed at the delivery point: the truck turns round.
					_fail(m, "enemies reported near the delivery point (%.0f, %.0f)" % [m.dest.x, m.dest.z], u)
			"serving":
				var pending := 0
				for sid in m.squads:
					var sq := sim.state.get_squad(sid)
					if sq == null:
						continue
					for id in sq.members:
						var s := sim.state.get_unit(id)
						if s and s.alive and s.resupply_src == "v%d" % u.id:
							pending += 1
				if pending == 0 or now - float(m.state_since) > SERVE_TIMEOUT_S or u.veh.cargo.get_qty(Inventory.AMMO) <= 0.5:
					# Delivered: what the soldiers took left the truck (kg -> rounds); the truck brings the rest back.
					m["delivered"] = float(m.loaded) - u.veh.cargo.get_qty(Inventory.AMMO)
					stats.kg_delivered += float(m.delivered)
					stats.delivered += 1
					for sid in m.squads:
						var sq := sim.state.get_squad(sid)
						if sq:
							for id in sq.members:
								var s := sim.state.get_unit(id)
								if s and s.resupply_src == "v%d" % u.id:
									s.resupply_src = ""
					_send_back(m)
					_return(m, u, "delivered %d kg" % roundi(float(m.delivered)))
			"returning":
				if u.veh.job.is_empty() and u.order == UnitState.Order.NONE and absf(u.veh.speed) < 0.6:
					_unload(m, u)
				elif now - float(m.state_since) > DRIVE_TIMEOUT_S:
					_finish(m, u, "failed", "the way back took too long")
			"unloading":
				if u.veh.job.is_empty():
					var left := u.veh.cargo.get_qty(Inventory.AMMO)
					m["returned"] = float(m.loaded) - float(m.get("delivered", 0.0)) - left
					stats.kg_returned += maxf(float(m.returned), 0.0)
					_finish(m, u, "done", "")


func _threatened(m: Dictionary) -> bool:
	return ws.threat_near(int(m.faction), m.dest, SAFE_M * 0.7) > 0


func _state(m: Dictionary, st: String) -> void:
	m["state"] = st
	m["state_since"] = sim.state.time


func _serve(m: Dictionary, u: UnitState) -> void:
	var n := 0
	var back := {}
	for sid in m.squads:
		var sq := sim.state.get_squad(sid)
		if sq == null or sq.members.is_empty() or sq.tactic != SquadState.Tactic.NONE or sq.tactic_owner == SquadState.Owner.PLAYER:
			continue
		var op := ws.war.operation(sq.op_id)
		if op != null and op.player_ordered:
			continue
		# The squad comes to the truck (an ordinary resupply order) and goes back to where it stood afterwards.
		back[sid] = ws.squad_center(sq)
		var r := lsim.order_resupply([sid], "v%d" % u.id)
		n += int(r.get("soldiers", 0))
	m["back"] = back
	_state(m, "serving")
	if n == 0:
		_return(m, u, "nobody could be served (squads engaged or gone)")


## The squads served by a truck go back to where they stood (a squad of an operation resumes through its operation:
## the stage logic tasks an idle squad again; a garrison squad walks back to its sector).
func _send_back(m: Dictionary) -> void:
	for sid in m.get("back", {}):
		var sq := sim.state.get_squad(int(sid))
		if sq == null or sq.members.is_empty() or sq.tactic_owner == SquadState.Owner.PLAYER:
			continue
		var op := ws.war.operation(sq.op_id)
		if op != null and (op.player_ordered or op.stage == OperationState.Stage.WITHDRAW):
			continue
		sim.squads.order_move([int(sid)], m.back[sid])


func _return(m: Dictionary, u: UnitState, note: String) -> void:
	var src := lsim.structure(int(m.src))
	if src == null or src.faction != int(m.faction):
		src = lsim.nearest_store(u.position, int(m.faction), Inventory.AMMO)
	if src == null:
		_finish(m, u, "failed", note + "; no depot to return to (the cargo stays aboard)")
		return
	m["src"] = src.id
	m["note"] = note
	var dock := lsim.dock_world(src, u.id)
	var res := sim.vehicles.order_drive(u.id, dock)
	u.veh.assign_kind = "supply"
	u.veh.assign_id = int(m.id)
	if not res.ok:
		_finish(m, u, "failed", note + "; cannot drive back: %s" % res.reason)
		return
	_state(m, "returning")


func _unload(m: Dictionary, u: UnitState) -> void:
	var src := lsim.structure(int(m.src))
	if src == null or u.veh.cargo.is_empty():
		_finish(m, u, "done", "")
		return
	var res := lsim.order_unload(u.id, src.id, Inventory.AMMO)
	if not res.ok:
		_finish(m, u, "done", "nothing to unload")
		return
	u.veh.assign_kind = "supply"
	u.veh.assign_id = int(m.id)
	_state(m, "unloading")


func _fail(m: Dictionary, why: String, u: UnitState) -> void:
	stats.failed += 1
	m["fail"] = why
	ws.log_event(int(m.faction), "supply", "Supply mission #%d failed: %s" % [m.id, why], m.dest)
	var op := ws.war.operation(int(m.op))
	if op:
		op.supply_why = "supply mission failed: " + why
	if u and u.alive and u.veh and not u.player_controlled and u.veh.assign_kind == "supply" and u.veh.assign_id == int(m.id):
		if u.veh.cargo.get_qty(Inventory.AMMO) > 0.5:
			m["loaded"] = float(m.get("loaded", u.veh.cargo.get_qty(Inventory.AMMO)))
			m["delivered"] = 0.0
			_return(m, u, why)
			if m.state == "returning":
				m["fail"] = why
				return
		_finish(m, u, "failed", why)
		return
	_state(m, "failed")
	if u and u.veh and u.veh.assign_kind == "supply" and u.veh.assign_id == int(m.id):
		u.veh.assign_kind = ""
		u.veh.assign_id = -1


func _finish(m: Dictionary, u: UnitState, state: String, note: String) -> void:
	_state(m, state)
	if note != "":
		m["fail"] = note
	if u and u.veh and u.veh.assign_kind == "supply" and u.veh.assign_id == int(m.id):
		u.veh.assign_kind = ""
		u.veh.assign_id = -1
	if state == "done":
		ws.log_event(int(m.faction), "supply", "Supply mission #%d done: %d kg delivered, %d kg back at the depot" % [m.id, roundi(float(m.get("delivered", 0.0))), roundi(float(m.get("returned", 0.0)))], m.dest)


# --- Inspection ----------------------------------------------------------------------------------------------------------------------

## Lines for the faction inspector: supply missions, squads recovering, and the readiness numbers.
func explain(f: FactionState) -> Array[String]:
	var out: Array[String] = []
	var p := ws.profile(f)
	var rec := 0
	for sq: SquadState in ws.squads_of(f.id):
		if sq.recover_site >= 0:
			var s := lsim.structure(sq.recover_site)
			rec += 1
			out.append("  recovering: %s at %s - %s" % [sq.squad_name, lsim.store_name(s) if s else "?", sq.recover_why])
		elif sq.recover_why != "" and sq.op_id < 0:
			out.append("  %s: %s" % [sq.squad_name, sq.recover_why])
	for m: Dictionary in ws.war.missions:
		if int(m.faction) != f.id:
			continue
		var u := sim.state.get_unit(int(m.truck))
		out.append("  supply #%d [%s] %s -> (%.0f, %.0f): %d kg loaded, %d delivered%s - %s" % [m.id, m.state, u.unit_name if u else "?", m.dest.x, m.dest.z, roundi(float(m.get("loaded", 0.0))),
			roundi(float(m.get("delivered", 0.0))), (", FAILED: " + m.fail) if m.get("fail", "") != "" else "", m.why])
	out.append("  readiness: attack needs squads above %d%% ammunition; free transport seats %d; delays %s" % [roundi(p.resupply_below * 100.0), free_seats(f.id), str(_delays)])
	return out


func summary() -> Dictionary:
	return {"stats": stats.duplicate(), "us_avg": snappedf(float(usec) / maxi(updates, 1), 0.1), "us_max": usec_max}
