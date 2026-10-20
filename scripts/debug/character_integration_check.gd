## CHARACTER-01 integration probe, shared by the WORLD-CORE self tests.
##
## Checks that every soldier body wears the modular infantry character for the loadout
## persisted in its UnitState, with every piece of that loadout attached (rigid pieces on
## their attachment bones, skinned pieces on the body's skeleton), that the animation
## state follows the body's velocity, and that bodiless soldiers show the single-surface
## proxy mesh. Returns {"data": {...}, "failures": [...]}.
class_name CharacterIntegrationCheck
extends RefCounted


static func run(sim: WorldSim) -> Dictionary:
	var failures: Array[String] = []
	if not InfantryCharacter.enabled():
		return {"data": {"enabled": false}, "failures": failures}
	var bodies := 0
	var ok_bodies := 0
	var loadouts := {}
	var moving_checked := 0
	var moving_ok := 0
	var missing := []
	for id in sim.bodies:
		var b: Node3D = sim.bodies[id]
		if not (b is SoldierBody):
			continue
		bodies += 1
		var sb := b as SoldierBody
		var c := sb.character
		if c == null or sb.unit.loadout == "" or c.loadout == null or c.loadout.id != sb.unit.loadout:
			missing.append(id)
			continue
		loadouts[c.loadout.id] = loadouts.get(c.loadout.id, 0) + 1
		var all_attached := true
		for it in c.loadout.items:
			var nodes: Array = c.pieces.get(it.id, [])
			if nodes.is_empty():
				all_attached = false
				continue
			var n: Node = nodes[0]
			if it.mode == InfantryEquipment.Mode.RIGID and not it.attach.contains(":"):
				all_attached = all_attached and n.get_parent() is BoneAttachment3D
			elif it.mode == InfantryEquipment.Mode.SKINNED:
				all_attached = all_attached and n.get_parent() == c.skeleton
		if all_attached:
			ok_bodies += 1
		else:
			missing.append(id)
		var v := Vector2(sb.velocity.x, sb.velocity.z).length()
		if v > 1.5:
			moving_checked += 1
			if c.anim_state().move_amount > 0.5:
				moving_ok += 1
	var proxies := 0
	var proxy_ok := 0
	for id in sim.proxies:
		var p: UnitProxy = sim.proxies[id]
		if p.unit.is_vehicle():
			continue
		proxies += 1
		var mi := p.get_child(0) as MeshInstance3D
		if mi and mi.mesh is ArrayMesh and mi.mesh.get_surface_count() == 1 and p.unit.loadout != "":
			proxy_ok += 1
	var data := {"soldier_bodies": bodies, "bodies_with_full_loadout": ok_bodies, "loadouts": loadouts,
		"moving_bodies_checked": moving_checked, "moving_bodies_animating": moving_ok,
		"soldier_proxies": proxies, "proxies_with_loadout_mesh": proxy_ok, "bad_ids": missing}
	if ok_bodies != bodies:
		failures.append("character01: %d of %d soldier bodies lack their loadout pieces %s" % [bodies - ok_bodies, bodies, str(missing)])
	if moving_ok != moving_checked:
		failures.append("character01: %d moving bodies not animating" % (moving_checked - moving_ok))
	if proxy_ok != proxies:
		failures.append("character01: %d soldier proxies without the loadout mesh" % (proxies - proxy_ok))
	return {"data": data, "failures": failures}
