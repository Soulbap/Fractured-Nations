## COMBAT-COVER-03: the one judgement of a soldier's position against the threats he is believed to face - used by the soldiers'
## own cover reactions (CombatBrain), the squad tactics' post searches (SquadPositions) and the player's placement preview (RTS),
## so the green marker the player sees is what the soldier will act on.
##
## Two separate answers, Company of Heroes style but on real geometry (LineOfFire: buildings, walls, rocks, logs, terrain):
##   level  HEAVY  a hard solid (wall, building, rock, sandbag, earth bank) stops both shoulder lines of the crouched soldier;
##          LIGHT  partial protection - a trunk, light cover (bales, pallets: VegetationMeshDef.cover_class 1), the edge of a
##                 solid (one shoulder line free: a corner), cover that works only lying down, or concealment by foliage
##                 that stops eyes but not bullets ("concealed");
##          NONE   nothing between him and the threat;
##          UNKNOWN no threat direction known (nothing to judge against).
##   fire   CLEAR / BLOCKED: whether his eye line (crouched; standing behind cover taller than his crouched eye) reaches the
##          threat - a wall can protect perfectly and still leave him nothing to shoot at.
## Direction is everything: every answer is against a believed threat position (a contact, a report, the facing the player
## gave), never against a hidden soldier's true position. Several threats: the worst protection and the best fire count.
class_name CoverEval
extends RefCounted

enum Level { UNKNOWN = -1, NONE = 0, LIGHT = 1, HEAVY = 2 }
enum Fire { UNKNOWN = -1, BLOCKED = 0, CLEAR = 1 }

const LEVEL_NAMES := {Level.UNKNOWN: "unknown", Level.NONE: "exposed", Level.LIGHT: "light cover", Level.HEAVY: "heavy cover"}

## A solid this close in front of the soldier is his cover (m); terrain counts farther out (a crest, a bank).
var contact_m := 6.0
var terrain_m := 15.0
## Half the width of the body lines (m): one from each shoulder of the crouched torso towards the threat.
var shoulder_m := 0.24
## How far the eye line is followed towards the threat when judging fire (m): beyond, the ground between is the fight's business.
var fire_check_m := 90.0
## Foliage layers on the first metres of the line that count as concealment (light cover without protection).
var conceal_layers := 2
var conceal_m := 30.0

var sim: WorldSim
var evals := 0


func _init(p_sim: WorldSim) -> void:
	sim = p_sim


## Judges a spot p (ground) against one threat position. low_ok: cover that protects only a prone soldier counts (LIGHT, "low").
## Returns {protected, low, can_fire, level, fire, blocker, partial, concealed, stand}. `protected` and `can_fire` keep their
## WORLD-COVER-01 meaning (physical protection of the crouched / prone soldier; a free eye line).
func judge(p: Vector3, threat: Vector3, low_ok := true) -> Dictionary:
	if not threat.is_finite():
		return {"protected": false, "low": false, "can_fire": true, "level": Level.UNKNOWN, "fire": Fire.UNKNOWN, "blocker": "",
			"partial": false, "concealed": false, "stand": false}
	evals += 1
	var line := sim.combat.line
	var t_eye := threat + Vector3.UP * CombatSim.EYE_HEIGHT
	var dist := _flat(p, threat)
	var torso := p + Vector3.UP * Posture.AIM_TORSO[Posture.CROUCH].y
	var reach := minf(maxf(contact_m, terrain_m), dist - 1.0)
	var out := {"protected": false, "low": false, "can_fire": true, "level": Level.NONE, "fire": Fire.CLEAR, "blocker": "",
		"partial": false, "concealed": false, "stand": false}
	if reach <= 0.5:
		return out
	var dir := (t_eye - torso).normalized()
	var r1 := line.trace(torso, torso + dir * reach, -1, false)
	var low := false
	var hit := r1
	if not _covers(r1):
		if not low_ok:
			out.fire = _fire(p, t_eye, dist, Posture.CROUCH, out)
			out.can_fire = out.fire == Fire.CLEAR
			return _concealment(out, p, dir)
		# WORLD-COVER-01.1: low cover - a hollow, a bank, a log - protects a soldier lying down.
		var pt := p + Vector3.UP * Posture.AIM_TORSO[Posture.PRONE].y
		var rp := line.trace(pt, pt + (t_eye - pt).normalized() * reach, -1, false)
		if not _covers(rp):
			out.fire = _fire(p, t_eye, dist, Posture.CROUCH, out)
			out.can_fire = out.fire == Fire.CLEAR
			return _concealment(out, p, dir)
		low = true
		hit = rp
	out.protected = true
	out.low = low
	out.blocker = hit.blocker
	# Both shoulders behind it? One free = the edge of the solid (a corner): partial protection.
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * shoulder_m
	var base := (p + Vector3.UP * Posture.AIM_TORSO[Posture.PRONE if low else Posture.CROUCH].y)
	var partial := false
	for s: Vector3 in [side, -side]:
		if not _covers(line.trace(base + s, base + s + dir * reach, -1, false)):
			partial = true
			break
	out.partial = partial
	var hard: bool = hit.blocker == "structure" or hit.blocker == "terrain" or (hit.blocker == "tree" and float(hit.get("solid", 0.0)) in [1.0, 2.0])
	out.level = Level.HEAVY if hard and not partial and not low else Level.LIGHT
	out.fire = _fire(p, t_eye, dist, Posture.PRONE if low else Posture.CROUCH, out)
	out.can_fire = out.fire == Fire.CLEAR
	return out


## Judges p against several believed threats: the worst protection, the best fire, `against` = the index of the threat the level
## came from. No threats: UNKNOWN (with the answers of `fallback` when it is finite - the facing the player gave, "assumed").
func judge_all(p: Vector3, threats: Array, fallback := Vector3.INF) -> Dictionary:
	if threats.is_empty():
		var r := judge(p, fallback)
		r["assumed"] = true
		return r
	var worst := {}
	var best_fire := Fire.BLOCKED
	for i in threats.size():
		var r := judge(p, threats[i])
		if worst.is_empty() or int(r.level) < int(worst.level):
			worst = r
			worst["against"] = i
		best_fire = maxi(best_fire, int(r.fire))
	worst.fire = best_fire
	worst.can_fire = best_fire == Fire.CLEAR
	worst["assumed"] = false
	return worst


## A solid close enough in front to be cover (terrain may be farther: a crest).
func _covers(r: Dictionary) -> bool:
	if not (r.blocker in ["structure", "terrain", "tree"]):
		return false
	return float(r.distance) <= (terrain_m if r.blocker == "terrain" else contact_m)


## Fire from p towards the threat's eye: the posture's eye line, followed fire_check_m; blocked within 4 m by the soldier's own
## cover while crouched, the standing eye line (he stands to fire over it: out.stand).
func _fire(p: Vector3, t_eye: Vector3, dist: float, posture: int, out: Dictionary) -> int:
	var line := sim.combat.line
	var reach := minf(dist - 2.0, fire_check_m)
	if reach <= 1.0:
		return Fire.CLEAR
	var eye := p + Vector3.UP * Posture.EYE[posture].y
	var r := line.trace(eye, eye + (t_eye - eye).normalized() * reach, -1, false)
	if r.blocker == "range":
		return Fire.CLEAR
	if posture == Posture.CROUCH and float(r.distance) <= 4.0:
		var se := p + Vector3.UP * Posture.EYE[Posture.STAND].y
		if line.trace(se, se + (t_eye - se).normalized() * reach, -1, false).blocker == "range":
			out.stand = true
			return Fire.CLEAR
	return Fire.BLOCKED


## Foliage on the first metres towards the threat hides the soldier without protecting him: LIGHT, "concealed".
func _concealment(out: Dictionary, p: Vector3, dir: Vector3) -> Dictionary:
	var eye := p + Vector3.UP * Posture.EYE[Posture.CROUCH].y
	if sim.combat.line.foliage_layers(eye - dir * 3.5, eye + dir * conceal_m, conceal_layers) >= conceal_layers:
		out.level = Level.LIGHT
		out.concealed = true
	return out


# --- Spots along solids -------------------------------------------------------------------------------------------------

## The spots beside one box solid (a wall, a building, a log, a sandbag module) for a threat in direction tdir (flat, unit):
## along every face turned away from the threat, `gap` behind it, every `spacing` metres (several soldiers along one wall);
## a diagonal threat gives two faces (the lee corner). Tall solids (over a crouched eye) also give the corner positions: just past
## each end of the lee face (a soldier fires past the corner, his body behind it) and along the side faces near their lee end.
## centre: the box's base centre; basis: its rotation (y up); hx / hz: half sizes along its x / z; h: its height.
static func box_spots(centre: Vector3, basis: Basis, hx: float, hz: float, h: float, tdir: Vector3, gap: float, spacing := 1.3) -> Array:
	var out: Array = []
	if h < 0.45 or maxf(hx, hz) < 0.3:
		return out
	var lt := basis.inverse() * tdir
	var faces: Array = []  # [axis 0 = face across local z (runs along x) / 1 = across x, sign of the lee side]
	if absf(lt.z) >= 0.35:
		faces.append([0, -signf(lt.z)])
	if absf(lt.x) >= 0.35:
		faces.append([1, -signf(lt.x)])
	for f: Array in faces:
		var along_h := hx if f[0] == 0 else hz
		var across_h := hz if f[0] == 0 else hx
		var side: float = f[1]
		var span := maxf(along_h * 2.0 - 0.6, 0.0)
		var n := maxi(1, floori(span / spacing) + 1)
		for k in n:
			var s := -along_h + 0.3 + span * (0.5 if n == 1 else float(k) / (n - 1))
			out.append(centre + basis * _local(f[0], s, side * (across_h + gap)))
		if h >= 1.25 and along_h >= 0.9:
			for e: float in [-1.0, 1.0]:
				out.append(centre + basis * _local(f[0], e * (along_h + 0.45), side * (across_h + gap * 0.7)))
				if across_h >= 1.2:
					out.append(centre + basis * _local(f[0], e * (along_h + gap), side * maxf(across_h - 0.8, 0.0)))
	return out


static func _local(axis: int, along: float, across: float) -> Vector3:
	return Vector3(along, 0.0, across) if axis == 0 else Vector3(across, 0.0, along)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
