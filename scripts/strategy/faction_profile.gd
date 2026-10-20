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
