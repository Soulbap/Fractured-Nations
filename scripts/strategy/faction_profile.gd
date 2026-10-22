## Strategic personality of an AI faction (WORLD-SANDBOX-01). The same decision code
## reads different numbers: an aggressive profile attacks sooner, farther and with less
## superiority, keeps fewer soldiers home and recovers faster after a defeat; a defensive
## profile keeps strong garrisons, reinforces threatened points early and only attacks
## nearby objectives with clear superiority.
class_name FactionProfile
extends Resource

@export var display_name := "Balanced"
## Seconds between strategic decisions.
@export var decision_s := 30.0
## Simultaneous ATTACK operations at most.
@export var max_attacks := 2
## Squads kept at the HQ / at every other owned objective of value >= garrison_min_value.
@export var hq_squads := 1
@export var garrison_squads := 1
@export var garrison_min_value := 2
## Attacking needs this many own soldiers per expected defender (unknown defenders are
## estimated from the objective's value).
@export var attack_ratio := 1.5
## Smallest attack force (soldiers).
@export var min_attack_soldiers := 12
## Targets farther than this from the attacking squads are not considered (m).
@export var max_attack_distance := 9000.0
## No new attack this long after a failed one (s).
@export var recovery_s := 180.0
## Target scoring: value, distance (per km), bonus for neutral / enemy-held, bonus for
## retaking a lost objective.
@export var w_value := 3.0
@export var w_distance := 1.0
@export var w_neutral := 1.5
@export var w_enemy := 1.0
@export var w_retake := 2.0
## Owned objectives with known enemies this close are threatened (m); reinforcements are
## sent when the defenders there are fewer than threat_ratio x the known attackers.
@export var threat_radius := 700.0
@export var threat_ratio := 1.0
## Squads with fewer living soldiers than this go home to recover.
@export var min_squad_size := 3
## WORLD-SANDBOX-01B: an attack takes at least this share of the free soldiers (not just
## the minimum it needs), so reserves that pile up are used instead of idling.
@export var attack_commit := 0.5
## WORLD-SANDBOX-01B: free squads idling at the HQ move up to the held objective nearest
## the enemy (at most this many there), so attacks start from the front instead of a
## march of 6-8 km from the HQ. 0 = never.
@export var forward_squads := 2
## AI-COMBAT-STRAT-01: share of the faction's soldiers kept out of new offensives (reserve), weight of
## defence against attack in the utility scoring, how long a strategic focus lasts (s) and its bonus,
## how much a believed threat on the way counts against an attack, and the operation effectiveness below
## which an attack breaks off.
@export var reserve_ratio := 0.15
@export var defend_weight := 1.0
@export var focus_commit_s := 150.0
@export var focus_bonus := 1.5
@export var route_risk_weight := 1.2
@export var withdraw_eff := 0.32

# --- AI-WAR-LOGISTICS-01: economy, force generation and logistics (numbers only, see WarEconomy / WarLogistics) ---
## The starting stockpile of the faction's first supply depot is the shared FacilityDefs.START_STOCK times this.
@export var start_stock_mult := 1.0
## Trucks standing at the vehicle depot when the war begins (further vehicles are bought from the depot's stock).
@export var start_trucks := 1
## Explicit income, per owned objective value and minute, delivered to the faction's main base (kg / l / personnel).
@export var income_supplies := 18.0
@export var income_ammo := 10.0
@export var income_fuel := 12.0
@export var income_manpower := 0.25
## The economy buys transport when it has fewer than these (a truck carries 12, an APC 8) and keeps the
## stocks below as a floor for new purchases; recruiting stops at max_squads_econ squads.
@export var want_trucks := 2
@export var want_apcs := 1
@export var max_squads_econ := 11
@export var keep_ammo_kg := 600.0
@export var keep_fuel_l := 800.0
## A distant march (m) is done by vehicle when transport is free; shorter ones walk.
@export var mech_min_m := 1500.0
## Ammunition share (of a full load) below which a squad goes to a depot instead of an operation.
@export var resupply_below := 0.55
## Counterattack: share of a weakened attacker the local reserve must out-number, and the longest distance (m).
@export var counter_ratio := 1.4
@export var counter_range_m := 450.0
