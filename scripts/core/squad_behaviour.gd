## QOL-01 squad behaviour modes: how cautiously a squad operates - SAFE, AWARE, COMBAT, STEALTH (after Arma 3's AI
## behaviour, adapted). The player chooses one per squad (SquadState.behaviour, saved); the systems that already decide
## how a squad moves and fights read it through this table:
##   * route choice: StrategicRoutes profile grids (road / open ground / forest cost) and the believed-threat penalty
##     (SquadControl._submit_wait), with a detour limit against the ordinary route;
##   * posture: CombatBrain._choose_posture (SAFE stays up unless shot at, COMBAT lower near a known threat, STEALTH
##     crouch-walks and lies low near one - never a crawl across the map);
##   * cover reactions on the move (CombatBrain._start_search radius / time), fire discipline (STEALTH holds fire at range
##     until compromised), weapon readiness (SoldierBody relaxed / ready idle), formation spacing (SquadControl._gap);
##   * when a player squad's move is interrupted by contact and how soon it resumes (SquadTactics._interrupt / _resume).
## The selected mode is the player's preference and is never overwritten by a reaction; what the squad is doing right now
## because of the situation is `effective` (a SAFE squad under fire fights like a COMBAT one, a STEALTH squad that has
## been fired on or has fired is compromised and acts as COMBAT), derived from the squad's assessment each tactics step.
## AWARE is the default and is the behaviour every squad had before QOL-01 (AI squads keep it).
class_name SquadBehaviour
extends RefCounted

const SAFE := 0
const AWARE := 1
const COMBAT := 2
const STEALTH := 3
const NAMES: Array[String] = ["Safe", "Aware", "Combat", "Stealth"]
const ICONS: Array[StringName] = [&"beh_safe", &"beh_aware", &"beh_combat", &"beh_stealth"]
const HINTS: Array[String] = [
	"SAFE\nEfficient travel where no fight is expected: roads and tracks, march column, weapons relaxed, upright. Still takes cover and returns fire when shot at (it then fights as COMBAT until it is quiet again).",
	"AWARE\nStandard movement through ground that may be hostile: weapons ready, practical routes that keep clear of known enemy, crouch or prone when it helps. Stops to fight when fired on, then carries on.",
	"COMBAT\nMovement through an active fight: wider spacing, routes through cover and away from known enemy, low posture near a threat, longer dashes to cover, bounds towards the destination when in contact. Moves quickly between cover - not slowly everywhere.",
	"STEALTH\nAvoid being seen: concealed routes through woods and away from known enemy, crouched near a reported enemy, does not open fire at range unless found. Runs across open ground it cannot avoid. Fired on, it fights as COMBAT.",
]

## Route profile of each mode (StrategicRoutes.PROFILES key).
const ROUTE: Array[String] = ["safe", "aware", "combat", "stealth"]
## Formation spacing multiplier (SquadControl._gap).
const SPACING: Array[float] = [1.0, 1.0, 1.4, 1.25]
## Cover reaction on the move: search radius and reaction time multipliers (CombatBrain._start_search "move").
const REACT_RADIUS: Array[float] = [0.8, 1.0, 1.6, 1.4]
const REACT_TIME: Array[float] = [0.8, 1.0, 1.6, 1.4]
## A believed threat this close (m) makes COMBAT / STEALTH squads go low (crouch) when they halt, STEALTH also while moving.
const LOW_M: Array[float] = [0.0, 0.0, 300.0, 250.0]
## STEALTH lies prone when holding within this distance of a believed threat (m).
const STEALTH_PRONE_M := 150.0
## STEALTH does not open fire at targets farther than this (m) while not compromised.
const STEALTH_FIRE_M := 50.0
## A STEALTH squad stays compromised this long after it was fired on or fired (s).
const COMPROMISED_S := 30.0
## Seconds without contact before an interrupted move resumes.
const RESUME_CALM_S: Array[float] = [10.0, 15.0, 20.0, 20.0]
## After a move has resumed, it is not interrupted again by fire for this long (s) - only being pinned interrupts.
const INTERRUPT_COOLDOWN_S := 40.0
## At most this many interruptions per order; then the squad presses on (reacting only individually).
const MAX_INTERRUPTS := 3


## What the squad does right now: its selected mode, raised by the situation (a = SquadTactics assessment, compromised: a
## STEALTH squad that was found). Never written back to the record.
static func effective(selected: int, a: Dictionary, compromised: bool) -> int:
	if a.is_empty():
		return selected
	match selected:
		SAFE:
			if int(a.get("under_fire", 0)) > 0:
				return COMBAT
			if bool(a.get("in_contact", false)):
				return AWARE
		STEALTH:
			if compromised:
				return COMBAT
	return selected


## Whether a moving squad (of the player) stops its move to fight, by mode: SAFE only when hard pressed, AWARE when fired on
## by more than one soldier's worth, COMBAT on any contact it can see or that fires at it, STEALTH only once fired on.
static func interrupts(selected: int, a: Dictionary) -> bool:
	var n := maxi(int(a.get("n", 0)), 1)
	var under_fire := int(a.get("under_fire", 0))
	var pinned := int(a.get("pinned", 0))
	match selected:
		SAFE:
			return under_fire * 2 >= n or pinned * 2 >= n
		AWARE:
			return under_fire >= 2 or pinned >= 1 or int(a.get("engaged", 0)) >= 2
		COMBAT:
			return under_fire > 0 or int(a.get("seen_n", 0)) > 0 or int(a.get("engaged", 0)) > 0
		STEALTH:
			return under_fire > 0
	return false


static func name_of(b: int) -> String:
	return NAMES[clampi(b, 0, NAMES.size() - 1)]
