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

@export_group("Presentation")
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
