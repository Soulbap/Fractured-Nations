## GAMEPLAY-04E opportunities: things worth doing that the world offers the player after the introduction (owned by WarSim:
## `WarSim.opps`; records in WarState.opportunities, saved). Filled in by GAMEPLAY-04E.
class_name Opportunities
extends RefCounted

var ws: WarSim


func _init(p_ws: WarSim) -> void:
	ws = p_ws


## Opportunities the player has accepted (shown by the objective tracker).
func accepted() -> Array:
	return []


func update(_dt: float) -> void:
	pass
