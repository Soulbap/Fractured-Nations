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
	return def.spread_base_deg + def.spread_moving_deg * clampf(speed / 4.5, 0.0, 1.5) + bloom


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
	for u: UnitState in sim.state.units.values():
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
