## Static description of a weapon (COMBAT-01a). Shared, read-only data: every soldier's
## magazine, reserve, fire mode, cooldown and reload progress live in its UnitState,
## never here (COMBAT-TECH-01: a shared Resource would share one magazine).
##
## Field set follows Jeh3no's WeaponResource (fire interval, magazine, reload, spread,
## damage drop-off, head multiplier), minus its runtime fields.
class_name WeaponDef
extends Resource

enum FireMode { SEMI, AUTO }
## How a shot travels. Only HITSCAN exists; PROJECTILE is the extension point for later
## ballistics (bullet drop, travel time), resolved by the same CombatSim.
enum Delivery { HITSCAN, PROJECTILE }

@export var id: StringName = &"rifle"
@export var display_name := "Rifle"
@export var delivery := Delivery.HITSCAN

@export_group("Fire")
@export var rounds_per_minute := 700.0
@export var allow_auto := true
@export var default_mode := FireMode.AUTO
@export var magazine_size := 30
## Rounds carried besides the magazine at spawn.
@export var reserve_start := 120
@export var reload_time := 2.4

@export_group("Damage")
## Damage of a body hit at short range (health is 100).
@export var damage := 34.0
## GAMEPLAY-01F: damage to structures per hit = damage x structure_mult x StructureHealth.resist (small arms barely scratch
## fortifications; heavier weapons will raise this).
@export var structure_mult := 1.0
@export var head_multiplier := 2.5
@export var body_multiplier := 1.0
## Full damage up to falloff_start, then linear down to min_damage_fraction at falloff_end.
@export var falloff_start := 120.0
@export var falloff_end := 400.0
@export var min_damage_fraction := 0.6
## Longest distance a shot is resolved (m).
@export var max_range := 600.0
## Distance the rifle is meant to be used at (HUD / later AI), not a hard limit.
@export var effective_range := 300.0

@export_group("Accuracy")
## Cone half-angle (degrees) of a single aimed shot from standing still.
@export var spread_base_deg := 0.06
## Added while the shooter moves at walking speed (scaled by speed).
@export var spread_moving_deg := 1.2
## Added per shot in a burst, up to spread_bloom_max_deg; recovers at spread_recovery_deg_s.
@export var spread_bloom_deg := 0.22
@export var spread_bloom_max_deg := 1.8
@export var spread_recovery_deg_s := 4.0

@export_group("Role (GAMEPLAY-02B)")
## What the weapon is for: &"rifle", &"lmg" (sustained fire, suppression; fortification slots marked "mg" prefer it).
## Squad tactics, the HUD and the AI read it; the firing rules are the same for every weapon.
@export var role: StringName = &"rifle"
## Suppression of one near miss relative to a rifle round (CombatBrain.suppression_per_shot), and how close a round must
## pass to count as a near miss (m). Damage is never scaled for suppression.
@export var suppression_mult := 1.0
@export var near_miss_m := 3.0
## Braced fire: after the shooter has stood still for settle_s the spread (and the AI's aim error) is multiplied by
## settled_mult (bipod, prone); 0 = no such effect. moving_aim_mult scales the AI aim error while walking.
@export var settle_s := 0.0
@export var settled_mult := 1.0
@export var moving_aim_mult := 1.0
## AI fire: burst length multiplier against targets it sees, and rounds per burst of a fire mission.
@export var burst_mult := 1.0
@export var mission_burst := 3

@export_group("Handling (GAMEPLAY-04C)")
## Seconds a shooter needs on a new target, standing, to settle the aim (the weapon's handling: a carbine comes up fast, a
## marksman rifle or a heavy machine gun slowly). The AI's aim error starts at CombatBrain.aim_first_mult times its settled
## value and falls to it over this time (soldier proficiency scales it); moving restarts it. 0 = the brain's default.
@export var aim_time_s := 0.0
## How well the AI can aim the weapon: its sight / optic and how it points (the aim error of CombatBrain is multiplied by it;
## the weapon's own spread is separate). A magnified marksman optic 0.4, a short carbine 1.15, the standard rifle 1.0.
@export var aim_mult := 1.0
## The AI engages targets out to this distance (m) with this weapon; 0 = CombatBrain.engage_range.
@export var ai_engage_m := 0.0
## A magnified optic: the soldier notices targets out to this distance (m) instead of CombatBrain.sight_range; 0 = none.
@export var optic_sight_m := 0.0
## Walking speed with the weapon as a share of the normal one (a heavy machine gun and its belt slow the gunner).
@export var move_speed_mult := 1.0

@export_group("Procurement (GAMEPLAY-04D)")
## Price of one weapon when the faction's armoury holds none (supplies kg), the ammunition a soldier is issued with it (kg),
## and the facility (FacilityDefs kind) that must be operational at the base where it is issued (&"" = any base).
@export var procure_cost := 0.0
@export var procure_ammo := 0.0
@export var procure_facility: StringName = &""

@export_group("Explosive (GAMEPLAY-02C)")
## A weapon that bursts (hand grenade, rocket): no hitscan damage of its own; CombatSim.detonate applies blast_damage to
## soldiers (falling off to nothing at blast_radius, mostly stopped by cover between them and the burst) and
## blast_structure x StructureHealth.blast_resist to the structures within blast_radius; soldiers within twice the radius
## are suppressed by blast_suppression.
@export var blast_radius := 0.0
@export var blast_damage := 0.0
@export var blast_structure := 0.0
@export var blast_suppression := 0.0
## Thrown (a hand grenade): lands where it was aimed (scatter grows with the distance), bursts fuse_s after the throw;
## max_range is the longest throw. Not thrown (a rocket): flies straight to the first thing in its way at
## projectile_speed and bursts there.
@export var thrown := false
@export var fuse_s := 0.0
@export var projectile_speed := 0.0

@export_group("Presentation")
## GAMEPLAY-02C: what first person holds for a weapon that is not a loadout piece in the hand (the launcher carried on the
## back is held in weapon space); null = the loadout's weapon pieces.
@export var viewmodel_scene: PackedScene
## Camera kick per shot in first person (degrees up, random sideways).
@export var recoil_pitch_deg := 0.55
@export var recoil_yaw_deg := 0.25


func fire_interval() -> float:
	return 60.0 / maxf(rounds_per_minute, 1.0)


## Damage multiplier for the distance a shot travelled.
func falloff(distance: float) -> float:
	if distance <= falloff_start:
		return 1.0
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 0.01), 0.0, 1.0)
	return lerpf(1.0, min_damage_fraction, t)


func zone_multiplier(zone: int) -> float:
	return head_multiplier if zone == CombatSim.Zone.HEAD else body_multiplier
