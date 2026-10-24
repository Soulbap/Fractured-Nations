## Faction intelligence (AI-INTEL-01): turns observations into each faction's contact picture.
##
## Owned by WarSim and ticked by it (once per second, no loop of its own). The only inputs are
## reports from things that can legitimately know: CombatBrain tells it when a soldier SEES an
## enemy, takes FIRE, or HEARS shots; WarSim tells it where a faction's own soldiers hold an
## objective an enemy stands in. A report reaches the faction after a short delay, becomes a
## ContactState in WarState.contacts[faction] (merged into an existing contact when it plausibly
## is the same group), and from then on only ages: confidence falls, the uncertainty circle
## grows, the position stays where it was last reported. Nothing here ever reads an unobserved
## enemy's position. WarSim's strategic decisions read contacts through threat_near() and
## contacts_of().
##
## Cost: reports are throttled per observer (one per report_every_s), the table is capped per
## faction (max_contacts), and the sweep touches only that table. CombatBrain's existing
## perception (3 Hz, line-of-sight budget, 128 m grid) is the only detection pipeline.
class_name IntelSim
extends RefCounted

# --- Tunables -----------------------------------------------------------------------------
## A sighting reaches the faction this long after it was made; a sound a little later (s).
var report_delay_s := 3.0
var heard_delay_s := 6.0
## One report per observing soldier at most this often (s).
var report_every_s := 2.5
## Reports within this distance (plus half the contact's uncertainty) of a contact belong to it (m).
var merge_m := 60.0
var heard_merge_m := 140.0
## A reported unit this far from the contact it was assigned to splits off from it (m).
var split_m := 120.0
var max_contacts := 40
## A contact seen this recently counts as currently observed (s).
var confirm_s := 7.0
## Evidence this young is never called stale; older evidence is stale below stale_conf and
## dropped below lost_conf (confidence).
var fresh_s := 30.0
var stale_conf := 0.45
var lost_conf := 0.12
## Reported unit ids older than this no longer count towards the strength estimate (s).
var id_window_s := 30.0
var unc_cap := 800.0
var heard_strength := 2
var max_pending := 600
## Time constant of the confidence decay (s) and confidence at the moment of evidence, per
## ContactState.Source (seen, fire, heard, objective).
const TAU: Array[float] = [90.0, 45.0, 45.0, 90.0]
const BASE_CONF: Array[float] = [1.0, 0.55, 0.4, 0.8]
## Speed the believed group may have moved at since the last evidence (m/s) per Kind.
const SPEED: Array[float] = [1.2, 1.2, 8.0]
const HISTORY_MAX := 80

var ws: WarSim
## faction -> {enemy unit id: contact id} (runtime index, rebuilt from the contacts' ids).
var _by_unit := {}
var _next_seen := {}
var _next_fire := {}
var _next_heard := {}
var _next_obj := {}
var _t := 0.0
## Newest last: {t, f, id, text}. Runtime, for the inspector.
var history: Array = []
## Measurements.
var reports_in := 0
var reports_throttled := 0
var reports_applied := 0
var reports_dropped := 0
var created := 0
var lost := 0
var merged := 0
var splits := 0
var usec := 0
## Time spent in the report_* calls made by CombatBrain / WarSim, and in CombatBrain's group
## counting for them (us).
var report_usec := 0
var group_usec := 0
var usec_max := 0
var sweeps := 0


func _init(p_ws: WarSim) -> void:
	ws = p_ws


func active() -> bool:
	return ws.enabled and ws.war.active


func _state() -> WorldState:
	return ws.sim.state


## After a load: the table came with the world; the runtime index and timers start fresh.
func rebuild() -> void:
	_by_unit.clear()
	_next_seen.clear()
	_next_fire.clear()
	_next_heard.clear()
	_next_obj.clear()
	history.clear()
	_t = 0.0
	for f in ws.war.contacts:
		var idx := {}
		for c: ContactState in ws.war.contacts[f].values():
			for uid in c.ids:
				idx[uid] = c.id
		_by_unit[f] = idx


# --- Reports (called by CombatBrain / WarSim) ----------------------------------------------

## True when o may file a sighting report now (CombatBrain asks first so it only works out
## the group size for reports that will be made).
func seen_due(o: UnitState) -> bool:
	return active() and _state().time >= _next_seen.get(o.id, 0.0)


## A soldier of o's faction sees enemy t. `group` is how many enemy soldiers are in the group
## around t (CombatBrain counts those within a few metres of the sighted one: a sighted group is
## taken to be seen as a group); the report carries an estimate of it, not the exact number.
func _report_seen(o: UnitState, t: UnitState, group := 1) -> void:
	if not active():
		return
	var now := _state().time
	if now < _next_seen.get(o.id, 0.0):
		reports_throttled += 1
		return
	_next_seen[o.id] = now + report_every_s * (0.75 + 0.5 * float((o.id * 37) % 100) / 100.0)
	var d := WarSim._flat(o.position, t.position)
	var kind := ContactState.Kind.VEHICLE if t.kind == UnitState.Kind.VEHICLE else ContactState.Kind.INFANTRY
	var est := clampi(roundi(group * (0.8 + 0.4 * float((o.id * 131 + t.id * 17) % 100) / 100.0)), 1, 40)
	_queue(o.faction, t.faction, kind, ContactState.Source.SEEN, t.position, t.id, 6.0 + d * 0.04, est, o.unit_name, now, report_delay_s)


## A soldier comes under fire from roughly `from` (already blurred by the caller).
func _report_fire(u: UnitState, from: Vector3) -> void:
	if not active() or not from.is_finite():
		return
	var now := _state().time
	if now < _next_fire.get(u.id, 0.0):
		reports_throttled += 1
		return
	_next_fire[u.id] = now + 4.0
	var d := WarSim._flat(u.position, from)
	_queue(u.faction, -1, ContactState.Kind.UNKNOWN, ContactState.Source.FIRE, from, -1, 40.0 + d * 0.12, heard_strength, u.unit_name, now, report_delay_s)


## A soldier hears hostile gunfire at `at` (distance d) without seeing the shooter: the report
## carries a blurred position and a wide uncertainty, no identity.
func _report_heard(u: UnitState, at: Vector3, d: float) -> void:
	if not active():
		return
	var now := _state().time
	if now < _next_heard.get(u.id, 0.0):
		reports_throttled += 1
		return
	_next_heard[u.id] = now + 4.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state().world_seed, u.id, int(now / 2.0), 77])
	var off := maxf(d * 0.25, 10.0)
	var p := at + Vector3(rng.randf_range(-off, off), 0.0, rng.randf_range(-off, off))
	_queue(u.faction, -1, ContactState.Kind.UNKNOWN, ContactState.Source.HEARD, p, -1, 40.0 + d * 0.5, heard_strength, u.unit_name, now, heard_delay_s)


## Soldiers of faction f stand in objective o together with n soldiers of faction ef.
func _report_objective(f: int, ef: int, o: ObjectiveState, n: int) -> void:
	if not active():
		return
	var key := f * 1000 + ef * 100 + o.id
	var now := _state().time
	if now < _next_obj.get(key, 0.0):
		return
	_next_obj[key] = now + 4.0
	_queue(f, ef, ContactState.Kind.INFANTRY, ContactState.Source.OBJECTIVE, o.position, -1, o.radius * 0.5, n, "garrison of %s" % o.obj_name, now, 1.0)


func report_seen(o: UnitState, t: UnitState, group := 1) -> void:
	var t0 := Time.get_ticks_usec()
	_report_seen(o, t, group)
	report_usec += Time.get_ticks_usec() - t0


func report_fire(u: UnitState, from: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_report_fire(u, from)
	report_usec += Time.get_ticks_usec() - t0


func report_heard(u: UnitState, at: Vector3, d: float) -> void:
	var t0 := Time.get_ticks_usec()
	_report_heard(u, at, d)
	report_usec += Time.get_ticks_usec() - t0


func report_objective(f: int, ef: int, o: ObjectiveState, n: int) -> void:
	var t0 := Time.get_ticks_usec()
	_report_objective(f, ef, o, n)
	report_usec += Time.get_ticks_usec() - t0


func _queue(f: int, ef: int, kind: int, src: int, p: Vector3, uid: int, unc: float, strength: int, by: String, now: float, delay: float) -> void:
	reports_in += 1
	if ws.war.intel_pending.size() >= max_pending:
		reports_dropped += 1
		return
	# GAMEPLAY-04B: Reconnaissance Capability shortens the way a report takes to the faction.
	if ws.dev:
		delay *= ws.dev.effect(f, "intel_delay_mult")
	ws.war.intel_pending.append({"f": f, "ef": ef, "kind": kind, "src": src, "p": p, "uid": uid, "unc": unc, "str": strength,
		"by": by, "t": now, "due": now + delay})


# --- Sweep (WarSim, once per second) ---------------------------------------------------------

func update(delta: float) -> void:
	if not active():
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var t0 := Time.get_ticks_usec()
	var now := _state().time
	var pend: Array = ws.war.intel_pending
	if not pend.is_empty():
		var keep := []
		for r: Dictionary in pend:
			if r.due <= now:
				_apply(r, now)
			else:
				keep.append(r)
		ws.war.intel_pending = keep
	for f in ws.war.contacts.keys():
		var tbl: Dictionary = ws.war.contacts[f]
		for cid in tbl.keys():
			var c: ContactState = tbl[cid]
			refresh(c, now)
			if c.status == ContactState.Status.LOST:
				_erase(c, "lost (%ds without news)" % roundi(now - c.t_seen))
				lost += 1
	sweeps += 1
	var dt := Time.get_ticks_usec() - t0
	usec += dt
	usec_max = maxi(usec_max, dt)


## Recomputes confidence, uncertainty and status of a contact for the time `now`.
func refresh(c: ContactState, now: float) -> void:
	var age := maxf(now - c.t_seen, 0.0)
	c.conf = c.conf0 * exp(-age / TAU[c.source])
	c.unc = minf(c.unc0 + SPEED[c.kind] * age, unc_cap)
	if c.source == ContactState.Source.SEEN and age <= confirm_s:
		c.status = ContactState.Status.OBSERVED
	elif c.conf >= stale_conf or age <= fresh_s:
		c.status = ContactState.Status.REPORTED
	elif c.conf >= lost_conf:
		c.status = ContactState.Status.STALE
	else:
		c.status = ContactState.Status.LOST
	# Old unit ids no longer count towards the group's size.
	var old := false
	for t in c.ids_t:
		if t < now - id_window_s:
			old = true
			break
	if old:
		var ids := PackedInt32Array()
		var ts := PackedFloat32Array()
		var idx: Dictionary = _by_unit.get(c.faction, {})
		for i in c.ids.size():
			if c.ids_t[i] >= now - id_window_s:
				ids.append(c.ids[i])
				ts.append(c.ids_t[i])
			elif idx.get(c.ids[i], -1) == c.id:
				idx.erase(c.ids[i])
		c.ids = ids
		c.ids_t = ts


func _apply(r: Dictionary, now: float) -> void:
	reports_applied += 1
	var f: int = r.f
	var tbl: Dictionary = ws.war.contacts.get(f, {})
	ws.war.contacts[f] = tbl
	var idx: Dictionary = _by_unit.get(f, {})
	_by_unit[f] = idx
	var c: ContactState = null
	if r.uid >= 0:
		c = tbl.get(idx.get(r.uid, -1))
		if c and WarSim._flat(c.pos, r.p) > split_m and r.t - c.t_seen < 10.0:
			# This unit is far from the group it was counted in: it is not part of it.
			_drop_id(c, r.uid)
			splits += 1
			c = null
	if c == null:
		c = _nearest(tbl, r)
	if c == null:
		c = ContactState.new()
		c.id = ws.war.next_contact_id
		ws.war.next_contact_id += 1
		c.faction = f
		c.enemy_faction = r.ef
		c.kind = r.kind
		c.source = r.src
		c.pos = r.p
		c.t_seen = r.t
		c.t_first = r.t
		c.t_report = now
		c.conf0 = BASE_CONF[r.src]
		c.unc0 = r.unc
		c.strength = r.str
		if tbl.size() >= max_contacts:
			_evict(tbl)
		tbl[c.id] = c
		created += 1
		_note_ids(c, r, idx)
		refresh(c, now)
		_hist(f, c.id, "new contact #%d: %s %s ~%d, %s (%s)" % [c.id, WorldState.faction_name(c.enemy_faction) if c.enemy_faction >= 0 else "unidentified", c.kind_name(), c.strength, c.source_name(), r.by])
		return
	merged += 1
	c.reports += 1
	c.t_report = now
	var prev_seen := c.t_seen
	var prev_strength := c.strength
	var better: bool = ContactState.SOURCE_RANK[r.src] >= ContactState.SOURCE_RANK[c.source] or r.t - c.t_seen > 10.0
	if better:
		var reacquired: bool = c.status != ContactState.Status.OBSERVED and r.src == ContactState.Source.SEEN
		if r.t - c.t_seen < 3.0 and WarSim._flat(c.pos, r.p) < split_m:
			c.pos = c.pos.lerp(r.p, 0.5)
		else:
			c.pos = r.p
		c.source = r.src
		c.conf0 = BASE_CONF[r.src]
		c.unc0 = r.unc
		c.t_seen = maxf(c.t_seen, r.t)
		if reacquired:
			_hist(f, c.id, "contact #%d reacquired (%s)" % [c.id, r.by])
	if r.kind != ContactState.Kind.UNKNOWN:
		c.kind = r.kind
	if r.ef >= 0:
		c.enemy_faction = r.ef
	_note_ids(c, r, idx)
	if r.src == ContactState.Source.SEEN:
		# Several observers of one group give a larger and larger count within a few seconds;
		# a sighting after a long gap replaces the old estimate.
		c.strength = maxi(r.str, c.ids.size()) if r.t - prev_seen > 8.0 else maxi(maxi(r.str, c.ids.size()), prev_strength)
	refresh(c, now)


## Best existing contact a report belongs to: same (or unidentified) enemy faction, nearest
## within the merge radius widened by half the contact's uncertainty.
func _nearest(tbl: Dictionary, r: Dictionary) -> ContactState:
	var best: ContactState = null
	var best_d := INF
	var soft: bool = r.src == ContactState.Source.HEARD or r.src == ContactState.Source.FIRE
	for c: ContactState in tbl.values():
		if r.ef >= 0 and c.enemy_faction >= 0 and c.enemy_faction != r.ef:
			continue
		var lim := (heard_merge_m if soft or c.source == ContactState.Source.HEARD or c.source == ContactState.Source.FIRE else merge_m) + 0.5 * minf(c.unc, 300.0)
		var d := WarSim._flat(c.pos, r.p)
		if d <= lim and d < best_d:
			best_d = d
			best = c
	return best


func _note_ids(c: ContactState, r: Dictionary, idx: Dictionary) -> void:
	if r.uid >= 0:
		var i := c.ids.find(r.uid)
		if i >= 0:
			c.ids_t[i] = r.t
		else:
			if c.ids.size() >= ContactState.MAX_IDS:
				idx.erase(c.ids[0])
				c.ids.remove_at(0)
				c.ids_t.remove_at(0)
			c.ids.append(r.uid)
			c.ids_t.append(r.t)
		idx[r.uid] = c.id
	if r.src == ContactState.Source.SEEN:
		c.strength = maxi(maxi(c.ids.size(), r.str), 1)
	elif r.src == ContactState.Source.OBJECTIVE:
		c.strength = maxi(r.str, 1)
	elif c.reports == 1:
		c.strength = r.str


func _drop_id(c: ContactState, uid: int) -> void:
	var i := c.ids.find(uid)
	if i >= 0:
		c.ids.remove_at(i)
		c.ids_t.remove_at(i)
	var idx: Dictionary = _by_unit.get(c.faction, {})
	idx.erase(uid)


func _erase(c: ContactState, why: String) -> void:
	var idx: Dictionary = _by_unit.get(c.faction, {})
	for uid in c.ids:
		if idx.get(uid, -1) == c.id:
			idx.erase(uid)
	ws.war.contacts[c.faction].erase(c.id)
	_hist(c.faction, c.id, "contact #%d %s" % [c.id, why])


func _evict(tbl: Dictionary) -> void:
	var worst: ContactState = null
	for c: ContactState in tbl.values():
		if worst == null or c.conf < worst.conf:
			worst = c
	if worst:
		_erase(worst, "dropped (table full)")


func _hist(f: int, cid: int, text: String) -> void:
	history.append({"t": snappedf(_state().time, 0.1), "f": f, "id": cid, "text": text})
	if history.size() > HISTORY_MAX:
		history.pop_front()


# --- Queries -------------------------------------------------------------------------------

func contacts_of(f: int) -> Array:
	return ws.war.contacts.get(f, {}).values()


func get_contact(f: int, cid: int) -> ContactState:
	return ws.war.contacts.get(f, {}).get(cid)


## Estimated enemy soldiers faction f believes to be within r of p: each contact counts its
## strength times its current confidence, and a contact whose uncertainty circle reaches into
## the area counts too. 0 when the faction knows of nothing there.
func threat_near(f: int, p: Vector3, r: float) -> int:
	var total := 0.0
	for c: ContactState in contacts_of(f):
		if WarSim._flat(c.pos, p) - 0.5 * c.unc <= r:
			total += c.strength * c.conf
	return ceili(total - 0.25) if total > 0.0 else 0


## Contacts of f within r of p, best (confidence x strength) first.
func contacts_near(f: int, p: Vector3, r: float) -> Array:
	var out := []
	for c: ContactState in contacts_of(f):
		if WarSim._flat(c.pos, p) - 0.5 * c.unc <= r:
			out.append(c)
	out.sort_custom(func(a: ContactState, b: ContactState) -> bool: return a.conf * a.strength > b.conf * b.strength)
	return out


## A squad went to a contact's reported position and found nothing newer than its order:
## the belief is weakened, so the faction stops acting on it.
func clear_contact(f: int, cid: int, since: float) -> bool:
	var c := get_contact(f, cid)
	if c == null or c.t_seen >= since:
		return false
	c.conf0 *= 0.25
	refresh(c, _state().time)
	_hist(f, cid, "contact #%d investigated: nothing found" % cid)
	return true


func counts(f: int) -> Dictionary:
	var out := {"total": 0, "observed": 0, "reported": 0, "stale": 0}
	for c: ContactState in contacts_of(f):
		out.total += 1
		match c.status:
			ContactState.Status.OBSERVED:
				out.observed += 1
			ContactState.Status.REPORTED:
				out.reported += 1
			_:
				out.stale += 1
	return out


func stats() -> Dictionary:
	var n := 0
	for f in ws.war.contacts:
		n += ws.war.contacts[f].size()
	return {"contacts": n, "pending": ws.war.intel_pending.size(), "reports_in": reports_in, "applied": reports_applied, "throttled": reports_throttled,
		"dropped": reports_dropped, "created": created, "merged": merged, "splits": splits, "lost": lost, "sweeps": sweeps,
		"report_us_total": report_usec + group_usec, "group_us": group_usec, "report_us_avg": snappedf(float(report_usec) / maxi(reports_in, 1), 0.2), "sweep_us_avg": snappedf(float(usec) / maxi(sweeps, 1), 0.1), "sweep_us_max": usec_max}
