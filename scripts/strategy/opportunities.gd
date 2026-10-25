## GAMEPLAY-04E opportunities: things worth doing that the world offers the player after the introduction, owned by WarSim
## (`WarSim.opps`; records in WarState.opportunities, saved). Nothing is spawned for them: every opportunity points at
## something that exists - a cache, equipment lying somewhere, an enemy-held objective, an enemy position nobody has looked
## at lately, a threatened base - and is complete when the world says so. The player may accept one (it is tracked, marked
## on the way) or ignore it; the reward comes either way when it is achieved (WarEconomy-style explicit income through
## BaseSim.faction_deposit: supplies and ammunition only, no other currency).
##
## Record: {id, kind, title, text, pos, ref (objective / cache / stash id), state ("offered", "accepted", "done", "lapsed"),
## reward {supplies, ammo}, created, since (recon: when a soldier came within reach), done_at}.
class_name Opportunities
extends RefCounted

const TICK_S := 2.0
const OFFER_S := 30.0
const MAX_OPEN := 4
const ASSAULT_RANGE_M := 4000.0
const RECON_MIN_M := 3000.0
const RECON_MAX_M := 9000.0
const RECON_REACH_M := 300.0
const RECON_HOLD_S := 20.0
const DEFEND_QUIET_S := 60.0
const REWARDS := {"supplies": {"supplies": 100.0, "ammo": 0.0}, "recover": {"supplies": 0.0, "ammo": 40.0},
	"assault": {"supplies": 300.0, "ammo": 100.0}, "recon": {"supplies": 150.0, "ammo": 0.0}, "defend": {"supplies": 100.0, "ammo": 150.0}}

var ws: WarSim
var _t := 0.0
var _offer_t := 0.0


func _init(p_ws: WarSim) -> void:
	ws = p_ws


func _list() -> Array:
	if not ws.war.guide.has("opps"):
		ws.war.guide["opps"] = []
	return ws.war.guide["opps"]


## Open, not ignored: what the player can take up (offered or accepted).
func open() -> Array:
	return _list().filter(func(o: Dictionary) -> bool: return o.state in ["offered", "accepted"])


func accepted() -> Array:
	return _list().filter(func(o: Dictionary) -> bool: return o.state == "accepted")


func offered() -> Array:
	return _list().filter(func(o: Dictionary) -> bool: return o.state == "offered")


func by_id(oid: int) -> Dictionary:
	for o: Dictionary in _list():
		if int(o.id) == oid:
			return o
	return {}


func accept(oid: int) -> bool:
	var o := by_id(oid)
	if o.is_empty() or o.state != "offered":
		return false
	o.state = "accepted"
	ws.log_event(ws.war.player_faction, "opportunity", "Accepted: %s" % o.title, o.pos)
	return true


func dismiss(oid: int) -> void:
	var o := by_id(oid)
	if not o.is_empty() and o.state in ["offered", "accepted"]:
		o.state = "lapsed"
		o["dismissed"] = true


## Offered only once the introduction is over (or a scenario without one), with the war running.
func active() -> bool:
	return ws.war.active and ws.enabled and (not ws.intro.active() or ws.intro.complete()) and bool(ws.war.rule("player_income", false))


func update(dt: float) -> void:
	if not active():
		return
	_t += dt
	if _t < TICK_S:
		return
	var step := _t
	_t = 0.0
	for o: Dictionary in open():
		_check(o, step)
	_offer_t += step
	if _offer_t >= OFFER_S or _list().is_empty():
		_offer_t = 0.0
		_offer()


# --- Completion ------------------------------------------------------------------------------------------------------

func _check(o: Dictionary, dt: float) -> void:
	var pf := ws.war.player_faction
	match String(o.kind):
		"supplies":
			var c := _cache(int(o.ref))
			if c.is_empty() or c.state == "depleted":
				_finish(o, int(c.get("taken_by", -1)) == pf)
		"recover":
			var s := _stash(int(o.ref))
			if s.is_empty() or (s.items as Dictionary).is_empty():
				_finish(o, true)
		"assault":
			var obj := ws.war.objective(int(o.ref))
			if obj == null:
				_finish(o, false)
			elif obj.owner == pf:
				_finish(o, true)
		"recon":
			var near := false
			ws.sim.brain._ensure_grid()
			for u: UnitState in ws.sim.brain._near(o.pos, RECON_REACH_M):
				if u.faction == pf and u.alive:
					near = true
					break
			o["since"] = float(o.get("since", 0.0)) + dt if near else 0.0
			if float(o.since) >= RECON_HOLD_S:
				_finish(o, true)
		"defend":
			var b: Dictionary = ws.sim.state.construction.bases.get(int(o.ref), {})
			if b.is_empty() or int(b.faction) != pf:
				_finish(o, false)
			elif ws.threat_near(pf, b.anchor, 700.0) == 0:
				o["since"] = float(o.get("since", 0.0)) + dt
				if float(o.since) >= DEFEND_QUIET_S:
					_finish(o, true)
			else:
				o["since"] = 0.0


func _finish(o: Dictionary, success: bool) -> void:
	var pf := ws.war.player_faction
	o.state = "done" if success else "lapsed"
	o["done_at"] = snappedf(ws.sim.state.time, 0.1)
	if not success:
		return
	var items := {}
	var parts: Array[String] = []
	for k in o.reward:
		if float(o.reward[k]) > 0.0:
			items[StringName(k)] = float(o.reward[k])
			parts.append("+%d kg %s" % [roundi(float(o.reward[k])), "ammunition" if k == "ammo" else k])
	if not items.is_empty():
		ws.sim.logistics.bases.faction_deposit(pf, items)
		var f := ws.war.faction(pf)
		for k in items:
			f.ledger["in"][String(k)] = float(f.ledger["in"].get(String(k), 0.0)) + float(items[k])
	ws.log_event(pf, "opportunity_done", "Opportunity complete: %s%s" % [o.title, (" (" + ", ".join(parts) + ")") if not parts.is_empty() else ""], o.pos)


# --- Offers ----------------------------------------------------------------------------------------------------------

func _has(kind: String, ref: int) -> bool:
	for o: Dictionary in _list():
		if o.kind == kind and int(o.ref) == ref and (o.state in ["offered", "accepted", "done"] or o.get("dismissed", false)):
			return true
	return false


func _add(kind: String, ref: int, title: String, text: String, pos: Vector3) -> void:
	var o := {"id": int(ws.war.guide.get("next_opp", 1)), "kind": kind, "ref": ref, "title": title, "text": text, "pos": pos,
		"state": "offered", "reward": REWARDS[kind].duplicate(), "created": snappedf(ws.sim.state.time, 0.1)}
	ws.war.guide["next_opp"] = int(o.id) + 1
	_list().append(o)
	ws.log_event(ws.war.player_faction, "opportunity", "New opportunity: %s" % title, pos)


## Where the player is: his bases and squads (distances for the offers are measured from the nearest).
func _anchors() -> Array:
	var pf := ws.war.player_faction
	var out := []
	for b: Dictionary in ws.sim.logistics.bases.bases_of(pf):
		out.append(b.anchor)
	for sq: SquadState in ws.squads_of(pf):
		out.append(ws.squad_center(sq))
	return out


func _dist(p: Vector3, anchors: Array) -> float:
	var d := INF
	for a: Vector3 in anchors:
		d = minf(d, WarSim._flat(a, p))
	return d


func _offer() -> void:
	if open().size() >= MAX_OPEN:
		return
	var pf := ws.war.player_faction
	var anchors := _anchors()
	if anchors.is_empty():
		return
	var cands := []
	# Defend first: a base the faction has been warned about.
	for b: Dictionary in ws.sim.logistics.bases.bases_of(pf):
		if ws.threat_near(pf, b.anchor, 700.0) > 0 and not _has_open("defend", int(b.id)):
			cands.append([0.0, "defend", int(b.id), "Defend %s" % b.name, "Enemy reported near %s. Garrison it (O) or bring squads; it is complete when the area has been quiet for a minute." % b.name, b.anchor])
	for c: Dictionary in ws.war.caches:
		if c.state != "depleted" and (c.known as Array).has(pf) and not _has("supplies", int(c.id)):
			cands.append([1.0 + _dist(c.pos, anchors) / 1000.0, "supplies", int(c.id), "Secure %s" % c.name, "Hold the cache with your soldiers for about 30 s with no enemy near; its supplies go to your stock.", c.pos])
	for s: Dictionary in ws.equip.known_stashes(pf):
		if s.kind != "fallen" and not (s.items as Dictionary).is_empty() and not _has("recover", int(s.id)):
			var names: Array[String] = []
			for k in s.items:
				var wd := ws.sim.combat.weapon(StringName(k))
				names.append(wd.display_name if wd else String(k))
			cands.append([1.5 + _dist(s.pos, anchors) / 1000.0, "recover", int(s.id), "Recover equipment at %s" % s.name,
				"%s lie there. Send a squad to REARM there (R) and hand the weapons in at a base with a Supply Depot." % ", ".join(names), s.pos])
	for o: ObjectiveState in ws.war.all_objectives():
		if o.owner >= 0 and o.owner != pf and not o.is_hq() and not _has("assault", o.id):
			var d := _dist(o.position, anchors)
			if d <= ASSAULT_RANGE_M:
				cands.append([2.0 + d / 1000.0, "assault", o.id, "Take %s" % o.obj_name, "%s holds %s (%d m away). Capture it for its income: scout it, then attack with more than one squad." % [WorldState.faction_name(o.owner), o.obj_name, roundi(d)], o.position])
	if ws.dev.is_done(pf, &"reconnaissance"):
		for o: ObjectiveState in ws.war.all_objectives():
			if o.owner >= 0 and o.owner != pf and not _has("recon", o.id):
				var d := _dist(o.position, anchors)
				if d >= RECON_MIN_M and d <= RECON_MAX_M and ws.intel.contacts_near(pf, o.position, 500.0).is_empty():
					cands.append([3.0 + d / 1000.0, "recon", o.id, "Observe %s" % o.obj_name, "Nobody has reported from %s lately. Bring a soldier within %d m for %d s: what he sees reaches your map." % [o.obj_name, roundi(RECON_REACH_M), roundi(RECON_HOLD_S)], o.position])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for c: Array in cands:
		if open().size() >= MAX_OPEN:
			break
		_add(c[1], c[2], c[3], c[4], c[5])


func _has_open(kind: String, ref: int) -> bool:
	for o: Dictionary in open():
		if o.kind == kind and int(o.ref) == ref:
			return true
	return false


func _cache(cid: int) -> Dictionary:
	for c: Dictionary in ws.war.caches:
		if int(c.id) == cid:
			return c
	return {}


func _stash(sid: int) -> Dictionary:
	for s: Dictionary in ws.war.stashes:
		if int(s.id) == sid:
			return s
	return {}
