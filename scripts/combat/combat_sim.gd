## The one combat authority (COMBAT-01a): firing, reloading, damage and death.
##
## Every shot - from the possessed soldier's mouse or, later, from AI - goes through
## request_fire(unit_id, origin, direction, source). Weapon numbers come from a static
## WeaponDef; magazine, reserve, cooldown, reload, spread bloom, health and alive live in
## the UnitState, with simulation time (WorldState.time) for every timer, so the state is
## the same with or without a body, across possession, tier changes and save / load.
##
## A shot is one event, resolved once against world data and unit records by
## LineOfFire, and its damage applied once to the target record. Bodies never apply
## damage, so a soldier being promoted or demoted mid-burst cannot be hit twice.
## Effects listen to WorldState.shot_fired and do nothing authoritative.
class_name CombatSim
extends RefCounted

enum Source { AI, PLAYER }
enum Zone { NONE, BODY, HEAD }

const WEAPON_DIR := "res://assets/combat/%s.tres"
## Eye height of a soldier record (origin of shots from units without a camera).
const EYE_HEIGHT := 1.6

var sim: WorldSim
var line: LineOfFire = LineOfFire.new()
var _weapons := {}
## Cost of the last resolved shot (usec) and running totals, for measurements.
var last_shot_usec := 0
var shots_total := 0
var shot_usec_total := 0
var shot_usec_max := 0
## GAMEPLAY-02C: explosives launched / burst, and the slowest burst (us).
var launched := 0
var detonated := 0
## GAMEPLAY-03D: a soldier down against a burst: the height the fragments are traced to and the share of them that reach him.
var blast_down_height := 0.35
var blast_down_factor := 0.5
var blast_usec_max := 0


func _init(p_sim: WorldSim) -> void:
	sim = p_sim


func weapon(id: StringName) -> WeaponDef:
	if id == &"":
		return null
	if not _weapons.has(id):
		var path := WEAPON_DIR % id
		_weapons[id] = load(path) as WeaponDef if ResourceLoader.exists(path) else null
	return _weapons[id]


## Gives every soldier without a weapon a full rifle (spawn; saves keep their state).
func equip_all(id: StringName) -> void:
	var def := weapon(id)
	if def == null:
		push_error("CombatSim: weapon %s missing" % id)
		return
	for u: UnitState in sim.state.units.values():
		if u.kind == UnitState.Kind.SOLDIER and u.weapon_id == &"":
			u.weapon_id = id
			u.mag = def.magazine_size
			u.reserve = def.reserve_start
			u.fire_auto = def.default_mode == WeaponDef.FireMode.AUTO and def.allow_auto


## GAMEPLAY-02B: gives the soldiers of a squad that have no role yet (fresh squads, replacements) their role from the
## scenario's squad composition (WarState.rules "squad_composition", default "standard"): a fresh squad by position, a
## replacement fills a role the squad lacks first (a squad that lost its machine gunner gets the next recruit as one),
## everybody else a rifleman. Soldiers that already have a role keep it and their weapon: veterans are never re-armed.
## only: when given, just these soldiers (the new recruits) are equipped; the others count with their weapon (a soldier of
## an old save without a role counts by its weapon). comp_override: another composition (a scenario squad). Returns how
## many soldiers got a role.
func apply_composition(sq: SquadState, only: Array = [], comp_override := "") -> int:
	var comp_id := "standard"
	if sim.state.war and sim.state.war.active:
		comp_id = String(sim.state.war.rule("squad_composition", "standard"))
	if comp_override != "":
		comp_id = comp_override
	elif sim.war and sim.war.dev and sim.war.dev.enabled():
		# GAMEPLAY-04C: an AI faction arms new soldiers with the first composition of the scenario's list it can field - every
		# role developed and its weapons issued at one of its bases (the player's rule; the player equips his own: 04D).
		var f := sim.state.war.faction(sq.faction)
		if f and not f.player:
			for cid in sim.state.war.rule("ai_compositions", []):
				var c := SquadComposition.by_id(String(cid))
				if c and c.slots.all(func(r: StringName) -> bool: return sim.war.dev.role_usable(sq.faction, r) == ""):
					comp_id = String(cid)
					break
	var comp := SquadComposition.by_id(comp_id)
	var slots: Array[StringName] = comp.slots if comp else ([] as Array[StringName])
	var fresh: Array = []
	var have := {}
	for i in sq.members.size():
		var u := sim.state.get_unit(sq.members[i])
		if u == null or u.kind != UnitState.Kind.SOLDIER:
			continue
		if u.role == &"" and (only.is_empty() or only.has(u.id)):
			fresh.append([i, u])
		elif u.alive:
			var r := u.role
			if r == &"":
				r = &"machine_gunner" if weapon(u.weapon_id) and weapon(u.weapon_id).role == &"lmg" else &"rifleman"
			have[r] = int(have.get(r, 0)) + 1
	if fresh.is_empty():
		return 0
	var want := {}
	for i in mini(slots.size(), sq.members.size()):
		want[slots[i]] = int(want.get(slots[i], 0)) + 1
	var given := {}
	# A fresh soldier first takes the role of its own slot when the squad still lacks it, then any lacking role.
	for e: Array in fresh:
		var i: int = e[0]
		if i < slots.size():
			var r: StringName = slots[i]
			if int(have.get(r, 0)) + int(given.get(r, 0)) < int(want.get(r, 0)):
				given[r] = int(given.get(r, 0)) + 1
				_equip_role(e[1], r)
	for e: Array in fresh:
		var u: UnitState = e[1]
		if u.role != &"":
			continue
		var pick: StringName = &"rifleman"
		for r: StringName in want:
			if r != &"rifleman" and int(have.get(r, 0)) + int(given.get(r, 0)) < int(want[r]):
				pick = r
				break
		given[pick] = int(given.get(pick, 0)) + 1
		_equip_role(u, pick)
	return fresh.size()


## Gives a soldier a role: its weapon with a full load, its grenades and secondary weapon, and the role's look.
func _equip_role(u: UnitState, role_id: StringName) -> void:
	var role := InfantryRole.by_id(role_id)
	u.role = role_id
	if role:
		u.grenades = role.grenades
		u.sec_id = role.secondary_id
		u.sec_ammo = role.secondary_rounds
		u.sec_active = false
	var wid: StringName = role.weapon_id if role else &"rifle"
	var def := weapon(wid)
	if def == null:
		wid = &"rifle"
		def = weapon(wid)
	if def and (u.weapon_id != wid or u.weapon_id == &""):
		u.weapon_id = wid
		u.mag = def.magazine_size
		u.reserve = def.reserve_start
		u.fire_auto = def.default_mode == WeaponDef.FireMode.AUTO and def.allow_auto
	if role:
		var lo := role.loadout_for(u.faction)
		if lo != "" and lo != u.loadout:
			u.loadout = lo
			# GAMEPLAY-04D: a soldier re-equipped while shown looks the part at once (body or far proxy).
			var view := sim.view_of(u.id)
			if view and view.has_method("refresh_look"):
				view.refresh_look()


# --- Firing -------------------------------------------------------------------------

## Pulls the trigger once. Returns {fired: bool, reason, ...shot}. The caller decides
## when (semi: on press, auto: while held); the weapon decides whether a round leaves.
func request_fire(unit_id: int, origin: Vector3, direction: Vector3, source := Source.AI) -> Dictionary:
	var u := sim.state.get_unit(unit_id)
	if u == null or not u.alive:
		return {"fired": false, "reason": "dead"}
	# Exactly one controller per soldier: the player for the possessed one, AI otherwise.
	if (source == Source.PLAYER) != u.player_controlled:
		return {"fired": false, "reason": "not_controller"}
	var def := weapon(u.weapon_id)
	if def == null:
		return {"fired": false, "reason": "unarmed"}
	var now := sim.state.time
	if u.is_reloading():
		return {"fired": false, "reason": "reloading"}
	if now < u.next_shot_at:
		return {"fired": false, "reason": "cooldown"}
	if u.mag <= 0:
		request_reload(unit_id)
		return {"fired": false, "reason": "empty"}
	u.mag -= 1
	u.shot_counter += 1
	u.next_shot_at = now + def.fire_interval()
	var spread := current_spread(u, def)
	u.bloom = minf(maxf(u.bloom - def.spread_recovery_deg_s * (now - u.last_shot_at), 0.0) + def.spread_bloom_deg, def.spread_bloom_max_deg)
	u.last_shot_at = now
	var dir := spread_direction(direction.normalized(), spread, sim.state.world_seed, u.id, u.shot_counter)
	var shot := resolve(u, def, origin, dir)
	shot["fired"] = true
	shot["spread_deg"] = spread
	if u.mag == 0 and u.reserve > 0:
		request_reload(unit_id)
	sim.state.shot_fired.emit(shot)
	return shot


## Resolves the travel and the damage of one shot (no ammo or cooldown handling).
func resolve(u: UnitState, def: WeaponDef, origin: Vector3, dir: Vector3) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var r := line.trace(origin, origin + dir * def.max_range, u.id)
	last_shot_usec = Time.get_ticks_usec() - t0
	shots_total += 1
	shot_usec_total += last_shot_usec
	shot_usec_max = maxi(shot_usec_max, last_shot_usec)
	var shot := {"shooter": u.id, "origin": origin, "dir": dir, "end": r.point, "distance": r.distance,
		"blocker": r.blocker, "hit_unit": r.hit_unit, "zone": r.zone, "structure_id": r.structure_id,
		"damage": 0.0, "killed": false, "counter": u.shot_counter, "usec": last_shot_usec}
	if r.blocker == "structure" and int(r.structure_id) >= 0:
		# GAMEPLAY-01F: the structure in the way takes the hit (weighed by what it is made of).
		var st := sim.state.construction.get_structure(int(r.structure_id))
		if st:
			shot["structure_damage"] = sim.state.construction.damage(st, def.damage * def.structure_mult * StructureHealth.resist(st.type_id))
	if r.hit_unit > 0:
		var amount: float = def.damage * def.zone_multiplier(r.zone) * def.falloff(r.distance)
		shot.damage = apply_damage(r.hit_unit, amount, r.zone, u.id)
		var t := sim.state.get_unit(r.hit_unit)
		shot.killed = t != null and not t.alive and t.killer_id == u.id and t.died_at == sim.state.time
	return shot


## What shot number `counter` of a unit would do from origin along direction with the
## given spread - the same seed and the same world data as request_fire, but no ammo,
## no damage and no events. Used to check reproducibility (and later by AI to judge a
## line of fire).
func preview_shot(unit_id: int, origin: Vector3, direction: Vector3, counter: int, spread_deg: float) -> Dictionary:
	var u := sim.state.get_unit(unit_id)
	var def := weapon(u.weapon_id) if u else null
	if def == null:
		return {}
	var dir := spread_direction(direction.normalized(), spread_deg, sim.state.world_seed, unit_id, counter)
	var r := line.trace(origin, origin + dir * def.max_range, unit_id)
	return {"end": r.point, "distance": r.distance, "blocker": r.blocker, "hit_unit": r.hit_unit, "zone": r.zone, "dir": dir}


## The spread (degrees) the next shot of u gets: base + movement + recovered bloom.
func current_spread(u: UnitState, def: WeaponDef) -> float:
	var speed := Vector2(u.velocity.x, u.velocity.z).length()
	var bloom := maxf(u.bloom - def.spread_recovery_deg_s * (sim.state.time - u.last_shot_at), 0.0)
	return (def.spread_base_deg + bloom) * settle_factor(u, def) + def.spread_moving_deg * clampf(speed / 4.5, 0.0, 1.5)


## GAMEPLAY-02B: a braced weapon (WeaponDef.settle_s > 0: bipod, prone) held still for settle_s shoots tighter.
func settle_factor(u: UnitState, def: WeaponDef) -> float:
	if def.settle_s <= 0.0 or sim.state.time - u.moved_at < def.settle_s:
		return 1.0
	return def.settled_mult


## Direction inside a cone of half-angle spread_deg around dir, from a seed built from the
## world seed, the shooter and its shot number: the same shot always deviates the same way.
static func spread_direction(dir: Vector3, spread_deg: float, world_seed: int, unit_id: int, counter: int) -> Vector3:
	if spread_deg <= 0.0:
		return dir
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, unit_id, counter])
	var angle := deg_to_rad(spread_deg) * sqrt(rng.randf())
	var phi := rng.randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir * cos(angle) + (side * cos(phi) + up * sin(phi)) * sin(angle)).normalized()


func set_fire_mode(unit_id: int, auto: bool) -> bool:
	var u := sim.state.get_unit(unit_id)
	var def := weapon(u.weapon_id) if u else null
	if def == null or (auto and not def.allow_auto):
		return false
	u.fire_auto = auto
	return true


# --- Explosives (GAMEPLAY-02C) ----------------------------------------------------------------------------------------------
# A hand grenade or a rocket is an entry of WorldState.explosives from the moment it leaves the hand / the tube until it
# bursts: plain data, stepped here every tick and saved, so near and far, possession and a save in mid-flight give the
# same result. No physics body flies: a grenade lands where it was aimed (with scatter), a rocket where its line first
# meets something (LineOfFire, the shot rules). The burst is one bounded query: soldiers from the CombatBrain grid,
# structures from the StructureManager cell index, each soldier's cover checked with one line.

## Throws one of u's grenades at `target` (a point the thrower chose: what it saw or was told, never a hidden enemy's true
## position). Returns {ok, reason, e}.
func throw_grenade(unit_id: int, target: Vector3, source := Source.AI) -> Dictionary:
	var u := sim.state.get_unit(unit_id)
	if u == null or not u.alive:
		return {"ok": false, "reason": "dead"}
	if (source == Source.PLAYER) != u.player_controlled:
		return {"ok": false, "reason": "not_controller"}
	var def := weapon(&"grenade")
	if def == null or u.grenades <= 0:
		return {"ok": false, "reason": "no grenades"}
	var now := sim.state.time
	if now - u.nade_at < 1.5 or u.is_reloading():
		return {"ok": false, "reason": "busy"}
	var from := eye_of(u)
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	var d := flat.length()
	if d < 2.0:
		return {"ok": false, "reason": "too close"}
	if d > def.max_range:
		flat = flat / d * def.max_range
		d = def.max_range
	# The first metres of the throw must be free (no wall in the thrower's face); over a parapet is fine.
	var first := line.trace(from, from + (flat / d) * 2.5 + Vector3.UP * 0.6, u.id, false)
	if first.blocker != "range":
		return {"ok": false, "reason": "blocked"}
	# Where it lands: seeded scatter growing with the throw (and with the thrower's suppression).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.state.world_seed, u.id, u.shot_counter + 1, 5303])
	var sigma := 0.8 + d * 0.06 + 2.0 * u.suppression_at(now)
	var land := from + flat + Vector3(rng.randfn(0.0, sigma), 0.0, rng.randfn(0.0, sigma))
	land.y = sim.tactics.pos.ground(land).y if sim.tactics else target.y
	u.grenades -= 1
	u.nade_at = now
	u.shot_counter += 1
	return {"ok": true, "e": _launch(u, &"grenade", from, land, now + def.fuse_s)}


## Fires the secondary weapon (a rocket) from origin along direction, like request_fire: the round flies straight to the
## first thing in its way. Returns {fired, reason, e}.
## aim_dist: for a lobbed weapon (a grenade launcher, WeaponDef role &"gl") the distance it was aimed at - the round comes down
## there (or on whatever it meets first) instead of flying on to its maximum range.
func fire_secondary(unit_id: int, origin: Vector3, direction: Vector3, source := Source.AI, aim_dist := -1.0) -> Dictionary:
	var u := sim.state.get_unit(unit_id)
	if u == null or not u.alive:
		return {"fired": false, "reason": "dead"}
	if (source == Source.PLAYER) != u.player_controlled:
		return {"fired": false, "reason": "not_controller"}
	var def := weapon(u.sec_id)
	if def == null:
		return {"fired": false, "reason": "no secondary weapon"}
	var now := sim.state.time
	if u.sec_ammo <= 0:
		return {"fired": false, "reason": "empty"}
	if now < u.sec_ready_at or u.is_reloading():
		return {"fired": false, "reason": "cooldown"}
	u.sec_ammo -= 1
	u.shot_counter += 1
	u.sec_ready_at = now + def.reload_time
	# Moving spoils the aim; standing (a shuffle under 0.6 m/s, as UnitState.moved_at counts it) does not.
	var spread := def.spread_base_deg + def.spread_moving_deg * clampf((Vector2(u.velocity.x, u.velocity.z).length() - 0.6) / 3.9, 0.0, 1.5)
	var dir := spread_direction(direction.normalized(), spread, sim.state.world_seed, u.id, u.shot_counter)
	var reach := def.max_range
	if def.role == &"gl" and aim_dist > 0.0:
		reach = minf(aim_dist + 1.0, def.max_range)
	var r := line.trace(origin, origin + dir * reach, u.id)
	var at: Vector3 = r.point - dir * 0.2
	var e := _launch(u, def.id, origin, at, now + r.distance / maxf(def.projectile_speed, 1.0))
	e["hit_structure"] = int(r.structure_id) if r.blocker == "structure" else -1
	e["blocker"] = String(r.blocker)
	return {"fired": true, "e": e, "blocker": r.blocker}


func _launch(u: UnitState, def_id: StringName, from: Vector3, at: Vector3, t: float) -> Dictionary:
	var e := {"id": sim.state.next_explosive_id(), "def": String(def_id), "src": u.id, "f": u.faction, "from": from, "at": at,
		"t0": sim.state.time, "t": t}
	sim.state.explosives.append(e)
	sim.state.explosive_launched.emit(e)
	launched += 1
	return e


## Bursts every explosive whose time has come (every physics tick, from update).
func _step_explosives() -> void:
	var list := sim.state.explosives
	if list.is_empty():
		return
	var now := sim.state.time
	var i := 0
	while i < list.size():
		var e: Dictionary = list[i]
		if now >= float(e.t):
			list.remove_at(i)
			detonate(e)
		else:
			i += 1


## The burst of explosive e at e.at: blast damage to soldiers (falloff with distance, cut to a tenth behind cover), damage
## to structures (blast_structure x blast_resist, falloff from the nearest part of the structure), suppression and a
## reaction (under fire) for every soldier within twice the radius. Friends are hurt as much as enemies. Emits exploded.
func detonate(e: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var def := weapon(StringName(e.def))
	if def == null:
		return e
	var at: Vector3 = e.at
	var src := int(e.src)
	var r := def.blast_radius
	var centre := at + Vector3.UP * 0.35
	var hits: Array = []
	var now := sim.state.time
	for u: UnitState in sim.brain.units_near(at, r * 2.0):
		if not u.alive or u.kind != UnitState.Kind.SOLDIER:
			continue
		# GAMEPLAY-03D: a soldier flat on the ground (down_until) is reached lower (low cover shields him) and by fewer fragments.
		var down := now < u.down_until
		var chest := u.position + Vector3.UP * (blast_down_height if down else 1.0)
		var d := centre.distance_to(chest)
		if d > r * 2.0:
			continue
		# Suppression and the reaction reach twice as far as the fragments.
		if def.blast_suppression > 0.0 and not u.player_controlled:
			u.add_suppression(def.blast_suppression * clampf(1.0 - d / (r * 2.0), 0.0, 1.0), now)
			sim.brain.under_fire_from(u, at)
		if d > r:
			continue
		var f := pow(1.0 - d / r, 1.4)
		var cover := line.trace(centre, chest, -1, false)
		var shielded: bool = cover.blocker != "range" and float(cover.distance) < d - 0.4
		if shielded:
			f *= 0.1
		if down:
			f *= blast_down_factor
		var dmg := def.blast_damage * f
		if dmg >= 1.0:
			var done := apply_damage(u.id, dmg, Zone.BODY, src)
			hits.append({"id": u.id, "f": u.faction, "d": snappedf(d, 0.1), "dmg": snappedf(done, 0.1), "cover": shielded, "killed": not u.alive})
	var structs: Array = []
	if def.blast_structure > 0.0:
		for hit: Dictionary in line.structures_near(at, r):
			var st := sim.state.construction.get_structure(int(hit.id))
			if st == null:
				continue
			var f := clampf(1.0 - float(hit.d) / r, 0.0, 1.0)
			if int(e.get("hit_structure", -1)) == st.id:
				f = 1.0  # a rocket that struck it
			var amount := def.blast_structure * f * StructureHealth.blast_resist(st.type_id)
			var done := sim.state.construction.damage(st, amount)
			if done > 0.0:
				structs.append({"id": st.id, "type": String(st.type_id), "dmg": snappedf(done, 0.1), "frac": snappedf(st.health_frac(), 0.01)})
	e["hits"] = hits
	e["structures"] = structs
	e["burst_at"] = now
	detonated += 1
	blast_usec_max = maxi(blast_usec_max, Time.get_ticks_usec() - t0)
	sim.state.exploded.emit(e)
	return e


# --- Reloading ----------------------------------------------------------------------

func request_reload(unit_id: int) -> bool:
	var u := sim.state.get_unit(unit_id)
	if u == null or not u.alive or u.is_reloading():
		return false
	var def := weapon(u.weapon_id)
	if def == null or u.mag >= def.magazine_size or u.reserve <= 0:
		return false
	u.reload_until = sim.state.time + def.reload_time
	sim.state.reload_started.emit(u)
	return true


## Completes reloads whose time has come (called every physics tick by WorldSim).
func update(_delta: float) -> void:
	var now := sim.state.time
	_step_explosives()
	for u: UnitState in sim.state.units.values():
		if u.velocity.x * u.velocity.x + u.velocity.z * u.velocity.z > 0.36:
			u.moved_at = now
		if u.reload_until >= 0.0 and now >= u.reload_until:
			u.reload_until = -1.0
			if not u.alive:
				continue
			var def := weapon(u.weapon_id)
			if def == null:
				continue
			var take := mini(def.magazine_size - u.mag, u.reserve)
			u.mag += take
			u.reserve -= take
			sim.state.reload_finished.emit(u)


# --- Damage and death ---------------------------------------------------------------

## Applies damage to a living soldier record once. Returns the damage applied.
func apply_damage(target_id: int, amount: float, zone: int, source_id := -1) -> float:
	var t := sim.state.get_unit(target_id)
	if t == null or not t.alive or amount <= 0.0:
		return 0.0
	var applied := minf(amount, t.health)
	t.health -= applied
	sim.state.unit_damaged.emit(t, applied, zone, source_id)
	if t.health <= 0.0:
		kill(t, source_id)
	return applied


## Death: the record stays (identity, position, killer) but stops moving, fighting and
## taking orders, and leaves its squad's formation.
func kill(t: UnitState, source_id := -1) -> void:
	if not t.alive:
		return
	t.alive = false
	t.health = 0.0
	t.died_at = sim.state.time
	t.killer_id = source_id
	t.order = UnitState.Order.NONE
	t.move_state = UnitState.MoveState.IDLE
	t.velocity = Vector3.ZERO
	t.reload_until = -1.0
	t.ai_state = UnitState.AiState.DEAD
	t.target_id = -1
	t.target_visible = false
	t.burst_left = 0
	t.clear_reaction()
	sim.state.mark_fallen(t.id)
	sim.state.unit_died.emit(t)


## Eye position of a soldier record (shots and sight lines of units without a camera).
static func eye_of(u: UnitState) -> Vector3:
	return u.position + Vector3.UP * EYE_HEIGHT
