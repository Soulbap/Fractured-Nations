## `--road-audit`: audits the road network of the loaded world and quits (AI-WAR-LOGISTICS-01).
##
##   Godot.exe --path . --resolution 1600x900 --log-file ra.log res://scenes/game/world_ref_20km.tscn -- --road-audit
##
## Prints "ROAD <section> <json>" lines and writes res://benchmarks/raw/road_audit.json. Works on any world the game can load:
## nothing in it names a place; locations come from the war's objectives, the bases and the world's sites.json.
class_name RoadAuditRunner
extends RefCounted

var demo: CoreDemo
var tree: SceneTree


func _init(p_demo: CoreDemo) -> void:
	demo = p_demo
	tree = demo.get_tree()


func run(_args: PackedStringArray) -> void:
	for i in 90:
		await tree.physics_frame
	var audit := RoadAudit.new(demo.sim)
	var src := "res://worlds/%s/source/" % demo.config.world_name
	var rep: Dictionary = await audit.run(src, ["objective:hq", "objective:town", "objective:village", "objective:bridge", "base", "dock", "settlement"], func() -> void: await tree.process_frame)
	for line in audit.describe(rep):
		print("ROAD ", line)
	for k in ["component_list", "isolated_roads", "near_misses", "crossings_without_junction", "steep_segments", "tight_turns", "locations_without_road_entry", "route_failures", "sample_long_routes"]:
		print("ROAD %s %s" % [k, JSON.stringify(rep.get(k, []))])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://benchmarks/raw"))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://benchmarks/raw/road_audit.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	# Why the first failure to each distinct destination fails.
	var locs := audit.locations(src)
	var by_name := {}
	for l: Dictionary in locs:
		by_name[l.name] = l
	var shown := {}
	for fl in rep.get("route_failures", []):
		if shown.has(fl.to) or shown.size() >= 6:
			continue
		shown[fl.to] = true
		if by_name.has(fl["from"]) and by_name.has(fl.to):
			print("ROAD diagnose %s -> %s %s" % [fl["from"], fl.to, JSON.stringify(audit.diagnose_route(by_name[fl["from"]].pos, by_name[fl.to].pos))])
	var why_shown := {}
	for fl in rep.get("route_failures", []):
		if not why_shown.has(fl.to) and why_shown.size() < 5:
			why_shown[fl.to] = true
			print("ROAD why %s -> %s: %s" % [fl["from"], fl.to, JSON.stringify(fl.why)])
	for pr in rep.get("location_probes", []):
		if not pr.get("enter_ok", true) and pr.intentional == "":
			var l: Dictionary = by_name.get(pr.name, {})
			if not l.is_empty():
				var near := audit.router.nearest_nodes(l.pos, 1, 2500.0)
				if not near.is_empty():
					print("ROAD leg %s -> road %s: %s" % [pr.name, near[0].road.name, JSON.stringify(audit.leg_diagnosis(l.pos, near[0].pos))])
	for pr in rep.get("location_probes", []):
		if float(pr.get("main_network_m", 0.0)) > 100.0 and pr.kind == "settlement":
			var l2: Dictionary = by_name.get(pr.name, {})
			var main_only := func(id: int, _pos: Vector3) -> bool:
				return audit.router._comp_of.get(id, -1) == audit.router._main_comp
			var mn := audit.router.nearest_nodes(l2.pos, 1, 3000.0, main_only)
			if not mn.is_empty():
				print("ROAD main-leg %s -> (%.0f, %.0f) on %s: %s" % [pr.name, mn[0].pos.x, mn[0].pos.z, mn[0].road.name, JSON.stringify(audit.leg_diagnosis(l2.pos, mn[0].pos))])
	print("ROAD DONE")
	demo.shutdown_cleanup()
	tree.quit()
