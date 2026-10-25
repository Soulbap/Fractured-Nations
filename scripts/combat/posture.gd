## COMBAT-01 combat posture: standing, crouching or prone - one state on the soldier record (UnitState.posture,
## posture_from, posture_at; saved) that every system reads through this table:
##   * the eye (where a soldier sees and shoots from) and the points the AI looks and aims at,
##   * the analytic hit volumes of LineOfFire (head sphere, torso capsule, legs capsule when prone),
##   * movement speed (WorldSim.move_speed, the possessed body), weapon steadiness (CombatSim spread, CombatBrain aim),
##   * how much of the soldier stands above the grass (CombatBrain concealment),
## and the character (InfantryCharacter: stand / crouch blend, prone clips; the far proxy mesh) only shows it.
##
## A change of posture takes time (TRANSITION_S): from posture_at the geometry moves from posture_from to posture; while a
## change to or from prone runs the soldier neither walks nor fires. Shapes are given in the soldier's own frame
## (x right, y up, z forward) relative to UnitState.position (the feet; prone: under the hips). The prone numbers are
## measured on the clips (tools/blender/character/char_prone.py prone_layout, build_log.json anim_check.prone).
class_name Posture
extends RefCounted

const STAND := 0
const CROUCH := 1
const PRONE := 2
const NAMES: Array[String] = ["standing", "crouching", "prone"]

## Seconds to go from [from] to [to].
const TRANSITION_S := [[0.0, 0.35, 1.0], [0.35, 0.0, 0.8], [1.1, 0.9, 0.0]]
## Share of the walking speed (crouch walk ~2.5 m/s, prone crawl ~0.8 m/s at the 4.5 m/s baseline).
const SPEED: Array[float] = [1.0, 0.55, 0.18]
## Weapon steadiness: multiplies the weapon's spread and bloom (CombatSim) and the AI's aim error (CombatBrain).
const STEADY: Array[float] = [1.0, 0.85, 0.65]
## A braced weapon (WeaponDef.settle_s > 0: bipod) counts as settled after this when prone.
const PRONE_SETTLE_S := 0.6

const EYE: Array[Vector3] = [Vector3(0, 1.60, 0.0), Vector3(0, 1.10, 0.12), Vector3(0.10, 0.36, 0.70)]
const HEAD: Array[Vector3] = [Vector3(0, 1.62, 0.0), Vector3(0, 1.12, 0.14), Vector3(0.05, 0.40, 0.65)]
const HEAD_R := 0.14
const TORSO_A: Array[Vector3] = [Vector3(0, 0.30, 0.0), Vector3(0, 0.32, 0.0), Vector3(0, 0.14, -0.02)]
const TORSO_B: Array[Vector3] = [Vector3(0, 1.20, 0.0), Vector3(0, 0.74, 0.10), Vector3(0, 0.25, 0.40)]
const TORSO_R: Array[float] = [0.30, 0.30, 0.19]
## Legs as their own capsule only when prone (standing and crouched the torso capsule reaches the ground).
const LEGS_A: Array[Vector3] = [Vector3(0, 0.30, 0.0), Vector3(0, 0.30, 0.0), Vector3(0, 0.12, -0.14)]
const LEGS_B: Array[Vector3] = [Vector3(0, 0.30, 0.0), Vector3(0, 0.30, 0.0), Vector3(0, 0.10, -0.86)]
const LEGS_R: Array[float] = [0.0, 0.0, 0.12]
## Where the AI looks for and aims at a soldier: torso, head.
const AIM_TORSO: Array[Vector3] = [Vector3(0, 1.10, 0.0), Vector3(0, 0.66, 0.06), Vector3(0, 0.21, 0.25)]
const AIM_HEAD: Array[Vector3] = [Vector3(0, 1.55, 0.0), Vector3(0, 1.08, 0.14), Vector3(0.05, 0.40, 0.64)]
## Height of the top of the soldier above the ground (grass concealment).
const TOP: Array[float] = [1.78, 1.24, 0.50]
## Horizontal reach of the hit volumes from UnitState.position (candidate filters).
const REACH: Array[float] = [0.6, 0.6, 1.05]

## Simulation time (WorldState.time), set by WorldSim every tick: static helpers without a clock (CombatSim.eye_of) read it.
static var now := 0.0


## 0..1: how far the current change of posture has come (1 = settled).
static func progress(u: UnitState, t := NAN) -> float:
	if is_nan(t):
		t = now
	if u.posture_from == u.posture:
		return 1.0
	var dur: float = TRANSITION_S[u.posture_from][u.posture]
	return clampf((t - u.posture_at) / maxf(dur, 0.01), 0.0, 1.0)


static func settled(u: UnitState, t := NAN) -> bool:
	return progress(u, t) >= 1.0


## A change to or from prone is under way: the soldier neither walks nor fires.
static func busy(u: UnitState, t := NAN) -> bool:
	return (u.posture == PRONE or u.posture_from == PRONE) and u.posture != u.posture_from and progress(u, t) < 1.0


## The posture the soldier is mostly in right now (the target once half way).
static func current(u: UnitState, t := NAN) -> int:
	return u.posture if progress(u, t) >= 0.5 else u.posture_from


## Asks for posture p. Returns false (nothing changes) while a change to or from prone is still running - getting down
## or up takes its time and cannot be cut short; a change between standing and crouching may be turned round at once.
static func request(u: UnitState, p: int, t := NAN) -> bool:
	if is_nan(t):
		t = now
	if u.posture == p and settled(u, t):
		return true
	if busy(u, t):
		return u.posture == p
	if u.posture == p:
		return true
	u.posture_from = current(u, t)
	u.posture = p
	u.posture_at = t
	if u.posture_from == p:
		u.posture_at = t - 999.0
	return true


## The posture a soldier moves in: a short shift keeps a prone crawl (3 m) or a crouch (8 m), anything longer is walked
## standing. Every move of the AI goes through here (WorldState.issue_move, CombatBrain reactions).
static func for_move(u: UnitState, dist: float, t := NAN) -> void:
	var p := current(u, t)
	if p == PRONE and dist <= 3.0:
		return
	if p != STAND and dist <= 8.0:
		request(u, CROUCH, t)
		return
	request(u, STAND, t)


## Sets the posture at once (spawning, tests, loading old saves).
static func set_now(u: UnitState, p: int) -> void:
	u.posture = p
	u.posture_from = p
	u.posture_at = -1.0e9


static func _blend_v(tab: Array[Vector3], u: UnitState, t: float) -> Vector3:
	var k := progress(u, t)
	return tab[u.posture_from].lerp(tab[u.posture], k)


static func _blend_f(tab: Array[float], u: UnitState, t: float) -> float:
	return lerpf(tab[u.posture_from], tab[u.posture], progress(u, t))


## The soldier's frame point (x right, y up, z forward) in world space.
static func to_world(u: UnitState, v: Vector3) -> Vector3:
	var f := Vector3(-sin(u.yaw), 0.0, -cos(u.yaw))
	var r := Vector3(cos(u.yaw), 0.0, -sin(u.yaw))
	return u.position + r * v.x + Vector3.UP * v.y + f * v.z


static func eye(u: UnitState, t := NAN) -> Vector3:
	return to_world(u, _blend_v(EYE, u, now if is_nan(t) else t))


## Eye height above the feet (the first-person camera).
static func eye_local(u: UnitState, t := NAN) -> Vector3:
	return _blend_v(EYE, u, now if is_nan(t) else t)


## Where to look at / aim for the soldier: its head (true) or torso.
static func aim_point(u: UnitState, head: bool, t := NAN) -> Vector3:
	return to_world(u, _blend_v(AIM_HEAD if head else AIM_TORSO, u, now if is_nan(t) else t))


static func top(u: UnitState, t := NAN) -> float:
	return _blend_f(TOP, u, now if is_nan(t) else t)


static func reach(u: UnitState) -> float:
	return maxf(REACH[u.posture], REACH[u.posture_from])


static func steady(u: UnitState, t := NAN) -> float:
	return _blend_f(STEADY, u, now if is_nan(t) else t)


static func speed_mult(u: UnitState, t := NAN) -> float:
	if busy(u, t):
		return 0.0
	return minf(SPEED[u.posture], SPEED[u.posture_from]) if not settled(u, t) else SPEED[u.posture]


## The soldier's long axis, low end to head (near misses, friends in the line of fire): standing feet to head, prone
## feet behind to head in front.
static func span(u: UnitState, t := NAN) -> Array[Vector3]:
	if is_nan(t):
		t = now
	var low := _blend_v(LEGS_B, u, t) if _blend_f(LEGS_R, u, t) > 0.02 else Vector3(0, 0.1, 0)
	return [to_world(u, low), to_world(u, _blend_v(HEAD, u, t))]


## Hit of a segment on the soldier's volumes: {d, zone (LineOfFire.Zone)}.
static func hit(from: Vector3, to: Vector3, u: UnitState, t := NAN) -> Dictionary:
	if is_nan(t):
		t = now
	var best := {"d": INF, "zone": LineOfFire.Zone.NONE}
	var hs := Geometry3D.segment_intersects_sphere(from, to, to_world(u, _blend_v(HEAD, u, t)), HEAD_R)
	if not hs.is_empty():
		best.d = from.distance_to(hs[0])
		best.zone = LineOfFire.Zone.HEAD
	var bd := LineOfFire.segment_capsule(from, to, to_world(u, _blend_v(TORSO_A, u, t)), to_world(u, _blend_v(TORSO_B, u, t)), _blend_f(TORSO_R, u, t))
	if bd >= 0.0 and bd < best.d:
		best.d = bd
		best.zone = LineOfFire.Zone.BODY
	var lr := _blend_f(LEGS_R, u, t)
	if lr > 0.02:
		var ld := LineOfFire.segment_capsule(from, to, to_world(u, _blend_v(LEGS_A, u, t)), to_world(u, _blend_v(LEGS_B, u, t)), lr)
		if ld >= 0.0 and ld < best.d:
			best.d = ld
			best.zone = LineOfFire.Zone.BODY
	return best
